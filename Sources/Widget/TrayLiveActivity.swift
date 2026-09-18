import ActivityKit
import SwiftUI
import WidgetKit

struct TrayLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrayActivityAttributes.self) { context in
            HStack {
                Image(systemName: "tray.full.fill")
                Text("\(context.state.count) items")
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text("\(context.state.count) items")
                }
            } compactLeading: {
                Image(systemName: "tray.full.fill")
            } compactTrailing: {
                Text("\(context.state.count)")
            } minimal: {
                Text("\(context.state.count)")
            }
            .widgetURL(TrayIDs.dropURL)
        }
    }
}
