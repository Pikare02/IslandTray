import UniformTypeIdentifiers
import XCTest
@testable import IslandTray

@MainActor
final class RichTextTests: XCTestCase {
    private let rtf = Data(#"{\rtf1\ansi {\b Hello} world}"#.utf8)

    func testRTFIsRecognisedByTypeNameOrBytes() {
        XCTAssertEqual(RichText.type(uti: UTType.rtf.identifier, filename: "x", data: Data()), .rtf)
        XCTAssertEqual(RichText.type(uti: nil, filename: "Rich Text.rtf", data: Data()), .rtf)
        // What an old build saved: RTF source under a plain-text type.
        XCTAssertEqual(RichText.type(uti: UTType.utf8PlainText.identifier, filename: "a.txt", data: rtf), .rtf)
        XCTAssertNil(RichText.type(uti: UTType.utf8PlainText.identifier, filename: "a.txt", data: Data("hi".utf8)))
    }

    func testPlainTextDropsTheFormatting() {
        XCTAssertEqual(RichText.plainText(rtf, type: .rtf), "Hello world")
        XCTAssertEqual(RichText.plainText(Data("<p><b>Hi</b> there</p>".utf8), type: .html)?
            .trimmingCharacters(in: .whitespacesAndNewlines), "Hi there")
    }
}
