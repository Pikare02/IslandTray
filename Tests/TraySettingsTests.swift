import XCTest
@testable import IslandTray

final class TraySettingsTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "TraySettingsTests.\(UUID().uuidString)"
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    /// This is also the widget-can't-read-it test: the production fallback
    /// (App Group missing -> each process falls back to its own `.standard`)
    /// can't be forced from a test process, but the behavior it depends on
    /// can. A process that has never written this key locally -- which is
    /// exactly what the widget extension is, without a shared App Group -- is
    /// indistinguishable from a fresh, untouched suite, and must see the
    /// correct default rather than nil/false/a crash.
    func testDefaultsToShowingWhenEmpty() {
        let settings = TraySettings(defaults: userDefaults)
        XCTAssertTrue(
            settings.showActivityWhenEmpty,
            "the user's ask was for the island to stay up while the app is alive; the default must be on"
        )
    }

    func testWriteThenReadRoundTrips() {
        let settings = TraySettings(defaults: userDefaults)
        settings.showActivityWhenEmpty = false
        XCTAssertFalse(settings.showActivityWhenEmpty)
        settings.showActivityWhenEmpty = true
        XCTAssertTrue(settings.showActivityWhenEmpty)
    }
}
