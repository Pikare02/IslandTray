import SwiftUI

/// One drawer slot's picture, in the order the island has always used:
/// the full-resolution file (shared-container builds), then the slot's
/// atlas tile, then the kind's SF Symbol.
struct DrawerIcon: View {
    let slot: TrayContentState.DrawerSlot
    /// The slot's position in the island's drawer, which names its icon file.
    let index: Int
    let tiles: [UIImage]
    /// Where the drawer's tiles start in `tiles`.
    var atlasOffset = 0
    var symbolFont: Font = .title3

    var body: some View {
        if let file = DrawerIconFiles.image(slot: index) {
            Image(uiImage: file).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
        } else if slot.hasIcon, tiles.indices.contains(atlasOffset + index) {
            Image(uiImage: tiles[atlasOffset + index])
                .resizable().interpolation(.high).aspectRatio(contentMode: .fill)
        } else {
            Image(systemName: slot.symbol).font(symbolFont).foregroundStyle(.white)
        }
    }
}
