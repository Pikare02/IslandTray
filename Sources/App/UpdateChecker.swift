import Foundation

/// Asks GitHub whether a newer release than this build exists.
///
/// Only asks: a sideloaded app cannot replace itself, so a newer version is
/// handed to the install page, where the .ipa is downloaded and installed
/// with whatever tool installed this one.
enum UpdateChecker {
    static let installPage = URL(string: "https://pikare02.github.io/IslandTray/")!
    private static let latestRelease = URL(string: "https://api.github.com/repos/Pikare02/IslandTray/releases/latest")!

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// A release newer than this build.
    struct Update: Equatable {
        let version: String
        /// Whether this one should be pressed rather than merely offered: a
        /// fix that cannot wait, or a version that changes how the app is
        /// used. Nothing else interrupts twice.
        let isImportant: Bool
    }

    /// The latest release when it is newer than this build, nil when it is
    /// not. Throws when GitHub could not be asked.
    static func newerVersion() async throws -> Update? {
        var request = URLRequest(url: latestRelease)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        struct Release: Decodable { let tag_name: String; let body: String? }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard isNewer(release.tag_name, than: currentVersion) else { return nil }
        return update(tag: release.tag_name, notes: release.body, local: currentVersion)
    }

    /// Marker a release's notes carry when the release fixes something that
    /// cannot wait. Written in the notes rather than derived from the version,
    /// because a patch release is exactly where an urgent fix lands.
    static let urgentMarker = "[urgent]"

    /// A major version means the app works differently than it did -- the one
    /// thing worth insisting on besides an urgent fix; everything else is a
    /// normal update, offered once and skippable.
    static func update(tag: String, notes: String?, local: String) -> Update {
        let remote = version(tag)
        let major = { (s: String) in Int(s.split(separator: ".").first ?? "") ?? 0 }
        let isUrgent = notes?.localizedCaseInsensitiveContains(urgentMarker) == true
        return Update(version: remote, isImportant: isUrgent || major(remote) > major(local))
    }

    /// Whether `update` may be dismissed for good. An important one may not,
    /// unless the user turned insisting off.
    static func isSkippable(_ update: Update, insisting: Bool) -> Bool {
        !(update.isImportant && insisting)
    }

    /// Whether `update` is shown on launch. "Don't show again" is honoured
    /// only for an update that could be skipped: an important one ignores an
    /// answer given about an ordinary update.
    static func shouldOffer(_ update: Update, skipped: String?, insisting: Bool) -> Bool {
        !isSkippable(update, insisting: insisting) || update.version != skipped
    }

    /// Compares dotted versions numerically ("1.10.0" > "1.9.2"), ignoring a
    /// leading "v" and treating missing parts as zero.
    static func isNewer(_ remote: String, than local: String) -> Bool {
        let parts = { (s: String) in version(s).split(separator: ".").map { Int($0) ?? 0 } }
        let (r, l) = (parts(remote), parts(local))
        for i in 0..<max(r.count, l.count) {
            let (a, b) = (i < r.count ? r[i] : 0, i < l.count ? l[i] : 0)
            if a != b { return a > b }
        }
        return false
    }

    private static func version(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }
}
