import SwiftUI
import UIKit

/// Shared by the expanded Dynamic Island and the Lock Screen presentation.
///
/// Thumbnails come from the content state itself -- one JPEG strip with a tile
/// per preview -- because this process cannot read the tray container without
/// the App Group entitlement, which does not survive SideStore's re-signing.
/// When the entitlement *is* present the higher-resolution file on disk wins;
/// when neither is available the preview falls back to its SF Symbol.
struct TrayPreviewStrip: View {
    let previews: [TrayContentState.Preview]
    /// The JPEG strip from the content state, sliced by preview index.
    var atlas: Data?
    var side: CGFloat = 36

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(previews.enumerated()), id: \.element.id) { index, preview in
                VStack(spacing: 2) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(.white.opacity(0.14))
                        if let image = thumbnail(for: preview, at: index) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        } else {
                            Image(systemName: preview.symbol)
                                .font(.system(size: side * 0.42))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .frame(width: side, height: side)

                    Text(preview.name)
                        .font(.system(size: 9))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.white.opacity(0.7))
                        // Wider than the tile so a short name is readable,
                        // still narrow enough that four of them fit the
                        // island's bottom region.
                        .frame(width: side * 1.5)
                }
            }
        }
    }

    private func thumbnail(for preview: TrayContentState.Preview, at index: Int) -> UIImage? {
        containerThumbnail(for: preview) ?? atlasTile(at: index, filled: preview.hasThumbnail)
    }

    private func containerThumbnail(for preview: TrayContentState.Preview) -> UIImage? {
        guard TrayContainer.isShared else { return nil }
        let url = TrayContainer.thumbsDirectory.appendingPathComponent("\(preview.id).png")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// The `index`-th square tile of the strip.
    ///
    /// The tile side is derived rather than carried in the content state: the
    /// strip is always `previews.count` squares wide, so the width alone
    /// determines it. A strip whose width is not a whole multiple of the
    /// count -- which would mean it was built for a different preview list --
    /// is refused rather than sliced at an offset.
    private func atlasTile(at index: Int, filled: Bool) -> UIImage? {
        guard filled, let atlas, !previews.isEmpty,
              let image = UIImage(data: atlas)?.cgImage else { return nil }
        let tile = image.height
        guard tile > 0, image.width == tile * previews.count, index < previews.count else { return nil }
        guard let cropped = image.cropping(
            to: CGRect(x: tile * index, y: 0, width: tile, height: tile)
        ) else { return nil }
        return UIImage(cgImage: cropped)
    }
}
