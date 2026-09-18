import XCTest
@testable import IslandTray

final class TrayStoreTests: XCTestCase {
    private var root: URL!
    private var store: TrayStore!

    /// TrayItem.fileURL resolves against TrayContainer, which is the real app
    /// container. Tests run against a temporary root, so they must pass it in.
    private var itemsDir: URL { root.appendingPathComponent("Items", isDirectory: true) }

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = TrayStore(root: root)
        try store.prepare()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAddThenLoadRoundTrip() throws {
        let item = try store.add(data: Data("hello".utf8), suggestedName: "a.txt", uti: "public.plain-text")
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, item.id)
        XCTAssertEqual(loaded[0].name, "a.txt")
        XCTAssertEqual(loaded[0].size, 5)
        XCTAssertEqual(loaded[0].ext, "txt")
    }

    func testStoredBytesMatch() throws {
        let payload = Data("island".utf8)
        let item = try store.add(data: payload, suggestedName: "b.bin", uti: "public.data")
        XCTAssertEqual(try Data(contentsOf: item.fileURL(in: itemsDir)), payload)
    }

    func testDuplicateNamesDoNotCollide() throws {
        let a = try store.add(data: Data("1".utf8), suggestedName: "same.txt", uti: "public.plain-text")
        let b = try store.add(data: Data("22".utf8), suggestedName: "same.txt", uti: "public.plain-text")
        XCTAssertNotEqual(a.fileURL(in: itemsDir), b.fileURL(in: itemsDir))
        XCTAssertEqual(try store.load().count, 2)
        XCTAssertEqual(try Data(contentsOf: a.fileURL(in: itemsDir)).count, 1)
        XCTAssertEqual(try Data(contentsOf: b.fileURL(in: itemsDir)).count, 2)
    }

    func testPathTraversalNameStaysInsideContainer() throws {
        let item = try store.add(data: Data("x".utf8), suggestedName: "../../escape.txt", uti: "public.plain-text")
        XCTAssertTrue(
            item.fileURL(in: itemsDir).standardizedFileURL.path
                .hasPrefix(itemsDir.standardizedFileURL.path)
        )
    }

    func testRemoveDeletesFileAndMetadata() throws {
        let item = try store.add(data: Data("x".utf8), suggestedName: "c.txt", uti: "public.plain-text")
        try store.remove(id: item.id)
        XCTAssertTrue(try store.load().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.fileURL(in: itemsDir).path))
    }

    func testNewestFirstOrdering() throws {
        let first = try store.add(data: Data("1".utf8), suggestedName: "1.txt", uti: "public.plain-text")
        let second = try store.add(data: Data("2".utf8), suggestedName: "2.txt", uti: "public.plain-text")
        let loaded = try store.load()
        XCTAssertEqual(loaded.map(\.id), [second.id, first.id])
    }

    func testAddCopyingFromURL() throws {
        let src = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("src.txt")
        try Data("from disk".utf8).write(to: src)
        defer { try? FileManager.default.removeItem(at: src) }

        let item = try store.add(copyingFrom: src, suggestedName: nil, uti: "public.plain-text")
        XCTAssertEqual(item.name, "src.txt")
        XCTAssertEqual(try Data(contentsOf: item.fileURL(in: itemsDir)), Data("from disk".utf8))
    }

    func testRebuildFromDiskRecoversAfterCorruptMetadata() throws {
        let item = try store.add(data: Data("keep".utf8), suggestedName: "d.txt", uti: "public.plain-text")
        try Data("}{ not json".utf8).write(to: root.appendingPathComponent("items.json"))

        // load() must not throw on corrupt metadata; it rebuilds instead.
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, item.id)
    }

    func testSymbolNameFallsBackByUTI() throws {
        let image = try store.add(data: Data("x".utf8), suggestedName: "p.jpeg", uti: "public.jpeg")
        let text = try store.add(data: Data("x".utf8), suggestedName: "t.txt", uti: "public.plain-text")
        XCTAssertEqual(image.symbolName, "photo")
        XCTAssertEqual(text.symbolName, "doc.text")
    }
}
