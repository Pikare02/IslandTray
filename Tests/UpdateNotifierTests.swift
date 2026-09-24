import XCTest
@testable import IslandTray

final class UpdateNotifierTests: XCTestCase {
    private func update(_ v: String, important: Bool) -> UpdateChecker.Update {
        UpdateChecker.Update(version: v, isImportant: important)
    }
    func testNotifiesForNewImportantWhenEnabled() {
        XCTAssertTrue(UpdateNotifier.shouldNotify(update: update("1.7.0", important: true),
                                                  enabled: true, lastNotified: nil))
    }
    func testNotWhenDisabled() {
        XCTAssertFalse(UpdateNotifier.shouldNotify(update: update("1.7.0", important: true),
                                                   enabled: false, lastNotified: nil))
    }
    func testNotWhenNotImportant() {
        XCTAssertFalse(UpdateNotifier.shouldNotify(update: update("1.7.0", important: false),
                                                   enabled: true, lastNotified: nil))
    }
    func testNotWhenAlreadyNotifiedSameVersion() {
        XCTAssertFalse(UpdateNotifier.shouldNotify(update: update("1.7.0", important: true),
                                                   enabled: true, lastNotified: "1.7.0"))
    }
    func testNotifiesAgainForNewerVersion() {
        XCTAssertTrue(UpdateNotifier.shouldNotify(update: update("1.8.0", important: true),
                                                  enabled: true, lastNotified: "1.7.0"))
    }
}
