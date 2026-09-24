import XCTest
@testable import IslandTray

final class WeatherFormatTests: XCTestCase {
    func testSymbolMapping() {
        XCTAssertEqual(WeatherFormat.symbol(forWMO: 0), "sun.max")
        XCTAssertEqual(WeatherFormat.symbol(forWMO: 3), "cloud")
        XCTAssertEqual(WeatherFormat.symbol(forWMO: 61), "cloud.rain")
        XCTAssertEqual(WeatherFormat.symbol(forWMO: 71), "snowflake")
        XCTAssertEqual(WeatherFormat.symbol(forWMO: 95), "cloud.bolt")
        XCTAssertEqual(WeatherFormat.symbol(forWMO: 999), "thermometer") // unknown fallback
    }

    func testTemperature() {
        XCTAssertEqual(WeatherFormat.temperature(celsius: 21.4, unit: "c"), "21°")
        XCTAssertEqual(WeatherFormat.temperature(celsius: 21.4, unit: "f"), "70°")
    }

    func testDateText() {
        var comps = DateComponents(); comps.year = 2026; comps.month = 9; comps.day = 24
        let date = Calendar(identifier: .gregorian).date(from: comps)! // Thursday
        XCTAssertEqual(WeatherFormat.dateText(date, language: "ja"), "9/24 木")
        XCTAssertEqual(WeatherFormat.dateText(date, language: "en"), "SEP 24 THU")
    }

    func testParseOpenMeteo() throws {
        let json = Data(#"{"current_weather":{"temperature":18.3,"weathercode":61}}"#.utf8)
        let m = try WeatherFormat.OpenMeteo.parse(json)
        XCTAssertEqual(m.temperatureC, 18.3, accuracy: 0.01)
        XCTAssertEqual(m.code, 61)
    }
}
