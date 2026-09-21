import CryptoKit
import Foundation
import UniformTypeIdentifiers

/// Turns dropped NSItemProviders into tray items.
///
/// The URL handed to loadFileRepresentation is only valid for the duration of
/// the completion handler, so the bytes are copied before returning.
enum DropReceiver {
    struct Result {
        var added: Int
        var failed: [String]
        /// Items held back because the tray already has the same bytes. They
        /// are staged on disk and go nowhere until someone decides.
        var duplicates: [Staged] = []
    }

    /// A dropped file that has been copied out of the provider but not yet
    /// added to the tray.
    ///
    /// The payload stays in the staging directory while the question is on
    /// screen, so answering "add it" does not need the drag back.
    struct Staged: Identifiable, Hashable {
        let id = UUID()
        let payload: URL
        let suggestedName: String?
        let uti: String
        /// The item already in the tray with these bytes.
        let existing: TrayItem
    }

    // MainActor rather than a Sendable dance for NSItemProvider: the array
    // arrives from a SwiftUI .onDrop callback (already MainActor) and this
    // whole call chain stays on it, so `provider` never has to be proven
    // Sendable to cross an isolation domain. The actual waiting still happens
    // off the actor -- loadFileRepresentation's completion runs on a system
    // queue and only resumes the continuation, which hops execution back.
    /// - Parameter allowingDuplicates: when true, bytes already in the tray
    ///   are added again rather than reported. The share extension passes
    ///   true: it has no way to ask, and silently dropping a share the user
    ///   asked for would be worse than a second copy.
    @MainActor
    static func ingest(providers: [NSItemProvider], allowingDuplicates: Bool = false) async -> Result {
        var added = 0
        var failed: [String] = []
        var duplicates: [Staged] = []
        // Loaded once, then kept current as this drop adds to it, so two
        // identical files dropped together are caught against each other too.
        var existing = (try? TrayStore.shared.load()) ?? []

        for provider in providers {
            let typeIdentifier = preferredTypeIdentifier(for: provider)
            do {
                let loaded = try await load(from: provider, typeIdentifier: typeIdentifier)
                let payload = loaded.payload
                let suggestedName = provider.suggestedName

                if !allowingDuplicates,
                   let match = duplicate(of: payload, among: existing) {
                    // Not deleted: the payload is what gets added if the user
                    // says to add it anyway.
                    duplicates.append(Staged(
                        payload: payload,
                        suggestedName: suggestedName,
                        uti: typeIdentifier,
                        existing: match
                    ))
                    continue
                }

                existing.append(try await add(
                    payload: payload,
                    suggestedName: suggestedName,
                    uti: typeIdentifier,
                    origin: loaded.origin
                ))
                added += 1
            } catch {
                failed.append(provider.suggestedName ?? "unnamed item")
            }
        }
        return Result(added: added, failed: failed, duplicates: duplicates)
    }

    /// Adds a staged payload to the tray and deletes the staging file.
    ///
    /// `Task.detached` because `TrayStore.add(copyingFrom:)` is synchronous
    /// disk I/O: a second full copy of the payload into the container, then a
    /// coordinated read-modify-write of items.json. Its callers resume on the
    /// MainActor, so without this hop that copy would run on the main thread
    /// once per dropped item -- twenty photos would freeze the UI twenty
    /// times over, and one large file for the whole copy. Only Sendable
    /// values cross into the task; the `NSItemProvider` never leaves the
    /// MainActor. The `defer` cleans up the staging file on the throwing path
    /// too, which is how it used to leak into NSTemporaryDirectory().
    static func add(
        payload: URL, suggestedName: String?, uti: String, origin: TrayItemOrigin? = nil
    ) async throws -> TrayItem {
        try await Task.detached(priority: .userInitiated) {
            defer { try? FileManager.default.removeItem(at: payload) }
            return try TrayStore.shared.add(
                copyingFrom: payload, suggestedName: suggestedName, uti: uti, origin: origin
            )
        }.value
    }

    /// Adds a duplicate the user asked for anyway.
    static func add(staged: Staged) async throws -> TrayItem {
        try await add(payload: staged.payload, suggestedName: staged.suggestedName, uti: staged.uti)
    }

    /// Throws the staging file away, for a duplicate the user declined.
    static func discard(staged: Staged) {
        try? FileManager.default.removeItem(at: staged.payload)
    }

    /// The tray item holding exactly these bytes, or nil.
    ///
    /// Size first, hash only on a size match: dropping onto a tray of large
    /// videos would otherwise read every one of them on every drop, and two
    /// files of different lengths can never be the same bytes.
    ///
    /// Internal so a test can pin it against real files without driving a
    /// drop through `NSItemProvider` and the real container.
    /// - Parameter itemURL: where an item's bytes are. Defaulted to the real
    ///   container, and a parameter only so a test can point this at files it
    ///   made itself.
    static func duplicate(
        of payload: URL,
        among items: [TrayItem],
        at itemURL: (TrayItem) -> URL = { $0.fileURL }
    ) -> TrayItem? {
        guard let size = try? payload.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              let payloadDigest = digest(of: payload) else { return nil }
        for item in items where item.size == size {
            if digest(of: itemURL(item)) == payloadDigest { return item }
        }
        return nil
    }

    /// SHA-256 of a file, read in chunks.
    ///
    /// Not `Data(contentsOf:)`: the tray takes videos, and hashing one by
    /// loading it whole is how a drop turns into a memory kill.
    private static func digest(of url: URL) -> SHA256Digest? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize()
    }

    /// What the share sheet tells the user an ingest did.
    ///
    /// Lives here rather than in `ShareViewController` because this file is
    /// the one both the share extension (project.yml adds it to that target)
    /// and the test bundle can see: the extension's own sources are not
    /// reachable from a test bundle, and an unpinned summary is how "3 of 5
    /// failed" got reported as a success.
    ///
    /// A partial outcome names both sides, the same rule `TrayRemovalResult`,
    /// `incompleteRemoval` and `ingestBanner` follow. Counts, not names: the
    /// sheet is a few lines tall and a long share can fail a dozen items.
    static func shareSheetMessage(for result: Result, board: TrayBoard = .tray) -> String {
        guard result.added > 0 else { return L.s("share.result.none") }
        let prefix = board == .clipboard ? "clipboard.result" : "share.result"
        guard !result.failed.isEmpty else { return L.s("\(prefix).added", result.added) }
        return L.s("\(prefix).partial", result.added, result.failed.count)
    }

    /// Prefer the most specific concrete type the provider offers, ignoring
    /// container-ish identifiers that would give us a useless extension.
    ///
    /// Internal rather than private so DropReceiverTests can pin this
    /// selection logic directly, without driving it through actual
    /// NSItemProvider file loading.
    static func preferredTypeIdentifier(for provider: NSItemProvider) -> String {
        let ignored: Set<String> = ["public.item", "public.content", "public.data"]
        let candidates = provider.registeredTypeIdentifiers
        return candidates.first { !ignored.contains($0) }
            ?? candidates.first
            ?? UTType.data.identifier
    }

    /// A staged copy of the dropped file, plus a way back to the original
    /// when there is one.
    struct Loaded {
        let payload: URL
        let origin: TrayItemOrigin?
    }

    /// Stages the dropped bytes, and keeps a handle on the source when the
    /// provider offers one.
    ///
    /// Asks for the in-place representation first. That is the only form that
    /// names the *original* file rather than a copy of it, and a bookmark
    /// taken while its access is open is what lets a later export delete the
    /// file where it actually lives. A provider that has no in-place form
    /// hands back a copy with `isInPlace == false`, which is exactly what the
    /// old path produced; a provider that refuses the call outright falls
    /// through to that old path unchanged, so nothing that worked before can
    /// stop working because of this.
    @MainActor
    private static func load(from provider: NSItemProvider, typeIdentifier: String) async throws -> Loaded {
        var loaded: Loaded
        if let inPlace = try? await loadInPlace(from: provider, typeIdentifier: typeIdentifier) {
            loaded = inPlace
        } else {
            loaded = Loaded(
                payload: try await loadFile(from: provider, typeIdentifier: typeIdentifier),
                origin: nil
            )
        }
        // The in-place file itself, then a file URL the provider hands over.
        // Nothing else: a photo arrives re-encoded with nothing in it that
        // says which asset it was, so photos are copies (see TrayItemOrigin).
        if loaded.origin == nil {
            loaded = Loaded(payload: loaded.payload, origin: await fileURLOrigin(of: provider))
        }
        DropDiagnostics.record(DropDiagnostics.line(
            name: provider.suggestedName, types: provider.registeredTypeIdentifiers, origin: loaded.origin
        ))
        return loaded
    }

    /// The original behind a `public.file-url` representation.
    ///
    /// Plenty of providers -- the Files app among them -- hand over the real
    /// URL of the file under this type without offering an in-place file
    /// representation at all. Loading it costs nothing (it is a URL, not the
    /// bytes), and it is the same kind of security-scoped handle, so the
    /// bookmark is taken exactly the same way.
    @MainActor
    private static func fileURLOrigin(of provider: NSItemProvider) async -> TrayItemOrigin? {
        let fileURLType = "public.file-url"
        guard provider.registeredTypeIdentifiers.contains(fileURLType) else { return nil }
        let bookmark: Data? = await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: fileURLType) { item, _ in
                guard let url = item as? URL ?? (item as? Data).flatMap({
                    URL(dataRepresentation: $0, relativeTo: nil)
                }) else {
                    continuation.resume(returning: nil)
                    return
                }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                continuation.resume(returning: try? url.bookmarkData())
            }
        }
        return bookmark.map(TrayItemOrigin.file)
    }

    @MainActor
    private static func loadInPlace(
        from provider: NSItemProvider, typeIdentifier: String
    ) async throws -> Loaded {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier) { url, isInPlace, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: CocoaError(.fileNoSuchFile))
                    return
                }
                // The bookmark has to be taken here, inside the access the
                // system opened for this call: it ends when this returns, and
                // the deletion it is for happens much later.
                let accessed = isInPlace && url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let bookmark = isInPlace ? try? url.bookmarkData() : nil
                do {
                    continuation.resume(returning: Loaded(
                        payload: try stage(url), origin: bookmark.map(TrayItemOrigin.file)
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Copies a file that is about to become invalid into a staging location.
    ///
    /// Both load paths need this and both need it synchronously: the URL they
    /// are handed stops being readable the moment their completion handler
    /// returns.
    private static func stage(_ url: URL) throws -> URL {
        let staging = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension)
        try FileManager.default.copyItem(at: url, to: staging)
        return staging
    }

    /// Copies the provider's file representation into a temporary location that
    /// stays valid after the completion handler returns.
    @MainActor
    private static func loadFile(
        from provider: NSItemProvider, typeIdentifier: String
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: CocoaError(.fileNoSuchFile))
                    return
                }
                do {
                    continuation.resume(returning: try stage(url))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
