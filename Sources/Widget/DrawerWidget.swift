import SwiftUI
import WidgetKit

/// The island's app drawer on the Home Screen and the Lock Screen, drawn
/// from `DrawerSnapshot` -- whatever the Live Activity was last given.
///
/// Every family but the circular one is a grid of square tiles filled from
/// the top left (`DrawerWidgetLayout`), as many as the drawer has, up to
/// the count chosen in the widget's settings. A tap opens the slot's
/// target: directly, through a `Link`, on the medium widget; through
/// `LaunchDrawerSlotIntent` and the app on the small widget and the Lock
/// Screen rectangle, where WidgetKit allows no `Link`. The circular Lock
/// Screen widget is only a launcher glyph for the app's drawer.
struct DrawerWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: DrawerSnapshot.widgetKind, intent: DrawerWidgetConfigurationIntent.self, provider: Provider()
        ) { entry in
            DrawerWidgetView(payload: entry.payload, count: entry.count)
        }
        .configurationDisplayName(L.s("widget.drawer.name"))
        .description(L.s("widget.drawer.desc"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }

    struct Entry: TimelineEntry {
        let date: Date
        let payload: DrawerSnapshot.Payload?
        /// From the widget's settings: how many icons to show.
        let count: Int
    }

    struct Provider: AppIntentTimelineProvider {
        private static let placeholderPayload = DrawerSnapshot.Payload(
            slots: (0..<4).map { _ in .init(symbol: "app.fill", name: "", launch: "", hasIcon: false) },
            atlas: nil, atlasOffset: 0
        )

        func placeholder(in context: Context) -> Entry {
            Entry(date: .now, payload: Self.placeholderPayload, count: TrayContentState.maxSlots)
        }

        func snapshot(for configuration: DrawerWidgetConfigurationIntent, in context: Context) async -> Entry {
            context.isPreview
                ? placeholder(in: context)
                : Entry(date: .now, payload: DrawerSnapshot.load(), count: configuration.count)
        }

        /// `.never`: the snapshot is rewritten by the Live Activity, and that
        /// write is what reloads this timeline.
        func timeline(for configuration: DrawerWidgetConfigurationIntent, in context: Context) async -> Timeline<Entry> {
            Timeline(entries: [Entry(date: .now, payload: DrawerSnapshot.load(), count: configuration.count)], policy: .never)
        }
    }
}

struct DrawerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let payload: DrawerSnapshot.Payload?
    let count: Int

    private var isAccessory: Bool {
        family == .accessoryRectangular || family == .accessoryCircular
    }

    var body: some View {
        Group {
            if family == .accessoryCircular {
                launcherGlyph
            } else if let payload, !payload.slots.isEmpty {
                grid(payload)
            } else {
                empty
            }
        }
        // The Home Screen tile is always near-black, so resolve `.secondary`
        // and `.primary` against dark even in Light appearance.
        .environment(\.colorScheme, isAccessory ? colorScheme : .dark)
        // The Lock Screen draws its own vibrant material behind accessories;
        // the Home Screen gets the island's black.
        .containerBackground(for: .widget) {
            if isAccessory { Color.clear } else { Color.black.opacity(0.85) }
        }
    }

    private var launcherGlyph: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "square.grid.2x2.fill").font(.title3)
        }
        .widgetURL(TrayIDs.drawerURL)
    }

    /// Square tiles from the top left, no names. The widget is a fixed
    /// box, so a tile's width is the column's and `aspectRatio` makes its
    /// height match; rows that are not filled stay at the top.
    private func grid(_ payload: DrawerSnapshot.Payload) -> some View {
        let tiles = AtlasSlicer.tiles(payload.atlas)
        let shown = Array(DrawerWidgetLayout.shown(payload.slots, count: count, family: family).enumerated())
        let columns = DrawerWidgetLayout.columns(for: family)
        return VStack(spacing: 0) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
                ForEach(shown, id: \.offset) { index, slot in
                    tap(slot) {
                        Color.white.opacity(0.08)
                            .aspectRatio(1, contentMode: .fit)
                            .overlay { DrawerIcon(slot: slot, index: index, tiles: tiles, atlasOffset: payload.atlasOffset) }
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        // Where a tile's button is not honoured (a Lock Screen that takes no
        // widget buttons), the tap falls through to the app's drawer.
        .widgetURL(TrayIDs.drawerURL)
    }

    /// The tile's tap: a `Link` where the family allows one, otherwise a
    /// button that runs the launch through the app. A slot with nothing to
    /// open (the gallery placeholder) is just the tile.
    @ViewBuilder private func tap<Tile: View>(
        _ slot: TrayContentState.DrawerSlot, @ViewBuilder tile: () -> Tile
    ) -> some View {
        if slot.launch.isEmpty {
            tile()
        } else if family == .systemMedium, let url = URL(string: slot.launch) {
            Link(destination: url) { tile() }
        } else {
            Button(intent: LaunchDrawerSlotIntent(launch: slot.launch)) { tile() }
                .buttonStyle(.plain)
        }
    }

    private var empty: some View {
        Text(L.s("widget.drawer.empty"))
            .font(.caption)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .widgetURL(TrayIDs.drawerURL)
    }
}
