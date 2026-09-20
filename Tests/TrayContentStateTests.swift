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
        let json = #"{"count": 1, "recent": [{"id": "\#(hugeID)", "symbol": "y", "name": "n", "hasThumbnail": false}]}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(TrayContentState.self, from: data)
        XCTAssertLessThanOrEqual(decoded.encodedByteCount, TrayContentState.maxEncodedBytes)
    }

    // MARK: - Thumbnail atlas

    /// The largest JPEG strip `make(from:atlas:)` has to carry, from the
    /// measurement `ThumbnailService.atlasTile` was chosen against: four
    /// 48px tiles of dense screenshot content at quality 0.3 encoded to 1871
    /// bytes. Rounded up; photographs compress well below this.
    private static let measuredWorstCaseAtlasBytes = 1900

    private func atlas(bytes: Int, tiles: Int = TrayContentState.maxPreviews) -> TrayContentState.Atlas {
        TrayContentState.Atlas(
            jpeg: Data(repeating: 0xAB, count: bytes),
            filled: Array(repeating: true, count: tiles)
        )
    }

    func testMeasuredWorstCaseAtlasFitsAlongsideWorstCaseNames() {
        // The reason the atlas exists is that it fits. If this fails the
        // island silently loses every thumbnail (make() drops the atlas), so
        // pin it against the worst case on both axes at once: the longest
        // symbol, names at the byte cap in 3-byte characters, and a strip at
        // the size the tile dimension was measured against.
        let items = (0..<TrayContentState.maxPreviews).map { _ in
            item(name: String(repeating: "あ", count: 40), uti: "public.source-code")
        }
        let state = TrayContentState.make(
            from: items,
            atlas: atlas(bytes: Self.measuredWorstCaseAtlasBytes)
        )
        XCTAssertNotNil(state.atlas, "the measured worst-case strip must survive make()")
        XCTAssertTrue(state.recent.allSatisfy(\.hasThumbnail))
        XCTAssertLessThanOrEqual(state.encodedByteCount, TrayContentState.maxEncodedBytes)
    }

    func testOversizedAtlasIsDroppedRatherThanShippedOverTheLimit() {
        let items = (0..<TrayContentState.maxPreviews).map { _ in item(name: "a.jpeg") }
        let state = TrayContentState.make(from: items, atlas: atlas(bytes: 100_000))
        XCTAssertNil(state.atlas)
        // Previews survive, but none may claim a tile that is no longer there.
        XCTAssertEqual(state.recent.count, TrayContentState.maxPreviews)
        XCTAssertFalse(state.recent.contains(where: \.hasThumbnail))
        XCTAssertLessThanOrEqual(state.encodedByteCount, TrayContentState.maxEncodedBytes)
    }

    func testAtlasWithFewerFlagsThanPreviewsMarksTheRestSymbolOnly() {
        let items = (0..<TrayContentState.maxPreviews).map { _ in item(name: "a.jpeg") }
        let partial = TrayContentState.Atlas(
            jpeg: Data(repeating: 0xAB, count: 64),
            filled: [true, false]
        )
        let state = TrayContentState.make(from: items, atlas: partial)
        XCTAssertEqual(state.recent.map(\.hasThumbnail), [true, false, false, false])
    }

    func testNoAtlasMeansNoPreviewClaimsAThumbnail() {
        let items = (0..<TrayContentState.maxPreviews).map { _ in item(name: "a.jpeg") }
        let state = TrayContentState.make(from: items)
        XCTAssertNil(state.atlas)
        XCTAssertFalse(state.recent.contains(where: \.hasThumbnail))
    }

    // MARK: - Display names

    func testShortNameIsCarriedWhole() {
        let state = TrayContentState.make(from: [item(name: "photo.jpeg")])
        XCTAssertEqual(state.recent.first?.name, "photo.jpeg")
    }

    func testLongNameKeepsItsExtension() {
        let name = String(repeating: "a", count: 200) + ".jpeg"
        let truncated = TrayContentState.islandName(name)
        XCTAssertTrue(truncated.hasSuffix(".jpeg"), "got \(truncated)")
        XCTAssertLessThanOrEqual(truncated.utf8.count, TrayContentState.maxNameBytes)
    }

    func testLongMultibyteNameStaysWithinTheByteCapAndIsNotCorrupted() {
        // Cutting on bytes would split a 3-byte character; the result must
        // still be the characters the name is made of.
        let name = String(repeating: "写", count: 60) + ".mov"
        let truncated = TrayContentState.islandName(name)
        XCTAssertLessThanOrEqual(truncated.utf8.count, TrayContentState.maxNameBytes)
        XCTAssertTrue(truncated.allSatisfy { "写….mov".contains($0) }, "got \(truncated)")
        XCTAssertTrue(truncated.contains("…"))
    }

    // MARK: - Decoding

    func testDecodingAStateFromAnOlderBuildDoesNotThrow() throws {
        // An activity started before this update is still on screen after it,
        // and the widget decodes its state -- which has no name, no
        // hasThumbnail and no atlas. Throwing here takes the island away.
        let json = #"{"count": 3, "recent": [{"id": "abc", "symbol": "photo"}]}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(TrayContentState.self, from: data)
        XCTAssertEqual(decoded.count, 3)
    }

    func testDecodingAnOversizedAtlasDegradesRatherThanThrowing() throws {
        let oversized = Data(repeating: 0xAB, count: 20_000).base64EncodedString()
        let json = #"{"count": 1, "recent": [], "atlas": "\#(oversized)"}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(TrayContentState.self, from: data)
        XCTAssertNil(decoded.atlas)
        XCTAssertLessThanOrEqual(decoded.encodedByteCount, TrayContentState.maxEncodedBytes)
    }

    func testRoundTripPreservesTheAtlas() throws {
        let items = (0..<TrayContentState.maxPreviews).map { _ in item(name: "a.jpeg") }
        let state = TrayContentState.make(from: items, atlas: atlas(bytes: 512))
        let decoded = try JSONDecoder().decode(
            TrayContentState.self, from: JSONEncoder().encode(state)
        )
        XCTAssertEqual(decoded, state)
    }
}
