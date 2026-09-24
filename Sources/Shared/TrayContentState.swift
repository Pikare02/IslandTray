import Foundation

/// Dynamic data shown by the Live Activity.
///
/// ActivityKit rejects a content state whose encoded form exceeds 4096 bytes.
/// The widget process can only read thumbnail files off disk when the App
/// Group entitlement survives (it does not under SideStore re-signing, which
/// is the real deployment), so the actual image bytes travel here instead —
/// as one JPEG strip covering every preview, not one JPEG per preview.
///
/// One strip, not four: a baseline JPEG carries ~600 bytes of quantization
/// and Huffman tables before a single pixel, so four separate 48px thumbnails
/// measured 5872 base64 bytes against 2496 for the same four tiles composited
/// side by side. Four real thumbnails only fit at all because the tables are
/// paid for once. (Measured over 16 screenshots, which are the worst case for
/// JPEG — dense text and hard edges — not photographs.) `ThumbnailService`
/// owns the tile size that measurement picked.
struct TrayContentState: Codable, Hashable {
    /// Maximum number of previews the Dynamic Island can show at once.
    static let maxPreviews = 4
    /// ActivityKit's hard limit for an encoded content state.
    static let maxEncodedBytes = 4096

    /// What `make(from:atlas:)` aims for, below `maxEncodedBytes`.
    ///
    /// `encodedByteCount` measures a vanilla `JSONEncoder`, which is not
    /// verified byte-identical to whatever ActivityKit encodes with. Before
    /// the atlas the margin was ~8x and the difference could not matter; a
    /// state carrying image bytes runs near the limit by design, so the
    /// build path leaves 512 bytes of headroom for that uncertainty.
    static let buildBudget = maxEncodedBytes - 512

    /// Longest display name carried per preview, in UTF-8 bytes.
    ///
    /// The island draws these under a 40pt tile, so roughly ten characters
    /// are legible however many are sent; the cap exists so four long names
    /// cannot push the atlas out of the budget.
    static let maxNameBytes = 32

    struct Preview: Codable, Hashable {
        /// TrayItem id. The widget derives the thumbnail path from this when
        /// the App Group container is readable.
        let id: String
        /// SF Symbol name, used when no real thumbnail is available.
        let symbol: String
        /// Display name, already capped to `maxNameBytes`.
        let name: String
        /// Whether this preview's tile in `atlas` holds a real thumbnail.
        ///
        /// The atlas always has one tile per preview so indices line up, but
        /// `QLThumbnailGenerator` returns nothing for some item types; those
        /// tiles are blank and must fall back to `symbol` rather than draw an
        /// empty box.
        let hasThumbnail: Bool

        /// Restricted to this file so every `Preview` built through
        /// `make(from:atlas:)` has `id` (a UUID string), `symbol`
        /// (`TrayItem.symbolName`'s closed set) and `name` (capped) bounded.
        /// This does not bound `Preview`'s own synthesized `Decodable`
        /// initializer — Swift generates `init(from:)` independently of this
        /// initializer's access level. The overall size invariant for a
        /// *decoded* `TrayContentState` is enforced one level up, in
        /// `TrayContentState.init(from:)`, which validates encoded size after
        /// decoding and degrades if needed.
        fileprivate init(id: String, symbol: String, name: String, hasThumbnail: Bool) {
            self.id = id
            self.symbol = symbol
            self.name = name
            self.hasThumbnail = hasThumbnail
        }
    }

    private enum CodingKeys: String, CodingKey {
        case count, recent, atlas, page, added, weather, drawer, view
    }

    /// What a shortcut just put in, shown with a check while the island is
    /// briefly expanded for it.
    struct Added: Codable, Hashable {
        let count: Int
        let board: TrayBoard
    }

    struct Weather: Codable, Hashable {
        let dateText: String
        let tempText: String
        let symbol: String
    }

    struct DrawerSlot: Codable, Hashable {
        let symbol: String
        let name: String
        /// A URL string the widget wraps in a `Link`.
        let launch: String
        /// Whether this slot's atlas tile holds a real icon.
        let hasIcon: Bool
    }

    enum View: String, Codable { case tray, drawer }

    /// Maximum drawer slots shown on the island.
    static let maxSlots = 6

    let count: Int
    let recent: [Preview]
    /// JPEG holding `recent.count` square tiles left to right, in `recent`'s
    /// order, or `nil` when no thumbnail was available or the bytes did not
    /// fit. The tile side is not carried: the tiles are square and there is
    /// one per preview, so the strip's own height is the side and
    /// `recent.count` is the rest of what the widget needs to slice it.
    let atlas: Data?
    /// Which run of `maxPreviews` items `recent` is.
    ///
    /// A widget cannot be scrolled or swiped -- it receives no gestures at
    /// all beyond a tap on a button -- so a tray of more than four is paged
    /// through with buttons in the expanded island, and this is what they
    /// move.
    let page: Int
    /// Set only for the moment after a shortcut adds something; see
    /// `TrayActivityController.announce(_:)`.
    let added: Added?
    /// Weather shown above the drawer, or `nil` outside `view == .drawer`.
    let weather: Weather?
    /// Shortcut slots shown by the drawer, capped to `maxSlots`, or `nil`
    /// outside `view == .drawer`.
    let drawer: [DrawerSlot]?
    /// Which face the island is showing. Tray states never set `weather` or
    /// `drawer`; only `makeDrawer(...)` does.
    let view: View

    /// Restricted so `maxPreviews` can never be bypassed by direct construction.
    /// Build a `TrayContentState` via `make(from:atlas:)` or `countOnly(count:)`.
    private init(
        count: Int, recent: [Preview], atlas: Data?, page: Int = 0, added: Added? = nil,
        weather: Weather? = nil, drawer: [DrawerSlot]? = nil, view: View = .tray
    ) {
        self.count = count
        self.recent = recent
        self.atlas = atlas
        self.page = page
        self.added = added
        self.weather = weather
        self.drawer = drawer
        self.view = view
    }

    /// The same state, carrying `added`. A few dozen bytes, which the
    /// headroom `buildBudget` leaves covers.
    func announcing(_ added: Added?) -> TrayContentState {
        TrayContentState(
            count: count, recent: recent, atlas: atlas, page: page, added: added,
            weather: weather, drawer: drawer, view: view
        )
    }

    /// Whether there is a run of items before or after this one.
    var hasPreviousPage: Bool { page > 0 }
    var hasNextPage: Bool { (page + 1) * Self.maxPreviews < count }

    /// The items one page shows, clamped so a page beyond the end shows the
    /// last one rather than nothing.
    ///
    /// The single place the slicing is defined: the state and the atlas built
    /// for it have to agree about which items they are describing, and they
    /// are built in different files.
    static func items(_ items: [TrayItem], onPage page: Int) -> [TrayItem] {
        guard !items.isEmpty else { return [] }
        let start = clampedPage(page, count: items.count) * maxPreviews
        return Array(items.dropFirst(start).prefix(maxPreviews))
    }

    static func clampedPage(_ page: Int, count: Int) -> Int {
        let pages = max(1, (count + maxPreviews - 1) / maxPreviews)
        return min(max(0, page), pages - 1)
    }

    /// Decoding is a real construction path: ActivityKit decodes this type
    /// in the widget process. The synthesized `init(from:)` would set the
    /// stored properties directly, bypassing `maxPreviews` and the bounded
    /// vocabulary that `make(from:atlas:)` enforces — a crafted payload (one
    /// oversized `id`, or an atlas of any size at all) could decode into a
    /// state well over `maxEncodedBytes`. This initializer clamps `recent`
    /// to `maxPreviews`, then drops the atlas, then drops the previews,
    /// taking the first form that fits.
    ///
    /// It never throws for a size problem, and it never throws because a
    /// field it did not expect was absent: an activity started by an older
    /// build of the app is still on screen after an update, and its state
    /// decodes here. Only a malformed/missing `count` (a genuine schema
    /// error) propagates.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedCount = try container.decode(Int.self, forKey: .count)
        let decodedRecent = (try? container.decode([Preview].self, forKey: .recent)) ?? []
        let decodedAtlas = try? container.decodeIfPresent(Data.self, forKey: .atlas)
        let decodedPage = (try? container.decodeIfPresent(Int.self, forKey: .page)) ?? 0
        let added = (try? container.decodeIfPresent(Added.self, forKey: .added)) ?? nil
        let decodedWeather = (try? container.decodeIfPresent(Weather.self, forKey: .weather)) ?? nil
        let decodedDrawer = (try? container.decodeIfPresent([DrawerSlot].self, forKey: .drawer))
            .map { Array($0.prefix(Self.maxSlots)) } ?? nil
        let decodedView = (try? container.decodeIfPresent(View.self, forKey: .view)) ?? .tray
        let clampedRecent = Array(decodedRecent.prefix(Self.maxPreviews))
        let page = Self.clampedPage(decodedPage, count: decodedCount)

        let full = TrayContentState(
            count: decodedCount, recent: clampedRecent, atlas: decodedAtlas, page: page, added: added,
            weather: decodedWeather, drawer: decodedDrawer, view: decodedView
        )
        if full.encodedByteCount <= Self.maxEncodedBytes {
            self = full
            return
        }
        let noAtlas = TrayContentState(
            count: decodedCount, recent: clampedRecent, atlas: nil, page: page, added: added,
            weather: decodedWeather, drawer: decodedDrawer, view: decodedView
        )
        self = noAtlas.encodedByteCount <= Self.maxEncodedBytes
            ? noAtlas
            : TrayContentState(
                count: decodedCount, recent: [], atlas: nil, page: page, added: added,
                weather: decodedWeather, drawer: decodedDrawer, view: decodedView
            )
    }

    /// A JPEG strip built for one `make(from:atlas:)` call, plus which of
    /// its tiles actually hold an image.
    ///
    /// `filled` is not encoded — it is what sets each `Preview.hasThumbnail`.
    /// It exists because a tile has to be reserved for every preview to keep
    /// the slicing indices honest, including the ones
    /// `QLThumbnailGenerator` had nothing for.
    struct Atlas {
        let jpeg: Data
        let filled: [Bool]

        init(jpeg: Data, filled: [Bool]) {
            self.jpeg = jpeg
            self.filled = filled
        }
    }

    /// - Parameter atlas: a strip with one tile per preview, in the same
    ///   order as `items`, or `nil`. Dropped whole if it does not fit; never
    ///   partially, since a strip cannot be shortened without re-encoding.
    static func make(from items: [TrayItem], atlas: Atlas? = nil, page: Int = 0) -> TrayContentState {
        let page = clampedPage(page, count: items.count)
        let previews = Self.items(items, onPage: page).enumerated().map { index, item in
            Preview(
                id: item.id.uuidString,
                symbol: item.symbolName,
                name: islandName(item.name),
                // `indices.contains` rather than `index < count`: a caller
                // that built a shorter `filled` than there are previews must
                // fall back to symbols, not read past the end.
                hasThumbnail: atlas?.filled.indices.contains(index) == true && atlas?.filled[index] == true
            )
        }
        let withAtlas = TrayContentState(
            count: items.count, recent: Array(previews), atlas: atlas?.jpeg, page: page
        )
        if withAtlas.encodedByteCount <= buildBudget { return withAtlas }

        let withoutAtlas = TrayContentState(
            count: items.count,
            recent: previews.map {
                Preview(id: $0.id, symbol: $0.symbol, name: $0.name, hasThumbnail: false)
            },
            atlas: nil,
            page: page
        )
        return withoutAtlas.encodedByteCount <= maxEncodedBytes
            ? withoutAtlas
            : countOnly(count: items.count)
    }

    /// Degraded state carrying only the count, for when the full state (with
    /// previews) would exceed `maxEncodedBytes`.
    static func countOnly(count: Int) -> TrayContentState {
        TrayContentState(count: count, recent: [], atlas: nil)
    }

    /// Empty-tray drawer/weather state, kept within the encoded-size cap the
    /// same way `make(from:atlas:)` is. Slot names are capped like preview names
    /// (`islandName`); launch URLs are never truncated (a cut URL is a dead
    /// link), so when even the atlas-dropped state is still too big, whole slots
    /// are shed from the end until it fits — worst case an empty drawer showing
    /// only the tiny weather line. `slots` is capped to `maxSlots` first.
    static func makeDrawer(weather: Weather?, slots: [DrawerSlot], atlas: Atlas?,
                           view: View, count: Int) -> TrayContentState {
        let capped = Array(slots.prefix(maxSlots)).map {
            DrawerSlot(symbol: $0.symbol, name: islandName($0.name), launch: $0.launch, hasIcon: $0.hasIcon)
        }
        let withAtlas = TrayContentState(
            count: count, recent: [], atlas: atlas?.jpeg, page: 0, added: nil,
            weather: weather, drawer: capped, view: view
        )
        if withAtlas.encodedByteCount <= buildBudget { return withAtlas }

        // Drop the atlas, then shed slots from the end until the symbol-only
        // state fits under the hard cap. `kept.isEmpty` is the floor: weather
        // alone is a few dozen bytes and always fits.
        var kept = capped
        while true {
            let candidate = TrayContentState(
                count: count, recent: [], atlas: nil, page: 0, added: nil,
                weather: weather,
                drawer: kept.map { DrawerSlot(symbol: $0.symbol, name: $0.name, launch: $0.launch, hasIcon: false) },
                view: view
            )
            if candidate.encodedByteCount <= maxEncodedBytes || kept.isEmpty { return candidate }
            kept.removeLast()
        }
    }

    /// `name` capped to `maxNameBytes`, cut in the middle so the extension
    /// survives — "which file" is mostly carried by the extension once the
    /// island has already truncated the stem visually.
    static func islandName(_ name: String) -> String {
        guard name.utf8.count > maxNameBytes else { return name }
        // Budget in bytes, but cut on Characters: removing a byte can split a
        // grapheme. Two thirds to the head, the rest to the tail.
        let ellipsis = "…"
        var head = ""
        var tail = ""
        let headBudget = (maxNameBytes - ellipsis.utf8.count) * 2 / 3
        for character in name {
            let next = head + String(character)
            if next.utf8.count > headBudget { break }
            head = next
        }
        let tailBudget = maxNameBytes - ellipsis.utf8.count - head.utf8.count
        for character in name.reversed() {
            let next = String(character) + tail
            if next.utf8.count > tailBudget { break }
            tail = next
        }
        return head + ellipsis + tail
    }

    var encodedByteCount: Int {
        (try? JSONEncoder().encode(self).count) ?? 0
    }
}
