import XCTest
@testable import Pilgrim

final class WalkPhotoCodableTests: XCTestCase {

    func testWalkPhoto_roundTrips() throws {
        let original = TempWalkPhoto(
            uuid: UUID(),
            localIdentifier: "ABC-123/L0/001",
            capturedAt: Date(timeIntervalSince1970: 1700000000),
            capturedLat: 35.0116,
            capturedLng: 135.7681,
            keptAt: Date(timeIntervalSince1970: 1700001000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TempWalkPhoto.self, from: data)
        XCTAssertEqual(decoded.uuid, original.uuid)
        XCTAssertEqual(decoded.localIdentifier, original.localIdentifier)
        XCTAssertEqual(decoded.capturedAt, original.capturedAt)
        XCTAssertEqual(decoded.capturedLat, original.capturedLat)
        XCTAssertEqual(decoded.capturedLng, original.capturedLng)
        XCTAssertEqual(decoded.keptAt, original.keptAt)
    }

    func testWorkout_decodesWithoutWalkPhotosKey() throws {
        let workout = TempWalk(
            uuid: UUID(),
            workoutType: .walking,
            distance: 1000,
            steps: 1500,
            startDate: Date(),
            endDate: Date(),
            burnedEnergy: nil,
            isRace: false,
            comment: nil,
            isUserModified: false,
            healthKitUUID: nil,
            finishedRecording: true,
            ascend: 0,
            descend: 0,
            activeDuration: 600,
            pauseDuration: 0,
            dayIdentifier: "20240615",
            heartRates: [],
            routeData: [],
            pauses: [],
            workoutEvents: []
        )

        let data = try JSONEncoder().encode(workout)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "_walkPhotos")
        let stripped = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(TempWalk.self, from: stripped)
        XCTAssertTrue(decoded.walkPhotos.isEmpty)
        XCTAssertEqual(decoded.distance, 1000)
    }

    func testWorkout_decodesWithWalkPhotos() throws {
        let photoUUID = UUID()
        let photo = TempWalkPhoto(
            uuid: photoUUID,
            localIdentifier: "XYZ-456/L0/001",
            capturedAt: Date(timeIntervalSince1970: 1700000000),
            capturedLat: 35.0116,
            capturedLng: 135.7681,
            keptAt: Date(timeIntervalSince1970: 1700001000)
        )
        let workout = TempWalk(
            uuid: UUID(),
            workoutType: .walking,
            distance: 2000,
            steps: 3000,
            startDate: Date(),
            endDate: Date(),
            burnedEnergy: nil,
            isRace: false,
            comment: "Walk in peace",
            isUserModified: false,
            healthKitUUID: nil,
            finishedRecording: true,
            ascend: 10,
            descend: 5,
            activeDuration: 1200,
            pauseDuration: 0,
            dayIdentifier: "20240615",
            heartRates: [],
            routeData: [],
            pauses: [],
            workoutEvents: [],
            walkPhotos: [photo]
        )

        let data = try JSONEncoder().encode(workout)
        let decoded = try JSONDecoder().decode(TempWalk.self, from: data)
        XCTAssertEqual(decoded.walkPhotos.count, 1)
        XCTAssertEqual(decoded.walkPhotos.first?.uuid, photoUUID)
        XCTAssertEqual(decoded.walkPhotos.first?.localIdentifier, "XYZ-456/L0/001")
        XCTAssertEqual(decoded.walkPhotos.first?.capturedLat, 35.0116)
    }

    func testTempWalk_fromInterface_copiesWalkPhotos() throws {
        let photoUUID = UUID()
        let photo = TempWalkPhoto(
            uuid: photoUUID,
            localIdentifier: "DEF-789/L0/001",
            capturedAt: Date(timeIntervalSince1970: 1700002000),
            capturedLat: 43.7696,
            capturedLng: 11.2558,
            keptAt: Date(timeIntervalSince1970: 1700003000)
        )
        let source = TempWalk(
            uuid: UUID(),
            workoutType: .walking,
            distance: 4000,
            steps: 5500,
            startDate: Date(),
            endDate: Date(),
            burnedEnergy: nil,
            isRace: false,
            comment: nil,
            isUserModified: false,
            healthKitUUID: nil,
            finishedRecording: true,
            ascend: 0,
            descend: 0,
            activeDuration: 2400,
            pauseDuration: 0,
            dayIdentifier: "20240615",
            heartRates: [],
            routeData: [],
            pauses: [],
            workoutEvents: [],
            walkPhotos: [photo]
        )

        let copy = TempWalk(from: source)

        XCTAssertEqual(copy.walkPhotos.count, 1)
        XCTAssertEqual(copy.walkPhotos.first?.uuid, photoUUID)
        XCTAssertEqual(copy.walkPhotos.first?.localIdentifier, "DEF-789/L0/001")
        XCTAssertEqual(copy.walkPhotos.first?.capturedLat, 43.7696)
        XCTAssertEqual(copy.walkPhotos.first?.capturedLng, 11.2558)
    }
}
