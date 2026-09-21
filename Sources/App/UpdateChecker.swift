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

    /// The latest release's version when it is newer than this build, nil
    /// when it is not. Throws when GitHub could not be asked.
    static func newerVersion() async throws -> String? {
        var request = URLRequest(url: latestRelease)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        struct Release: Decodable { let tag_name: String }
        let latest = try JSONDecoder().decode(Release.self, from: data).tag_name
        return isNewer(latest, than: currentVersion) ? version(latest) : nil
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
