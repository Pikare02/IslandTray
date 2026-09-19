import AppIntents
import XCTest
@testable import IslandTray

/// `RefreshTrayActivityIntent`'s job hinges on two things a unit test can
/// actually pin: its static metadata (what Shortcuts reads without ever
/// running the intent) and `perform()`'s return-type contract. Everything
/// else -- whether the system truly grants background Live Activity
/// permission, whether Shortcuts indexes the phrases -- needs a real device
/// and is out of reach here.
final class RefreshTrayActivityIntentTests: XCTestCase {
    /// The entire point of conforming to `LiveActivityIntent` is running from
    /// the background without opening the app. `openAppWhenRun = true` would
    /// silently defeat that -- the automation would try to foreground the app
    /// instead of running headless -- so this is the one flag most worth
    /// pinning here.
    func testDoesNotOpenTheAppWhenRun() {
        XCTAssertFalse(RefreshTrayActivityIntent.openAppWhenRun)
    }

    func testTitleMatchesTheSetupGuidesWording() {
        // SetupGuideView's step 5 tells the user to pick this exact action
        // name in the Shortcuts action list; the two must stay in sync.
        XCTAssertEqual(RefreshTrayActivityIntent.title, "トレイの表示を更新")
    }

    func testDescriptionExplainsTheEightHourCadence() {
        XCTAssertEqual(
            RefreshTrayActivityIntent.description.descriptionText,
            "ダイナミックアイランドのトレイ表示を作り直します。8 時間ごとに実行すると表示が途切れません。"
        )
    }

    /// `perform()` must be callable and return normally. `TrayActivityController
    /// .restart()` guards on `ActivityAuthorizationInfo().areActivitiesEnabled`,
    /// which is false in a test bundle (see `TrayActivityControllerTests`), so
    /// this exercises the intent's plumbing down to that guard without ever
    /// touching real ActivityKit state.
    func testPerformReturnsWithoutThrowing() async throws {
        _ = try await RefreshTrayActivityIntent().perform()
    }
}
