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
    /// A photo library asset's local identifier. No longer recorded: kept so
    /// that items written by the builds that did still decode. See
    /// `photoMetadata`.
    case photo(localIdentifier: String)
    /// What a photo's own metadata said about it. No longer recorded either,
    /// and the reason photos are simply copies now.
    ///
    /// A photo dragged out of Photos arrives re-encoded: the device reported
    /// a HEIC library asset arriving as "IMG_9787.jpeg" with a capture time
    /// 27 hours off, and then as a bare "public.jpeg" with no capture time at
    /// all. There is nothing left in it that identifies which of a library's
    /// thousands of same-sized images it was, and deleting the wrong photo is
    /// not a mistake worth risking for a guess. Kept as a case so items
    /// written by the builds that recorded it still decode.
    case photoMetadata(creationDate: Date, pixelWidth: Int, pixelHeight: Int)

    /// Whether taking the item out can delete what it came from.
    ///
    /// Only a file. A photo origin is legacy data and is treated exactly like
    /// no origin at all.
    var deletesOriginal: Bool {
        switch self {
        case .file: return true
        case .photo, .photoMetadata: return false
        }
    }
}

/// Which of the app's two boards an item belongs to.
///
/// One store holds both. The alternative -- a second `TrayStore` rooted
/// somewhere else -- would need every path in the app to learn which
/// container an item came from, starting with `TrayItem.fileURL`, and would
/// duplicate a file's worth of hard-won guarantees to save a field.
enum TrayBoard: String, Codable, Hashable, CaseIterable {
    case tray
    case clipboard
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
    /// Which board this belongs to. Optional so that items written before
    /// there were two boards decode as what they were: the tray.
    var board: TrayBoard?
    /// Where the bytes came from, when the source can still be reached and
    /// deleted -- what makes taking an item out a move rather than a copy.
    ///
    /// Optional, and optional on purpose: an item added before this existed
    /// decodes with `nil` (Swift's synthesized decoder uses
    /// `decodeIfPresent` for an Optional), so no schema bump and no rebuild.
    /// `nil` simply means there is nothing to delete, which is most sources.
    var origin: TrayItemOrigin?

    /// The board, with the default an item written before boards existed
    /// implies.
    var boardOrTray: TrayBoard { board ?? .tray }

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
        if type.conforms(to: .folder) { return "folder" }
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
