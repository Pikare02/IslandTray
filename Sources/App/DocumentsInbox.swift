import Foundation
import UniformTypeIdentifiers

/// The app's Documents folder, which `UIFileSharingEnabled` exposes in the
/// Files app as "On My iPhone / IslandTray", used as an inbox.
///
/// This is how anything reaches the tray from another app's share sheet on a
/// free developer account. The share extension cannot do it: without the App
/// Group entitlement -- which does not survive SideStore's re-signing -- the
/// extension and the app resolve to different sandboxes, so a file the
/// extension receives has nowhere to go. "ファイルに保存" -> IslandTray is a
/// route through the system's own file layer that needs no entitlement.
///
/// The tray itself lives in Application Support, not here, so this folder
/// holds nothing but what the user put in it.
enum DocumentsInbox {
    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// The Files app hides an app's folder while it is empty, so an empty
    /// inbox cannot be found -- and it is empty exactly when the user is
    /// looking for somewhere to save their first file. This one file keeps
    /// the folder on screen, and says what the folder is for.
    ///
    /// Skipped by the sweep by name, which does mean a file the user saves
    /// under this exact name is ignored. The alternative is a folder that
    /// does not exist until it is no longer needed.
    static let markerName = "ここに保存.txt"

    /// Both languages, always. The file is written once and the name never
    /// changes with the app's language -- a renamed marker would stop being
    /// skipped by the sweep and would get taken into the tray as a text file.
    private static let markerBody = """
    このフォルダに保存したファイルは、IslandTray を開いたときにトレイへ取り込まれます。
    取り込まれたファイルはこのフォルダから消えます（移動です）。
    このファイル自体は取り込まれません。消しても次回起動時に作り直されます。

    Anything you save in this folder is taken into the tray the next time you
    open IslandTray, and disappears from here (it is a move, not a copy).
    This file itself is never taken in; delete it and it comes back.
    """

    /// Creates the marker if it is missing. Cheap enough to call on every
    /// sweep, which is also the only way it comes back after the user deletes
    /// it.
    static func ensureVisible(in directory: URL = directory) {
        let marker = directory.appendingPathComponent(markerName)
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data(markerBody.utf8).write(to: marker, options: .atomic)
    }

    /// Moves every file in the inbox into the tray.
    ///
    /// Reports through `DropReceiver.Result` rather than a type of its own so
    /// this shares `TrayModel.ingestBanner(reloadSucceeded:result:)` with the
    /// drop path -- the precedence there (a failed read outranks an import
    /// failure outranks a clean import) is the same either way.
    ///
    /// Synchronous, and copies files: callers keep it off the main actor, the
    /// same as `TrayStore.add(copyingFrom:)` everywhere else.
    static func sweep(store: TrayStore = .shared, directory: URL = directory) -> DropReceiver.Result {
        defer { ensureVisible(in: directory) }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentTypeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var added = 0
        var failed: [String] = []
        for url in contents {
            let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey])
            // A folder is taken in whole, as one item, never walked into its
            // files. Except "Inbox": iOS owns that one, for files other apps
            // hand over with "Open In".
            if values?.isDirectory == true, url.lastPathComponent == "Inbox" { continue }
            guard url.lastPathComponent != markerName else { continue }
            do {
                _ = try store.add(
                    copyingFrom: url,
                    suggestedName: url.lastPathComponent,
                    uti: values?.contentType?.identifier
                )
            } catch {
                failed.append(url.lastPathComponent)
                continue
            }
            do {
                // Only after the copy landed. If this throws the file is now
                // in both places and the next sweep would import it twice, so
                // it is reported rather than swallowed -- the user can delete
                // it in Files.
                try FileManager.default.removeItem(at: url)
            } catch {
                failed.append(url.lastPathComponent)
                continue
            }
            added += 1
        }
        return DropReceiver.Result(added: added, failed: failed)
    }
}
