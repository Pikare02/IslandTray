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
    }

    // MainActor rather than a Sendable dance for NSItemProvider: the array
    // arrives from a SwiftUI .onDrop callback (already MainActor) and this
    // whole call chain stays on it, so `provider` never has to be proven
    // Sendable to cross an isolation domain. The actual waiting still happens
    // off the actor -- loadFileRepresentation's completion runs on a system
    // queue and only resumes the continuation, which hops execution back.
    @MainActor
    static func ingest(providers: [NSItemProvider]) async -> Result {
        var added = 0
        var failed: [String] = []

        for provider in providers {
            let typeIdentifier = preferredTypeIdentifier(for: provider)
            do {
                let payload = try await loadFile(from: provider, typeIdentifier: typeIdentifier)
                let suggestedName = provider.suggestedName

                // TrayStore.add(copyingFrom:) is a synchronous, non-async call
                // that does real disk I/O: a second full copy of the payload
                // into the App Group container, then a coordinated
                // read-modify-write of items.json. `loadFile` resumes back
                // onto the MainActor (see its own comment), so without this,
                // that copy+write would run inline on the main thread -- once
                // per dropped item, so 20 photos would freeze the UI 20 times
                // in a row, and one large file would freeze it for the whole
                // copy. Task.detached hops it onto the cooperative thread
                // pool; only Sendable values (URL, String?) cross into it, so
                // `provider` itself (not Sendable) never has to leave the
                // MainActor. The `defer` cleans up the staging file on both
                // the success and the throwing path -- previously it only ran
                // after `add` succeeded, leaking the staging file into
                // NSTemporaryDirectory() whenever `add` threw.
                _ = try await Task.detached(priority: .userInitiated) {
                    defer { try? FileManager.default.removeItem(at: payload) }
                    return try TrayStore.shared.add(
                        copyingFrom: payload,
                        suggestedName: suggestedName,
                        uti: typeIdentifier
                    )
                }.value
                added += 1
            } catch {
                failed.append(provider.suggestedName ?? "unnamed item")
            }
        }
        return Result(added: added, failed: failed)
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
    static func shareSheetMessage(for result: Result) -> String {
        guard result.added > 0 else { return "追加できませんでした" }
        let landed = "\(result.added) 件をトレイに追加しました"
        guard !result.failed.isEmpty else { return landed }
        return landed + "（\(result.failed.count) 件は追加できませんでした）"
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
                // Must copy synchronously: url is deleted once this returns.
                let staging = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)
                do {
                    try FileManager.default.copyItem(at: url, to: staging)
                    continuation.resume(returning: staging)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
