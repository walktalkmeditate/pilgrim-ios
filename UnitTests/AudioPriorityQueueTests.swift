import XCTest
import Combine
@testable import Pilgrim

final class AudioPriorityQueueTests: XCTestCase {

    private var tempFileURLs: [URL] = []

    override func setUp() {
        super.setUp()
        VoiceGuidePlayer.shared.stop()
        WayVoicePlayer.shared.stop()
        AudioPriorityQueue.shared.stopWhisper()
    }

    override func tearDown() {
        WayVoicePlayer.shared.stop()
        AudioPriorityQueue.shared.stopWhisper()
        WayVoicePlayer.shared.onFinished = nil
        for url in tempFileURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempFileURLs = []
        super.tearDown()
    }

    private func makeSilentFile(duration: TimeInterval) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("audio-\(UUID().uuidString).wav")
        try TestAudioFile.writeSilentAudioFile(to: url, duration: duration)
        tempFileURLs.append(url)
        return url
    }

    func testWhisperHeldAcrossAVoiceRunResumesAfterTheLastVoice() throws {
        let whisper1 = try makeSilentFile(duration: 2)
        let whisper2 = try makeSilentFile(duration: 2)
        let voiceA = try makeSilentFile(duration: 0.3)
        let voiceB = try makeSilentFile(duration: 0.3)

        AudioPriorityQueue.shared.playWhisper(url: whisper1)
        XCTAssertTrue(AudioPriorityQueue.shared.isPlayingWhisper, "an unblocked whisper starts immediately")

        var finishCount = 0
        let voiceAFinished = expectation(description: "voice A finished and started voice B")
        WayVoicePlayer.shared.onFinished = {
            finishCount += 1
            if finishCount == 1 {
                WayVoicePlayer.shared.play(url: voiceB, volume: 0.8)
                voiceAFinished.fulfill()
            }
        }

        WayVoicePlayer.shared.play(url: voiceA, volume: 0.8)
        XCTAssertFalse(AudioPriorityQueue.shared.isPlayingWhisper, "starting a Way voice cuts the audible whisper")

        AudioPriorityQueue.shared.playWhisper(url: whisper2)
        XCTAssertEqual(AudioPriorityQueue.shared._test_pendingWhisperURL, whisper2,
                       "a whisper requested while a Way voice plays is held, not started")
        XCTAssertFalse(AudioPriorityQueue.shared.isPlayingWhisper)

        wait(for: [voiceAFinished], timeout: 5)
        XCTAssertEqual(finishCount, 1)
        XCTAssertEqual(AudioPriorityQueue.shared._test_pendingWhisperURL, whisper2,
                       "a whisper held across a run of Way voices must survive the next voice's start")
        XCTAssertFalse(AudioPriorityQueue.shared.isPlayingWhisper, "voice B is now the one in flight")

        let whisperResumed = expectation(description: "held whisper resumed after the last voice")
        var releaseSubscription: AnyCancellable?
        releaseSubscription = AudioPriorityQueue.shared.$isPlayingWhisper
            .dropFirst()
            .first(where: { $0 })
            .sink { _ in
                whisperResumed.fulfill()
                releaseSubscription?.cancel()
            }

        wait(for: [whisperResumed], timeout: 5)
        XCTAssertEqual(finishCount, 2, "voice B must have finished naturally to release the held whisper")
        XCTAssertNil(AudioPriorityQueue.shared._test_pendingWhisperURL)
        XCTAssertTrue(AudioPriorityQueue.shared.isPlayingWhisper, "the held whisper resumes once the voice run ends")
    }

    func testPendingWhisperClearedByInterruptForVoiceGuide() throws {
        let voiceURL = try makeSilentFile(duration: 5)
        let whisperURL = try makeSilentFile(duration: 5)

        WayVoicePlayer.shared.play(url: voiceURL, volume: 0.8)
        XCTAssertTrue(WayVoicePlayer.shared.isPlayingWayVoice, "precondition: a Way voice is in flight")

        AudioPriorityQueue.shared.playWhisper(url: whisperURL)
        XCTAssertEqual(AudioPriorityQueue.shared._test_pendingWhisperURL, whisperURL,
                       "a whisper requested while a Way voice plays is held, not started")

        AudioPriorityQueue.shared.interruptForVoiceGuide()
        XCTAssertNil(AudioPriorityQueue.shared._test_pendingWhisperURL,
                     "a guide prompt beginning must still clear any held whisper")
    }
}
