import XCTest
@testable import Pilgrim

final class BackupSerializationTests: XCTestCase {

    // MARK: - Version Codes

    func testBackupV4_versionCode_isV4() {
        XCTAssertEqual(BackupV4.versionCode, "V4")
    }

    func testAllVersionCodes_areUnique() {
        let codes = [
            BackupV1.versionCode,
            BackupV2.versionCode,
            BackupV3.versionCode,
            BackupV4.versionCode
        ]
        XCTAssertEqual(Set(codes).count, codes.count)
    }

    // MARK: - BackupV4 Serialization

    func testBackupV4_encodeDecodeRoundTrip_preservesFields() throws {
        let walk = WalkDataFactory.makeWalk(
            distance: 5000,
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            endDate: DateFactory.makeDate(2024, 6, 15, 10, 0, 0),
            ascend: 50,
            descend: 30,
            activeDuration: 3600
        )
        let event = TempV4.Event(
            uuid: UUID(),
            title: "Morning Walk",
            comment: "Nice walk",
            startDate: walk.startDate,
            endDate: walk.endDate,
            workouts: [walk.uuid ?? UUID()]
        )

        let backup = BackupV4(workouts: [walk], events: [event])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupV4.self, from: data)

        XCTAssertEqual(decoded.version, "V4")
        XCTAssertEqual(decoded.workoutData.count, 1)
        XCTAssertEqual(decoded.eventData.count, 1)
        XCTAssertEqual(decoded.workoutData.first?.distance, 5000)
        XCTAssertEqual(decoded.eventData.first?.title, "Morning Walk")
    }

    func testBackupV4_encodedJSON_containsCorrectVersionKey() throws {
        let backup = BackupV4(workouts: [], events: [])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["version"] as? String, "V4")
    }

    // MARK: - Legacy asTemp Conversions

    func testV1_asTemp_mapsFieldsCorrectly() {
        let v1 = TempV1.Workout(
            uuid: UUID(),
            workoutType: 1,
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            endDate: DateFactory.makeDate(2024, 6, 15, 10, 0, 0),
            distance: 5000,
            burnedEnergy: 200,
            healthKitUUID: nil,
            locations: []
        )
        let temp = v1.asTemp
        XCTAssertEqual(temp.distance, 5000)
        XCTAssertEqual(temp.workoutType, .walking)
        XCTAssertEqual(temp.burnedEnergy, 200)
        XCTAssertFalse(temp.isRace)
        XCTAssertTrue(temp.finishedRecording)
        XCTAssertEqual(temp.pauses.count, 0)
    }

    func testV2_asTemp_preservesIsRaceAndComment() {
        let v2 = TempV2.Workout(
            uuid: UUID(),
            workoutType: 1,
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            endDate: DateFactory.makeDate(2024, 6, 15, 10, 0, 0),
            distance: 10000,
            isRace: true,
            isUserModified: true,
            comment: "Morning pilgrimage",
            burnedEnergy: 400,
            healthKitUUID: nil,
            locations: []
        )
        let temp = v2.asTemp
        XCTAssertTrue(temp.isRace)
        XCTAssertTrue(temp.isUserModified)
        XCTAssertEqual(temp.comment, "Morning pilgrimage")
    }

    func testV3_asTemp_derivesPausesFromEvents() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let end = DateFactory.makeDate(2024, 6, 15, 10, 0, 0)
        let pauseStart = DateFactory.makeDate(2024, 6, 15, 9, 20, 0)
        let pauseEnd = DateFactory.makeDate(2024, 6, 15, 9, 25, 0)

        let v3 = TempV3.Workout(
            uuid: UUID(),
            workoutType: 1,
            startDate: start,
            endDate: end,
            distance: 5000,
            steps: 6000,
            isRace: false,
            isUserModified: false,
            comment: nil,
            burnedEnergy: 200,
            healthKitUUID: nil,
            workoutEvents: [
                TempV3.WorkoutEvent(uuid: nil, eventType: 0, startDate: pauseStart, endDate: pauseStart),
                TempV3.WorkoutEvent(uuid: nil, eventType: 2, startDate: pauseEnd, endDate: pauseEnd)
            ],
            locations: [],
            heartRates: []
        )
        let temp = v3.asTemp
        XCTAssertEqual(temp.pauses.count, 1)
        XCTAssertEqual(temp.pauses.first?.startDate, pauseStart)
        XCTAssertEqual(temp.pauses.first?.endDate, pauseEnd)
        XCTAssertEqual(temp.steps, 6000)
    }
}
