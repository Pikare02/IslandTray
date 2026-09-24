import UIKit

/// High-resolution drawer icons as files in the App Group container, for
/// builds that have one (TrollStore). The widget reads these directly, so
/// they are not bound by the content state's 4096 bytes the way the atlas
/// is. Without a shared container (the free build) this does nothing and
/// the atlas is the only path.
///
/// Files are per island slot (0..<maxSlots), not per shortcut: the app
/// rewrites every slot on each sync and removes the file of a slot with no
/// icon, so a file on disk is always this slot's current icon.
enum DrawerIconFiles {
    /// 3x of the largest tile the island draws (~60pt).
    static let side: CGFloat = 180
    static let quality: CGFloat = 0.9

    static var isAvailable: Bool { TrayContainer.isShared }

    static func url(slot: Int) -> URL {
        TrayContainer.root.appendingPathComponent("DrawerIcons", isDirectory: true)
            .appendingPathComponent("slot-\(slot).jpg")
    }

    /// Widget side: this slot's icon, or nil (then atlas, then SF Symbol).
    static func image(slot: Int) -> UIImage? {
        guard isAvailable, let data = try? Data(contentsOf: url(slot: slot)) else { return nil }
        return UIImage(data: data)
    }

    /// App side: writes `images[i]` as slot i's file, removing slots with no
    /// image and every slot past the end. Returns false when there is no
    /// shared container, so the caller falls back to the atlas.
    @discardableResult
    static func write(_ images: [UIImage?]) -> Bool {
        guard isAvailable else { return false }
        let dir = url(slot: 0).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for slot in 0..<TrayContentState.maxSlots {
            let target = url(slot: slot)
            if slot < images.count, let image = images[slot], let data = squared(image).jpegData(compressionQuality: quality) {
                try? data.write(to: target, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: target)
            }
        }
        return true
    }

    private static func squared(_ image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            ctx.cgContext.interpolationQuality = .high
            let k = max(side / max(1, image.size.width), side / max(1, image.size.height))
            let w = image.size.width * k, h = image.size.height * k
            image.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        }
    }
}
