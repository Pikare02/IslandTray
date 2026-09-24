import Foundation

/// One launchable entry in the app drawer.
enum DrawerKind: Codable, Hashable {
    case installedApp(bundleID: String)
    case shortcut(name: String)
    case urlScheme(String)
    case webURL(String)
}

struct DrawerShortcut: Codable, Identifiable, Hashable {
    let id: UUID
    var kind: DrawerKind
    var displayName: String
    /// Filename of a square custom icon in the drawer container, or nil for
    /// the kind's default icon.
    var customIconName: String?
    var order: Int
    /// When it was added, for sorting by it. `nil` on entries saved before
    /// this existed; those sort as oldest, in their current order.
    var addedAt: Date? = nil

    enum Sort: String, CaseIterable {
        case name, oldest, newest
    }

    /// `items` put in `sort` order and renumbered, so the result is saved
    /// like a manual arrangement and dragging can carry on from it.
    static func sorted(_ items: [DrawerShortcut], by sort: Sort) -> [DrawerShortcut] {
        let current = items.sorted { $0.order < $1.order }
        let ranked = current.enumerated().sorted { a, b in
            switch sort {
            case .name:
                let r = a.element.displayName.localizedStandardCompare(b.element.displayName)
                return r == .orderedSame ? a.offset < b.offset : r == .orderedAscending
            case .oldest, .newest:
                let x = a.element.addedAt ?? .distantPast, y = b.element.addedAt ?? .distantPast
                if x == y { return a.offset < b.offset }
                return sort == .oldest ? x < y : x > y
            }
        }
        return ranked.enumerated().map { i, pair in
            var s = pair.element; s.order = i; return s
        }
    }

    /// Where a tap goes. Shortcut/url-scheme/web-url open directly from the
    /// widget; an installed app must bounce through the app so it can use the
    /// private launch API, so it points back at our own scheme.
    var launchURL: URL? {
        switch kind {
        case let .urlScheme(s): return URL(string: s)
        case let .webURL(s): return URL(string: s)
        case let .shortcut(name):
            var c = URLComponents(string: "shortcuts://run-shortcut")
            c?.queryItems = [URLQueryItem(name: "name", value: name)]
            return c?.url
        case .installedApp:
            return URL(string: "islandtray://launch?item=\(id.uuidString)")
        }
    }

    /// SF Symbol fallback when no icon image is available.
    var symbolName: String {
        switch kind {
        case .installedApp: return "app.dashed"
        case .shortcut: return "square.stack.3d.up"
        case .urlScheme: return "link"
        case .webURL: return "globe"
        }
    }
}
