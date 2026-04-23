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

    func test_sanitizeUnplayableRecordings_clearsPath_forMoovLessFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WalkSessionGuardRecoveryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let brokenFile = tmpDir.appendingPathComponent("broken.m4a")
        try Data().write(to: brokenFile)

        let recording = TempVoiceRecording(
            uuid: nil,
            startDate: Date(timeIntervalSinceNow: -30),
            endDate: Date(),
            duration: 30,
            fileRelativePath: "ignored/broken.m4a",
            isEnhanced: false
        )

        let sanitized = WalkSessionGuard.sanitizeRecording(
            recording,
            fileURL: brokenFile
        )
        XCTAssertEqual(sanitized.fileRelativePath, "")
        XCTAssertEqual(sanitized.duration, 30, accuracy: 0.1,
                       "duration must be preserved for the Talk timer")
    }

    func test_sanitizeUnplayableRecordings_preservesPath_whenFilePlayable() throws {
        let playable = TempVoiceRecording(
            uuid: nil,
            startDate: Date(),
            endDate: Date().addingTimeInterval(5),
            duration: 5,
            fileRelativePath: "Recordings/ABC/rec.m4a",
            isEnhanced: false
        )

        let sanitized = WalkSessionGuard.sanitizeRecording(
            playable,
            fileURL: nil,
            durationProbe: { _ in 5.0 }
        )
        XCTAssertEqual(sanitized.fileRelativePath, "Recordings/ABC/rec.m4a")
    }

    func test_sanitizeUnplayableRecordings_preservesPath_whenProbeReportsPositive() {
        let recording = TempVoiceRecording(
            uuid: nil,
            startDate: Date(),
            endDate: Date().addingTimeInterval(5),
            duration: 5,
            fileRelativePath: "Recordings/ABC/rec.m4a",
            isEnhanced: false
        )
        let fakeURL = URL(fileURLWithPath: "/does/not/exist.m4a")

        let sanitized = WalkSessionGuard.sanitizeRecording(
            recording,
            fileURL: fakeURL,
            durationProbe: { _ in 5.0 }
        )

        XCTAssertEqual(sanitized.fileRelativePath, "Recordings/ABC/rec.m4a")
    }
}
