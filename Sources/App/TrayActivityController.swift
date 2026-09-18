import ActivityKit
import Foundation

/// Owns the tray's Live Activity.
///
/// ActivityKit ends an activity after eight hours, so `restart()` exists to
/// reset that window. It runs when the app comes forward and from the
/// RefreshTrayActivityIntent that the Shortcuts automation triggers.
actor TrayActivityController {
    static let shared = TrayActivityController()

    /// Surfaced to the UI when starting fails, rather than swallowing the error.
    private(set) var lastError: String?

    // `static` (not an instance member) so this stays nonisolated: it only
    // reads ActivityKit's own static registry, never `self`. `Activity` is a
    // pre-Concurrency ActivityKit class with no `Sendable` conformance and
    // its own `update`/`end` run detached from the caller's isolation, so an
    // *instance* property here would tag the `Activity` it returns as part
    // of this actor's isolation region, and hand-off to those detached calls
    // would need `Activity` to be `Sendable` (it is not, and the escape
    // hatches for asserting that are banned in this project).
    private static var current: Activity<TrayActivityAttributes>? {
        Activity<TrayActivityAttributes>.activities.first
    }

    func sync(items: [TrayItem]) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = "ライブアクティビティが許可されていません"
            return
        }
        guard !items.isEmpty else {
            await end()
            return
        }

        // No encodedByteCount/countOnly degrade path here: `make(from:)` caps
        // `recent` at `maxPreviews` and only ever encodes a fixed-length UUID
        // `id` plus a `symbol` drawn from TrayItem's closed vocabulary, so its
        // output is provably always under `maxEncodedBytes`
        // (TrayContentStateTests.testStaysUnderFourKilobytesWithMaxPreviewsAndLongestSymbol
        // and .testExplicitFactoryPathsCannotExceedEncodedLimit pin this for the
        // worst case). A size guard here could never fire; see task-8-report.md
        // for the fuller rationale.
        let state = TrayContentState.make(from: items)

        if Self.current != nil {
            await update(state)
        } else {
            await start(state)
        }
    }

    func restart() async {
        let items = (try? TrayStore.shared.load()) ?? []
        await end()
        await sync(items: items)
    }

    // MARK: - Internals

    private func start(_ state: TrayContentState) async {
        do {
            _ = try Activity.request(
                attributes: TrayActivityAttributes(),
                content: .init(state: state, staleDate: nil)
            )
            lastError = nil
        } catch {
            lastError = "アイランドの表示を開始できません: \(error.localizedDescription)"
        }
    }

    private func update(_ state: TrayContentState) async {
        guard let current = Self.current else { return }
        await current.update(.init(state: state, staleDate: nil))
        lastError = nil
    }

    private func end() async {
        for activity in Activity<TrayActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
