import Foundation

/// Dynamic data shown by the Live Activity.
/// Must stay under 4096 bytes when encoded, so it never carries image data —
/// only an id the widget uses to locate a thumbnail file, plus a symbol fallback.
struct TrayContentState: Codable, Hashable {
    /// Maximum number of previews the Dynamic Island can show at once.
    static let maxPreviews = 4

    struct Preview: Codable, Hashable {
        /// TrayItem id. The widget derives the thumbnail path from this.
        var id: String
        /// SF Symbol name, used when the App Group container is unavailable.
        var symbol: String
    }

    var count: Int
    var recent: [Preview]
}
