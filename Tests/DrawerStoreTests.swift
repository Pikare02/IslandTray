import UIKit
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

final class DrawerSortTests: XCTestCase {
    private func item(_ name: String, _ order: Int, _ added: TimeInterval?) -> DrawerShortcut {
        DrawerShortcut(id: UUID(), kind: .webURL("https://\(name)"), displayName: name, customIconName: nil,
                       order: order, addedAt: added.map { Date(timeIntervalSince1970: $0) })
    }

    func testSortsAndRenumbers() {
        let items = [item("b", 0, 20), item("A", 1, nil), item("c", 2, 10), item("a2", 3, nil)]
        XCTAssertEqual(DrawerShortcut.sorted(items, by: .name).map(\.displayName), ["A", "a2", "b", "c"])
        // Undated entries count as oldest and keep their relative order.
        XCTAssertEqual(DrawerShortcut.sorted(items, by: .oldest).map(\.displayName), ["A", "a2", "c", "b"])
        XCTAssertEqual(DrawerShortcut.sorted(items, by: .newest).map(\.displayName), ["b", "c", "A", "a2"])
        XCTAssertEqual(DrawerShortcut.sorted(items, by: .name).map(\.order), [0, 1, 2, 3])
    }
}

final class AtlasSlicerTests: XCTestCase {
    func testTilesDecodesEverySquare() {
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        let strip = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 10), format: f).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        XCTAssertEqual(AtlasSlicer.tiles(strip.jpegData(compressionQuality: 0.5)).count, 3)
        XCTAssertTrue(AtlasSlicer.tiles(nil).isEmpty)
    }
}
