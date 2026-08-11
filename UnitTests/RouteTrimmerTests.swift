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

    func testClusteredEndpointCollisionIsHonest() {
        // Route with ~1000m + ~1000m + ~1m segments: total ~2km, but endpoints cluster
        // together at the end, causing trim's start/end pointers to collide.
        // canTrim must return false AND trim must return route unchanged.
        let route = [
            SharePayload.RoutePoint(lat: 35.0, lon: -105.0, alt: 2000, ts: 1000),
            SharePayload.RoutePoint(lat: 35.009, lon: -105.0, alt: 2000, ts: 1030),      // ~1000m from point 0
            SharePayload.RoutePoint(lat: 35.018, lon: -105.0, alt: 2000, ts: 1060),      // ~1000m from point 1
            SharePayload.RoutePoint(lat: 35.018009, lon: -105.0, alt: 2000, ts: 1090),   // ~1m from point 2
        ]
        XCTAssertFalse(RouteTrimmer.canTrim(route, meters: 150))
        XCTAssertEqual(RouteTrimmer.trim(route, meters: 150).count, 4)
    }

    func testCanTrimAlwaysAgreesWithTrim() {
        let geometries: [(name: String, route: [SharePayload.RoutePoint])] = [
            ("uniform 20-point", straightRoute(points: 20)),
            ("clustered endpoints", [
                SharePayload.RoutePoint(lat: 35.0, lon: -105.0, alt: 2000, ts: 1000),
                SharePayload.RoutePoint(lat: 35.009, lon: -105.0, alt: 2000, ts: 1030),
                SharePayload.RoutePoint(lat: 35.018, lon: -105.0, alt: 2000, ts: 1060),
                SharePayload.RoutePoint(lat: 35.018009, lon: -105.0, alt: 2000, ts: 1090),
            ]),
            ("short 4-point walk", straightRoute(points: 4)),
            ("10-point with huge end segment", Array((0..<9).map { i in
                SharePayload.RoutePoint(lat: 35.0 + Double(i) * 0.001, lon: -105.0, alt: 2000, ts: 1000 + i * 30)
            }) + [
                SharePayload.RoutePoint(lat: 35.009, lon: -105.0 + 0.045, alt: 2000, ts: 1270)  // ~5km from previous
            ]),
        ]

        for geometry in geometries {
            let canTrimResult = RouteTrimmer.canTrim(geometry.route, meters: 150)
            let trimResult = RouteTrimmer.trim(geometry.route, meters: 150)
            let trimChanged = trimResult.count < geometry.route.count
            XCTAssertEqual(canTrimResult, trimChanged, "Mismatch for \(geometry.name): canTrim=\(canTrimResult), trim changed=\(trimChanged)")
        }
    }

    func testDegenerateRouteCounts() {
        // Empty route
        let empty: [SharePayload.RoutePoint] = []
        XCTAssertEqual(RouteTrimmer.trim(empty, meters: 150).count, 0)
        XCTAssertFalse(RouteTrimmer.canTrim(empty, meters: 150))

        // 1-point route
        let onePoint = [SharePayload.RoutePoint(lat: 35.0, lon: -105.0, alt: 2000, ts: 1000)]
        XCTAssertEqual(RouteTrimmer.trim(onePoint, meters: 150).count, 1)
        XCTAssertFalse(RouteTrimmer.canTrim(onePoint, meters: 150))

        // 2-point route
        let twoPoints = [
            SharePayload.RoutePoint(lat: 35.0, lon: -105.0, alt: 2000, ts: 1000),
            SharePayload.RoutePoint(lat: 35.001, lon: -105.0, alt: 2000, ts: 1030),
        ]
        XCTAssertEqual(RouteTrimmer.trim(twoPoints, meters: 150).count, 2)
        XCTAssertFalse(RouteTrimmer.canTrim(twoPoints, meters: 150))

        // 3-point route
        let threePoints = [
            SharePayload.RoutePoint(lat: 35.0, lon: -105.0, alt: 2000, ts: 1000),
            SharePayload.RoutePoint(lat: 35.001, lon: -105.0, alt: 2000, ts: 1030),
            SharePayload.RoutePoint(lat: 35.002, lon: -105.0, alt: 2000, ts: 1060),
        ]
        XCTAssertEqual(RouteTrimmer.trim(threePoints, meters: 150).count, 3)
        XCTAssertFalse(RouteTrimmer.canTrim(threePoints, meters: 150))
    }
}
