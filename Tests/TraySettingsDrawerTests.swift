import XCTest
@testable import IslandTray

final class TraySettingsDrawerTests: XCTestCase {
    private func isolated() -> TraySettings {
        let suite = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        return TraySettings(defaults: suite)
    }

    func testDefaults() {
        let s = isolated()
        XCTAssertFalse(s.appDrawerEnabled)
        XCTAssertTrue(s.showAppNames)
        XCTAssertEqual(s.drawerBackgroundHex, "000000")
        XCTAssertEqual(s.temperatureUnit, "c")
        XCTAssertEqual(s.weatherLocationMode, "auto")
        XCTAssertNil(s.weatherManualLat)
    }

    func testRoundTrip() {
        let s = isolated()
        s.appDrawerEnabled = true
        s.temperatureUnit = "f"
        s.weatherManualLat = 35.68
        XCTAssertTrue(s.appDrawerEnabled)
        XCTAssertEqual(s.temperatureUnit, "f")
        XCTAssertEqual(s.weatherManualLat, 35.68)
    }
}
