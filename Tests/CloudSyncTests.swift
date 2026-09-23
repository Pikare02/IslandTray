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
}
