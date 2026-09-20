import SwiftUI

/// One tray item. Presentation only: the drag, the selection and the layout
/// all belong to `TrayGridView`, which is where iOS puts them -- a collection
/// view is the only thing that can add a second item to a drag already in
/// flight.
struct TrayCardView: View {
    let item: TrayItem
    var isSelecting = false
    var isSelected = false
    let onDelete: () -> Void

    // The thumbnail generator takes the scale rather than discovering it: read
    // off the main thread, UITraitCollection.current is unset and everything
    // silently renders at 2x. This environment value is the authoritative scale
    // for this view.
    @Environment(\.displayScale) private var displayScale
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.quaternary)
                if let thumbnail {
                    // scaledToFit, not Fill: a tall photo cropped to a square
                    // tile shows a strip of its middle, which is the least
                    // recognisable part of it. Fitting keeps the whole image
                    // inside the tile the grid gives it.
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .padding(5)
                } else {
                    Image(systemName: item.symbolName)
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                }
                if isSelecting { selectionBadge }
            }
            .aspectRatio(1, contentMode: .fit)

            Text(item.name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .task(id: item.id) {
            thumbnail = await ThumbnailService.shared.thumbnail(for: item, scale: displayScale)
        }
        .contextMenu {
            // No markExported here, unlike the drag: ShareLink reports neither
            // success nor cancellation, and its Transferable is exported when
            // an activity is *picked* -- a user who backs out of the Files
            // picker after that would lose the file. Sharing therefore always
            // leaves the item in the tray, whatever `removeOnExport` says.
            ShareLink(item: SharedTrayFile(item: item), preview: SharePreview(item.name)) {
                Label("共有", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive, action: onDelete) {
                Label("削除", systemImage: "trash")
            }
        }
    }

    private var selectionBadge: some View {
        VStack {
            HStack {
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, isSelected ? Color.accentColor : Color.black.opacity(0.4))
                    .padding(6)
            }
            Spacer()
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
struct SharedTrayFile: Transferable {
    let item: TrayItem

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.item.fileURL)
            .suggestedFileName { $0.item.name }
    }
}
