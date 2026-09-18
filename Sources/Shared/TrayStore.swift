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

    /// Newest first. Corrupt (but readable) metadata is rebuilt from disk.
    /// A metadata file that cannot be read throws: an unreadable tray is not an
    /// empty tray, and callers must not persist anything derived from it.
    func load() throws -> [TrayItem] {
        try prepare()
        guard let data = try coordinatedRead(), !data.isEmpty else { return [] }
        guard let items = try? JSONDecoder.tray.decode([TrayItem].self, from: data) else {
            return try rebuildFromDisk()
        }
        return presentable(items)
    }

    /// Recovers the list from the files actually present in Items/.
    /// Metadata that the files cannot carry (the original display name) is
    /// replaced by a placeholder; everything derivable from the filename is
    /// recovered. Throws if the directory cannot be listed, so a failed
    /// recovery is never persisted as an empty tray.
    @discardableResult
    func rebuildFromDisk() throws -> [TrayItem] {
        try prepare()
        return try mutate { $0 = try self.itemsOnDisk() }
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

    func remove(id: UUID) throws {
        try mutate { items in
            guard let index = items.firstIndex(where: { $0.id == id }) else { return }
            // Unlink before dropping the entry: load() already filters an entry
            // whose file is missing, while a file whose entry is missing gets
            // resurrected by rebuildFromDisk(). A failed unlink aborts the whole
            // mutation, so a deletion is never reported as done while the bytes
            // are still there.
            try self.deleteFiles(for: items[index])
            items.remove(at: index)
        }
    }

    func removeAll() throws {
        try mutate { items in
            for item in items { try self.deleteFiles(for: item) }
            items.removeAll()
        }
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
    private func mutate(_ body: (inout [TrayItem]) throws -> Void) throws -> [TrayItem] {
        try prepare()
        var written: [TrayItem] = []
        var bodyError: Error?
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(
            writingItemAt: metadataURL, options: .forMerging, error: &coordinatorError
        ) { url in
            do {
                var items = try self.currentItems(at: url)
                try body(&items)
                items = self.presentable(items)
                // Atomic so a crash mid-write cannot leave truncated JSON. There
                // are no file presenters here that would need an in-place write.
                try JSONEncoder.tray.encode(items).write(to: url, options: .atomic)
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
    /// Never substitutes an empty list for a read it could not perform.
    private func currentItems(at url: URL) throws -> [TrayItem] {
        guard let data = try readIfPresent(at: url), !data.isEmpty else { return [] }
        guard let items = try? JSONDecoder.tray.decode([TrayItem].self, from: data) else {
            // Corrupt but readable: recover from the payloads rather than
            // building this mutation on top of nothing.
            return try itemsOnDisk()
        }
        return items
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
    /// two items share a timestamp. Entries whose payload is gone are dropped.
    private func presentable(_ items: [TrayItem]) -> [TrayItem] {
        items
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
            let interval = try decoder.singleValueContainer().decode(Double.self)
            return Date(timeIntervalSinceReferenceDate: interval)
        }
        return decoder
    }
}
