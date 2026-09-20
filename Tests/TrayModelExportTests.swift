import XCTest
@testable import IslandTray

/// The one path in this app that deletes a file the user did not ask to
/// delete. The tray can hold their only copy, so all three states are pinned:
/// handed out with the setting on, handed out with it off, and never handed
/// out at all.
@MainActor
final class TrayModelExportTests: XCTestCase {
    private var root: URL!
    private var store: TrayStore!
    private var model: TrayModel!
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    override func setUp() async throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = TrayStore(root: root)
        try store.prepare()
        suiteName = "TrayModelExportTests.\(UUID().uuidString)"
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        model = TrayModel(store: store, exports: ExportRegister(defaults: userDefaults))
    }

    override func tearDown() async throws {
        userDefaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }

    private func addItem(_ name: String = "a.txt") throws -> TrayItem {
        let item = try store.add(data: Data("x".utf8), suggestedName: name, uti: "public.plain-text")
        model.reload()
        return item
    }

    /// `markExported` is `nonisolated` and hops to the main actor, so the
    /// insert lands on a later turn of the run loop than the call.
    private func waitForMark(_ id: UUID) async throws {
        for _ in 0..<1000 where !model.exported.contains(id) {
            await Task.yield()
        }
        XCTAssertTrue(model.exported.contains(id), "markExported never landed")
    }

    private func settings(removeOnExport: Bool) -> TraySettings {
        let settings = TraySettings(defaults: userDefaults)
        settings.removeOnExport = removeOnExport
        return settings
    }

    func testAnItemLeavesTheIslandTheMomentItIsTaken() async throws {
        // Not at the next foreground, which is when the file itself goes: the
        // user hands a photo to another app and looks straight at the island.
        let item = try addItem()
        model.markExported(item.id, removeOnExport: true)
        try await waitForMark(item.id)

        XCTAssertEqual(model.visible, [], "the island reads `visible`")
        XCTAssertEqual(model.items.map(\.id), [item.id], "the file is still there until the flush")
    }

    func testCopyModeTakesNothingOffTheIsland() async throws {
        let item = try addItem()
        model.markExported(item.id, removeOnExport: false)
        // Nothing to wait for -- the call returns without recording anything.
        await Task.yield()

        XCTAssertTrue(model.exported.isEmpty)
        XCTAssertEqual(model.visible.map(\.id), [item.id])
    }

    func testAnItemAnotherAppTookLeavesTheTray() async throws {
        let item = try addItem()
        model.markExported(item.id, removeOnExport: true)
        try await waitForMark(item.id)

        await model.flushExported(settings: settings(removeOnExport: true))

        XCTAssertTrue(model.items.isEmpty, "the tray is a cut buffer by default")
        XCTAssertTrue(try store.load().isEmpty)
    }

    func testAnItemNobodyTookStays() async throws {
        let taken = try addItem("taken.txt")
        let kept = try addItem("kept.txt")
        model.markExported(taken.id, removeOnExport: true)
        try await waitForMark(taken.id)

        await model.flushExported(settings: settings(removeOnExport: true))

        XCTAssertEqual(model.items.map(\.id), [kept.id])
    }

    func testNothingIsRemovedWhenTheSettingIsOff() async throws {
        let item = try addItem()
        model.markExported(item.id, removeOnExport: true)
        try await waitForMark(item.id)

        await model.flushExported(settings: settings(removeOnExport: false))

        XCTAssertEqual(model.items.map(\.id), [item.id])
        XCTAssertEqual(try store.load().count, 1)
    }

    func testTurningTheSettingOnLaterDoesNotDeleteWhatWasHandedOutBefore() async throws {
        // The set is emptied by every flush, on or off. Without that, a user
        // who shares ten files with the setting off and then turns it on
        // loses all ten the next time the app comes forward.
        let item = try addItem()
        model.markExported(item.id, removeOnExport: true)
        try await waitForMark(item.id)

        await model.flushExported(settings: settings(removeOnExport: false))
        XCTAssertTrue(model.exported.isEmpty)

        await model.flushExported(settings: settings(removeOnExport: true))
        XCTAssertEqual(model.items.map(\.id), [item.id])
    }


    // MARK: - A card dropped back onto the tray

    private func staged(duplicateOf item: TrayItem) throws -> DropReceiver.Staged {
        let payload = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: payload)
        return DropReceiver.Staged(
            payload: payload, suggestedName: item.name, uti: "public.plain-text", existing: item
        )
    }

    func testDecliningACardThatCameStraightBackKeepsIt() async throws {
        // Dragging a card and letting go over the tray runs the whole
        // handover -- our own drop target asks the provider for the bytes,
        // which is what marks the item as given away. Declining the copy then
        // left the user with neither: the copy refused and the original
        // already on its way out.
        let item = try addItem()
        model.markExported(item.id, removeOnExport: true)
        try await waitForMark(item.id)
        model.pendingDuplicates = [try staged(duplicateOf: item)]

        await model.discardPendingDuplicates()

        XCTAssertTrue(model.exported.isEmpty, "it never went anywhere")
        XCTAssertEqual(model.visible.map(\.id), [item.id])
        await model.flushExported(settings: settings(removeOnExport: true))
        XCTAssertEqual(try store.load().map(\.id), [item.id], "and the file is still on disk")
    }

    func testAcceptingACardThatCameStraightBackAlsoKeepsTheOriginal() async throws {
        let item = try addItem()
        model.markExported(item.id, removeOnExport: true)
        try await waitForMark(item.id)
        model.pendingDuplicates = [try staged(duplicateOf: item)]

        await model.addPendingDuplicates()

        XCTAssertTrue(model.exported.isEmpty)
        XCTAssertTrue(model.visible.contains { $0.id == item.id })
    }


    func testAHandoverSurvivesTheAppBeingKilled() async throws {
        // Handing a file over takes the user into the other app, and a
        // backgrounded sideloaded app is routinely killed before they come
        // back. Held in memory, the record died with it: the item was back in
        // the tray and the original never touched.
        let item = try addItem()
        model.markExported(item.id, removeOnExport: true)
        try await waitForMark(item.id)

        // A second model over the same register is what a relaunch looks like.
        let relaunched = TrayModel(store: store, exports: ExportRegister(defaults: userDefaults))
        relaunched.reload()

        XCTAssertEqual(relaunched.exported, [item.id])
        XCTAssertTrue(relaunched.visible.isEmpty)
        await relaunched.flushExported(settings: settings(removeOnExport: true))
        XCTAssertTrue(try store.load().isEmpty, "the move finishes on the next launch")
    }

    func testAFlushClearsWhatIsKeptOnDisk() async throws {
        let item = try addItem()
        model.markExported(item.id, removeOnExport: true)
        try await waitForMark(item.id)

        await model.flushExported(settings: settings(removeOnExport: false))

        XCTAssertTrue(
            ExportRegister(defaults: userDefaults).ids.isEmpty,
            "or every later launch would try the same removal again"
        )
    }
}
