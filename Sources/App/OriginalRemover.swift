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

    /// - Parameter name: the item's display name, which for a photo is the
    ///   filename the drag suggested. Passed in rather than stored in the
    ///   origin: adding a field to a persisted enum case makes every item
    ///   written before it fail to decode, and an item that fails to decode
    ///   is what TrayStore answers with a destructive rebuild.
    static func remove(_ origin: TrayItemOrigin, named name: String) async -> Outcome {
        let outcome = await attempt(origin, named: name)
        if case .failed(let reason) = outcome {
            logger.error("The original was not deleted.")
            DropDiagnostics.record("削除できず: \(reason)")
        }
        return outcome
    }

    private static func attempt(_ origin: TrayItemOrigin, named name: String) async -> Outcome {
        switch origin {
        case .file(let bookmark):
            return removeFile(bookmark: bookmark)
        case .photo(let localIdentifier):
            let fetched = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            return await removePhoto(matching: (0..<fetched.count).map(fetched.object(at:)))
        case .photoMetadata(let creationDate, let pixelWidth, let pixelHeight):
            guard await authorized else { return .failed("photo: 権限なし") }
            switch asset(takenAt: creationDate, width: pixelWidth, height: pixelHeight, named: name) {
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

    /// The one asset the dropped photo came from.
    ///
    /// Dimensions first, because they are exact and indexable, then the
    /// capture time, then the filename. The date alone was not enough on the
    /// device: a photo whose pixels matched to the pixel matched no asset at
    /// all by date, which is what a re-encoded copy carrying a rewritten (or
    /// differently zoned) EXIF timestamp looks like. So the date is now a
    /// filter over the size-matched set rather than a database predicate, and
    /// the filename the drag suggested is the fallback when it finds nothing.
    ///
    /// Anything other than exactly one candidate deletes nothing, and says
    /// how many it found at each step -- the numbers are what makes the next
    /// attempt something other than a guess.
    private enum AssetMatch {
        case one([PHAsset])
        case noneOrSeveral(String)
    }

    private static func asset(
        takenAt date: Date, width: Int, height: Int, named name: String
    ) -> AssetMatch {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "pixelWidth == %d AND pixelHeight == %d", width, height)
        let bySize = PHAsset.fetchAssets(with: .image, options: options)
        guard bySize.count > 0 else {
            return .noneOrSeveral("photo: サイズ一致0 \(width)x\(height)")
        }

        var byDate: [PHAsset] = []
        var nearest: TimeInterval?
        bySize.enumerateObjects { asset, _, _ in
            guard let created = asset.creationDate else { return }
            let delta = created.timeIntervalSince(date)
            if nearest == nil || abs(delta) < abs(nearest!) { nearest = delta }
            if abs(delta) <= 2 { byDate.append(asset) }
        }
        if byDate.count == 1 { return .one(byDate) }

        // Only when the date found nothing usable, and only over a set small
        // enough to walk: `assetResources` is a per-asset round trip, not a
        // column of the index. The cap is high because the set is not small
        // -- 4032x3024 is what every 12MP iPhone photo measures, so "same
        // dimensions" can be most of a library -- and this runs once, on an
        // export the user asked for.
        //
        // Compared without the extension, and case-insensitively. Photos
        // converts on the way out: the device reported a drag arriving as
        // "IMG_9787.jpeg" against a library holding "IMG_9787.HEIC", so
        // comparing whole filenames matched nothing while the stem matched
        // exactly. The stem is the part Photos actually assigns.
        var byName: [PHAsset] = []
        let nameScanLimit = 2000
        let stem = (name as NSString).deletingPathExtension.lowercased()
        if bySize.count <= nameScanLimit, !stem.isEmpty {
            bySize.enumerateObjects { asset, _, _ in
                let matches = PHAssetResource.assetResources(for: asset).contains {
                    ($0.originalFilename as NSString).deletingPathExtension.lowercased() == stem
                }
                if matches { byName.append(asset) }
            }
            if byName.count == 1 { return .one(byName) }
        }

        let delta = nearest.map { "\(Int($0))秒" } ?? "なし"
        let scanned = bySize.count <= nameScanLimit ? "\(byName.count)件" : "未走査"
        return .noneOrSeveral(
            "photo: サイズ\(bySize.count)件 日時\(byDate.count)件 名前\(scanned) 最近差\(delta) 名\(name)"
        )
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
    private static func removePhoto(matching assets: [PHAsset]) async -> Outcome {
        guard !assets.isEmpty else { return .failed("photo: 該当なし") }
        guard await authorized else { return .failed("photo: 権限なし") }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }
            return .removed
        } catch {
            // Cancelling the confirmation lands here too, which is correct:
            // the photo is still there.
            return .failed("photo: \((error as NSError).code)")
        }
    }
}
