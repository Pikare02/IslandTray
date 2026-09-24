import XCTest
@testable import IslandTray

final class LaunchRouterTests: XCTestCase {
    func testRoutes() {
        XCTAssertEqual(LaunchRouter.route(URL(string: "islandtray://drop")!), .drop)
        XCTAssertEqual(LaunchRouter.route(URL(string: "islandtray://drawer")!), .drawer)
        let id = UUID()
        XCTAssertEqual(LaunchRouter.route(URL(string: "islandtray://launch?item=\(id.uuidString)")!), .launch(id))
        XCTAssertEqual(LaunchRouter.route(URL(string: "islandtray://launch?item=notauuid")!), .ignore)
        XCTAssertEqual(LaunchRouter.route(URL(string: "https://example.com")!), .ignore)
        // launch with no item param, and an unknown host, both fall closed.
        XCTAssertEqual(LaunchRouter.route(URL(string: "islandtray://launch")!), .ignore)
        XCTAssertEqual(LaunchRouter.route(URL(string: "islandtray://unknownhost")!), .ignore)
    }
}
