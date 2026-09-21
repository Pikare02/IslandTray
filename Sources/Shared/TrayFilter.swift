import Foundation

/// What a board or the search screen is currently showing out of everything
/// it could.
///
/// A value with a pure `apply`, like `TrayOrdering`: the part that decides
/// which items a person sees is the part worth pinning, and none of it needs
/// a view to run.
struct TrayFilter: Equatable {
    /// How recently an item was added, as a coarse window rather than a date
    /// range -- "today" and "this week" are what someone looking for
    /// something they just put down actually wants.
    enum Window: String, CaseIterable, Equatable {
        case day
        case week
        case month

        var seconds: TimeInterval {
            switch self {
            case .day: return 60 * 60 * 24
            case .week: return 60 * 60 * 24 * 7
            case .month: return 60 * 60 * 24 * 30
            }
        }
    }

    var text = ""
    /// Empty means every kind, not no kind.
    var kinds: Set<TrayItemKind> = []
    var window: Window?

    /// Whether anything is being filtered out, which is what the funnel in
    /// the toolbar colours itself by.
    var isActive: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty || !kinds.isEmpty || window != nil
    }

    func apply(to items: [TrayItem], now: Date = Date()) -> [TrayItem] {
        guard isActive else { return items }
        return items.filter { matches($0, now: now) }
    }

    func matches(_ item: TrayItem, now: Date = Date()) -> Bool {
        let query = text.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            // localizedStandardContains: case- and diacritic-insensitive, and
            // right for Japanese too, where a plain `contains` would miss a
            // half-width match.
            guard item.name.localizedStandardContains(query) else { return false }
        }
        if !kinds.isEmpty {
            guard kinds.contains(TrayItemKind(uti: item.uti)) else { return false }
        }
        if let window {
            // Items dated in the future (a clock change, a restored backup)
            // count as recent rather than being hidden by a window they are
            // past the end of.
            guard now.timeIntervalSince(item.addedAt) <= window.seconds else { return false }
        }
        return true
    }
}
