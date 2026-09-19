import AppIntents

/// Recreates the Live Activity so its eight-hour window restarts.
///
/// Conforming to LiveActivityIntent is what makes this work from the
/// background: the system launches the app's process without opening the app,
/// runs perform(), and grants permission to start a Live Activity. A Shortcuts
/// time-of-day automation calling this three times a day keeps the tray visible
/// around the clock.
struct RefreshTrayActivityIntent: AppIntent, LiveActivityIntent {
    // `let`, not `var`: all three requirements below are get-only in the
    // `AppIntent` protocol, and Swift 6 strict concurrency flags a mutable
    // static as global shared state that isn't provably Sendable-safe. A
    // constant sidesteps that without an escape hatch, and nothing here is
    // ever meant to change at runtime anyway.
    static let title: LocalizedStringResource = "トレイの表示を更新"
    static let description = IntentDescription(
        "ダイナミックアイランドのトレイ表示を作り直します。8 時間ごとに実行すると表示が途切れません。"
    )
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        await TrayActivityController.shared.restart()
        return .result()
    }
}
