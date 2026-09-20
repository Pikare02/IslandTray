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
        model = TrayModel(store: store)
        suiteName = "TrayModelExportTests.\(UUID().uuidString)"
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
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

    func testAnItemAnotherAppTookLeavesTheTray() async throws {
        let item = try addItem()
        model.markExported(item.id)
        try await waitForMark(item.id)

        await model.flushExported(settings: settings(removeOnExport: true))

        XCTAssertTrue(model.items.isEmpty, "the tray is a cut buffer by default")
        XCTAssertTrue(try store.load().isEmpty)
    }

    func testAnItemNobodyTookStays() async throws {
        let taken = try addItem("taken.txt")
        let kept = try addItem("kept.txt")
        model.markExported(taken.id)
        try await waitForMark(taken.id)

        await model.flushExported(settings: settings(removeOnExport: true))

        XCTAssertEqual(model.items.map(\.id), [kept.id])
    }

    func testNothingIsRemovedWhenTheSettingIsOff() async throws {
        let item = try addItem()
        model.markExported(item.id)
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
        model.markExported(item.id)
        try await waitForMark(item.id)

        await model.flushExported(settings: settings(removeOnExport: false))
        XCTAssertTrue(model.exported.isEmpty)

        await model.flushExported(settings: settings(removeOnExport: true))
        XCTAssertEqual(model.items.map(\.id), [item.id])
    }
}
