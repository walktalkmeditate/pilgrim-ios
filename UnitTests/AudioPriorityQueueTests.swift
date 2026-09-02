import XCTest
@testable import Pilgrim

final class AudioPriorityQueueTests: XCTestCase {

    override func setUp() {
        super.setUp()
        VoiceGuidePlayer.shared.stop()
        WayVoicePlayer.shared.stop()
        AudioPriorityQueue.shared.stopWhisper()
    }

    override func tearDown() {
        AudioPriorityQueue.shared.stopWhisper()
        WayVoicePlayer.shared.stop()
        super.tearDown()
    }

    func testWhisperHeldDuringAVoiceRunResumesAfterTheLastVoice() throws {
        let voiceURL = FileManager.default.temporaryDirectory.appendingPathComponent("way-voice-\(UUID().uuidString).wav")
        try TestAudioFile.writeSilentAudioFile(to: voiceURL, duration: 5)
        defer { try? FileManager.default.removeItem(at: voiceURL) }

        let whisperURL = FileManager.default.temporaryDirectory.appendingPathComponent("whisper-\(UUID().uuidString).wav")
        try TestAudioFile.writeSilentAudioFile(to: whisperURL, duration: 5)
        defer { try? FileManager.default.removeItem(at: whisperURL) }

        WayVoicePlayer.shared.play(url: voiceURL, volume: 0.8)
        XCTAssertTrue(WayVoicePlayer.shared.isPlayingWayVoice, "precondition: a Way voice is in flight")

        AudioPriorityQueue.shared.playWhisper(url: whisperURL)
        XCTAssertEqual(AudioPriorityQueue.shared._test_pendingWhisperURL, whisperURL,
                       "a whisper requested while a Way voice plays is held, not started")

        AudioPriorityQueue.shared.interruptForWayVoice()
        XCTAssertEqual(AudioPriorityQueue.shared._test_pendingWhisperURL, whisperURL,
                       "a whisper held across a run of Way voices must survive interruptForWayVoice")

        AudioPriorityQueue.shared.interruptForVoiceGuide()
        XCTAssertNil(AudioPriorityQueue.shared._test_pendingWhisperURL,
                     "a guide prompt beginning must still clear any held whisper")
    }
}
