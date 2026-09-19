import SwiftUI

@main
struct IslandTrayApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TrayView()
                .onOpenURL { _ in
                    // The Live Activity's only deep link brings the tray forward
                    // so a drag in flight can be dropped. Nothing else to do.
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Restart the Live Activity whenever the app comes forward, so the
            // eight-hour window resets even if the Shortcuts automation missed.
            if phase == .active {
                Task { await TrayActivityController.shared.restart() }
            }
        }
    }
}
