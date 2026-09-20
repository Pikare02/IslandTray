import QuickLook
import SwiftUI

/// The system's own preview, for a tap on a tray card.
///
/// QuickLook rather than an image view: the tray takes whatever is dropped on
/// it, and this is the one thing that already knows how to show a photo, a
/// video, a PDF, a spreadsheet and a text file. It reads the file straight
/// from the container -- the on-disk name carries the extension, which is how
/// it works out what it is looking at.
struct QuickLookView: UIViewControllerRepresentable {
    let url: URL
    /// The item's display name. QuickLook titles the preview after the URL's
    /// last path component otherwise, and on disk that is a UUID -- TrayItem
    /// never builds a path from the name.
    let name: String
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(url: url, name: name) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        // Its own bar button rather than a SwiftUI wrapper: QLPreviewController
        // brings its own chrome, and nesting it in a NavigationStack stacks two
        // bars on top of each other.
        preview.navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done, primaryAction: UIAction { _ in onDone() }
        )
        return UINavigationController(rootViewController: preview)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        private let item: PreviewItem

        init(url: URL, name: String) {
            item = PreviewItem(url: url, name: name)
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            item
        }
    }

    /// `QLPreviewItem` is an ObjC protocol with a URL and a title; NSURL
    /// conforms to it already but answers the title from its own last path
    /// component, which is the UUID.
    final class PreviewItem: NSObject, QLPreviewItem {
        let previewItemURL: URL?
        let previewItemTitle: String?

        init(url: URL, name: String) {
            previewItemURL = url
            previewItemTitle = name
        }
    }
}
