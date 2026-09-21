import XCTest
@testable import IslandTray

final class UpdateCheckerTests: XCTestCase {
    func testComparesVersionsNumerically() {
        XCTAssertTrue(UpdateChecker.isNewer("v1.1.0", than: "1.0.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.10.0", than: "1.9.2"))
        XCTAssertTrue(UpdateChecker.isNewer("v2", than: "1.9.9"))
        XCTAssertFalse(UpdateChecker.isNewer("v1.0.0", than: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0", than: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer("v0.9.9", than: "1.0.0"))
    }
}
