import XCTest
@testable import Pilgrim

/// A discarded walk keeps nothing of the recording it had open: not the
/// partial file, and not the microphone session behind it.
final class VoiceRecordingDiscardTests: XCTestCase {

    private func writePartialFile(relativePath: String) throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data([0x00]).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func test_discardRecording_releasesTheSessionAndTakesThePartialFile() throws {
        let mgmt = VoiceRecordingManagement(builder: WalkBuilder())
        settleCombineSchedulers()
        let relativePath = "Recordings/discard-\(UUID().uuidString).m4a"
        let file = try writePartialFile(relativePath: relativePath)
        mgmt._test_setActiveRecording(start: Date(timeIntervalSinceNow: -10), relativePath: relativePath)
        AudioSessionCoordinator.shared.activate(for: .recordingOnly, consumer: "voiceRecording")

        mgmt.discardRecording()

        XCTAssertFalse(mgmt.isRecording)
        XCTAssertNil(mgmt.recordingStartDate)
        XCTAssertFalse(AudioSessionCoordinator.shared._test_isConsumerActive("voiceRecording"),
                       "the microphone is let go here, not at a commit that never comes")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path),
                       "a discarded walk leaves no orphan audio on disk")
    }

    func test_discardRecording_doesNothingWithNoRecordingOpen() {
        let mgmt = VoiceRecordingManagement(builder: WalkBuilder())
        settleCombineSchedulers()
        AudioSessionCoordinator.shared.activate(for: .recordingOnly, consumer: "someoneElse")
        addTeardownBlock { AudioSessionCoordinator.shared.deactivate(consumer: "someoneElse") }

        mgmt.discardRecording()

        XCTAssertFalse(mgmt.isRecording)
        XCTAssertTrue(AudioSessionCoordinator.shared._test_isConsumerActive("someoneElse"),
                      "another consumer's session is not this one's to release")
    }
}
