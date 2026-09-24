import XCTest
@testable import IslandTray

final class TrayContentStateDrawerTests: XCTestCase {
    private func slot(_ i: Int) -> TrayContentState.DrawerSlot {
        .init(symbol: "app", name: "App\(i)", launch: "islandtray://launch?item=\(i)", hasIcon: false)
    }

    func testDrawerStateWithinBudget() {
        // 6 slots + a 6-tile atlas + weather must stay within the hard cap.
        let atlasJPEG = Data(count: 2200) // stand-in near the measured 6-tile size
        let state = TrayContentState.makeDrawer(
            weather: .init(dateText: "9/24 木", tempText: "21°", symbol: "sun.max"),
            slots: (0..<6).map(slot),
            atlas: .init(jpeg: atlasJPEG, filled: Array(repeating: true, count: 6)),
            view: .drawer, count: 0
        )
        XCTAssertLessThanOrEqual(state.encodedByteCount, TrayContentState.maxEncodedBytes)
        XCTAssertEqual(state.view, .drawer)
    }

    func testDefaultsAbsentWhenTrayState() {
        let state = TrayContentState.make(from: [], atlas: nil)
        XCTAssertNil(state.weather)
        XCTAssertNil(state.drawer)
        XCTAssertEqual(state.view, .tray)
    }

    func testDecodeToleratesMissingNewFields() throws {
        // A state from an older build with no view/weather/drawer keys decodes.
        let legacy = Data(#"{"count":0,"recent":[],"page":0}"#.utf8)
        let decoded = try JSONDecoder().decode(TrayContentState.self, from: legacy)
        XCTAssertEqual(decoded.view, .tray)
        XCTAssertNil(decoded.weather)
    }
}
