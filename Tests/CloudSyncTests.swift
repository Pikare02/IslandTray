import XCTest
@testable import IslandTray

final class CloudSyncTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID()

    // MARK: - The rules that can delete files

    func testNewHereIsUploadedAndNewThereIsListedOnly() {
        let plan = CloudPlan.make(local: [a], remote: [b], tombstones: [], synced: [])
        XCTAssertEqual(plan.upload, [a])
        XCTAssertEqual(plan.cloudOnly, [b])
        XCTAssertTrue(plan.removeLocal.isEmpty)
        XCTAssertTrue(plan.bury.isEmpty)
    }

    func testDeletedHereIsBuriedThere() {
        let plan = CloudPlan.make(local: [], remote: [a], tombstones: [], synced: [a])
        XCTAssertEqual(plan.bury, [a])
        XCTAssertTrue(plan.cloudOnly.isEmpty)
    }

    func testDeletedThereIsRemovedHere() {
        let plan = CloudPlan.make(local: [a], remote: [], tombstones: [a], synced: [a])
        XCTAssertEqual(plan.removeLocal, [a])
        XCTAssertTrue(plan.upload.isEmpty)
    }

    /// An entry removed by hand in Files leaves no tombstone. The copy here is
    /// then the only one, and goes back up rather than being deleted.
    func testVanishedWithoutTombstoneIsUploadedAgain() {
        let plan = CloudPlan.make(local: [a], remote: [], tombstones: [], synced: [a])
        XCTAssertEqual(plan.upload, [a])
        XCTAssertTrue(plan.removeLocal.isEmpty)
    }

    /// A fresh device, or a fresh folder: nothing it lacks reads as a delete.
    func testNothingIsDeletedWithoutHistory() {
        let plan = CloudPlan.make(local: [a], remote: [b, c], tombstones: [], synced: [])
        XCTAssertTrue(plan.bury.isEmpty)
        XCTAssertTrue(plan.removeLocal.isEmpty)
        XCTAssertEqual(plan.cloudOnly, [b, c])
    }

    // MARK: - The folder

    func testTwoDevicesRoundTripThroughTheFolder() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let phone = TrayStore(root: temp.appendingPathComponent("phone"))
        let pad = TrayStore(root: temp.appendingPathComponent("pad"))
        let folder = CloudFolder(root: temp.appendingPathComponent("iCloud"))

        let item = try phone.add(data: Data("hi".utf8), suggestedName: "note.txt", uti: "public.plain-text")
        try folder.upload(item, from: phone.payloadURL(for: item))

        let listing = try folder.list()
        XCTAssertEqual(listing.ids, [item.id])
        let remote = try XCTUnwrap(listing.items[item.id])
        XCTAssertEqual(remote.name, "note.txt")

        try pad.adopt(remote, copyingFrom: folder.payloadURL(for: remote))
        let onPad = try pad.load()
        XCTAssertEqual(onPad.map(\.id), [item.id])
        XCTAssertEqual(try Data(contentsOf: pad.payloadURL(for: onPad[0])), Data("hi".utf8))

        try folder.bury(item.id, ext: remote.ext)
        let after = try folder.list()
        XCTAssertTrue(after.ids.isEmpty)
        XCTAssertEqual(after.tombstones, [item.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.payloadURL(for: remote).path))
    }

    /// The entry's extension becomes part of a path here.
    func testAnEntryThatWouldEscapeItsFolderIsRefused() {
        let id = UUID()
        var item = TrayItem(id: id, name: "x", uti: "public.data", size: 0, addedAt: Date(), ext: "txt")
        XCTAssertTrue(CloudFolder.isSafe(item, id: id))
        item.ext = "/../../x"
        XCTAssertFalse(CloudFolder.isSafe(item, id: id))
        item.ext = "txt"
        XCTAssertFalse(CloudFolder.isSafe(item, id: UUID()))
    }

    func testPlaceholderNamesMapToTheirFiles() {
        XCTAssertEqual(CloudFolder.placeholderTarget(".A.json.icloud"), "A.json")
        XCTAssertNil(CloudFolder.placeholderTarget("A.json"))
    }

    /// A meta entry iCloud has not downloaded yet is counted as present but
    /// reported as pending, so the poll knows to look again soon instead of
    /// waiting a full idle interval to read it.
    func testUndownloadedEntryIsPendingNotReadable() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let folder = CloudFolder(root: temp)
        try folder.prepare()
        // How iCloud lists a meta file whose contents are not here yet.
        let placeholder = folder.metaDirectory.appendingPathComponent(".\(a.uuidString).json.icloud")
        try Data().write(to: placeholder)

        let listing = try folder.list()
        XCTAssertEqual(listing.ids, [a])
        XCTAssertEqual(listing.pendingDownloads, [a])
        XCTAssertNil(listing.items[a])
    }
}

final class DrawerSyncTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000), t1 = Date(timeIntervalSince1970: 2_000)

    func testLastEditWins() {
        XCTAssertEqual(DrawerSyncStep.decide(local: nil, remote: nil), .none)
        XCTAssertEqual(DrawerSyncStep.decide(local: t0, remote: nil), .upload)
        XCTAssertEqual(DrawerSyncStep.decide(local: nil, remote: t0), .adopt)
        XCTAssertEqual(DrawerSyncStep.decide(local: t1, remote: t0), .upload)
        XCTAssertEqual(DrawerSyncStep.decide(local: t0, remote: t1), .adopt)
        XCTAssertEqual(DrawerSyncStep.decide(local: t0, remote: t0), .none)
    }

    func testDrawerRoundTripsThroughTheFolderWithIconsAndStamp() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let phone = DrawerStore(directory: temp.appendingPathComponent("phone"))
        let pad = DrawerStore(directory: temp.appendingPathComponent("pad"))
        let folder = CloudFolder(root: temp.appendingPathComponent("iCloud"))

        let id = UUID()
        let icon = phone.writeIcon(Data("png".utf8), for: id)
        phone.save([DrawerShortcut(id: id, kind: .webURL("https://a.b"), displayName: "A", customIconName: icon, order: 0)])
        phone.writeBackgroundImage(Data("bg".utf8))
        let stamp = try XCTUnwrap(phone.modifiedAt)

        XCTAssertEqual(DrawerSyncStep.decide(local: phone.modifiedAt, remote: try folder.listDrawer().document?.modifiedAt), .upload)
        try folder.uploadDrawer(from: phone, at: stamp)

        let document = try XCTUnwrap(try folder.listDrawer().document)
        XCTAssertEqual(DrawerSyncStep.decide(local: pad.modifiedAt, remote: document.modifiedAt), .adopt)
        try folder.adoptDrawer(document, into: pad)
        XCTAssertEqual(pad.load().map(\.id), [id])
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(pad.iconURL(for: pad.load()[0]))), Data("png".utf8))
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(pad.backgroundImageURL)), Data("bg".utf8))
        // Taken, not edited: the next pass must not send it straight back.
        XCTAssertEqual(DrawerSyncStep.decide(local: pad.modifiedAt, remote: document.modifiedAt), .none)

        // The pad clears the drawer; the phone follows, icon and background included.
        pad.save([])
        pad.writeBackgroundImage(nil)
        try folder.uploadDrawer(from: pad, at: XCTUnwrap(pad.modifiedAt))
        let cleared = try XCTUnwrap(try folder.listDrawer().document)
        XCTAssertEqual(DrawerSyncStep.decide(local: phone.modifiedAt, remote: cleared.modifiedAt), .adopt)
        try folder.adoptDrawer(cleared, into: phone)
        XCTAssertTrue(phone.load().isEmpty)
        XCTAssertNil(phone.backgroundImageURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: phone.dir.appendingPathComponent(icon).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.drawerDirectory.appendingPathComponent(icon).path))
    }

    /// An icon name is a path on this device; one the folder made up is refused.
    func testForeignIconNameIsDropped() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let store = DrawerStore(directory: temp.appendingPathComponent("store"))
        let folder = CloudFolder(root: temp.appendingPathComponent("iCloud"))
        let bad = DrawerShortcut(id: UUID(), kind: .webURL("https://a.b"), displayName: "A", customIconName: "../evil.jpg", order: 0)
        try folder.adoptDrawer(DrawerDocument(modifiedAt: t0, shortcuts: [bad], hasBackground: false), into: store)
        XCTAssertNil(store.load()[0].customIconName)
    }
}
