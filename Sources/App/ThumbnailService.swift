import QuickLookThumbnailing
import UIKit

/// Generates and caches thumbnails using the same API the Files app uses,
/// so tray items look exactly like they do in Files.
actor ThumbnailService {
    static let shared = ThumbnailService()

    private static let pointSize = CGSize(width: 120, height: 120)
    private var inFlight: [UUID: Task<UIImage?, Never>] = [:]

    func thumbnail(for item: TrayItem) async -> UIImage? {
        if let cached = loadCached(item) { return cached }
        if let running = inFlight[item.id] { return await running.value }

        let task = Task<UIImage?, Never> {
            // UITraitCollection.current is documented as safe to read off the
            // main thread (it's how UIGraphicsImageRenderer-style code picks up
            // display scale in background rendering contexts), unlike the
            // deprecated UIScreen.main, which would require a MainActor hop.
            let scale = UITraitCollection.current.displayScale
            let request = QLThumbnailGenerator.Request(
                fileAt: item.fileURL,
                size: Self.pointSize,
                scale: scale > 0 ? scale : 2,
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

    private func loadCached(_ item: TrayItem) -> UIImage? {
        guard let data = try? Data(contentsOf: item.thumbnailURL) else { return nil }
        return UIImage(data: data)
    }

    private func store(_ image: UIImage, for item: TrayItem) {
        guard let data = image.pngData() else { return }
        try? FileManager.default.createDirectory(
            at: TrayContainer.thumbsDirectory, withIntermediateDirectories: true
        )
        try? data.write(to: item.thumbnailURL, options: .atomic)
    }
}
