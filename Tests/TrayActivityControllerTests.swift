import ActivityKit
import XCTest
@testable import IslandTray

/// Only the state predicate is covered here. Everything else in
/// `TrayActivityController` needs a live ActivityKit:
/// `ActivityAuthorizationInfo().areActivitiesEnabled` is false in a test
/// bundle and `Activity.activities` is always empty, so `sync`/`start`/
/// `update`/`end`/`restart` cannot be driven down any branch that would fail.
final class TrayActivityControllerTests: XCTestCase {
    func testOnlyOnScreenStatesCountAsLive() {
        XCTAssertTrue(TrayActivityController.isLive(.active))
        XCTAssertTrue(
            TrayActivityController.isLive(.stale),
            "a stale activity is still on screen; treating it as gone would start a second island beside it"
        )
        XCTAssertFalse(
            TrayActivityController.isLive(.ended),
            "the activity ActivityKit ends after eight hours stays in the registry until dismissed, and updating it is a silent no-op"
        )
        XCTAssertFalse(TrayActivityController.isLive(.dismissed))
    }
}
