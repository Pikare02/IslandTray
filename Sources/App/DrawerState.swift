import UIKit

/// Turns the stored drawer into the content-state pieces the island needs.
enum DrawerState {
    static func slots(from shortcuts: [DrawerShortcut], showNames: Bool) -> [TrayContentState.DrawerSlot] {
        shortcuts.sorted { $0.order < $1.order }
            .prefix(TrayContentState.maxSlots)
            .map { s in
                TrayContentState.DrawerSlot(
                    symbol: s.symbolName,
                    name: showNames ? TrayContentState.islandName(s.displayName) : "",
                    launch: s.launchURL?.absoluteString ?? "",
                    hasIcon: s.customIconName != nil
                )
            }
    }

    /// Icon image per slot (custom photo, else installed-app icon on TrollStore,
    /// else nil → SF Symbol fallback). Order matches `slots(from:)`.
    static func icons(for shortcuts: [DrawerShortcut]) async -> [UIImage?] {
        shortcuts.sorted { $0.order < $1.order }
            .prefix(TrayContentState.maxSlots)
            .map { s -> UIImage? in
                if let url = DrawerStore.shared.iconURL(for: s),
                   let data = try? Data(contentsOf: url) {
                    return UIImage(data: data)
                }
                #if TROLLSTORE
                if case let .installedApp(bundleID) = s.kind {
                    return InstalledApps.icon(bundleID: bundleID)
                }
                #endif
                return nil
            }
    }
}
