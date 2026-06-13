import XCTest
@testable import Pilgrim

/// A recording whose audio file exists on disk so `transcribeRecordings`
/// reaches the engine instead of skipping on the file-existence guard.
private final class FakeRecording: VoiceRecordingInterface {
    let uuid: UUID?
    let fileRelativePath: String
    init(uuid: UUID, fileRelativePath: String) {
        self.uuid = uuid
        self.fileRelativePath = fileRelativePath
    }
}

/// An engine that throws on every transcription — stands in for WhisperKit
/// failing on corrupt audio / OOM on older devices.
private final class FailingEngine: TranscriptionEngine {
    func transcribeAudio(atPath path: String) async throws -> TranscriptionOutput {
        throw NSError(domain: "FailingEngine", code: 1)
    }
    func unloadModels() async {}
}

/// AF32: when every recording fails to transcribe, the batch must reach
/// `.failed`, not `.completed` — otherwise the UI reports success while no
/// transcriptions exist, with no path to understand or retry.
final class TranscriptionServiceBatchStateTests: XCTestCase {

    private var createdFiles: [URL] = []

    override func tearDown() {
        for url in createdFiles { try? FileManager.default.removeItem(at: url) }
        createdFiles = []
        super.tearDown()
    }

    /// Writes a placeholder file under the documents directory and returns a
    /// recording pointing at its relative path.
    private func makeRecording() throws -> FakeRecording {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let relativePath = "test-recording-\(UUID().uuidString).m4a"
        let url = docs.appendingPathComponent(relativePath)
        try Data([0x00]).write(to: url)
        createdFiles.append(url)
        return FakeRecording(uuid: UUID(), fileRelativePath: relativePath)
    }

    private func isFailed(_ state: TranscriptionService.State) -> Bool {
        if case .failed = state { return true }
        return false
    }

    func testAllRecordingsFail_reachesFailedState() async throws {
        let service = TranscriptionService(engineLoader: { FailingEngine() })
        let recordings = [try makeRecording(), try makeRecording()]

        let results = await service.transcribeRecordings(recordings)

        XCTAssertTrue(results.isEmpty, "no transcriptions should be produced when every file fails")
        let state = await service.state
        XCTAssertTrue(isFailed(state), "an all-failed batch must report .failed, not .completed (AF32)")
    }

    func testEmptyBatch_doesNotReportFailure() async throws {
        let service = TranscriptionService(engineLoader: { FailingEngine() })

        let results = await service.transcribeRecordings([])

        XCTAssertTrue(results.isEmpty)
        let state = await service.state
        XCTAssertFalse(isFailed(state), "an empty batch is not a failure — nothing was attempted")
    }
}
