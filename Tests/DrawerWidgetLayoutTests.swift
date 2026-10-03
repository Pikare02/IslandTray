import WidgetKit
import XCTest
@testable import IslandTray

final class DrawerWidgetLayoutTests: XCTestCase {
    private func slots(_ n: Int) -> [TrayContentState.DrawerSlot] {
        (0..<n).map { .init(symbol: "app", name: "App\($0)", launch: "https://example.com/\($0)", hasIcon: false) }
    }

    func testColumnsPerFamily() {
        XCTAssertEqual(DrawerWidgetLayout.columns(for: .systemSmall), 3)
        XCTAssertEqual(DrawerWidgetLayout.columns(for: .systemMedium), 5)
        XCTAssertEqual(DrawerWidgetLayout.columns(for: .accessoryRectangular), 4)
    }

    func testCapacityPerFamily() {
        XCTAssertEqual(DrawerWidgetLayout.capacity(for: .systemSmall), 9)
        XCTAssertEqual(DrawerWidgetLayout.capacity(for: .systemMedium), 9)
        XCTAssertEqual(DrawerWidgetLayout.capacity(for: .accessoryRectangular), 4)
    }

    func testShownTakesTheFirstUpToTheSettingAndTheCapacity() {
        let nine = slots(9)
        XCTAssertEqual(DrawerWidgetLayout.shown(nine, count: 9, family: .systemSmall).map(\.name).last, "App8")
        XCTAssertEqual(DrawerWidgetLayout.shown(nine, count: 4, family: .systemSmall).count, 4)
        // The rectangle holds four whatever the setting says.
        XCTAssertEqual(DrawerWidgetLayout.shown(nine, count: 9, family: .accessoryRectangular).count, 4)
        // Fewer slots than the setting: all of them, in order.
        XCTAssertEqual(DrawerWidgetLayout.shown(slots(2), count: 9, family: .systemMedium).map(\.name), ["App0", "App1"])
    }

    func testANonsenseCountShowsNothingRatherThanCrashing() {
        XCTAssertEqual(DrawerWidgetLayout.shown(slots(3), count: 0, family: .systemSmall).count, 0)
        XCTAssertEqual(DrawerWidgetLayout.shown(slots(3), count: -5, family: .systemSmall).count, 0)
    }
}
