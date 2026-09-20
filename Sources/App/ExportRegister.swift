import Foundation

/// The items handed to another app that have not left the tray yet.
///
/// On disk rather than in memory, because this is lost exactly when it
/// matters. Handing a file to another app means the user leaves this one, and
/// a backgrounded app -- a sideloaded one especially -- is routinely killed
/// before they come back. With the record gone, the move never completed: the
/// item reappeared in the tray and the original was never touched.
///
/// `UserDefaults` rather than a file: this is a handful of UUIDs that must
/// survive a kill, not tray data, and `TrayStore`'s coordinated writes are
/// for the user's files.
struct ExportRegister {
    private let defaults: UserDefaults
    private let key = "exportedItems"

    init(defaults: UserDefaults = UserDefaults(suiteName: TrayIDs.appGroupID) ?? .standard) {
        self.defaults = defaults
    }

    var ids: Set<UUID> {
        get { Set((defaults.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:))) }
        nonmutating set { defaults.set(newValue.map(\.uuidString), forKey: key) }
    }
}
