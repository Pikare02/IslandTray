import SwiftUI

/// The app-drawer row in the expanded island: up to six launchable tiles
/// plus a "more" tile that opens the full drawer in the app. Icons come from
/// the same atlas mechanism as tray previews (see `AtlasSlicer`); a slot with
/// no atlas tile falls back to its SF Symbol.
struct DrawerStrip: View {
    let slots: [TrayContentState.DrawerSlot]
    let atlas: Data?
    let side: CGFloat
    /// Where the drawer's tiles start in `atlas`: after the tray's own on a
    /// tray state carrying the drawer, 0 on a drawer state.
    var atlasOffset = 0

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                if let url = URL(string: slot.launch) {
                    Link(destination: url) { tile(slot, index: index) }
                } else {
                    tile(slot, index: index)
                }
            }
            Link(destination: URL(string: "\(TrayIDs.urlScheme)://drawer")!) {
                VStack(spacing: 2) {
                    Image(systemName: "ellipsis")
                        .frame(width: side, height: side)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    Text(L.s("drawer.more")).font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private func tile(_ slot: TrayContentState.DrawerSlot, index: Int) -> some View {
        VStack(spacing: 2) {
            iconImage(index)
                .frame(width: side, height: side)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            if !slot.name.isEmpty {
                Text(slot.name).font(.system(size: 9)).lineLimit(1).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func iconImage(_ index: Int) -> some View {
        if slots[index].hasIcon, let ui = AtlasSlicer.tile(atlas, index: atlasOffset + index) {
            Image(uiImage: ui).resizable().aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            Image(systemName: slots[index].symbol).font(.title3).foregroundStyle(.white)
        }
    }
}
