import XCTest
import AVFoundation
@testable import Pilgrim

private final class FakeAudioSession: AudioSessionApplying {
    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws {}
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {}
}

/// Real AVAudioPlayer over a real file, but `play()` only counts — the
/// decision logic under test runs unchanged while no audio hardware is
/// touched.
private final class CountingPlayer: AVAudioPlayer {
    private(set) var playCount = 0
    var playResult = true

    override func prepareToPlay() -> Bool { true }

    override func play() -> Bool {
        playCount += 1
        return playResult
    }

    override func stop() {}
}

private struct PlayerInitError: Error {}

final class SeekSoundPlayerTests: XCTestCase {

    private var coordinator: AudioSessionCoordinator!
    private var pingURL: URL!
    private var bowlURL: URL!
    private var players: [CountingPlayer] = []
    private var whisperPlaying = false
    private var voiceGuidePlaying = false

    override func setUpWithError() throws {
        try super.setUpWithError()
        coordinator = AudioSessionCoordinator(session: FakeAudioSession())
        let dir = FileManager.default.temporaryDirectory
        pingURL = dir.appendingPathComponent("seek-ping-\(UUID().uuidString).wav")
        bowlURL = dir.appendingPathComponent("seek-bowl-\(UUID().uuidString).wav")
        try TestAudioFile.writeSilentAudioFile(to: pingURL, duration: 0.7)
        try TestAudioFile.writeSilentAudioFile(to: bowlURL, duration: 1.0)
        players = []
        whisperPlaying = false
        voiceGuidePlaying = false
    }

    override func tearDown() {
        UserPreferences.seekSonarEnabled.delete()
        UserPreferences.seekSonarVolume.delete()
        UserPreferences.seekLastDurationMinutes.delete()
        UserPreferences.seekSafetyShown.delete()
        try? FileManager.default.removeItem(at: pingURL)
        try? FileManager.default.removeItem(at: bowlURL)
        coordinator = nil
        super.tearDown()
    }

    private func makeSoundPlayer(
        gap: TimeInterval = 0.1,
        factory: ((URL) throws -> AVAudioPlayer)? = nil
    ) -> SeekSoundPlayer {
        SeekSoundPlayer(
            coordinator: coordinator,
            pingURL: pingURL,
            bowlURL: bowlURL,
            doublePingGap: gap,
            makePlayer: factory ?? { url in
                let player = try CountingPlayer(contentsOf: url)
                self.players.append(player)
                return player
            },
            isWhisperPlaying: { self.whisperPlaying },
            isVoiceGuidePlaying: { self.voiceGuidePlaying }
        )
    }

    private var totalPlays: Int { players.map(\.playCount).reduce(0, +) }

    private func waitForDoublePingWindow(_ seconds: TimeInterval = 0.3) {
        let exp = expectation(description: "double-ping window elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 1.0)
    }

    // MARK: - Lifecycle

    func testPrepare_activatesConsumerAndArmsBothPlayersWithoutPlaying() {
        let player = makeSoundPlayer()

        player.prepare()

        XCTAssertTrue(coordinator._test_isConsumerActive(SeekSoundPlayer.consumerID))
        XCTAssertEqual(players.count, 2)
        XCTAssertEqual(totalPlays, 0)
    }

    func testStop_deactivatesConsumer() {
        let player = makeSoundPlayer()
        player.prepare()

        player.stop()

        XCTAssertFalse(coordinator._test_isConsumerActive(SeekSoundPlayer.consumerID))
    }

    func testDeinitWithoutStop_releasesConsumer() {
        var player: SeekSoundPlayer? = makeSoundPlayer()
        player?.prepare()
        XCTAssertTrue(coordinator._test_isConsumerActive(SeekSoundPlayer.consumerID))

        player = nil

        XCTAssertFalse(coordinator._test_isConsumerActive(SeekSoundPlayer.consumerID),
                       "an abandoned seek must not wedge the coordinator for the session")
    }

    // MARK: - Ping gating

    func testDisabledPreference_producesNoPlayAttempt() {
        UserPreferences.seekSonarEnabled.value = false
        let player = makeSoundPlayer()
        player.prepare()

        player.playPing(aligned: true)
        waitForDoublePingWindow()

        XCTAssertEqual(totalPlays, 0)
    }

    func testWhisperPlaying_skipsPing_playsAfterClear() {
        let player = makeSoundPlayer()
        player.prepare()

        whisperPlaying = true
        player.playPing(aligned: false)
        XCTAssertEqual(totalPlays, 0)

        whisperPlaying = false
        player.playPing(aligned: false)
        XCTAssertEqual(totalPlays, 1)
    }

    func testVoiceGuidePlaying_skipsPing_playsAfterClear() {
        let player = makeSoundPlayer()
        player.prepare()

        voiceGuidePlaying = true
        player.playPing(aligned: false)
        XCTAssertEqual(totalPlays, 0)

        voiceGuidePlaying = false
        player.playPing(aligned: false)
        XCTAssertEqual(totalPlays, 1)
    }

    func testMicCapableSessionMode_skipsPing_playsAfterRecordingEnds() {
        let player = makeSoundPlayer()
        player.prepare()

        coordinator.activate(for: .recordAndPlay, consumer: "voiceRecording")
        player.playPing(aligned: false)
        XCTAssertEqual(totalPlays, 0, "pings must never perturb an active talk recording")

        coordinator.deactivate(consumer: "voiceRecording")
        player.playPing(aligned: false)
        XCTAssertEqual(totalPlays, 1)
    }

    func testVolumePreference_appliedOnNextPing() throws {
        UserPreferences.seekSonarVolume.value = 0.9
        let player = makeSoundPlayer()
        player.prepare()

        player.playPing(aligned: false)

        let pingPlayer = try XCTUnwrap(players.first)
        XCTAssertEqual(pingPlayer.playCount, 1)
        XCTAssertEqual(pingPlayer.volume, 0.9, accuracy: 0.001)
    }

    // MARK: - Double ping

    func testAlignedPing_playsTwice() {
        let player = makeSoundPlayer()
        player.prepare()

        player.playPing(aligned: true)
        XCTAssertEqual(totalPlays, 1)

        waitForDoublePingWindow()
        XCTAssertEqual(totalPlays, 2)
    }

    func testStopBetweenDoublePingPlays_cancelsPendingSecond() {
        let player = makeSoundPlayer()
        player.prepare()

        player.playPing(aligned: true)
        player.stop()
        waitForDoublePingWindow()

        XCTAssertEqual(totalPlays, 1)
        XCTAssertFalse(coordinator._test_isConsumerActive(SeekSoundPlayer.consumerID))
    }

    func testNewRequestBetweenDoublePingPlays_supersedesPendingSecond() {
        let player = makeSoundPlayer()
        player.prepare()

        player.playPing(aligned: true)
        player.playPing(aligned: false)
        XCTAssertEqual(totalPlays, 2)

        waitForDoublePingWindow()
        XCTAssertEqual(totalPlays, 2, "the stale aligned second must not fire after a newer request")
    }

    func testDisableBetweenDoublePingPlays_silencesPendingSecond() {
        let player = makeSoundPlayer()
        player.prepare()

        player.playPing(aligned: true)
        UserPreferences.seekSonarEnabled.value = false
        waitForDoublePingWindow()

        XCTAssertEqual(totalPlays, 1)
    }

    // MARK: - Error paths

    func testPlayerInitFailure_onPrepare_deactivatesConsumer() {
        let player = makeSoundPlayer(factory: { _ in throw PlayerInitError() })

        player.prepare()

        XCTAssertFalse(coordinator._test_isConsumerActive(SeekSoundPlayer.consumerID))
    }

    func testPlayerInitFailure_onPing_leavesConsumerReleased() {
        let player = makeSoundPlayer(factory: { _ in throw PlayerInitError() })
        player.prepare()

        player.playPing(aligned: false)

        XCTAssertFalse(coordinator._test_isConsumerActive(SeekSoundPlayer.consumerID))
    }

    func testPlayFailure_resetsStateAndDeactivatesConsumer() {
        let player = makeSoundPlayer(factory: { url in
            let counting = try CountingPlayer(contentsOf: url)
            counting.playResult = false
            self.players.append(counting)
            return counting
        })
        player.prepare()

        player.playPing(aligned: false)

        XCTAssertFalse(coordinator._test_isConsumerActive(SeekSoundPlayer.consumerID))
    }

    func testBowlInitFailure_deactivatesConsumer() {
        let player = makeSoundPlayer(factory: { _ in throw PlayerInitError() })

        player.playBowl()

        XCTAssertFalse(coordinator._test_isConsumerActive(SeekSoundPlayer.consumerID))
    }

    // MARK: - Interruptions

    func testInterruptionBegan_skipsPings_endedRearmsOnNextPing() {
        let player = makeSoundPlayer()
        player.prepare()
        let armedAtPrepare = players.count

        coordinator._test_simulateInterruptionBegan()
        settleCombineSchedulers()
        player.playPing(aligned: false)
        XCTAssertEqual(totalPlays, 0, "state must stay honest while another app owns the session")

        coordinator._test_simulateInterruptionEnded(shouldResume: true)
        settleCombineSchedulers()
        player.playPing(aligned: false)

        XCTAssertEqual(totalPlays, 1, "the first ping after .ended must succeed without manual intervention")
        XCTAssertGreaterThan(players.count, armedAtPrepare, "re-arm recreates the dropped player")
    }

    func testInterruptionBegan_cancelsPendingDoublePing() {
        let player = makeSoundPlayer()
        player.prepare()

        player.playPing(aligned: true)
        coordinator._test_simulateInterruptionBegan()
        settleCombineSchedulers()
        waitForDoublePingWindow()

        XCTAssertEqual(totalPlays, 1)
    }

    // MARK: - Bowl

    func testBowl_playsEvenWhenSonarDisabled() {
        UserPreferences.seekSonarEnabled.value = false
        let player = makeSoundPlayer()
        player.prepare()

        player.playBowl()

        XCTAssertEqual(totalPlays, 1, "the reveal bowl belongs to the ritual, not the sonar toggle")
    }

    // MARK: - Preferences

    func testSeekPreferences_defaults() {
        XCTAssertTrue(UserPreferences.seekSonarEnabled.value)
        XCTAssertEqual(UserPreferences.seekSonarVolume.value, 0.5, accuracy: 0.001)
        XCTAssertEqual(UserPreferences.seekLastDurationMinutes.value, 60)
        XCTAssertFalse(UserPreferences.seekSafetyShown.value)
    }

    func testSeekPreferences_persistChanges() {
        UserPreferences.seekSonarEnabled.value = false
        UserPreferences.seekSonarVolume.value = 0.8
        UserPreferences.seekLastDurationMinutes.value = 120
        UserPreferences.seekSafetyShown.value = true

        XCTAssertFalse(UserPreferences.seekSonarEnabled.value)
        XCTAssertEqual(UserPreferences.seekSonarVolume.value, 0.8, accuracy: 0.001)
        XCTAssertEqual(UserPreferences.seekLastDurationMinutes.value, 120)
        XCTAssertTrue(UserPreferences.seekSafetyShown.value)
    }

    func testIsEnabled_roundTripsThroughPreference() {
        let player = makeSoundPlayer()

        player.isEnabled = false
        XCTAssertFalse(UserPreferences.seekSonarEnabled.value)

        UserPreferences.seekSonarEnabled.value = true
        XCTAssertTrue(player.isEnabled)
    }
}
