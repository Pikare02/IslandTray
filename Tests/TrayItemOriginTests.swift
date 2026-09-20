import XCTest
@testable import IslandTray

/// The origin is what makes taking an item out a move rather than a copy, and
/// it is persisted alongside every other field of a tray item -- so the two
/// things that must hold are that it survives a round trip, and that adding
/// it did not make every items.json written before it unreadable.
final class TrayItemOriginTests: XCTestCase {
    private var root: URL!
    private var store: TrayStore!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = TrayStore(root: root)
        try store.prepare()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAnItemWrittenBeforeOriginsExistedStillDecodes() throws {
        // The exact shape TrayItem had one commit ago. If this throws, every
        // existing tray reads as corrupt metadata, and TrayStore answers
        // corrupt metadata with a destructive rebuild that replaces every
        // display name with "Recovered-...".
        let json = """
        {"id":"1B0DF2B4-2D53-4C3B-9E2E-7F4B9E2B0A11","name":"a.txt","uti":"public.plain-text",
         "size":5,"addedAt":760000000,"ext":"txt"}
        """
        let item = try JSONDecoder.tray.decode(TrayItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.name, "a.txt")
        XCTAssertNil(item.origin, "no origin means nothing to delete, which is the safe reading")
    }

    func testBothKindsOfOriginRoundTrip() throws {
        for origin in [
            TrayItemOrigin.file(bookmark: Data([0x01, 0x02, 0x03])),
            TrayItemOrigin.photo(localIdentifier: "ABC-123/L0/001")
        ] {
            var item = TrayItem(
                id: UUID(), name: "a.txt", uti: "public.plain-text",
                size: 5, addedAt: Date(), ext: "txt"
            )
            item.origin = origin
            let decoded = try JSONDecoder.tray.decode(
                TrayItem.self, from: JSONEncoder.tray.encode(item)
            )
            XCTAssertEqual(decoded.origin, origin)
        }
    }

    func testTheStoreKeepsTheOriginItWasGiven() throws {
        let source = root.appendingPathComponent("source.txt")
        try Data("hello".utf8).write(to: source)
        let origin = TrayItemOrigin.photo(localIdentifier: "ABC-123/L0/001")

        _ = try store.add(
            copyingFrom: source, suggestedName: "a.txt", uti: "public.plain-text", origin: origin
        )

        XCTAssertEqual(try store.load().first?.origin, origin)
    }

    func testAnItemAddedWithNoOriginHasNone() throws {
        let source = root.appendingPathComponent("source.txt")
        try Data("hello".utf8).write(to: source)

        _ = try store.add(copyingFrom: source, suggestedName: "a.txt", uti: "public.plain-text")

        XCTAssertNil(try store.load().first?.origin)
    }
}
