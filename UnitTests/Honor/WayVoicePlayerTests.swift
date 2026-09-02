import XCTest
@testable import Pilgrim

final class WayVoicePlayerTests: XCTestCase {

    func testMissingFileReportsFinishedAndReleasesTheSession() {
        let player = WayVoicePlayer()
        let finished = expectation(description: "finished")
        player.onFinished = { finished.fulfill() }
        player.play(url: URL(fileURLWithPath: "/nonexistent/voice.m4a"), volume: 0.8)
        wait(for: [finished], timeout: 1)
        XCTAssertFalse(player.isPlayingWayVoice)
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
