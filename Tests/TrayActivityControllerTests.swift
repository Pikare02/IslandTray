import ActivityKit
import XCTest
@testable import IslandTray

/// Only the state predicate is covered here -- but that is a historical
/// accident, not a limit of the test host. Two claims in earlier versions of
/// this comment were both wrong, and each cost a round of work:
///
/// - "`areActivitiesEnabled` is false here." It is **true**. A test was built
///   expecting `restart()` to stop at that guard; it sailed past instead.
/// - "`Activity.request` never produces a real activity here." It **does** --
///   a request adds an observable entry to `Activity.activities`, shown
///   causally by mutation-testing the migration's resync path, not inferred.
///
/// So more of `sync`/`start`/`update`/`end`/`restart` is reachable from a test
/// than is currently pinned. Before adding one, verify what the API actually
/// does in this host rather than trusting a comment -- including this one.
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

    // MARK: - syncDecision

    func testEmptyTrayWithShowWhenEmptyOnStaysUp() {
        XCTAssertEqual(
            TrayActivityController.syncDecision(itemCount: 0, showActivityWhenEmpty: true),
            .show
        )
    }

    func testEmptyTrayWithShowWhenEmptyOffEnds() {
        XCTAssertEqual(
            TrayActivityController.syncDecision(itemCount: 0, showActivityWhenEmpty: false),
            .end
        )
    }

    func testNonEmptyTrayAlwaysShowsRegardlessOfSetting() {
        XCTAssertEqual(
            TrayActivityController.syncDecision(itemCount: 3, showActivityWhenEmpty: true),
            .show
        )
        XCTAssertEqual(
            TrayActivityController.syncDecision(itemCount: 3, showActivityWhenEmpty: false),
            .show,
            "a non-empty tray must show even if the empty-tray setting is off"
        )
    }
}
