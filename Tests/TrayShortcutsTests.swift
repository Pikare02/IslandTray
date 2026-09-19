import AppIntents
import XCTest
@testable import IslandTray

/// `AppShortcut` exposes no public getters at all -- `phrases`, `shortTitle`
/// and `systemImageName` are write-only from a test's perspective, so the
/// only fact about `TrayShortcuts.appShortcuts` a unit test can pin is its
/// shape: exactly one shortcut, wired to the refresh intent. The phrase
/// wording and icon are visible only by launching the Shortcuts app, which
/// step 5 of the task brief hands to the user as a manual check.
final class TrayShortcutsTests: XCTestCase {
    func testExposesExactlyOneShortcut() {
        XCTAssertEqual(TrayShortcuts.appShortcuts.count, 1)
    }
}
