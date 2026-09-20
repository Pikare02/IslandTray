import Foundation
import UniformTypeIdentifiers

/// How the grid arranges what is in the tray.
///
/// A value rather than logic spread through the view, and the arranging is a
/// pure function over it, so the part that decides what the user sees can be
/// pinned without a collection view.
struct TrayOrdering: Equatable {
    enum Key: String, CaseIterable {
        case name
        case addedAt
        case size
    }

    var key: Key = .addedAt
    /// Newest, largest, or A→Z first. Defaults to false because the default
    /// key is the time it was added, and the thing just dropped belongs at
    /// the front.
    var ascending = false
    /// Split into one section per kind of file, rather than one flat run.
    var groupsByKind = false

    /// One section per kind when grouping, otherwise a single unnamed one.
    ///
    /// Sections come out in a fixed kind order rather than whatever order the
    /// tray happens to hold, so the grid does not reshuffle its sections
    /// every time something is added.
    struct Section: Equatable {
        let kind: TrayItemKind?
        let items: [TrayItem]
    }

    func arrange(_ items: [TrayItem]) -> [Section] {
        let sorted = items.sorted(by: precedes)
        guard groupsByKind else { return [Section(kind: nil, items: sorted)] }
        return TrayItemKind.allCases.compactMap { kind in
            let matching = sorted.filter { TrayItemKind(uti: $0.uti) == kind }
            return matching.isEmpty ? nil : Section(kind: kind, items: matching)
        }
    }

    private func precedes(_ a: TrayItem, _ b: TrayItem) -> Bool {
        switch key {
        case .name:
            // Case- and width-insensitive, and digits compared as numbers, so
            // "photo 2" comes before "photo 10" the way a person would file
            // them.
            let order = a.name.localizedStandardCompare(b.name)
            if order != .orderedSame { return ascending == (order == .orderedAscending) }
        case .addedAt:
            if a.addedAt != b.addedAt { return ascending == (a.addedAt < b.addedAt) }
        case .size:
            if a.size != b.size { return ascending == (a.size < b.size) }
        }
        // A total order even when the key ties: `sorted(by:)` is not stable,
        // so without this two items of the same size could swap places on
        // every redraw.
        return a.id.uuidString < b.id.uuidString
    }
}

/// The coarse kind of a tray item, for grouping.
///
/// Deliberately few: this exists to break a screenful of cards into runs the
/// eye can skip through, not to classify files.
enum TrayItemKind: String, CaseIterable {
    case image
    case video
    case audio
    case document
    case archive
    case other

    init(uti: String) {
        guard let type = UTType(uti) else { self = .other; return }
        if type.conforms(to: .image) { self = .image }
        else if type.conforms(to: .movie) { self = .video }
        else if type.conforms(to: .audio) { self = .audio }
        else if type.conforms(to: .archive) { self = .archive }
        else if type.conforms(to: .pdf) || type.conforms(to: .text)
            || type.conforms(to: .spreadsheet) || type.conforms(to: .presentation) { self = .document }
        else { self = .other }
    }
}
