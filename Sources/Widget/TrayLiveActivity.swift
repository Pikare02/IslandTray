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
                    Label("\(context.state.count)", systemImage: "tray.full.fill")
                        .font(.caption.bold())
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(L.s("tray.title"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // No ScrollView and no swipe: a widget receives no
                    // gestures at all. A button does run an intent, though,
                    // which is how a tray of more than four is paged through.
                    HStack(spacing: 4) {
                        pageButton(.backward, enabled: context.state.hasPreviousPage)
                        TrayPreviewStrip(
                            previews: context.state.recent, atlas: context.state.atlas, side: 40
                        )
                        .frame(maxWidth: .infinity)
                        pageButton(.forward, enabled: context.state.hasNextPage)
                    }
                    .padding(.top, 2)
                }
            } compactLeading: {
                Image(systemName: "tray.full.fill")
            } compactTrailing: {
                Text("\(context.state.count)")
                    .font(.caption.monospacedDigit())
            } minimal: {
                Text("\(context.state.count)")
                    .font(.caption2.monospacedDigit())
            }
            .widgetURL(TrayIDs.dropURL)
        }
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

    private func lockScreen(_ state: TrayContentState) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.full.fill")
                .font(.title3)
            VStack(alignment: .leading, spacing: 6) {
                Text(L.s("island.count", state.count))
                    .font(.subheadline.bold())
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
