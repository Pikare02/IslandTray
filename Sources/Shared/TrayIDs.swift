import Foundation

/// Identifiers shared by the app and both extensions.
/// Keep these in sync with project.yml and the entitlements files.
enum TrayIDs {
    static let appGroupID = "group.com.pikare.islandtray"
    static let urlScheme = "islandtray"

    /// Deep link used by the Live Activity to bring the tray forward for a drop.
    static let dropURL = URL(string: "\(urlScheme)://drop")!
    /// Opens the app on its drawer tab.
    static let drawerURL = URL(string: "\(urlScheme)://drawer")!
    /// Opens the app straight on one tray item's preview.
    static func openURL(item id: String) -> URL? { URL(string: "\(urlScheme)://open?item=\(id)") }
}
