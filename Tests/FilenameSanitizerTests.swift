import XCTest
@testable import IslandTray

final class FilenameSanitizerTests: XCTestCase {
    func testKeepsOrdinaryName() {
        let r = FilenameSanitizer.sanitize("photo.jpeg", fallbackExtension: nil)
        XCTAssertEqual(r.name, "photo.jpeg")
        XCTAssertEqual(r.ext, "jpeg")
    }

    func testStripsPathSeparators() {
        let r = FilenameSanitizer.sanitize("../../etc/passwd", fallbackExtension: nil)
        XCTAssertFalse(r.name.contains("/"))
        XCTAssertFalse(r.name.contains(".."))
        XCTAssertEqual(r.name, "passwd")
    }

    func testStripsNullAndControlCharacters() {
        let r = FilenameSanitizer.sanitize("a\u{0}b\nc.txt", fallbackExtension: nil)
        XCTAssertEqual(r.name, "abc.txt")
        XCTAssertEqual(r.ext, "txt")
    }

    func testUsesFallbackWhenNameIsNil() {
        let r = FilenameSanitizer.sanitize(nil, fallbackExtension: "png")
        XCTAssertEqual(r.name, "Untitled.png")
        XCTAssertEqual(r.ext, "png")
    }

    func testUsesFallbackWhenNameIsBlank() {
        let r = FilenameSanitizer.sanitize("   ", fallbackExtension: "pdf")
        XCTAssertEqual(r.name, "Untitled.pdf")
        XCTAssertEqual(r.ext, "pdf")
    }

    func testAppendsFallbackExtensionWhenMissing() {
        let r = FilenameSanitizer.sanitize("scan", fallbackExtension: "pdf")
        XCTAssertEqual(r.name, "scan.pdf")
        XCTAssertEqual(r.ext, "pdf")
    }

    func testNoExtensionAndNoFallback() {
        let r = FilenameSanitizer.sanitize("README", fallbackExtension: nil)
        XCTAssertEqual(r.name, "README")
        XCTAssertEqual(r.ext, "")
    }

    func testLowercasesExtension() {
        let r = FilenameSanitizer.sanitize("IMG_0001.JPEG", fallbackExtension: nil)
        XCTAssertEqual(r.ext, "jpeg")
    }

    func testTruncatesVeryLongName() {
        let long = String(repeating: "a", count: 500) + ".txt"
        let r = FilenameSanitizer.sanitize(long, fallbackExtension: nil)
        XCTAssertLessThanOrEqual(r.name.utf8.count, 255)
        XCTAssertTrue(r.name.hasSuffix(".txt"))
    }
}
