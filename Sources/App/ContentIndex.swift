import Foundation
import Observation
import UniformTypeIdentifiers
import Vision

/// The words inside each item, for searching by content: what a text item
/// says, and what Vision reads in an image.
///
/// Built on the search screen, for items not read yet, and kept on disk:
/// recognising the text in a screenshot takes a noticeable moment, and the
/// answer for an item never changes.
@MainActor
@Observable
final class ContentIndex {
    static let shared = ContentIndex()

    /// Item id to its words; "" for an item with none, so it is not read again.
    private(set) var texts: [UUID: String]
    private(set) var isIndexing = false

    /// A text file bigger than this is left out rather than read whole.
    private static let maxTextBytes = 2_000_000

    /// Caches, not the container: all of it can be rebuilt from the items.
    private static let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("content-index.json")

    private init() {
        texts = (try? JSONDecoder().decode([UUID: String].self, from: Data(contentsOf: Self.url))) ?? [:]
    }

    func text(for item: TrayItem) -> String? {
        texts[item.id].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Reads whatever in `items` has not been read yet, and forgets what is
    /// no longer there. Stops early when its task is cancelled -- the search
    /// screen restarts it whenever the items change -- keeping what it read.
    func update(_ items: [TrayItem]) async {
        let ids = Set(items.map(\.id))
        let stale = texts.keys.filter { !ids.contains($0) }
        let unread = items.filter { texts[$0.id] == nil }
        guard !stale.isEmpty || !unread.isEmpty else { return }

        for id in stale { texts[id] = nil }
        isIndexing = true
        for item in unread {
            if Task.isCancelled { break }
            texts[item.id] = await read(item)
        }
        isIndexing = false
        try? JSONEncoder().encode(texts).write(to: Self.url, options: .atomic)
    }

    private func read(_ item: TrayItem) async -> String {
        guard let type = UTType(item.uti) else { return "" }
        let url = item.fileURL
        if type.conforms(to: .image) {
            return await Task.detached(priority: .utility) { Self.recognise(url) }.value
        }
        guard type.conforms(to: .text), item.size <= Self.maxTextBytes else { return "" }
        // Rich text by its words, not its RTF or HTML source.
        if let rich = RichText.contents(of: item) { return rich.plain }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// The text Vision finds in an image, one line per observation.
    nonisolated static func recognise(_ url: URL) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Korean, Japanese and English alike, without asking which.
        request.automaticallyDetectsLanguage = true
        guard (try? VNImageRequestHandler(url: url).perform([request])) != nil else { return "" }
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
