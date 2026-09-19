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
                    Text("トレイ")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // No ScrollView: widget views cannot receive gestures, so the
                    // full swipeable list lives in the app.
                    TrayPreviewStrip(previews: context.state.recent, side: 40)
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

    private func lockScreen(_ state: TrayContentState) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.full.fill")
                .font(.title3)
            VStack(alignment: .leading, spacing: 6) {
                Text("トレイに \(state.count) 件")
                    .font(.subheadline.bold())
                TrayPreviewStrip(previews: state.recent, side: 32)
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
