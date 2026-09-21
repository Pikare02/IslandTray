import XCTest
@testable import IslandTray

final class TrayFilterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000_000)

    private func item(
        _ name: String, uti: String = "public.jpeg", agoInHours hours: Double = 0
    ) -> TrayItem {
        TrayItem(
            id: UUID(), name: name, uti: uti, size: 1,
            addedAt: now.addingTimeInterval(-hours * 3600), ext: "jpeg"
        )
    }

    private func names(_ items: [TrayItem]) -> [String] { items.map(\.name) }

    func testAnEmptyFilterChangesNothing() {
        let all = [item("a.jpeg"), item("b.png")]
        XCTAssertFalse(TrayFilter().isActive)
        XCTAssertEqual(names(TrayFilter().apply(to: all, now: now)), ["a.jpeg", "b.png"])
    }

    func testTextMatchesPartOfTheName() {
        var filter = TrayFilter()
        filter.text = "rep"
        let all = [item("report.pdf"), item("photo.jpeg")]
        XCTAssertEqual(names(filter.apply(to: all, now: now)), ["report.pdf"])
    }

    func testTextIgnoresCase() {
        var filter = TrayFilter()
        filter.text = "REPORT"
        XCTAssertEqual(names(filter.apply(to: [item("report.pdf")], now: now)), ["report.pdf"])
    }

    func testWhitespaceOnlyTextIsNotAFilter() {
        var filter = TrayFilter()
        filter.text = "   "
        XCTAssertFalse(filter.isActive, "the funnel must not look active for a space")
        XCTAssertEqual(names(filter.apply(to: [item("a.jpeg")], now: now)), ["a.jpeg"])
    }

    func testKindsNarrowToTheChosenOnes() {
        var filter = TrayFilter()
        filter.kinds = [.document]
        let all = [item("a.jpeg"), item("b.txt", uti: "public.plain-text")]
        XCTAssertEqual(names(filter.apply(to: all, now: now)), ["b.txt"])
    }

    func testSeveralKindsAreAnOrNotAnAnd() {
        var filter = TrayFilter()
        filter.kinds = [.document, .image]
        let all = [item("a.jpeg"), item("b.txt", uti: "public.plain-text"), item("c.mp3", uti: "public.mp3")]
        XCTAssertEqual(names(filter.apply(to: all, now: now)), ["a.jpeg", "b.txt"])
    }

    func testTheWindowKeepsWhatIsInsideIt() {
        var filter = TrayFilter()
        filter.window = .day
        let all = [item("fresh.jpeg", agoInHours: 2), item("old.jpeg", agoInHours: 30)]
        XCTAssertEqual(names(filter.apply(to: all, now: now)), ["fresh.jpeg"])
    }

    func testAnItemDatedInTheFutureIsNotHidden() {
        // A restored backup or a clock change can leave a date ahead of now;
        // hiding it because it is "not within the last day" would be absurd.
        var filter = TrayFilter()
        filter.window = .day
        let all = [item("future.jpeg", agoInHours: -5)]
        XCTAssertEqual(names(filter.apply(to: all, now: now)), ["future.jpeg"])
    }

    func testEveryPartMustMatch() {
        var filter = TrayFilter()
        filter.text = "a"
        filter.kinds = [.image]
        filter.window = .day
        let all = [
            item("a.jpeg", agoInHours: 1),
            item("a.txt", uti: "public.plain-text", agoInHours: 1),
            item("a.jpeg", agoInHours: 100),
            item("b.jpeg", agoInHours: 1)
        ]
        XCTAssertEqual(filter.apply(to: all, now: now).count, 1)
    }
}

/// The highlight colour survives a round trip through the only form
/// UserDefaults can hold it in.
final class AccentColorTests: XCTestCase {
    func testAHexBecomesAColourAndBack() {
        let hex = "34C759"
        let color = AccentColor.color(forHex: hex)
        XCTAssertNotNil(color)
        XCTAssertEqual(AccentColor.hex(for: try XCTUnwrap(color)), hex)
    }

    func testAHashAndLowercaseAreAccepted() {
        // What a person types, and what a palette hands back.
        XCTAssertEqual(AccentColor.color(forHex: "#ff9500"), AccentColor.color(forHex: "FF9500"))
    }

    func testNonsenseIsRefusedRatherThanShowingBlack() {
        XCTAssertNil(AccentColor.color(forHex: ""))
        XCTAssertNil(AccentColor.color(forHex: "ZZZZZZ"))
        XCTAssertNil(AccentColor.color(forHex: "12345"))
        XCTAssertNil(AccentColor.color(forHex: "1234567"))
    }

    func testAGreyDoesNotCrashTheHexReader() {
        // UIColor gives a grey two components, not four; reading [0],[1],[2]
        // off that is a crash rather than a wrong colour.
        XCTAssertEqual(AccentColor.hex(for: .white), "FFFFFF")
        XCTAssertEqual(AccentColor.hex(for: .black), "000000")
    }

    func testEveryCommonSwatchIsAColour() {
        for hex in AccentColor.common {
            XCTAssertNotNil(AccentColor.color(forHex: hex), hex)
        }
    }
}
