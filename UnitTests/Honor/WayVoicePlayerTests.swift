import XCTest
import AVFoundation
@testable import Pilgrim

final class WayVoicePlayerTests: XCTestCase {

    private var soundscapeVolume: Float = 0

    override func setUp() {
        super.setUp()
        soundscapeVolume = SoundscapePlayer.shared.currentTargetVolume
        VoiceGuidePlayer.shared.stop()
        WayVoicePlayer.shared.stop()
        WayVoicePlayer.shared.onFinished = nil
        AudioPriorityQueue.shared.stopWhisper()
    }

    override func tearDown() {
        VoiceGuidePlayer.shared.stop()
        WayVoicePlayer.shared.stop()
        WayVoicePlayer.shared.onFinished = nil
        AudioPriorityQueue.shared.stopWhisper()
        SoundscapePlayer.shared.setVolume(soundscapeVolume, animated: false)
        super.tearDown()
    }

    private func makeAudioFile(duration: TimeInterval = 5) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("way-voice-\(UUID().uuidString).m4a")
        _ = try TestAudioFile.writeSilentAudioFile(to: url, duration: duration)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testMissingFileReportsFinishedAndReleasesTheSession() {
        let player = WayVoicePlayer()
        let finished = expectation(description: "finished")
        player.onFinished = { finished.fulfill() }
        player.play(url: URL(fileURLWithPath: "/nonexistent/voice.m4a"), volume: 0.8)
        wait(for: [finished], timeout: 1)
        XCTAssertFalse(player.isPlayingWayVoice)
        XCTAssertFalse(AudioSessionCoordinator.shared._test_isConsumerActive("honor-voice"))
    }

    func testStaleFinishAfterStopDoesNotNotify() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("way-voice-\(UUID().uuidString).m4a")
        _ = try TestAudioFile.writeSilentAudioFile(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let player = WayVoicePlayer()
        let notified = expectation(description: "onFinished should not fire")
        notified.isInverted = true
        player.onFinished = { notified.fulfill() }

        player.play(url: url, volume: 0.8)
        player.stop()

        let stale = try AVAudioPlayer(contentsOf: url)
        player.audioPlayerDidFinishPlaying(stale, successfully: true)

        wait(for: [notified], timeout: 0.5)
    }

    func testNaturalFinishNotifiesExactlyOnce() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("way-voice-\(UUID().uuidString).m4a")
        _ = try TestAudioFile.writeSilentAudioFile(to: url, duration: 0.3)
        defer { try? FileManager.default.removeItem(at: url) }

        let player = WayVoicePlayer()
        var callCount = 0
        let finished = expectation(description: "finished")
        player.onFinished = {
            callCount += 1
            finished.fulfill()
        }

        player.play(url: url, volume: 0.8)
        wait(for: [finished], timeout: 5)

        XCTAssertEqual(callCount, 1)
        XCTAssertFalse(player.isPlayingWayVoice)
        XCTAssertFalse(AudioSessionCoordinator.shared._test_isConsumerActive("honor-voice"))
    }

    func testPlaysAGeneratedFileAndPausesResumes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("way-voice-\(UUID().uuidString).m4a")
        _ = try TestAudioFile.writeSilentAudioFile(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let player = WayVoicePlayer()
        player.play(url: url, volume: 0.8)
        XCTAssertTrue(player.isPlayingWayVoice)
        player.pause()
        XCTAssertTrue(player.isPlayingWayVoice, "paused is still 'in flight' for the queue")
        player.resume()
        player.stop()
        XCTAssertFalse(player.isPlayingWayVoice)
    }

    // MARK: - Guide interplay (B2, B3)

    /// B2: a voice held behind a guide prompt used to be stranded when the
    /// guide was STOPPED rather than allowed to finish — `stop()` sent no
    /// `playbackDidFinish`, so nothing ever released the pending voice.
    func testStoppingTheGuideReleasesAPendingWayVoice() throws {
        let voiceURL = try makeAudioFile()
        let guideAV = try TestAudioFile.makePlayer(duration: 5)
        XCTAssertTrue(guideAV.play())
        VoiceGuidePlayer.shared._test_install(player: guideAV, onFinished: nil)
        XCTAssertTrue(VoiceGuidePlayer.shared.isPlaying)

        let voice = WayVoicePlayer.shared
        voice.play(url: voiceURL, volume: 0.8)
        XCTAssertFalse(voice.isPlayingWayVoice, "a voice arriving behind a guide waits its turn")

        let started = expectation(description: "the held voice starts")
        let token = voice.$isPlayingWayVoice.filter { $0 }.sink { _ in started.fulfill() }
        VoiceGuidePlayer.shared.stop()
        wait(for: [started], timeout: 2)
        token.cancel()
    }

    /// B3, guide-then-voice: the guide restores the soundscape on its way
    /// out, the released voice ducks from there, and its own end brings the
    /// walker's level back.
    func testGuideThenVoiceRestoresTheOriginalSoundscapeLevel() throws {
        let original: Float = 0.9
        SoundscapePlayer.shared.setVolume(original, animated: false)
        let voiceURL = try makeAudioFile()
        let guideURL = try makeAudioFile()

        VoiceGuidePlayer.shared._test_play(url: guideURL)
        let voice = WayVoicePlayer.shared
        voice.play(url: voiceURL, volume: 0.8)
        XCTAssertFalse(voice.isPlayingWayVoice)

        let started = expectation(description: "the held voice starts")
        let token = voice.$isPlayingWayVoice.filter { $0 }.sink { _ in started.fulfill() }
        VoiceGuidePlayer.shared.stop()
        wait(for: [started], timeout: 2)
        token.cancel()

        voice.stop()
        XCTAssertEqual(SoundscapePlayer.shared.currentTargetVolume, original, accuracy: 0.001)
    }

    /// B3, voice-then-guide: the guide arriving mid-voice used to capture the
    /// voice's duck as its own "before", so whichever ended last left the
    /// soundscape quiet for the rest of the walk.
    func testVoiceThenGuideRestoresTheOriginalSoundscapeLevel() throws {
        let original: Float = 0.9
        SoundscapePlayer.shared.setVolume(original, animated: false)
        let voiceURL = try makeAudioFile()
        let guideURL = try makeAudioFile()

        let voice = WayVoicePlayer.shared
        voice.play(url: voiceURL, volume: 0.8)
        XCTAssertTrue(voice.isPlayingWayVoice)
        XCTAssertNotEqual(SoundscapePlayer.shared.currentTargetVolume, original, accuracy: 0.001,
                          "the voice ducks the soundscape while it speaks")

        VoiceGuidePlayer.shared._test_play(url: guideURL)

        // The voice ends first — the ordering that used to leave the guide
        // restoring the soundscape to the duck it inherited.
        voice.stop()
        VoiceGuidePlayer.shared.stop()

        XCTAssertEqual(SoundscapePlayer.shared.currentTargetVolume, original, accuracy: 0.001)
    }

    /// A guide prompt only pauses a voice; the walker's own pause must not be
    /// undone when the prompt ends.
    func testGuideFinishDoesNotResumeAWalkerPausedVoice() throws {
        let voiceURL = try makeAudioFile()
        let guideURL = try makeAudioFile()
        let voice = WayVoicePlayer.shared
        voice.play(url: voiceURL, volume: 0.8)
        voice.pause()

        VoiceGuidePlayer.shared._test_play(url: guideURL)
        VoiceGuidePlayer.shared.stop()

        XCTAssertTrue(voice.isPlayingWayVoice, "a paused voice is still in flight for the queue")
    }
}
