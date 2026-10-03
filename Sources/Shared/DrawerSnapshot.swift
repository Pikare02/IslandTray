import Foundation
import WidgetKit

/// The drawer as the island last drew it, kept by the widget extension for
/// its own Home Screen and Lock Screen widgets.
///
/// Nothing else can reach them: the free build has no App Group, so the app
/// cannot hand the extension a file. But the Live Activity's views are
/// evaluated in the extension's own process, with the slots and the icon
/// strip already inside the content state -- so the view records what it
/// was given, and the widgets read that back. The app never touches this.
enum DrawerSnapshot {
    struct Payload: Codable, Equatable {
        let slots: [TrayContentState.DrawerSlot]
        let atlas: Data?
        /// Where the drawer's tiles start in `atlas`: after the tray's own on
        /// a tray state, 0 on a drawer state. The island's own rule.
        let atlasOffset: Int
    }

    enum Change: Equatable { case written, removed, unchanged }

    /// The widget this feeds, for `reloadTimelines(ofKind:)`.
    static let widgetKind = "DrawerWidget"

    /// Inside whichever process asks -- the extension's own container when
    /// the extension does, which is the only one that ever reads it.
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IslandTray", isDirectory: true)
            .appendingPathComponent("drawer-snapshot.json")
    }

    static func payload(for state: TrayContentState) -> Payload? {
        guard let slots = state.drawer else { return nil }
        return Payload(slots: slots, atlas: state.atlas,
                       atlasOffset: state.view == .drawer ? 0 : state.recent.count)
    }

    /// Saves what the island was given. Writes only on a change, and only
    /// then asks the widget to reload, so a state the island redraws every
    /// few minutes costs nothing here.
    @discardableResult
    static func record(_ state: TrayContentState, at url: URL = url) -> Change {
        let fm = FileManager.default
        // sortedKeys: the unchanged check compares bytes, so the encoding must be stable.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let payload = payload(for: state), let data = try? encoder.encode(payload) else {
            // Drawer turned off: the widget must not keep showing one.
            guard !state.drawerAvailable, fm.fileExists(atPath: url.path) else { return .unchanged }
            try? fm.removeItem(at: url)
            WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
            return .removed
        }
        // A tray state carries the drawer only as far as its own tiles leave
        // room: icons only with the Lock Screen drawer on, and slots shed to
        // nothing when the state runs out of bytes. What a drawer state
        // recorded stays unless the drawer's make-up changed, or the tray
        // state has more icons than what is on disk. It also keeps the
        // tray's own thumbnails from rewriting this file on every change.
        if state.view != .drawer {
            if payload.slots.isEmpty { return .unchanged }
            if let existing = load(from: url),
               existing.slots.map(Self.identity) == payload.slots.map(Self.identity),
               existing.slots.filter(\.hasIcon).count >= payload.slots.filter(\.hasIcon).count {
                return .unchanged
            }
        }
        if (try? Data(contentsOf: url)) == data { return .unchanged }
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            // Lock-screen-readable: the Live Activity is drawn, and this is
            // written, while the device is locked (see TrayContainer).
            try data.write(to: url, options: [.atomic, TrayContainer.lockScreenReadableWrite])
        } catch {
            return .unchanged
        }
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        return .written
    }

    /// What makes a slot the same slot, icon or not.
    private static func identity(_ slot: TrayContentState.DrawerSlot) -> String {
        "\(slot.symbol)|\(slot.name)|\(slot.launch)"
    }

    static func load(from url: URL = url) -> Payload? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }
}
