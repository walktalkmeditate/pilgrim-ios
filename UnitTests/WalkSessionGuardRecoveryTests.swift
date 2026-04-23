import XCTest
@testable import Pilgrim

final class WalkSessionGuardRecoveryTests: XCTestCase {

    func test_checkpointVoiceRecording_snapshot_can_be_appended_to_checkpoint() {
        let vm = ActiveWalkViewModel()
        let builder = vm.builder
        builder.setStatus(.recording)

        vm.voiceRecordingManagement._test_setActiveRecording(
            start: Date(timeIntervalSinceNow: -42),
            relativePath: "Recordings/DEADBEEF/rec.m4a"
        )

        builder._test_setStartDate(Date(timeIntervalSinceNow: -60))

        let snapshot = builder.createCheckpointSnapshot()
        XCTAssertNotNil(snapshot)

        if let inflight = vm.voiceRecordingManagement.checkpointVoiceRecording() {
            snapshot?.appendVoiceRecordings([inflight])
        }

        XCTAssertEqual(snapshot?.voiceRecordings.count, 1)
        XCTAssertEqual(snapshot?.voiceRecordings.first?.fileRelativePath,
                       "Recordings/DEADBEEF/rec.m4a")
        XCTAssertEqual(snapshot?.voiceRecordings.first?.duration ?? 0, 42, accuracy: 1.0)
    }
}
