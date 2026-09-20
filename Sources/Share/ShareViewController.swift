import SwiftUI
import UIKit

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        // Without the App Group entitlement this process writes to its own
        // sandbox, which the app can never read. Say so instead of silently
        // losing the item.
        guard TrayContainer.isShared else {
            present(message: L.s("share.freeOnly"))
            return
        }
        Task { await ingest() }
    }

    /// Shares the app's own drop path instead of a second copy of it.
    ///
    /// `DropReceiver` already picks the most specific type identifier the
    /// provider offers (a generic `public.data` standing first would store the
    /// payload with no extension and no thumbnail), stages the file before the
    /// completion handler invalidates it, keeps the copy and the coordinated
    /// write off the main actor, and counts what failed. Reimplementing any of
    /// that here is how this extension lost both the type selection and the
    /// failure count; project.yml compiles that file into this target.
    private func ingest() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        // Duplicates are added rather than reported here: a share sheet has
        // nowhere to ask, and dropping a share the user asked for would be
        // worse than a second copy. The app asks; this cannot.
        let result = await DropReceiver.ingest(providers: providers, allowingDuplicates: true)
        present(message: DropReceiver.shareSheetMessage(for: result))
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
            Button(L.s("common.close"), action: onDone)
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}
