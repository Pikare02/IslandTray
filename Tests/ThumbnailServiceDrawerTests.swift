import XCTest
import UIKit
@testable import IslandTray

final class ThumbnailServiceDrawerTests: XCTestCase {
    func testDrawerAtlasFilledFlags() async {
        let img = UIGraphicsImageRenderer(size: .init(width: 10, height: 10)).image { ctx in
            UIColor.red.setFill(); ctx.fill(.init(x: 0, y: 0, width: 10, height: 10))
        }
        let atlas = await ThumbnailService.shared.drawerAtlas(for: [img, nil, img])
        XCTAssertNotNil(atlas)
        XCTAssertEqual(atlas?.filled, [true, false, true])
    }

    func testEmptyReturnsNil() async {
        let atlas = await ThumbnailService.shared.drawerAtlas(for: [nil, nil])
        XCTAssertNil(atlas) // no real icons → nothing to composite
    }
}
