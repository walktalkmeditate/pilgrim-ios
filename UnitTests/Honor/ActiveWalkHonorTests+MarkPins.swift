import XCTest
import CoreLocation
@testable import Pilgrim

/// The stage's service marks as the walk's own pins: which forty, when they
/// are re-chosen, and when they are not drawn at all. Cases of
/// `ActiveWalkHonorTests` (its fixture drives the real view model); a file of
/// their own only because that one is already at SwiftLint's length gate.
extension ActiveWalkHonorTests {

    /// Three water marks 100 m apart along the same equatorial kilometre the
    /// other fixtures walk, carried by a pilgrimage stage.
    private func stageWayWithMarks() -> Way {
        let route = (0...10).map { i in WayPoint(lat: 0, lon: Double(i) * 0.000898, alt: nil, t: Double(i) * 60) }
        var way = Way(id: WayStore.stageWayId(routeId: "camino-frances", stageIndex: 0),
                      source: .pilgrimage(routeId: "camino-frances", stageIndex: 0),
                      title: "Stage one", departedAt: start, tzIdentifier: nil, expires: nil,
                      route: route, totalDistanceMeters: 1000, theirActiveSeconds: 600,
                      moments: [], weather: nil)
        way.marks = (0..<3).map { i in
            WayMark(id: "m\(i)", kind: .water, name: "fuente \(i)",
                    at: WayCoordinate(lat: 0, lon: Double(i) * 0.000898),
                    frac: Double(i) / 10, offLineMeters: 5)
        }
        way.stage = WayStage(routeId: "camino-frances", index: 0, count: 33, name: "Stage one",
                             theme: "Initiation", narrative: "n", closing: "c", warnings: [],
                             distanceKm: 1, gainMeters: 0, hours: WayStageHours(min: 1, max: 2),
                             difficulty: "easy",
                             start: WayStagePlace(name: "here", at: WayCoordinate(lat: 0, lon: 0)),
                             end: WayStagePlace(name: "there", at: WayCoordinate(lat: 0, lon: 0.00898)))
        return way
    }

    private func honorStage() {
        var senses = HonorSenses()
        senses.isAppActive = { false }
        vm.cancel()
        vm = ActiveWalkViewModel(mode: .honor, way: stageWayWithMarks(), honorSenses: senses)
        settleCombineSchedulers()
    }

    private func markIDs() -> [String] {
        vm.honorMarkPins.compactMap { pin in
            if case .wayMark(let id, _) = pin.kind { return id }
            return nil
        }
    }

    func testASharedWayHasNoMarksToDraw() {
        // The setUp Way is someone's own walk: no `marks` block at all, so no
        // fix on it may ever put a service pin on the map.
        var publishes = 0
        let watch = vm.$honorMarkPins.dropFirst().sink { _ in publishes += 1 }
        begin()
        drive(fix(lon: 0, seconds: 0))
        drive(fix(lon: 300 / 111_320, seconds: 200))
        XCTAssertTrue(vm.honorMarkPins.isEmpty)
        XCTAssertEqual(publishes, 0, "nothing to draw must also mean nothing published")
        watch.cancel()
    }

    func testTheNearestMarksAreReselectedOnlyOnceTheWalkerHasMovedTwoHundredMetres() {
        honorStage()
        var publishes = 0
        let watch = vm.$honorMarkPins.dropFirst().sink { _ in publishes += 1 }
        begin()

        drive(fix(lon: 0, seconds: 0))
        XCTAssertEqual(publishes, 1, "the first fix anchors the selection")
        XCTAssertEqual(markIDs().first, "m0", "nearest to the walker comes first")

        drive(fix(lon: 50 / 111_320, seconds: 40))
        XCTAssertEqual(publishes, 1, "50 m is inside the 200 m throttle")

        drive(fix(lon: 250 / 111_320, seconds: 200))
        XCTAssertEqual(publishes, 2, "250 m from the anchor re-sorts them")
        XCTAssertEqual(markIDs().first, "m2", "the mark 50 m ahead is now the nearest")
        watch.cancel()
    }

    func testPinchingBelowThirteenHidesTheMarksAndComingBackRestoresThem() {
        honorStage()
        begin()
        drive(fix(lon: 0, seconds: 0))
        XCTAssertEqual(markIDs().count, 3, "the map starts at the follow-puck's zoom")

        // A pinch, with the walker standing still: the marks answer to the
        // camera the map reports, not to a zoom assumed on their behalf.
        vm.mapCameraDidChange(center: CLLocationCoordinate2D(latitude: 0, longitude: 0), zoom: 10.2)
        XCTAssertTrue(vm.honorMarkPins.isEmpty)

        vm.mapCameraDidChange(center: CLLocationCoordinate2D(latitude: 0, longitude: 0), zoom: 14.1)
        XCTAssertEqual(markIDs().count, 3)
    }
}
