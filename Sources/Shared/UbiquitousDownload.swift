import Foundation

/// Brings a file -- or everything inside a folder -- that iCloud lists but
/// has not put on this device down, before it is copied into the tray.
///
/// A coordinated read of one evicted file does trigger its download, but a
/// read of a folder does not fetch its children: a copy of the folder then
/// carries `.X.icloud` placeholders instead of files, with the wrong size,
/// and the bytes never match an item already in the tray. This walks the
/// source, asks for every missing item, and waits until none is missing.
///
/// Synchronous on purpose: every caller is already off the main actor (an
/// `NSItemProvider` completion queue, `Task.detached`, the inbox sweep).
/// The caller holds any security scope the URL needs.
enum UbiquitousDownload {
    struct TimedOut: LocalizedError {
        let name: String
        var errorDescription: String? { L.s("cloud.downloadTimedOut", name) }
    }

    /// `.X.icloud` is how iCloud lists a file it has not downloaded.
    static func placeholderTarget(_ name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return nil }
        return String(name.dropFirst().dropLast(".icloud".count))
    }

    private static let keys: Set<URLResourceKey> = [
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .isDirectoryKey,
    ]

    /// The real URLs of every item at or under `url` that is not on this
    /// device yet. Empty for anything outside iCloud.
    ///
    /// Hidden files are walked: the placeholders are hidden files.
    static func pending(in url: URL) -> [URL] {
        var urls = [url]
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
           let walker = FileManager.default.enumerator(
               at: url, includingPropertiesForKeys: Array(keys), options: []
           ) {
            while let child = walker.nextObject() as? URL { urls.append(child) }
        }
        return urls.compactMap { item in
            if let real = placeholderTarget(item.lastPathComponent) {
                return item.deletingLastPathComponent().appendingPathComponent(real)
            }
            // `.notDownloaded` only, not "anything but current": a folder in
            // iCloud reports no status at all, and would otherwise be waited
            // on until the deadline.
            guard let values = try? item.resourceValues(forKeys: keys),
                  values.isDirectory != true,
                  values.isUbiquitousItem == true,
                  values.ubiquitousItemDownloadingStatus == .notDownloaded else { return nil }
            return item
        }
    }

    /// Asks iCloud for everything `pending(in:)` lists and waits until the
    /// list is empty. Items that appear while waiting (a folder whose
    /// contents only became visible once it arrived) are asked for too.
    static func ensureDownloaded(_ url: URL, timeout: TimeInterval = 120, poll: TimeInterval = 0.5) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var asked = Set<URL>()
        while true {
            let missing = pending(in: url)
            if missing.isEmpty { return }
            for item in missing where asked.insert(item).inserted {
                // A refusal is not reported here: an item that never
                // arrives is what the deadline below names.
                try? FileManager.default.startDownloadingUbiquitousItem(at: item)
            }
            if Date() >= deadline { throw TimedOut(name: missing[0].lastPathComponent) }
            Thread.sleep(forTimeInterval: poll)
        }
    }
}
