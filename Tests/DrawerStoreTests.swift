import XCTest
@testable import IslandTray

final class DrawerStoreTests: XCTestCase {
    /// Documents is the Files-app inbox; a drawer folder there gets swept
    /// into the tray as an item and deleted.
    func testDefaultLocationIsOutsideFilesInbox() {
        XCTAssertFalse(DrawerStore().dir.path.hasPrefix(DocumentsInbox.directory.path))
    }

    func testLaunchURLPerKind() {
        let scheme = DrawerShortcut(id: UUID(), kind: .urlScheme("instagram://"),
                                    displayName: "IG", customIconName: nil, order: 0)
        XCTAssertEqual(scheme.launchURL, URL(string: "instagram://"))

        let web = DrawerShortcut(id: UUID(), kind: .webURL("https://x.com"),
                                 displayName: "X", customIconName: nil, order: 1)
        XCTAssertEqual(web.launchURL, URL(string: "https://x.com"))

        let sc = DrawerShortcut(id: UUID(), kind: .shortcut(name: "Morning"),
                                displayName: "Morning", customIconName: nil, order: 2)
        XCTAssertEqual(sc.launchURL, URL(string: "shortcuts://run-shortcut?name=Morning"))

        let id = UUID()
        let app = DrawerShortcut(id: id, kind: .installedApp(bundleID: "com.apple.Maps"),
                                 displayName: "Maps", customIconName: nil, order: 3)
        XCTAssertEqual(app.launchURL, URL(string: "islandtray://launch?item=\(id.uuidString)"))
    }

    func testCodableRoundTrip() throws {
        let items = [DrawerShortcut(id: UUID(), kind: .webURL("https://a.b"),
                                    displayName: "A", customIconName: "x.jpg", order: 0)]
        let data = try JSONEncoder().encode(items)
        let back = try JSONDecoder().decode([DrawerShortcut].self, from: data)
        XCTAssertEqual(back, items)
    }
}
