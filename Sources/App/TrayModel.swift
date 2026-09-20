import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class TrayModel {
    var items: [TrayItem] = []
    var banner: String?

    /// The tray on disk. Defaulted to the shared singleton, which is what the
    /// app always uses; a parameter only so `start(migratingFrom:)` can be
    /// pinned against temporary containers instead of the real one.
    private let store: TrayStore
    /// Where `exported` lives between launches. A parameter so a test can use
    /// an isolated suite instead of the real user defaults.
    private let exports: ExportRegister

    init(store: TrayStore = .shared, exports: ExportRegister = ExportRegister()) {
        self.store = store
        self.exports = exports
        self.exported = exports.ids
    }

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
            items = try store.load()
            return true
        } catch {
            banner = L.s("banner.loadFailed", error.localizedDescription)
            return false
        }
    }

    /// Everything the tray's first appearance has to do, in the one order
    /// that works.
    ///
    /// The migration is awaited before the first `reload()` rather than fired
    /// off beside it: the two would otherwise race, and a reload that won
    /// would leave the migrated tray looking empty for the whole session --
    /// nothing reloads it again until the user drops or deletes something.
    ///
    /// The Live Activity needs the same treatment for the same reason, which
    /// is why this owns that decision too. `scenePhase`'s transition to
    /// `.active` has already fired `TrayActivityController.restart()` by now,
    /// and it read the container *before* the migration, so it found an empty
    /// tray and put no island up. Nothing else syncs the island this session.
    /// On an ordinary launch there is nothing to correct and syncing here
    /// would only duplicate `restart()`, so this is conditional.
    func start(migratingFrom oldRoot: URL = TrayContainer.localRoot) async {
        let migrated = await migrateIfNeeded(from: oldRoot)
        reload()
        if migrated { await syncActivity() }
        // Before the inbox, and here rather than only in the scene-phase
        // handler: `onChange` does not fire for the phase a launch starts in,
        // so a user whose app was killed while they were in the app they
        // handed a file to came back to a move that never finished.
        await flushExported()
        await importFromFilesFolder()
        // Even when nothing was taken in: the folder has to exist and be
        // non-empty before the user can find it to save into.
        DocumentsInbox.ensureVisible()
    }

    /// Takes in anything the user saved into the app's folder in the Files
    /// app since the last look. Runs on every foreground, so it returns
    /// without touching anything in the overwhelmingly common case of an
    /// empty inbox.
    ///
    /// Detached for the same reason as the migration and the drop path: this
    /// copies the user's files, and a large one would otherwise hold up the
    /// main actor for the whole copy.
    func importFromFilesFolder() async {
        let store = self.store
        let result = await Task.detached(priority: .userInitiated) {
            DocumentsInbox.sweep(store: store)
        }.value
        guard result.added > 0 || !result.failed.isEmpty else { return }

        let reloadSucceeded = reload()
        switch Self.ingestBanner(reloadSucceeded: reloadSucceeded, result: result) {
        case .keep:
            break
        case .set(let value):
            banner = value
        }
        await syncActivity()
    }

    /// Carries the tray over when the app gains an App Group container after
    /// a move to a paid developer account. Returns whether anything moved.
    ///
    /// No `TrayContainer.isShared` guard: without the App Group the old root
    /// *is* this store's root, which `migrateIfNeeded(from:)` already answers
    /// with 0 on its first line. One place decides this, not two.
    ///
    /// Detached because this copies the user's files: a large tray would
    /// otherwise copy on the main actor and hold up the first frame, the same
    /// reason `DropReceiver` keeps `add(copyingFrom:)` off it.
    ///
    /// A failure is deliberately silent. The old container is left exactly as
    /// it was, every item is still in one container or the other, and the next
    /// launch tries again; a banner here would only report a state the user
    /// cannot act on.
    private func migrateIfNeeded(from oldRoot: URL) async -> Bool {
        let store = self.store
        return await Task.detached(priority: .userInitiated) {
            ((try? store.migrateIfNeeded(from: oldRoot)) ?? 0) > 0
        }.value
    }

    /// Files held back because the tray already has exactly these bytes,
    /// waiting on the user's answer.
    ///
    /// Dragging a tray card and letting go over the tray itself hands the
    /// item straight back to us, so without this the same file piles up a
    /// copy per slip.
    var pendingDuplicates: [DropReceiver.Staged] = []

    var duplicatePrompt: String {
        guard pendingDuplicates.count == 1 else {
            return L.s("dup.many", pendingDuplicates.count)
        }
        return L.s("dup.one", pendingDuplicates[0].existing.name)
    }

    func ingest(_ providers: [NSItemProvider]) async {
        let result = await DropReceiver.ingest(providers: providers)
        pendingDuplicates += result.duplicates
        await returnToTray(result.duplicates)
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
            return .set(L.s("banner.ingestFailed", result.failed.joined(separator: ", ")))
        }
        if result.added > 0 {
            return .set(nil)
        }
        return .keep
    }

    /// Puts back items that were marked as handed out but turned out to have
    /// come straight back to us.
    ///
    /// Dropping a tray card onto the tray itself runs the whole handover: our
    /// own drop target asks the provider for the bytes, which is exactly the
    /// signal `markExported` listens for, so the item is recorded as given
    /// away -- and then the copy is declined and the user is left with
    /// nothing. Bytes that are already in the tray did not go anywhere.
    ///
    /// Called both when the duplicate is found and when the user answers:
    /// `markExported` lands on a later turn of the run loop than the drop, so
    /// the first call can run before the mark does, and the second is what
    /// makes it certain.
    func returnToTray(_ duplicates: [DropReceiver.Staged]) async {
        let returned = duplicates.map(\.existing.id).filter { exported.remove($0) != nil }
        guard !returned.isEmpty else { return }
        await syncActivity()
    }

    /// Adds the held-back files after all.
    func addPendingDuplicates() async {
        let staged = pendingDuplicates
        pendingDuplicates = []
        await returnToTray(staged)
        var failed: [String] = []
        var added = 0
        for item in staged {
            do {
                _ = try await DropReceiver.add(staged: item)
                added += 1
            } catch {
                failed.append(item.suggestedName ?? item.existing.name)
            }
        }
        let reloadSucceeded = reload()
        switch Self.ingestBanner(
            reloadSucceeded: reloadSucceeded,
            result: DropReceiver.Result(added: added, failed: failed)
        ) {
        case .keep:
            break
        case .set(let value):
            banner = value
        }
        await syncActivity()
    }

    /// Throws the held-back files away. Nothing was ever added, so there is
    /// nothing to reload -- only the staging files to clean up, and the item
    /// that came back to put back.
    func discardPendingDuplicates() async {
        let staged = pendingDuplicates
        pendingDuplicates = []
        staged.forEach(DropReceiver.discard(staged:))
        await returnToTray(staged)
    }

    /// Updates the Live Activity and surfaces any failure rather than
    /// swallowing it — the spec requires the reason to be visible.
    func syncActivity() async {
        await TrayActivityController.shared.sync(items: visible)
        if let error = await TrayActivityController.shared.lastError {
            banner = error
        }
    }

    // MARK: - Handing items to other apps

    /// Items whose bytes another app has taken, waiting to leave the tray.
    ///
    /// Removal is deferred rather than done at the handoff for one reason:
    /// the receiving app copies our file *after* the provider hands over the
    /// URL, and the tray may hold the user's only copy. Deleting while that
    /// copy is in flight destroys the file on both sides. The next time this
    /// app comes forward -- which is when the user has finished whatever they
    /// dragged the file into -- the copy is long done.
    ///
    /// `private(set)` rather than `private` so a test can see that a flush
    /// empties it even when nothing was removed. Every change is written
    /// through to `exports`, which is what survives the app being killed
    /// while the user is in the app they handed the file to.
    private(set) var exported: Set<UUID> = [] {
        didSet { exports.ids = exported }
    }

    /// The items the tray still shows.
    ///
    /// An item another app has taken drops out of this the moment it is taken,
    /// while `items` keeps it until the file is really gone. The island and
    /// the card list both read this, so handing a file to another app updates
    /// the island right then -- waiting for the deferred removal left it
    /// showing a count that no longer matched what the user had just done.
    var visible: [TrayItem] { items.filter { !exported.contains($0.id) } }

    /// Records that another app took `id`'s bytes, and takes it off the
    /// island immediately.
    ///
    /// `nonisolated` because `NSItemProvider` calls its load handler on
    /// whatever queue it likes; the hop to the main actor is this method's
    /// whole job.
    ///
    /// The setting is read here *as well as* in `flushExported`, and both
    /// must say yes. Nothing may disappear from the island in copy mode, and
    /// reading it again at the flush keeps the safe direction: a user who
    /// switches to copy mode in between gets their file kept, not deleted.
    /// `removeOnExport` is a parameter only so a test can set it without
    /// writing to the real user defaults.
    nonisolated func markExported(_ id: UUID, removeOnExport: Bool = TraySettings().removeOnExport) {
        guard removeOnExport else { return }
        Task { @MainActor in
            guard self.exported.insert(id).inserted else { return }
            await self.syncActivity()
            await self.finishExportWhileAway(id)
        }
    }

    /// Finishes the move without waiting for the user to come back.
    ///
    /// The handover happens while they are on their way into the other app,
    /// and this app is about to be suspended. `beginBackgroundTask` buys the
    /// ~30 seconds that need to pass first: the receiving app is still
    /// copying our file, and deleting it mid-copy is how a move loses the
    /// file it was moving. The wait is scaled to the size, since that is what
    /// the copy takes, and capped well inside the window iOS grants.
    ///
    /// Every guard that made this safe when it ran on the next foreground
    /// still holds -- the setting is re-read, the register is what decides
    /// what to remove, and a kill in the middle leaves the move to be
    /// finished at the next launch.
    /// Background time, taken while the app is still in front.
    ///
    /// This is the whole reason the move used to need the user to come back.
    /// Asking for it at the handover was too late: by then they are already in
    /// the other app and this one is being suspended, so the request -- and
    /// everything queued behind it -- simply did not run until the app was
    /// next resumed, which is exactly when the deletions were observed to
    /// happen. Taken at the *start* of the drag instead, the process is still
    /// running and the assertion is already held when the handover arrives.
    private var handover: UIBackgroundTaskIdentifier = .invalid

    /// Called as a drag leaves a card, on the main thread, with the app in
    /// front.
    func beginHandover() {
        guard handover == .invalid else { return }
        handover = UIApplication.shared.beginBackgroundTask(withName: "tray handover") { [weak self] in
            // iOS reclaiming the time. Ending it here is required; the move
            // is finished at the next launch from the register on disk.
            self?.endHandover()
        }
        DropDiagnostics.record(L.s(handover == .invalid ? "diag.handover.denied" : "diag.handover.granted"))
    }

    private func endHandover() {
        guard handover != .invalid else { return }
        UIApplication.shared.endBackgroundTask(handover)
        handover = .invalid
    }

    private func finishExportWhileAway(_ id: UUID) async {
        let bytes = items.first { $0.id == id }?.size ?? 0
        // 5 MB/s is a deliberately pessimistic copy rate; the floor matters
        // more than the slope, since most items are small and the cap keeps
        // the whole thing inside the background window.
        let grace = min(20, max(6, Double(bytes) / 5_000_000))
        // Every step is recorded. Whether this pass runs at all is the whole
        // question -- iOS can refuse the time, suspend us before the wait is
        // over, or kill the app outright -- and none of that is visible from
        // here or from a test.
        DropDiagnostics.record(L.s("diag.background.wait", Int(grace)))
        try? await Task.sleep(for: .seconds(grace))
        DropDiagnostics.record(L.s("diag.background.run", Self.stateName(UIApplication.shared.applicationState)))
        await flushExported()
        endHandover()
    }

    private static func stateName(_ state: UIApplication.State) -> String {
        switch state {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "?"
        }
    }

    /// Takes everything handed out since the last flush out of the tray, if
    /// the tray is configured as a cut buffer.
    ///
    /// The set is emptied either way, so turning the setting on later cannot
    /// retroactively delete items handed out while it was off.
    func flushExported(settings: TraySettings = TraySettings()) async {
        let ids = exported
        exported = []
        guard settings.removeOnExport else { return }
        for id in ids {
            // Re-read `items` each time rather than resolving the whole batch
            // up front: `remove(_:)` reloads, and an id that is already gone
            // must not be handed to the store again as a failed removal.
            // `items`, not `visible`: `exported` has just been emptied, but
            // these are exactly the ids it held.
            guard let item = items.first(where: { $0.id == id }) else { continue }
            let origin = item.origin
            await remove(item)
            // The tray copy goes first: whatever happens to the original, the
            // destination already has the file, so neither order can lose it.
            // Items with no origin -- most of them -- are simply copies, and
            // say nothing about it.
            guard let origin, origin.deletesOriginal else {
                DropDiagnostics.record(L.s("diag.export.copy", item.name))
                continue
            }
            switch OriginalRemover.remove(origin) {
            case .removed:
                DropDiagnostics.record(L.s("diag.export.deleted", item.name))
            case .failed(let reason):
                banner = L.s("banner.originalFailed", reason)
            }
        }
    }

    func remove(_ item: TrayItem) async {
        // remove(id:) returns what actually happened on disk. A partial failure
        // must not be reported to the user as a clean delete, nor as a no-op.
        do {
            let result = try store.remove(id: item.id)
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
    /// driving it through a real `TrayStore` and real disk I/O.
    static func removalBanner(for outcome: Result<TrayRemovalResult, Error>) -> String? {
        switch outcome {
        case .success(let result):
            return result.failed.isEmpty ? nil : L.s("banner.removePartial")
        case .failure(let error as TrayStoreError):
            if case .incompleteRemoval(let result, _) = error {
                return L.s("banner.removeCounts", result.removed.count, result.failed.count)
            }
            return L.s("banner.removeFailed")
        case .failure:
            return L.s("banner.removeFailed")
        }
    }
}
