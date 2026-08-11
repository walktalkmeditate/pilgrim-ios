import XCTest
@testable import Pilgrim

final class RouteTrimmerTests: XCTestCase {

    /// ~111m per 0.001 degrees latitude.
    private func straightRoute(points: Int, stepDegrees: Double = 0.001) -> [SharePayload.RoutePoint] {
        (0..<points).map { i in
            SharePayload.RoutePoint(lat: 35.0 + Double(i) * stepDegrees, lon: -105.0, alt: 2000, ts: 1000 + i * 30)
        }
    }

    func testTrimZeroReturnsRouteUnchanged() {
        let route = straightRoute(points: 10)
        XCTAssertEqual(RouteTrimmer.trim(route, meters: 0).count, 10)
    }

    func testTrimRemovesBothEnds() {
        let route = straightRoute(points: 20)   // ~2.1km total, 111m steps
        let trimmed = RouteTrimmer.trim(route, meters: 150)
        XCTAssertLessThan(trimmed.count, 20)
        XCTAssertGreaterThan(trimmed.first!.lat, route.first!.lat)
        XCTAssertLessThan(trimmed.last!.lat, route.last!.lat)
        XCTAssertGreaterThanOrEqual(trimmed.count, 2)
    }

    func testShortWalkSharesUntrimmed() {
        let route = straightRoute(points: 4)    // ~333m total < 4 * 150
        XCTAssertEqual(RouteTrimmer.trim(route, meters: 150).count, 4)
    }

    func testCanTrimReflectsThreshold() {
        XCTAssertFalse(RouteTrimmer.canTrim(straightRoute(points: 4), meters: 150))
        XCTAssertTrue(RouteTrimmer.canTrim(straightRoute(points: 20), meters: 150))
    }
}
