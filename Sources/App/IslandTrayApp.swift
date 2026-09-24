import BackgroundTasks
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
                    case .open(let id):
                        NotificationCenter.default.post(name: .openTrayItem, object: id)
                    case .external(let url):
                        UIApplication.shared.open(url)
                    case .drop:
                        // The tray face of the island (or a drop) lands on the tray tab.
                        NotificationCenter.default.post(name: .openTray, object: nil)
                    case .ignore:
                        break
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Restart the Live Activity whenever the app comes forward, so the
            // eight-hour window resets even if the Shortcuts automation missed.
            if phase == .active {
                Task { await TrayActivityController.shared.restart() }
            } else if phase == .background {
                // Queue the hourly weather refresh; iOS decides the exact time.
                Self.scheduleWeatherRefresh()
            }
        }
        // Wakes the app roughly hourly to refresh the island's temperature
        // without the app being opened. iOS throttles this by usage, so the
        // hour is a floor, not a guarantee. Auto-location may fail in the
        // background (when-in-use); a pinned location always resolves.
        .backgroundTask(.appRefresh(Self.weatherRefreshID)) {
            await TrayActivityController.shared.syncFromStore()
            Self.scheduleWeatherRefresh()
        }
    }

    static let weatherRefreshID = "com.pikare.islandtray.weather"

    /// Submits the next hourly refresh. Replaces any pending one with the same
    /// identifier, so calling it on every background transition is safe.
    /// `nonisolated` so the `@Sendable` background-task closure can call it.
    nonisolated static func scheduleWeatherRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: weatherRefreshID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)
        try? BGTaskScheduler.shared.submit(request)
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
