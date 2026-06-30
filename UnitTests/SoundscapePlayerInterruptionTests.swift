import XCTest
import AVFoundation
@testable import Pilgrim

/// Drives the shared SoundscapePlayer with real AVAudioPlayer instances over
/// generated silent files seeded into AudioFileStore's soundscape directory.
final class SoundscapePlayerInterruptionTests: XCTestCase {

    private var seededAssets: [AudioAsset] = []

    override func tearDown() {
        SoundscapePlayer.shared.stop(fadeDuration: 0)
        for asset in seededAssets {
            try? FileManager.default.removeItem(at: AudioFileStore.shared.destinationURL(for: asset))
        }
        seededAssets = []
        super.tearDown()
    }

    private func seedAsset(id: String) throws -> AudioAsset {
        let asset = AudioAsset(
            id: id,
            type: .soundscape,
            name: id,
            displayName: id,
            durationSec: 30,
            r2Key: "soundscape/\(id).aac",
            fileSizeBytes: 1,
            usageTags: []
        )
        try TestAudioFile.writeSilentAudioFile(to: AudioFileStore.shared.destinationURL(for: asset), duration: 30)
        seededAssets.append(asset)
        return asset
    }

    /// Spins the main run loop so asyncAfter cleanups can fire.
    private func spinMainRunLoop(for interval: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(interval))
    }

    // MARK: - Interruption resilience (AF5)

    func testInterruptionBegan_pausesPlayback_isPlayingReflectsReality() throws {
        let player = SoundscapePlayer.shared
        player.play(try seedAsset(id: "interrupt-a"), volume: 0.4, fadeDuration: 0)
        XCTAssertTrue(player.isPlaying)

        player.handleInterruption(.began)

        XCTAssertFalse(player.isPlaying, "a silent soundscape must not report itself playing")
        XCTAssertEqual(player._test_activePlayer?.isPlaying, false)
        XCTAssertNotNil(player.currentAsset, "asset stays current so resume/restart can find it")
    }

    func testInterruptionEndedWithResume_resumesPlayback() throws {
        let player = SoundscapePlayer.shared
        player.play(try seedAsset(id: "interrupt-b"), volume: 0.4, fadeDuration: 0)
        player.handleInterruption(.began)

        player.handleInterruption(.ended(shouldResume: true))

        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(player._test_activePlayer?.isPlaying, true)
    }

    func testInterruptionEndedWithoutResume_staysPausedConsistently() throws {
        let player = SoundscapePlayer.shared
        player.play(try seedAsset(id: "interrupt-c"), volume: 0.4, fadeDuration: 0)
        player.handleInterruption(.began)

        player.handleInterruption(.ended(shouldResume: false))

        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player._test_activePlayer?.isPlaying, false)
        XCTAssertNotNil(player.currentAsset)
    }

    func testInterruptionEndedWithoutBegan_doesNotDisturbPlayback() throws {
        let player = SoundscapePlayer.shared
        player.play(try seedAsset(id: "interrupt-d"), volume: 0.4, fadeDuration: 0)

        player.handleInterruption(.ended(shouldResume: true))

        XCTAssertTrue(player.isPlaying)
    }

    // MARK: - Crossfade state (AF21)

    func testStopThenPlayWithinFadeWindow_isPlayingTrue_exactlyOneActivePlayer() throws {
        let player = SoundscapePlayer.shared
        player.play(try seedAsset(id: "fade-a"), volume: 0.4, fadeDuration: 0)
        player.stop(fadeDuration: 1.0)
        XCTAssertFalse(player.isPlaying)

        let assetB = try seedAsset(id: "fade-b")
        player.play(assetB, volume: 0.4, fadeDuration: 0.2)

        XCTAssertTrue(player.isPlaying, "crossfade start must publish isPlaying = true")
        XCTAssertEqual(player.currentAsset?.id, assetB.id)
        XCTAssertNotNil(player._test_activePlayer)
        XCTAssertTrue(player._test_activePlayer !== player._test_fadingOutPlayer)

        spinMainRunLoop(for: 0.5)
        XCTAssertNil(player._test_fadingOutPlayer, "old player must be cleaned up after the fade")
        XCTAssertNotNil(player._test_activePlayer, "cleanup must not touch the new active player")
        XCTAssertTrue(player.isPlaying)
    }

    // MARK: - Stale crossfade cleanup (AF22)

    func testRapidCrossfades_staleCleanupDoesNotCutNewerFadeShort() throws {
        let player = SoundscapePlayer.shared
        player.play(try seedAsset(id: "rapid-a"), volume: 0.4, fadeDuration: 0)
        player.play(try seedAsset(id: "rapid-b"), volume: 0.4, fadeDuration: 1.0)

        spinMainRunLoop(for: 0.4)
        player.play(try seedAsset(id: "rapid-c"), volume: 0.4, fadeDuration: 1.0)

        // The first crossfade's cleanup fires ~1.0s in; the second fade-out
        // (of player B) runs until ~1.4s and must survive it.
        spinMainRunLoop(for: 0.75)
        XCTAssertNotNil(player._test_fadingOutPlayer,
                        "a stale cleanup must not stop the newer fade-out early")

        spinMainRunLoop(for: 0.6)
        XCTAssertNil(player._test_fadingOutPlayer)
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(player.currentAsset?.id, "rapid-c")
    }
}
