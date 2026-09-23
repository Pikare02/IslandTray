import XCTest
@testable import IslandTray

final class TrayDragProviderTests: XCTestCase {
    private func item(uti: String, ext: String) -> TrayItem {
        TrayItem(id: UUID(), name: "x.\(ext)", uti: uti, size: 1, addedAt: Date(), ext: ext)
    }

    func testDeclaredTypesAreOfferedAsThemselves() {
        XCTAssertEqual(TrayDragProvider.typeIdentifier(for: item(uti: "public.png", ext: "png")), "public.png")
        XCTAssertEqual(TrayDragProvider.typeIdentifier(for: item(uti: "unknown.type", ext: "zip")), "public.zip-archive")
    }

    func testAFolderIsOfferedAsAFolder() {
        XCTAssertEqual(TrayDragProvider.typeIdentifier(for: item(uti: "public.folder", ext: "")), "public.folder")
    }

    /// Files shows no "+" for a drag that only offers a dyn.* type.
    func testUndeclaredExtensionIsOfferedAsData() {
        XCTAssertEqual(TrayDragProvider.typeIdentifier(for: item(uti: "com.apple.itunes.ipa", ext: "ipa")), "public.data")
        XCTAssertEqual(TrayDragProvider.typeIdentifier(for: item(uti: "dyn.ah62d4rv4ge80w6db", ext: "ipa")), "public.data")
    }

    /// Dragging out of the clipboard board is a paste, not a move.
    func testOnlyTheTrayHandsItemsOver() {
        var tray = item(uti: "public.png", ext: "png")
        XCTAssertTrue(TrayDragProvider.handsOver(tray))
        tray.board = .clipboard
        XCTAssertFalse(TrayDragProvider.handsOver(tray))
    }
}
