import UIKit
import UniformTypeIdentifiers

/// Formatted text -- what copying from Safari, Notes or Mail puts on the
/// clipboard -- kept as the format it came in, with its plain words on hand
/// for every receiver that does not read that format.
enum RichText {
    /// The formats this can read back into plain words. RTFD packages are
    /// left out: Shortcuts hands those over as a folder, not as bytes.
    static let types: [UTType] = [.rtf, .flatRTFD, .html]

    /// The rich type of a file, or nil when it is anything else. By declared
    /// type, then by extension, then by the bytes: Shortcuts does not always
    /// say what it is handing over.
    static func type(uti: String?, filename: String, data: Data) -> UTType? {
        if let declared = uti.flatMap(UTType.init), let rich = types.first(where: declared.conforms) {
            return rich
        }
        let ext = (filename as NSString).pathExtension
        if let byName = UTType(filenameExtension: ext), let rich = types.first(where: byName.conforms) {
            return rich
        }
        return data.starts(with: Data("{\\rtf".utf8)) ? .rtf : nil
    }

    /// The words without the formatting. Main actor because the HTML reader
    /// is WebKit, which must not be driven from anywhere else.
    @MainActor
    static func plainText(_ data: Data, type: UTType) -> String? {
        let documentType: NSAttributedString.DocumentType =
            type.conforms(to: .html) ? .html : type.conforms(to: .flatRTFD) ? .rtfd : .rtf
        let text = try? NSAttributedString(
            data: data, options: [.documentType: documentType], documentAttributes: nil
        ).string
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    /// A stored item's rich bytes and their plain words, or nil when it is not
    /// rich text. The bytes are checked too, so an item saved before rich
    /// text was recognised -- RTF source in a .txt -- is still read right.
    @MainActor
    static func contents(of item: TrayItem) -> (type: UTType, data: Data, plain: String)? {
        guard let data = try? Data(contentsOf: item.fileURL),
              let type = type(uti: item.uti, filename: item.fileName, data: data),
              let plain = plainText(data, type: type) else { return nil }
        return (type, data, plain)
    }

    /// Puts an item on the system clipboard: for text, the formatting for
    /// apps that paste it and the plain words beside it for every app that
    /// does not; anything else, as its bytes under its own type. Returns false
    /// when the file could not be read.
    ///
    /// Bytes, not an NSItemProvider: a provider is read lazily, from this
    /// process, and the paste happens in another app after this one is
    /// suspended.
    @MainActor
    @discardableResult
    static func copy(_ item: TrayItem) -> Bool {
        let copied = write(item)
        UINotificationFeedbackGenerator().notificationOccurred(copied ? .success : .error)
        return copied
    }

    @MainActor
    private static func write(_ item: TrayItem) -> Bool {
        if let rich = contents(of: item) {
            UIPasteboard.general.setItems([[
                rich.type.identifier: rich.data,
                UTType.utf8PlainText.identifier: rich.plain,
            ]])
            return true
        }
        guard let data = try? Data(contentsOf: item.fileURL) else { return false }
        if UTType(item.uti)?.conforms(to: .text) == true, let text = String(data: data, encoding: .utf8) {
            UIPasteboard.general.string = text
        } else {
            UIPasteboard.general.setItems([[item.uti: data]])
        }
        return true
    }
}
