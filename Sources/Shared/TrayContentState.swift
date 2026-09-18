import Foundation

/// Dynamic data shown by the Live Activity.
///
/// ActivityKit rejects a content state whose encoded form exceeds 4096 bytes,
/// so this never carries image data — only an id the widget uses to locate a
/// thumbnail file on disk, plus an SF Symbol name to fall back to.
struct TrayContentState: Codable, Hashable {
    /// Maximum number of previews the Dynamic Island can show at once.
    static let maxPreviews = 4
    /// ActivityKit's hard limit for an encoded content state.
    static let maxEncodedBytes = 4096

    struct Preview: Codable, Hashable {
        /// TrayItem id. The widget derives the thumbnail path from this.
        var id: String
        /// SF Symbol name, used when the App Group container is unavailable.
        var symbol: String
    }

    var count: Int
    var recent: [Preview]

    static func make(from items: [TrayItem]) -> TrayContentState {
        let previews = items.prefix(maxPreviews).map {
            Preview(id: $0.id.uuidString, symbol: $0.symbolName)
        }
        return TrayContentState(count: items.count, recent: Array(previews))
    }

    var encodedByteCount: Int {
        (try? JSONEncoder().encode(self).count) ?? 0
    }
}
