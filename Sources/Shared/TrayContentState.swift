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
        let id: String
        /// SF Symbol name, used when the App Group container is unavailable.
        let symbol: String

        /// Restricted to this file so every `Preview` is built through
        /// `make(from:)`, which bounds both `id` (a UUID string) and `symbol`
        /// (`TrayItem.symbolName`'s closed set) — never from arbitrary input.
        fileprivate init(id: String, symbol: String) {
            self.id = id
            self.symbol = symbol
        }
    }

    let count: Int
    let recent: [Preview]

    /// Restricted so `maxPreviews` can never be bypassed by direct construction.
    /// Build a `TrayContentState` via `make(from:)` or `countOnly(count:)`.
    private init(count: Int, recent: [Preview]) {
        self.count = count
        self.recent = recent
    }

    static func make(from items: [TrayItem]) -> TrayContentState {
        let previews = items.prefix(maxPreviews).map {
            Preview(id: $0.id.uuidString, symbol: $0.symbolName)
        }
        return TrayContentState(count: items.count, recent: Array(previews))
    }

    /// Degraded state carrying only the count, for when the full state (with
    /// previews) would exceed `maxEncodedBytes`.
    static func countOnly(count: Int) -> TrayContentState {
        TrayContentState(count: count, recent: [])
    }

    var encodedByteCount: Int {
        (try? JSONEncoder().encode(self).count) ?? 0
    }
}
