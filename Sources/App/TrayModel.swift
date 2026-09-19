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
    func reload() {
        do {
            items = try TrayStore.shared.load()
        } catch {
            banner = "トレイを読み込めません: \(error.localizedDescription)"
        }
    }

    func ingest(_ providers: [NSItemProvider]) async {
        let result = await DropReceiver.ingest(providers: providers)
        reload()

        if !result.failed.isEmpty {
            banner = "取り込めませんでした: \(result.failed.joined(separator: ", "))"
        } else if result.added > 0 {
            banner = nil
        }
        await syncActivity()
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
