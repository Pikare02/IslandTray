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
        static let orderingKey = "orderingKey"
        static let orderingAscending = "orderingAscending"
        static let groupsByKind = "groupsByKind"
        static let language = "language"
        static let theme = "theme"
        static let checksForUpdates = "checksForUpdates"
        static let skippedUpdateVersion = "skippedUpdateVersion"
    }

    /// The suite everything here reads, exposed so `@AppStorage` can watch the
    /// same keys -- a SwiftUI view has to be told when one of these changes,
    /// and this type is a plain value with nothing to observe.
    static var store: UserDefaults { UserDefaults(suiteName: TrayIDs.appGroupID) ?? .standard }

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
    /// `false`: the user asked for a copy by default, since a cut can also
    /// delete the original file.
    ///
    /// Only the app process ever reads this; the widget has no say in what
    /// leaves the tray. It lives here anyway because `TraySettings` is the
    /// one place a setting is defined, not because the widget needs it.
    var removeOnExport: Bool {
        get { defaults.object(forKey: Keys.removeOnExport) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Keys.removeOnExport) }
    }

    /// How the grid is arranged. Stored as its parts rather than as encoded
    /// data, so a value written by a build that did not know one of them
    /// still reads back with that part at its default.
    var ordering: TrayOrdering {
        get {
            var ordering = TrayOrdering()
            if let raw = defaults.string(forKey: Keys.orderingKey),
               let key = TrayOrdering.Key(rawValue: raw) {
                ordering.key = key
            }
            ordering.ascending = defaults.object(forKey: Keys.orderingAscending) as? Bool ?? false
            ordering.groupsByKind = defaults.object(forKey: Keys.groupsByKind) as? Bool ?? false
            return ordering
        }
        nonmutating set {
            defaults.set(newValue.key.rawValue, forKey: Keys.orderingKey)
            defaults.set(newValue.ascending, forKey: Keys.orderingAscending)
            defaults.set(newValue.groupsByKind, forKey: Keys.groupsByKind)
        }
    }

    /// The language the app is shown in: "en", "ja", or nil for whatever the
    /// device is set to.
    ///
    /// Not a cross-process setting like the others in spirit -- but the widget
    /// reads it too, and without an App Group it will not see a choice the app
    /// wrote, so it falls back to the device's own language. That is the right
    /// thing to fall back to.
    var language: String? {
        get { defaults.string(forKey: Keys.language) }
        nonmutating set { defaults.set(newValue, forKey: Keys.language) }
    }

    /// "light", "dark", or nil to follow the device.
    var theme: String? {
        get { defaults.string(forKey: Keys.theme) }
        nonmutating set { defaults.set(newValue, forKey: Keys.theme) }
    }

    /// Whether the app asks GitHub for a newer release each time it opens.
    /// Defaults to `true`. Only the app reads it.
    var checksForUpdates: Bool {
        get { defaults.object(forKey: Keys.checksForUpdates) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Keys.checksForUpdates) }
    }

    /// A release the user asked not to be told about again. A later release
    /// is still offered.
    var skippedUpdateVersion: String? {
        get { defaults.string(forKey: Keys.skippedUpdateVersion) }
        nonmutating set { defaults.set(newValue, forKey: Keys.skippedUpdateVersion) }
    }
}
