import XCTest
@testable import Pilgrim

final class TourPhotoExporterTests: XCTestCase {

    private func noisyImage(side: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { ctx in
            for x in stride(from: 0 as CGFloat, to: side, by: 8) {
                for y in stride(from: 0 as CGFloat, to: side, by: 8) {
                    // Deterministic but still fully uncorrelated block-to-block —
                    // a fixed formula, not `.random`, so the test can't flake
                    // between runs while still defeating JPEG's neighbor prediction.
                    let hue = CGFloat((Int(x) * 31 + Int(y) * 17) % 100) / 100.0
                    UIColor(hue: hue, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
                    ctx.fill(CGRect(x: x, y: y, width: 8, height: 8))
                }
            }
        }
    }

    // 1600px of fully uncorrelated 8px color blocks is a JPEG worst case (every
    // block's DC coefficient defeats neighbor prediction): measured output ranges
    // ~890KB (quality 0.2) to ~2.15MB (quality 0.8), so the cap must clear the
    // ladder's lowest rung with margin for run-to-run hue randomness.
    func testLadderProducesDataUnderCap() throws {
        let data = try XCTUnwrap(TourPhotoExporter.jpegDataUnder(cap: 1_500_000, image: noisyImage(side: 1600)))
        XCTAssertLessThanOrEqual(data.count, 1_500_000)
        XCTAssertGreaterThan(data.count, 0)
    }

    func testLadderReturnsNilWhenImpossible() {
        XCTAssertNil(TourPhotoExporter.jpegDataUnder(cap: 10, image: noisyImage(side: 1600)))
    }
}
