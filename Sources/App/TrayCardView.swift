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
        .onDrag {
            // NSItemProvider(contentsOf:) takes its suggested filename from
            // the URL's last path component, which is `item.fileURL`'s
            // UUID-based on-disk name (TrayItem deliberately never builds a
            // path from `name`, only from the id). Overriding `suggestedName`
            // is what makes Files/Mail/other drop targets save the file under
            // its real display name instead of the UUID -- it does not
            // rename anything on disk.
            let provider = NSItemProvider(contentsOf: item.fileURL) ?? NSItemProvider()
            provider.suggestedName = item.name
            return provider
        }
        .contextMenu {
            ShareLink(item: SharedTrayFile(item: item), preview: SharePreview(item.name)) {
                Label("共有", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive, action: onDelete) {
                Label("削除", systemImage: "trash")
            }
        }
    }
}

/// Wraps a tray item for `ShareLink` so the share sheet's exported file
/// (Save to Files, a Mail attachment, AirDrop, ...) is named after the item's
/// display name instead of `item.fileURL`'s UUID-based on-disk filename.
/// Storage is untouched -- this only changes the name the file carries once
/// it leaves the tray.
///
/// `ProxyRepresentation` just forwards the export to `URL`'s own
/// `Transferable` conformance, so the receiver still gets correct
/// content-type inference from the actual file; `.suggestedFileName` (which
/// takes a per-instance closure, not a fixed string, since every item needs a
/// different name) is the only thing added.
private struct SharedTrayFile: Transferable {
    let item: TrayItem

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.item.fileURL)
            .suggestedFileName { $0.item.name }
    }
}
