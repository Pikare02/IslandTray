import AppIntents

/// Puts what is on the system clipboard onto the app's clipboard board.
///
/// Driven from a shortcut, which is what makes it reachable from the Action
/// button, a back tap, or the share sheet: copy something, run the shortcut,
/// and it is kept here instead of being overwritten by the next copy.
///
/// The text and the files are separate parameters because the clipboard's own
/// contents are: Shortcuts' "Get Clipboard" gives text for text and a file for
/// anything else, and a shortcut can pass whichever it got.
struct AddToClipboardIntent: AppIntent {
    static let title: LocalizedStringResource = "クリップボードに追加"
    static let description = IntentDescription(
        "コピーした内容をアプリのクリップボードに保存します。アクションボタンや背面タップから実行できます。"
    )
    static let openAppWhenRun: Bool = false

    @Parameter(title: "テキスト")
    var text: String?

    @Parameter(title: "ファイル", supportedTypeIdentifiers: ["public.item"])
    var files: [IntentFile]?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var added = 0
        var failed: [String] = []

        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                _ = try TrayStore.shared.add(
                    data: Data(text.utf8),
                    // The first line, so the card reads as what was copied
                    // rather than as "clipboard.txt" over and over.
                    suggestedName: Self.name(for: text),
                    uti: "public.utf8-plain-text",
                    board: .clipboard
                )
                added += 1
            } catch {
                failed.append(Self.name(for: text))
            }
        }

        for file in files ?? [] {
            do {
                if let url = file.fileURL {
                    _ = try TrayStore.shared.add(
                        copyingFrom: url, suggestedName: file.filename, uti: file.type?.identifier,
                        board: .clipboard
                    )
                } else {
                    _ = try TrayStore.shared.add(
                        data: file.data, suggestedName: file.filename, uti: file.type?.identifier,
                        board: .clipboard
                    )
                }
                added += 1
            } catch {
                failed.append(file.filename)
            }
        }

        let result = DropReceiver.Result(added: added, failed: failed)
        return .result(dialog: IntentDialog(stringLiteral: DropReceiver.shareSheetMessage(for: result)))
    }

    /// A filename made of the text's first line, short enough to read on a
    /// card and safe enough to hand to the sanitizer.
    ///
    /// Internal so a test can pin it: this is the only place the app turns
    /// arbitrary pasted text into something with a name.
    static func name(for text: String) -> String {
        let firstLine = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first ?? ""
        let head = String(firstLine.prefix(40)).trimmingCharacters(in: .whitespaces)
        return head.isEmpty ? "clipboard.txt" : "\(head).txt"
    }
}
