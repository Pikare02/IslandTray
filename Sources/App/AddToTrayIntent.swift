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
                // The URL when there is one: it is already a file on disk, and
                // `data` would read a video into memory to write it straight
                // back out again.
                if let url = file.fileURL {
                    _ = try TrayStore.shared.add(
                        copyingFrom: url, suggestedName: file.filename, uti: file.type?.identifier
                    )
                } else {
                    _ = try TrayStore.shared.add(
                        data: file.data, suggestedName: file.filename, uti: file.type?.identifier
                    )
                }
                added += 1
            } catch {
                failed.append(file.filename)
            }
        }
        // The island is what the user sees from wherever they ran this, so it
        // has to be told. `restart()` rather than `sync()`: this process may
        // have just been launched for the intent and have no activity of its
        // own yet.
        await TrayActivityController.shared.restart()

        let result = DropReceiver.Result(added: added, failed: failed)
        return .result(dialog: IntentDialog(stringLiteral: DropReceiver.shareSheetMessage(for: result)))
    }
}
