import XCTest
import CoreLocation
@testable import Pilgrim

final class WayGeometryTests: XCTestCase {

    /// A 1 km straight line east along the equator, 11 points, 100 m apart, 60 s apart.
    private func straight() -> WayGeometry {
        let points = (0...10).map { i in
            WayPoint(lat: 0, lon: Double(i) * 0.000898, alt: nil, t: Double(i) * 60)
        }
        return WayGeometry(route: points)
    }

    /// Out and back: 500 m east then the same 500 m west, 11 points.
    private func outAndBack() -> WayGeometry {
        let out = (0...5).map { i in WayPoint(lat: 0, lon: Double(i) * 0.000898, alt: nil, t: Double(i) * 60) }
        let back = (1...5).map { i in WayPoint(lat: 0, lon: Double(5 - i) * 0.000898, alt: nil, t: Double(5 + i) * 60) }
        return WayGeometry(route: out + back)
    }

    func testTotalsAndFracRoundTrips() {
        let geo = straight()
        XCTAssertEqual(geo.totalMeters, 1000, accuracy: 5)
        XCTAssertEqual(geo.totalSeconds, 600)
        let mid = geo.coordinate(atFrac: 0.5)
        XCTAssertEqual(mid.longitude, 0.00449, accuracy: 0.00002)
        XCTAssertEqual(geo.elapsed(atFrac: 0.5), 300, accuracy: 1)
        XCTAssertEqual(geo.frac(atElapsed: 300), 0.5, accuracy: 0.01)
        XCTAssertEqual(geo.frac(atElapsed: 9999), 1)
        XCTAssertEqual(geo.frac(atElapsed: -5), 0)
    }

    func testNearestOnStraightLine() {
        let geo = straight()
        let probe = CLLocationCoordinate2D(latitude: 0.00018, longitude: 0.00449)
        let hit = geo.nearest(to: probe, within: nil)
        XCTAssertEqual(hit.frac, 0.5, accuracy: 0.01)
        XCTAssertEqual(hit.meters, 20, accuracy: 2)
    }

    func testWindowedNearestStaysOnTheOutboundLeg() {
        let geo = outAndBack()
        // 250 m along: both legs pass here. Unwindowed search is ambiguous.
        let probe = CLLocationCoordinate2D(latitude: 0, longitude: 0.000898 * 2.5)
        let windowed = geo.nearest(to: probe, within: 0.20...0.35)
        XCTAssertEqual(windowed.frac, 0.25, accuracy: 0.01)
        let returnLeg = geo.nearest(to: probe, within: 0.70...0.85)
        XCTAssertEqual(returnLeg.frac, 0.75, accuracy: 0.01)
    }

    func testDegenerateRoutes() {
        let single = WayGeometry(route: [WayPoint(lat: 1, lon: 1, alt: nil, t: 0)])
        XCTAssertEqual(single.totalMeters, 0)
        XCTAssertEqual(single.frac(atElapsed: 10), 1)
        let hit = single.nearest(to: CLLocationCoordinate2D(latitude: 1, longitude: 1), within: nil)
        XCTAssertEqual(hit.frac, 0)
        XCTAssertEqual(hit.meters, 0, accuracy: 0.01)
    }

    /// A rest: two points at one place, sixty seconds apart. The inverse map
    /// lands on the end of the pause (depart together); the forward map holds
    /// the dot at the rest for the whole pause.
    func testAPauseMapsToTheMomentTheyMovedOn() {
        let points = [
            WayPoint(lat: 0, lon: 0, alt: nil, t: 0),
            WayPoint(lat: 0, lon: 0.000898, alt: nil, t: 60),
            WayPoint(lat: 0, lon: 0.000898, alt: nil, t: 120),
            WayPoint(lat: 0, lon: 0.001796, alt: nil, t: 180),
        ]
        let geo = WayGeometry(route: points)
        XCTAssertEqual(geo.elapsed(atFrac: 0.5), 120, accuracy: 0.5)
        XCTAssertEqual(geo.frac(atElapsed: 70), 0.5, accuracy: 0.01)
        XCTAssertEqual(geo.frac(atElapsed: 110), 0.5, accuracy: 0.01)
        XCTAssertEqual(geo.frac(atElapsed: 150), 0.75, accuracy: 0.01)
    }
}
