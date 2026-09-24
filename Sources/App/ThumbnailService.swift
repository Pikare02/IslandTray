import QuickLookThumbnailing
import UIKit

/// Generates and caches thumbnails using the same API the Files app uses,
/// so tray items look exactly like they do in Files.
actor ThumbnailService {
    static let shared = ThumbnailService()

    private static let pointSize = CGSize(width: 120, height: 120)
    private var inFlight: [UUID: Task<UIImage?, Never>] = [:]

    /// - Parameter scale: the display scale of the context the thumbnail will be
    ///   shown in. Required, no default: `UITraitCollection.current` can't be
    ///   trusted here — it's thread-local, and this actor never runs on the main
    ///   thread, so it would always read as unset. The caller must supply the real
    ///   scale, e.g. a SwiftUI view's `@Environment(\.displayScale)`.
    func thumbnail(for item: TrayItem, scale: CGFloat) async -> UIImage? {
        // Defensive clamp against a genuinely invalid value (0 or negative),
        // not a substitute for the caller passing the real display scale.
        let scale = scale > 0 ? scale : 2
        if let cached = loadCached(item, scale: scale) { return cached }
        if let running = inFlight[item.id] { return await running.value }

        let task = Task<UIImage?, Never> {
            let request = QLThumbnailGenerator.Request(
                fileAt: item.fileURL,
                size: Self.pointSize,
                scale: scale,
                representationTypes: .all
            )
            guard let rep = try? await QLThumbnailGenerator.shared
                .generateBestRepresentation(for: request) else { return nil }
            return rep.uiImage
        }
        inFlight[item.id] = task

        let image = await task.value
        inFlight[item.id] = nil
        if let image { store(image, for: item) }
        return image
    }

    func removeCache(for item: TrayItem) {
        try? FileManager.default.removeItem(at: item.thumbnailURL)
    }

    // MARK: - Dynamic Island atlas

    /// Tile side in pixels for the island strip.
    ///
    /// 48px against a 40pt tile is barely over 1x — soft on a 3x screen, and
    /// chosen anyway because the whole strip has to fit in what is left of
    /// ActivityKit's 4096 bytes after four names and four ids. Measured worst
    /// case (16 screenshots, the worst content for JPEG) as base64: 48px/0.3
    /// = 2496 bytes and fits with ~460 to spare; 64px/0.3 = 3684 and does
    /// not, so a tray of four screenshots would lose its thumbnails
    /// altogether. A soft thumbnail beats a generic icon, which is what this
    /// whole path exists to replace.
    private static let atlasTile = 48
    private static let atlasQuality: CGFloat = 0.3

    /// Last strip built, keyed by the exact item ids it covers.
    ///
    /// `sync()` runs on every drop, delete and foreground, and the foreground
    /// case usually asks for a strip identical to the last one. One entry is
    /// enough for that; any change to the tray rebuilds all of it, which is a
    /// handful of thumbnail requests on a user action.
    private var cachedAtlas: (ids: [UUID], atlas: TrayContentState.Atlas?)?

    /// A JPEG strip of up to `TrayContentState.maxPreviews` tiles for the
    /// Live Activity, or `nil` when no item yielded a thumbnail.
    ///
    /// This does not go through `thumbnail(for:scale:)` or its disk cache on
    /// purpose. That cache is keyed by item alone with the scale supplied by
    /// the caller, so priming it from here — where there is no display scale
    /// to read — would leave the card view loading pixels rendered for a
    /// different scale. The island needs 64px; asking QuickLook for exactly
    /// that is cheaper than the 240px the card wants anyway.
    func islandAtlas(for items: [TrayItem]) async -> TrayContentState.Atlas? {
        let items = Array(items.prefix(TrayContentState.maxPreviews))
        let ids = items.map(\.id)
        if let cached = cachedAtlas, cached.ids == ids { return cached.atlas }

        var tiles: [UIImage?] = []
        for item in items {
            tiles.append(await islandTile(for: item))
        }
        let atlas = tiles.contains(where: { $0 != nil }) ? Self.strip(from: tiles) : nil
        cachedAtlas = (ids, atlas)
        return atlas
    }

    /// Composites drawer icons into one strip the way `islandAtlas` does for
    /// tray thumbnails. Returns nil when no image is present, so the widget
    /// falls back to per-slot SF Symbols.
    func drawerAtlas(for images: [UIImage?]) async -> TrayContentState.Atlas? {
        guard images.contains(where: { $0 != nil }) else { return nil }
        return Self.strip(from: images)
    }

    /// The tray page's strip with drawer icons appended, for a tray state
    /// that also carries the drawer (`TrayContentState.withDrawer`). The tray
    /// tiles are sliced back out of `tray` rather than regenerated. `nil` when
    /// no drawer slot has an image -- the tray atlas alone is then enough.
    func combinedAtlas(tray: TrayContentState.Atlas?, trayCount: Int, drawer: [UIImage?]) async -> TrayContentState.Atlas? {
        guard drawer.contains(where: { $0 != nil }) else { return nil }
        let trayTiles: [UIImage?] = (0..<trayCount).map { i in
            guard let tray, tray.filled.indices.contains(i), tray.filled[i] else { return nil }
            return AtlasSlicer.tile(tray.jpeg, index: i, count: trayCount)
        }
        return Self.strip(from: trayTiles + drawer)
    }

    private func islandTile(for item: TrayItem) async -> UIImage? {
        let side = CGFloat(Self.atlasTile)
        let request = QLThumbnailGenerator.Request(
            fileAt: item.fileURL,
            size: CGSize(width: side, height: side),
            scale: 1,
            representationTypes: .all
        )
        guard let rep = try? await QLThumbnailGenerator.shared
            .generateBestRepresentation(for: request) else { return nil }
        return rep.uiImage
    }

    /// Composites the tiles left to right, aspect-filled, into one opaque JPEG.
    ///
    /// Every element gets a tile, including the `nil` ones: the widget slices
    /// the strip by index, so a missing tile has to occupy its slot rather
    /// than shift the rest. A flat black tile costs almost nothing once
    /// compressed, and the widget draws the SF Symbol over that slot anyway
    /// (`Preview.hasThumbnail` is false for it).
    private static func strip(from tiles: [UIImage?]) -> TrayContentState.Atlas? {
        guard !tiles.isEmpty else { return nil }
        let side = CGFloat(atlasTile)
        let format = UIGraphicsImageRendererFormat.preferred()
        // Pixels, not points: `size` below is already in pixels, and the
        // renderer would otherwise multiply it by the device scale.
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: side * CGFloat(tiles.count), height: side)
        let strip = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for (index, tile) in tiles.enumerated() {
                guard let tile else { continue }
                let slot = CGRect(x: side * CGFloat(index), y: 0, width: side, height: side)
                context.cgContext.saveGState()
                context.cgContext.clip(to: slot)
                tile.draw(in: aspectFill(tile.size, in: slot))
                context.cgContext.restoreGState()
            }
        }
        guard let jpeg = strip.jpegData(compressionQuality: atlasQuality) else { return nil }
        return TrayContentState.Atlas(jpeg: jpeg, filled: tiles.map { $0 != nil })
    }

    /// The rect to draw `size` into so it covers `slot` without distortion.
    private static func aspectFill(_ size: CGSize, in slot: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return slot }
        let scale = max(slot.width / size.width, slot.height / size.height)
        let scaled = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: slot.midX - scaled.width / 2,
            y: slot.midY - scaled.height / 2,
            width: scaled.width,
            height: scaled.height
        )
    }


    // MARK: - Disk cache
    //
    // The cache lives in the container so the widget process can read it too,
    // which is what makes real thumbnails possible in the Dynamic Island.

    // PNG carries no scale metadata, so the bytes alone don't say what scale
    // they were rendered at. We tag them with the caller's requested scale
    // rather than a hardcoded 1.0 — accurate as long as a given device's
    // display scale doesn't change between the write and this read, which
    // holds in practice (it's a fixed device/simulator characteristic).
    private func loadCached(_ item: TrayItem, scale: CGFloat) -> UIImage? {
        guard let data = try? Data(contentsOf: item.thumbnailURL) else { return nil }
        return UIImage(data: data, scale: scale)
    }

    private func store(_ image: UIImage, for item: TrayItem) {
        guard let data = image.pngData() else { return }
        try? FileManager.default.createDirectory(
            at: TrayContainer.thumbsDirectory, withIntermediateDirectories: true
        )
        try? data.write(to: item.thumbnailURL, options: .atomic)
    }
}
