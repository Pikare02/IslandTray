import Foundation

/// Resolves where tray data lives.
///
/// This is the only place in the codebase that knows whether the App Group
/// entitlement is present. Everything else just uses the URLs below.
/// Without a paid developer account the entitlement is absent, the App Group
/// container URL comes back nil, and we fall back to the app's own sandbox.
enum TrayContainer {
    static var isShared: Bool { appGroupRoot != nil }

    static var root: URL { appGroupRoot ?? localRoot }

    /// The sandbox location, ignoring any App Group. Used by the migration in
    /// TrayStore when the app moves from a free to a paid account.
    static var localRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("IslandTray", isDirectory: true)
    }

    static var itemsDirectory: URL { root.appendingPathComponent("Items", isDirectory: true) }
    static var thumbsDirectory: URL { root.appendingPathComponent("Thumbs", isDirectory: true) }
    static var metadataURL: URL { root.appendingPathComponent("items.json") }

    private static var appGroupRoot: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: TrayIDs.appGroupID)
    }
}
