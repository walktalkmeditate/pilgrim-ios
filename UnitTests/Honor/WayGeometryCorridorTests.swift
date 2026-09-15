import XCTest
import CoreLocation
@testable import Pilgrim

final class WayGeometryCorridorTests: XCTestCase {

    private func straight(km: Double, lat: Double = 42) -> [CLLocationCoordinate2D] {
        let metersPerDegreeLon = 111_320 * cos(lat * .pi / 180)
        let steps = Int(km * 10)
        return (0...steps).map { i in
            CLLocationCoordinate2D(latitude: lat, longitude: Double(i) * 100 / metersPerDegreeLon)
        }
    }

    func testAStraightLineYieldsARectangleOfTheRightWidth() {
        let line = straight(km: 3)
        let ring = WayGeometry.corridor(around: line, halfWidthMeters: 500)
        XCTAssertEqual(ring.first?.latitude, ring.last?.latitude)
        XCTAssertEqual(ring.first?.longitude, ring.last?.longitude, "ring is closed")
        let area = WayGeometry.ringAreaSquareMeters(ring)
        XCTAssertEqual(area, 3_000 * 1_000, accuracy: 3_000 * 1_000 * 0.05)
        let latitudes = ring.map(\.latitude)
        let spanMeters = (latitudes.max()! - latitudes.min()!) * 111_320
        XCTAssertEqual(spanMeters, 1_000, accuracy: 20)
    }

    func testARightAngleBendKeepsItsOuterCorner() {
        let lat = 42.0
        let east = straight(km: 2, lat: lat)
        let metersPerDegreeLat = 111_320.0
        let north = (1...20).map { i in
            CLLocationCoordinate2D(latitude: lat + Double(i) * 100 / metersPerDegreeLat, longitude: east.last!.longitude)
        }
        let ring = WayGeometry.corridor(around: east + north, halfWidthMeters: 500)
        // 300 m outside the bend on the diagonal: inside a 500 m corridor.
        let corner = CLLocationCoordinate2D(latitude: lat - 212 / metersPerDegreeLat,
                                            longitude: east.last!.longitude + 212 / (metersPerDegreeLat * cos(lat * .pi / 180)))
        XCTAssertTrue(WayGeometry.ringContains(ring, corner))
        // 700 m outside: not.
        let far = CLLocationCoordinate2D(latitude: lat - 495 / metersPerDegreeLat,
                                         longitude: east.last!.longitude + 495 / (metersPerDegreeLat * cos(lat * .pi / 180)))
        XCTAssertFalse(WayGeometry.ringContains(ring, far))
    }

    func testSimplificationDropsWigglesUnderTolerance() {
        var line = straight(km: 1)
        // A 10 m wiggle on every other point.
        for i in stride(from: 1, to: line.count, by: 2) {
            line[i] = CLLocationCoordinate2D(latitude: line[i].latitude + 10 / 111_320, longitude: line[i].longitude)
        }
        let simplified = WayGeometry.simplified(line, toleranceMeters: 25)
        XCTAssertEqual(simplified.count, 2, "a straight-enough line is its two ends")
    }

    /// The checked-in `stage-00.json` is a short synthetic stage (about
    /// 1 km, eleven points), not the real Francés day — what matters is
    /// that a decoded Way's route goes through the same path a real one
    /// will. Area within 20 % of length × 1 km, every route point inside.
    func testTheFrancesStageZeroCorridorIsTightAndCoversItsLine() throws {
        let data = try PilgrimageFixtures.data("stage-00.json")
        let way = try PilgrimageWayImporter.way(from: data, routeId: "camino-frances", stageIndex: 0)
        let line = way.route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        let ring = WayGeometry.corridor(around: line, halfWidthMeters: 500)
        let geometry = WayGeometry(route: way.route)
        let area = WayGeometry.ringAreaSquareMeters(ring)
        XCTAssertEqual(area, geometry.totalMeters * 1_000, accuracy: geometry.totalMeters * 1_000 * 0.2)
        // The first and last points lie exactly on the ring's closing edges
        // — a boundary ray casting cannot decide either way — so only the
        // interior points are asserted inside. The endpoint's tile still
        // loads: the two ring vertices offset from it sit inside that tile.
        for point in line.dropFirst().dropLast() where !WayGeometry.ringContains(ring, point) {
            XCTFail("route point \(point) outside its own corridor")
            break
        }
    }

    func testTwoPointsAndOnePointStillProduceARing() {
        let two = WayGeometry.corridor(around: Array(straight(km: 0.1).prefix(2)), halfWidthMeters: 500)
        XCTAssertGreaterThanOrEqual(two.count, 5)
        let one = WayGeometry.corridor(around: [CLLocationCoordinate2D(latitude: 42, longitude: 0)], halfWidthMeters: 500)
        XCTAssertGreaterThanOrEqual(one.count, 5, "a point becomes a square")
    }
}
