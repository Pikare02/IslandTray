#if TROLLSTORE
import UIKit

/// Installed-app enumeration and launch via the private LSApplicationWorkspace.
/// TrollStore-signed builds run with the privilege these need; the Free build
/// never compiles this file (no `TROLLSTORE` flag).
///
/// ponytail: private API surface — method selectors are stable across the iOS
/// versions IslandTray targets but are not header-declared; if a future iOS
/// renames one, only this file changes. Icons come back at the system's
/// default variant; tune the variant constant if they look wrong on device.
struct InstalledApp {
    let bundleID: String
    let name: String
    let icon: UIImage?
}

enum InstalledApps {
    private static var workspace: NSObject? {
        let cls: AnyClass? = NSClassFromString("LSApplicationWorkspace")
        return cls?.value(forKey: "defaultWorkspace") as? NSObject
    }

    static func all() -> [InstalledApp] {
        guard let ws = workspace,
              let apps = ws.value(forKey: "allApplications") as? [NSObject] else { return [] }
        return apps.compactMap { proxy in
            guard let bid = proxy.value(forKey: "applicationIdentifier") as? String else { return nil }
            // User-installed apps only: system app types clutter the picker.
            let type = proxy.value(forKey: "applicationType") as? String
            guard type == "User" else { return nil }
            let name = (proxy.value(forKey: "localizedName") as? String) ?? bid
            return InstalledApp(bundleID: bid, name: name, icon: icon(bundleID: bid))
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func icon(bundleID: String) -> UIImage? {
        // UIImage(named:inBundle:) can't reach another app's bundle; use the
        // private icon services image the springboard uses.
        let sel = NSSelectorFromString("_applicationIconImageForBundleIdentifier:format:scale:")
        guard UIImage.responds(to: sel) else { return nil }
        let unmanaged = UIImage.perform(sel, with: bundleID, with: 2)
        return unmanaged?.takeUnretainedValue() as? UIImage
    }

    @discardableResult
    static func launch(bundleID: String) -> Bool {
        guard let ws = workspace else { return false }
        let sel = NSSelectorFromString("openApplicationWithBundleID:")
        guard ws.responds(to: sel) else { return false }
        let result = ws.perform(sel, with: bundleID)
        return result != nil
    }
}
#endif
