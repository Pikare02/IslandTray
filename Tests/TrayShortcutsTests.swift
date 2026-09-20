import AppIntents
import XCTest
@testable import IslandTray

/// `AppShortcut` exposes no public getters at all -- `phrases`, `shortTitle`
/// and `systemImageName` are write-only from a test's perspective, so the
/// only fact about `TrayShortcuts.appShortcuts` a unit test can pin is its
/// shape. The phrase wording and icon are visible only by launching the
/// Shortcuts app.
final class TrayShortcutsTests: XCTestCase {
    /// Both of them, and the count is what the user's setup instructions
    /// depend on: the refresh action the automation calls, and the add action
    /// a share-sheet shortcut is built from. Losing either silently breaks a
    /// documented setup step rather than the app.
    func testExposesTheRefreshAndTheTwoAddShortcuts() {
        XCTAssertEqual(TrayShortcuts.appShortcuts.count, 3)
    }

    /// The add intent is the whole free-account route back into the share
    /// sheet, and it only works if it takes files and does not open the app.
    func testAddingRunsWithoutOpeningTheApp() {
        XCTAssertFalse(AddToTrayIntent.openAppWhenRun)
        XCTAssertFalse(AddToClipboardIntent.openAppWhenRun)
    }

    // No test reads `AddToTrayIntent().files`: an `@Parameter` that nothing
    // has filled in traps inside AppIntents rather than answering empty, and
    // that trap takes the whole test host down with it.
}
