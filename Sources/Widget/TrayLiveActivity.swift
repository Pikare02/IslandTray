import ActivityKit
import SwiftUI
import WidgetKit

struct TrayLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrayActivityAttributes.self) { context in
            lockScreen(context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    // Weather only ever accompanies the empty-tray/drawer
                    // states, and `added` only ever accompanies a tray one,
                    // so the two never compete for this region.
                    if let w = context.state.weather, context.state.added == nil {
                        Text(w.dateText).font(.caption.bold()).lineLimit(1).padding(.leading, 4)
                    } else {
                        Label("\(context.state.count)", systemImage: "tray.full.fill")
                            .font(.caption.bold())
                            .padding(.leading, 4)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let added = context.state.added {
                        addedBadge(added)
                            .padding(.trailing, 4)
                    } else if let w = context.state.weather {
                        HStack(spacing: 2) {
                            Image(systemName: w.symbol)
                            Text(w.tempText).font(.caption.monospacedDigit())
                        }
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                    } else {
                        Text(L.s("tray.title"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // No ScrollView and no swipe: a widget receives no
                    // gestures at all. A button does run an intent, though,
                    // which is how a tray of more than four is paged through
                    // and how the drawer is switched to and from.
                    if context.state.view == .drawer, let slots = context.state.drawer {
                        HStack(spacing: 4) {
                            drawerToggleButton(systemImage: "chevron.left")
                            DrawerStrip(slots: slots, atlas: context.state.atlas, side: 44)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.top, 2)
                    } else {
                        HStack(spacing: 4) {
                            // On the first tray page, a left arrow has
                            // nowhere to go, so it becomes the drawer switch
                            // instead -- but only once the drawer has
                            // something to show.
                            if context.state.drawerAvailable && !context.state.hasPreviousPage {
                                drawerToggleButton(systemImage: "square.grid.2x2")
                            } else {
                                pageButton(.backward, enabled: context.state.hasPreviousPage)
                            }
                            TrayPreviewStrip(
                                previews: context.state.recent, atlas: context.state.atlas, side: 40
                            )
                            .frame(maxWidth: .infinity)
                            pageButton(.forward, enabled: context.state.hasNextPage)
                        }
                        .padding(.top, 2)
                    }
                }
            } compactLeading: {
                if let w = context.state.weather {
                    Text(w.dateText).font(.caption2.bold()).lineLimit(1)
                } else {
                    Image(systemName: context.state.added == nil ? "tray.full.fill" : "checkmark.circle.fill")
                        .foregroundStyle(context.state.added == nil ? Color.primary : Color.green)
                }
            } compactTrailing: {
                if let w = context.state.weather {
                    HStack(spacing: 2) {
                        Image(systemName: w.symbol)
                        Text(w.tempText).font(.caption.monospacedDigit())
                    }
                } else {
                    Text("\(context.state.count)")
                        .font(.caption.monospacedDigit())
                }
            } minimal: {
                Text("\(context.state.count)")
                    .font(.caption2.monospacedDigit())
            }
            .widgetURL(TrayIDs.dropURL)
        }
    }

    /// The check a shortcut's add is answered with, instead of a dialog.
    private func addedBadge(_ added: TrayContentState.Added) -> some View {
        Label(
            added.board == .clipboard ? L.s("island.added.clipboard") : L.s("island.added", added.count),
            systemImage: "checkmark.circle.fill"
        )
        .font(.caption.bold())
        .foregroundStyle(.green)
        .lineLimit(1)
    }

    private enum Direction {
        case backward
        case forward
    }

    /// Always laid out, only tappable when there is somewhere to go: a button
    /// that appears and disappears would shift the strip sideways every time
    /// the end of the tray is reached.
    private func pageButton(_ direction: Direction, enabled: Bool) -> some View {
        Button(intent: TrayPageIntent(delta: direction == .forward ? 1 : -1)) {
            Image(systemName: direction == .forward ? "chevron.right" : "chevron.left")
                .font(.footnote.bold())
                .foregroundStyle(.white.opacity(enabled ? 0.8 : 0.15))
                .frame(width: 18, height: 40)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// Same footprint and look as `pageButton`, wired to `ToggleDrawerIntent`
    /// instead: the grid icon on the tray's first page, and the back chevron
    /// inside the drawer.
    private func drawerToggleButton(systemImage: String) -> some View {
        Button(intent: ToggleDrawerIntent()) {
            Image(systemName: systemImage)
                .font(.footnote.bold())
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 18, height: 40)
        }
        .buttonStyle(.plain)
    }

    private func lockScreen(_ state: TrayContentState) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.full.fill")
                .font(.title3)
            VStack(alignment: .leading, spacing: 6) {
                if let added = state.added {
                    addedBadge(added)
                } else {
                    Text(L.s("island.count", state.count))
                        .font(.subheadline.bold())
                }
                TrayPreviewStrip(previews: state.recent, atlas: state.atlas, side: 32)
            }
            Spacer()
        }
        .padding(14)
        .activityBackgroundTint(Color.black.opacity(0.45))
        // Devices without a Dynamic Island only ever show this presentation,
        // so without its own widgetURL the drop deep link never fires there.
        .widgetURL(TrayIDs.dropURL)
    }
}
