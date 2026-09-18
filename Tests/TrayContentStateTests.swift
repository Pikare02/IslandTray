import XCTest
@testable import IslandTray

final class TrayContentStateTests: XCTestCase {
    private func item(name: String, uti: String = "public.jpeg") -> TrayItem {
        TrayItem(id: UUID(), name: name, uti: uti, size: 1, addedAt: Date(), ext: "jpeg")
    }

    func testCountReflectsAllItems() {
        let items = (0..<10).map { item(name: "\($0).jpeg") }
        let state = TrayContentState.make(from: items)
        XCTAssertEqual(state.count, 10)
    }

    func testRecentIsCappedAtMaxPreviews() {
        let items = (0..<10).map { item(name: "\($0).jpeg") }
        let state = TrayContentState.make(from: items)
        XCTAssertEqual(state.recent.count, TrayContentState.maxPreviews)
    }

    func testRecentPreservesOrder() {
        let items = (0..<4).map { item(name: "\($0).jpeg") }
        let state = TrayContentState.make(from: items)
        XCTAssertEqual(state.recent.map(\.id), items.map { $0.id.uuidString })
    }

    func testEmptyTray() {
        let state = TrayContentState.make(from: [])
        XCTAssertEqual(state.count, 0)
        XCTAssertTrue(state.recent.isEmpty)
    }

    func testSymbolComesFromUTI() {
        let state = TrayContentState.make(from: [item(name: "a.txt", uti: "public.plain-text")])
        XCTAssertEqual(state.recent.first?.symbol, "doc.text")
    }

    func testStaysUnderFourKilobytesWithMaxPreviewsAndLongestSymbol() {
        // Genuine worst case reachable through `make(from:)`: the maximum number
        // of previews, each with the longest symbol `TrayItem.symbolName` can
        // produce. `id` is always a fixed-length UUID string, so it does not
        // vary; `.sourceCode`'s UTI ("public.source-code") maps to the longest
        // entry in TrayItem.symbolName(forUTI:)'s table, "chevron.left.forwardslash.chevron.right".
        let items = (0..<(TrayContentState.maxPreviews * 3)).map { _ in
            item(name: "x", uti: "public.source-code")
        }
        let state = TrayContentState.make(from: items)
        XCTAssertEqual(state.recent.count, TrayContentState.maxPreviews)
        XCTAssertEqual(state.recent.first?.symbol, "chevron.left.forwardslash.chevron.right")
        XCTAssertLessThan(state.encodedByteCount, TrayContentState.maxEncodedBytes)
    }

    func testConstructionPathsCannotExceedEncodedLimit() {
        // After closing the memberwise-init bypass (Finding 1), `make(from:)`
        // and `countOnly(count:)` are the only ways left to build a
        // `TrayContentState`. Pin that neither can produce an oversized state,
        // even fed pathological input.
        let manyWorstCaseItems = (0..<10_000).map { _ in
            item(name: "x", uti: "public.source-code")
        }
        let madeState = TrayContentState.make(from: manyWorstCaseItems)
        XCTAssertLessThan(madeState.encodedByteCount, TrayContentState.maxEncodedBytes)

        let countOnlyState = TrayContentState.countOnly(count: .max)
        XCTAssertLessThan(countOnlyState.encodedByteCount, TrayContentState.maxEncodedBytes)
    }

    func testEncodedByteCountIsNonZero() {
        let state = TrayContentState.make(from: [item(name: "a.jpeg")])
        XCTAssertGreaterThan(state.encodedByteCount, 0)
    }
}
