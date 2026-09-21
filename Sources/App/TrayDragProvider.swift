import Foundation
import UniformTypeIdentifiers

/// Builds the item provider a tray card hands to another app.
///
/// Its own type because two things need it now: the grid's drag delegate,
/// which is where a drag actually starts, and anything else that has to offer
/// the same file under the same name with the same handover bookkeeping.
enum TrayDragProvider {
    @MainActor
    static func provider(for item: TrayItem, model: TrayModel) -> NSItemProvider {
        // Background time, taken here because this runs as the drag begins,
        // with the app still in front. Asking at the handover is too late --
        // by then the user is in the other app and this one is suspending.
        model.beginHandover()

        let provider = NSItemProvider()
        // NSItemProvider takes its suggested filename from the URL's last path
        // component, which is `item.fileURL`'s UUID-based on-disk name
        // (TrayItem deliberately never builds a path from `name`, only from
        // the id). Overriding `suggestedName` is what makes Files/Mail/other
        // drop targets save the file under its real display name instead of
        // the UUID -- it does not rename anything on disk.
        provider.suggestedName = item.name
        // Registered by hand rather than via NSItemProvider(contentsOf:),
        // which is otherwise equivalent, because only this form has a load
        // handler to observe: a receiver asking for the bytes is the signal
        // that the drop was accepted.
        provider.registerFileRepresentation(
            forTypeIdentifier: typeIdentifier(for: item),
            fileOptions: [],
            visibility: .all
        ) { completion in
            // Recorded, never acted on here: the receiving app copies the file
            // after this returns, and the tray may hold the user's only copy.
            model.markExported(item.id)
            completion(item.fileURL, false, nil)
            return nil
        }
        // Formatted text is offered as its plain words too, after the file so
        // that a receiver that reads the formatting still prefers it. Without
        // this a notes field or a chat box gets nothing, or the RTF source.
        if let plain = RichText.contents(of: item)?.plain {
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all
            ) { completion in
                model.markExported(item.id)
                completion(Data(plain.utf8), nil)
                return nil
            }
        }
        return provider
    }

    /// The type the dragged file is offered as.
    ///
    /// `item.uti` is what the drop recorded, and is preferred; it can be a
    /// type this device no longer resolves, in which case the extension is a
    /// better guess than nothing, and `.data` is what any receiver accepts.
    ///
    /// A dynamic type (`dyn.…`, what an undeclared extension such as `.ipa`
    /// resolves to) is offered as `.data` instead: Files refuses a drag that
    /// only offers a dynamic type, while `suggestedName` still carries the
    /// real extension.
    static func typeIdentifier(for item: TrayItem) -> String {
        guard let type = UTType(item.uti) ?? UTType(filenameExtension: item.ext), !type.isDynamic else {
            return UTType.data.identifier
        }
        return type.identifier
    }
}
