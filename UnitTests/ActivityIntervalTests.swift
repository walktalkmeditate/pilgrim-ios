import XCTest
@testable import Pilgrim

final class ActivityIntervalTests: XCTestCase {

    func testActivityType_rawValues() {
        XCTAssertEqual(ActivityInterval.ActivityType.unknown.rawValue, 0)
        XCTAssertEqual(ActivityInterval.ActivityType.meditation.rawValue, 1)
        XCTAssertEqual(ActivityInterval.ActivityType(rawValue: 0), .unknown)
        XCTAssertEqual(ActivityInterval.ActivityType(rawValue: 1), .meditation)
        XCTAssertEqual(ActivityInterval.ActivityType(rawValue: 99), .unknown)
    }

    func testDuration_computed() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let end = DateFactory.makeDate(2024, 6, 15, 9, 5, 0)
        let interval = WalkDataFactory.makeActivityInterval(startDate: start, endDate: end)
        XCTAssertEqual(interval.duration, 300, accuracy: 0.01)
    }

    func testTempActivityInterval_codableRoundTrip() throws {
        let original = WalkDataFactory.makeActivityInterval(
            uuid: UUID(),
            activityType: .meditation,
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            endDate: DateFactory.makeDate(2024, 6, 15, 9, 8, 0)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TempActivityInterval.self, from: data)

        XCTAssertEqual(decoded.uuid, original.uuid)
        XCTAssertEqual(decoded.activityType, original.activityType)
        XCTAssertEqual(decoded.startDate, original.startDate)
        XCTAssertEqual(decoded.endDate, original.endDate)
    }

    func testNewWalk_meditateDurationFromIntervals() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let end = DateFactory.makeDate(2024, 6, 15, 10, 0, 0)
        let intervals = [
            WalkDataFactory.makeActivityInterval(
                startDate: start.addingTimeInterval(60),
                endDate: start.addingTimeInterval(360)
            ),
            WalkDataFactory.makeActivityInterval(
                startDate: start.addingTimeInterval(600),
                endDate: start.addingTimeInterval(900)
            )
        ]
        let walk = NewWalk(
            workoutType: .walking, distance: 1000, steps: nil,
            startDate: start, endDate: end,
            isRace: false, comment: nil, isUserModified: false, finishedRecording: true,
            heartRates: [], routeData: [], pauses: [], workoutEvents: [],
            activityIntervals: intervals
        )
        XCTAssertEqual(walk.meditateDuration, 600, accuracy: 0.01)
    }

    func testNewWalk_meditateDurationClampedToActiveDuration() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let end = DateFactory.makeDate(2024, 6, 15, 9, 10, 0)
        let intervals = [
            WalkDataFactory.makeActivityInterval(
                startDate: start,
                endDate: start.addingTimeInterval(1200)
            )
        ]
        let walk = NewWalk(
            workoutType: .walking, distance: 1000, steps: nil,
            startDate: start, endDate: end,
            isRace: false, comment: nil, isUserModified: false, finishedRecording: true,
            heartRates: [], routeData: [], pauses: [], workoutEvents: [],
            activityIntervals: intervals
        )
        XCTAssertEqual(walk.meditateDuration, 600, accuracy: 0.01)
    }

    func testNewWalk_emptyIntervals_zeroMeditateDuration() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let end = DateFactory.makeDate(2024, 6, 15, 10, 0, 0)
        let walk = NewWalk(
            workoutType: .walking, distance: 1000, steps: nil,
            startDate: start, endDate: end,
            isRace: false, comment: nil, isUserModified: false, finishedRecording: true,
            heartRates: [], routeData: [], pauses: [], workoutEvents: []
        )
        XCTAssertEqual(walk.meditateDuration, 0, accuracy: 0.01)
    }
}
