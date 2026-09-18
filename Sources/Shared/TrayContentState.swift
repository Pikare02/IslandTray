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

        /// Restricted to this file so every `Preview` built through
        /// `make(from:)` has `id` (a UUID string) and `symbol`
        /// (`TrayItem.symbolName`'s closed set) bounded. This does not bound
        /// `Preview`'s own synthesized `Decodable` initializer — Swift
        /// generates `init(from:)` independently of this initializer's
        /// access level. The overall size invariant for a *decoded*
        /// `TrayContentState` is enforced one level up, in
        /// `TrayContentState.init(from:)`, which validates encoded size
        /// after decoding and degrades if needed.
        fileprivate init(id: String, symbol: String) {
            self.id = id
            self.symbol = symbol
        }
    }

    private enum CodingKeys: String, CodingKey {
        case count, recent
    }

    let count: Int
    let recent: [Preview]

    /// Restricted so `maxPreviews` can never be bypassed by direct construction.
    /// Build a `TrayContentState` via `make(from:)` or `countOnly(count:)`.
    private init(count: Int, recent: [Preview]) {
        self.count = count
        self.recent = recent
    }

    /// Decoding is a real construction path: ActivityKit decodes this type
    /// in the widget process. The synthesized `init(from:)` would set
    /// `count`/`recent` directly, bypassing `maxPreviews` and the bounded
    /// symbol vocabulary that `make(from:)` enforces — a crafted payload
    /// (e.g. one oversized `id`) could decode into a state well over
    /// `maxEncodedBytes`. This custom initializer clamps `recent` to
    /// `maxPreviews` and then, if the result is still oversized (a single
    /// pathologically long `id`/`symbol` is enough to blow the budget by
    /// itself), degrades to the same count-only shape `countOnly(count:)`
    /// produces — which is always within the limit regardless of `count`.
    /// It never throws for a size problem; only a malformed/missing `count`
    /// (a genuine schema error, not a size issue) propagates.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedCount = try container.decode(Int.self, forKey: .count)
        let decodedRecent = (try? container.decode([Preview].self, forKey: .recent)) ?? []
        let clamped = TrayContentState(count: decodedCount, recent: Array(decodedRecent.prefix(Self.maxPreviews)))
        self = clamped.encodedByteCount <= Self.maxEncodedBytes
            ? clamped
            : TrayContentState(count: decodedCount, recent: [])
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
