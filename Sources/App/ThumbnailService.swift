import QuickLookThumbnailing
import UIKit

/// Generates and caches thumbnails using the same API the Files app uses,
/// so tray items look exactly like they do in Files.
actor ThumbnailService {
    static let shared = ThumbnailService()

    private static let pointSize = CGSize(width: 120, height: 120)
    private var inFlight: [UUID: Task<UIImage?, Never>] = [:]

    /// - Parameter scale: the display scale to render at. `UITraitCollection.current`
    ///   can't be trusted here — it's thread-local, and this actor never runs on the
    ///   main thread, so it would always read as unset. Callers should pass the real
    ///   scale of the context the thumbnail will be shown in, e.g. a SwiftUI view's
    ///   `@Environment(\.displayScale)`. The default only covers callers with no
    ///   display context (previews, tests); it matches the historical fallback here.
    func thumbnail(for item: TrayItem, scale: CGFloat = 2) async -> UIImage? {
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
