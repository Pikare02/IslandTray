import UIKit
import XCTest
@testable import IslandTray

final class ContentIndexTests: XCTestCase {
    func testTextInAnImageIsRecognised() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 160)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 160))
            ("INVOICE 2026" as NSString).draw(
                at: CGPoint(x: 30, y: 50),
                withAttributes: [.font: UIFont.systemFont(ofSize: 48), .foregroundColor: UIColor.black]
            )
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ocr-\(UUID()).png")
        try XCTUnwrap(image.pngData()).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(ContentIndex.recognise(url).localizedStandardContains("invoice"))
    }
}
