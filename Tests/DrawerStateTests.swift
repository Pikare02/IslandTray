import XCTest
@testable import IslandTray

final class DrawerStateTests: XCTestCase {
    func testSlotsMapLaunchAndName() {
        let items = [
            DrawerShortcut(id: UUID(), kind: .webURL("https://a"), displayName: "A", customIconName: nil, order: 0),
            DrawerShortcut(id: UUID(), kind: .shortcut(name: "M"), displayName: "M", customIconName: nil, order: 1)
        ]
        let slots = DrawerState.slots(from: items, showNames: true)
        XCTAssertEqual(slots.count, 2)
        XCTAssertEqual(slots[0].launch, "https://a")
        XCTAssertEqual(slots[0].name, "A")
        XCTAssertEqual(slots[1].launch, "shortcuts://run-shortcut?name=M")
    }

    func testNamesBlankedWhenHidden() {
        let items = [DrawerShortcut(id: UUID(), kind: .webURL("https://a"), displayName: "A", customIconName: nil, order: 0)]
        XCTAssertEqual(DrawerState.slots(from: items, showNames: false)[0].name, "")
    }

    func testCappedToMax() {
        let items = (0..<10).map { DrawerShortcut(id: UUID(), kind: .webURL("https://\($0)"), displayName: "\($0)", customIconName: nil, order: $0) }
        XCTAssertEqual(DrawerState.slots(from: items, showNames: true).count, TrayContentState.maxSlots)
    }
}
