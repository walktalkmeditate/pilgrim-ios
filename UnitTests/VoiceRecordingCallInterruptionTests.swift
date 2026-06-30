import XCTest
import CallKit
@testable import Pilgrim

final class VoiceRecordingCallInterruptionTests: XCTestCase {

    func test_callChanged_stopsRecording_whenCallConnects() {
        let builder = WalkBuilder()
        let mgmt = VoiceRecordingManagement(builder: builder)
        settleCombineSchedulers()

        mgmt._test_setActiveRecording(
            start: Date(timeIntervalSinceNow: -10),
            relativePath: "Recordings/X/rec.m4a"
        )
        XCTAssertTrue(mgmt.isRecording, "precondition: recording is active")

        mgmt._test_simulateCallChanged(hasConnected: true, hasEnded: false)

        XCTAssertFalse(mgmt.isRecording,
                       "recording should stop the moment a call connects")
    }

    func test_callChanged_stopsRecording_whenCallRinging() {
        let builder = WalkBuilder()
        let mgmt = VoiceRecordingManagement(builder: builder)
        settleCombineSchedulers()

        mgmt._test_setActiveRecording(
            start: Date(timeIntervalSinceNow: -10),
            relativePath: "Recordings/X/rec.m4a"
        )

        // An incoming call that rings but is never answered still takes the mic.
        mgmt._test_simulateCallChanged(hasConnected: false, hasEnded: false)

        XCTAssertFalse(mgmt.isRecording,
                       "an active (ringing/unanswered) call must end the recording, not just a connected one")
    }

    func test_callChanged_doesNothing_whenNotRecording() {
        let builder = WalkBuilder()
        let mgmt = VoiceRecordingManagement(builder: builder)
        settleCombineSchedulers()

        mgmt._test_simulateCallChanged(hasConnected: true, hasEnded: false)

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

        mgmt._test_simulateCallChanged(hasConnected: true, hasEnded: true)

        XCTAssertTrue(mgmt.isRecording,
                      "a call-ended transition after disconnect must not flip recording state")
    }

    // MARK: - Non-call audio interruptions (declined call, Siri, alarm)

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
                      "a transient non-call interruption (notification, Siri, alarm) must NOT end the talk — only a real call does")
        XCTAssertNotNil(mgmt.recordingStartDate)
    }

    func test_audioInterruption_beginThenEnd_keepsRecording() {
        let builder = WalkBuilder()
        let mgmt = VoiceRecordingManagement(builder: builder)
        settleCombineSchedulers()

        mgmt._test_setActiveRecording(
            start: Date(timeIntervalSinceNow: -10),
            relativePath: "Recordings/X/rec.m4a"
        )
        mgmt._test_simulateAudioInterruption(.began)

        mgmt._test_simulateAudioInterruption(.ended(shouldResume: true))

        XCTAssertTrue(mgmt.isRecording,
                      "a transient interruption that begins and ends must leave the talk recording untouched")
    }

    func test_audioInterruptionBegan_doesNothing_whenNotRecording() {
        let builder = WalkBuilder()
        let mgmt = VoiceRecordingManagement(builder: builder)
        settleCombineSchedulers()

        mgmt._test_simulateAudioInterruption(.began)

        XCTAssertFalse(mgmt.isRecording)
    }
}
