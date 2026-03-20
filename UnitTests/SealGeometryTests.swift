import XCTest
@testable import Pilgrim

final class SealGeometryTests: XCTestCase {

    func testRingCount_baseThreeToFive() {
        let bytes = [UInt8](repeating: 0, count: 32)
        let geo = SealGeometry(bytes: bytes, size: 512, meditateRatio: 0, talkRatio: 0)
        XCTAssertGreaterThanOrEqual(geo.rings.count, 3)
        XCTAssertLessThanOrEqual(geo.rings.count, 8)
    }

    func testHighMeditationRatio_addsExtraRings() {
        var bytes = [UInt8](repeating: 128, count: 32)
        bytes[1] = 0
        let geoLow = SealGeometry(bytes: bytes, size: 512, meditateRatio: 0, talkRatio: 0)
        let geoHigh = SealGeometry(bytes: bytes, size: 512, meditateRatio: 0.8, talkRatio: 0)
        XCTAssertGreaterThan(geoHigh.rings.count, geoLow.rings.count)
    }

    func testHighTalkRatio_addsExtraLines() {
        var bytes = [UInt8](repeating: 128, count: 32)
        bytes[8] = 0
        let geoLow = SealGeometry(bytes: bytes, size: 512, meditateRatio: 0, talkRatio: 0)
        let geoHigh = SealGeometry(bytes: bytes, size: 512, meditateRatio: 0, talkRatio: 0.5)
        XCTAssertGreaterThan(geoHigh.radialLines.count, geoLow.radialLines.count)
    }

    func testRotation_derivedFromByte0() {
        var bytes = [UInt8](repeating: 0, count: 32)
        bytes[0] = 128
        let geo = SealGeometry(bytes: bytes, size: 512, meditateRatio: 0, talkRatio: 0)
        let expected = (128.0 / 255.0) * 360.0
        XCTAssertEqual(geo.rotation, expected, accuracy: 0.1)
    }

    func testArcCount_twoToFour() {
        let bytes = [UInt8](repeating: 0, count: 32)
        let geo = SealGeometry(bytes: bytes, size: 512, meditateRatio: 0, talkRatio: 0)
        XCTAssertGreaterThanOrEqual(geo.arcSegments.count, 2)
        XCTAssertLessThanOrEqual(geo.arcSegments.count, 4)
    }

    func testDotCount_threeToSeven() {
        let bytes = [UInt8](repeating: 0, count: 32)
        let geo = SealGeometry(bytes: bytes, size: 512, meditateRatio: 0, talkRatio: 0)
        XCTAssertGreaterThanOrEqual(geo.dots.count, 3)
        XCTAssertLessThanOrEqual(geo.dots.count, 7)
    }

    func testDeterministic_sameBytesProduceSameGeometry() {
        let bytes: [UInt8] = (0..<32).map { UInt8($0 * 8) }
        let geo1 = SealGeometry(bytes: bytes, size: 512, meditateRatio: 0.3, talkRatio: 0.1)
        let geo2 = SealGeometry(bytes: bytes, size: 512, meditateRatio: 0.3, talkRatio: 0.1)
        XCTAssertEqual(geo1.rings.count, geo2.rings.count)
        XCTAssertEqual(geo1.radialLines.count, geo2.radialLines.count)
        XCTAssertEqual(geo1.rotation, geo2.rotation)
    }

    func testRenderer_producesNonEmptyImage() {
        let bytes: [UInt8] = (0..<32).map { UInt8($0 * 8) }
        let geo = SealGeometry(bytes: bytes, size: 512, meditateRatio: 0.3, talkRatio: 0.1)
        let input = SealRenderer.Input(
            geometry: geo,
            color: .brown,
            season: "Spring",
            year: 2026,
            timeOfDay: "Morning",
            displayDistance: "5.2",
            unitLabel: "KM",
            routePoints: [(35.68, 139.76), (35.69, 139.77), (35.70, 139.78)],
            altitudes: Array(stride(from: 100.0, through: 200.0, by: 10.0)),
            weatherCondition: "rain",
            weatherSeed: UInt64(bytes[0]) | (UInt64(bytes[1]) << 8) | (UInt64(bytes[2]) << 16) | (UInt64(bytes[3]) << 24)
        )
        let image = SealRenderer.render(input: input)
        XCTAssertEqual(image.size.width, 512)
        XCTAssertEqual(image.size.height, 512)
    }
}
