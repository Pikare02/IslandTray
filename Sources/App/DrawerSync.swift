import Foundation

/// The drawer as one document in the sync folder: `Drawer/drawer.json`
/// beside the custom icons and background it names.
///
/// Unlike the tray, the drawer is one ordered list, so there is nothing to
/// merge item by item: the device that edited it last wins, decided by
/// `modifiedAt`. Every device writes the same file, which is what the tray
/// avoids -- but two people editing one drawer within a sync interval is
/// rare, and the loser is an undo away, not a lost file.
/// ponytail: last-writer-wins on device clocks; per-shortcut merge if
/// edits on two devices at once ever come up.
struct DrawerDocument: Codable, Equatable {
    var modifiedAt: Date
    var shortcuts: [DrawerShortcut]
    var hasBackground: Bool
}

/// What one pass does with the drawer, from the two stamps alone.
enum DrawerSyncStep: Equatable {
    case upload, adopt, none

    /// `local` nil: never saved here. `remote` nil: nothing in the folder.
    static func decide(local: Date?, remote: Date?) -> DrawerSyncStep {
        switch (local, remote) {
        case (nil, nil): return .none
        case (.some, nil): return .upload
        case (nil, .some): return .adopt
        case let (.some(l), .some(r)):
            if l > r { return .upload }
            if r > l { return .adopt }
            return .none
        }
    }
}

extension CloudFolder {
    var drawerDirectory: URL { root.appendingPathComponent("Drawer", isDirectory: true) }
    private var drawerDocumentURL: URL { drawerDirectory.appendingPathComponent("drawer.json") }
    private var drawerBackgroundURL: URL { drawerDirectory.appendingPathComponent("background.jpg") }

    /// Everything the pass needs to know about the folder's drawer.
    struct DrawerListing {
        var document: DrawerDocument?
        /// Something under `Drawer/` is still coming down from iCloud: asked
        /// for, and read next pass.
        var pending = false
    }

    func listDrawer() throws -> DrawerListing {
        try FileManager.default.createDirectory(at: drawerDirectory, withIntermediateDirectories: true)
        var listing = DrawerListing()
        // A coordinated look, so iCloud refreshes the listing (see `names`).
        _ = try names(in: drawerDirectory)
        let missing = UbiquitousDownload.pending(in: drawerDirectory)
        if !missing.isEmpty {
            for url in missing { try? FileManager.default.startDownloadingUbiquitousItem(at: url) }
            listing.pending = true
            return listing
        }
        guard FileManager.default.fileExists(atPath: drawerDocumentURL.path) else { return listing }
        let data = try Self.coordinatedRead(drawerDocumentURL)
        listing.document = try JSONDecoder.tray.decode(DrawerDocument.self, from: data)
        return listing
    }

    /// Puts this device's drawer in the folder. Files before the document,
    /// so a reader that sees the document finds what it names.
    func uploadDrawer(from store: DrawerStore, at stamp: Date) throws {
        try FileManager.default.createDirectory(at: drawerDirectory, withIntermediateDirectories: true)
        let shortcuts = store.load()
        var keep: Set<String> = ["drawer.json"]
        for s in shortcuts {
            guard let name = s.customIconName, let url = store.iconURL(for: s) else { continue }
            try Self.coordinatedWrite(drawerDirectory.appendingPathComponent(name), .forReplacing) {
                try Data(contentsOf: url).write(to: $0, options: .atomic)
            }
            keep.insert(name)
        }
        if let url = store.backgroundImageURL {
            try Self.coordinatedWrite(drawerBackgroundURL, .forReplacing) {
                try Data(contentsOf: url).write(to: $0, options: .atomic)
            }
            keep.insert("background.jpg")
        }
        let document = DrawerDocument(modifiedAt: stamp, shortcuts: shortcuts, hasBackground: store.backgroundImageURL != nil)
        try Self.coordinatedWrite(drawerDocumentURL, .forReplacing) {
            try JSONEncoder.tray.encode(document).write(to: $0, options: .atomic)
        }
        // Icons of shortcuts that no longer exist, and a background that was
        // removed. Last, so nothing is ever gone before the document says so.
        for name in (try? names(in: drawerDirectory)) ?? [] where !keep.contains(name) && !name.hasPrefix(".") {
            try? Self.coordinatedWrite(drawerDirectory.appendingPathComponent(name), .forDeleting) {
                try FileManager.default.removeItem(at: $0)
            }
        }
    }

    /// Replaces this device's drawer with the folder's. An icon the folder
    /// does not have (or names unsafely) leaves its shortcut on the default
    /// icon rather than failing the whole drawer.
    func adoptDrawer(_ document: DrawerDocument, into store: DrawerStore) throws {
        let old = store.load()
        var shortcuts = document.shortcuts
        for i in shortcuts.indices {
            guard let name = shortcuts[i].customIconName else { continue }
            // The name came from outside this app and becomes a path.
            guard name == DrawerStore.iconName(for: shortcuts[i].id),
                  let data = try? Self.coordinatedRead(drawerDirectory.appendingPathComponent(name)),
                  !data.isEmpty else {
                shortcuts[i].customIconName = nil
                continue
            }
            store.writeIcon(data, for: shortcuts[i].id)
        }
        if document.hasBackground, let data = try? Self.coordinatedRead(drawerBackgroundURL), !data.isEmpty {
            store.writeBackgroundImage(data)
        } else if !document.hasBackground, store.backgroundImageURL != nil {
            store.writeBackgroundImage(nil)
        }
        store.save(shortcuts)
        for s in old where !shortcuts.contains(where: { $0.id == s.id }) { store.removeIcon(for: s) }
        // After every write above, each of which stamped "now".
        store.setModifiedAt(document.modifiedAt)
    }
}
