import SwiftUI

/// The app-drawer row in the expanded island: up to six launchable tiles.
/// The full drawer is a tap on the island's empty space (its widgetURL). Icons come from
/// the same atlas mechanism as tray previews (see `AtlasSlicer`); a slot with
/// no atlas tile falls back to its SF Symbol.
struct DrawerStrip: View {
    let slots: [TrayContentState.DrawerSlot]
    let atlas: Data?
    /// Tile edge with names shown; tiles grow when names are hidden. Either
    /// way a tile shrinks to fit when the row is narrower than six of them.
    let side: CGFloat
    /// Where the drawer's tiles start in `atlas`: after the tray's own on a
    /// tray state carrying the drawer, 0 on a drawer state.
    var atlasOffset = 0

    /// Names off in the app's drawer settings arrive as empty strings.
    private var showsNames: Bool { slots.contains { !$0.name.isEmpty } }
    private var maxSide: CGFloat { showsNames ? side : side * 1.3 }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                if let url = URL(string: slot.launch) {
                    Link(destination: url) { tile(slot.name) { iconImage(index) } }
                } else {
                    tile(slot.name) { iconImage(index) }
                }
            }
        }
    }

    /// A square that takes its share of the row, capped at `maxSide`.
    private func tile<Icon: View>(_ name: String, @ViewBuilder icon: () -> Icon) -> some View {
        VStack(spacing: 2) {
            Color.white.opacity(0.08)
                .aspectRatio(1, contentMode: .fit)
                .overlay { icon() }
                .clipShape(RoundedRectangle(cornerRadius: 10))
            if !name.isEmpty {
                Text(name).font(.system(size: 9)).lineLimit(1).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: maxSide)
    }

    @ViewBuilder private func iconImage(_ index: Int) -> some View {
        if slots[index].hasIcon, let ui = AtlasSlicer.tile(atlas, index: atlasOffset + index) {
            Image(uiImage: ui).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
        } else {
            Image(systemName: slots[index].symbol).font(.title3).foregroundStyle(.white)
        }
    }
}
