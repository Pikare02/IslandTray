import XCTest
@testable import IslandTray

/// The test host is the app itself, whose window listens for the launch
/// notification and takes the pending URL the moment it is posted -- which
/// is the real behaviour. So these watch the notification rather than the
/// slot it leaves behind.
@MainActor
final class LaunchDrawerSlotIntentTests: XCTestCase {
    func testPerformHandsTheURLToTheApp() async throws {
        // Our own scheme with an unknown host: the host app's window routes
        // it to `.ignore`, so the test never sends the host to another app.
        let posted = expectation(forNotification: .launchDrawerSlot, object: nil) { note in
            (note.object as? URL)?.host == "test"
        }
        _ = try await LaunchDrawerSlotIntent(launch: "islandtray://test").perform()
        await fulfillment(of: [posted], timeout: 1)
        // Whoever listened took it; a later listener finds nothing, so the
        // launch runs once.
        XCTAssertNil(LaunchDrawerSlotIntent.takePending())
    }

    /// An empty launch, not a malformed one: since iOS 17 `URL(string:)`
    /// percent-encodes almost anything into a URL.
    func testAnEmptyLaunchPostsNothing() async throws {
        let posted = expectation(forNotification: .launchDrawerSlot, object: nil)
        posted.isInverted = true
        _ = try await LaunchDrawerSlotIntent(launch: "").perform()
        await fulfillment(of: [posted], timeout: 0.3)
        XCTAssertNil(LaunchDrawerSlotIntent.takePending())
    }
}
