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

extension PilgrimageWayImporterTests {

    private func stage00() throws -> Way {
        try PilgrimageWayImporter.way(from: PilgrimageFixtures.data("stage-00.json"),
                                      routeId: "camino-frances", stageIndex: 0)
    }

    func testDecodesTheFixtureStage() throws {
        let way = try stage00()
        XCTAssertEqual(way.id, "pilgrimage:camino-frances:0")
        XCTAssertEqual(way.source, .pilgrimage(routeId: "camino-frances", stageIndex: 0))
        XCTAssertEqual(way.title, "Saint-Jean-Pied-de-Port to Roncesvalles")
        XCTAssertNil(way.expires, "a route never returns to the trail on its own")
        XCTAssertNil(way.weather)
        XCTAssertEqual(way.route.count, 11)
        XCTAssertEqual(way.totalDistanceMeters, 1000, accuracy: 5)
        XCTAssertEqual(way.theirActiveSeconds, 28_800)
        XCTAssertEqual(way.tzIdentifier, "Europe/Madrid")
    }

    func testMomentsCarryTextLocalNamesSitMinutesAndAPin() throws {
        let way = try stage00()
        XCTAssertEqual(way.moments.map(\.id), ["wp-saint-jean", "wp-orisson", "wp-roncesvalles"])
        let orisson = try XCTUnwrap(way.moments.first { $0.id == "wp-orisson" })
        guard case .waypoint(let label, let icon) = orisson.kind else { return XCTFail("kind") }
        XCTAssertEqual(label, "Vierge d'Orisson")
        XCTAssertEqual(icon, "building.columns")
        XCTAssertEqual(orisson.text, "A shepherd carried this Madonna up from Lourdes.")
        XCTAssertEqual(orisson.names?["eu"], "Orissongo Ama Birjina")
        XCTAssertEqual(orisson.sitMinutes, 5)
        XCTAssertEqual(orisson.at, WayCoordinate(lat: 0, lon: 0.002694), "triggers fire on the line")
        XCTAssertEqual(orisson.pin, WayCoordinate(lat: 0, lon: 0.0027), "the pin draws off it")
        XCTAssertNil(way.moments.first { $0.id == "wp-saint-jean" }?.text)
    }

    func testMarksAndTheStageBlockSurvive() throws {
        let way = try stage00()
        let marks = try XCTUnwrap(way.marks)
        XCTAssertEqual(marks.map(\.id), ["wp-fuente-roldan", "wp-fuente-lejos", "wp-bar-orisson"])
        XCTAssertEqual(marks[0].kind, .water)
        XCTAssertEqual(marks[0].name, "Fuente de Roldán")
        XCTAssertEqual(marks[0].offLineMeters, 12)
        XCTAssertEqual(marks[2].kind, .food)
        let stage = try XCTUnwrap(way.stage)
        XCTAssertEqual(stage.routeId, "camino-frances")
        XCTAssertEqual(stage.index, 0)
        XCTAssertEqual(stage.count, 2)
        XCTAssertEqual(stage.theme, "Initiation")
        XCTAssertEqual(stage.closing, "You crossed a border on foot. Few things are still done this way.")
        XCTAssertEqual(stage.warnings, ["The Napoleon Route closes in winter."])
        XCTAssertEqual(stage.distanceKm, 24.2)
        XCTAssertEqual(stage.gainMeters, 1419)
        XCTAssertEqual(stage.hours, WayStageHours(min: 7, max: 9))
        XCTAssertEqual(stage.difficulty, "hard")
        XCTAssertEqual(stage.end.name, "Roncesvalles")
    }

    func testTheStageMustMatchTheRouteAndIndexItWasFetchedFor() throws {
        let data = try PilgrimageFixtures.data("stage-00.json")
        XCTAssertThrowsError(try PilgrimageWayImporter.way(from: data, routeId: "camino-frances", stageIndex: 4)) {
            XCTAssertEqual($0 as? PilgrimageError, .notWalkable)
        }
        XCTAssertThrowsError(try PilgrimageWayImporter.way(from: data, routeId: "camino-norte", stageIndex: 0)) {
            XCTAssertEqual($0 as? PilgrimageError, .notWalkable)
        }
        XCTAssertThrowsError(try PilgrimageWayImporter.way(from: data, routeId: "../etc", stageIndex: 0)) {
            XCTAssertEqual($0 as? PilgrimageError, .notWalkable)
        }
    }

    /// One field out of range at a time; each `from` is anchored with enough
    /// surrounding context to match exactly one place in the fixture, so a
    /// case can never pass because a *different* field's guard fired first.
    /// Each must be refused before any `Int(_:)` conversion, the way
    /// `WayImporter.validate` does.
    func testOutOfRangeStageFieldsAreNotWalkable() throws {
        let base = String(data: try PilgrimageFixtures.data("stage-00.json"), encoding: .utf8)!
        let cases: [(name: String, from: String, to: String)] = [
            ("moment frac above 1", "\"frac\": 0.3,\n      \"kind\": \"waypoint\"",
             "\"frac\": 1.4,\n      \"kind\": \"waypoint\""),
            ("route point latitude off Earth", "\"lat\": 0, \"lon\": 0.002694, \"alt\": 700",
             "\"lat\": 991, \"lon\": 0.002694, \"alt\": 700"),
            ("moment at latitude off Earth", "\"at\": { \"lat\": 0, \"lon\": 0.002694 },\n      \"pin\"",
             "\"at\": { \"lat\": 991, \"lon\": 0.002694 },\n      \"pin\""),
            ("moment pin longitude off Earth", "\"pin\": { \"lat\": 0, \"lon\": 0.002700 }",
             "\"pin\": { \"lat\": 0, \"lon\": 999 }"),
            ("mark at latitude off Earth",
             "\"at\": { \"lat\": 0, \"lon\": 0.002694 }, \"frac\": 0.3, \"offLineMeters\": 20 }",
             "\"at\": { \"lat\": 991, \"lon\": 0.002694 }, \"frac\": 0.3, \"offLineMeters\": 20 }"),
            ("mark frac above 1", "\"frac\": 0.7, \"offLineMeters\": 250", "\"frac\": 1.4, \"offLineMeters\": 250"),
            ("sitMinutes absurd", "\"sitMinutes\": 5", "\"sitMinutes\": 999999999"),
            ("distanceKm absurd", "\"distanceKm\": 24.2,", "\"distanceKm\": 1e300,"),
            ("stage count over 200", "\"count\": 2,", "\"count\": 900,"),
            ("mark frac negative", "\"frac\": 0.5, \"offLineMeters\": 12", "\"frac\": -0.5, \"offLineMeters\": 12"),
            ("hours not finite", "\"hours\": { \"min\": 7, \"max\": 9 },", "\"hours\": { \"min\": 7, \"max\": 1e400 },")
        ]
        for testCase in cases {
            let json = base.replacingOccurrences(of: testCase.from, with: testCase.to)
            XCTAssertNotEqual(json, base, "\(testCase.name): the fixture no longer contains that text")
            XCTAssertThrowsError(try PilgrimageWayImporter.way(from: Data(json.utf8),
                                                              routeId: "camino-frances", stageIndex: 0),
                                 testCase.name) {
                XCTAssertEqual($0 as? PilgrimageError, .notWalkable, testCase.name)
            }
        }
    }

    func testFreeTextIsCappedAtParseTime() throws {
        let base = String(data: try PilgrimageFixtures.data("stage-00.json"), encoding: .utf8)!
        let long = String(repeating: "a", count: 5000)
        let json = base
            .replacingOccurrences(of: "\"theme\": \"Initiation\"", with: "\"theme\": \"\(long)\"")
            .replacingOccurrences(of: "\"A shepherd carried this Madonna up from Lourdes.\"", with: "\"\(long)\"")
        let way = try PilgrimageWayImporter.way(from: Data(json.utf8), routeId: "camino-frances", stageIndex: 0)
        XCTAssertEqual(way.stage?.theme.count, 80)
        XCTAssertEqual(way.moments.first { $0.id == "wp-orisson" }?.text?.count, 600)
    }

    func testTooManyMomentsOrMarksIsNotWalkable() throws {
        let base = String(data: try PilgrimageFixtures.data("stage-00.json"), encoding: .utf8)!
        let extraMark = ",{ \"id\": \"x\", \"kind\": \"water\", \"name\": \"x\", \"at\": { \"lat\": 0, \"lon\": 0 }, \"frac\": 0.1, \"offLineMeters\": 5 }"
        let many = String(repeating: extraMark, count: PilgrimageWayImporter.maxMarks)
        let json = base.replacingOccurrences(of: "\"offLineMeters\": 20 }\n  ],", with: "\"offLineMeters\": 20 }\(many)\n  ],")
        XCTAssertThrowsError(try PilgrimageWayImporter.way(from: Data(json.utf8),
                                                          routeId: "camino-frances", stageIndex: 0)) {
            XCTAssertEqual($0 as? PilgrimageError, .notWalkable)
        }
    }

    func testUnknownMarkKindsAndMomentKindsAreSkippedNotFatal() throws {
        let base = String(data: try PilgrimageFixtures.data("stage-00.json"), encoding: .utf8)!
        let json = base
            .replacingOccurrences(of: "\"kind\": \"food\"", with: "\"kind\": \"helipad\"")
            .replacingOccurrences(of: "\"frac\": 0.0,\n      \"kind\": \"waypoint\"",
                                  with: "\"frac\": 0.0,\n      \"kind\": \"shrine\"")
        XCTAssertNotEqual(json, base)
        let way = try PilgrimageWayImporter.way(from: Data(json.utf8), routeId: "camino-frances", stageIndex: 0)
        XCTAssertEqual(way.marks?.map(\.id), ["wp-fuente-roldan", "wp-fuente-lejos"])
        XCTAssertEqual(way.moments.map(\.id), ["wp-orisson", "wp-roncesvalles"],
                       "an unknown moment kind is skipped, not fatal")
    }

    /// The dataset's stage files omit `tzIdentifier` entirely — no route in
    /// the build carries a time zone — and carry a top-level `schemaVersion`
    /// the importer has no field for. The fixtures both carry a
    /// `tzIdentifier`, so this is the only place either fact is exercised.
    func testDecodesAStageFileMissingTzIdentifierWithAnUnknownSchemaVersionKey() throws {
        let base = String(data: try PilgrimageFixtures.data("stage-00.json"), encoding: .utf8)!
        let json = base
            .replacingOccurrences(of: "\"tzIdentifier\": \"Europe/Madrid\",\n", with: "")
            .replacingOccurrences(of: "\"id\": \"pilgrimage:camino-frances:0\",",
                                  with: "\"schemaVersion\": 1,\n  \"id\": \"pilgrimage:camino-frances:0\",")
        XCTAssertNotEqual(json, base)
        let way = try PilgrimageWayImporter.way(from: Data(json.utf8), routeId: "camino-frances", stageIndex: 0)
        XCTAssertNil(way.tzIdentifier)
    }

    func testDecodesTheRouteFile() throws {
        let route = try PilgrimageWayImporter.route(from: PilgrimageFixtures.data("route.json"))
        XCTAssertEqual(route.id, "camino-frances")
        XCTAssertEqual(route.name, "Camino de Santiago (Francés)")
        XCTAssertEqual(route.names["gl"], "Camiño de Santiago (Francés)")
        XCTAssertEqual(route.country, "ES")
        XCTAssertEqual(route.stageCount, 2)
        XCTAssertEqual(route.distanceKm, 46.1)
        XCTAssertEqual(route.summary, "The most walked of the caminos.")
        XCTAssertEqual(route.stages.map(\.index), [0, 1])
        XCTAssertEqual(route.stages[0].difficulty, "hard")
        XCTAssertEqual(route.stages[1].hours, WayStageHours(min: 5, max: 7))
    }

    func testARouteFileWhoseNumbersAreOutOfRangeIsNotWalkable() throws {
        let base = String(data: try PilgrimageFixtures.data("route.json"), encoding: .utf8)!
        for (from, to) in [("\"stageCount\": 2", "\"stageCount\": 0"),
                           ("\"distanceKm\": 46.1", "\"distanceKm\": 99999"),
                           ("\"id\": \"camino-frances\"", "\"id\": \"../etc\"")] {
            let json = base.replacingOccurrences(of: from, with: to)
            XCTAssertNotEqual(json, base)
            XCTAssertThrowsError(try PilgrimageWayImporter.route(from: Data(json.utf8))) {
                XCTAssertEqual($0 as? PilgrimageError, .notWalkable)
            }
        }
    }

    /// The manager downloads and saves each stage positionally — stage 0,
    /// then 1, then 2 — and the route screen keys a tapped row on `route.json`'s
    /// own `index`. 1-based indices would hand every tapped row the *next*
    /// stage's Way.
    func testOneBasedStageIndicesAreNotWalkable() throws {
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: try PilgrimageFixtures.data("route.json")) as? [String: Any])
        var stages = try XCTUnwrap(obj["stages"] as? [[String: Any]])
        for index in stages.indices {
            let current = try XCTUnwrap(stages[index]["index"] as? Int)
            stages[index]["index"] = current + 1
        }
        obj["stages"] = stages
        let json = try JSONSerialization.data(withJSONObject: obj)
        XCTAssertThrowsError(try PilgrimageWayImporter.route(from: json)) {
            XCTAssertEqual($0 as? PilgrimageError, .notWalkable)
        }
    }

    /// A duplicate index leaves one saved stage unreachable and hands its
    /// row to the stage that does carry that index instead.
    func testADuplicateStageIndexIsNotWalkable() throws {
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: try PilgrimageFixtures.data("route.json")) as? [String: Any])
        var stages = try XCTUnwrap(obj["stages"] as? [[String: Any]])
        stages[1]["index"] = 0
        obj["stages"] = stages
        let json = try JSONSerialization.data(withJSONObject: obj)
        XCTAssertThrowsError(try PilgrimageWayImporter.route(from: json)) {
            XCTAssertEqual($0 as? PilgrimageError, .notWalkable)
        }
    }

    func testEveryErrorHasItsOwnLine() {
        XCTAssertEqual(PilgrimageCopy.line(for: .notWalkable), "this route isn't walkable yet")
        XCTAssertEqual(PilgrimageCopy.line(for: .incomplete), "the download didn't finish")
        XCTAssertEqual(PilgrimageCopy.line(for: .walkInProgress), "finish your walk first")
        XCTAssertEqual(PilgrimageCopy.line(for: .catalogUnreachable), "the routes are out of reach right now")
        XCTAssertEqual(PilgrimageCopy.line(for: .diskFull),
                       HonorImportCopy.line(for: .failed(.diskFull)),
                       "disk full keeps the copy the share importer already ships")
    }
}
