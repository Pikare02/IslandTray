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

    func testInsistingDecidesWhetherAnImportantUpdateCanBeSkipped() {
        let important = UpdateChecker.Update(version: "2.0.0", isImportant: true)
        let ordinary = UpdateChecker.Update(version: "1.5.0", isImportant: false)
        XCTAssertFalse(UpdateChecker.isSkippable(important, insisting: true))
        XCTAssertTrue(UpdateChecker.isSkippable(important, insisting: false))
        XCTAssertTrue(UpdateChecker.isSkippable(ordinary, insisting: true))

        XCTAssertTrue(UpdateChecker.shouldOffer(important, skipped: "2.0.0", insisting: true))
        XCTAssertFalse(UpdateChecker.shouldOffer(important, skipped: "2.0.0", insisting: false))
        XCTAssertTrue(UpdateChecker.shouldOffer(important, skipped: nil, insisting: false))
        XCTAssertFalse(UpdateChecker.shouldOffer(ordinary, skipped: "1.5.0", insisting: true))
    }
}
