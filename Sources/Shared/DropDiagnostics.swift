import Foundation

/// A short record of what each drop's item provider actually offered.
///
/// In `Shared` rather than beside `DropReceiver`: that file is compiled into
/// the share extension too, and the extension records here as well.
///
/// Whether a dragged file can be deleted at its source is decided entirely by
/// what the *other* app registers on its item provider, and that cannot be
/// seen from a simulator or a unit test -- only on the device, from the app
/// that received the drag. This is how that answer gets out without a cable:
/// the settings screen shows the last few lines.
enum DropDiagnostics {
    private static let key = "dropDiagnostics"
    private static let limit = 12

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: TrayIDs.appGroupID) ?? .standard
    }

    static var lines: [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    static func record(_ line: String) {
        defaults.set(Array((lines + [line]).suffix(limit)), forKey: key)
    }

    static func clear() {
        defaults.removeObject(forKey: key)
    }

    /// One line per dropped item: what it was, what the provider offered, and
    /// what came out of it.
    static func line(name: String?, types: [String], origin: TrayItemOrigin?) -> String {
        let outcome: String
        switch origin {
        case .file: outcome = "file"
        case .photo: outcome = "photo-id"
        case .photoMetadata: outcome = "photo-exif"
        case nil: outcome = "none"
        }
        // Type identifiers, shortened: the interesting part of
        // "com.apple.photos.asset-identifier" is the tail, and a dozen full
        // identifiers do not fit on a phone screen.
        let shortTypes = types.map { $0.components(separatedBy: ".").suffix(2).joined(separator: ".") }
        return "\(name ?? "?") → \(outcome)\n  \(shortTypes.joined(separator: ", "))"
    }
}
