import XCTest
@testable import Pilgrim

final class MigrationTests: XCTestCase {

    // MARK: - V1 Migration

    func testV1_asTemp_setsDefaultsForMissingFields() {
        let v1 = TempV1.Workout(
            uuid: UUID(),
            workoutType: 1,
            startDate: DateFactory.makeDate(2024, 1, 15, 8, 0, 0),
            endDate: DateFactory.makeDate(2024, 1, 15, 9, 0, 0),
            distance: 3000,
            burnedEnergy: 150,
            healthKitUUID: nil,
            locations: []
        )
        let temp = v1.asTemp
        XCTAssertNil(temp.steps)
        XCTAssertNil(temp.comment)
        XCTAssertFalse(temp.isRace)
        XCTAssertFalse(temp.isUserModified)
        XCTAssertTrue(temp.finishedRecording)
        XCTAssertEqual(temp.pauseDuration, 0)
        XCTAssertEqual(temp.talkDuration, 0)
        XCTAssertEqual(temp.meditateDuration, 0)
        XCTAssertEqual(temp.pauses.count, 0)
        XCTAssertEqual(temp.workoutEvents.count, 0)
        XCTAssertEqual(temp.voiceRecordings.count, 0)
    }

    func testV1_asTemp_convertsRouteData() {
        let location = TempV1.RouteDataSample(
            uuid: UUID(),
            timestamp: DateFactory.makeDate(2024, 1, 15, 8, 5, 0),
            latitude: 48.8566,
            longitude: 2.3522,
            altitude: 35,
            speed: 1.4,
            direction: 90
        )
        let v1 = TempV1.Workout(
            uuid: UUID(),
            workoutType: 1,
            startDate: DateFactory.makeDate(2024, 1, 15, 8, 0, 0),
            endDate: DateFactory.makeDate(2024, 1, 15, 9, 0, 0),
            distance: 3000,
            burnedEnergy: 150,
            healthKitUUID: nil,
            locations: [location]
        )
        let temp = v1.asTemp
        XCTAssertEqual(temp.routeData.count, 1)
        XCTAssertEqual(temp.routeData.first?.latitude, 48.8566)
        XCTAssertEqual(temp.routeData.first?.horizontalAccuracy, 0)
        XCTAssertEqual(temp.routeData.first?.verticalAccuracy, 0)
    }

    // MARK: - V2 Migration

    func testV2_asTemp_carriesOverAllFields() {
        let v2 = TempV2.Workout(
            uuid: UUID(),
            workoutType: 1,
            startDate: DateFactory.makeDate(2024, 3, 20, 7, 0, 0),
            endDate: DateFactory.makeDate(2024, 3, 20, 8, 30, 0),
            distance: 8000,
            isRace: true,
            isUserModified: true,
            comment: "Pilgrimage walk",
            burnedEnergy: 350,
            healthKitUUID: nil,
            locations: []
        )
        let temp = v2.asTemp
        XCTAssertEqual(temp.distance, 8000)
        XCTAssertEqual(temp.burnedEnergy, 350)
        XCTAssertEqual(temp.workoutType, .walking)
        XCTAssertTrue(temp.isRace)
        XCTAssertTrue(temp.isUserModified)
        XCTAssertEqual(temp.comment, "Pilgrimage walk")
    }

    // MARK: - V3 Migration

    func testV3_asTemp_noEvents_emptyPauses() {
        let v3 = TempV3.Workout(
            uuid: UUID(),
            workoutType: 1,
            startDate: DateFactory.makeDate(2024, 6, 1, 6, 0, 0),
            endDate: DateFactory.makeDate(2024, 6, 1, 7, 0, 0),
            distance: 5000,
            steps: 7000,
            isRace: false,
            isUserModified: false,
            comment: nil,
            burnedEnergy: nil,
            healthKitUUID: nil,
            workoutEvents: [],
            locations: [],
            heartRates: []
        )
        let temp = v3.asTemp
        XCTAssertEqual(temp.pauses.count, 0)
        XCTAssertEqual(temp.pauseDuration, 0)
        XCTAssertEqual(temp.workoutEvents.count, 0)
    }

    func testV3_asTemp_pauseEventsUsedForPausesNotWorkoutEvents() {
        let start = DateFactory.makeDate(2024, 6, 1, 6, 0, 0)
        let end = DateFactory.makeDate(2024, 6, 1, 7, 0, 0)
        let v3 = TempV3.Workout(
            uuid: UUID(),
            workoutType: 1,
            startDate: start,
            endDate: end,
            distance: 5000,
            steps: nil,
            isRace: false,
            isUserModified: false,
            comment: nil,
            burnedEnergy: nil,
            healthKitUUID: nil,
            workoutEvents: [
                TempV3.WorkoutEvent(uuid: nil, eventType: 0,
                    startDate: DateFactory.makeDate(2024, 6, 1, 6, 15, 0),
                    endDate: DateFactory.makeDate(2024, 6, 1, 6, 15, 0)),
                TempV3.WorkoutEvent(uuid: nil, eventType: 2,
                    startDate: DateFactory.makeDate(2024, 6, 1, 6, 20, 0),
                    endDate: DateFactory.makeDate(2024, 6, 1, 6, 20, 0)),
                TempV3.WorkoutEvent(uuid: nil, eventType: 1,
                    startDate: DateFactory.makeDate(2024, 6, 1, 6, 35, 0),
                    endDate: DateFactory.makeDate(2024, 6, 1, 6, 35, 0)),
                TempV3.WorkoutEvent(uuid: nil, eventType: 3,
                    startDate: DateFactory.makeDate(2024, 6, 1, 6, 40, 0),
                    endDate: DateFactory.makeDate(2024, 6, 1, 6, 40, 0))
            ],
            locations: [],
            heartRates: []
        )
        let temp = v3.asTemp
        XCTAssertEqual(temp.pauses.count, 2)
        XCTAssertEqual(temp.workoutEvents.count, 0)
    }
}
