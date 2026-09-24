import SwiftUI
import UserNotifications

/// Lets the important-update notification's banner show even though the
/// launch-time check that schedules it runs while the app is foreground --
/// without this, UNUserNotificationCenter suppresses a foreground banner.
final class NotificationForeground: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }
}

@main
struct IslandTrayApp: App {
    @Environment(\.scenePhase) private var scenePhase
    /// At the window, not on a view inside it, so sheets and the preview
    /// inherit the choice rather than each having to be told.
    @AppStorage("theme", store: TraySettings.store) private var theme = ""
    /// Held so it isn't deallocated the instant `init()` returns -- the
    /// delegate property on `UNUserNotificationCenter` is weak.
    private let notificationForeground = NotificationForeground()

    init() {
        UNUserNotificationCenter.current().delegate = notificationForeground
    }

    var body: some Scene {
        WindowGroup {
            TrayView()
                .preferredColorScheme(Self.scheme(theme))
                .onOpenURL { url in
                    switch LaunchRouter.route(url) {
                    case .drawer:
                        NotificationCenter.default.post(name: .openDrawer, object: nil)
                    case .launch(let id):
                        LaunchRouter.performLaunch(id)
                    case .external(let url):
                        UIApplication.shared.open(url)
                    case .drop, .ignore:
                        // drop just needs the app foregrounded, which already happened;
                        // ignore covers unknown/malformed links.
                        break
                    }
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
