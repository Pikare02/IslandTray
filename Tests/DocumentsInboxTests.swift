import XCTest
@testable import IslandTray

final class DocumentsInboxTests: XCTestCase {
    private var inbox: URL!
    private var storeRoot: URL!
    private var store: TrayStore!

    override func setUpWithError() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        inbox = base.appendingPathComponent("Documents", isDirectory: true)
        storeRoot = base.appendingPathComponent("Support", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        store = TrayStore(root: storeRoot)
        try store.prepare()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: inbox.deletingLastPathComponent())
    }

    @discardableResult
    private func write(_ name: String, _ contents: String = "hello") throws -> URL {
        let url = inbox.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func sweep() -> DropReceiver.Result {
        DocumentsInbox.sweep(store: store, directory: inbox)
    }

    func testAFileSavedIntoTheFolderEndsUpInTheTray() throws {
        try write("note.txt")

        let result = sweep()

        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.failed, [])
        let items = try store.load()
        XCTAssertEqual(items.map(\.name), ["note.txt"])
        XCTAssertEqual(
            try Data(contentsOf: items[0].fileURL(in: storeRoot.appendingPathComponent("Items"))),
            Data("hello".utf8)
        )
    }

    func testTheOriginalIsMovedNotCopied() throws {
        // Left behind, the same file would be imported again on every
        // foreground, and the tray would fill with duplicates of it.
        let url = try write("note.txt")

        _ = sweep()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testAnEmptyFolderIsANoOp() {
        let result = sweep()
        XCTAssertEqual(result.added, 0)
        XCTAssertEqual(result.failed, [])
    }

    func testEveryFileIsTakenNotJustTheFirst() throws {
        try write("a.txt")
        try write("b.txt")
        try write("c.txt")

        XCTAssertEqual(sweep().added, 3)
        XCTAssertEqual(try store.load().count, 3)
    }

    func testAFolderIsLeftWhereTheUserPutIt() throws {
        let folder = inbox.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try write("note.txt")

        let result = sweep()

        XCTAssertEqual(result.added, 1, "the folder must not count as an import")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
    }

    func testTheTypeIsReadFromTheFileRatherThanGuessed() throws {
        try write("note.txt")
        _ = sweep()
        XCTAssertEqual(try store.load().first?.uti, "public.plain-text")
    }

    func testAMissingFolderIsNotAFailure() {
        // The Documents folder exists on a real device, but a sweep must not
        // report failures for a directory it simply could not read.
        let result = DocumentsInbox.sweep(
            store: store,
            directory: inbox.appendingPathComponent("nope", isDirectory: true)
        )
        XCTAssertEqual(result.added, 0)
        XCTAssertEqual(result.failed, [])
    }


    func testTheMarkerKeepsTheFolderVisibleAndIsNotTakenIn() throws {
        // The Files app hides an app's folder while it is empty, so an empty
        // inbox cannot be found -- and it is empty exactly when the user is
        // hunting for somewhere to save their first file. The marker must
        // therefore exist, and must never be swept into the tray itself.
        try write("note.txt")

        let result = sweep()

        XCTAssertEqual(result.added, 1, "only the real file")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: inbox.appendingPathComponent(DocumentsInbox.markerName).path
            )
        )
    }

    func testTheMarkerComesBackAfterTheUserDeletesIt() throws {
        DocumentsInbox.ensureVisible(in: inbox)
        try FileManager.default.removeItem(at: inbox.appendingPathComponent(DocumentsInbox.markerName))

        _ = sweep()

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: inbox.appendingPathComponent(DocumentsInbox.markerName).path
            )
        )
    }

    func testAnInboxHoldingOnlyTheMarkerIsANoOp() {
        DocumentsInbox.ensureVisible(in: inbox)
        let result = sweep()
        XCTAssertEqual(result.added, 0)
        XCTAssertEqual(result.failed, [])
    }
}
