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

    /// Pins the 255-byte guarantee generally, not just for the "long stem, short
    /// extension" shape: every input here must come back at or under the cap,
    /// regardless of where the bytes are concentrated.
    func testByteCapHoldsRegardlessOfShape() {
        let cases: [(raw: String?, fallback: String?)] = [
            (String(repeating: "a", count: 500) + ".txt", nil),
            ("photo." + String(repeating: "a", count: 400), nil),
            (String(repeating: "a", count: 500), String(repeating: "b", count: 400)),
            (String(repeating: "a", count: 500) + "." + String(repeating: "a", count: 400), nil),
            (String(repeating: "é", count: 500) + ".txt", nil),
        ]
        for c in cases {
            let r = FilenameSanitizer.sanitize(c.raw, fallbackExtension: c.fallback)
            XCTAssertLessThanOrEqual(
                r.name.utf8.count, 255,
                "name exceeded 255 bytes for raw=\(String(describing: c.raw)), fallback=\(String(describing: c.fallback))"
            )
        }
    }

    /// Finding 1 repro: a filename whose "extension" segment is absurdly long
    /// must not be able to defeat the 255-byte cap by driving the truncation
    /// budget negative. The over-long segment is not a real extension, so it
    /// is dropped entirely rather than truncated in place.
    func testOverLongExtensionSegmentIsTreatedAsNoExtension() {
        let r = FilenameSanitizer.sanitize("photo." + String(repeating: "a", count: 400), fallbackExtension: nil)
        XCTAssertLessThanOrEqual(r.name.utf8.count, 255)
        XCTAssertEqual(r.ext, "")
        XCTAssertEqual(r.name, "photo")
    }

    /// Same defect, reachable through fallbackExtension instead of raw.
    func testOverLongFallbackExtensionIsRejected() {
        let r = FilenameSanitizer.sanitize("scan", fallbackExtension: String(repeating: "a", count: 400))
        XCTAssertLessThanOrEqual(r.name.utf8.count, 255)
        XCTAssertEqual(r.ext, "")
        XCTAssertEqual(r.name, "scan")
    }

    /// Guards against overcorrecting: real-world long extensions (up to ~12
    /// chars, e.g. Sketch's "sketchplugin" or Numbers' "numbers-tef") must
    /// still be preserved, not swept up by the over-long-extension guard.
    func testOrdinaryLongExtensionIsPreserved() {
        let r = FilenameSanitizer.sanitize("archive.sketchplugin", fallbackExtension: nil)
        XCTAssertEqual(r.ext, "sketchplugin")
        XCTAssertEqual(r.name, "archive.sketchplugin")
    }

    func testStripsLineAndParagraphSeparators() {
        let r = FilenameSanitizer.sanitize("a\u{2028}b\u{2029}c.txt", fallbackExtension: nil)
        XCTAssertEqual(r.name, "abc.txt")
        XCTAssertEqual(r.ext, "txt")
    }
}
