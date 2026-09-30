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
    static var drawerIconsDirectory: URL { root.appendingPathComponent("DrawerIcons", isDirectory: true) }
    static var metadataURL: URL { root.appendingPathComponent("items.json") }

    /// The Live Activity refresh and the widget read items.json, thumbnails and
    /// drawer icons *while the device is locked* (a background refresh, and the
    /// Lock Screen presentation). The default protection can leave those files
    /// unreadable when locked -- the read fails with a permission error, which
    /// showed up as "can't read items.json" and as blank photo thumbnails on
    /// the Lock Screen. This class stays readable once the device has been
    /// unlocked a single time since boot, which a running Live Activity implies,
    /// while still encrypting the files at rest.
    static let lockScreenReadableProtection = FileProtectionType.completeUntilFirstUserAuthentication

    /// Write option matching `lockScreenReadableProtection`, for the files above.
    static let lockScreenReadableWrite: Data.WritingOptions = .completeFileProtectionUntilFirstUserAuthentication

    /// Re-apply that class to files an earlier build wrote under a stricter one,
    /// so the fix lands without waiting for each file to be rewritten. Cheap:
    /// items.json plus a handful of small thumbnail/icon files, attribute-only.
    /// Must run while unlocked (app foreground), so the reads it needs succeed.
    static func relaxProtectionForLockScreenReads() {
        let fm = FileManager.default
        func relax(_ url: URL) {
            try? fm.setAttributes([.protectionKey: lockScreenReadableProtection], ofItemAtPath: url.path)
        }
        relax(metadataURL)
        for dir in [thumbsDirectory, drawerIconsDirectory] {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            files.forEach(relax)
        }
    }

    private static var appGroupRoot: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: TrayIDs.appGroupID)
    }
}
