import XCTest
@testable import Pilgrim

final class SeekLiveActivityTests: XCTestCase {

    // MARK: - Distance buckets

    func testDistanceBucketFloorsToHundredMeterSteps() {
        XCTAssertEqual(SeekGlanceModel.distanceBucket(forMeters: 0), 0)
        XCTAssertEqual(SeekGlanceModel.distanceBucket(forMeters: 99.9), 0)
        XCTAssertEqual(SeekGlanceModel.distanceBucket(forMeters: 100), 100)
        XCTAssertEqual(SeekGlanceModel.distanceBucket(forMeters: 150), 100)
        XCTAssertEqual(SeekGlanceModel.distanceBucket(forMeters: 999), 900)
        XCTAssertEqual(SeekGlanceModel.distanceBucket(forMeters: 1999), 1900)
    }

    func testDistanceBucketCapsAtMax() {
        XCTAssertEqual(SeekGlanceModel.distanceBucket(forMeters: 2000), 2000)
        XCTAssertEqual(SeekGlanceModel.distanceBucket(forMeters: 2050), 2000)
        XCTAssertEqual(SeekGlanceModel.distanceBucket(forMeters: 12_000), 2000)
    }

    func testDistanceBucketClampsNegativeToZero() {
        XCTAssertEqual(SeekGlanceModel.distanceBucket(forMeters: -5), 0)
    }

    func testDistanceBucketIsMonotonic() {
        let samples = stride(from: 0.0, through: 3000.0, by: 25.0)
        let buckets = samples.map { SeekGlanceModel.distanceBucket(forMeters: $0) }
        XCTAssertEqual(buckets, buckets.sorted())
    }

    // MARK: - Direction hint quadrants

    func testDirectionHintQuadrants() {
        XCTAssertEqual(SeekGlanceModel.directionHint(courseDegrees: 0, bearingDegrees: 0), .ahead)
        XCTAssertEqual(SeekGlanceModel.directionHint(courseDegrees: 0, bearingDegrees: 90), .right)
        XCTAssertEqual(SeekGlanceModel.directionHint(courseDegrees: 0, bearingDegrees: 180), .behind)
        XCTAssertEqual(SeekGlanceModel.directionHint(courseDegrees: 0, bearingDegrees: 270), .left)
    }

    func testDirectionHintConeBoundaries() {
        XCTAssertEqual(SeekGlanceModel.directionHint(courseDegrees: 0, bearingDegrees: 45), .ahead)
        XCTAssertEqual(SeekGlanceModel.directionHint(courseDegrees: 0, bearingDegrees: 46), .right)
        XCTAssertEqual(SeekGlanceModel.directionHint(courseDegrees: 0, bearingDegrees: 315), .ahead)
        XCTAssertEqual(SeekGlanceModel.directionHint(courseDegrees: 0, bearingDegrees: 314), .left)
        XCTAssertEqual(SeekGlanceModel.directionHint(courseDegrees: 0, bearingDegrees: 135), .behind)
        XCTAssertEqual(SeekGlanceModel.directionHint(courseDegrees: 0, bearingDegrees: 134), .right)
    }

    func testDirectionHintIsCourseRelativeAcrossNorthWrap() {
        XCTAssertEqual(SeekGlanceModel.directionHint(courseDegrees: 350, bearingDegrees: 10), .ahead)
        XCTAssertEqual(SeekGlanceModel.directionHint(courseDegrees: 10, bearingDegrees: 350), .ahead)
        XCTAssertEqual(SeekGlanceModel.directionHint(courseDegrees: 350, bearingDegrees: 80), .right)
        XCTAssertEqual(SeekGlanceModel.directionHint(courseDegrees: 90, bearingDegrees: 350), .left)
    }

    // MARK: - Glance assembly

    func testGlanceInvalidCourseHidesHintButKeepsDistance() {
        let glance = SeekGlanceModel.glance(
            distanceToActiveMeters: 420,
            courseDegrees: -1,
            speedMetersPerSecond: 1.4,
            bearingToClearingDegrees: 90,
            phase: .guiding
        )
        XCTAssertEqual(glance?.distanceBucketMeters, 400)
        XCTAssertNil(glance?.directionHint)
        XCTAssertEqual(glance?.isComplete, false)
    }

    func testGlanceStationarySpeedHidesHintButKeepsDistance() {
        let glance = SeekGlanceModel.glance(
            distanceToActiveMeters: 420,
            courseDegrees: 90,
            speedMetersPerSecond: 0.2,
            bearingToClearingDegrees: 90,
            phase: .guiding
        )
        XCTAssertEqual(glance?.distanceBucketMeters, 400)
        XCTAssertNil(glance?.directionHint)
    }

    func testGlanceMovingAtSpeedFloorShowsHint() {
        let glance = SeekGlanceModel.glance(
            distanceToActiveMeters: 420,
            courseDegrees: 0,
            speedMetersPerSecond: SeekGlanceModel.stationarySpeedFloor,
            bearingToClearingDegrees: 90,
            phase: .guiding
        )
        XCTAssertEqual(glance?.directionHint, .right)
    }

    func testGlanceCompletePhaseIgnoresDistanceInputs() {
        let glance = SeekGlanceModel.glance(
            distanceToActiveMeters: nil,
            courseDegrees: nil,
            speedMetersPerSecond: nil,
            bearingToClearingDegrees: nil,
            phase: .complete
        )
        XCTAssertEqual(glance?.isComplete, true)
        XCTAssertNil(glance?.directionHint)
    }

    func testGlanceWithoutDistanceReturnsNil() {
        let glance = SeekGlanceModel.glance(
            distanceToActiveMeters: nil,
            courseDegrees: 90,
            speedMetersPerSecond: 1.4,
            bearingToClearingDegrees: 45,
            phase: .guiding
        )
        XCTAssertNil(glance)
    }

    func testGlanceWithAllNilInputsReturnsNil() {
        let glance = SeekGlanceModel.glance(
            distanceToActiveMeters: nil,
            courseDegrees: nil,
            speedMetersPerSecond: nil,
            bearingToClearingDegrees: nil,
            phase: .guiding
        )
        XCTAssertNil(glance)
    }

    // MARK: - Manager gating

    func testShouldPushOnSeekGlanceChangeAlone() {
        XCTAssertTrue(WalkActivityManager.shouldPush(
            movedMeters: 0,
            flagsChanged: false,
            seekGlanceChanged: true,
            secondsSinceLastPush: 1
        ))
    }

    func testShouldNotPushWhenNothingChangedInsideFloor() {
        XCTAssertFalse(WalkActivityManager.shouldPush(
            movedMeters: WalkActivityManager.distanceThreshold - 1,
            flagsChanged: false,
            seekGlanceChanged: false,
            secondsSinceLastPush: WalkActivityManager.timeThreshold - 1
        ))
    }

    func testShouldPushOnExistingTriggers() {
        XCTAssertTrue(WalkActivityManager.shouldPush(
            movedMeters: WalkActivityManager.distanceThreshold,
            flagsChanged: false,
            seekGlanceChanged: false,
            secondsSinceLastPush: 0
        ))
        XCTAssertTrue(WalkActivityManager.shouldPush(
            movedMeters: 0,
            flagsChanged: true,
            seekGlanceChanged: false,
            secondsSinceLastPush: 0
        ))
        XCTAssertTrue(WalkActivityManager.shouldPush(
            movedMeters: 0,
            flagsChanged: false,
            seekGlanceChanged: false,
            secondsSinceLastPush: WalkActivityManager.timeThreshold
        ))
    }

    func testGlanceEqualityMatchesGatingExpectations() {
        let a = SeekGlanceState(distanceBucketMeters: 400, directionHint: .ahead, isComplete: false)
        let sameAsA = SeekGlanceState(distanceBucketMeters: 400, directionHint: .ahead, isComplete: false)
        let newBucket = SeekGlanceState(distanceBucketMeters: 300, directionHint: .ahead, isComplete: false)
        let newHint = SeekGlanceState(distanceBucketMeters: 400, directionHint: .left, isComplete: false)
        let completed = SeekGlanceState(distanceBucketMeters: 400, directionHint: .ahead, isComplete: true)

        XCTAssertEqual(a, sameAsA)
        XCTAssertNotEqual(a, newBucket)
        XCTAssertNotEqual(a, newHint)
        XCTAssertNotEqual(a, completed)
        XCTAssertNotEqual(a, nil as SeekGlanceState?)
    }

    // MARK: - ContentState backward compatibility (wander parity)

    func testContentStateDecodesPreSeekFixtureWithoutSeekKey() throws {
        let fixture = Data("""
        {
            "activeDurationSeconds": 600,
            "distanceMeters": 1200,
            "isPaused": false,
            "isMeditating": false,
            "isRecordingVoice": false
        }
        """.utf8)

        let state = try JSONDecoder().decode(WalkActivityAttributes.ContentState.self, from: fixture)
        XCTAssertNil(state.seek)
        XCTAssertEqual(state.activeDurationSeconds, 600)
        XCTAssertEqual(state.distanceMeters, 1200)
    }

    func testContentStateWithNilSeekEncodesWithoutSeekKey() throws {
        let state = WalkActivityAttributes.ContentState(
            activeDurationSeconds: 600,
            walkTimerStart: nil,
            distanceMeters: 1200,
            meditationTimerStart: nil,
            talkTimerStart: nil,
            isPaused: false,
            isMeditating: false,
            isRecordingVoice: false
        )

        let data = try JSONEncoder().encode(state)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["seek"])
        XCTAssertEqual(
            Set(json.keys),
            ["activeDurationSeconds", "distanceMeters", "isPaused", "isMeditating", "isRecordingVoice"]
        )
    }

    func testContentStateRoundTripsSeekGlance() throws {
        let state = WalkActivityAttributes.ContentState(
            activeDurationSeconds: 60,
            walkTimerStart: nil,
            distanceMeters: 300,
            meditationTimerStart: nil,
            talkTimerStart: nil,
            isPaused: false,
            isMeditating: false,
            isRecordingVoice: false,
            seek: SeekGlanceState(distanceBucketMeters: 700, directionHint: .behind, isComplete: false)
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WalkActivityAttributes.ContentState.self, from: data)
        XCTAssertEqual(decoded, state)
        XCTAssertEqual(decoded.seek?.distanceBucketMeters, 700)
        XCTAssertEqual(decoded.seek?.directionHint, .behind)
    }
}
