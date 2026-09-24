import UserNotifications

/// Delivers ONE system (local) notification when an important update is
/// available and the "important update" setting is on. The app has no push
/// backend, so this is a locally-scheduled notification fired when the app's
/// launch-time update check finds a newer important release. Once per
/// version: `TraySettings.notifiedUpdateVersion` is the high-water mark.
enum UpdateNotifier {
    static let categoryID = "importantUpdate"

    /// Pure decision, unit-tested. Notify only for a NEW important version
    /// while the toggle is on.
    static func shouldNotify(update: UpdateChecker.Update, enabled: Bool, lastNotified: String?) -> Bool {
        update.isImportant && enabled && update.version != lastNotified
    }

    static func notifyIfNeeded(_ update: UpdateChecker.Update) async {
        let settings = TraySettings()
        guard shouldNotify(update: update,
                           enabled: settings.insistsOnImportantUpdates,
                           lastNotified: settings.notifiedUpdateVersion) else { return }

        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return } // denied: fall back to the in-app prompt only

        let content = UNMutableNotificationContent()
        content.title = L.s("update.notify.title")
        content.body = L.s("update.notify.body", update.version)
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "\(categoryID).\(update.version)", content: content, trigger: nil
        )
        try? await center.add(request)
        // Mark done only after a successful schedule attempt, so a denied or
        // failed add can still notify on a later launch.
        settings.notifiedUpdateVersion = update.version
    }
}
