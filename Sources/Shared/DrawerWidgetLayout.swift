import WidgetKit

/// How the drawer widget lays its tiles out: a grid of squares, filled from
/// the top left with as many slots as there are, up to what the family
/// holds and what the person asked for in the widget's settings.
enum DrawerWidgetLayout {
    /// Square tiles per row.
    static func columns(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 5
        case .accessoryRectangular: return 4
        default: return 1
        }
    }

    /// The most tiles the family shows: a 3x3 on the small widget, two rows
    /// of five on the medium one capped at the drawer's own nine, and a
    /// single row of four on the Lock Screen rectangle.
    static func capacity(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall, .systemMedium: return TrayContentState.maxSlots
        case .accessoryRectangular: return 4
        default: return 1
        }
    }

    /// The slots to draw, from the first: no more than `count` (the
    /// widget's setting) and no more than the family's capacity.
    static func shown(
        _ slots: [TrayContentState.DrawerSlot], count: Int, family: WidgetFamily
    ) -> [TrayContentState.DrawerSlot] {
        Array(slots.prefix(max(0, min(count, capacity(for: family)))))
    }
}
