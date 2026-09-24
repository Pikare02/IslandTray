import AppIntents

/// Flips the island between the tray strip and the app drawer. Wired to the
/// left arrow on the first tray page; like `TrayPageIntent`, it runs in the
/// app process and updates the live activity.
struct ToggleDrawerIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "トレイとアプリドロワーを切り替え"
    static let openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        await TrayActivityController.shared.toggleDrawer()
        return .result()
    }
}
