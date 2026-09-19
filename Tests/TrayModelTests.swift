import ActivityKit
import XCTest
@testable import IslandTray

/// Only `removalBanner(for:)` is covered here. The rest of `TrayModel` drives
/// `TrayStore.shared`/`ThumbnailService.shared`/`TrayActivityController.shared`
/// against real singletons and SwiftUI's `@Observable` machinery, none of
/// which is exercisable from a test bundle. The mapping from a removal
/// outcome to banner text is ordinary branching, pulled out specifically so
/// it can be pinned on its own.
@MainActor
final class TrayModelTests: XCTestCase {
    func testCleanSuccessClearsTheBanner() {
        let result = TrayRemovalResult(removed: [UUID()], failed: [])
        XCTAssertNil(TrayModel.removalBanner(for: .success(result)))
    }

    func testSuccessWithSurvivorsReportsAPartialFailure() {
        let result = TrayRemovalResult(removed: [UUID()], failed: [UUID()])
        XCTAssertEqual(
            TrayModel.removalBanner(for: .success(result)),
            "一部のファイルを削除できませんでした"
        )
    }

    func testIncompleteRemovalReportsBothCounts() {
        let result = TrayRemovalResult(removed: [UUID(), UUID()], failed: [UUID()])
        let error = TrayStoreError.incompleteRemoval(result, reason: "locked")
        XCTAssertEqual(
            TrayModel.removalBanner(for: .failure(error)),
            "2 件を削除しましたが、1 件は削除できませんでした"
        )
    }

    func testOtherTrayStoreErrorsReportAGenericFailure() {
        XCTAssertEqual(
            TrayModel.removalBanner(for: .failure(TrayStoreError.unsupportedSchemaVersion(9999))),
            "削除に失敗しました"
        )
    }

    func testANonTrayStoreErrorReportsAGenericFailure() {
        struct OtherError: Error {}
        XCTAssertEqual(
            TrayModel.removalBanner(for: .failure(OtherError())),
            "削除に失敗しました"
        )
    }

    // MARK: - ingestBanner(reloadSucceeded:result:)

    /// Pins the precedence from Critical Finding 2: a `reload()` failure
    /// must survive a subsequent partial or total ingest success. Without
    /// this guard, `ingest(_:)` used to overwrite that banner unconditionally
    /// whenever at least one provider succeeded or any failed, leaving the
    /// user with no explanation and a stale item list.

    func testAReloadFailureIsKeptEvenWhenEverythingWasImported() {
        let result = DropReceiver.Result(added: 1, failed: [])
        XCTAssertEqual(
            TrayModel.ingestBanner(reloadSucceeded: false, result: result),
            .keep
        )
    }

    func testAReloadFailureIsKeptEvenWhenSomeImportsFailed() {
        let result = DropReceiver.Result(added: 0, failed: ["photo.heic"])
        XCTAssertEqual(
            TrayModel.ingestBanner(reloadSucceeded: false, result: result),
            .keep
        )
    }

    func testAReloadFailureIsKeptOnAnEmptyDrop() {
        let result = DropReceiver.Result(added: 0, failed: [])
        XCTAssertEqual(
            TrayModel.ingestBanner(reloadSucceeded: false, result: result),
            .keep
        )
    }

    func testFailedImportsAreReportedAfterASuccessfulReload() {
        let result = DropReceiver.Result(added: 0, failed: ["photo.heic", "video.mov"])
        XCTAssertEqual(
            TrayModel.ingestBanner(reloadSucceeded: true, result: result),
            .set("取り込めませんでした: photo.heic, video.mov")
        )
    }

    func testACleanImportClearsTheBannerAfterASuccessfulReload() {
        let result = DropReceiver.Result(added: 2, failed: [])
        XCTAssertEqual(
            TrayModel.ingestBanner(reloadSucceeded: true, result: result),
            .set(nil)
        )
    }

    func testAnEmptyDropLeavesTheBannerUntouchedAfterASuccessfulReload() {
        let result = DropReceiver.Result(added: 0, failed: [])
        XCTAssertEqual(
            TrayModel.ingestBanner(reloadSucceeded: true, result: result),
            .keep
        )
    }

    // MARK: - Round 5, Important 2: start() and the Live Activity

    /// A temporary container, cleaned up with the test.
    private func makeStore(containing names: [String]) throws -> (TrayStore, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = TrayStore(root: root)
        try store.prepare()
        for name in names {
            _ = try store.add(data: Data("x".utf8), suggestedName: name, uti: "public.plain-text")
        }
        return (store, root)
    }

    /// Live activities this test host put up. `Activity.request` does succeed
    /// here (only its UI is missing), so whether `start()` reached
    /// `syncActivity()` is directly observable -- no seam, no banner text to
    /// depend on. Ended ones linger in the registry until dismissed, which is
    /// what `isLive` is for.
    private func liveActivityCount() -> Int {
        Activity<TrayActivityAttributes>.activities
            .filter { TrayActivityController.isLive($0.activityState) }
            .count
    }

    private func clearActivities() async {
        for activity in Activity<TrayActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    override func tearDown() async throws {
        await clearActivities()
    }

    func testAMigrationResyncsTheIslandOnTheLaunchThatMigrated() async throws {
        await clearActivities()
        let (_, oldRoot) = try makeStore(containing: ["a.txt"])
        let (store, _) = try makeStore(containing: [])
        let model = TrayModel(store: store)

        await model.start(migratingFrom: oldRoot)

        XCTAssertEqual(model.items.count, 1, "the migrated item is in the list")
        XCTAssertEqual(
            liveActivityCount(), 1,
            "scenePhase's restart() read the container before the migration and put no island "
                + "up; nothing else syncs it this session, so the launch that migrated has to"
        )
    }

    /// The other half: with nothing to migrate, the island is scenePhase's
    /// `restart()`'s business and syncing here would only duplicate it.
    func testALaunchWithNothingToMigrateLeavesTheIslandAlone() async throws {
        await clearActivities()
        let (_, oldRoot) = try makeStore(containing: [])
        let (store, _) = try makeStore(containing: ["a.txt"])
        let model = TrayModel(store: store)

        await model.start(migratingFrom: oldRoot)

        XCTAssertEqual(model.items.count, 1)
        XCTAssertEqual(liveActivityCount(), 0, "an ordinary launch must not sync the island twice")
    }
}
