import XCTest
import AVFoundation
@testable import Pilgrim

final class WayVoicePlayerTests: XCTestCase {

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
}
