import XCTest
@testable import IslandTray

final class WeatherProviderTests: XCTestCase {
    func testCacheEncodesAndDecodes() throws {
        let r = WeatherProvider.Reading(symbol: "cloud.rain", tempText: "18°", fetched: Date())
        let data = try JSONEncoder().encode(r)
        let back = try JSONDecoder().decode(WeatherProvider.Reading.self, from: data)
        XCTAssertEqual(back.symbol, "cloud.rain")
        XCTAssertEqual(back.tempText, "18°")
    }

    func testStaleness() {
        let fresh = WeatherProvider.Reading(symbol: "s", tempText: "1°", fetched: Date())
        let old = WeatherProvider.Reading(symbol: "s", tempText: "1°",
                                          fetched: Date().addingTimeInterval(-3600))
        XCTAssertFalse(WeatherProvider.isStale(fresh))
        XCTAssertTrue(WeatherProvider.isStale(old))
    }
}
