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

    func testAMajorVersionIsImportant() {
        XCTAssertTrue(UpdateChecker.update(tag: "v2.0.0", notes: "New look", local: "1.3.1").isImportant)
        XCTAssertFalse(UpdateChecker.update(tag: "v1.4.0", notes: "New look", local: "1.3.1").isImportant)
    }

    func testNotesCanMarkAPatchUrgent() {
        let urgent = UpdateChecker.update(tag: "v1.3.2", notes: "[urgent] fixes data loss", local: "1.3.1")
        XCTAssertTrue(urgent.isImportant)
        XCTAssertEqual(urgent.version, "1.3.2")
        XCTAssertFalse(UpdateChecker.update(tag: "v1.3.2", notes: nil, local: "1.3.1").isImportant)
    }
}
