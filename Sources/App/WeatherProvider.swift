import CoreLocation
import Foundation

/// Fetches current weather from Open-Meteo for the current (or a pinned)
/// location and caches the last reading. Only the app process uses this; it
/// hands a finished `Reading` to the content state.
actor WeatherProvider {
    static let shared = WeatherProvider()

    struct Reading: Codable {
        let symbol: String
        let tempText: String
        let fetched: Date
    }

    /// Refresh cadence: half an hour is plenty for a glanceable temperature.
    static let maxAge: TimeInterval = 30 * 60
    static func isStale(_ r: Reading) -> Bool {
        Date().timeIntervalSince(r.fetched) > maxAge
    }

    private static let cacheKey = "weatherReading"

    func cached() -> Reading? {
        guard let data = TraySettings.store.data(forKey: Self.cacheKey) else { return nil }
        return try? JSONDecoder().decode(Reading.self, from: data)
    }

    private func store(_ r: Reading) {
        if let data = try? JSONEncoder().encode(r) {
            TraySettings.store.set(data, forKey: Self.cacheKey)
        }
    }

    /// Cached reading if fresh; otherwise fetch, cache, and return it. Returns
    /// the stale cache (or nil) if the fetch fails — never blocks the island.
    func current() async -> Reading? {
        if let c = cached(), !Self.isStale(c) { return c }
        guard let coord = await coordinate() else { return cached() }
        do {
            let reading = try await fetch(coord)
            store(reading)
            return reading
        } catch {
            return cached()
        }
    }

    private func coordinate() async -> CLLocationCoordinate2D? {
        let settings = TraySettings()
        if settings.weatherLocationMode == "manual",
           let lat = settings.weatherManualLat, let lon = settings.weatherManualLon {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return await LocationOnce.shared.coordinate()
    }

    private func fetch(_ coord: CLLocationCoordinate2D) async throws -> Reading {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(coord.latitude)),
            .init(name: "longitude", value: String(coord.longitude)),
            .init(name: "current_weather", value: "true")
        ]
        let (data, _) = try await URLSession.shared.data(from: c.url!)
        let m = try WeatherFormat.OpenMeteo.parse(data)
        let settings = TraySettings()
        return Reading(
            symbol: WeatherFormat.symbol(forWMO: m.code),
            tempText: WeatherFormat.temperature(celsius: m.temperatureC, unit: settings.temperatureUnit),
            fetched: Date()
        )
    }
}

/// One-shot CoreLocation wrapper: asks for when-in-use, resolves a single
/// fix, then stops. Kept separate so `WeatherProvider` stays testable.
final class LocationOnce: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let shared = LocationOnce()
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    func coordinate() async -> CLLocationCoordinate2D? {
        await withCheckedContinuation { cont in
            self.continuation = cont
            manager.delegate = self
            let status = manager.authorizationStatus
            if status == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else if status == .denied || status == .restricted {
                finish(nil)
            } else {
                manager.requestLocation()
            }
        }
    }

    private func finish(_ value: CLLocationCoordinate2D?) {
        continuation?.resume(returning: value)
        continuation = nil
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        switch m.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: m.requestLocation()
        case .denied, .restricted: finish(nil)
        default: break
        }
    }
    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        finish(locs.first?.coordinate)
    }
    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }
}
