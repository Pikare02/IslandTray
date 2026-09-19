import XCTest
@testable import IslandTray

final class TrayStoreTests: XCTestCase {
    private var root: URL!
    private var store: TrayStore!

    /// TrayItem.fileURL resolves against TrayContainer, which is the real app
    /// container. Tests run against a temporary root, so they must pass it in.
    private var itemsDir: URL { root.appendingPathComponent("Items", isDirectory: true) }

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = TrayStore(root: root)
        try store.prepare()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAddThenLoadRoundTrip() throws {
        let item = try store.add(data: Data("hello".utf8), suggestedName: "a.txt", uti: "public.plain-text")
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, item.id)
        XCTAssertEqual(loaded[0].name, "a.txt")
        XCTAssertEqual(loaded[0].size, 5)
        XCTAssertEqual(loaded[0].ext, "txt")
    }

    func testStoredBytesMatch() throws {
        let payload = Data("island".utf8)
        let item = try store.add(data: payload, suggestedName: "b.bin", uti: "public.data")
        XCTAssertEqual(try Data(contentsOf: item.fileURL(in: itemsDir)), payload)
    }

    func testDuplicateNamesDoNotCollide() throws {
        let a = try store.add(data: Data("1".utf8), suggestedName: "same.txt", uti: "public.plain-text")
        let b = try store.add(data: Data("22".utf8), suggestedName: "same.txt", uti: "public.plain-text")
        XCTAssertNotEqual(a.fileURL(in: itemsDir), b.fileURL(in: itemsDir))
        XCTAssertEqual(try store.load().count, 2)
        XCTAssertEqual(try Data(contentsOf: a.fileURL(in: itemsDir)).count, 1)
        XCTAssertEqual(try Data(contentsOf: b.fileURL(in: itemsDir)).count, 2)
    }

    func testPathTraversalNameStaysInsideContainer() throws {
        let item = try store.add(data: Data("x".utf8), suggestedName: "../../escape.txt", uti: "public.plain-text")
        XCTAssertTrue(
            item.fileURL(in: itemsDir).standardizedFileURL.path
                .hasPrefix(itemsDir.standardizedFileURL.path)
        )
    }

    func testRemoveDeletesFileAndMetadata() throws {
        let item = try store.add(data: Data("x".utf8), suggestedName: "c.txt", uti: "public.plain-text")
        _ = try store.remove(id: item.id)
        XCTAssertTrue(try store.load().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.fileURL(in: itemsDir).path))
    }

    func testNewestFirstOrdering() throws {
        let first = try store.add(data: Data("1".utf8), suggestedName: "1.txt", uti: "public.plain-text")
        let second = try store.add(data: Data("2".utf8), suggestedName: "2.txt", uti: "public.plain-text")
        let loaded = try store.load()
        XCTAssertEqual(loaded.map(\.id), [second.id, first.id])
    }

    func testAddCopyingFromURL() throws {
        let src = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("src.txt")
        try Data("from disk".utf8).write(to: src)
        defer { try? FileManager.default.removeItem(at: src) }

        let item = try store.add(copyingFrom: src, suggestedName: nil, uti: "public.plain-text")
        XCTAssertEqual(item.name, "src.txt")
        XCTAssertEqual(try Data(contentsOf: item.fileURL(in: itemsDir)), Data("from disk".utf8))
    }

    func testRebuildFromDiskRecoversAfterCorruptMetadata() throws {
        let item = try store.add(data: Data("keep".utf8), suggestedName: "d.txt", uti: "public.plain-text")
        try Data("}{ not json".utf8).write(to: root.appendingPathComponent("items.json"))

        // load() must not throw on corrupt metadata; it rebuilds instead.
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, item.id)
    }

    func testSymbolNameFallsBackByUTI() throws {
        let image = try store.add(data: Data("x".utf8), suggestedName: "p.jpeg", uti: "public.jpeg")
        let text = try store.add(data: Data("x".utf8), suggestedName: "t.txt", uti: "public.plain-text")
        XCTAssertEqual(image.symbolName, "photo")
        XCTAssertEqual(text.symbolName, "doc.text")
    }

    // MARK: - Helpers

    private var metadataURL: URL { root.appendingPathComponent("items.json") }

    private func addText(_ name: String, _ body: String = "x") throws -> TrayItem {
        try store.add(data: Data(body.utf8), suggestedName: name, uti: "public.plain-text")
    }

    private func itemsDirEntries() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: itemsDir.path)
    }

    /// Arranges a real failure on disk (unreadable file, undeletable directory)
    /// instead of adding an injection seam to the store.
    private func withPermissions(_ mode: Int, at url: URL, _ body: () throws -> Void) throws {
        let fm = FileManager.default
        let original = (try fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber) ?? 0o755
        try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
        defer { try? fm.setAttributes([.posixPermissions: original], ofItemAtPath: url.path) }
        try body()
    }

    /// chflags uchg -- what a file locked by another process looks like to
    /// unlink(2). Restored before tearDown so the temporary root can be removed.
    private func withImmutable(_ url: URL, _ body: () throws -> Void) throws {
        let fm = FileManager.default
        try fm.setAttributes([.immutable: true], ofItemAtPath: url.path)
        defer { try? fm.setAttributes([.immutable: false], ofItemAtPath: url.path) }
        try body()
    }

    private func corruptMetadata() throws {
        try Data("}{ not json".utf8).write(to: metadataURL)
    }

    // MARK: - Finding 1: concurrent read-modify-write

    func testConcurrentAddsFromTwoStoresAllSurvive() throws {
        let first = store!
        let second = TrayStore(root: root)
        let iterations = 20

        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            let target = i.isMultiple(of: 2) ? first : second
            do {
                _ = try target.add(data: Data("\(i)".utf8), suggestedName: "f\(i).txt", uti: "public.plain-text")
            } catch {
                XCTFail("concurrent add \(i) threw: \(error)")
            }
        }

        let loaded = try store.load()
        XCTAssertEqual(loaded.count, iterations, "metadata lost concurrent adds")
        XCTAssertEqual(Set(loaded.map(\.id)).count, iterations)
        XCTAssertEqual(try itemsDirEntries().count, iterations, "orphaned payloads on disk")
    }

    // MARK: - Finding 2: a failed read is not an empty tray

    func testLoadThrowsWhenMetadataIsUnreadable() throws {
        _ = try addText("1.txt")
        _ = try addText("2.txt")
        _ = try addText("3.txt")

        try withPermissions(0o000, at: metadataURL) {
            XCTAssertNil(try? Data(contentsOf: metadataURL), "precondition: items.json must be unreadable")
            XCTAssertThrowsError(try store.load(), "a failed read must not look like an empty tray")
        }

        XCTAssertEqual(try store.load().count, 3)
    }

    func testAddDuringReadFailureDoesNotOverwriteMetadata() throws {
        _ = try addText("1.txt")
        _ = try addText("2.txt")
        _ = try addText("3.txt")
        let before = try Data(contentsOf: metadataURL)

        try withPermissions(0o000, at: metadataURL) {
            XCTAssertThrowsError(try self.addText("4.txt"), "a write must not proceed from an unreadable baseline")
        }

        XCTAssertEqual(try Data(contentsOf: metadataURL), before)
        XCTAssertEqual(try store.load().count, 3)
    }

    func testRemoveAllDuringReadFailureDeletesNothing() throws {
        _ = try addText("1.txt")
        _ = try addText("2.txt")

        try withPermissions(0o000, at: metadataURL) {
            XCTAssertThrowsError(try store.removeAll())
        }

        XCTAssertEqual(try store.load().count, 2)
        XCTAssertEqual(try itemsDirEntries().count, 2)
    }

    // MARK: - Finding 3: rebuild must not destroy what it recovers

    func testRebuildThrowsWhenItemsDirectoryIsUnlistable() throws {
        _ = try addText("1.txt")
        _ = try addText("2.txt")
        _ = try addText("3.txt")
        try corruptMetadata()
        let corrupt = try Data(contentsOf: metadataURL)

        try withPermissions(0o000, at: itemsDir) {
            XCTAssertNil(
                try? FileManager.default.contentsOfDirectory(atPath: itemsDir.path),
                "precondition: Items/ must be unlistable"
            )
            XCTAssertThrowsError(try store.rebuildFromDisk(), "a failed listing must propagate")
            XCTAssertEqual(try Data(contentsOf: metadataURL), corrupt, "rebuild must leave metadata alone on failure")
        }

        // The recovery path is still available once the condition clears.
        XCTAssertEqual(try store.load().count, 3)
    }

    // MARK: - Finding 4: deletion must not reverse itself

    func testRemovedItemStaysRemovedAcrossRebuild() throws {
        let keep = try addText("keep.txt")
        let gone = try addText("gone.txt")
        _ = try store.remove(id: gone.id)
        try corruptMetadata()
        XCTAssertEqual(try store.load().map(\.id), [keep.id], "rebuild resurrected a removed item")
    }

    func testRemoveReportsFailureWhenPayloadCannotBeDeleted() throws {
        let item = try addText("stuck.txt")

        try withPermissions(0o500, at: itemsDir) {
            XCTAssertThrowsError(try store.remove(id: item.id), "a failed unlink must not be reported as success")
        }

        // Still listed, and still listed after a rebuild -- never silently
        // dropped from metadata while its bytes stay on disk.
        XCTAssertEqual(try store.load().map(\.id), [item.id])
        try corruptMetadata()
        XCTAssertEqual(try store.load().map(\.id), [item.id])
    }

    // MARK: - Finding 5: add is transactional

    func testFailedAddLeavesNoPayloadBehind() throws {
        _ = try addText("1.txt")

        try withPermissions(0o000, at: metadataURL) {
            XCTAssertThrowsError(try self.addText("2.txt"))
        }

        XCTAssertEqual(try itemsDirEntries().count, 1, "a failed add leaked its payload")
        XCTAssertEqual(try store.load().count, 1)
    }

    func testFailedCopyAddLeavesNoPayloadBehind() throws {
        let source = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".txt")
        try Data("payload".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        _ = try addText("1.txt")

        try withPermissions(0o000, at: metadataURL) {
            XCTAssertThrowsError(try store.add(copyingFrom: source, suggestedName: nil, uti: "public.plain-text"))
        }

        XCTAssertEqual(try itemsDirEntries().count, 1, "a failed add leaked its payload")
    }

    // MARK: - Finding 6: addedAt precision and total ordering

    func testAddedItemEqualsItemLoadedBack() throws {
        let item = try addText("a.txt")
        XCTAssertEqual(try store.load().first, item, "value round-trip through items.json is lossy")
    }

    func testOrderingIsDeterministicForIdenticalTimestamps() throws {
        var added: [TrayItem] = []
        for i in 0..<5 { added.append(try addText("\(i).txt")) }

        // Force an exact collision -- what second-resolution timestamps produce
        // for every item added in the same second.
        let stamp = Date()
        let collided = added.map {
            TrayItem(id: $0.id, name: $0.name, uti: $0.uti, size: $0.size, addedAt: stamp, ext: $0.ext)
        }
        try JSONEncoder.tray.encode(collided).write(to: metadataURL)

        let first = try store.load().map(\.id)
        let second = try store.load().map(\.id)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, added.map(\.id).sorted { $0.uuidString < $1.uuidString })
    }

    // MARK: - Finding 7: what rebuild does and does not recover

    func testRebuildRecoversExtensionDerivedMetadata() throws {
        let photo = try store.add(data: Data("jpegbytes".utf8), suggestedName: "vacation.jpeg", uti: "public.jpeg")
        let blob = try store.add(data: Data("x".utf8), suggestedName: nil, uti: nil)
        XCTAssertEqual(blob.ext, "")
        try corruptMetadata()

        let recovered = try store.load()
        let photoBack = try XCTUnwrap(recovered.first { $0.id == photo.id })
        let blobBack = try XCTUnwrap(recovered.first { $0.id == blob.id })

        // Recovered from the filename: extension, UTI, glyph, size.
        XCTAssertEqual(photoBack.ext, "jpeg")
        XCTAssertEqual(photoBack.uti, "public.jpeg")
        XCTAssertEqual(photoBack.symbolName, "photo")
        XCTAssertEqual(photoBack.size, 9)
        XCTAssertTrue(photoBack.name.hasSuffix(".jpeg"), "recovered name should keep the extension: \(photoBack.name)")

        // Not recovered: the original display name. It must not be the raw UUID.
        XCTAssertNotEqual(photoBack.name, "vacation.jpeg")
        XCTAssertFalse(photoBack.name.contains(photo.id.uuidString), "display name must not be the UUID")

        // Not recovered: the UTI of an extension-less payload.
        XCTAssertEqual(blobBack.uti, "public.data")
        XCTAssertEqual(blobBack.symbolName, "doc")
        XCTAssertFalse(blobBack.name.isEmpty)

        // The recovered list is persisted, so the next load does not re-rebuild.
        // It is persisted in the current schema, not the bare array it replaced.
        let persisted = try JSONDecoder.tray.decode(TrayMetadata.self, from: Data(contentsOf: metadataURL))
        XCTAssertEqual(persisted.version, TrayMetadata.currentVersion)
        XCTAssertEqual(Set(persisted.items.map(\.id)), Set(recovered.map(\.id)))
    }

    // MARK: - Finding 8: uncovered paths

    func testRemoveAllDeletesFilesAndMetadata() throws {
        _ = try addText("1.txt")
        _ = try addText("2.txt")
        _ = try store.removeAll()
        XCTAssertTrue(try store.load().isEmpty)
        XCTAssertEqual(try itemsDirEntries(), [])
        // And nothing comes back from a rebuild.
        try corruptMetadata()
        XCTAssertTrue(try store.load().isEmpty)
    }

    func testLoadDropsEntriesWhosePayloadIsMissing() throws {
        let kept = try addText("kept.txt")
        let vanished = try addText("vanished.txt")
        try FileManager.default.removeItem(at: vanished.fileURL(in: itemsDir))
        XCTAssertEqual(try store.load().map(\.id), [kept.id])
    }

    func testRemoveUnknownIDIsANoOp() throws {
        let item = try addText("1.txt")
        _ = try store.remove(id: UUID())
        XCTAssertEqual(try store.load().map(\.id), [item.id])
    }

    // MARK: - Regression 1: a mutation must not rebuild from disk

    func testAddOnCorruptMetadataThrowsAndLeavesNoPayload() throws {
        let existing = try addText("old.txt")
        try corruptMetadata()

        // The payload is written before the claim is taken, so a mutation that
        // rebuilt its baseline from disk would find the in-flight file there and
        // insert the same id twice.
        XCTAssertThrowsError(try self.addText("new.txt"), "a mutation must not recover behind the caller's back")

        XCTAssertEqual(try itemsDirEntries().count, 1, "a failed add leaked its payload")
        XCTAssertEqual(try store.load().map(\.id), [existing.id])
    }

    func testLoadNeverReturnsDuplicateIDs() throws {
        let item = try addText("dupe.txt")
        // However the duplicate got there -- a merge, an interrupted recovery,
        // a hand-edited file. TrayItem is Identifiable and this list feeds a
        // SwiftUI ForEach, where a repeated id is undefined behaviour.
        try JSONEncoder.tray.encode(TrayMetadata(items: [item, item])).write(to: metadataURL)

        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.map(\.id), [item.id])

        // And the invariant survives the payload still being on disk for both.
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.fileURL(in: itemsDir).path))
    }

    // MARK: - Regression 2: partial destruction is never reported as total failure

    func testRemoveAllReportsPartialSuccessWhenOnePayloadIsLocked() throws {
        var added: [TrayItem] = []
        for i in 0..<5 { added.append(try addText("\(i).txt")) }
        let stuck = added[2]

        try withImmutable(stuck.fileURL(in: itemsDir)) {
            XCTAssertThrowsError(
                try FileManager.default.removeItem(at: stuck.fileURL(in: itemsDir)),
                "precondition: the payload must be undeletable"
            )

            // A sweep that left a payload behind is not the "it worked" shape,
            // but it still has to say exactly what went and what did not.
            XCTAssertThrowsError(try store.removeAll()) { error in
                guard case .incompleteRemoval(let result, _) = error as? TrayStoreError else {
                    return XCTFail("a partial destruction must carry both lists: \(error)")
                }
                XCTAssertEqual(Set(result.removed), Set(added.filter { $0.id != stuck.id }.map(\.id)))
                XCTAssertEqual(result.failed, [stuck.id])
            }

            // Metadata agrees with disk: what went is gone from both, what
            // stayed is listed in both.
            XCTAssertEqual(try itemsDirEntries(), [stuck.fileName])
            XCTAssertEqual(try store.load().map(\.id), [stuck.id])
        }
    }

    func testRemoveAllSurvivorIsNotResurrectedAndIsDeletableLater() throws {
        let a = try addText("a.txt")
        let stuck = try addText("stuck.txt")

        try withImmutable(stuck.fileURL(in: itemsDir)) {
            _ = try? store.removeAll()
        }

        // Finding 4: the payloads that did go must not come back from a rebuild.
        try corruptMetadata()
        XCTAssertEqual(try store.load().map(\.id), [stuck.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.fileURL(in: itemsDir).path))

        let second = try store.removeAll()
        XCTAssertEqual(second.removed, [stuck.id])
        XCTAssertTrue(second.failed.isEmpty)
        XCTAssertTrue(try store.load().isEmpty)
    }

    func testRemoveAllSurfacesWhatWentWhenTheMetadataWriteFails() throws {
        let a = try addText("a.txt")
        let b = try addText("b.txt")

        // Items/ stays writable, so the unlinks succeed; root/ does not, so the
        // atomic rename of items.json cannot land.
        try withPermissions(0o500, at: root) {
            XCTAssertThrowsError(try store.removeAll()) { error in
                guard case .incompleteRemoval(let result, _) = error as? TrayStoreError else {
                    return XCTFail("a partial destruction must not surface as a plain failure: \(error)")
                }
                XCTAssertEqual(Set(result.removed), Set([a.id, b.id]))
                XCTAssertTrue(result.failed.isEmpty)
            }
        }

        XCTAssertEqual(try itemsDirEntries(), [], "the unlinks did happen")
    }

    // MARK: - Regression 3: the on-disk format is versioned and backward tolerant

    func testMetadataCarriesSchemaVersion() throws {
        _ = try addText("1.txt")
        let stored = try JSONDecoder.tray.decode(TrayMetadata.self, from: Data(contentsOf: metadataURL))
        XCTAssertEqual(stored.version, TrayMetadata.currentVersion)
        XCTAssertEqual(stored.items.count, 1)
    }

    func testLegacyISO8601MetadataKeepsItsDisplayNames() throws {
        let taxes = try addText("taxes.pdf")
        let cat = try addText("cat.jpeg")

        // Exactly what the previous build wrote: a bare array, ISO8601 dates.
        let legacy = JSONEncoder()
        legacy.dateEncodingStrategy = .iso8601
        try legacy.encode([taxes, cat]).write(to: metadataURL)

        let loaded = try store.load()
        XCTAssertEqual(Set(loaded.map(\.name)), ["taxes.pdf", "cat.jpeg"], "a format change destroyed the names")
        XCTAssertEqual(Set(loaded.map(\.id)), Set([taxes.id, cat.id]))
    }

    func testUnknownSchemaVersionThrowsAndIsNotRebuiltOver() throws {
        _ = try addText("keep.txt")
        let future = Data(#"{"version":9999,"items":[]}"#.utf8)
        try future.write(to: metadataURL)

        XCTAssertThrowsError(try store.load(), "metadata from a newer build is not corrupt metadata")
        XCTAssertEqual(try Data(contentsOf: metadataURL), future, "a newer schema must never be overwritten")
        XCTAssertThrowsError(try self.addText("2.txt"), "a mutation must not build on an unrecognised schema")
    }

    func testBytesThatAreNotJSONStillRebuild() throws {
        let item = try addText("keep.txt")
        try corruptMetadata()
        // The destructive path is still reachable -- for genuine garbage only.
        XCTAssertEqual(try store.load().map(\.id), [item.id])
    }

    // MARK: - Round 3, Finding 1: a recovery must not eat a concurrent add

    /// The damage needs a real race: a recovery whose decision was taken before
    /// another process's add() landed. One store retries add() while three
    /// others call load() on the same corrupt tray, which is what the app, the
    /// widget's timeline provider and the share extension do to one container.
    /// Every trial is asserted, so one destroyed name out of ten fails the test.
    func testRecoveryRacingAnAddKeepsTheRealNameAndTimestamp() throws {
        let payload = Data("photo".utf8)

        for trial in 0..<10 {
            let trialRoot = root.appendingPathComponent("trial-\(trial)", isDirectory: true)
            let trialItems = trialRoot.appendingPathComponent("Items", isDirectory: true)
            let adder = TrayStore(root: trialRoot)
            try adder.prepare()
            try Data("}{ not json".utf8).write(to: trialRoot.appendingPathComponent("items.json"))
            let readers = (0..<3).map { _ in TrayStore(root: trialRoot) }

            DispatchQueue.concurrentPerform(iterations: readers.count + 1) { i in
                guard i > 0 else {
                    // add() throws while the metadata is still garbage, so it
                    // retries: the item at risk is the one that commits next to
                    // a recovery, not one that is refused outright.
                    let deadline = Date().addingTimeInterval(5)
                    while Date() < deadline {
                        let added = try? adder.add(
                            data: payload, suggestedName: "photo.txt", uti: "public.plain-text"
                        )
                        if added != nil { return }
                    }
                    return
                }
                for _ in 0..<5 { _ = try? readers[i - 1].load() }
            }

            let loaded = try adder.load()
            XCTAssertEqual(loaded.count, 1, "trial \(trial): the concurrent add did not survive")
            let item = try XCTUnwrap(loaded.first)
            XCTAssertEqual(
                item.name, "photo.txt",
                "trial \(trial): a recovery replaced a concurrent add's display name"
            )
            // A recovered placeholder takes addedAt from the payload's creation
            // date, which is always later than the real item's -- so a surviving
            // timestamp is provably the one add() chose, not the file's.
            let created = try XCTUnwrap(
                FileManager.default
                    .attributesOfItem(atPath: item.fileURL(in: trialItems).path)[.creationDate] as? Date
            )
            XCTAssertLessThan(
                item.addedAt, created,
                "trial \(trial): addedAt was replaced by the payload's creation time"
            )
        }
    }

    /// Which twin the dedupe keeps is not academic: the one case that produces
    /// duplicates is a recovery racing an add, and a timestamp tiebreak always
    /// picks the placeholder because its addedAt is the file's creation date.
    func testDuplicateIDKeepsTheRealEntryNotTheRecoveredPlaceholder() throws {
        let item = try addText("photo.txt")
        let placeholder = TrayItem(
            id: item.id,
            name: "Recovered-\(item.id.uuidString.prefix(8)).txt",
            uti: item.uti,
            size: item.size,
            addedAt: item.addedAt.addingTimeInterval(60),
            ext: item.ext
        )
        try JSONEncoder.tray.encode(TrayMetadata(items: [item, placeholder])).write(to: metadataURL)

        XCTAssertEqual(try store.load().map(\.name), ["photo.txt"])
    }

    /// The decision to rebuild and the rebuild itself must be one transaction.
    /// Driven directly, because that is what a "Repair tray" affordance does --
    /// and because load()'s decision is stale by the time the claim is taken.
    func testRebuildLeavesMetadataThatIsValidAlone() throws {
        let item = try addText("vacation.jpeg")

        let rebuilt = try store.rebuildFromDisk()
        XCTAssertEqual(rebuilt.map(\.name), ["vacation.jpeg"], "a rebuild destroyed valid metadata")
        XCTAssertEqual(rebuilt.map(\.id), [item.id])
        XCTAssertEqual(try store.load().map(\.name), ["vacation.jpeg"])
        XCTAssertEqual(try store.load().first?.addedAt, item.addedAt)
    }

    // MARK: - Round 3, Finding 4: rebuild carries load()'s version guard too

    func testRebuildRefusesANewerSchema() throws {
        _ = try addText("keep.txt")
        let future = Data(#"{"version":9999,"items":[]}"#.utf8)
        try future.write(to: metadataURL)

        XCTAssertThrowsError(try store.rebuildFromDisk(), "a newer schema is not damage") { error in
            XCTAssertEqual(error as? TrayStoreError, .unsupportedSchemaVersion(9999))
        }
        XCTAssertEqual(try Data(contentsOf: metadataURL), future, "a newer schema must never be overwritten")
    }

    // MARK: - Round 3, Finding 2: one contract for what a sweep did

    func testRemoveAllTellsTheCallerWhatSurvivedWhenEveryUnlinkFails() throws {
        let a = try addText("a.txt")
        let b = try addText("b.txt")

        try withPermissions(0o500, at: itemsDir) {
            XCTAssertThrowsError(try store.removeAll(), "a sweep that deleted nothing still failed") { error in
                guard case .incompleteRemoval(let result, _) = error as? TrayStoreError else {
                    return XCTFail("the failed list must not be discarded: \(error)")
                }
                XCTAssertTrue(result.removed.isEmpty)
                XCTAssertEqual(Set(result.failed), Set([a.id, b.id]))
            }
        }

        XCTAssertEqual(try store.load().count, 2, "nothing was destroyed, so nothing was dropped")
        XCTAssertEqual(try itemsDirEntries().count, 2)
    }

    // MARK: - Round 3, Finding 3: an older schema is migrated, not refused

    func testAFutureBuildStillReadsMetadataThisBuildWrote() throws {
        let item = try addText("taxes.pdf")
        let today = try Data(contentsOf: metadataURL)

        // Simulate the next routine version bump: the same decoder, one
        // currentVersion higher. Whoever bumps it finds out here, not from users.
        let migrated = try TrayStore.decodeItems(
            from: today, currentVersion: TrayMetadata.currentVersion + 1
        )
        XCTAssertEqual(migrated.map(\.id), [item.id])
        XCTAssertEqual(migrated.map(\.name), ["taxes.pdf"], "a version bump must not orphan existing trays")

        // The other direction is unchanged: metadata from a build that knows a
        // newer schema is refused, never read as this build's shape.
        XCTAssertThrowsError(
            try TrayStore.decodeItems(from: today, currentVersion: TrayMetadata.currentVersion - 1)
        ) { error in
            XCTAssertEqual(error as? TrayStoreError, .unsupportedSchemaVersion(TrayMetadata.currentVersion))
        }
    }

    // MARK: - Task 11: migration from a previous container

    /// A second container to migrate from, cleaned up with the test.
    private func makeOldStore() throws -> (store: TrayStore, root: URL) {
        let oldRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: oldRoot) }
        let oldStore = TrayStore(root: oldRoot)
        try oldStore.prepare()
        return (oldStore, oldRoot)
    }

    func testMigrationMovesItemsFromLocalRoot() throws {
        let (oldStore, oldRoot) = try makeOldStore()
        let a = try oldStore.add(data: Data("one".utf8), suggestedName: "a.txt", uti: "public.plain-text")
        _ = try oldStore.add(data: Data("two".utf8), suggestedName: "b.txt", uti: "public.plain-text")

        let moved = try store.migrateIfNeeded(from: oldRoot)
        XCTAssertEqual(moved, 2)

        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 2)
        let migratedA = try XCTUnwrap(loaded.first { $0.id == a.id })
        XCTAssertEqual(migratedA.name, "a.txt", "a moved item keeps its display name, not a placeholder")
        XCTAssertEqual(try Data(contentsOf: migratedA.fileURL(in: itemsDir)), Data("one".utf8))
        XCTAssertTrue(try oldStore.load().isEmpty, "the payloads were moved, not duplicated")
    }

    func testMigrationIsIdempotent() throws {
        let (oldStore, oldRoot) = try makeOldStore()
        _ = try oldStore.add(data: Data("one".utf8), suggestedName: "a.txt", uti: "public.plain-text")

        XCTAssertEqual(try store.migrateIfNeeded(from: oldRoot), 1)
        XCTAssertEqual(try store.migrateIfNeeded(from: oldRoot), 0)
        XCTAssertEqual(try store.load().count, 1)
        XCTAssertEqual(try itemsDirEntries().count, 1)
    }

    func testMigrationFromSameRootDoesNothing() throws {
        _ = try store.add(data: Data("x".utf8), suggestedName: "a.txt", uti: "public.plain-text")
        // Read-only root, so a run that got as far as rewriting metadata would
        // throw instead of returning the same 0 by coincidence: this pins the
        // guard itself, not the fact that every id is already known.
        try withPermissions(0o500, at: root) {
            XCTAssertEqual(try store.migrateIfNeeded(from: root), 0)
        }
        XCTAssertEqual(try store.load().count, 1)
    }

    /// The migration reads someone else's container, so it must not call
    /// anything that prepares or repairs one: on a free-to-paid move the old
    /// root may legitimately not exist at all.
    func testMigrationNeverCreatesTheContainerItReadsFrom() throws {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: missing) }

        XCTAssertEqual(try store.migrateIfNeeded(from: missing), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }

    /// Idempotence by id alone would not be enough: a migrated item the user
    /// then deleted is absent from this container's metadata too, so a second
    /// run must find nothing left to take rather than bringing it back.
    func testMigrationDoesNotResurrectARemovedItem() throws {
        let (oldStore, oldRoot) = try makeOldStore()
        let item = try oldStore.add(data: Data("one".utf8), suggestedName: "a.txt", uti: "public.plain-text")

        XCTAssertEqual(try store.migrateIfNeeded(from: oldRoot), 1)
        _ = try store.remove(id: item.id)

        XCTAssertEqual(try store.migrateIfNeeded(from: oldRoot), 0)
        XCTAssertTrue(try store.load().isEmpty)
        XCTAssertEqual(try itemsDirEntries(), [])
    }

    /// Both containers hold items the other does not: the union survives.
    func testMigrationKeepsItemsAlreadyInThisContainer() throws {
        let (oldStore, oldRoot) = try makeOldStore()
        let mine = try store.add(data: Data("mine".utf8), suggestedName: "mine.txt", uti: "public.plain-text")
        let theirs = try oldStore.add(data: Data("theirs".utf8), suggestedName: "theirs.txt", uti: "public.plain-text")

        XCTAssertEqual(try store.migrateIfNeeded(from: oldRoot), 1)
        XCTAssertEqual(Set(try store.load().map(\.id)), Set([mine.id, theirs.id]))
    }
}
