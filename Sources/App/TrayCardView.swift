import SwiftUI

struct TrayCardView: View {
    let item: TrayItem
    let onDelete: () -> Void

    // The thumbnail generator takes the scale rather than discovering it: read
    // off the main thread, UITraitCollection.current is unset and everything
    // silently renders at 2x. This environment value is the authoritative scale
    // for this view.
    @Environment(\.displayScale) private var displayScale
    @State private var thumbnail: UIImage?

    private static let cardWidth: CGFloat = 104

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.quaternary)
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    Image(systemName: item.symbolName)
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: Self.cardWidth, height: Self.cardWidth)

            Text(item.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: Self.cardWidth)
        }
        .task(id: item.id) {
            thumbnail = await ThumbnailService.shared.thumbnail(for: item, scale: displayScale)
        }
        // onDrag rather than .draggable: this hands other apps the actual file
        // rather than a link to it.
        .onDrag { NSItemProvider(contentsOf: item.fileURL) ?? NSItemProvider() }
        .contextMenu {
            ShareLink(item: item.fileURL) {
                Label("共有", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive, action: onDelete) {
                Label("削除", systemImage: "trash")
            }
        }
    }
}
