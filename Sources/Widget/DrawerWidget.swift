import SwiftUI
import WidgetKit

/// The island's app drawer on the Home Screen and the Lock Screen, drawn
/// from `DrawerSnapshot` -- whatever the Live Activity was last given.
///
/// Medium is the island's own row: six tiles, each a `Link`. Small and the
/// Lock Screen families take a single tap target (WidgetKit allows no
/// `Link` there), so they show the first icons and open the app's drawer.
struct DrawerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: DrawerSnapshot.widgetKind, provider: Provider()) { entry in
            DrawerWidgetView(payload: entry.payload)
        }
        .configurationDisplayName(L.s("widget.drawer.name"))
        .description(L.s("widget.drawer.desc"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }

    struct Entry: TimelineEntry {
        let date: Date
        let payload: DrawerSnapshot.Payload?
    }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry {
            Entry(date: .now, payload: .init(
                slots: (0..<4).map { _ in .init(symbol: "app.fill", name: "", launch: "", hasIcon: false) },
                atlas: nil, atlasOffset: 0
            ))
        }

        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            completion(context.isPreview ? placeholder(in: context) : Entry(date: .now, payload: DrawerSnapshot.load()))
        }

        /// `.never`: the snapshot is rewritten by the Live Activity, and that
        /// write is what reloads this timeline.
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            completion(Timeline(entries: [Entry(date: .now, payload: DrawerSnapshot.load())], policy: .never))
        }
    }
}

struct DrawerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let payload: DrawerSnapshot.Payload?

    private var isAccessory: Bool {
        family == .accessoryRectangular || family == .accessoryCircular
    }

    var body: some View {
        Group {
            if let payload, !payload.slots.isEmpty {
                content(payload)
            } else {
                empty
            }
        }
        // The Lock Screen draws its own vibrant material behind accessories;
        // the Home Screen gets the island's black.
        .containerBackground(for: .widget) {
            if isAccessory { Color.clear } else { Color.black.opacity(0.85) }
        }
    }

    @ViewBuilder private func content(_ payload: DrawerSnapshot.Payload) -> some View {
        switch family {
        case .systemMedium:
            DrawerStrip(slots: payload.slots, atlas: payload.atlas, side: 56, atlasOffset: payload.atlasOffset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "square.grid.2x2.fill").font(.title3)
            }
            .widgetURL(TrayIDs.drawerURL)
        default:
            grid(payload, columns: family == .systemSmall ? 2 : 4)
                .widgetURL(TrayIDs.drawerURL)
        }
    }

    /// The first four slots as tiles with no names: a glance, and one tap
    /// into the full drawer.
    private func grid(_ payload: DrawerSnapshot.Payload, columns: Int) -> some View {
        let tiles = AtlasSlicer.tiles(payload.atlas)
        let shown = Array(payload.slots.prefix(4).enumerated())
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
            ForEach(shown, id: \.offset) { index, slot in
                Color.white.opacity(0.08)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { DrawerIcon(slot: slot, index: index, tiles: tiles, atlasOffset: payload.atlasOffset) }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
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
