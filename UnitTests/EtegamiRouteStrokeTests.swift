import XCTest
@testable import Pilgrim

final class EtegamiRouteStrokeTests: XCTestCase {

    func testProjection_fitsWithinBounds() {
        let points: [(lat: Double, lon: Double)] = [
            (35.68, 139.76), (35.69, 139.77), (35.70, 139.78)
        ]
        let bounds = CGRect(x: 100, y: 200, width: 880, height: 1000)
        let projected = EtegamiRouteStroke.projectRoute(points, into: bounds)
        for p in projected {
            XCTAssertTrue(bounds.contains(p), "Point \(p) outside bounds \(bounds)")
        }
    }

    func testProjection_emptyRoute_returnsEmpty() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let projected = EtegamiRouteStroke.projectRoute([], into: bounds)
        XCTAssertTrue(projected.isEmpty)
    }

    func testStrokeWidth_uphillIsThicker() {
        let altitudes = [100.0, 110.0, 200.0]
        let widths = EtegamiRouteStroke.computeStrokeWidths(
            altitudes: altitudes, baseWidth: 4, count: 3
        )
        XCTAssertGreaterThan(widths[1], widths[0])
    }

    func testTaper_endsAreThin() {
        let tapers = EtegamiRouteStroke.computeTaperMultipliers(count: 100)
        XCTAssertLessThan(tapers[0], 0.5)
        XCTAssertLessThan(tapers[99], 0.5)
        XCTAssertGreaterThan(tapers[50], 0.9)
    }

    func testStrokeWidth_flatTerrain_returnsBaseWidth() {
        let altitudes = [100.0, 100.0, 100.0]
        let widths = EtegamiRouteStroke.computeStrokeWidths(
            altitudes: altitudes, baseWidth: 4, count: 2
        )
        XCTAssertEqual(widths[0], 4.0)
        XCTAssertEqual(widths[1], 4.0)
    }

    func testEtegamiRenderer_producesCorrectSize() {
        let input = EtegamiRenderer.Input(
            routePoints: [(35.68, 139.76), (35.69, 139.77), (35.70, 139.78)],
            altitudes: [100, 120, 140],
            activityMarkers: [],
            sealImage: UIImage(),
            sealPosition: CGPoint(x: 500, y: 800),
            haikuText: "spring morning walk\nforty minutes in silence\nalong the trail",
            moonPhase: nil,
            timeOfDay: "Morning",
            inkColor: .brown,
            paperColor: UIColor(hex: "#F5F0E8"),
            displayDistance: "3.2"
        )
        let image = EtegamiRenderer.render(input: input)
        XCTAssertEqual(image.size.width, 1080)
        XCTAssertEqual(image.size.height, 1920)
    }
}
