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
                _ = try TrayStore.shared.add(
                    copyingFrom: payload,
                    suggestedName: provider.suggestedName,
                    uti: typeIdentifier
                )
                try? FileManager.default.removeItem(at: payload)
                added += 1
            } catch {
                failed.append(provider.suggestedName ?? "unnamed item")
            }
        }
        return Result(added: added, failed: failed)
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
