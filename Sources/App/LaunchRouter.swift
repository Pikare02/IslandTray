import Foundation

enum LaunchRoute: Equatable {
    case drop
    case drawer
    case launch(UUID)
    case ignore
}

enum LaunchRouter {
    static func route(_ url: URL) -> LaunchRoute {
        guard url.scheme == TrayIDs.urlScheme else { return .ignore }
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
        guard let item = DrawerStore.shared.load().first(where: { $0.id == id }) else { return false }
        #if TROLLSTORE
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
