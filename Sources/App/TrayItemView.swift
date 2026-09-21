import SwiftUI
import UniformTypeIdentifiers

/// One item, as a card in a grid or a row in a list. Presentation only: the
/// drag, the selection and the layout all belong to `TrayGridView`, which is
/// where iOS puts them -- a collection view is the only thing that can add a
/// second item to a drag already in flight.
struct TrayItemView: View {
    enum Style {
        case card
        case row
    }

    let item: TrayItem
    var style: Style = .card
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
        content
            .task(id: item.id) {
                thumbnail = await ThumbnailService.shared.thumbnail(for: item, scale: displayScale)
            }
            .contextMenu {
                // No markExported here, unlike the drag: ShareLink reports
                // neither success nor cancellation, and its Transferable is
                // exported when an activity is *picked* -- a user who backs
                // out of the Files picker after that would lose the file.
                // Sharing therefore always leaves the item where it is,
                // whatever `removeOnExport` says.
                ShareLink(item: SharedTrayFile(item: item), preview: SharePreview(item.name)) {
                    Label(L.s("common.share"), systemImage: "square.and.arrow.up")
                }
                if isClipboard || UTType(item.uti)?.conforms(to: .text) == true {
                    Button { RichText.copy(item) } label: {
                        Label(L.s("common.copy"), systemImage: "doc.on.doc")
                    }
                }
                Button(role: .destructive, action: onDelete) {
                    Label(L.s("common.delete"), systemImage: "trash")
                }
            }
    }

    private var isClipboard: Bool { item.boardOrTray == .clipboard }

    /// On the clipboard board the name is a copy button: putting a kept item
    /// back on the system clipboard is what that board is for. Anywhere else,
    /// and while selecting, it is only a label and a tap opens the item.
    @ViewBuilder
    private func name(_ text: some View) -> some View {
        if isClipboard && !isSelecting {
            Button { RichText.copy(item) } label: { text }
                .buttonStyle(.plain)
                .accessibilityHint(L.s("common.copy"))
        } else {
            text
        }
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .card: card
        case .row: row
        }
    }

    private var row: some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary)
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .padding(3)
                } else {
                    Image(systemName: item.symbolName)
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                name(Text(item.name)
                    .lineLimit(2)
                    .truncationMode(.middle))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    /// Size and when it arrived, which is what a timeline row is for.
    private var subtitle: String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file)
        let added = item.addedAt.formatted(date: .abbreviated, time: .shortened)
        return "\(size) · \(added)"
    }

    private var card: some View {
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

            name(Text(item.name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle))
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
