import Foundation

/// User-facing text, in the language the app is set to.
///
/// Not SwiftUI's `Text("key")`: that resolves against the device's language,
/// and this app lets the language be chosen in its own settings. Every string
/// therefore goes through here, which picks the bundle for the chosen language
/// and falls back to the device's own when the choice is "system".
///
/// The key is looked up with itself as the fallback value, so a key with no
/// entry shows as the key rather than as nothing -- visible in a screenshot,
/// which a blank label is not.
enum L {
    static func s(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func s(_ key: String, _ arguments: any CVarArg...) -> String {
        String(format: s(key), arguments: arguments)
    }

    private static var bundle: Bundle {
        guard let code = TraySettings().language, !code.isEmpty,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }
}
