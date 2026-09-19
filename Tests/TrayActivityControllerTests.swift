import ActivityKit
import XCTest
@testable import IslandTray

/// Only the state predicate is covered here. Everything else in
/// `TrayActivityController` needs a live ActivityKit.
///
/// Note that `ActivityAuthorizationInfo().areActivitiesEnabled` is **true**
/// in this test host, not false -- an earlier version of this comment claimed
/// the opposite and cost a round of work: a test was built on the assumption
/// that `restart()` would stop at that guard, and it sailed past it instead.
/// What actually blocks the rest is `Activity.activities` always being empty
/// and `Activity.request` never producing a real activity, so `sync`/`start`/
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
