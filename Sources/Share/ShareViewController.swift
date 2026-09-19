import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        // Without the App Group entitlement this process writes to its own
        // sandbox, which the app can never read. Say so instead of silently
        // losing the item.
        guard TrayContainer.isShared else {
            present(message: "共有シートからの追加は、有料の Apple Developer アカウントでビルドした場合のみ利用できます。")
            return
        }
        Task { await ingest() }
    }

    private func ingest() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }

        var added = 0
        for provider in providers {
            let typeIdentifier = provider.registeredTypeIdentifiers.first
                ?? UTType.data.identifier
            guard let staged = await loadFile(from: provider, typeIdentifier: typeIdentifier)
            else { continue }
            let suggestedName = provider.suggestedName

            // Copying the payload into the container and the coordinated
            // metadata write are both disk work, and this method runs on the
            // main actor: detached, or the sheet freezes for as long as the
            // copy takes -- the same reason DropReceiver keeps `add` off it.
            // Only Sendable values cross in; `provider` itself stays here.
            // The `defer` drops the staging copy on the throwing path too.
            added += await Task.detached(priority: .userInitiated) {
                defer { try? FileManager.default.removeItem(at: staged) }
                let stored = try? TrayStore.shared.add(
                    copyingFrom: staged,
                    suggestedName: suggestedName,
                    uti: typeIdentifier
                )
                return stored == nil ? 0 : 1
            }.value
        }

        present(message: added > 0 ? "\(added) 件をトレイに追加しました" : "追加できませんでした")
    }

    private func loadFile(from provider: NSItemProvider, typeIdentifier: String) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                // Must copy synchronously: url is deleted once this returns.
                let staging = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)
                try? FileManager.default.copyItem(at: url, to: staging)
                continuation.resume(
                    returning: FileManager.default.fileExists(atPath: staging.path) ? staging : nil
                )
            }
        }
    }

    private func present(message: String) {
        let host = UIHostingController(rootView: ShareResultView(message: message) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

private struct ShareResultView: View {
    let message: String
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 40))
            Text(message)
                .multilineTextAlignment(.center)
                .font(.callout)
            Button("閉じる", action: onDone)
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}
