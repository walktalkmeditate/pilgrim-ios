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
         "meditation":[{"start_frac":0.5,"end_frac":0.5,"duration":720},{"start_frac":0.5,"end_frac":0.5}],
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
                                          .meditation(minutes: 7, isEstimate: true)],
                       "second sitting has no duration: estimated from the 400 s gap around frac 0.5")
    }

    func testExpiredManifestIsReturnedToTrail() throws {
        XCTAssertThrowsError(try WayImporter.way(from: manifest(expires: "2000-01-01T00:00:00Z"), shareId: "x", now: Date())) {
            XCTAssertEqual($0 as? WayError, .returnedToTrail)
        }
    }

    func testMalformedShareIdIsNotFoundBeforeAnyNetwork() async {
        let store = WayStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
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
}
