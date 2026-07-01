import XCTest
import CallKit
@testable import Pilgrim

final class VoiceRecordingCallInterruptionTests: XCTestCase {

    func test_callChanged_stopsRecording_forAnyActiveCall() {
        let builder = WalkBuilder()
        let mgmt = VoiceRecordingManagement(builder: builder)
        settleCombineSchedulers()

        mgmt._test_setActiveRecording(
            start: Date(timeIntervalSinceNow: -10),
            relativePath: "Recordings/X/rec.m4a"
        )
        XCTAssertTrue(mgmt.isRecording, "precondition: recording is active")

        // Any active call (`!hasEnded`) takes the mic — a connected call and an
        // unanswered incoming ring are treated identically.
        mgmt._test_simulateCallChanged(hasEnded: false)

        XCTAssertFalse(mgmt.isRecording,
                       "an active call (connected or unanswered ring) must end the recording")
        XCTAssertNil(mgmt.recordingStartDate)
    }

    func test_callChanged_doesNothing_whenNotRecording() {
        let builder = WalkBuilder()
        let mgmt = VoiceRecordingManagement(builder: builder)
        settleCombineSchedulers()

        mgmt._test_simulateCallChanged(hasEnded: false)

        XCTAssertFalse(mgmt.isRecording)
    }

    func test_callChanged_doesNothing_whenCallEnded() {
        let builder = WalkBuilder()
        let mgmt = VoiceRecordingManagement(builder: builder)
        settleCombineSchedulers()

        mgmt._test_setActiveRecording(
            start: Date(timeIntervalSinceNow: -10),
            relativePath: "Recordings/X/rec.m4a"
        )

        mgmt._test_simulateCallChanged(hasEnded: true)

        XCTAssertTrue(mgmt.isRecording,
                      "a call-ended transition must not flip recording state")
        XCTAssertNotNil(mgmt.recordingStartDate)
    }

    func test_realCall_callThenAudioInterruption_stopsExactlyOnce() {
        let builder = WalkBuilder()
        let mgmt = VoiceRecordingManagement(builder: builder)
        settleCombineSchedulers()

        mgmt._test_setActiveRecording(
            start: Date(timeIntervalSinceNow: -10),
            relativePath: "Recordings/X/rec.m4a"
        )

        // A real call fires BOTH CXCallObserver and a session interruption. The
        // call stops the talk; the trailing interruption must be a clean no-op.
        mgmt._test_simulateCallChanged(hasEnded: false)
        mgmt._test_setRecorderCapturing(false)
        mgmt._test_simulateAudioInterruption(.began)
        mgmt._test_simulateAudioInterruption(.ended(shouldResume: false))

        XCTAssertFalse(mgmt.isRecording)
        XCTAssertNil(mgmt.recordingStartDate)
    }

    // MARK: - Non-call audio interruptions (notification, Siri, alarm)

    func test_audioInterruptionBegan_doesNotFinalize_transientNonCall() {
        let builder = WalkBuilder()
        let mgmt = VoiceRecordingManagement(builder: builder)
        settleCombineSchedulers()

        mgmt._test_setActiveRecording(
            start: Date(timeIntervalSinceNow: -10),
            relativePath: "Recordings/X/rec.m4a"
        )

        mgmt._test_simulateAudioInterruption(.began)

        XCTAssertTrue(mgmt.isRecording,
                      "a transient non-call interruption (notification, Siri, alarm) must NOT end the talk on .began")
        XCTAssertNotNil(mgmt.recordingStartDate)
    }

    func test_audioInterruptionEnded_keepsRecording_whenRecorderSurvived() {
        let builder = WalkBuilder()
        let mgmt = VoiceRecordingManagement(builder: builder)
        settleCombineSchedulers()

        mgmt._test_setActiveRecording(
            start: Date(timeIntervalSinceNow: -10),
            relativePath: "Recordings/X/rec.m4a"
        )
        mgmt._test_setRecorderCapturing(true)

        mgmt._test_simulateAudioInterruption(.began)
        mgmt._test_simulateAudioInterruption(.ended(shouldResume: true))

        XCTAssertTrue(mgmt.isRecording,
                      "a recorder that lived through a transient interruption must keep recording — no split")
        XCTAssertNotNil(mgmt.recordingStartDate)
    }

    func test_audioInterruptionEnded_finalizes_whenRecorderStopped() {
        let builder = WalkBuilder()
        let mgmt = VoiceRecordingManagement(builder: builder)
        settleCombineSchedulers()

        mgmt._test_setActiveRecording(
            start: Date(timeIntervalSinceNow: -10),
            relativePath: "Recordings/X/rec.m4a"
        )
        mgmt._test_setRecorderCapturing(false)

        mgmt._test_simulateAudioInterruption(.began)
        mgmt._test_simulateAudioInterruption(.ended(shouldResume: false))

        XCTAssertFalse(mgmt.isRecording,
                       "a recorder the interruption stopped must be finalized on .ended, not left capturing nothing")
        XCTAssertNil(mgmt.recordingStartDate)
    }

    func test_audioInterruptionBegan_doesNothing_whenNotRecording() {
        let builder = WalkBuilder()
        let mgmt = VoiceRecordingManagement(builder: builder)
        settleCombineSchedulers()

        mgmt._test_simulateAudioInterruption(.began)

        XCTAssertFalse(mgmt.isRecording)
    }
}
