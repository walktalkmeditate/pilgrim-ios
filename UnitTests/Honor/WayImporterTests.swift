import XCTest
@testable import Pilgrim

final class WayImporterTests: XCTestCase {

    /// `expires` carries milliseconds because the worker's Date.toISOString() does.
    private func manifest(expires: String = "2099-01-01T00:00:00.000Z", extraEncounter: String = "") throws -> TourManifest {
        let json = """
        {"v":1,"theme":"light","time_bucket":"morning","place_start":"Rúa do Franco","place_end":"Obradoiro",
         "weather_condition":"rain","weather_temperature":9,"units":"metric","start_date":"2026-08-01T07:00:00Z",
         "tz_identifier":"Europe/Madrid","expires":"\(expires)",
         "route":[{"lat":42.88,"lon":-8.545,"alt":250,"ts":1000},{"lat":42.88,"lon":-8.540,"alt":250,"ts":1400},{"lat":42.88,"lon":-8.535,"alt":250,"ts":1600}],
         "total_distance_m":820,
         "encounters":[{"type":"departure","frac":0},
           {"type":"voice","frac":0.5,"end_frac":0.6,"n":1,"duration":40,"dwell":30,"lat":42.8801,"lon":-8.5401},
           {"type":"ambience","frac":0.7,"end_frac":0.75,"n":2,"duration":20,"dwell":20},
           {"type":"photo","frac":0.8,"n":1,"dwell":5},
           {"type":"rest","frac":0.9,"minutes":4,"dwell":4}\(extraEncounter),
           {"type":"arrival","frac":1}],
         "meditation":[{"start_frac":0.5,"end_frac":0.5,"duration":720},{"start_frac":0.75,"end_frac":0.75}],
         "activity_segments":[],"stats":{"active_duration":540}}
        """
        return try JSONDecoder().decode(TourManifest.self, from: Data(json.utf8))
    }

    func testBuildsAWayFromTheManifest() throws {
        let way = try WayImporter.way(from: manifest(), shareId: "Qoi4YmPHLN", now: Date())
        XCTAssertEqual(way.id, "share:Qoi4YmPHLN")
        XCTAssertEqual(way.title, "Rúa do Franco → Obradoiro")
        XCTAssertEqual(way.route.map(\.t), [0, 400, 600])
        XCTAssertEqual(way.theirActiveSeconds, 540)
        XCTAssertEqual(way.weather, WayWeather(condition: "rain", temperatureC: 9))
        let voice = try XCTUnwrap(way.moments.first { $0.id == "voice-1" })
        XCTAssertEqual(voice.at, WayCoordinate(lat: 42.8801, lon: -8.5401))
        guard case .voice(_, _, let kind, let media) = voice.kind else { return XCTFail() }
        XCTAssertEqual(kind, .spoken)
        XCTAssertEqual(media, .file("audio/1.m4a"))
        let ambience = try XCTUnwrap(way.moments.first { $0.id == "voice-2" })
        XCTAssertNil(ambience.at, "older shares carry no coordinate")
        guard case .voice(_, _, .ambient, .file("audio/2.m4a")) = ambience.kind else { return XCTFail() }
        XCTAssertEqual(way.moments.first { $0.id == "photo-1" }?.kind, .photo(media: .file("photos/1.jpg")))
        let sits = way.moments.filter { if case .meditation = $0.kind { return true }; return false }
        XCTAssertEqual(sits.map(\.kind), [.meditation(minutes: 12, isEstimate: false),
                                          .meditation(minutes: 3, isEstimate: true)],
                       "second sitting has no duration: estimated from the 200 s gap of the segment " +
                       "containing frac 0.75 (interior to the second leg, which spans frac 0.5 to 1)")
    }

    func testExpiredManifestIsReturnedToTrail() throws {
        XCTAssertThrowsError(try WayImporter.way(from: manifest(expires: "2000-01-01T00:00:00Z"), shareId: "x", now: Date())) {
            XCTAssertEqual($0 as? WayError, .returnedToTrail)
        }
    }

    func testMalformedShareIdIsNotFoundBeforeAnyNetwork() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let store = WayStore(baseDirectory: dir)
        do {
            _ = try await WayImporter(store: store).importShare(id: "../etc")
            XCTFail("expected notFound")
        } catch {
            XCTAssertEqual(error as? WayError, .notFound)
        }
    }

    func testOversizedManifestIsUnavailable() throws {
        let many = (0..<300).map { _ in ",{\"type\":\"waypoint\",\"frac\":0.5,\"label\":\"x\",\"icon\":\"leaf\",\"dwell\":3}" }.joined()
        XCTAssertThrowsError(try WayImporter.way(from: manifest(extraEncounter: many), shareId: "x", now: Date())) {
            XCTAssertEqual($0 as? WayError, .unavailable)
        }
    }

    func testDepartureArrivalAndUnknownTypesAreSkipped() throws {
        let way = try WayImporter.way(from: manifest(extraEncounter: ",{\"type\":\"beacon\",\"frac\":0.95}"), shareId: "x", now: Date())
        XCTAssertEqual(way.moments.count, 6, "departure, arrival, and the unknown 'beacon' type are all skipped")
        XCTAssertTrue(way.moments.allSatisfy { moment in
            if case .waypoint = moment.kind { return false }
            return true
        }, "the base fixture carries no waypoint encounter")
    }

    /// A manifest with just the fields `WayImporter.way(from:)` reads, every one
    /// inside its valid range by default, so each parameter below isolates exactly
    /// one field for `testOutOfRangeNumbersAreUnavailable`.
    private func manifestJSON(
        ts0: String = "1000", ts1: String = "1400", routeLat: String = "42.88",
        encounterFrac: String = "0.5", encounterN: String = "1",
        sittingDuration: String = "720", weatherTemperature: String = "9"
    ) -> String {
        """
        {"v":1,"start_date":"2026-08-01T07:00:00Z","expires":"2099-01-01T00:00:00.000Z",
         "weather_temperature":\(weatherTemperature),
         "route":[{"lat":\(routeLat),"lon":-8.545,"alt":250,"ts":\(ts0)},{"lat":42.88,"lon":-8.540,"alt":250,"ts":\(ts1)}],
         "encounters":[{"type":"voice","frac":\(encounterFrac),"end_frac":0.6,"n":\(encounterN),"duration":40,"lat":42.8801,"lon":-8.5401}],
         "meditation":[{"start_frac":0.25,"end_frac":0.25,"duration":\(sittingDuration)}],
         "stats":{"active_duration":540}}
        """
    }

    private func decode(_ json: String) throws -> TourManifest {
        try JSONDecoder().decode(TourManifest.self, from: Data(json.utf8))
    }

    func testOutOfRangeNumbersAreUnavailable() throws {
        let cases: [(name: String, json: String)] = [
            // ts0/ts1 are Int.min/Int.max: individually valid Int64s, so decoding
            // succeeds; only the sane-window check stops `ts - ts0` from trapping.
            ("ts overflow pair", manifestJSON(ts0: "-9223372036854775808", ts1: "9223372036854775807")),
            ("duration", manifestJSON(sittingDuration: "1e300")),
            ("weather_temperature", manifestJSON(weatherTemperature: "1e300")),
            ("lat", manifestJSON(routeLat: "91")),
            ("frac", manifestJSON(encounterFrac: "1.5")),
            ("n", manifestJSON(encounterN: "0"))
        ]
        for testCase in cases {
            let manifest = try decode(testCase.json)
            XCTAssertThrowsError(try WayImporter.way(from: manifest, shareId: "x", now: Date()), testCase.name) { error in
                XCTAssertEqual(error as? WayError, .unavailable, testCase.name)
            }
        }
    }

    func testMeditationCountIsCapped() throws {
        let sitting = "{\"start_frac\":0.25,\"end_frac\":0.25,\"duration\":60}"
        let many = Array(repeating: sitting, count: WayImporter.maxEncounters + 1).joined(separator: ",")
        let json = """
        {"v":1,"start_date":"2026-08-01T07:00:00Z","expires":"2099-01-01T00:00:00.000Z",
         "route":[{"lat":42.88,"lon":-8.545,"alt":250,"ts":1000},{"lat":42.88,"lon":-8.540,"alt":250,"ts":1400}],
         "encounters":[],"meditation":[\(many)],"stats":{"active_duration":540}}
        """
        let manifest = try decode(json)
        XCTAssertThrowsError(try WayImporter.way(from: manifest, shareId: "x", now: Date())) {
            XCTAssertEqual($0 as? WayError, .unavailable)
        }
    }

    func testShareIdShapeAcceptsTenSafeCharacters() {
        XCTAssertTrue(WayImporter.isShareId("Qoi4YmPHLN"))
        XCTAssertFalse(WayImporter.isShareId("Qoi4YmPHL"), "9 characters")
        XCTAssertFalse(WayImporter.isShareId("Qoi4YmPHLNx"), "11 characters")
        XCTAssertFalse(WayImporter.isShareId("Qoi4YmPH/N"), "a slash in place of a safe character")
    }

    func testUntrustedFreeTextIsBounded() throws {
        let long = String(repeating: "x", count: 500)
        let extra = ",{\"type\":\"waypoint\",\"frac\":0.4,\"label\":\"\(long)\",\"icon\":\"\(long)\"}"
        let json = try manifest(extraEncounter: extra)
        let way = try WayImporter.way(from: json, shareId: "Qoi4YmPHLN", now: Date())

        let waypoint = try XCTUnwrap(way.moments.first { $0.id == "waypoint-1" })
        guard case .waypoint(let label, let icon) = waypoint.kind else { return XCTFail("expected a waypoint moment") }
        XCTAssertEqual(label.count, WayImporter.maxLabelCharacters, "a manifest label reaches a map callout — bound it at the door")
        XCTAssertEqual(icon.count, WayImporter.maxIconCharacters)
    }

    func testWeatherConditionIsBounded() throws {
        let long = String(repeating: "y", count: 500)
        let json = """
        {"v":1,"start_date":"2026-08-01T07:00:00Z","expires":"2099-01-01T00:00:00.000Z",
         "weather_condition":"\(long)",
         "route":[{"lat":42.88,"lon":-8.545,"alt":250,"ts":1000},{"lat":42.88,"lon":-8.540,"alt":250,"ts":1400}],
         "encounters":[],"meditation":[],"stats":{"active_duration":540}}
        """
        let way = try WayImporter.way(from: decode(json), shareId: "Qoi4YmPHLN", now: Date())
        XCTAssertEqual(way.weather?.condition.count, WayImporter.maxWeatherConditionCharacters)
    }

    /// The same floor `OwnWalkWayBuilder` applies: a route with no real
    /// length is not a Way anyone can follow.
    func testRouteShorterThanTheFloorIsUnavailable() throws {
        let json = """
        {"v":1,"start_date":"2026-08-01T07:00:00Z","expires":"2099-01-01T00:00:00.000Z",
         "route":[{"lat":42.88,"lon":-8.545,"alt":250,"ts":1000},{"lat":42.88,"lon":-8.54501,"alt":250,"ts":1400}],
         "encounters":[],"meditation":[],"stats":{"active_duration":540}}
        """
        XCTAssertThrowsError(try WayImporter.way(from: decode(json), shareId: "Qoi4YmPHLN", now: Date())) {
            XCTAssertEqual($0 as? WayError, .unavailable)
        }
    }
}

extension WayImporterTests {

    func testActivitySegmentsBecomeSpansAndUnknownKindsAreSkipped() throws {
        let json = """
        {"v":1,"place_start":"A","place_end":"B","start_date":"2026-08-01T07:00:00Z","expires":"2099-01-01T00:00:00.000Z",
         "route":[{"lat":42.88,"lon":-8.545,"alt":250,"ts":1000},{"lat":42.88,"lon":-8.540,"alt":250,"ts":1400},{"lat":42.88,"lon":-8.535,"alt":250,"ts":1600}],
         "encounters":[],"meditation":[],
         "activity_segments":[{"kind":"talk","start_frac":0.1,"end_frac":0.2},{"kind":"meditation","start_frac":0.5,"end_frac":0.6},{"kind":"dance","start_frac":0.7,"end_frac":0.8}],
         "stats":{"active_duration":540}}
        """
        let manifest = try JSONDecoder().decode(TourManifest.self, from: Data(json.utf8))
        let way = try WayImporter.way(from: manifest, shareId: "Qoi4YmPHLN", now: Date())
        XCTAssertEqual(way.spans?.map(\.kind), [.talking, .meditating])
        XCTAssertEqual(way.spans?.first?.startFrac ?? 0, 0.1, accuracy: 1e-9)
    }

    func testActivitySegmentOutOfRangeIsUnavailable() throws {
        let json = """
        {"v":1,"start_date":"2026-08-01T07:00:00Z","expires":"2099-01-01T00:00:00.000Z",
         "route":[{"lat":42.88,"lon":-8.545,"alt":250,"ts":1000},{"lat":42.88,"lon":-8.535,"alt":250,"ts":1600}],
         "encounters":[],"meditation":[],"activity_segments":[{"kind":"talk","start_frac":0.1,"end_frac":1.5}]}
        """
        let manifest = try JSONDecoder().decode(TourManifest.self, from: Data(json.utf8))
        XCTAssertThrowsError(try WayImporter.way(from: manifest, shareId: "Qoi4YmPHLN", now: Date())) {
            XCTAssertEqual($0 as? WayError, .unavailable)
        }
    }
}
