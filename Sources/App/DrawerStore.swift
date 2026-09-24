import Foundation

/// Persists the drawer's shortcut list and its custom images as plain files
/// in the app container. The widget never reads these (no shared App Group on
/// the real deployment); the app serialises what the island needs into the
/// content state instead.
final class DrawerStore: Sendable {
    static let shared = DrawerStore()

    private let dir: URL
    private let listURL: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Drawer", isDirectory: true)
        dir = base
        listURL = base.appendingPathComponent("shortcuts.json")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    func load() -> [DrawerShortcut] {
        guard let data = try? Data(contentsOf: listURL),
              let items = try? JSONDecoder().decode([DrawerShortcut].self, from: data)
        else { return [] }
        return items.sorted { $0.order < $1.order }
    }

    func save(_ items: [DrawerShortcut]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: listURL, options: .atomic)
    }

    func iconURL(for shortcut: DrawerShortcut) -> URL? {
        guard let name = shortcut.customIconName else { return nil }
        return dir.appendingPathComponent(name)
    }

    /// Writes a custom icon and returns its filename (store it on the shortcut).
    @discardableResult
    func writeIcon(_ data: Data, for id: UUID) -> String {
        let name = "icon-\(id.uuidString).jpg"
        try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
        return name
    }

    /// Removes a shortcut's custom icon file, if it has one. Call this when
    /// the shortcut itself is deleted, or the file is orphaned on disk.
    func removeIcon(for shortcut: DrawerShortcut) {
        guard let name = shortcut.customIconName else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
    }

    var backgroundImageURL: URL? {
        let url = dir.appendingPathComponent("background.jpg")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func writeBackgroundImage(_ data: Data?) {
        let url = dir.appendingPathComponent("background.jpg")
        if let data { try? data.write(to: url, options: .atomic) }
        else { try? FileManager.default.removeItem(at: url) }
    }
}
