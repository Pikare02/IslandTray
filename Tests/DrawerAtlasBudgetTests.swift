import UIKit
import XCTest
@testable import IslandTray

/// Six app-icon-like images (gradient + glyph) with names should get a
/// sharper strip than the tray's 48px default under the state budget.
final class DrawerAtlasBudgetTests: XCTestCase {
    func testSixIconsFitAboveTrayResolution() async {
        let colors: [UIColor] = [.systemBlue, .systemGreen, .systemOrange, .systemPink, .systemPurple, .systemTeal]
        let images: [UIImage?] = colors.enumerated().map { i, c in
            UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256)).image { ctx in
                let g = CGGradient(colorsSpace: nil, colors: [c.cgColor, UIColor.black.cgColor] as CFArray, locations: nil)!
                ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 256, y: 256), options: [])
                UIImage(systemName: ["star.fill", "heart.fill", "bolt.fill", "leaf.fill", "flame.fill", "globe"][i])?
                    .withTintColor(.white).draw(in: CGRect(x: 64, y: 64, width: 128, height: 128))
            }
        }
        let slots = (0..<6).map {
            TrayContentState.DrawerSlot(symbol: "globe", name: "App \($0)",
                                        launch: "shortcuts://run-shortcut?name=App%20\($0)", hasIcon: true)
        }
        let weather = TrayContentState.Weather(dateText: "SEP 24 THU", tempText: "21°", symbol: "sun.max")
        var chosen = 0
        for q in ThumbnailService.drawerQualities {
            let atlas = await ThumbnailService.shared.drawerAtlas(for: images, side: q.side, quality: q.quality)
            let state = TrayContentState.makeDrawer(weather: weather, slots: slots, atlas: atlas, view: .drawer, count: 0)
            print("tier \(q.side)px q\(q.quality): jpeg=\(atlas?.jpeg.count ?? -1) \(state.encodedByteCount)B atlas=\(state.atlas != nil)")
            if let fitted = state.atlas {
                chosen = q.side
                // WebP ("RIFF....WEBP"), and it decodes back into six tiles
                // the way the widget reads it.
                XCTAssertEqual(String(decoding: fitted.prefix(4), as: UTF8.self), "RIFF")
                XCTAssertEqual(String(decoding: fitted.dropFirst(8).prefix(4), as: UTF8.self), "WEBP")
                XCTAssertEqual(AtlasSlicer.tiles(fitted).count, 6)
                break
            }
        }
        XCTAssertGreaterThan(chosen, 48)
    }
}
