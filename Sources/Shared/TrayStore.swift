import Foundation
import UniformTypeIdentifiers

/// Reads and writes the tray contents.
///
/// Items are stored as copies: drag payloads are short-lived and Photos items
/// carry no durable path, so keeping a reference would leave dangling entries.
///
/// The app and the share extension can both write, so the whole
/// read-modify-write of items.json runs inside a single coordinated write.
/// Serializing only the byte-level accesses would still lose updates, because
/// the transaction lives in the gap between them.
///
/// The `Sendable` conformance covers this type's (immutable, empty) memory
/// state only. File-level safety comes from NSFileCoordinator, not from it.
final class TrayStore: Sendable {
    static let shared = TrayStore(root: TrayContainer.root)

    private let root: URL
    private let itemsDirectory: URL
    private let thumbsDirectory: URL
    private let metadataURL: URL

    init(root: URL) {
        self.root = root
        self.itemsDirectory = root.appendingPathComponent("Items", isDirectory: true)
        self.thumbsDirectory = root.appendingPathComponent("Thumbs", isDirectory: true)
        self.metadataURL = root.appendingPathComponent("items.json")
    }

    func prepare() throws {
        for dir in [root, itemsDirectory, thumbsDirectory] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Reading

    /// Newest first. This is the only entry point that *asks* for recovery:
    /// metadata that is not tray metadata at all sends it to rebuildFromDisk(),
    /// which re-checks that under its own claim before destroying anything --
    /// this read claim is released in between, so the answer here is a hint.
    /// A metadata file that cannot be read throws: an unreadable tray is not an
    /// empty tray, and callers must not persist anything derived from it.
    /// Metadata in an unrecognised schema throws too -- that is data from a
    /// newer build, not damage, and rebuilding over it would destroy it.
    func load() throws -> [TrayItem] {
        try prepare()
        guard let data = try coordinatedRead(), !data.isEmpty else { return [] }
        do {
            return presentable(try Self.decodeItems(from: data))
        } catch TrayStoreError.unreadableMetadata {
            return try rebuildFromDisk()
        }
    }

    /// Recovers the list from the files actually present in Items/ -- but only
    /// if the metadata is still unreadable when this claim is held.
    ///
    /// The precondition is re-checked inside the write claim rather than
    /// trusted from the caller, because the caller's read claim was released
    /// before this one was taken: by now another process may have repaired the
    /// file, or written a schema this build must not touch. Deciding under one
    /// claim and destroying under another is the read-modify-write split the
    /// mutation path was fixed for, and recovery holds the same invariants.
    ///
    /// Metadata that the files cannot carry (the original display name) is
    /// replaced by a placeholder; everything derivable from the filename is
    /// recovered. Throws if the directory cannot be listed, so a failed
    /// recovery is never persisted as an empty tray.
    @discardableResult
    func rebuildFromDisk() throws -> [TrayItem] {
        try mutate(recovering: true) { _ in }
    }

    // MARK: - Writing

    @discardableResult
    func add(data: Data, suggestedName: String?, uti: String?) throws -> TrayItem {
        try prepare()
        let item = makeItem(suggestedName: suggestedName, uti: uti, size: data.count)
        let destination = item.fileURL(in: itemsDirectory)
        try data.write(to: destination, options: .atomic)
        try commit(item, payload: destination)
        return item
    }

    @discardableResult
    func add(copyingFrom source: URL, suggestedName: String?, uti: String?) throws -> TrayItem {
        try prepare()
        let name = suggestedName ?? source.lastPathComponent
        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let item = makeItem(suggestedName: name, uti: uti, size: size)
        let destination = item.fileURL(in: itemsDirectory)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        try commit(item, payload: destination)
        return item
    }

    /// See `sweep` for the contract. Not `@discardableResult`: a caller that
    /// wants to ignore what happened to the user's files has to write it down.
    func remove(id: UUID) throws -> TrayRemovalResult {
        try sweep { $0.id == id }
    }

    func removeAll() throws -> TrayRemovalResult {
        try sweep { _ in true }
    }

    /// Unlinks every matching payload, then persists metadata describing what
    /// actually happened on disk.
    ///
    /// Unlink comes first because load() already filters an entry whose file is
    /// missing, while a file whose entry is missing gets resurrected by
    /// rebuildFromDisk(). An unlink cannot be rolled back, so the outcome is
    /// reported as what it is rather than as one bit:
    ///
    /// - **Returns** a result: every match was unlinked and metadata saying so
    ///   was written. `failed` is empty -- that is the whole meaning of a
    ///   return.
    /// - **Throws `.incompleteRemoval(result, reason:)`**: some payloads went
    ///   and some did not, or they all went and the metadata write failed.
    ///   `result.removed` is gone for good, `result.failed` is still there,
    ///   and load() agrees with disk either way.
    /// - **Throws anything else**: nothing was unlinked and nothing was
    ///   written. Only this shape means "nothing happened".
    ///
    /// So a throw on its own never says whether files were destroyed; the case
    /// does, and every case that destroyed anything carries the list.
    private func sweep(_ matches: (TrayItem) -> Bool) throws -> TrayRemovalResult {
        var removed: [UUID] = []
        var failed: [UUID] = []
        var firstFailure: Error?
        do {
            try mutate { items in
                for item in items where matches(item) {
                    do {
                        try self.deleteFiles(for: item)
                        removed.append(item.id)
                    } catch {
                        failed.append(item.id)
                        if firstFailure == nil { firstFailure = error }
                    }
                }
                // Nothing went, so there is nothing to record: leave metadata
                // alone and let the failure carry the list out below.
                if removed.isEmpty, let firstFailure { throw firstFailure }
                let gone = Set(removed)
                items.removeAll { gone.contains($0.id) }
            }
        } catch {
            // The read or the metadata write failed, or every unlink did. If
            // no payload was even attempted, nothing was destroyed and the
            // plain error is honest. Otherwise the caller needs the lists.
            if removed.isEmpty, failed.isEmpty { throw error }
            throw TrayStoreError.incompleteRemoval(
                TrayRemovalResult(removed: removed, failed: failed),
                reason: String(describing: error)
            )
        }
        // Metadata landed, but some payload survived its unlink: still not the
        // "it worked" shape, and the survivors keep their entries.
        if let firstFailure {
            throw TrayStoreError.incompleteRemoval(
                TrayRemovalResult(removed: removed, failed: failed),
                reason: String(describing: firstFailure)
            )
        }
        return TrayRemovalResult(removed: removed, failed: failed)
    }

    // MARK: - Internals

    private func makeItem(suggestedName: String?, uti: String?, size: Int) -> TrayItem {
        let fallbackExtension = uti.flatMap { UTType($0)?.preferredFilenameExtension }
        let clean = FilenameSanitizer.sanitize(suggestedName, fallbackExtension: fallbackExtension)
        return TrayItem(
            id: UUID(),
            name: clean.name,
            uti: uti ?? utiIdentifier(forExtension: clean.ext),
            size: size,
            addedAt: Date(),
            ext: clean.ext
        )
    }

    /// The payload is already on disk. If the metadata write fails, unlink it:
    /// an add that throws must leave nothing behind for a later rebuild to
    /// resurrect as an item the caller was told had failed.
    private func commit(_ item: TrayItem, payload: URL) throws {
        do {
            // The insert is authoritative for this id. A recovery that ran
            // between the payload landing and this claim being granted will
            // have listed that file and inserted a placeholder for it; the
            // caller's real name and timestamp replace it rather than
            // competing with it for the dedupe.
            try mutate { items in
                items.removeAll { $0.id == item.id }
                items.insert(item, at: 0)
            }
        } catch {
            try? FileManager.default.removeItem(at: payload)
            throw error
        }
    }

    /// Reads, mutates and writes items.json inside one coordinated write.
    /// Returns the list that was written.
    ///
    /// `recovering` is the only way to get past an unreadable baseline, and it
    /// still reads that baseline first: the check that the bytes are garbage
    /// and the act of replacing them happen under the same claim. A baseline
    /// that decodes is kept, whoever wrote it; a version this build does not
    /// know propagates out unwritten.
    @discardableResult
    private func mutate(
        recovering: Bool = false,
        _ body: (inout [TrayItem]) throws -> Void
    ) throws -> [TrayItem] {
        try prepare()
        var written: [TrayItem] = []
        var bodyError: Error?
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(
            writingItemAt: metadataURL, options: .forMerging, error: &coordinatorError
        ) { url in
            do {
                var items: [TrayItem]
                do {
                    items = try self.currentItems(at: url)
                } catch TrayStoreError.unreadableMetadata where recovering {
                    items = try self.itemsOnDisk()
                }
                try body(&items)
                items = self.presentable(items)
                // Atomic so a crash mid-write cannot leave truncated JSON. There
                // are no file presenters here that would need an in-place write.
                try JSONEncoder.tray.encode(TrayMetadata(items: items)).write(to: url, options: .atomic)
                written = items
            } catch {
                bodyError = error
            }
        }
        if let bodyError { throw bodyError }
        if let coordinatorError { throw coordinatorError }
        return written
    }

    /// The baseline for a mutation, read from inside the coordinated accessor.
    /// Never substitutes an empty list for a read it could not perform, and
    /// never recovers: a mutation that rebuilt from disk here would pick up the
    /// payload its own caller had just written and insert that id twice.
    /// Recovery is the caller's explicit choice, and mutate() acts on it only
    /// after this read has confirmed the damage under the same claim.
    private func currentItems(at url: URL) throws -> [TrayItem] {
        guard let data = try readIfPresent(at: url), !data.isEmpty else { return [] }
        return try Self.decodeItems(from: data)
    }

    /// Decodes items.json, tolerating the unversioned layout earlier builds
    /// wrote (a bare array, whose dates are ISO8601 strings).
    ///
    /// The two failure modes are kept apart on purpose: `unreadableMetadata`
    /// means the bytes are not tray metadata and the destructive
    /// rebuild-and-persist is the right answer, while
    /// `unsupportedSchemaVersion` means a newer build owns this file and
    /// rebuilding would throw its contents away.
    ///
    /// `currentVersion` is a parameter, not a constant read in place, so a test
    /// can exercise the guard a future build will have without a build flag:
    /// the bump is where this used to break.
    static func decodeItems(
        from data: Data,
        currentVersion: Int = TrayMetadata.currentVersion
    ) throws -> [TrayItem] {
        if let probe = try? JSONDecoder().decode(SchemaProbe.self, from: data) {
            // Only a *newer* schema is refused. An older one is this app's own
            // data from a previous release: refusing it would take every
            // existing tray out on the first routine version bump.
            guard probe.version <= currentVersion else {
                throw TrayStoreError.unsupportedSchemaVersion(probe.version)
            }
            return try migrated(data, from: probe.version)
        }
        guard let legacy = try? JSONDecoder.tray.decode([TrayItem].self, from: data) else {
            throw TrayStoreError.unreadableMetadata
        }
        return legacy
    }

    /// One arm per schema this build can read, newest last. Bumping
    /// `TrayMetadata.currentVersion` without adding an arm here refuses the
    /// old data rather than destroying it, and the version-bump test fails
    /// before anyone ships it.
    private static func migrated(_ data: Data, from version: Int) throws -> [TrayItem] {
        switch version {
        case 1:
            guard let metadata = try? JSONDecoder.tray.decode(TrayMetadata.self, from: data) else {
                throw TrayStoreError.unreadableMetadata
            }
            return metadata.items
        default:
            // A version number this build has no reader for. Not damage, so
            // never rebuilt over.
            throw TrayStoreError.unsupportedSchemaVersion(version)
        }
    }

    /// Reads the version without committing to the rest of the layout, so a
    /// schema whose items this build cannot decode is still recognised as a
    /// version rather than as garbage.
    private struct SchemaProbe: Decodable {
        let version: Int
    }

    /// nil only when the file genuinely does not exist. Every other failure
    /// throws, so "I could not read it" can never be mistaken for "it is empty".
    private func readIfPresent(at url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return nil
        }
    }

    private func coordinatedRead() throws -> Data? {
        var result: Data?
        var readError: Error?
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(
            readingItemAt: metadataURL, options: [], error: &coordinatorError
        ) { url in
            do { result = try self.readIfPresent(at: url) } catch { readError = error }
        }
        if let readError { throw readError }
        if let coordinatorError { throw coordinatorError }
        return result
    }

    /// Metadata reconstructed from the payload files themselves.
    private func itemsOnDisk() throws -> [TrayItem] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: itemsDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]
        )
        return urls.compactMap { url in
            let stem = url.deletingPathExtension().lastPathComponent
            guard let id = UUID(uuidString: stem) else { return nil }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
            let ext = url.pathExtension.lowercased()
            return TrayItem(
                id: id,
                name: Self.recoveredName(id: id, ext: ext),
                uti: utiIdentifier(forExtension: ext),
                size: values?.fileSize ?? 0,
                addedAt: values?.creationDate ?? Date(),
                ext: ext
            )
        }
    }

    /// The original display name is gone with the metadata, and the UUID is a
    /// path detail, never a name. Keep what the file still carries — its
    /// extension — and label the rest honestly.
    private static func recoveredName(id: UUID, ext: String) -> String {
        let stem = "Recovered-\(id.uuidString.prefix(8))"
        return ext.isEmpty ? stem : "\(stem).\(ext)"
    }

    private func deleteFiles(for item: TrayItem) throws {
        try deleteIfPresent(item.fileURL(in: itemsDirectory))
        // A stale thumbnail is cosmetic: rebuildFromDisk reads Items/ only, so
        // it can never bring a removed item back.
        try? deleteIfPresent(item.thumbnailURL(in: thumbsDirectory))
    }

    private func deleteIfPresent(_ url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            // Already gone.
        }
    }

    /// Newest first, with the id as a tiebreaker so the order is total even when
    /// two items share a timestamp. Entries whose payload is gone are dropped,
    /// and an id survives at most once: TrayItem is Identifiable and this list
    /// feeds a SwiftUI ForEach, where a repeated id is undefined behaviour --
    /// and where deleting one twin unlinks the payload both of them share.
    /// The dedupe is an invariant of everything this type hands out, not a
    /// patch on one path that could produce a duplicate.
    ///
    /// Twins are resolved by position, before the sort, so the entry nearest
    /// the head of the list wins -- which is the one commit() just inserted.
    /// Resolving them by timestamp instead always kept the wrong one: a
    /// recovered placeholder takes its addedAt from the payload's creation
    /// date, which is set after makeItem() stamps the real item, so the
    /// placeholder is always the later of the two.
    private func presentable(_ items: [TrayItem]) -> [TrayItem] {
        var seen = Set<UUID>()
        return items
            .filter { seen.insert($0.id).inserted }
            .filter { FileManager.default.fileExists(atPath: $0.fileURL(in: itemsDirectory).path) }
            .sorted {
                $0.addedAt == $1.addedAt ? $0.id.uuidString < $1.id.uuidString : $0.addedAt > $1.addedAt
            }
    }

    private func utiIdentifier(forExtension ext: String) -> String {
        guard !ext.isEmpty,
              let type = UTType(filenameExtension: ext) else { return "public.data" }
        return type.identifier
    }
}

/// What a destructive sweep actually did. `failed` items keep both their bytes
/// and their metadata entry, so the caller can report the partial result rather
/// than claiming a delete that half happened either succeeded or did not.
struct TrayRemovalResult: Sendable, Equatable {
    let removed: [UUID]
    let failed: [UUID]
}

enum TrayStoreError: Error, Equatable {
    /// Present, readable, and not tray metadata. Safe to rebuild over.
    case unreadableMetadata
    /// Tray metadata written by a build that knows a schema this one does not.
    /// Never rebuilt over: it is someone else's data, not damage.
    case unsupportedSchemaVersion(Int)
    /// A sweep that did not fully work: some payloads survived their unlink,
    /// or the metadata describing the ones that went could not be written.
    /// Always carries both lists, so the caller can say which of the user's
    /// files are gone and which are still there.
    case incompleteRemoval(TrayRemovalResult, reason: String)
}

/// The on-disk envelope. The version exists so that the next format change is a
/// migration rather than a silent reclassification of every user's metadata as
/// corrupt -- which is what an unversioned bare array made of the previous one.
struct TrayMetadata: Codable {
    static let currentVersion = 1

    var version: Int = Self.currentVersion
    var items: [TrayItem]
}

// Dates are persisted as a raw time interval rather than ISO8601, which has
// one-second resolution: truncating there makes an added item unequal to the
// same item read back, and leaves same-second items with no defined order.
extension JSONEncoder {
    static var tray: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate)
        }
        return encoder
    }
}

extension JSONDecoder {
    static var tray: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let interval = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: interval)
            }
            // Metadata from before the interval format. The second-resolution
            // truncation is already baked into those bytes; accepting it keeps
            // the display names, which a rebuild would destroy outright.
            let text = try container.decode(String.self)
            guard let date = ISO8601DateFormatter().date(from: text) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "unrecognised date encoding"
                )
            }
            return date
        }
        return decoder
    }
}
