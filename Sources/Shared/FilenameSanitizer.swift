import Foundation

/// Normalizes filenames that arrive from drops and the share sheet.
/// These are untrusted input: they may contain path separators, parent
/// references, or control characters. Container paths are always built from a
/// UUID, so this result is only used for display and for the file extension —
/// but it must still never escape the container if it is ever joined to a path.
enum FilenameSanitizer {
    private static let maxBytes = 255

    // Real-world extensions top out around 12 chars (e.g. "sketchplugin",
    // "numbers-tef"). Anything longer isn't a genuine extension, and if left
    // unbounded it can drive `truncate`'s byte budget negative, defeating the
    // 255-byte guarantee (see task-3-review.md Finding 1). Cap with headroom.
    private static let maxExtensionBytes = 20

    static func sanitize(_ raw: String?, fallbackExtension: String?) -> (name: String, ext: String) {
        // Take only the last path component, which drops "../" and any directories.
        var base = (raw ?? "")
            .components(separatedBy: CharacterSet(charactersIn: "/\\"))
            .last ?? ""

        base = base.components(separatedBy: .controlCharacters).joined()
        base = base.components(separatedBy: CharacterSet(charactersIn: "\u{2028}\u{2029}")).joined()
        base = base.trimmingCharacters(in: .whitespacesAndNewlines)

        // A name made only of dots would still resolve to a directory reference.
        if base.allSatisfy({ $0 == "." }) { base = "" }

        var ext = (base as NSString).pathExtension.lowercased()
        if ext.utf8.count > maxExtensionBytes {
            // Not a real extension -- treat as absent so the fallback path below applies.
            ext = ""
        }
        if ext.isEmpty, let fallback = fallbackExtension?.lowercased(), !fallback.isEmpty,
           fallback.utf8.count <= maxExtensionBytes {
            ext = fallback
        }

        var stem = (base as NSString).deletingPathExtension
        if stem.isEmpty { stem = "Untitled" }

        stem = truncate(stem, toBytes: maxBytes - (ext.isEmpty ? 0 : ext.utf8.count + 1))

        let name = ext.isEmpty ? stem : "\(stem).\(ext)"
        return (name, ext)
    }

    private static func truncate(_ s: String, toBytes limit: Int) -> String {
        guard s.utf8.count > limit, limit > 0 else { return s }
        var out = s
        while out.utf8.count > limit { out.removeLast() }
        return out
    }
}
