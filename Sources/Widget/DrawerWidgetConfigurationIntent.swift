import AppIntents
import WidgetKit

/// What the drawer widget's edit sheet (long-press, Edit Widget) offers:
/// how many of the drawer's icons to show.
struct DrawerWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "widget.drawer.name"
    static let description = IntentDescription("widget.drawer.desc")

    /// 1...9: the drawer's own maximum. The family's capacity caps it again
    /// at draw time (`DrawerWidgetLayout`), so nine on the Lock Screen
    /// rectangle still means four.
    @Parameter(title: "widget.count.title", default: 9, inclusiveRange: (1, 9))
    var count: Int
}
