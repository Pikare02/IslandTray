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
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentTypeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var added = 0
        var failed: [String] = []
        for url in contents {
            let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isRegularFileKey])
            // Folders are left where they are rather than walked: the user put
            // a folder in their own Files space, and taking it apart is not
            // what "the tray took your file" should mean.
            guard values?.isRegularFile == true else { continue }
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
