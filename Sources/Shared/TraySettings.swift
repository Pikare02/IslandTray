import Foundation

/// User-facing settings, readable from the app and both extensions.
///
/// Backed by `UserDefaults(suiteName: TrayIDs.appGroupID)`, the same App
/// Group the rest of the tray's shared state would use if it were available.
/// On the real deployment (a free developer account sideloaded with
/// SideStore) that App Group does not survive re-signing, so the app and the
/// widget extension each end up reading and writing their own private
/// defaults instead of a shared one -- a value the app writes is invisible to
/// the widget process, and vice versa.
///
/// That is only safe because every setting below is defined so its *default*
/// -- what a process sees when it has never had this key written locally --
/// is the correct behavior to fall back to. Nothing here may assume a
/// cross-process write was observed.
struct TraySettings {
    private let defaults: UserDefaults

    /// `defaults` defaults to the App Group suite, falling back to `.standard`
    /// when the suite can't be opened (no entitlement). Injectable so tests
    /// can point at an isolated suite instead of touching real user defaults.
    ///
    /// No `static let shared`: `UserDefaults` isn't `Sendable`, so a cached
    /// instance would make this a non-Sendable value shared across
    /// concurrency domains (Swift 6 strict concurrency rejects that, and
    /// `@unchecked Sendable` is off the table here). Constructing a fresh
    /// `TraySettings()` per call is cheap -- `UserDefaults` itself is the
    /// actual shared, thread-safe store; this struct is just a typed view
    /// onto it, never retained anywhere.
    init(defaults: UserDefaults = UserDefaults(suiteName: TrayIDs.appGroupID) ?? .standard) {
        self.defaults = defaults
    }

    private enum Keys {
        static let showActivityWhenEmpty = "showActivityWhenEmpty"
        static let removeOnExport = "removeOnExport"
    }

    /// Whether the Live Activity should stay up while the tray has zero
    /// items, as long as the app is alive in the background. Defaults to
    /// `true` -- the behavior the user asked for, and also the one value that
    /// is safe to fall back to when a process can't see an override written
    /// elsewhere.
    var showActivityWhenEmpty: Bool {
        get { defaults.object(forKey: Keys.showActivityWhenEmpty) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Keys.showActivityWhenEmpty) }
    }

    /// Whether handing an item to another app takes it out of the tray --
    /// the tray as a cut buffer rather than a copy buffer. Defaults to
    /// `true`, which is what the user asked for.
    ///
    /// Only the app process ever reads this; the widget has no say in what
    /// leaves the tray. It lives here anyway because `TraySettings` is the
    /// one place a setting is defined, not because the widget needs it.
    var removeOnExport: Bool {
        get { defaults.object(forKey: Keys.removeOnExport) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Keys.removeOnExport) }
    }
}
