import Foundation

enum LaunchRoute: Equatable {
    case drop
    case drawer
    case launch(UUID)
    /// A drawer slot's own URL (web, `shortcuts://`, another app's scheme).
    /// A Live Activity's `Link` always opens this app with the URL rather
    /// than the target, so the app has to pass it on.
    case external(URL)
    case ignore
}

enum LaunchRouter {
    static func route(_ url: URL) -> LaunchRoute {
        // file:// is a document handed over with "Open In", never a slot.
        guard let scheme = url.scheme, !url.isFileURL else { return .ignore }
        guard scheme == TrayIDs.urlScheme else { return .external(url) }
        switch url.host {
        case "drop": return .drop
        case "drawer": return .drawer
        case "launch":
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            guard let raw = comps?.queryItems?.first(where: { $0.name == "item" })?.value,
                  let id = UUID(uuidString: raw) else { return .ignore }
            return .launch(id)
        default: return .ignore
        }
    }

    /// Runs the side effect for a `.launch` route: only installed apps reach
    /// here (other kinds open directly from the widget). Returns false when the
    /// item is missing or launching is unsupported on this build.
    @discardableResult
    static func performLaunch(_ id: UUID) -> Bool {
        // The whole lookup lives inside the flag: on a Free build nothing can
        // launch an installed app, so reading the store would be a pointless
        // disk hit and `item` would be an unused binding (a compiler warning).
        #if TROLLSTORE
        guard let item = DrawerStore.shared.load().first(where: { $0.id == id }) else { return false }
        if case let .installedApp(bundleID) = item.kind {
            return InstalledApps.launch(bundleID: bundleID)
        }
        #endif
        return false
    }
}

extension Notification.Name {
    static let openDrawer = Notification.Name("openDrawer")
}
