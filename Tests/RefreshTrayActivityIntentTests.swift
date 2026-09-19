import AppIntents
import XCTest
@testable import IslandTray

/// `RefreshTrayActivityIntent`'s job hinges on what a unit test can actually
/// pin: its static metadata, which Shortcuts reads without ever running the
/// intent. `perform()`'s only real logic -- calling
/// `TrayActivityController.shared.restart()` -- is deliberately left
/// unpinned here. Its only observable effect is `lastError`, and what value
/// that ends up holding after a real call depends on
/// `ActivityAuthorizationInfo().areActivitiesEnabled` -- verified empirically
/// (by running this suite) to be `true` in this test bundle, not `false` as
/// `TrayActivityControllerTests`'s doc comment assumes -- and on whatever
/// `TrayStore.shared`'s on-disk container already holds. Both are real,
/// unmocked state this test cannot control, so no assertion on `lastError`
/// here would be a pin rather than a coin flip. Everything else -- whether
/// the system truly grants background Live Activity permission, whether
/// Shortcuts indexes the phrases -- needs a real device and is out of reach
/// too.
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
        // SetupGuideView's step 5 interpolates this exact property (see
        // SetupGuideView.swift), so the two cannot drift apart by
        // construction; this only pins the title's own text against an
        // accidental edit.
        XCTAssertEqual(RefreshTrayActivityIntent.title, "トレイの表示を更新")
    }

    func testDescriptionExplainsTheEightHourCadence() {
        XCTAssertEqual(
            RefreshTrayActivityIntent.description.descriptionText,
            "ダイナミックアイランドのトレイ表示を作り直します。8 時間ごとに実行すると表示が途切れません。"
        )
    }
}
