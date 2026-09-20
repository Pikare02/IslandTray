import XCTest
@testable import IslandTray

/// The bookmark path is all there is: photos are copies, and a photo origin
/// only appears on items written by the builds that tried to delete them.
final class OriginalRemoverTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testTheBookmarkedFileIsDeleted() throws {
        let original = root.appendingPathComponent("original.txt")
        try Data("hello".utf8).write(to: original)
        let bookmark = try original.bookmarkData()

        let outcome = OriginalRemover.remove(.file(bookmark: bookmark))

        XCTAssertEqual(outcome, .removed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
    }

    func testAnUnresolvableBookmarkIsReportedRatherThanIgnored() {
        // The tray copy is removed either way; the user has to be told their
        // original is still sitting there.
        let outcome = OriginalRemover.remove(.file(bookmark: Data([0x00, 0x01, 0x02])))
        guard case .failed(let reason) = outcome else { return XCTFail("got \(outcome)") }
        XCTAssertTrue(reason.contains("file:"), "the reason names the step that refused: \(reason)")
    }

    func testAFileThatIsAlreadyGoneIsNotReportedAsDeleted() throws {
        let original = root.appendingPathComponent("original.txt")
        try Data("hello".utf8).write(to: original)
        let bookmark = try original.bookmarkData()
        try FileManager.default.removeItem(at: original)

        let outcome = OriginalRemover.remove(.file(bookmark: bookmark))

        guard case .failed(let reason) = outcome else { return XCTFail("got \(outcome)") }
        XCTAssertTrue(reason.contains("file:"), "the reason names the step that refused: \(reason)")
    }


    func testALegacyPhotoOriginIsRefused() {
        // Items from the builds that recorded a photo origin are still in
        // people's trays. Nothing in the library may be touched for them.
        let outcome = OriginalRemover.remove(.photo(localIdentifier: "ABC-123/L0/001"))
        XCTAssertEqual(outcome, .failed("photo: コピー扱い"))
    }
}
