import SwiftUI

/// Hands one of the app's ready-made shortcuts to the Shortcuts app.
///
/// The file is built and signed at build time by scripts/make-shortcuts.py,
/// not here: signing needs macOS, and an unsigned shortcut can only be
/// imported after the user finds "Allow Untrusted Shortcuts" in Settings --
/// which iOS hides until they have run a shortcut at least once.
struct ShortcutLink: View {
    private let url: URL?
    private let title: String

    init(_ resource: String, title: String) {
        url = Bundle.main.url(forResource: resource, withExtension: "shortcut")
        self.title = title
    }

    var body: some View {
        if let url {
            ShareLink(item: url) {
                Label(title, systemImage: "square.and.arrow.down")
            }
        }
    }
}
