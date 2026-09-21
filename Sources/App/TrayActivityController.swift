import ActivityKit
import Foundation
import OSLog

/// Owns the tray's Live Activity.
///
/// ActivityKit ends an activity after eight hours, so `restart()` exists to
/// reset that window. It runs when the app comes forward and from the
/// RefreshTrayActivityIntent that the Shortcuts automation triggers.
actor TrayActivityController {
    static let shared = TrayActivityController()

    /// `restart()`'s only caller besides the foreground scene-phase handler is
    /// `RefreshTrayActivityIntent`, which the system runs in a background-
    /// launched process with no UI and no one reading `lastError` back. The
    /// system log is the one record that outlives that process, so every
    /// failure branch below writes here too -- static, non-interpolated text
    /// only: never a filename, item name, or count from the user's tray.
    private static let logger = Logger(subsystem: "com.pikare.islandtray", category: "TrayActivityController")

    /// Why the island does not match the tray right now, or `nil` when it does.
    ///
    /// Nothing reads this yet: the view model that surfaces it arrives with
    /// the UI wiring task. Every assignment below happens before its writer's
    /// first suspension point, so an older call resuming later can never erase
    /// a newer one's error.
    private(set) var lastError: String?

    /// Which run of items the island is showing.
    ///
    /// Actor state rather than something read back off the activity: the
    /// activity's own state is what this produces, and reading the answer out
    /// of the thing being written is how two taps in quick succession end up
    /// moving one page.
    private var page = 0

    /// The activities this controller treats as its own.
    ///
    /// `Activity.activities` is not a list of visible activities: it also
    /// holds `.ended` and `.dismissed` entries, and the one ActivityKit ends
    /// at the eight-hour mark lingers there until it is dismissed. Updating
    /// such an activity is a silent no-op, so it must never be mistaken for
    /// the current one. `.stale` is included because that activity *is* still
    /// on screen and an update returns it to `.active`; starting a second one
    /// beside it would put two islands up.
    ///
    /// `nonisolated` because this reads ActivityKit's process-global registry
    /// and never touches `self`, which is also what lets the values it returns
    /// be handed to `Activity`'s own detached `update`/`end`. It asserts
    /// nothing about `Activity` being thread-safe -- ActivityKit owns that,
    /// and this actor never stores an `Activity` of its own.
    private nonisolated var liveActivities: [Activity<TrayActivityAttributes>] {
        Activity<TrayActivityAttributes>.activities.filter { Self.isLive($0.activityState) }
    }

    /// Whether an activity in that state is on screen and worth updating.
    ///
    /// Split out of `liveActivities` because it is the one decision here that
    /// does not need ActivityKit to be running, and so the only one a test can
    /// pin. Internal rather than private for that test.
    nonisolated static func isLive(_ state: ActivityState) -> Bool {
        state == .active || state == .stale
    }

    /// What `sync`/`restart` should do about the island, given the tray's
    /// current item count and the "show when empty" setting.
    ///
    /// Pulled out as a pure, ActivityKit-free function so it can be pinned by
    /// a test without a live Activity: everything else in this file needs
    /// ActivityKit actually running to observe.
    enum SyncDecision: Equatable {
        /// Start or keep an island up, even with `itemCount == 0`.
        case show
        /// End whatever is up; the tray is empty and the setting says hide.
        case end
    }

    nonisolated static func syncDecision(itemCount: Int, showActivityWhenEmpty: Bool) -> SyncDecision {
        itemCount > 0 || showActivityWhenEmpty ? .show : .end
    }

    func sync(items: [TrayItem]) async {
        // No os_log call here, unlike restart(): sync()'s only callers are
        // TrayModel.ingest(_:)/remove(_:), which read lastError back into
        // `banner` in the same foreground session, right after this returns.
        // That failure is never silent the way a background restart() is, so
        // logging it too would just be noise.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = L.s("banner.activityDenied")
            return
        }
        let decision = Self.syncDecision(
            itemCount: items.count,
            showActivityWhenEmpty: TraySettings().showActivityWhenEmpty
        )
        guard decision == .show else {
            await end()
            return
        }

        // No size guard around this call: the state now carries JPEG bytes and
        // so can genuinely exceed `maxEncodedBytes`, but `make(from:atlas:)`
        // is what enforces the budget -- it drops the atlas, then the
        // previews, and returns something that fits in every case
        // (TrayContentStateTests pins the worst case). A second guard here
        // would be unreachable, exactly as the pre-atlas one was.
        let state = await pagedState(for: items)

        // An update that lands nowhere falls through to `start` instead of
        // being dropped: whatever removed the activity (the eight-hour end, a
        // swipe-away, a concurrent `end()`) must not leave the tray full, the
        // island gone and nothing said about it. `start` can leave an
        // `.ended` sibling behind in the registry -- the eight-hour case is
        // exactly that -- so sweep the rest of the registry the same way
        // `restart()` does once the replacement exists.
        if await update(state) == false, let replacement = start(state) {
            await retireOthers(keeping: replacement)
        }
    }

    func restart() async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = L.s("banner.activityDenied")
            Self.logger.error("restart() aborted: Live Activities are disabled.")
            return
        }
        let items: [TrayItem]
        do {
            // TrayStore.load() can escalate through prepare()/rebuildFromDisk()
            // into a coordinated *write*, which blocks its caller on file I/O.
            // restart() now runs on every foreground (scenePhase -> .active),
            // so calling load() directly here would block this actor's serial
            // executor -- and every other call queued behind it, including
            // sync(items:) from a drop in progress -- on disk I/O. Task.detached
            // hops the synchronous call onto the cooperative thread pool; this
            // method only resumes back onto the actor once it has a result.
            //
            // Deliberately `Task.detached`, not a plain `Task { }`: a plain
            // task created from inside an actor method inherits that actor's
            // isolation, so `TrayStore.shared.load()` would still run on
            // this actor's executor and block it exactly as before --
            // `Task.detached` is what actually gets off the actor. The price
            // is losing task-local values (unused anywhere in this codebase
            // today) and this task's link to its caller's cancellation --
            // the `Task { await restart() }` in IslandTrayApp's
            // `onChange(of: scenePhase)` is never itself cancelled, so this
            // is inert today, but do not "simplify" this back to a plain
            // `Task { }`; that reintroduces the actor-blocking bug this fix
            // exists for.
            items = try await loadTray()
        } catch {
            // TrayStore.load() throws precisely so a failed read is not read
            // back as an empty tray. Ending the island over a transient
            // metadata failure is the one thing that must not happen here, so
            // leave whatever is up alone and report instead.
            lastError = L.s("banner.loadFailed", error.localizedDescription)
            Self.logger.error("restart() aborted: TrayStore.load() threw.")
            return
        }
        let decision = Self.syncDecision(
            itemCount: items.count,
            showActivityWhenEmpty: TraySettings().showActivityWhenEmpty
        )
        guard decision == .show else {
            await end()
            return
        }

        // Replace, never destroy-then-hope. `Activity.request` throws, and this
        // method's documented caller is a background Shortcuts automation --
        // exactly where ActivityKit is most likely to refuse. Requesting first
        // means a failure leaves the working island untouched; the old ones go
        // only once the replacement exists, so the success path still ends with
        // a single activity.
        let state = await pagedState(for: items)
        guard let replacement = start(state) else { return }
        await retireOthers(keeping: replacement)
    }

    /// Brings the island up to date with what is on disk, updating the
    /// activity that is up rather than replacing it.
    ///
    /// For a shortcut that just wrote to the store. `restart()` would request
    /// a new activity, and ActivityKit refuses that while another app is in
    /// front -- which is where a shortcut runs from -- so the island kept its
    /// old count until the app was next opened. An update is allowed from
    /// the background; `sync` still falls back to starting one when nothing
    /// is up.
    func syncFromStore() async {
        guard let items = try? await loadTray() else {
            Self.logger.error("syncFromStore() aborted: TrayStore.load() threw.")
            return
        }
        await sync(items: items)
    }

    /// What the island shows: the tray's items, read off the actor. See
    /// `restart()` for why the load must be detached. The clipboard board
    /// has its own screen and does not belong in the island's count.
    private func loadTray() async throws -> [TrayItem] {
        try await Task.detached(priority: .userInitiated) {
            try TrayStore.shared.load()
        }.value.filter { $0.boardOrTray == .tray }
    }

    /// Moves the island's strip by `delta` pages and updates what is on
    /// screen. Called from the buttons in the expanded island.
    func turnPage(by delta: Int) async {
        let tray: [TrayItem]
        do {
            tray = try await loadTray()
        } catch {
            Self.logger.error("turnPage() aborted: TrayStore.load() threw.")
            return
        }
        page = TrayContentState.clampedPage(page + delta, count: tray.count)
        _ = await update(await pagedState(for: tray))
    }

    /// The state for the page currently being shown, with an atlas built from
    /// exactly the items on it.
    ///
    /// Both halves go through `TrayContentState.items(_:onPage:)` so the
    /// picture and the labels can never describe different items.
    private func pagedState(for items: [TrayItem]) async -> TrayContentState {
        page = TrayContentState.clampedPage(page, count: items.count)
        let onPage = TrayContentState.items(items, onPage: page)
        return TrayContentState.make(
            from: items,
            atlas: await ThumbnailService.shared.islandAtlas(for: onPage),
            page: page
        )
    }

    // MARK: - Internals

    /// The new activity's id, or `nil` when the request failed.
    ///
    /// Not `async`: `Activity.request` is synchronous, which is what makes the
    /// `lastError` writes here race-free without further care.
    @discardableResult
    private func start(_ state: TrayContentState) -> String? {
        do {
            let activity = try Activity.request(
                attributes: TrayActivityAttributes(),
                content: .init(state: state, staleDate: nil)
            )
            lastError = nil
            return activity.id
        } catch {
            lastError = L.s("banner.activityFailed", error.localizedDescription)
            // Shared by restart() and sync()'s self-recovery path -- either
            // way, Activity.request refused a request that should have
            // succeeded, and this is worth a durable record regardless of
            // which caller hit it.
            Self.logger.error("Activity.request failed.")
            return nil
        }
    }

    /// `false` when there was nothing live to update, so the caller can start one.
    ///
    /// Updates every live activity rather than an arbitrary `first` of an
    /// unordered registry, so an update can no longer land on one the user
    /// cannot see. This is a narrower set than `retireOthers` sweeps: that one
    /// spans the whole registry on purpose, to also catch `.ended` entries
    /// this method must never touch.
    private func update(_ state: TrayContentState) async -> Bool {
        let activities = liveActivities
        guard !activities.isEmpty else { return false }
        // Cleared here, not after the loop: `Activity.update` suspends, and on
        // resume this assignment would wipe an error another task raised in the
        // meantime. `update` cannot report failure anyway, so "we reached a
        // live activity" is the most this can honestly mean.
        lastError = nil
        for activity in activities {
            await activity.update(.init(state: state, staleDate: nil))
        }
        return true
    }

    private func end() async {
        // Cleared before the first suspension point, for the reason given in
        // `update`. With no island wanted there is no failure left to report.
        lastError = nil
        // The whole registry, not just `liveActivities`: an `.ended` activity
        // is still on screen until it is dismissed, and ending it with
        // `.immediate` is what takes it off.
        for activity in Activity<TrayActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Ends every other activity in the registry once `keeping` exists.
    ///
    /// Iterates the whole registry, exactly like `end()` does, not
    /// `liveActivities`: an `.ended` activity -- the one ActivityKit produces
    /// at the eight-hour mark -- stays on screen until it is dismissed, and
    /// `.immediate` is what takes it off. `restart()` and `sync()`'s
    /// self-recovery path both call `start` after finding nothing live to
    /// update, so both must sweep the whole registry afterward, or the old
    /// `.ended` card sits on the Lock Screen next to the new one for up to
    /// four hours.
    private func retireOthers(keeping id: String) async {
        for activity in Activity<TrayActivityAttributes>.activities where activity.id != id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
