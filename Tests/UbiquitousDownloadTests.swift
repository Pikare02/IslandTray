import XCTest
@testable import IslandTray

/// The real download can only be exercised on a device with iCloud Drive,
/// so these pin what can be pinned locally: which names count as
/// placeholders, that local files are never waited on, and that a
/// placeholder that never turns into a file is reported by name.
final class UbiquitousDownloadTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    func testPlaceholderNames() {
        XCTAssertEqual(UbiquitousDownload.placeholderTarget(".a.txt.icloud"), "a.txt")
        XCTAssertNil(UbiquitousDownload.placeholderTarget("a.txt"))
        XCTAssertNil(UbiquitousDownload.placeholderTarget(".hidden"))
    }

    func testLocalFilesHaveNothingPendingAndAreNotWaitedOn() throws {
        let file = scratch.appendingPathComponent("a.txt")
        try Data("hi".utf8).write(to: file)
        let sub = scratch.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: sub.appendingPathComponent("b.txt"))

        XCTAssertEqual(UbiquitousDownload.pending(in: file), [])
        XCTAssertEqual(UbiquitousDownload.pending(in: scratch), [])

        let started = Date()
        XCTAssertNoThrow(try UbiquitousDownload.ensureDownloaded(scratch, timeout: 5))
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }

    func testAPlaceholderInsideAFolderIsPendingUnderItsRealName() throws {
        let sub = scratch.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data().write(to: sub.appendingPathComponent(".x.pdf.icloud"))

        XCTAssertEqual(UbiquitousDownload.pending(in: scratch).map(\.lastPathComponent), ["x.pdf"])
    }

    func testAPlaceholderThatNeverArrivesTimesOutNamingIt() throws {
        try Data().write(to: scratch.appendingPathComponent(".x.pdf.icloud"))

        XCTAssertThrowsError(
            try UbiquitousDownload.ensureDownloaded(scratch, timeout: 0.3, poll: 0.1)
        ) { error in
            XCTAssertEqual((error as? UbiquitousDownload.TimedOut)?.name, "x.pdf")
        }
    }
}
