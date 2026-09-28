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

    func testDrawerDegradesWhenSlotsTooBig() {
        // Six slots whose launch URLs are far too big to all fit, even without
        // an atlas: the state must still come back within the hard cap, with
        // fewer slots rather than an over-limit payload.
        let bigURL = "https://example.com/?q=" + String(repeating: "a", count: 900)
        let slots = (0..<6).map { i in
            TrayContentState.DrawerSlot(symbol: "app", name: "App\(i)", launch: bigURL, hasIcon: false)
        }
        let state = TrayContentState.makeDrawer(
            weather: .init(dateText: "9/24 木", tempText: "21°", symbol: "sun.max"),
            slots: slots, atlas: nil, view: .drawer, count: 0
        )
        XCTAssertLessThanOrEqual(state.encodedByteCount, TrayContentState.maxEncodedBytes)
        XCTAssertLessThan(state.drawer?.count ?? 0, 6) // some slots were shed to fit
        XCTAssertNotNil(state.weather)                 // weather is always retained
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
        XCTAssertFalse(decoded.hideLockScreen)
    }

    func testMinimalFieldsAndHideLockScreenRoundTrip() throws {
        // The half-island date/weather choice and the hide-Lock-Screen flag
        // must survive the encode/decode ActivityKit does across processes.
        let state = TrayContentState.makeDrawer(
            weather: .init(dateText: "9/24 木", tempText: "21°", symbol: "sun.max",
                           dayText: "24", showsWeather: true),
            slots: [], atlas: nil, view: .drawer, count: 0
        ).hidingLockScreen(true)
        let decoded = try JSONDecoder().decode(
            TrayContentState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.weather?.dayText, "24")
        XCTAssertEqual(decoded.weather?.showsWeather, true)
        XCTAssertTrue(decoded.hideLockScreen)
    }

    func testWeatherDecodeToleratesMissingMinimalFields() throws {
        // An older activity's Weather has no dayText/showsWeather; they default.
        let legacy = Data(#"{"count":0,"recent":[],"page":0,"view":"drawer","weather":{"dateText":"SEP 24 THU","tempText":"21°","symbol":"sun.max"}}"#.utf8)
        let decoded = try JSONDecoder().decode(TrayContentState.self, from: legacy)
        XCTAssertEqual(decoded.weather?.symbol, "sun.max")
        XCTAssertEqual(decoded.weather?.dayText, "")
        XCTAssertEqual(decoded.weather?.showsWeather, false)
    }
}
