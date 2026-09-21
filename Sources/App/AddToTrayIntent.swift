import AppIntents

/// Puts files into the tray from anywhere the Shortcuts app reaches --
/// including the share sheet.
///
/// This is the free-account way back into the share sheet. The share
/// extension needs an App Group to hand what it receives to the app, and that
/// entitlement does not survive sideloading; an App Intent has no such
/// problem, because the system runs it inside the app's own process, writing
/// to the app's own container. A one-action shortcut built on this, with
/// "Show in Share Sheet" turned on, appears in the share sheet of every app
/// that can share a file.
struct AddToTrayIntent: AppIntent {
    // `let`, not `var`, for the same reason as RefreshTrayActivityIntent: the
    // protocol's requirements are get-only and a mutable static is shared
    // state Swift 6 cannot prove safe.
    static let title: LocalizedStringResource = "トレイに追加"
    static let description = IntentDescription(
        "共有されたファイルをトレイに入れます。共有シートに出すショートカットに使えます。"
    )
    /// The app is not brought forward: the point is to stay where you are.
    static let openAppWhenRun: Bool = false

    // `supportedTypeIdentifiers`, not `supportedContentTypes`: the UTType
    // form of this initializer is iOS 18, and this app runs on 17.
    @Parameter(title: "ファイル", supportedTypeIdentifiers: ["public.item"])
    var files: [IntentFile]

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var added = 0
        var failed: [String] = []
        for file in files {
            do {
                try TrayStore.shared.add(file, board: .tray)
                added += 1
            } catch {
                failed.append(file.filename)
            }
        }
        // The island is what the user sees from wherever they ran this, so it
        // has to be told.
        await TrayStore.didChangeFromIntent()

        let result = DropReceiver.Result(added: added, failed: failed)
        return .result(dialog: IntentDialog(stringLiteral: DropReceiver.shareSheetMessage(for: result)))
    }
}

extension TrayStore {
    /// Posted after a shortcut wrote to the store. The intent runs in this
    /// process, so an open screen hears it and shows the item now instead of
    /// the next time the app comes to the front.
    static let didChangeFromIntentNotification = Notification.Name("TrayStore.didChangeFromIntent")

    /// The island and any open screen, after a shortcut wrote to the store.
    /// `restart()` rather than `sync()`: this process may have just been
    /// launched for the intent and have no activity of its own yet. Main
    /// actor so the notification arrives where SwiftUI can take it.
    @MainActor
    static func didChangeFromIntent() async {
        await TrayActivityController.shared.restart()
        NotificationCenter.default.post(name: didChangeFromIntentNotification, object: nil)
    }

    /// Stores a file handed over by Shortcuts.
    ///
    /// The URL when there is one: it is already a file on disk, and `data`
    /// would read a video into memory to write it straight back out. That URL
    /// is security-scoped -- a copied photo or a file from Files lives outside
    /// this sandbox -- so it is only readable inside an access; without one the
    /// copy fails and the item is reported as not added. `data` is the fallback
    /// for any URL that still cannot be copied, since IntentFile handles the
    /// access itself when it reads.
    func add(_ file: IntentFile, board: TrayBoard) throws {
        if let url = file.fileURL {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if (try? add(
                copyingFrom: url, suggestedName: file.filename, uti: file.type?.identifier,
                board: board
            )) != nil { return }
        }
        _ = try add(data: file.data, suggestedName: file.filename, uti: file.type?.identifier, board: board)
    }
}
