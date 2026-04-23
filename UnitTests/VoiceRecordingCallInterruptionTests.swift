import XCTest
import CallKit
@testable import Pilgrim

final class VoiceRecordingCallInterruptionTests: XCTestCase {

    func test_callChanged_stopsRecording_whenCallConnects() {
        let builder = WalkBuilder()
        let mgmt = VoiceRecordingManagement(builder: builder)

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

        mgmt._test_simulateCallChanged(hasConnected: true, hasEnded: false)

        XCTAssertFalse(mgmt.isRecording)
    }

    func test_callChanged_doesNothing_whenCallEnded() {
        let builder = WalkBuilder()
        let mgmt = VoiceRecordingManagement(builder: builder)

        mgmt._test_setActiveRecording(
            start: Date(timeIntervalSinceNow: -10),
            relativePath: "Recordings/X/rec.m4a"
        )

        mgmt._test_simulateCallChanged(hasConnected: true, hasEnded: true)

        XCTAssertTrue(mgmt.isRecording,
                      "a call-ended transition after disconnect must not flip recording state")
    }
}
