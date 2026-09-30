import UIKit
import XCTest
@testable import IslandTray

/// The reported bug: on the free build the Lock Screen is set to show the app
/// drawer while the tray holds an item. The drawer icons then ride in the
/// *combined* (tray + drawer) atlas, and when that atlas is dropped for size
/// every slot falls back to its SF Symbol -- which is what the user sees a
/// short while after the island settles onto the tray state.
final class LockScreenDrawerIconsTests: XCTestCase {
    // App-icon-like image: a gradient plus a white glyph, detailed enough to
    // be a fair stand-in for a real icon's compressed cost.
    private func icon(_ i: Int) -> UIImage {
        let colors: [UIColor] = [.systemBlue, .systemGreen, .systemOrange, .systemPink, .systemPurple, .systemTeal]
        let glyphs = ["star.fill", "heart.fill", "bolt.fill", "leaf.fill", "flame.fill", "globe"]
        return UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256)).image { ctx in
            let g = CGGradient(colorsSpace: nil,
                               colors: [colors[i % 6].cgColor, UIColor.black.cgColor] as CFArray, locations: nil)!
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 256, y: 256), options: [])
            UIImage(systemName: glyphs[i % 6])?.withTintColor(.white).draw(in: CGRect(x: 64, y: 64, width: 128, height: 128))
        }
    }

    private func item(_ name: String) -> TrayItem {
        TrayItem(id: UUID(), name: name, uti: "public.jpeg", size: 1, addedAt: Date(), ext: "jpeg")
    }

    /// Tray has one item; the Lock Screen shows the drawer's six icons. This is
    /// the exact free-build path `TrayActivityController.pagedState` takes:
    /// build the tray state, then `withDrawer(combined:lockDrawer:)`.
    func testLockScreenDrawerKeepsIconsWithOneTrayItem() async {
        let drawer: [UIImage?] = (0..<6).map { icon($0) }
        // One tray thumbnail tile, the way `islandAtlas` builds a single item's.
        let trayTile = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48)).image { ctx in
            UIColor.systemRed.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
            UIImage(systemName: "photo")?.withTintColor(.white).draw(in: CGRect(x: 8, y: 8, width: 32, height: 32))
        }
        let trayAtlas = TrayContentState.Atlas(jpeg: trayTile.jpegData(compressionQuality: 0.3)!, filled: [true])

        let combined = await ThumbnailService.shared.combinedAtlas(tray: trayAtlas, trayCount: 1, drawer: drawer)
        let slots = (0..<6).map { i in
            TrayContentState.DrawerSlot(symbol: "globe", name: "App \(i)",
                                        launch: "shortcuts://run-shortcut?name=App%20\(i)", hasIcon: true)
        }
        let tray = TrayContentState.make(from: [item("photo.jpeg")], atlas: trayAtlas, page: 0)
        let state = tray.withDrawer(slots, combined: combined, lockDrawer: true)

        let kept = state.drawer?.filter(\.hasIcon).count ?? 0
        print("combined jpeg=\(combined?.jpeg.count ?? -1)B, state=\(state.encodedByteCount)B, "
            + "atlas kept=\(state.atlas != nil), drawer icons kept=\(kept)/6")
        XCTAssertEqual(kept, 6, "Lock Screen drawer dropped its icons -> shows SF Symbols instead")
    }
}
