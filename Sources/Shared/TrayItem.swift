import Foundation
import UniformTypeIdentifiers

/// A handle back to the file a tray item was taken from.
///
/// Only two kinds of source can be reached again after the drag that
/// delivered them. Everything else (a web image, a mail attachment, text
/// pasted from Notes) has no original to delete, and items from those carry
/// no origin at all.
enum TrayItemOrigin: Codable, Hashable {
    /// A security-scoped bookmark to the file the drag came from -- the Files
    /// app, iCloud Drive, or any other document provider. Taken while the
    /// drag's in-place access was still open, because that access ends with
    /// the drag and the deletion happens much later.
    case file(bookmark: Data)
    /// A photo library asset's local identifier.
    case photo(localIdentifier: String)
}

struct TrayItem: Codable, Hashable, Identifiable {
    var id: UUID
    /// Display name, already sanitized. Never used to build a path.
    var name: String
    var uti: String
    var size: Int
    var addedAt: Date
    /// Lowercased extension without the dot. May be empty.
    var ext: String
    /// Where the bytes came from, when the source can still be reached and
    /// deleted -- what makes taking an item out a move rather than a copy.
    ///
    /// Optional, and optional on purpose: an item added before this existed
    /// decodes with `nil` (Swift's synthesized decoder uses
    /// `decodeIfPresent` for an Optional), so no schema bump and no rebuild.
    /// `nil` simply means there is nothing to delete, which is most sources.
    var origin: TrayItemOrigin?

    /// Path is built from the UUID only, never from `name`.
    var fileName: String { ext.isEmpty ? id.uuidString : "\(id.uuidString).\(ext)" }

    func fileURL(in itemsDirectory: URL) -> URL {
        itemsDirectory.appendingPathComponent(fileName)
    }

    func thumbnailURL(in thumbsDirectory: URL) -> URL {
        thumbsDirectory.appendingPathComponent("\(id.uuidString).png")
    }

    var fileURL: URL { fileURL(in: TrayContainer.itemsDirectory) }
    var thumbnailURL: URL { thumbnailURL(in: TrayContainer.thumbsDirectory) }

    /// Fallback glyph used in the Dynamic Island when thumbnails are unreachable.
    var symbolName: String { Self.symbolName(forUTI: uti) }

    static func symbolName(forUTI identifier: String) -> String {
        guard let type = UTType(identifier) else { return "doc" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .movie) { return "film" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .archive) { return "doc.zipper" }
        if type.conforms(to: .spreadsheet) { return "tablecells" }
        if type.conforms(to: .presentation) { return "rectangle.on.rectangle" }
        if type.conforms(to: .sourceCode) { return "chevron.left.forwardslash.chevron.right" }
        if type.conforms(to: .url) { return "link" }
        if type.conforms(to: .text) { return "doc.text" }
        return "doc"
    }
}
