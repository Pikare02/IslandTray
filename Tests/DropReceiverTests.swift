import UniformTypeIdentifiers
import XCTest
@testable import IslandTray

/// `preferredTypeIdentifier` and `duplicate(of:among:at:)` are covered here.
/// The rest of `ingest`
/// drives `loadFileRepresentation` and `TrayStore.shared`, which need a real
/// drag session and the app's real container respectively -- neither is
/// available in a test bundle. The type-identifier selection, though, is
/// ordinary Swift over `NSItemProvider.registeredTypeIdentifiers` and is
/// worth pinning on its own.
final class DropReceiverTests: XCTestCase {
    /// `registeredTypeIdentifiers` reports identifiers in registration order:
    /// registering `first` then `second` gives `candidates == [first, second]`.
    private func provider(registering identifiers: [String]) -> NSItemProvider {
        let provider = NSItemProvider()
        for identifier in identifiers {
            provider.registerDataRepresentation(forTypeIdentifier: identifier, visibility: .all) { completion in
                completion(Data(), nil)
                return nil
            }
        }
        return provider
    }

    func testPrefersTheConcreteTypeOverAContainerType() {
        // "public.data" is registered first (so it would win a plain
        // `.first`), but it's on the ignore list, so the concrete type behind
        // it must be the one picked.
        let item = provider(registering: ["public.data", "public.jpeg"])
        XCTAssertEqual(
            DropReceiver.preferredTypeIdentifier(for: item), "public.jpeg",
            "a container-ish identifier standing first must not win over a concrete type behind it"
        )
    }

    func testFallsBackToTheFirstCandidateWhenEveryOneIsIgnored() {
        // Both "public.item" and "public.content" are on the ignore list;
        // with nothing concrete offered, the first one registered still wins
        // over manufacturing a generic UTType.data identifier.
        let item = provider(registering: ["public.item", "public.content"])
        XCTAssertEqual(DropReceiver.preferredTypeIdentifier(for: item), "public.item")
    }

    func testFallsBackToUTTypeDataWhenNothingIsRegistered() {
        let empty = NSItemProvider()
        XCTAssertEqual(DropReceiver.preferredTypeIdentifier(for: empty), UTType.data.identifier)
    }

    // MARK: - Round 5, Important 2: the share sheet's summary

    func testACleanImportReportsOnlyWhatLanded() {
        XCTAssertEqual(
            DropReceiver.shareSheetMessage(for: .init(added: 2, failed: [])),
            "2 件をトレイに追加しました"
        )
    }

    /// The share sheet closes itself, so a count that hides the failures is
    /// the user's last word on files that never arrived. Same rule as
    /// `TrayRemovalResult`, `incompleteRemoval` and `ingestBanner`: a partial
    /// outcome is never reported as a clean one.
    func testAPartialImportReportsBothCounts() {
        XCTAssertEqual(
            DropReceiver.shareSheetMessage(for: .init(added: 2, failed: ["a.txt", "b.txt", "c.txt"])),
            "2 件をトレイに追加しました（3 件は追加できませんでした）"
        )
    }

    func testAnImportThatLandedNothingReportsAPlainFailure() {
        XCTAssertEqual(
            DropReceiver.shareSheetMessage(for: .init(added: 0, failed: ["a.txt"])),
            "追加できませんでした"
        )
    }

    /// The clipboard shortcut says where things went, not "to the tray".
    func testTheClipboardSaysClipboard() {
        XCTAssertEqual(
            DropReceiver.shareSheetMessage(for: .init(added: 1, failed: []), board: .clipboard),
            "クリップボードに追加されました"
        )
    }


    // MARK: - duplicate(of:among:at:)
    //
    // Dragging a tray card and letting go over the tray hands the item
    // straight back to us, so this is what stands between a slip of the
    // finger and a tray full of the same file.

    private var scratch: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("DropReceiverTests", isDirectory: true)
    }

    private func file(_ name: String, _ contents: String) throws -> URL {
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let url = scratch.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func item(name: String, size: Int) -> TrayItem {
        TrayItem(id: UUID(), name: name, uti: "public.plain-text", size: size, addedAt: Date(), ext: "txt")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    func testTheSameBytesAreRecognised() throws {
        let existing = try file("existing.txt", "hello")
        let dropped = try file("dropped.txt", "hello")
        XCTAssertEqual(
            DropReceiver.duplicate(
                of: dropped, among: [item(name: "existing.txt", size: 5)], at: { _ in existing }
            )?.name,
            "existing.txt"
        )
    }

    func testTheSameLengthIsNotEnough() throws {
        // Both five bytes: a size check alone would call these the same file.
        let existing = try file("existing.txt", "hello")
        let dropped = try file("dropped.txt", "world")
        XCTAssertNil(
            DropReceiver.duplicate(
                of: dropped, among: [item(name: "existing.txt", size: 5)], at: { _ in existing }
            )
        )
    }

    func testADifferentLengthIsNotEvenRead() throws {
        // The item's own recorded size rules it out, so `at:` is never called
        // -- which is what keeps a drop from reading every video in the tray.
        let dropped = try file("dropped.txt", "hello")
        XCTAssertNil(
            DropReceiver.duplicate(
                of: dropped,
                among: [item(name: "existing.txt", size: 9_999)],
                at: { _ in XCTFail("a size mismatch must not be hashed"); return URL(fileURLWithPath: "/dev/null") }
            )
        )
    }

    func testAnEmptyTrayHasNoDuplicates() throws {
        let dropped = try file("dropped.txt", "hello")
        XCTAssertNil(DropReceiver.duplicate(of: dropped, among: [], at: { _ in dropped }))
    }

    func testTheMatchIsFoundPastNonMatches() throws {
        let other = try file("other.txt", "world")
        let existing = try file("existing.txt", "hello")
        let dropped = try file("dropped.txt", "hello")
        let items = [item(name: "other.txt", size: 5), item(name: "existing.txt", size: 5)]
        XCTAssertEqual(
            DropReceiver.duplicate(
                of: dropped, among: items, at: { $0.name == "other.txt" ? other : existing }
            )?.name,
            "existing.txt"
        )
    }
}
