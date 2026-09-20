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

    /// What happened to the original.
    ///
    /// A failure carries the reason as text rather than a flag. Which step
    /// refused -- resolving the bookmark, opening its scope, the coordinated
    /// delete, the photo match, the library -- decides what to do about it,
    /// and none of those steps can be reached from a simulator or a test: the
    /// answer only exists on the device. It goes in the banner and in the
    /// settings screen's record.
    ///
    /// A failure is never a reason to keep the tray copy: the file the user
    /// asked for has already reached its destination.
    enum Outcome: Equatable {
        case removed
        case failed(String)
    }

    static func remove(_ origin: TrayItemOrigin) async -> Outcome {
        let outcome = await attempt(origin)
        if case .failed(let reason) = outcome {
            logger.error("The original was not deleted.")
            DropDiagnostics.record("削除できず: \(reason)")
        }
        return outcome
    }

    private static func attempt(_ origin: TrayItemOrigin) async -> Outcome {
        switch origin {
        case .file(let bookmark):
            return removeFile(bookmark: bookmark)
        case .photo(let localIdentifier):
            return await removePhoto(matching: PHAsset.fetchAssets(
                withLocalIdentifiers: [localIdentifier], options: nil
            ))
        case .photoMetadata(let creationDate, let pixelWidth, let pixelHeight):
            guard await authorized else { return .failed("photo: 権限なし") }
            switch asset(takenAt: creationDate, width: pixelWidth, height: pixelHeight) {
            case .one(let assets):
                return await removePhoto(matching: assets)
            case .noneOrSeveral(let reason):
                return .failed(reason)
            }
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
    private static func removeFile(bookmark: Data) -> Outcome {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return .failed("file: ブックマーク解決不可")
        }
        // A stale bookmark still resolves, but to where the file *was*. Acting
        // on it could delete something that moved into that path since.
        guard !isStale else {
            return .failed("file: ブックマークが古い")
        }
        // Never the tray's own storage. A file URL handed over by a drag
        // normally points somewhere else entirely, but the tray is reachable
        // through the Files app now, and deleting out of it here would race
        // TrayStore's own bookkeeping for the same bytes.
        guard !url.resolvingSymlinksInPath().path
            .hasPrefix(TrayContainer.root.resolvingSymlinksInPath().path) else {
            return .failed("file: トレイ自身の中")
        }
        // Not a guard: `startAccessingSecurityScopedResource` answers false
        // for a URL that needs no scope at all, and refusing there would skip
        // deletions that would have worked. A scope that was genuinely needed
        // and denied shows up as the removal below failing, which is reported
        // either way.
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        var removalError: NSError?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(
            writingItemAt: url, options: .forDeleting, error: &coordinationError
        ) { url in
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                removalError = error as NSError
            }
        }
        // The codes are the point: 257/513 is a sandbox refusal, 4 is a file
        // that is no longer there, and a coordination error means the
        // provider never let us near it. Guessing between those is what this
        // avoids.
        if let coordinationError {
            return .failed("file: 調整不可 \(coordinationError.domain) \(coordinationError.code)\(accessed ? "" : " (scope無)")")
        }
        if let removalError {
            return .failed("file: 削除拒否 \(removalError.domain) \(removalError.code)\(accessed ? "" : " (scope無)")")
        }
        return .removed
    }

    /// The single asset whose capture time and dimensions match, or an empty
    /// result.
    ///
    /// Seconds resolution on the date, because that is all EXIF records, and
    /// the dimensions alongside it. More than one match means two photos were
    /// taken in the same second at the same size -- burst frames -- and there
    /// is no way to tell which one the user dragged, so nothing is deleted.
    private enum AssetMatch {
        case one(PHFetchResult<PHAsset>)
        case noneOrSeveral(String)
    }

    private static func asset(takenAt date: Date, width: Int, height: Int) -> AssetMatch {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@ AND pixelWidth == %d AND pixelHeight == %d",
            date.addingTimeInterval(-1) as NSDate,
            date.addingTimeInterval(1) as NSDate,
            width, height
        )
        let matches = PHAsset.fetchAssets(with: .image, options: options)
        guard matches.count == 1 else {
            // The numbers are what makes this actionable: 0 means the search
            // was wrong (a converted copy, a shifted timestamp), more than 1
            // means the library really does hold several.
            return .noneOrSeveral("photo: 該当 \(matches.count) 件 \(width)x\(height)")
        }
        return .one(matches)
    }

    private static var authorized: Bool {
        get async { await PHPhotoLibrary.requestAuthorization(for: .readWrite) == .authorized }
    }

    /// Deletes the asset through PhotoKit.
    ///
    /// iOS puts its own confirmation in front of this, with a thumbnail of
    /// what is about to go, and a deleted photo lands in Recently Deleted for
    /// thirty days. That is what makes deleting on a metadata match safe
    /// enough to do at all: the user sees the photo and says yes, and a
    /// mistake is recoverable.
    private static func removePhoto(matching assets: PHFetchResult<PHAsset>) async -> Outcome {
        guard assets.count > 0 else { return .failed("photo: 該当なし") }
        guard await authorized else { return .failed("photo: 権限なし") }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            return .removed
        } catch {
            // Cancelling the confirmation lands here too, which is correct:
            // the photo is still there.
            return .failed("photo: \((error as NSError).code)")
        }
    }
}
