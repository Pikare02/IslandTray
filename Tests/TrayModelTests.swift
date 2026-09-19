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
}
