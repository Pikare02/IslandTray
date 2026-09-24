import Foundation
import Observation

/// What one sync pass has to do, decided from ids alone.
///
/// Pure so the rules that can destroy files are pinned by a test rather than
/// by a device pair. Every doubtful case resolves toward keeping a file: a
/// duplicate can be deleted, an absence cannot be undone.
struct CloudPlan: Equatable {
    /// Here, not in the folder: put it there.
    var upload: Set<UUID> = []
    /// Deleted on another device: delete it here too.
    var removeLocal: Set<UUID> = []
    /// Deleted here since the last pass (or already tombstoned): mark it
    /// deleted in the folder and clear what is left of it.
    var bury: Set<UUID> = []
    /// In the folder, never here: listed with a cloud until downloaded.
    var cloudOnly: Set<UUID> = []

    /// - Parameters:
    ///   - local: ids in this device's store.
    ///   - remote: ids with an entry in the folder, downloaded or not.
    ///   - tombstones: ids some device deleted.
    ///   - synced: ids that were on both sides after the last pass -- the
    ///     only way to tell "deleted here" from "new there".
    static func make(local: Set<UUID>, remote: Set<UUID>, tombstones: Set<UUID>, synced: Set<UUID>) -> CloudPlan {
        var plan = CloudPlan()
        plan.removeLocal = local.intersection(tombstones)
        // Missing from the folder while still here is re-uploaded even if it
        // was synced before: an entry deleted by hand in Files carries no
        // tombstone, and treating it as a delete would destroy the last copy.
        plan.upload = local.subtracting(tombstones).subtracting(remote)
        for id in remote.subtracting(local) {
            if tombstones.contains(id) || synced.contains(id) {
                plan.bury.insert(id)
            } else {
                plan.cloudOnly.insert(id)
            }
        }
        return plan
    }
}

/// The folder every device's tray mirrors into -- normally one in iCloud
/// Drive, picked in Files, so it needs no iCloud entitlement and works the
/// same on a free account.
///
/// One file per item rather than one list: `Meta/<id>.json` is written once,
/// by the device that uploaded it, and a deletion is a new file in
/// `Deleted/`. No two devices ever write the same file, so iCloud never has
/// a conflict to resolve. Payload before entry on upload, tombstone before
/// anything is removed.
struct CloudFolder: Sendable {
    let root: URL

    var itemsDirectory: URL { root.appendingPathComponent("Items", isDirectory: true) }
    var metaDirectory: URL { root.appendingPathComponent("Meta", isDirectory: true) }
    var deletedDirectory: URL { root.appendingPathComponent("Deleted", isDirectory: true) }

    struct Listing {
        /// Every id with an entry, including ones iCloud has not brought down
        /// yet -- those still count as present, or they would be re-uploaded.
        var ids: Set<UUID> = []
        var items: [UUID: TrayItem] = [:]
        var tombstones: Set<UUID> = []
        /// Entries that were still `.icloud` placeholders this pass, so their
        /// download was only just asked for and cannot be read until a later
        /// one. A non-empty set means "come back soon" -- see `settling`.
        var pendingDownloads: Set<UUID> = []
    }

    func prepare() throws {
        for dir in [itemsDirectory, metaDirectory, deletedDirectory] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    func list() throws -> Listing {
        try prepare()
        var listing = Listing()
        for name in try names(in: metaDirectory) {
            if let real = Self.placeholderTarget(name) {
                // Not on this device yet. Asked for, and read next pass.
                guard let id = Self.id(fromMeta: real) else { continue }
                listing.ids.insert(id)
                listing.pendingDownloads.insert(id)
                try? FileManager.default.startDownloadingUbiquitousItem(at: metaDirectory.appendingPathComponent(real))
                continue
            }
            guard let id = Self.id(fromMeta: name) else { continue }
            listing.ids.insert(id)
            let url = metaDirectory.appendingPathComponent(name)
            if let data = try? Self.coordinatedRead(url),
               let item = try? JSONDecoder.tray.decode(TrayItem.self, from: data),
               Self.isSafe(item, id: id) {
                listing.items[id] = item
            }
        }
        for name in try names(in: deletedDirectory) {
            if let id = UUID(uuidString: Self.placeholderTarget(name) ?? name) { listing.tombstones.insert(id) }
        }
        return listing
    }

    func upload(_ item: TrayItem, from payload: URL) throws {
        try prepare()
        var item = item
        item.origin = nil
        let destination = item.fileURL(in: itemsDirectory)
        try Self.coordinatedWrite(destination, .forReplacing) { url in
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            try TrayStore.coordinatedCopy(from: payload, to: url)
        }
        let data = try JSONEncoder.tray.encode(item)
        try Self.coordinatedWrite(metaURL(item.id), .forReplacing) { try data.write(to: $0, options: .atomic) }
    }

    /// Marks `id` deleted everywhere, then clears its entry and payload.
    /// `ext` is nil when the entry was never readable here; the payload is
    /// then found by its id.
    func bury(_ id: UUID, ext: String?) throws {
        let tombstone = deletedDirectory.appendingPathComponent(id.uuidString)
        if !FileManager.default.fileExists(atPath: tombstone.path) {
            try Self.coordinatedWrite(tombstone, []) { try Data().write(to: $0) }
        }
        try? Self.coordinatedWrite(metaURL(id), .forDeleting) { try FileManager.default.removeItem(at: $0) }
        let payloads = ext.map { [itemsDirectory.appendingPathComponent($0.isEmpty ? id.uuidString : "\(id.uuidString).\($0)")] }
            ?? ((try? names(in: itemsDirectory)) ?? [])
                .filter { $0.hasPrefix(id.uuidString) || $0.hasPrefix(".\(id.uuidString)") }
                .map { itemsDirectory.appendingPathComponent($0) }
        for url in payloads where FileManager.default.fileExists(atPath: url.path) {
            try? Self.coordinatedWrite(url, .forDeleting) { try FileManager.default.removeItem(at: $0) }
        }
    }

    func payloadURL(for item: TrayItem) -> URL { item.fileURL(in: itemsDirectory) }

    /// False only while iCloud still has to send it. A folder outside iCloud
    /// has nothing to wait for.
    func isUploaded(_ item: TrayItem) -> Bool {
        let values = try? payloadURL(for: item).resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemIsUploadedKey])
        guard values?.isUbiquitousItem == true else { return true }
        return values?.ubiquitousItemIsUploaded ?? true
    }

    // MARK: - Internals

    private func metaURL(_ id: UUID) -> URL { metaDirectory.appendingPathComponent("\(id.uuidString).json") }

    /// A coordinated look at the directory, which is what makes iCloud
    /// refresh a listing it has not fetched in a while.
    private func names(in directory: URL) throws -> [String] {
        var result: [String] = []
        var failure: Error?
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(
            readingItemAt: directory, options: .immediatelyAvailableMetadataOnly, error: &coordinatorError
        ) { url in
            do { result = try FileManager.default.contentsOfDirectory(atPath: url.path) } catch { failure = error }
        }
        if let error = coordinatorError ?? failure { throw error }
        return result
    }

    /// `.X.icloud` is how iCloud lists a file it has not downloaded.
    static func placeholderTarget(_ name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return nil }
        return String(name.dropFirst().dropLast(".icloud".count))
    }

    private static func id(fromMeta name: String) -> UUID? {
        guard name.hasSuffix(".json") else { return nil }
        return UUID(uuidString: String(name.dropLast(".json".count)))
    }

    /// The entry comes from outside this app. Its extension becomes part of a
    /// path, so anything but letters and digits is refused, and an entry must
    /// describe the file it is named after.
    static func isSafe(_ item: TrayItem, id: UUID) -> Bool {
        item.id == id && item.ext.count <= 16 && item.ext.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    private static func coordinatedRead(_ url: URL) throws -> Data {
        var data: Data?
        var failure: Error?
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { url in
            do { data = try Data(contentsOf: url) } catch { failure = error }
        }
        if let error = coordinatorError ?? failure { throw error }
        return data ?? Data()
    }

    private static func coordinatedWrite(
        _ url: URL, _ options: NSFileCoordinator.WritingOptions, _ body: (URL) throws -> Void
    ) throws {
        var failure: Error?
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordinatorError) { url in
            do { try body(url) } catch { failure = error }
        }
        if let error = coordinatorError ?? failure { throw error }
    }
}

/// Keeps this device's tray and the sync folder in step, and holds what the
/// screens show about it.
@MainActor
@Observable
final class CloudSync {
    /// Items in the folder that are not on this device.
    private(set) var cloudOnly: [TrayItem] = []
    private(set) var downloading: Set<UUID> = []
    private(set) var isSyncing = false
    /// The last pass left a download or upload in flight, so the foreground
    /// poll should come back in seconds rather than a full interval.
    private(set) var settling = false
    /// Steps done and to do in the pass that is running.
    private(set) var done = 0
    private(set) var total = 0
    private(set) var pendingUploads = 0
    private(set) var lastSync: Date?
    private(set) var lastError: String?
    /// Newest first, capped: what the details screen shows.
    private(set) var log: [String] = []
    private(set) var folderName: String?
    /// The sync switch. Off is the local mode: nothing is read from or
    /// written to the folder, and its items are not listed. The folder stays
    /// remembered, so switching back on carries on where it left off.
    var isOn: Bool {
        didSet {
            TraySettings().cloudSyncEnabled = isOn
            if !isOn { cloudOnly = [] }
        }
    }

    private let store: TrayStore
    private let defaults: UserDefaults
    private var rerun = false

    init(store: TrayStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        isOn = TraySettings().cloudSyncEnabled
        folderName = resolveFolder()?.lastPathComponent
    }

    var isEnabled: Bool { isOn && folderName != nil }

    func isCloudOnly(_ id: UUID) -> Bool { cloudOnly.contains { $0.id == id } }

    // MARK: - Folder

    private enum Keys {
        static let bookmark = "cloud.bookmark"
    }

    /// Starts syncing with `url`, as handed over by the folder picker.
    func choose(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let bookmark = try? url.bookmarkData() else {
            lastError = L.s("cloud.error.folder")
            return
        }
        defaults.set(bookmark, forKey: Keys.bookmark)
        // What was in step with another folder says nothing about this one,
        // and read against it would look like a pile of deletions.
        synced = []
        cloudOnly = []
        lastError = nil
        folderName = url.lastPathComponent
    }

    /// Stops syncing. Nothing is deleted, here or in the folder.
    func turnOff() {
        defaults.removeObject(forKey: Keys.bookmark)
        synced = []
        cloudOnly = []
        folderName = nil
        lastError = nil
    }

    private var synced: Set<UUID> {
        get {
            guard let data = try? Data(contentsOf: store.cloudStateURL),
                  let ids = try? JSONDecoder().decode([UUID].self, from: data) else { return [] }
            return Set(ids)
        }
        set { try? JSONEncoder().encode(Array(newValue)).write(to: store.cloudStateURL, options: .atomic) }
    }

    private func resolveFolder() -> URL? {
        guard let bookmark = defaults.data(forKey: Keys.bookmark) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale) else { return nil }
        if isStale, let fresh = try? url.bookmarkData() { defaults.set(fresh, forKey: Keys.bookmark) }
        return url
    }

    /// Runs `body` with the folder open. nil when there is no folder, or it
    /// can no longer be reached.
    private func withFolder<T: Sendable>(_ body: @escaping @Sendable (CloudFolder) async throws -> T) async throws -> T? {
        guard let url = resolveFolder() else { return nil }
        return try await Task.detached(priority: .utility) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return try await body(CloudFolder(root: url))
        }.value
    }

    // MARK: - Syncing

    /// One pass. Returns whether this device's store changed, so the caller
    /// knows to reload. Calls that arrive mid-pass fold into one more pass.
    @discardableResult
    func sync() async -> Bool {
        guard isEnabled else { return false }
        guard !isSyncing else { rerun = true; return false }
        isSyncing = true
        defer {
            isSyncing = false
            done = 0
            total = 0
        }
        var changed = false
        repeat {
            rerun = false
            changed = await pass() || changed
        } while rerun
        return changed
    }

    private struct Outcome: Sendable {
        var changed = false
        var cloudOnly: [TrayItem] = []
        var synced: Set<UUID> = []
        var pendingUploads = 0
        /// This pass left something mid-flight -- a download just asked for, or
        /// an upload iCloud has not sent yet -- so the poll should look again
        /// in seconds rather than waiting a full idle interval.
        var settling = false
        var lines: [String] = []
    }

    private func pass() async -> Bool {
        let synced = self.synced
        let store = self.store
        done = 0
        total = 0
        do {
            guard let outcome = try await withFolder({ folder in
                try await Self.run(folder: folder, store: store, synced: synced) { done, total in
                    await MainActor.run { self.done = done; self.total = total }
                }
            }) else {
                lastError = L.s("cloud.error.folder")
                return false
            }
            self.synced = outcome.synced
            cloudOnly = outcome.cloudOnly
            pendingUploads = outcome.pendingUploads
            settling = outcome.settling
            record(outcome.lines)
            lastSync = Date()
            lastError = nil
            return outcome.changed
        } catch {
            // The store or the folder could not be read. Nothing was decided
            // from it, so nothing was deleted.
            lastError = L.s("cloud.error.sync", error.localizedDescription)
            return false
        }
    }

    private nonisolated static func run(
        folder: CloudFolder,
        store: TrayStore,
        synced: Set<UUID>,
        progress: @Sendable (Int, Int) async -> Void
    ) async throws -> Outcome {
        // Both reads throw rather than coming back empty: a list that could
        // not be read must never be taken as one where everything was deleted.
        let local = try store.load()
        let listing = try folder.list()
        let plan = CloudPlan.make(
            local: Set(local.map(\.id)), remote: listing.ids,
            tombstones: listing.tombstones, synced: synced
        )
        var outcome = Outcome()
        var inStep = Set(local.map(\.id)).subtracting(plan.removeLocal)
        let steps = plan.removeLocal.count + plan.upload.count + plan.bury.count
        var done = 0
        await progress(0, steps)

        for item in local where plan.removeLocal.contains(item.id) {
            if (try? store.remove(id: item.id)) != nil {
                outcome.changed = true
                outcome.lines.append(L.s("cloud.log.removed", item.name))
            }
            done += 1
            await progress(done, steps)
        }
        for item in local where plan.upload.contains(item.id) {
            do {
                try folder.upload(item, from: store.payloadURL(for: item))
                outcome.lines.append(L.s("cloud.log.uploaded", item.name))
            } catch {
                // Left out of `synced`, so a later pass cannot read its
                // absence from the folder as a deletion.
                inStep.remove(item.id)
                outcome.lines.append(L.s("cloud.log.failed", item.name, error.localizedDescription))
            }
            done += 1
            await progress(done, steps)
        }
        for id in plan.bury {
            let item = listing.items[id]
            try? folder.bury(id, ext: item?.ext)
            if let item, !listing.tombstones.contains(id) {
                outcome.lines.append(L.s("cloud.log.buried", item.name))
            }
            done += 1
            await progress(done, steps)
        }

        outcome.synced = inStep
        outcome.cloudOnly = plan.cloudOnly.compactMap { listing.items[$0] }
        outcome.pendingUploads = local.filter { inStep.contains($0.id) && !folder.isUploaded($0) }.count
        outcome.settling = !listing.pendingDownloads.isEmpty || outcome.pendingUploads > 0
        return outcome
    }

    /// Brings `item` down from the folder into this device's store.
    func download(_ item: TrayItem) async -> Bool {
        guard downloading.insert(item.id).inserted else { return false }
        let store = self.store
        defer { downloading.remove(item.id) }
        do {
            _ = try await withFolder { folder in
                try store.adopt(item, copyingFrom: folder.payloadURL(for: item))
            }
            synced.insert(item.id)
            cloudOnly.removeAll { $0.id == item.id }
            record([L.s("cloud.log.downloaded", item.name)])
            return true
        } catch {
            lastError = L.s("cloud.downloadFailed", item.name, error.localizedDescription)
            record([lastError ?? ""])
            return false
        }
    }

    /// Deletes an item this device never downloaded, everywhere.
    func delete(_ item: TrayItem) async {
        cloudOnly.removeAll { $0.id == item.id }
        do {
            _ = try await withFolder { folder in try folder.bury(item.id, ext: item.ext) }
            record([L.s("cloud.log.buried", item.name)])
        } catch {
            lastError = L.s("cloud.error.sync", error.localizedDescription)
        }
    }

    private func record(_ lines: [String]) {
        guard !lines.isEmpty else { return }
        let stamp = Date().formatted(date: .omitted, time: .shortened)
        log = Array((lines.reversed().map { "\(stamp)  \($0)" } + log).prefix(200))
    }
}
