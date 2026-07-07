import XCTest
import CoreLocation
@testable import Pilgrim

/// Deterministic stand-in for CMMotionActivityManager: tests drive the
/// stationary signal and observe update lifecycle calls.
final class FakeMotionActivityProvider: SeekMotionActivityProviding {

    var denied = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var handler: ((Bool) -> Void)?

    var authorizationDenied: Bool { denied }

    func startUpdates(handler: @escaping (Bool) -> Void) {
        startCount += 1
        self.handler = handler
    }

    func stopUpdates() {
        stopCount += 1
        handler = nil
    }

    func sendStationary(_ still: Bool) {
        handler?(still)
    }
}

final class SeekStillnessDetectorTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
    private var motion: FakeMotionActivityProvider!

    override func setUp() {
        super.setUp()
        motion = FakeMotionActivityProvider()
    }

    private func makeDetector(window: TimeInterval = 60) -> SeekStillnessDetector {
        let detector = SeekStillnessDetector(motion: motion, windowDuration: window)
        detector.start()
        return detector
    }

    private func fix(metersNorth: Double = 0, accuracy: Double = 10) -> CLLocation {
        let base = SeekPoint(latitude: 42.0, longitude: -8.0)
        let point = SeekChainGenerator.destination(
            from: base, bearingDegrees: 0, distanceMeters: metersNorth
        )
        return CLLocation(
            coordinate: point.coordinate, altitude: 0,
            horizontalAccuracy: accuracy, verticalAccuracy: 10,
            course: -1, speed: 0, timestamp: t0
        )
    }

    // MARK: - AE4 vote matrix

    func testAllThreeSignalsStill_beginsThenCompletesAfterWindow() {
        let detector = makeDetector()
        detector.recordSteps(100)
        motion.sendStationary(true)
        detector.recordLocation(fix())
        detector.recordLocation(fix(metersNorth: 3))

        XCTAssertEqual(detector.evaluate(at: t0), .began)
        XCTAssertEqual(detector.evaluate(at: t0.addingTimeInterval(59)), .none)
        XCTAssertEqual(detector.evaluate(at: t0.addingTimeInterval(60)), .completed)
        XCTAssertEqual(detector.evaluate(at: t0.addingTimeInterval(61)), .none, "completion fires once")
    }

    func testTwoOfThreeStill_begins() {
        let detector = makeDetector()
        detector.recordSteps(100)
        motion.sendStationary(true)
        XCTAssertEqual(detector.evaluate(at: t0), .began)
    }

    func testOnlyOneSignalStill_neverBegins() {
        let detector = makeDetector()
        detector.recordSteps(100)
        XCTAssertEqual(detector.evaluate(at: t0), .none)
        XCTAssertEqual(detector.evaluate(at: t0.addingTimeInterval(300)), .none)
    }

    func testDisplacementVeto_overridesTwoStillVotes() {
        let detector = makeDetector()
        detector.recordSteps(100)
        motion.sendStationary(true)
        detector.recordLocation(fix())
        detector.recordLocation(fix(metersNorth: 30))
        XCTAssertEqual(
            detector.evaluate(at: t0), .none,
            "steps still + motion still + confident displacement must NOT read as still"
        )
    }

    func testLowAccuracyFixes_doNotFeedDisplacement() {
        let detector = makeDetector()
        detector.recordSteps(100)
        motion.sendStationary(true)
        detector.recordLocation(fix(accuracy: 80))
        detector.recordLocation(fix(metersNorth: 30, accuracy: 80))
        XCTAssertEqual(
            detector.evaluate(at: t0), .began,
            "bad-accuracy movement must not veto; steps + motion carry the vote"
        )
    }

    func testStepDelta_breaksRunningWindow_thenRestartsAfterQuiet() {
        let detector = makeDetector()
        detector.recordSteps(100)
        motion.sendStationary(true)
        XCTAssertEqual(detector.evaluate(at: t0), .began)

        detector.recordSteps(104)
        XCTAssertEqual(detector.evaluate(at: t0.addingTimeInterval(30)), .none, "new steps break the window")
        XCTAssertEqual(detector.evaluate(at: t0.addingTimeInterval(35)), .began, "quiet again after re-baseline")
        XCTAssertEqual(detector.evaluate(at: t0.addingTimeInterval(94)), .none)
        XCTAssertEqual(
            detector.evaluate(at: t0.addingTimeInterval(95)), .completed,
            "window restarts from the second begin"
        )
    }

    // MARK: - Motion permission denied (displacement-only mode)

    func testDenied_lengthensWindowAndRunsOnDisplacementAlone() {
        motion.denied = true
        let detector = makeDetector(window: 60)
        XCTAssertEqual(detector.windowDuration, 90, accuracy: 0.001)
        XCTAssertTrue(detector.isDisplacementOnly)
        XCTAssertEqual(motion.startCount, 0, "no motion updates when denied")

        detector.recordLocation(fix())
        detector.recordLocation(fix(metersNorth: 3))
        XCTAssertEqual(detector.evaluate(at: t0), .began)
        XCTAssertEqual(detector.evaluate(at: t0.addingTimeInterval(89)), .none)
        XCTAssertEqual(detector.evaluate(at: t0.addingTimeInterval(90)), .completed)
    }

    func testDenied_stepsAndMotionAloneCannotBegin() {
        motion.denied = true
        let detector = makeDetector()
        detector.recordSteps(100)
        motion.sendStationary(true)
        XCTAssertEqual(detector.evaluate(at: t0), .none)
    }

    // MARK: - Suspension

    func testSuspend_freezesEvaluation_resumeRestartsWindow() {
        let detector = makeDetector()
        detector.recordSteps(100)
        motion.sendStationary(true)
        XCTAssertEqual(detector.evaluate(at: t0), .began)

        detector.suspend()
        XCTAssertEqual(
            detector.evaluate(at: t0.addingTimeInterval(120)), .none,
            "suspended detector stays silent"
        )

        detector.resume()
        detector.recordSteps(100)
        motion.sendStationary(true)
        let resumeTime = t0.addingTimeInterval(120)
        XCTAssertEqual(detector.evaluate(at: resumeTime), .began, "window restarts after resume")
        XCTAssertEqual(detector.evaluate(at: resumeTime.addingTimeInterval(60)), .completed)
    }

    func testStop_stopsMotionUpdatesAndSilencesEvaluation() {
        let detector = makeDetector()
        XCTAssertEqual(motion.startCount, 1)
        detector.stop()
        XCTAssertGreaterThanOrEqual(motion.stopCount, 1)
        XCTAssertEqual(detector.evaluate(at: t0), .none)
    }
}
