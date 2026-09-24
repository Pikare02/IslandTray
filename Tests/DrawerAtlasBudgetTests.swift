import UIKit
import XCTest
@testable import IslandTray

/// Drawer icons must reach the island as an atlas, not be dropped for size:
/// six app-icon-like images (gradient + glyph) with names still fit a tier.
final class DrawerAtlasBudgetTests: XCTestCase {
    func testSixIconsKeepAnAtlas() async {
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
            if state.atlas != nil { chosen = q.side; break }
        }
        XCTAssertGreaterThan(chosen, 0)
    }
}
