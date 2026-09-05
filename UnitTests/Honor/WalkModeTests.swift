import XCTest
@testable import Pilgrim

final class WalkModeTests: XCTestCase {

    func testHonorIsTheThirdMode() {
        XCTAssertEqual(WalkMode.allCases, [.wander, .honor, .seek])
        XCTAssertTrue(WalkMode.honor.isAvailable)
        XCTAssertEqual(WalkMode.honor.subtitle, "walk in their steps")
        XCTAssertEqual(WalkMode.honor.buttonLabel, "Choose a way")
    }

    func testHonorQuotesAreLocalized() {
        XCTAssertEqual(WalkMode.honor.quotes.count, 3)
        XCTAssertFalse(WalkMode.honor.quotes.contains(""))
        XCTAssertFalse(WalkMode.honor.quotes.contains { $0.hasPrefix("Honor.Quote") })
    }
}

extension WalkModeTests {

    func testHonorSpeaksOfAStageWhenTheWayIsOne() {
        var way = Way(id: "pilgrimage:camino-frances:0",
                      source: .pilgrimage(routeId: "camino-frances", stageIndex: 0),
                      title: "s", departedAt: Date(), tzIdentifier: nil, expires: nil,
                      route: [WayPoint(lat: 0, lon: 0, alt: nil, t: 0),
                              WayPoint(lat: 0, lon: 0.001, alt: nil, t: 60)],
                      totalDistanceMeters: 111, theirActiveSeconds: 60, moments: [], weather: nil)
        XCTAssertEqual(WalkMode.honor.subtitle(for: way), "walk in their steps",
                       "not a stage until it carries a stage block")
        way.stage = WayStage(routeId: "camino-frances", index: 0, count: 33, name: "n", theme: "t",
                             narrative: "n", closing: "c", warnings: [], distanceKm: 24.2, gainMeters: 100,
                             hours: WayStageHours(min: 5, max: 7), difficulty: "hard",
                             start: WayStagePlace(name: "a", at: WayCoordinate(lat: 0, lon: 0)),
                             end: WayStagePlace(name: "b", at: WayCoordinate(lat: 0, lon: 0.001)))
        XCTAssertEqual(WalkMode.honor.subtitle(for: way), "walk the stage")
        XCTAssertEqual(WalkMode.honor.subtitle(for: nil), "walk in their steps")
        XCTAssertEqual(WalkMode.wander.subtitle(for: way), WalkMode.wander.subtitle,
                       "only Honor's copy assumes another walker")
    }
}
