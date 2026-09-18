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

    /// Newest first. This is the only entry point that recovers: metadata that
    /// is not tray metadata at all is rebuilt from disk here, explicitly.
    /// A metadata file that cannot be read throws: an unreadable tray is not an
    /// empty tray, and callers must not persist anything derived from it.
    /// Metadata in an unrecognised schema throws too -- that is data from a
    /// newer build, not damage, and rebuilding over it would destroy it.
    func load() throws -> [TrayItem] {
        try prepare()
        guard let data = try coordinatedRead(), !data.isEmpty else { return [] }
        do {
            return presentable(try decodeItems(from: data))
        } catch TrayStoreError.unreadableMetadata {
            return try rebuildFromDisk()
        }
    }

    /// Recovers the list from the files actually present in Items/.
    /// Metadata that the files cannot carry (the original display name) is
    /// replaced by a placeholder; everything derivable from the filename is
    /// recovered. Throws if the directory cannot be listed, so a failed
    /// recovery is never persisted as an empty tray.
    @discardableResult
    func rebuildFromDisk() throws -> [TrayItem] {
        try prepare()
        // The baseline is the thing being replaced, so it is not read back in:
        // reading it would fail (it is corrupt) and, worse, the payload of an
        // in-flight add would be picked up as a "recovered" item.
        return try mutate(ignoringCurrentItems: true) { $0 = try self.itemsOnDisk() }
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

    @discardableResult
    func remove(id: UUID) throws -> TrayRemovalResult {
        try sweep { $0.id == id }
    }

    @discardableResult
    func removeAll() throws -> TrayRemovalResult {
        try sweep { _ in true }
    }

    /// Unlinks every matching payload, then persists metadata describing what
    /// actually happened on disk.
    ///
    /// Unlink comes first because load() already filters an entry whose file is
    /// missing, while a file whose entry is missing gets resurrected by
    /// rebuildFromDisk(). But an unlink cannot be rolled back, so a mutation
    /// that threw after unlinking some payloads would report a total failure
    /// after a partial destruction. Instead the failures are collected, the
    /// entries of the items that did go are dropped, and the caller is told
    /// which ids went and which did not. Only a sweep that removed nothing at
    /// all throws -- then nothing happened and nothing is written.
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
                if removed.isEmpty, let firstFailure { throw firstFailure }
                let gone = Set(removed)
                items.removeAll { gone.contains($0.id) }
            }
        } catch {
            // The read or the metadata write failed. If that happened before
            // any unlink, nothing was destroyed and the plain error is honest.
            // If it happened after, the bytes are already gone and a bare
            // error would be the same lie the loop above avoids, so the
            // partial result goes out with it.
            if removed.isEmpty { throw error }
            throw TrayStoreError.partialRemoval(
                TrayRemovalResult(removed: removed, failed: failed),
                reason: String(describing: error)
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
            try mutate { $0.insert(item, at: 0) }
        } catch {
            try? FileManager.default.removeItem(at: payload)
            throw error
        }
    }

    /// Reads, mutates and writes items.json inside one coordinated write.
    /// Returns the list that was written.
    @discardableResult
    private func mutate(
        ignoringCurrentItems: Bool = false,
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
                var items: [TrayItem] = ignoringCurrentItems ? [] : try self.currentItems(at: url)
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
    /// Recovery is rebuildFromDisk()'s job, invoked explicitly by load().
    private func currentItems(at url: URL) throws -> [TrayItem] {
        guard let data = try readIfPresent(at: url), !data.isEmpty else { return [] }
        return try decodeItems(from: data)
    }

    /// Decodes items.json, tolerating the unversioned layout earlier builds
    /// wrote (a bare array, whose dates are ISO8601 strings).
    ///
    /// The two failure modes are kept apart on purpose: `unreadableMetadata`
    /// means the bytes are not tray metadata and the destructive
    /// rebuild-and-persist is the right answer, while
    /// `unsupportedSchemaVersion` means a newer build owns this file and
    /// rebuilding would throw its contents away.
    private func decodeItems(from data: Data) throws -> [TrayItem] {
        if let probe = try? JSONDecoder().decode(SchemaProbe.self, from: data) {
            guard probe.version == TrayMetadata.currentVersion else {
                throw TrayStoreError.unsupportedSchemaVersion(probe.version)
            }
            guard let metadata = try? JSONDecoder.tray.decode(TrayMetadata.self, from: data) else {
                throw TrayStoreError.unreadableMetadata
            }
            return metadata.items
        }
        guard let legacy = try? JSONDecoder.tray.decode([TrayItem].self, from: data) else {
            throw TrayStoreError.unreadableMetadata
        }
        return legacy
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
    private func presentable(_ items: [TrayItem]) -> [TrayItem] {
        var seen = Set<UUID>()
        return items
            .filter { FileManager.default.fileExists(atPath: $0.fileURL(in: itemsDirectory).path) }
            .sorted {
                $0.addedAt == $1.addedAt ? $0.id.uuidString < $1.id.uuidString : $0.addedAt > $1.addedAt
            }
            .filter { seen.insert($0.id).inserted }
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
    /// Payloads were unlinked but the metadata describing that could not be
    /// written. Carries what did go, so the caller can still be truthful.
    case partialRemoval(TrayRemovalResult, reason: String)
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
