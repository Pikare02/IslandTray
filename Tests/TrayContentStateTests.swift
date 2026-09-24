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

/// Paging exists because a widget receives no gestures: the only way past the
/// first four items is a button that moves this.
final class TrayContentStatePagingTests: XCTestCase {
    private func items(_ count: Int) -> [TrayItem] {
        (0..<count).map {
            TrayItem(
                id: UUID(), name: "item-\($0).jpeg", uti: "public.jpeg", size: 1,
                addedAt: Date(), ext: "jpeg"
            )
        }
    }

    func testThePageDecidesWhichItemsAreShown() {
        let all = items(9)
        XCTAssertEqual(
            TrayContentState.items(all, onPage: 1).map(\.name),
            ["item-4.jpeg", "item-5.jpeg", "item-6.jpeg", "item-7.jpeg"]
        )
    }

    func testTheLastPageIsWhateverIsLeft() {
        XCTAssertEqual(TrayContentState.items(items(9), onPage: 2).map(\.name), ["item-8.jpeg"])
    }

    func testAPageBeyondTheEndShowsTheLastOne() {
        // A page can outlive the items it was counted against: the tray
        // shrinks while the island is on page three.
        XCTAssertEqual(TrayContentState.items(items(5), onPage: 99).map(\.name), ["item-4.jpeg"])
        XCTAssertEqual(TrayContentState.clampedPage(99, count: 5), 1)
        XCTAssertEqual(TrayContentState.clampedPage(-3, count: 5), 0)
    }

    func testAnEmptyTrayHasOnePage() {
        XCTAssertEqual(TrayContentState.items([], onPage: 3), [])
        XCTAssertEqual(TrayContentState.clampedPage(3, count: 0), 0)
    }

    func testTheStateSaysWhereItCanGo() {
        let first = TrayContentState.make(from: items(9), page: 0)
        XCTAssertFalse(first.hasPreviousPage)
        XCTAssertTrue(first.hasNextPage)

        let last = TrayContentState.make(from: items(9), page: 2)
        XCTAssertTrue(last.hasPreviousPage)
        XCTAssertFalse(last.hasNextPage)

        let short = TrayContentState.make(from: items(3))
        XCTAssertFalse(short.hasPreviousPage)
        XCTAssertFalse(short.hasNextPage, "four or fewer needs no buttons at all")
    }

    func testTheCountIsTheWholeTrayNotThePage() {
        // The compact island shows this number; it must not fall to 4.
        XCTAssertEqual(TrayContentState.make(from: items(9), page: 1).count, 9)
    }

    func testAPageSurvivesTheRoundTrip() throws {
        let state = TrayContentState.make(from: items(9), page: 2)
        let decoded = try JSONDecoder().decode(
            TrayContentState.self, from: JSONEncoder().encode(state)
        )
        XCTAssertEqual(decoded.page, 2)
        XCTAssertEqual(decoded.recent.map(\.name), state.recent.map(\.name))
    }

    func testAStateFromBeforePagingDecodesOnPageZero() throws {
        let json = #"{"count": 2, "recent": []}"#
        let decoded = try JSONDecoder().decode(
            TrayContentState.self, from: XCTUnwrap(json.data(using: .utf8))
        )
        XCTAssertEqual(decoded.page, 0)
    }

    func testWithDrawerFallsBackToSymbolsWhenCombinedAtlasTooBig() throws {
        let slots = (0..<6).map {
            TrayContentState.DrawerSlot(symbol: "globe", name: "S\($0)", launch: "https://a.b/\($0)", hasIcon: true)
        }
        let tray = TrayContentState.countOnly(count: 3)

        let small = TrayContentState.Atlas(jpeg: Data(count: 100), filled: Array(repeating: true, count: 6))
        let fits = tray.withDrawer(slots, combined: small, lockDrawer: true)
        XCTAssertEqual(fits.atlas, small.jpeg)
        XCTAssertTrue(fits.drawer?.allSatisfy(\.hasIcon) == true)

        let huge = TrayContentState.Atlas(jpeg: Data(count: 5000), filled: Array(repeating: true, count: 6))
        let degraded = tray.withDrawer(slots, combined: huge, lockDrawer: true)
        XCTAssertNil(degraded.atlas)
        XCTAssertEqual(degraded.drawer?.count, 6)
        XCTAssertTrue(degraded.drawer?.allSatisfy { !$0.hasIcon } == true)
        XCTAssertLessThanOrEqual(degraded.encodedByteCount, TrayContentState.buildBudget)

        let back = try JSONDecoder().decode(TrayContentState.self, from: JSONEncoder().encode(degraded))
        XCTAssertTrue(back.lockDrawer)
        XCTAssertTrue(back.drawerAvailable)
    }
}
