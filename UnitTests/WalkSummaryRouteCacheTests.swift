import XCTest
import CoreLocation
@testable import Pilgrim

/// Covers the route-derived caches WalkSummaryView computes once per walk
/// identity at init (AF17) instead of traversing the CoreStore routeData
/// relationship on every body evaluation.
final class WalkSummaryRouteCacheTests: XCTestCase {

    private func makeSample(minute: Int, altitude: Double) -> TempRouteDataSample {
        WalkDataFactory.makeRouteDataSample(
            timestamp: DateFactory.makeDate(2024, 6, 15, 9, minute, 0),
            latitude: 48.8566 + Double(minute) * 0.0001,
            longitude: 2.3522 + Double(minute) * 0.0001,
            altitude: altitude
        )
    }

    func testComputeRouteCoordinates_mapsAllSamplesInOrder() {
        let walk = WalkDataFactory.makeWalk(
            routeData: [makeSample(minute: 0, altitude: 10), makeSample(minute: 1, altitude: 12)]
        )
        let coords = WalkSummaryView.computeRouteCoordinates(for: walk)
        XCTAssertEqual(coords.count, 2)
        XCTAssertEqual(coords[0].latitude, 48.8566, accuracy: 0.000001)
        XCTAssertEqual(coords[1].latitude, 48.8567, accuracy: 0.000001)
    }

    func testComputeRouteCoordinates_emptyRoute_returnsEmpty() {
        let walk = WalkDataFactory.makeWalk(routeData: [])
        XCTAssertTrue(WalkSummaryView.computeRouteCoordinates(for: walk).isEmpty)
    }

    func testComputeElevationData_variedRoute_returnsMinMax() {
        let altitudes: [Double] = [10, 14, 22, 18, 30, 26]
        let walk = WalkDataFactory.makeWalk(
            routeData: altitudes.enumerated().map { makeSample(minute: $0.offset, altitude: $0.element) }
        )
        let elevation = WalkSummaryView.computeElevationData(for: walk)
        XCTAssertNotNil(elevation)
        XCTAssertEqual(elevation?.altitudes.count, 6)
        XCTAssertEqual(elevation?.minAlt, 10)
        XCTAssertEqual(elevation?.maxAlt, 30)
    }

    func testComputeElevationData_tooFewSamples_returnsNil() {
        let walk = WalkDataFactory.makeWalk(
            routeData: (0..<5).map { makeSample(minute: $0, altitude: Double(10 + $0 * 5)) }
        )
        XCTAssertNil(WalkSummaryView.computeElevationData(for: walk))
    }

    func testComputeElevationData_flatRoute_returnsNil() {
        let walk = WalkDataFactory.makeWalk(
            routeData: (0..<10).map { makeSample(minute: $0, altitude: 20) }
        )
        XCTAssertNil(WalkSummaryView.computeElevationData(for: walk))
    }
}
