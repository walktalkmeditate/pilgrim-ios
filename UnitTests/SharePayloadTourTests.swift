import XCTest
@testable import Pilgrim

final class SharePayloadTourTests: XCTestCase {

    private func encodeToJSON(_ payload: SharePayload) throws -> [String: Any] {
        let data = try JSONEncoder().encode(payload)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func minimalPayload(tour: SharePayload.Tour?, pauses: [SharePayload.Pause]? = nil, photos: [SharePayload.Photo]? = nil) -> SharePayload {
        var payload = SharePayload(
            stats: .init(distance: 1000, activeDuration: 600, elevationAscent: nil, elevationDescent: nil, steps: nil, meditateDuration: 0, talkDuration: 0, weatherCondition: nil, weatherTemperature: nil),
            route: [.init(lat: 35.68, lon: -105.94, alt: 2100, ts: 1000), .init(lat: 35.69, lon: -105.93, alt: 2110, ts: 1600)],
            activityIntervals: [],
            journal: nil,
            expiryDays: 90,
            units: "metric",
            startDate: "2026-08-11T08:00:00Z",
            tzIdentifier: "America/Denver",
            toggledStats: ["distance"],
            placeStart: nil, placeEnd: nil, mark: nil,
            waypoints: nil,
            photos: photos
        )
        payload.tour = tour
        payload.pauses = pauses
        return payload
    }

    func testTourEncodesSnakeCaseWithOrderedRecordings() throws {
        let tour = SharePayload.Tour(
            recordings: [
                .init(n: 1, startTs: 1100, endTs: 1400, duration: 300, kind: "spoken", transcription: nil, wpm: 120, sizeBytes: 2_400_000),
                .init(n: 2, startTs: 1450, endTs: 1500, duration: 50, kind: "ambient", transcription: nil, wpm: nil, sizeBytes: 800_000),
            ],
            trimM: 150,
            soundscapeUrl: "https://cdn.pilgrimapp.org/audio/soundscape/stream.m4a"
        )
        let json = try encodeToJSON(minimalPayload(tour: tour))
        let tourJSON = try XCTUnwrap(json["tour"] as? [String: Any])
        XCTAssertEqual(tourJSON["trim_m"] as? Int, 150)
        XCTAssertEqual(tourJSON["soundscape_url"] as? String, "https://cdn.pilgrimapp.org/audio/soundscape/stream.m4a")
        let recs = try XCTUnwrap(tourJSON["recordings"] as? [[String: Any]])
        XCTAssertEqual(recs.count, 2)
        XCTAssertEqual(recs[0]["n"] as? Int, 1)
        XCTAssertEqual(recs[0]["start_ts"] as? Int, 1100)
        XCTAssertEqual(recs[0]["end_ts"] as? Int, 1400)
        XCTAssertEqual(recs[0]["kind"] as? String, "spoken")
        XCTAssertEqual(recs[0]["size_bytes"] as? Int, 2_400_000)
        XCTAssertEqual(recs[1]["wpm"] as? Double, nil)
    }

    func testPausesEncodeSnakeCase() throws {
        let json = try encodeToJSON(minimalPayload(tour: nil, pauses: [.init(startTs: 1150, endTs: 1450)]))
        let pauses = try XCTUnwrap(json["pauses"] as? [[String: Any]])
        XCTAssertEqual(pauses[0]["start_ts"] as? Int, 1150)
        XCTAssertEqual(pauses[0]["end_ts"] as? Int, 1450)
    }

    func testAbsentTourAndPausesOmittedFromJSON() throws {
        let json = try encodeToJSON(minimalPayload(tour: nil))
        XCTAssertNil(json["tour"])
        XCTAssertNil(json["pauses"])
    }

    func testPhotoWithoutDataOmitsDataKey() throws {
        let photo = SharePayload.Photo(lat: 35.69, lon: -105.94, ts: 1200, data: nil)
        let json = try encodeToJSON(minimalPayload(tour: nil, photos: [photo]))
        let photos = try XCTUnwrap(json["photos"] as? [[String: Any]])
        XCTAssertNil(photos[0]["data"])
        XCTAssertEqual(photos[0]["ts"] as? Int, 1200)
    }
}
