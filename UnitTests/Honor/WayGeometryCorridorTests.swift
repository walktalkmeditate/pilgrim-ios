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

    private func offset(_ from: CLLocationCoordinate2D, northMeters: Double, eastMeters: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: from.latitude + northMeters / 111_320,
                               longitude: from.longitude + eastMeters / (111_320 * cos(from.latitude * .pi / 180)))
    }

    /// Walks the closed ring in the local-metre frame and returns true only
    /// when every turn bends the same way. A bowtie carries five coordinates
    /// exactly like a quad does, so counting them proves nothing about
    /// self-intersection; the sign of the cross products does.
    private func isConvex(_ ring: [CLLocationCoordinate2D]) -> Bool {
        guard let first = ring.first, ring.count > 3 else { return false }
        let lonScale = cos(first.latitude * .pi / 180)
        let vertices = ring.dropLast().map { (x: $0.longitude * lonScale, y: $0.latitude) }
        var edges: [(x: Double, y: Double)] = []
        for i in vertices.indices {
            let a = vertices[i], b = vertices[(i + 1) % vertices.count]
            let edge = (x: b.x - a.x, y: b.y - a.y)
            // A zero-length edge has no direction to turn from.
            if edge.x != 0 || edge.y != 0 { edges.append(edge) }
        }
        guard edges.count > 2 else { return false }
        var sign = 0.0
        for i in edges.indices {
            let current = edges[i], next = edges[(i + 1) % edges.count]
            let cross = current.x * next.y - current.y * next.x
            if cross == 0 { continue }
            if sign == 0 { sign = cross } else if (cross > 0) != (sign > 0) { return false }
        }
        return sign != 0
    }

    func testEveryPartIsAClosedConvexRing() {
        let line = straight(km: 3)
        let parts = WayGeometry.corridor(around: line, halfWidthMeters: 500)
        XCTAssertEqual(parts.count, 3, "one quad for the simplified two-point line, one square per end")
        for part in parts {
            XCTAssertEqual(part.count, 5)
            XCTAssertEqual(part.first?.latitude, part.last?.latitude)
            XCTAssertEqual(part.first?.longitude, part.last?.longitude)
            XCTAssertTrue(isConvex(part), "every part is convex, so no part can self-intersect")
        }
    }

    func testAStraightLineIsCoveredToHalfWidthAndNotBeyond() {
        let line = straight(km: 3)
        let parts = WayGeometry.corridor(around: line, halfWidthMeters: 500)
        let mid = line[15]
        XCTAssertTrue(WayGeometry.corridorContains(parts, mid))
        XCTAssertTrue(WayGeometry.corridorContains(parts, offset(mid, northMeters: 480, eastMeters: 0)))
        XCTAssertFalse(WayGeometry.corridorContains(parts, offset(mid, northMeters: 520, eastMeters: 0)))
        // The end square reaches half a width past the endpoint; a full width does not.
        XCTAssertTrue(WayGeometry.corridorContains(parts, offset(line.last!, northMeters: 0, eastMeters: 480)))
        XCTAssertFalse(WayGeometry.corridorContains(parts, offset(line.last!, northMeters: 0, eastMeters: 1_020)))
    }

    func testARightAngleBendKeepsItsOuterCornerAndEveryPointOnTheLine() {
        let lat = 42.0
        let east = straight(km: 2, lat: lat)
        let north = (1...20).map { i in offset(east.last!, northMeters: Double(i) * 100, eastMeters: 0) }
        let line = east + north
        let parts = WayGeometry.corridor(around: line, halfWidthMeters: 500)
        // 300 m outside the bend on the diagonal: inside the vertex square.
        XCTAssertTrue(WayGeometry.corridorContains(parts, offset(east.last!, northMeters: -212, eastMeters: 212)))
        // The vertex square is axis-aligned, so its corner reaches 707 m on
        // the diagonal: 700 m out is still covered, and that generosity at a
        // bend is the price of a part that cannot self-intersect.
        XCTAssertTrue(WayGeometry.corridorContains(parts, offset(east.last!, northMeters: -495, eastMeters: 495)))
        // 520 m on each axis clears the square and both rectangles.
        XCTAssertFalse(WayGeometry.corridorContains(parts, offset(east.last!, northMeters: -520, eastMeters: 520)))
        for point in line where !WayGeometry.corridorContains(parts, point) {
            XCTFail("route point \(point) outside its own corridor")
            break
        }
    }

    /// The failure the single ring had: a hairpin whose inner offsets crossed.
    func testAHairpinCoversItsOwnPointsWithNoSelfIntersectingPart() {
        let lat = 42.0
        let out = straight(km: 1, lat: lat)
        let back = (1...10).map { i in offset(out.last!, northMeters: 60, eastMeters: -Double(i) * 100) }
        let line = out + back
        let parts = WayGeometry.corridor(around: line, halfWidthMeters: 500)
        for point in line where !WayGeometry.corridorContains(parts, point) {
            XCTFail("hairpin point \(point) outside its own corridor")
            break
        }
        for part in parts {
            XCTAssertEqual(part.count, 5, "quads and squares only")
            XCTAssertTrue(isConvex(part), "every part is convex, so no part can self-intersect")
        }
    }

    func testSimplificationDropsWigglesUnderTolerance() {
        var line = straight(km: 1)
        for i in stride(from: 1, to: line.count, by: 2) {
            line[i] = offset(line[i], northMeters: 10, eastMeters: 0)
        }
        XCTAssertEqual(WayGeometry.simplified(line, toleranceMeters: 25).count, 2)
    }

    /// The checked-in `stage-00.json` is a short synthetic stage, not the
    /// real Francés day; what matters is that a decoded Way's route goes
    /// through the same path a real one will.
    func testADecodedStageCorridorCoversItsWholeLineIncludingTheEnds() throws {
        let data = try PilgrimageFixtures.data("stage-00.json")
        let way = try PilgrimageWayImporter.way(from: data, routeId: "camino-frances", stageIndex: 0)
        let line = way.route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        let parts = WayGeometry.corridor(around: line, halfWidthMeters: 500)
        for point in line where !WayGeometry.corridorContains(parts, point) {
            XCTFail("route point \(point) outside its own corridor")
            break
        }
    }

    func testOnePointBecomesOneSquare() {
        let parts = WayGeometry.corridor(around: [CLLocationCoordinate2D(latitude: 42, longitude: 0)], halfWidthMeters: 500)
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0].count, 5)
    }

    /// A zero-length segment has no perpendicular, so it yields no rectangle
    /// — but both its vertices still yield squares, and the point is covered.
    func testTwoIdenticalPointsYieldSquaresAndNoRectangle() {
        let point = CLLocationCoordinate2D(latitude: 42, longitude: 0)
        let parts = WayGeometry.corridor(around: [point, point], halfWidthMeters: 500)
        XCTAssertEqual(parts.count, 2)
        for part in parts {
            XCTAssertEqual(part.count, 5)
        }
        XCTAssertTrue(WayGeometry.corridorContains(parts, point))
    }
}
