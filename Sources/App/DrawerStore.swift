import Foundation

/// Persists the drawer's shortcut list and its custom images as plain files
/// in Application Support -- never Documents: that folder is the Files-app
/// inbox, and `DocumentsInbox.sweep` would take a "Drawer" folder there into
/// the tray as an item (and delete it, losing every later save). The widget never reads these (no shared App Group on
/// the real deployment); the app serialises what the island needs into the
/// content state instead.
final class DrawerStore: Sendable {
    static let shared = DrawerStore()

    let dir: URL
    private let listURL: URL
    /// When this device last changed the drawer, as the sync folder compares
    /// it; see `DrawerSync`. Written by every mutation below.
    private let stampURL: URL

    /// Posted after the sync folder replaced this device's drawer, so a view
    /// holding its own copy of the list reloads it.
    static let didSyncNotification = Notification.Name("DrawerStore.didSync")

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Drawer", isDirectory: true)
        dir = base
        listURL = base.appendingPathComponent("shortcuts.json")
        stampURL = base.appendingPathComponent("modified")
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
        touch()
    }

    /// The last local edit. A drawer saved before the stamp existed reports
    /// its list file's date, so it still competes with other devices on
    /// when it was really changed; nil means nothing was ever saved.
    var modifiedAt: Date? {
        if let s = try? String(contentsOf: stampURL, encoding: .utf8), let t = TimeInterval(s) {
            return Date(timeIntervalSinceReferenceDate: t)
        }
        return (try? listURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// Sets the stamp to `date` -- the sync folder's, after adopting its
    /// drawer, so the copy just taken does not read as a newer local edit.
    func setModifiedAt(_ date: Date) {
        try? String(date.timeIntervalSinceReferenceDate).write(to: stampURL, atomically: true, encoding: .utf8)
    }

    private func touch() { setModifiedAt(Date()) }

    /// The one filename a custom icon ever has, so a name that arrives from
    /// the sync folder is checked against it before becoming a path.
    static func iconName(for id: UUID) -> String { "icon-\(id.uuidString).jpg" }

    func iconURL(for shortcut: DrawerShortcut) -> URL? {
        guard let name = shortcut.customIconName else { return nil }
        return dir.appendingPathComponent(name)
    }

    /// Writes a custom icon and returns its filename (store it on the shortcut).
    @discardableResult
    func writeIcon(_ data: Data, for id: UUID) -> String {
        let name = Self.iconName(for: id)
        try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
        touch()
        return name
    }

    /// Removes a shortcut's custom icon file, if it has one. Call this when
    /// the shortcut itself is deleted, or the file is orphaned on disk.
    func removeIcon(for shortcut: DrawerShortcut) {
        guard let name = shortcut.customIconName else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        touch()
    }

    var backgroundImageURL: URL? {
        let url = dir.appendingPathComponent("background.jpg")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func writeBackgroundImage(_ data: Data?) {
        let url = dir.appendingPathComponent("background.jpg")
        if let data { try? data.write(to: url, options: .atomic) }
        else { try? FileManager.default.removeItem(at: url) }
        touch()
        // The file URL is not observable; bump a counter so views watching it
        // (@AppStorage "drawerBackgroundVersion") reload the image at once.
        let store = TraySettings.store
        store.set(store.integer(forKey: "drawerBackgroundVersion") + 1, forKey: "drawerBackgroundVersion")
    }
}
