import AppIntents
import UIKit
import UniformTypeIdentifiers

/// Puts what is on the system clipboard onto the app's clipboard board.
///
/// Driven from a shortcut, which is what makes it reachable from the Action
/// button, a back tap, or the share sheet: copy something, run the shortcut,
/// and it is kept here instead of being overwritten by the next copy.
///
/// One parameter, not one for text and one for files. The clipboard holds
/// either, "Get Clipboard" hands over whichever it found, and a shortcut with
/// two slots makes the person decide every time which one today's copy goes
/// in. Shortcuts converts text to a file on its way into this, and text is
/// recognised again on arrival by its type.
struct AddToClipboardIntent: AppIntent {
    static let title: LocalizedStringResource = "クリップボードに追加"
    static let description = IntentDescription(
        "コピーした内容をアプリのクリップボードに保存します。「クリップボードを取得」の出力をつなげてください。"
    )
    static let openAppWhenRun: Bool = false

    /// Optional, so a shortcut that has not had the Clipboard variable
    /// connected to it still runs instead of stopping to ask for a file every
    /// time. What it does with nothing is below.
    @Parameter(title: "内容", supportedTypeIdentifiers: ["public.item"])
    var content: [IntentFile]?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let files = content ?? []
        guard !files.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral: await fromPasteboard()))
        }

        var added = 0
        var failed: [String] = []

        for file in files {
            do {
                try add(file)
                added += 1
            } catch {
                failed.append(file.filename)
            }
        }

        let result = DropReceiver.Result(added: added, failed: failed)
        return .result(dialog: IntentDialog(stringLiteral: DropReceiver.shareSheetMessage(for: result)))
    }

    /// The last resort when the shortcut handed over nothing: read the
    /// system clipboard here instead.
    ///
    /// iOS only lets an app read the clipboard while it is in front, so this
    /// works when the shortcut is run with the app open and not when it is
    /// run from a back tap in another app. That is exactly when it says so,
    /// rather than reporting that it added nothing and leaving the person to
    /// guess which of the two happened.
    @MainActor
    private func fromPasteboard() async -> String {
        let board = UIPasteboard.general
        if let text = board.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                _ = try TrayStore.shared.add(
                    data: Data(text.utf8), suggestedName: Self.name(for: text),
                    uti: UTType.utf8PlainText.identifier, board: .clipboard
                )
                return DropReceiver.shareSheetMessage(for: .init(added: 1, failed: []))
            } catch {
                return DropReceiver.shareSheetMessage(for: .init(added: 0, failed: ["clipboard"]))
            }
        }
        if let type = board.types.first, let data = board.data(forPasteboardType: type) {
            let uti = UTType(type)
            let ext = uti?.preferredFilenameExtension.map { ".\($0)" } ?? ""
            do {
                _ = try TrayStore.shared.add(
                    data: data, suggestedName: "clipboard\(ext)",
                    uti: uti?.identifier, board: .clipboard
                )
                return DropReceiver.shareSheetMessage(for: .init(added: 1, failed: []))
            } catch {
                return DropReceiver.shareSheetMessage(for: .init(added: 0, failed: ["clipboard"]))
            }
        }
        return L.s("clipboard.connectVariable")
    }

    private func add(_ file: IntentFile) throws {
        // Text arrives as a file whose name is whatever Shortcuts made up.
        // Naming it after what it says is the difference between a readable
        // board and a column of "Text.txt".
        if let text = Self.text(in: file) {
            _ = try TrayStore.shared.add(
                data: Data(text.utf8),
                suggestedName: Self.name(for: text),
                uti: UTType.utf8PlainText.identifier,
                board: .clipboard
            )
            return
        }
        // The URL when there is one: it is already a file on disk, and `data`
        // would read a video into memory to write it straight back out.
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
    }

    /// The file's contents when it is text, and nil when it is anything else.
    ///
    /// By declared type first, and only then by whether the bytes happen to
    /// decode: a JPEG that decodes as UTF-8 by accident is not text, and a
    /// text file with no type is.
    static func text(in file: IntentFile) -> String? {
        if let type = file.type, !type.conforms(to: .text) { return nil }
        guard let text = String(data: file.data, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    /// A filename made of the text's first line, short enough to read on a
    /// card and safe enough to hand to the sanitizer.
    static func name(for text: String) -> String {
        let firstLine = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first ?? ""
        let head = String(firstLine.prefix(40)).trimmingCharacters(in: .whitespaces)
        return head.isEmpty ? "clipboard.txt" : "\(head).txt"
    }
}
