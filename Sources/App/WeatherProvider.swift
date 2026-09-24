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
/// fix, then stops. Concurrent callers coalesce onto ONE in-flight request,
/// and every continuation is resumed exactly once. An NSLock guards the
/// mutable state, which is what makes the `@unchecked Sendable` sound; the
/// delegate is set once in init (never reassigned), so a fresh request is
/// kicked off only from `begin()`, never doubled by an authorization echo.
final class LocationOnce: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let shared = LocationOnce()
    private let manager = CLLocationManager()
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<CLLocationCoordinate2D?, Never>] = []
    private var requesting = false

    override init() {
        super.init()
        manager.delegate = self // once; never reassigned per-call
    }

    func coordinate() async -> CLLocationCoordinate2D? {
        await withCheckedContinuation { cont in
            lock.lock()
            waiters.append(cont)
            let shouldStart = !requesting
            if shouldStart { requesting = true }
            lock.unlock()
            // A second concurrent caller just rides the in-flight request.
            guard shouldStart else { return }
            Task { @MainActor in self.begin() } // CLLocationManager wants a run loop
        }
    }

    @MainActor private func begin() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: finish(nil)
        default: manager.requestLocation()
        }
    }

    /// Resumes every pending waiter exactly once and resets for the next request.
    private func finish(_ value: CLLocationCoordinate2D?) {
        lock.lock()
        let pending = waiters
        waiters.removeAll()
        requesting = false
        lock.unlock()
        for cont in pending { cont.resume(returning: value) }
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        lock.lock(); let active = requesting; lock.unlock()
        guard active else { return } // ignore the echo fired when the delegate was first set
        switch m.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: m.requestLocation()
        case .denied, .restricted: finish(nil)
        default: break // notDetermined: wait for the user's choice
        }
    }
    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        finish(locs.first?.coordinate)
    }
    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }
}
