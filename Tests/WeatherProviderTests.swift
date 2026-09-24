import XCTest
@testable import IslandTray

final class WeatherProviderTests: XCTestCase {
    func testCacheEncodesAndDecodes() throws {
        let r = WeatherProvider.Reading(symbol: "cloud.rain", celsius: 18, fetched: Date())
        let data = try JSONEncoder().encode(r)
        let back = try JSONDecoder().decode(WeatherProvider.Reading.self, from: data)
        XCTAssertEqual(back.symbol, "cloud.rain")
        XCTAssertEqual(back.celsius, 18)
    }

    // A cached reading is unit-agnostic: the same Celsius formats to either
    // scale, so toggling °C/°F needs no re-fetch.
    func testCelsiusFormatsToEitherUnit() {
        let r = WeatherProvider.Reading(symbol: "s", celsius: 20, fetched: Date())
        XCTAssertEqual(WeatherFormat.temperature(celsius: r.celsius, unit: "c"), "20°")
        XCTAssertEqual(WeatherFormat.temperature(celsius: r.celsius, unit: "f"), "68°")
    }

    func testStaleness() {
        let fresh = WeatherProvider.Reading(symbol: "s", celsius: 1, fetched: Date())
        let old = WeatherProvider.Reading(symbol: "s", celsius: 1,
                                          fetched: Date().addingTimeInterval(-3600))
        XCTAssertFalse(WeatherProvider.isStale(fresh))
        XCTAssertTrue(WeatherProvider.isStale(old))
    }
}
