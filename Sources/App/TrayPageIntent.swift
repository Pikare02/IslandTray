import AppIntents

/// Moves the island's preview strip to the next or previous run of items.
///
/// A widget receives no gestures -- no scrolling, no swiping -- so this is the
/// only way to see past the four the island has room for. A button in a Live
/// Activity runs an intent, and `LiveActivityIntent` is what lets that intent
/// run in the app's process, in the background, and update the activity.
struct TrayPageIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "トレイの表示をめくる"
    static let openAppWhenRun: Bool = false

    /// -1 or 1. A parameter rather than two intents so the widget's two
    /// buttons are one thing with a direction.
    @Parameter(title: "方向")
    var delta: Int

    init() {}

    init(delta: Int) {
        self.delta = delta
    }

    func perform() async throws -> some IntentResult {
        await TrayActivityController.shared.turnPage(by: delta)
        return .result()
    }
}
