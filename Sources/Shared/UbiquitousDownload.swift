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
        // A file literally named `.icloud` has no target.
        let target = String(name.dropFirst().dropLast(".icloud".count))
        guard !target.isEmpty else { return nil }
        return target
    }

    private static let keys: Set<URLResourceKey> = [
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .isDirectoryKey,
    ]

    private static func isUbiquitous(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true
    }

    /// The real URLs of every item at or under `url` that is not on this
    /// device yet. Empty when `url` itself is not in iCloud: a local folder
    /// can hold old `.X.icloud` stubs that will never turn into files.
    /// `assumingUbiquitous` skips that root check for a caller that has
    /// already made it (or a test walking a local fixture).
    ///
    /// Hidden files are walked: the placeholders are hidden files.
    static func pending(in url: URL, assumingUbiquitous: Bool = false) -> [URL] {
        guard assumingUbiquitous || isUbiquitous(url) else { return [] }
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
    /// list is empty. Returns at once for anything outside iCloud.
    static func ensureDownloaded(_ url: URL, timeout: TimeInterval = 120, poll: TimeInterval = 0.5) throws {
        guard isUbiquitous(url) else { return }
        try waitUntilDownloaded(url, deadline: Date().addingTimeInterval(timeout), poll: poll)
    }

    /// The wait loop. Items that appear while waiting (a folder whose
    /// contents only became visible once it arrived) are asked for too.
    static func waitUntilDownloaded(_ url: URL, deadline: Date, poll: TimeInterval) throws {
        var asked = Set<URL>()
        // The root is the one URL reused on every pass; its resource values
        // can be served from a cache, so a status that has moved on since
        // the last pass would be read as unchanged.
        var root = url
        while true {
            root.removeAllCachedResourceValues()
            let missing = pending(in: root, assumingUbiquitous: true)
            if missing.isEmpty { return }
            for item in missing where asked.insert(item).inserted {
                // A refusal is not reported here: an item that never
                // arrives is what the deadline below names.
                try? FileManager.default.startDownloadingUbiquitousItem(at: item)
            }
            // An offline device or a refused download should fail the drop
            // now, not after two minutes of "taking in...". A placeholder's
            // real URL may not exist yet; that reads as no error.
            for item in missing {
                if let error = (try? item.resourceValues(forKeys: [.ubiquitousItemDownloadingErrorKey]))?
                    .ubiquitousItemDownloadingError {
                    throw error
                }
            }
            if Date() >= deadline { throw TimedOut(name: missing[0].lastPathComponent) }
            Thread.sleep(forTimeInterval: poll)
        }
    }
}
