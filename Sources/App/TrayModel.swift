import Foundation
import Observation

@MainActor
@Observable
final class TrayModel {
    var items: [TrayItem] = []
    var banner: String?

    /// `load()` deliberately distinguishes a failed read from an empty tray
    /// (see TrayStore), so a thrown read must never be swallowed into `[]`
    /// here. A failure leaves `items` as it was and reports through `banner`
    /// instead of quietly showing an empty tray.
    ///
    /// Returns whether the read succeeded, so a caller that is about to make
    /// its own decision about `banner` (namely `ingest(_:)`) can tell "a read
    /// failure was just posted" apart from "nothing happened" and avoid
    /// overwriting it.
    @discardableResult
    func reload() -> Bool {
        do {
            items = try TrayStore.shared.load()
            return true
        } catch {
            banner = "トレイを読み込めません: \(error.localizedDescription)"
            return false
        }
    }

    func ingest(_ providers: [NSItemProvider]) async {
        let result = await DropReceiver.ingest(providers: providers)
        let reloadSucceeded = reload()

        switch Self.ingestBanner(reloadSucceeded: reloadSucceeded, result: result) {
        case .keep:
            break
        case .set(let value):
            banner = value
        }
        await syncActivity()
    }

    /// What `ingest(_:)` should do to `banner` after a drop, given whether
    /// the `reload()` that just ran succeeded and what `DropReceiver`
    /// reported.
    enum BannerUpdate: Equatable {
        /// Leave `banner` exactly as it is.
        case keep
        /// Overwrite `banner`, `nil` meaning "clear it".
        case set(String?)
    }

    /// Precedence, highest first:
    /// 1. `reload()` just failed -- its "トレイを読み込めません: …" message must
    ///    survive. This is the whole point of Critical Finding 2: an ingest
    ///    that partially or fully succeeded must never paper over a read that
    ///    just failed, or the user sees no banner at all while `items` is
    ///    silently stale.
    /// 2. Otherwise, any provider that failed to import is reported.
    /// 3. Otherwise, a clean import (`added > 0`) clears the banner.
    /// 4. An empty drop (`added == 0`, nothing failed) leaves `banner`
    ///    untouched -- unspecified by the brief, kept as-is.
    ///
    /// Pulled out as a pure static function, mirroring `removalBanner(for:)`,
    /// so this precedence can be pinned by a unit test without driving it
    /// through `DropReceiver`'s real `NSItemProvider`/`TrayStore.shared`
    /// machinery.
    static func ingestBanner(reloadSucceeded: Bool, result: DropReceiver.Result) -> BannerUpdate {
        guard reloadSucceeded else { return .keep }
        if !result.failed.isEmpty {
            return .set("取り込めませんでした: \(result.failed.joined(separator: ", "))")
        }
        if result.added > 0 {
            return .set(nil)
        }
        return .keep
    }

    /// Updates the Live Activity and surfaces any failure rather than
    /// swallowing it — the spec requires the reason to be visible.
    func syncActivity() async {
        await TrayActivityController.shared.sync(items: items)
        if let error = await TrayActivityController.shared.lastError {
            banner = error
        }
    }

    func remove(_ item: TrayItem) async {
        // remove(id:) returns what actually happened on disk. A partial failure
        // must not be reported to the user as a clean delete, nor as a no-op.
        do {
            let result = try TrayStore.shared.remove(id: item.id)
            banner = Self.removalBanner(for: .success(result))
        } catch {
            banner = Self.removalBanner(for: .failure(error))
        }
        await ThumbnailService.shared.removeCache(for: item)
        reload()
        await syncActivity()
    }

    /// Maps what a removal attempt actually did on disk to the banner text.
    ///
    /// Pulled out as a pure, static function (rather than inlined in
    /// `remove(_:)`) so this branching can be pinned by a unit test without
    /// driving it through the real `TrayStore.shared` singleton, which has no
    /// injection seam and would otherwise force the test onto real disk I/O.
    static func removalBanner(for outcome: Result<TrayRemovalResult, Error>) -> String? {
        switch outcome {
        case .success(let result):
            return result.failed.isEmpty ? nil : "一部のファイルを削除できませんでした"
        case .failure(let error as TrayStoreError):
            if case .incompleteRemoval(let result, _) = error {
                return "\(result.removed.count) 件を削除しましたが、\(result.failed.count) 件は削除できませんでした"
            }
            return "削除に失敗しました"
        case .failure:
            return "削除に失敗しました"
        }
    }
}
