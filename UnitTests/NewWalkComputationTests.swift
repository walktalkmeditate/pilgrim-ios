import XCTest
@testable import Pilgrim

final class NewWalkComputationTests: XCTestCase {

    func testTalkDuration_clampedToActiveDuration() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let end = DateFactory.makeDate(2024, 6, 15, 9, 10, 0)
        let recordings = [
            WalkDataFactory.makeVoiceRecording(duration: 600),
            WalkDataFactory.makeVoiceRecording(duration: 600)
        ]
        let walk = NewWalk(
            workoutType: .walking, distance: 1000, steps: nil,
            startDate: start, endDate: end,
            isRace: false, comment: nil, isUserModified: false, finishedRecording: true,
            heartRates: [], routeData: [], pauses: [], workoutEvents: [],
            voiceRecordings: recordings
        )
        XCTAssertEqual(walk.talkDuration, 600, accuracy: 0.01)
    }

    func testMeditateDuration_clampedToActiveDuration() {
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

    func testElevation_computedFromRouteAltitudes() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let end = DateFactory.makeDate(2024, 6, 15, 10, 0, 0)
        let routeData = Array(stride(from: 0.0, through: 200.0, by: 5.0)).enumerated().map { i, alt in
            WalkDataFactory.makeRouteDataSample(
                timestamp: start.addingTimeInterval(Double(i) * 60),
                altitude: alt
            )
        }
        let walk = NewWalk(
            workoutType: .walking, distance: 5000, steps: nil,
            startDate: start, endDate: end,
            isRace: false, comment: nil, isUserModified: false, finishedRecording: true,
            heartRates: [], routeData: routeData, pauses: [], workoutEvents: []
        )
        XCTAssertGreaterThan(walk.ascend, 0)
    }

    func testDuration_computedFromStartEndPauses() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let end = DateFactory.makeDate(2024, 6, 15, 10, 0, 0)
        let pauses = [
            WalkDataFactory.makePause(
                startDate: DateFactory.makeDate(2024, 6, 15, 9, 20, 0),
                endDate: DateFactory.makeDate(2024, 6, 15, 9, 30, 0)
            )
        ]
        let walk = NewWalk(
            workoutType: .walking, distance: 5000, steps: nil,
            startDate: start, endDate: end,
            isRace: false, comment: nil, isUserModified: false, finishedRecording: true,
            heartRates: [], routeData: [], pauses: pauses, workoutEvents: []
        )
        XCTAssertEqual(walk.activeDuration, 3000, accuracy: 0.01)
        XCTAssertEqual(walk.pauseDuration, 600, accuracy: 0.01)
    }

    func testBurnedEnergy_nilWhenNoWeightPreference() {
        let saved = UserPreferences.weight.value
        UserPreferences.weight.value = nil
        defer { UserPreferences.weight.value = saved }

        let walk = NewWalk(
            workoutType: .walking, distance: 5000, steps: nil,
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            endDate: DateFactory.makeDate(2024, 6, 15, 10, 0, 0),
            isRace: false, comment: nil, isUserModified: false, finishedRecording: true,
            heartRates: [], routeData: [], pauses: [], workoutEvents: []
        )
        XCTAssertNil(walk.burnedEnergy)
    }
}
