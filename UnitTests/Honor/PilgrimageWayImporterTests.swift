import XCTest
@testable import Pilgrim

final class PilgrimageWayImporterTests: XCTestCase {

    func testFixturePackageIsReadable() throws {
        XCTAssertFalse(try PilgrimageFixtures.data("stage-00.json").isEmpty)
        XCTAssertFalse(try PilgrimageFixtures.data("stage-01.json").isEmpty)
        XCTAssertFalse(try PilgrimageFixtures.data("route.json").isEmpty)
        XCTAssertFalse(try PilgrimageFixtures.data("index.json").isEmpty)
    }

    /// The build marks a route sparse when fewer than half its stages carry a
    /// curated place beyond the start and end towns — true of the Camino
    /// Francés today. The fixture must carry both fields, and one route must
    /// omit them, so the parse is exercised against an older index too.
    func testTheFixtureIndexCarriesTheSparseFlag() throws {
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try PilgrimageFixtures.data("index.json")) as? [String: Any])
        let routes = try XCTUnwrap(json["routes"] as? [[String: Any]])
        let ways = try XCTUnwrap(routes.first?["ways"] as? [String: Any])
        XCTAssertEqual(ways["placesPerStage"] as? Double, 0.4)
        XCTAssertEqual(ways["sparse"] as? Bool, true)
        let older = try XCTUnwrap(routes.last?["ways"] as? [String: Any])
        XCTAssertNil(older["sparse"], "an index written before the flag existed")
        XCTAssertNil(older["placesPerStage"])
    }

    func testAStageWayCarriesMarksAndAStageBlock() throws {
        let stage = WayStage(
            routeId: "camino-frances", index: 0, count: 33,
            name: "Saint-Jean-Pied-de-Port to Roncesvalles", theme: "Initiation",
            narrative: "The Pyrenees are …", closing: "You crossed a border on foot.",
            warnings: ["The Napoleon Route closes in winter."],
            distanceKm: 24.2, gainMeters: 1419,
            hours: WayStageHours(min: 7, max: 9), difficulty: "hard",
            start: WayStagePlace(name: "Saint-Jean-Pied-de-Port", at: WayCoordinate(lat: 43.163, lon: -1.236)),
            end: WayStagePlace(name: "Roncesvalles", at: WayCoordinate(lat: 43.01, lon: -1.319)))
        let mark = WayMark(id: "wp-fuente-roldan", kind: .water, name: "Fuente de Roldán",
                           at: WayCoordinate(lat: 43.1, lon: -1.3), frac: 0.42, offLineMeters: 40)
        var moment = WayMoment(id: "wp-orisson", frac: 0.3, at: WayCoordinate(lat: 0, lon: 0.0027),
                               kind: .waypoint(label: "Vierge d'Orisson", icon: "building.columns"))
        moment.text = "A shepherd carried this Madonna up from Lourdes."
        moment.names = ["fr": "Vierge d'Orisson"]
        moment.sitMinutes = 5
        moment.pin = WayCoordinate(lat: 0, lon: 0.0028)
        var way = Way(id: "pilgrimage:camino-frances:0",
                      source: .pilgrimage(routeId: "camino-frances", stageIndex: 0),
                      title: stage.name, departedAt: Date(timeIntervalSince1970: 1_700_000_000),
                      tzIdentifier: "Europe/Madrid", expires: nil,
                      route: [WayPoint(lat: 0, lon: 0, alt: nil, t: 0),
                              WayPoint(lat: 0, lon: 0.00898, alt: nil, t: 28_800)],
                      totalDistanceMeters: 1000, theirActiveSeconds: 28_800,
                      moments: [moment], weather: nil)
        way.marks = [mark]
        way.stage = stage

        let data = try JSONEncoder().encode(way)
        let round = try JSONDecoder().decode(Way.self, from: data)
        XCTAssertEqual(round, way)
        XCTAssertEqual(round.stage?.hours.max, 9)
        XCTAssertEqual(round.marks?.first?.kind, .water)
        XCTAssertEqual(round.moments.first?.sitMinutes, 5)
        XCTAssertEqual(round.moments.first?.pin, WayCoordinate(lat: 0, lon: 0.0028))
    }

    /// A `way.json` written before this slice must still decode, as an
    /// unmarked, unstaged Way.
    func testAWayWrittenBeforeStagesStillDecodes() throws {
        let json = """
        {"id":"share:Qoi4YmPHLN",
         "source":{"share":{"id":"Qoi4YmPHLN","pageURL":"https://walk.pilgrimapp.org/Qoi4YmPHLN"}},
         "title":"Rúa do Franco → Obradoiro","departedAt":"2026-08-01T07:00:00Z",
         "expires":"2099-01-01T00:00:00Z",
         "route":[{"lat":42.88,"lon":-8.545,"t":0},{"lat":42.88,"lon":-8.540,"t":400}],
         "totalDistanceMeters":420,"theirActiveSeconds":400,
         "moments":[{"id":"waypoint-1","frac":0.5,"kind":{"waypoint":{"label":"Oak","icon":"leaf"}}}]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let way = try decoder.decode(Way.self, from: Data(json.utf8))
        XCTAssertNil(way.marks)
        XCTAssertNil(way.stage)
        XCTAssertNil(way.moments[0].text)
        XCTAssertNil(way.moments[0].pin)
    }

    func testTheStoreAcceptsStageIdsAndRefusesEverythingElse() throws {
        XCTAssertTrue(WayStore.isValidId("pilgrimage:camino-frances:0"))
        XCTAssertTrue(WayStore.isValidId("pilgrimage:camino-frances:199"))
        XCTAssertFalse(WayStore.isValidId("pilgrimage"))
        XCTAssertFalse(WayStore.isValidId("pilgrimage:../etc:0"))
        XCTAssertFalse(WayStore.isValidId("pilgrimage:Camino:0"), "slugs are lowercase")
        XCTAssertFalse(WayStore.isValidId("pilgrimage:camino-frances:1000"))
        XCTAssertTrue(WayStore.isValidRouteId("camino-frances"))
        XCTAssertFalse(WayStore.isValidRouteId("../etc/passwd"))
        XCTAssertEqual(WayStore.stageWayId(routeId: "camino-frances", stageIndex: 7),
                       "pilgrimage:camino-frances:7")
    }

    func testAStageWayRoundTripsThroughTheStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let store = WayStore(baseDirectory: dir)
        var way = Way(id: "pilgrimage:camino-frances:0",
                      source: .pilgrimage(routeId: "camino-frances", stageIndex: 0),
                      title: "s", departedAt: Date(), tzIdentifier: nil, expires: nil,
                      route: [WayPoint(lat: 0, lon: 0, alt: nil, t: 0),
                              WayPoint(lat: 0, lon: 0.001, alt: nil, t: 60)],
                      totalDistanceMeters: 111, theirActiveSeconds: 60, moments: [], weather: nil)
        way.marks = []
        try store.save(way)
        XCTAssertEqual(store.load(id: "pilgrimage:camino-frances:0")?.id, way.id)
        let packageDir = try XCTUnwrap(store.pilgrimageDirectory(for: "camino-frances"))
        XCTAssertTrue(packageDir.path.hasSuffix("pilgrimage/camino-frances"))
        XCTAssertNil(store.pilgrimageDirectory(for: "../etc"))
        XCTAssertTrue(store.list().contains { $0.id == way.id },
                      "the package folder is not a way id, so list() steps over it")
    }
}
