import CoreLocation
import Foundation

/// Fetches current weather from Open-Meteo for the current (or a pinned)
/// location and caches the last reading. Only the app process uses this; it
/// hands a finished `Reading` to the content state.
actor WeatherProvider {
    static let shared = WeatherProvider()

    struct Reading: Codable {
        let symbol: String
        /// Raw Celsius, not a formatted string: the display unit is applied
        /// where the state is built, so toggling °C/°F re-renders the cached
        /// reading without a re-fetch. (Older caches stored a `tempText`
        /// string; those simply fail to decode and trigger one fresh fetch.)
        let celsius: Double
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
        return Reading(
            symbol: WeatherFormat.symbol(forWMO: m.code),
            celsius: m.temperatureC,
            fetched: Date()
        )
    }
}

/// One-shot CoreLocation wrapper: asks for when-in-use, resolves a single
/// fix, then stops. Concurrent callers coalesce onto ONE in-flight request;
/// every continuation is resumed exactly once. The manager is created lazily
/// on the main actor (a manager made on the WeatherProvider actor's executor
/// has no run loop and its delegate callbacks may never fire); a fail-safe
/// timeout guarantees a caller is never left awaiting forever. An NSLock
/// guards the mutable state (sound `@unchecked Sendable`).
final class LocationOnce: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let shared = LocationOnce()
    static let timeout: Duration = .seconds(8)

    private let lock = NSLock()
    private var manager: CLLocationManager?
    private var waiters: [CheckedContinuation<CLLocationCoordinate2D?, Never>] = []
    private var requesting = false
    private var cycle = 0

    func coordinate() async -> CLLocationCoordinate2D? {
        await withCheckedContinuation { cont in
            lock.lock()
            waiters.append(cont)
            let shouldStart = !requesting
            if shouldStart { requesting = true; cycle &+= 1 }
            let startedCycle = cycle
            lock.unlock()
            guard shouldStart else { return } // ride the in-flight request
            Task { @MainActor in self.begin(cycle: startedCycle) }
        }
    }

    @MainActor private func begin(cycle startedCycle: Int) {
        let m: CLLocationManager
        if let existing = manager {
            m = existing
        } else {
            m = CLLocationManager()
            m.delegate = self // created & set on the main run loop
            manager = m
        }
        // Fail-safe: never leave a caller awaiting forever.
        Task { @MainActor in
            try? await Task.sleep(for: Self.timeout)
            self.finish(nil, forCycle: startedCycle)
        }
        switch m.authorizationStatus {
        case .notDetermined: m.requestWhenInUseAuthorization()
        case .denied, .restricted: finish(nil, forCycle: startedCycle)
        default: m.requestLocation()
        }
    }

    /// Resumes every pending waiter exactly once, then resets. `forCycle`
    /// makes a stale timeout/callback from a finished cycle a no-op.
    private func finish(_ value: CLLocationCoordinate2D?, forCycle c: Int?) {
        lock.lock()
        if let c, c != cycle { lock.unlock(); return }
        guard requesting else { lock.unlock(); return }
        let pending = waiters
        waiters.removeAll()
        requesting = false
        lock.unlock()
        for cont in pending { cont.resume(returning: value) }
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        lock.lock(); let active = requesting; let c = cycle; lock.unlock()
        guard active else { return }
        switch m.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: m.requestLocation()
        case .denied, .restricted: finish(nil, forCycle: c)
        default: break
        }
    }
    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        lock.lock(); let c = cycle; lock.unlock()
        finish(locs.first?.coordinate, forCycle: c)
    }
    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        lock.lock(); let c = cycle; lock.unlock()
        finish(nil, forCycle: c)
    }
}
