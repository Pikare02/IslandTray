import XCTest
@testable import IslandTray

/// Only the bookmark path is covered. The photo path needs a real library and
/// the system's own confirmation dialog, neither of which exists in a test
/// bundle -- it is guarded by an authorization check and reports failure
/// rather than assuming success.
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

    func testTheBookmarkedFileIsDeleted() async throws {
        let original = root.appendingPathComponent("original.txt")
        try Data("hello".utf8).write(to: original)
        let bookmark = try original.bookmarkData()

        let removed = await OriginalRemover.remove(.file(bookmark: bookmark))

        XCTAssertTrue(removed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
    }

    func testAnUnresolvableBookmarkIsReportedRatherThanIgnored() async {
        // The tray copy is removed either way; the user has to be told their
        // original is still sitting there.
        let removed = await OriginalRemover.remove(.file(bookmark: Data([0x00, 0x01, 0x02])))
        XCTAssertFalse(removed)
    }

    func testAFileThatIsAlreadyGoneIsNotReportedAsDeleted() async throws {
        let original = root.appendingPathComponent("original.txt")
        try Data("hello".utf8).write(to: original)
        let bookmark = try original.bookmarkData()
        try FileManager.default.removeItem(at: original)

        let removed = await OriginalRemover.remove(.file(bookmark: bookmark))

        XCTAssertFalse(removed)
    }
}
