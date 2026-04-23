import XCTest
@testable import Pilgrim

final class VoiceRecordingCheckpointTests: XCTestCase {

    func test_checkpointVoiceRecording_returnsNil_whenNotRecording() {
        let builder = WalkBuilder()
        let mgmt = VoiceRecordingManagement(builder: builder)

        XCTAssertNil(mgmt.checkpointVoiceRecording())
    }

    func test_checkpointVoiceRecording_returnsSnapshot_whenRecording() {
        let builder = WalkBuilder()
        let mgmt = VoiceRecordingManagement(builder: builder)

        mgmt._test_setActiveRecording(
            start: Date(timeIntervalSinceNow: -30),
            relativePath: "Recordings/ABC/rec.m4a"
        )

        guard let snapshot = mgmt.checkpointVoiceRecording() else {
            XCTFail("expected a provisional recording snapshot")
            return
        }
        XCTAssertEqual(snapshot.fileRelativePath, "Recordings/ABC/rec.m4a")
        XCTAssertEqual(snapshot.duration, 30, accuracy: 1.0)
        XCTAssertEqual(snapshot.startDate.timeIntervalSinceNow, -30, accuracy: 1.0)
        XCTAssertNil(snapshot.uuid)
        XCTAssertFalse(snapshot.isEnhanced)
    }
}
