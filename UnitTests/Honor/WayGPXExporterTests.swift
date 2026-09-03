import XCTest
@testable import Pilgrim

final class WayGPXExporterTests: XCTestCase {

    func testEmitsTimedWaypointsAndNoTrack() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let route = [WayPoint(lat: 42.1, lon: -8.2, alt: 300, t: 0), WayPoint(lat: 42.2, lon: -8.3, alt: nil, t: 90)]
        let sit = WayMoment(id: "sit-1", frac: 1, at: nil, kind: .meditation(minutes: 5, isEstimate: false))
        let way = Way(id: "walk:x", source: .ownWalk(UUID()), title: "x", departedAt: start, tzIdentifier: nil, expires: nil,
                      route: route, totalDistanceMeters: 13_000, theirActiveSeconds: 90, moments: [sit], weather: nil)
        let xml = String(decoding: WayGPXExporter.gpx(for: way), as: UTF8.self)
        XCTAssertFalse(xml.contains("<trk>"))
        XCTAssertEqual(xml.components(separatedBy: "<wpt ").count - 1, 2)
        XCTAssertTrue(xml.contains("<time>2023-11-14T22:13:20Z</time>"))
        XCTAssertTrue(xml.contains("<time>2023-11-14T22:14:50Z</time>"))
        XCTAssertTrue(xml.contains("<ele>300</ele>"))
        XCTAssertTrue(xml.contains("<name>sit-1</name>"), "moment kinds ride on the nearest route waypoint")
    }
}
