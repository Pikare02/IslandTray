import Foundation
import OSLog

/// Deletes the file a tray item was taken from, so taking an item out of the
/// tray is a move rather than a copy.
///
/// Only files. A photo dragged out of Photos is always a copy -- see
/// `TrayItemOrigin` for why that is not a decision this app gets to make.
enum OriginalRemover {
    private static let logger = Logger(
        subsystem: "com.pikare.islandtray", category: "OriginalRemover"
    )

    /// What happened to the original.
    ///
    /// A failure carries the reason as text rather than a flag. Which step
    /// refused -- resolving the bookmark, opening its scope, the coordinated
    /// delete -- decides what to do about it, and none of those steps can be
    /// reached from a simulator or a test: the answer only exists on the
    /// device. It goes in the banner and in the settings screen's record.
    ///
    /// A failure is never a reason to keep the tray copy: the file the user
    /// asked for has already reached its destination.
    enum Outcome: Equatable {
        case removed
        case failed(String)
    }

    static func remove(_ origin: TrayItemOrigin) -> Outcome {
        let outcome = attempt(origin)
        if case .failed(let reason) = outcome {
            logger.error("The original was not deleted.")
            DropDiagnostics.record(L.s("diag.export.failed", reason))
        }
        return outcome
    }

    private static func attempt(_ origin: TrayItemOrigin) -> Outcome {
        switch origin {
        case .file(let bookmark):
            return removeFile(bookmark: bookmark)
        case .photo, .photoMetadata:
            // Only reachable for items added by a build that still recorded
            // these. Nothing is deleted for them, the same as for an item with
            // no origin at all.
            return .failed(L.s("reason.photoCopy"))
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
            return .failed(L.s("reason.bookmarkUnresolved"))
        }
        // A stale bookmark still resolves, but to where the file *was*. Acting
        // on it could delete something that moved into that path since.
        guard !isStale else {
            return .failed(L.s("reason.bookmarkStale"))
        }
        // Never the tray's own storage. A file URL handed over by a drag
        // normally points somewhere else entirely, but the tray is reachable
        // through the Files app now, and deleting out of it here would race
        // TrayStore's own bookkeeping for the same bytes.
        guard !url.resolvingSymlinksInPath().path
            .hasPrefix(TrayContainer.root.resolvingSymlinksInPath().path) else {
            return .failed(L.s("reason.insideTray"))
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
            return .failed(L.s(
                "reason.coordination", coordinationError.domain, coordinationError.code,
                accessed ? "" : L.s("reason.noScope")
            ))
        }
        if let removalError {
            return .failed(L.s(
                "reason.removal", removalError.domain, removalError.code,
                accessed ? "" : L.s("reason.noScope")
            ))
        }
        return .removed
    }
}
