import UIKit

/// Slices one square tile out of an atlas JPEG strip -- `count` equal-width
/// tiles laid left to right, one per item, in that item's order.
///
/// Shared by `TrayPreviewStrip` (tray previews) and `DrawerStrip` (drawer
/// slots): both receive their atlas the same way in `TrayContentState`, so
/// the slicing math lives here once instead of twice.
enum AtlasSlicer {
    /// The `index`-th square tile of `atlas`, or `nil` when the atlas is
    /// absent, malformed, or was not built for `count` tiles.
    ///
    /// The tile side is derived rather than carried alongside the atlas: the
    /// strip is always `count` squares wide, so the width alone determines
    /// it. A strip whose width is not a whole multiple of `count` -- which
    /// would mean it was built for a different list -- is refused rather
    /// than sliced at an offset.
    /// Every square tile of the strip, decoded once, the count taken from
    /// the strip itself (width / height) -- a tray strip may have the
    /// drawer's icons appended after the tray's own tiles.
    ///
    /// For the widget: call this once per render, never per tile. Decoding
    /// the whole strip for each tile (twice, in 1.7.0 Nightly 4) pushed the
    /// Live Activity past its memory/time limit, and the system then drew
    /// the entire island as grey placeholders.
    static func tiles(_ atlas: Data?) -> [UIImage] {
        guard let atlas, let image = UIImage(data: atlas)?.cgImage,
              image.height > 0, image.width % image.height == 0 else { return [] }
        let side = image.height
        return (0..<(image.width / side)).compactMap { i in
            image.cropping(to: CGRect(x: side * i, y: 0, width: side, height: side)).map(UIImage.init(cgImage:))
        }
    }

    static func tile(_ atlas: Data?, index: Int, count: Int) -> UIImage? {
        guard count > 0, index >= 0, index < count,
              let atlas, let image = UIImage(data: atlas)?.cgImage else { return nil }
        let side = image.height
        guard side > 0, image.width == side * count else { return nil }
        guard let cropped = image.cropping(
            to: CGRect(x: side * index, y: 0, width: side, height: side)
        ) else { return nil }
        return UIImage(cgImage: cropped)
    }
}
