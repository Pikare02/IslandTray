import XCTest
@testable import IslandTray

final class TrayOrderingTests: XCTestCase {
    private func item(
        _ name: String, uti: String = "public.jpeg", size: Int = 1, added: TimeInterval = 0
    ) -> TrayItem {
        TrayItem(
            id: UUID(), name: name, uti: uti, size: size,
            addedAt: Date(timeIntervalSince1970: added), ext: "jpeg"
        )
    }

    private func names(_ sections: [TrayOrdering.Section]) -> [String] {
        sections.flatMap { $0.items }.map(\.name)
    }

    func testNewestFirstByDefault() {
        let ordering = TrayOrdering()
        let arranged = ordering.arrange([
            item("old", added: 10), item("new", added: 30), item("middle", added: 20)
        ])
        XCTAssertEqual(names(arranged), ["new", "middle", "old"])
    }

    func testAscendingReversesIt() {
        var ordering = TrayOrdering()
        ordering.ascending = true
        let arranged = ordering.arrange([item("old", added: 10), item("new", added: 30)])
        XCTAssertEqual(names(arranged), ["old", "new"])
    }

    func testNamesSortTheWayAPersonFilesThem() {
        // localizedStandardCompare, not <: "photo 10" after "photo 2", and
        // case ignored.
        var ordering = TrayOrdering()
        ordering.key = .name
        ordering.ascending = true
        let arranged = ordering.arrange([
            item("photo 10.jpeg"), item("Photo 2.jpeg"), item("apple.jpeg")
        ])
        XCTAssertEqual(names(arranged), ["apple.jpeg", "Photo 2.jpeg", "photo 10.jpeg"])
    }

    func testSizeOrder() {
        var ordering = TrayOrdering()
        ordering.key = .size
        let arranged = ordering.arrange([item("small", size: 1), item("big", size: 99)])
        XCTAssertEqual(names(arranged), ["big", "small"])
    }

    func testATieStillHasOneFixedOrder() {
        // sorted(by:) is not stable: without a tiebreaker two items of the
        // same size swap places on every redraw.
        var ordering = TrayOrdering()
        ordering.key = .size
        let items = (0..<8).map { item("same-\($0)", size: 5) }
        let first = names(ordering.arrange(items))
        XCTAssertEqual(first, names(ordering.arrange(items.reversed())))
    }

    func testUngroupedIsOneSection() {
        let arranged = TrayOrdering().arrange([item("a"), item("b")])
        XCTAssertEqual(arranged.count, 1)
        XCTAssertNil(arranged[0].kind)
    }

    func testGroupingSplitsByKindInAFixedOrder() {
        var ordering = TrayOrdering()
        ordering.groupsByKind = true
        let arranged = ordering.arrange([
            item("a.txt", uti: "public.plain-text"),
            item("b.jpeg", uti: "public.jpeg"),
            item("c.mp4", uti: "public.mpeg-4"),
            item("d.jpeg", uti: "public.jpeg")
        ])
        XCTAssertEqual(arranged.map(\.kind), [.image, .video, .document])
        XCTAssertEqual(arranged[0].items.count, 2)
    }

    func testAnEmptyKindGetsNoSection() {
        var ordering = TrayOrdering()
        ordering.groupsByKind = true
        let arranged = ordering.arrange([item("b.jpeg")])
        XCTAssertEqual(arranged.map(\.kind), [.image])
    }

    func testEveryItemSurvivesGrouping() {
        var ordering = TrayOrdering()
        ordering.groupsByKind = true
        let items = [
            item("a.txt", uti: "public.plain-text"),
            item("b.jpeg", uti: "public.jpeg"),
            item("c.zip", uti: "public.zip-archive"),
            item("d.mp3", uti: "public.mp3"),
            item("e.bin", uti: "public.data")
        ]
        XCTAssertEqual(Set(names(ordering.arrange(items))), Set(items.map(\.name)))
    }

    func testKindsAreRecognised() {
        XCTAssertEqual(TrayItemKind(uti: "public.jpeg"), .image)
        XCTAssertEqual(TrayItemKind(uti: "public.mpeg-4"), .video)
        XCTAssertEqual(TrayItemKind(uti: "public.mp3"), .audio)
        XCTAssertEqual(TrayItemKind(uti: "com.adobe.pdf"), .document)
        XCTAssertEqual(TrayItemKind(uti: "public.zip-archive"), .archive)
        XCTAssertEqual(TrayItemKind(uti: "public.data"), .other)
        XCTAssertEqual(TrayItemKind(uti: "not a real uti at all"), .other)
    }
}

/// The clipboard names itself after what was copied: a card reading
/// "clipboard.txt" over and over is no use for finding anything again.
final class ClipboardNamingTests: XCTestCase {
    func testTheFirstLineBecomesTheName() {
        XCTAssertEqual(AddToClipboardIntent.name(for: "hello world"), "hello world.txt")
    }

    func testOnlyTheFirstLine() {
        XCTAssertEqual(AddToClipboardIntent.name(for: "first\nsecond\nthird"), "first.txt")
    }

    func testALongTextIsCutToSomethingReadable() {
        let name = AddToClipboardIntent.name(for: String(repeating: "x", count: 500))
        XCTAssertLessThanOrEqual(name.count, 44)
        XCTAssertTrue(name.hasSuffix(".txt"))
    }

    func testWhitespaceOnlyTextStillGetsAName() {
        // Sanitizing an empty name would leave "Untitled"; giving it one here
        // keeps the card honest about what it is.
        XCTAssertEqual(AddToClipboardIntent.name(for: "   \n  "), "clipboard.txt")
    }
}
