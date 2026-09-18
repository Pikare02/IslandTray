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

    func testExplicitFactoryPathsCannotExceedEncodedLimit() {
        // `make(from:)` and `countOnly(count:)` are the type's two explicit
        // factory functions. Pin that neither can produce an oversized state,
        // even fed pathological input. This does not cover decoding — a
        // `TrayContentState` can also be constructed via `Codable`, which
        // `testDecodingOversizedJSONStaysWithinEncodedLimit` below covers
        // separately, since decoding degrades rather than clamping in place.
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

    func testDecodingOversizedJSONStaysWithinEncodedLimit() throws {
        // Reviewer's crafted repro (task-6-review-2.md, Finding 1): the
        // synthesized Decodable initializer ignored `maxPreviews` and the
        // bounded symbol vocabulary entirely, decoding a single 5000-byte
        // `id` into a 5045-byte `TrayContentState` with no resistance.
        // ActivityKit decodes this type in the widget process, so decoding
        // must degrade to a value within the limit rather than throw or
        // silently exceed it.
        let hugeID = String(repeating: "x", count: 5000)
        let json = #"{"count": 1, "recent": [{"id": "\#(hugeID)", "symbol": "y"}]}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(TrayContentState.self, from: data)
        XCTAssertLessThanOrEqual(decoded.encodedByteCount, TrayContentState.maxEncodedBytes)
    }
}
