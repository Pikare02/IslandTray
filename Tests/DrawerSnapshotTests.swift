import XCTest
@testable import IslandTray

final class DrawerSnapshotTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("drawer-snapshot.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private func slot(_ i: Int) -> TrayContentState.DrawerSlot {
        .init(symbol: "app", name: "App\(i)", launch: "islandtray://launch?item=\(i)", hasIcon: true)
    }

    private func item(_ i: Int) -> TrayItem {
        TrayItem(id: UUID(), name: "f\(i).txt", uti: "public.plain-text", size: 1, addedAt: Date(), ext: "txt")
    }

    private func drawerState() -> TrayContentState {
        TrayContentState.makeDrawer(
            weather: nil, slots: [slot(0), slot(1)],
            atlas: .init(jpeg: Data([1, 2, 3]), filled: [true, true]),
            view: .drawer, count: 0
        )
    }

    func testADrawerStateIsRecordedAndReadBack() {
        XCTAssertEqual(DrawerSnapshot.record(drawerState(), at: url), .written)
        let loaded = DrawerSnapshot.load(from: url)
        XCTAssertEqual(loaded?.slots.map(\.name), ["App0", "App1"])
        XCTAssertEqual(loaded?.atlas, Data([1, 2, 3]))
        XCTAssertEqual(loaded?.atlasOffset, 0)
    }

    func testTheSameStateIsNotRewritten() {
        XCTAssertEqual(DrawerSnapshot.record(drawerState(), at: url), .written)
        XCTAssertEqual(DrawerSnapshot.record(drawerState(), at: url), .unchanged)
    }

    func testATrayStateCarryingTheDrawerStartsAfterItsOwnTiles() {
        let state = TrayContentState.make(from: [item(0), item(1), item(2)], atlas: nil)
            .withDrawer([slot(0)], combined: nil, lockDrawer: false)
        XCTAssertEqual(DrawerSnapshot.record(state, at: url), .written)
        XCTAssertEqual(DrawerSnapshot.load(from: url)?.atlasOffset, 3)
    }

    private func trayState(carrying slots: [TrayContentState.DrawerSlot]) -> TrayContentState {
        TrayContentState.make(from: [item(0)], atlas: nil).withDrawer(slots, combined: nil, lockDrawer: false)
    }

    func testATrayStateDoesNotReplaceADrawerStateWithTheSameSlots() {
        XCTAssertEqual(DrawerSnapshot.record(drawerState(), at: url), .written)
        XCTAssertEqual(DrawerSnapshot.record(trayState(carrying: [slot(0), slot(1)]), at: url), .unchanged)
        XCTAssertEqual(DrawerSnapshot.load(from: url)?.slots.map(\.hasIcon), [true, true])
    }

    func testATrayStateWithDifferentSlotsIsRecorded() {
        XCTAssertEqual(DrawerSnapshot.record(drawerState(), at: url), .written)
        XCTAssertEqual(DrawerSnapshot.record(trayState(carrying: [slot(0), slot(1), slot(2)]), at: url), .written)
        XCTAssertEqual(DrawerSnapshot.load(from: url)?.slots.count, 3)
    }

    func testATrayStateWithNoSlotsIsIgnored() {
        XCTAssertEqual(DrawerSnapshot.record(drawerState(), at: url), .written)
        XCTAssertEqual(DrawerSnapshot.record(trayState(carrying: []), at: url), .unchanged)
        XCTAssertEqual(DrawerSnapshot.load(from: url)?.slots.count, 2)
    }

    func testATrayStateIsRecordedWhenNothingIsOnDisk() {
        XCTAssertEqual(DrawerSnapshot.record(trayState(carrying: [slot(0)]), at: url), .written)
    }

    func testTurningTheDrawerOffRemovesTheSnapshot() {
        XCTAssertEqual(DrawerSnapshot.record(drawerState(), at: url), .written)
        let off = TrayContentState.make(from: [], atlas: nil)
        XCTAssertFalse(off.drawerAvailable)
        XCTAssertEqual(DrawerSnapshot.record(off, at: url), .removed)
        XCTAssertNil(DrawerSnapshot.load(from: url))
        XCTAssertEqual(DrawerSnapshot.record(off, at: url), .unchanged)
    }
}
