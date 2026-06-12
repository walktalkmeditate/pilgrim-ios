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

    func test_callChanged_doesNothing_whenCallNotConnected() {
        let builder = WalkBuilder()
        let mgmt = VoiceRecordingManagement(builder: builder)
        settleCombineSchedulers()

        mgmt._test_setActiveRecording(
            start: Date(timeIntervalSinceNow: -10),
            relativePath: "Recordings/X/rec.m4a"
        )

        mgmt._test_simulateCallChanged(hasConnected: false, hasEnded: false)

        XCTAssertTrue(mgmt.isRecording,
                      "ringing / declined call must NOT end the recording")
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

    func test_audioInterruptionBegan_finalizesActiveRecording() {
        let builder = WalkBuilder()
        let mgmt = VoiceRecordingManagement(builder: builder)
        settleCombineSchedulers()

        mgmt._test_setActiveRecording(
            start: Date(timeIntervalSinceNow: -10),
            relativePath: "Recordings/X/rec.m4a"
        )

        mgmt._test_simulateAudioInterruption(.began)

        XCTAssertFalse(mgmt.isRecording,
                       "a non-call interruption pauses the recorder with no resume — the recording must finalize, not silently truncate")
        XCTAssertNil(mgmt.recordingStartDate)
    }

    func test_audioInterruptionEnded_doesNotRestartRecording() {
        let builder = WalkBuilder()
        let mgmt = VoiceRecordingManagement(builder: builder)
        settleCombineSchedulers()

        mgmt._test_setActiveRecording(
            start: Date(timeIntervalSinceNow: -10),
            relativePath: "Recordings/X/rec.m4a"
        )
        mgmt._test_simulateAudioInterruption(.began)

        mgmt._test_simulateAudioInterruption(.ended(shouldResume: true))

        XCTAssertFalse(mgmt.isRecording,
                       "the interrupted recording was finalized — .ended must not spontaneously restart capture")
    }

    func test_audioInterruptionBegan_doesNothing_whenNotRecording() {
        let builder = WalkBuilder()
        let mgmt = VoiceRecordingManagement(builder: builder)
        settleCombineSchedulers()

        mgmt._test_simulateAudioInterruption(.began)

        XCTAssertFalse(mgmt.isRecording)
    }
}
