import Foundation

/// Pure weather/date presentation: WMO code → SF Symbol, °C→display, and the
/// language-driven date line the island shows when the tray is empty.
enum WeatherFormat {
    /// WMO weather-interpretation code → SF Symbol. Grouped by the ranges
    /// Open-Meteo documents; unknown codes fall back to a thermometer.
    static func symbol(forWMO code: Int) -> String {
        switch code {
        case 0: return "sun.max"
        case 1, 2: return "cloud.sun"
        case 3: return "cloud"
        case 45, 48: return "cloud.fog"
        case 51, 53, 55, 56, 57: return "cloud.drizzle"
        case 61, 63, 65, 66, 67, 80, 81, 82: return "cloud.rain"
        case 71, 73, 75, 77, 85, 86: return "snowflake"
        case 95, 96, 99: return "cloud.bolt"
        default: return "thermometer"
        }
    }

    static func temperature(celsius: Double, unit: String) -> String {
        let value = unit == "f" ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))°"
    }

    /// ja: "9/24 木". en (and anything else): "SEP 24 THU".
    static func dateText(_ date: Date, language: String?) -> String {
        var cal = Calendar(identifier: .gregorian)
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        if language == "ja" {
            cal.locale = Locale(identifier: "ja_JP")
            let weekdays = ["日", "月", "火", "水", "木", "金", "土"]
            let w = cal.component(.weekday, from: date) - 1
            return "\(month)/\(day) \(weekdays[w])"
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US")
        df.dateFormat = "MMM d EEE"
        return df.string(from: date).uppercased()
    }

    struct OpenMeteo: Decodable {
        let temperatureC: Double
        let code: Int

        private struct Root: Decodable {
            struct Current: Decodable { let temperature: Double; let weathercode: Int }
            let current_weather: Current
        }

        static func parse(_ data: Data) throws -> OpenMeteo {
            let root = try JSONDecoder().decode(Root.self, from: data)
            return OpenMeteo(temperatureC: root.current_weather.temperature,
                             code: root.current_weather.weathercode)
        }
    }
}
