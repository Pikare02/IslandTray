import SwiftUI

@main
struct IslandTrayApp: App {
    @Environment(\.scenePhase) private var scenePhase
    /// At the window, not on a view inside it, so sheets and the preview
    /// inherit the choice rather than each having to be told.
    @AppStorage("theme", store: TraySettings.store) private var theme = ""

    var body: some Scene {
        WindowGroup {
            TrayView()
                .preferredColorScheme(Self.scheme(theme))
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

    /// `nil` means "whatever the device is set to", which is what SwiftUI
    /// already does when no scheme is given.
    private static func scheme(_ theme: String) -> ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
