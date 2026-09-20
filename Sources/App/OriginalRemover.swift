import Foundation
import OSLog
import Photos

/// Deletes the file a tray item was taken from, so taking an item out of the
/// tray is a move rather than a copy.
///
/// Only runs for items that carry a `TrayItemOrigin`, which is the minority:
/// most sources hand over bytes with nothing behind them to delete, and those
/// items are simply copies. Never runs in copy mode.
enum OriginalRemover {
    private static let logger = Logger(
        subsystem: "com.pikare.islandtray", category: "OriginalRemover"
    )

    /// Whether the original is gone.
    ///
    /// `false` means it is still where it was -- the bookmark went stale, the
    /// provider refused, the photo was already deleted, or the user declined
    /// the system's confirmation. Never a reason to keep the tray copy: the
    /// file the user asked for has already reached its destination.
    static func remove(_ origin: TrayItemOrigin) async -> Bool {
        switch origin {
        case .file(let bookmark):
            return removeFile(bookmark: bookmark)
        case .photo(let localIdentifier):
            return await removePhoto(localIdentifier: localIdentifier)
        }
    }

    /// Resolves the bookmark taken during the drag and deletes what it points
    /// at, under file coordination.
    ///
    /// The resolved URL is security-scoped: without `startAccessing...` every
    /// operation on it fails with a permission error. Coordinated, because
    /// the file lives in someone else's document provider (the Files app,
    /// iCloud Drive, a third party) and deleting it from under an open
    /// coordinated read is what corrupts the provider's own bookkeeping.
    private static func removeFile(bookmark: Data) -> Bool {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            logger.error("The original's bookmark no longer resolves.")
            return false
        }
        // A stale bookmark still resolves, but to where the file *was*. Acting
        // on it could delete something that moved into that path since.
        guard !isStale else {
            logger.error("The original's bookmark is stale; leaving the file alone.")
            return false
        }
        // Not a guard: `startAccessingSecurityScopedResource` answers false
        // for a URL that needs no scope at all, and refusing there would skip
        // deletions that would have worked. A scope that was genuinely needed
        // and denied shows up as the removal below failing, which is reported
        // either way.
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        var removed = false
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(
            writingItemAt: url, options: .forDeleting, error: &coordinationError
        ) { url in
            removed = (try? FileManager.default.removeItem(at: url)) != nil
        }
        if !removed { logger.error("The original could not be deleted.") }
        return removed
    }

    /// Deletes the asset through PhotoKit.
    ///
    /// iOS puts its own confirmation in front of this, with a thumbnail of
    /// what is about to go, and a deleted photo lands in Recently Deleted for
    /// thirty days. That is what makes deleting from an identifier the drag
    /// handed us safe enough to do at all: the user sees the photo and says
    /// yes, and a mistake is recoverable.
    private static func removePhoto(localIdentifier: String) async -> Bool {
        guard await PHPhotoLibrary.requestAuthorization(for: .readWrite) == .authorized else {
            logger.error("The photo library is not available to this app.")
            return false
        }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard assets.count > 0 else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            return true
        } catch {
            // Cancelling the confirmation lands here too, which is correct:
            // the photo is still there.
            logger.error("The photo was not deleted.")
            return false
        }
    }
}
