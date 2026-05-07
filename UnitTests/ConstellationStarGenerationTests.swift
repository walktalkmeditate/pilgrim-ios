import XCTest
@testable import Pilgrim

final class ConstellationStarGenerationTests: XCTestCase {

    func testGenerateStars_countWithinRange() {
        for _ in 0..<50 {
            let stars = ConstellationOverlay.generateStars(canvasSize: CGSize(width: 393, height: 852))
            XCTAssertGreaterThanOrEqual(stars.count, 1, "Star count must be ≥ 1")
            XCTAssertLessThanOrEqual(stars.count, 12, "Star count must be ≤ 12")
        }
    }

    func testGenerateStars_positionsNormalized() {
        let stars = ConstellationOverlay.generateStars(canvasSize: CGSize(width: 393, height: 852))
        for star in stars {
            XCTAssertGreaterThanOrEqual(star.position.x, 0)
            XCTAssertLessThanOrEqual(star.position.x, 1)
            XCTAssertGreaterThanOrEqual(star.position.y, 0)
            XCTAssertLessThanOrEqual(star.position.y, 1)
        }
    }

    func testGenerateStars_twinkleFrequencyWithinAudibleRange() {
        let stars = ConstellationOverlay.generateStars(canvasSize: CGSize(width: 393, height: 852))
        for star in stars {
            // WCAG 2.3.1 — must be < 3 Hz; design target ≤ 1 Hz
            XCTAssertLessThanOrEqual(star.twinkleFrequencyHz, 1.0)
            XCTAssertGreaterThan(star.twinkleFrequencyHz, 0.0)
        }
    }

    func testStaticOpacityForReduceMotion_isMidValue() {
        XCTAssertEqual(ConstellationOverlay.staticOpacity, 0.6, accuracy: 0.001)
    }
}
