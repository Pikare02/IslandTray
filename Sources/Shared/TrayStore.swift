import Foundation
import UniformTypeIdentifiers

/// Reads and writes the tray contents.
///
/// Items are stored as copies: drag payloads are short-lived and Photos items
/// carry no durable path, so keeping a reference would leave dangling entries.
///
/// The app and the share extension can both write, so every access to
/// items.json goes through NSFileCoordinator.
// All stored properties are immutable (`let`) and the type itself has no
// mutable state, so it is safe to share across concurrency domains despite
// FileManager/NSFileCoordinator not being marked Sendable upstream.
final class TrayStore: @unchecked Sendable {
    static let shared = TrayStore(root: TrayContainer.root)

    private let root: URL
    private let itemsDirectory: URL
    private let thumbsDirectory: URL
    private let metadataURL: URL
    private let fileManager = FileManager.default

    init(root: URL) {
        self.root = root
        self.itemsDirectory = root.appendingPathComponent("Items", isDirectory: true)
        self.thumbsDirectory = root.appendingPathComponent("Thumbs", isDirectory: true)
        self.metadataURL = root.appendingPathComponent("items.json")
    }

    func prepare() throws {
        for dir in [root, itemsDirectory, thumbsDirectory] {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Reading

    /// Newest first. Never throws on corrupt metadata — it rebuilds from disk.
    func load() throws -> [TrayItem] {
        try prepare()
        guard let data = coordinatedRead(), !data.isEmpty else { return [] }
        guard let items = try? JSONDecoder.tray.decode([TrayItem].self, from: data) else {
            return try rebuildFromDisk()
        }
        return items
            .filter { fileManager.fileExists(atPath: $0.fileURL(in: itemsDirectory).path) }
            .sorted { $0.addedAt > $1.addedAt }
    }

    /// Recovers the list from the files actually present in Items/.
    /// Metadata that cannot be recovered (original name, UTI) is approximated.
    @discardableResult
    func rebuildFromDisk() throws -> [TrayItem] {
        try prepare()
        let urls = (try? fileManager.contentsOfDirectory(
            at: itemsDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]
        )) ?? []

        let recovered: [TrayItem] = urls.compactMap { url in
            let stem = url.deletingPathExtension().lastPathComponent
            guard let id = UUID(uuidString: stem) else { return nil }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
            let ext = url.pathExtension.lowercased()
            return TrayItem(
                id: id,
                name: url.lastPathComponent,
                uti: utiIdentifier(forExtension: ext),
                size: values?.fileSize ?? 0,
                addedAt: values?.creationDate ?? Date(),
                ext: ext
            )
        }
        .sorted { $0.addedAt > $1.addedAt }

        try write(recovered)
        return recovered
    }

    // MARK: - Writing

    @discardableResult
    func add(data: Data, suggestedName: String?, uti: String?) throws -> TrayItem {
        try prepare()
        let item = makeItem(suggestedName: suggestedName, uti: uti, size: data.count)
        try data.write(to: item.fileURL(in: itemsDirectory), options: .atomic)
        try mutate { $0.insert(item, at: 0) }
        return item
    }

    @discardableResult
    func add(copyingFrom source: URL, suggestedName: String?, uti: String?) throws -> TrayItem {
        try prepare()
        let name = suggestedName ?? source.lastPathComponent
        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let item = makeItem(suggestedName: name, uti: uti, size: size)
        let destination = item.fileURL(in: itemsDirectory)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
        try mutate { $0.insert(item, at: 0) }
        return item
    }

    func remove(id: UUID) throws {
        var removed: TrayItem?
        try mutate { items in
            if let index = items.firstIndex(where: { $0.id == id }) {
                removed = items.remove(at: index)
            }
        }
        if let removed {
            try? fileManager.removeItem(at: removed.fileURL(in: itemsDirectory))
            try? fileManager.removeItem(at: removed.thumbnailURL(in: thumbsDirectory))
        }
    }

    func removeAll() throws {
        let items = try load()
        for item in items {
            try? fileManager.removeItem(at: item.fileURL(in: itemsDirectory))
            try? fileManager.removeItem(at: item.thumbnailURL(in: thumbsDirectory))
        }
        try write([])
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

    private func mutate(_ body: (inout [TrayItem]) -> Void) throws {
        var items = (try? load()) ?? []
        body(&items)
        try write(items)
    }

    private func write(_ items: [TrayItem]) throws {
        let data = try JSONEncoder.tray.encode(items.sorted { $0.addedAt > $1.addedAt })
        var coordinatorError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(
            writingItemAt: metadataURL, options: .forReplacing, error: &coordinatorError
        ) { url in
            do { try data.write(to: url, options: .atomic) } catch { writeError = error }
        }
        if let writeError { throw writeError }
        if let coordinatorError { throw coordinatorError }
    }

    private func coordinatedRead() -> Data? {
        var result: Data?
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(
            readingItemAt: metadataURL, options: [], error: &coordinatorError
        ) { url in
            result = try? Data(contentsOf: url)
        }
        return result
    }

    private func utiIdentifier(forExtension ext: String) -> String {
        guard !ext.isEmpty,
              let type = UTType(filenameExtension: ext) else { return "public.data" }
        return type.identifier
    }
}

extension JSONEncoder {
    static var tray: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var tray: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
