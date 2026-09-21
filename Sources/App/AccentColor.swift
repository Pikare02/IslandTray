import SwiftUI

/// The app's highlight colour, chosen in the settings.
///
/// Stored as a hex string because that is what survives `UserDefaults`, what
/// a person can type in, and what a recents list can hold. An empty string
/// means the app's own blue, which is what `nil` tint gives.
enum AccentColor {
    static let key = "accent"
    private static let recentsKey = "accentRecents"
    private static let recentsLimit = 8

    /// A handful to tap without thinking. Deliberately short: a wall of
    /// swatches is slower to choose from than six, and the system picker is
    /// one tap away for anything else.
    static let common = [
        "007AFF", "34C759", "FF9500", "FF3B30", "AF52DE", "FF2D55", "5AC8FA", "8E8E93"
    ]

    static func color(forHex hex: String) -> Color? {
        var value: UInt64 = 0
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&value) else { return nil }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    static func hex(for color: Color) -> String {
        let components = UIColor(color).cgColor.components ?? []
        // A grey comes back as two components (white, alpha), a colour as
        // four; reading [0],[1],[2] blindly would crash on the first.
        let (r, g, b): (CGFloat, CGFloat, CGFloat) = components.count >= 3
            ? (components[0], components[1], components[2])
            : (components.first ?? 0, components.first ?? 0, components.first ?? 0)
        let clamp = { (v: CGFloat) in Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }

    static var recents: [String] {
        TraySettings.store.stringArray(forKey: recentsKey) ?? []
    }

    /// Most recent first, without duplicates, so the list stays short and the
    /// last few choices are always the first few swatches.
    static func remember(_ hex: String) {
        guard color(forHex: hex) != nil else { return }
        var list = recents.filter { $0.caseInsensitiveCompare(hex) != .orderedSame }
        list.insert(hex.uppercased(), at: 0)
        TraySettings.store.set(Array(list.prefix(recentsLimit)), forKey: recentsKey)
    }
}
