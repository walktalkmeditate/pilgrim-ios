import AVFoundation

/// Pocket guidance channel for Seek: the sonar ping and the reveal bowl,
/// played through the dedicated "seekPing" audio consumer (`.playback` +
/// `.mixWithOthers` — never a mic-capable mode, never `duckOthers`). The
/// consumer stays active from `prepare()` to `stop()` so sub-second pings
/// don't churn the session; there is deliberately no silent keep-alive bed.
///
/// Pings skip — never queue, never duck — while a whisper or voice-guide
/// prompt is speaking, and while the session is in a mic-capable mode so an
/// active talk recording is never perturbed.
final class SeekSoundPlayer {

    static let consumerID = "seekPing"

    var isEnabled: Bool {
        get { UserPreferences.seekSonarEnabled.value }
        set { UserPreferences.seekSonarEnabled.value = newValue }
    }

    /// The master Sounds toggle silences seek audio the same way it silences
    /// bells and whispers — checked at play time so a mid-walk flip applies
    /// to the very next ping or bowl.
    private var isSoundsEnabled: Bool {
        UserPreferences.soundsEnabled.value
    }

    private let coordinator: AudioSessionCoordinator
    private let pingURL: URL?
    private let bowlURL: URL?
    private let doublePingGap: TimeInterval
    private let makePlayer: (URL) throws -> AVAudioPlayer
    private let isWhisperPlaying: () -> Bool
    private let isVoiceGuidePlaying: () -> Bool

    private var pingPlayer: AVAudioPlayer?
    private var bowlPlayer: AVAudioPlayer?
    private var isSessionActive = false
    private var isInterrupted = false
    private var pingGeneration = 0

    init(
        coordinator: AudioSessionCoordinator = .shared,
        pingURL: URL? = Bundle.main.url(forResource: "seek-ping", withExtension: "aac"),
        bowlURL: URL? = Bundle.main.url(forResource: "seek-bowl", withExtension: "aac"),
        doublePingGap: TimeInterval = 0.25,
        makePlayer: @escaping (URL) throws -> AVAudioPlayer = { try AVAudioPlayer(contentsOf: $0) },
        isWhisperPlaying: @escaping () -> Bool = { AudioPriorityQueue.shared.isPlayingWhisper },
        isVoiceGuidePlaying: @escaping () -> Bool = { VoiceGuidePlayer.shared.isPlaying }
    ) {
        self.coordinator = coordinator
        self.pingURL = pingURL
        self.bowlURL = bowlURL
        self.doublePingGap = doublePingGap
        self.makePlayer = makePlayer
        self.isWhisperPlaying = isWhisperPlaying
        self.isVoiceGuidePlaying = isVoiceGuidePlaying
    }

    deinit {
        stop()
    }

    /// Activates the consumer and arms both players at seek start so the
    /// first pulse plays without cold-start latency.
    func prepare() {
        activateSessionIfNeeded()
        armPingPlayerIfNeeded()
        armBowlPlayerIfNeeded()
        deactivateIfNothingArmed()
    }

    /// `aligned` plays the bundled ping twice with a short generation-guarded
    /// gap — any later request, `stop()`, or an interruption cancels the
    /// pending second cleanly (AF22).
    /// `closeness` (0 far → 1 near, the engine's shared curve) shapes the
    /// ping from a whisper over the hill to a drop beside you.
    func playPing(aligned: Bool, closeness: Double = 1) {
        pingGeneration += 1
        guard isEnabled, isSoundsEnabled else { return }
        let volumeScale = 0.55 + 0.45 * min(max(closeness, 0), 1)
        firePingIfAllowed(volumeScale: volumeScale)
        guard aligned else { return }
        let generation = pingGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + doublePingGap) { [weak self] in
            guard let self, generation == self.pingGeneration,
                  self.isEnabled, self.isSoundsEnabled else { return }
            self.firePingIfAllowed(volumeScale: volumeScale)
        }
    }

    /// Reveal/completion tone. Part of the reveal ritual rather than the
    /// sonar guidance channel, so it plays even when the sonar toggle is off —
    /// only the master Sounds toggle silences it.
    func playBowl() {
        guard isSoundsEnabled, !isInterrupted else { return }
        activateSessionIfNeeded()
        armBowlPlayerIfNeeded()
        guard let player = bowlPlayer else {
            deactivateIfNothingArmed()
            return
        }
        play(player)
    }

    func stop() {
        pingGeneration += 1
        isInterrupted = false
        pingPlayer?.stop()
        bowlPlayer?.stop()
        pingPlayer = nil
        bowlPlayer = nil
        deactivateSessionIfNeeded()
    }

    // MARK: - Ping gating

    private func firePingIfAllowed(volumeScale: Double) {
        guard !isInterrupted, canPingOverCurrentAudio else { return }
        activateSessionIfNeeded()
        armPingPlayerIfNeeded()
        guard let player = pingPlayer else {
            deactivateIfNothingArmed()
            return
        }
        play(player, volumeScale: volumeScale)
    }

    private var canPingOverCurrentAudio: Bool {
        guard !isWhisperPlaying(), !isVoiceGuidePlaying() else { return false }
        switch coordinator.currentMode {
        case .recordingOnly, .recordAndPlay:
            return false
        case .idle, .playbackOnly:
            return true
        }
    }

    // MARK: - Players

    private func play(_ player: AVAudioPlayer, volumeScale: Double = 1) {
        player.volume = Float(UserPreferences.seekSonarVolume.value * volumeScale)
        player.currentTime = 0
        if !player.play() {
            print("[SeekSoundPlayer] play() failed — resetting")
            resetAfterFailure()
        }
    }

    private func resetAfterFailure() {
        pingPlayer = nil
        bowlPlayer = nil
        deactivateSessionIfNeeded()
    }

    private func armPingPlayerIfNeeded() {
        guard pingPlayer == nil else { return }
        pingPlayer = armedPlayer(for: pingURL)
    }

    private func armBowlPlayerIfNeeded() {
        guard bowlPlayer == nil else { return }
        bowlPlayer = armedPlayer(for: bowlURL)
    }

    private func armedPlayer(for url: URL?) -> AVAudioPlayer? {
        guard let url else { return nil }
        do {
            let player = try makePlayer(url)
            player.prepareToPlay()
            return player
        } catch {
            print("[SeekSoundPlayer] Player init error: \(error)")
            return nil
        }
    }

    private func deactivateIfNothingArmed() {
        guard pingPlayer == nil, bowlPlayer == nil else { return }
        deactivateSessionIfNeeded()
    }

    // MARK: - Session

    private func activateSessionIfNeeded() {
        guard !isSessionActive else { return }
        isSessionActive = true
        coordinator.addInterruptionObserver(id: Self.consumerID) { [weak self] event in
            self?.handleInterruption(event)
        }
        coordinator.activate(for: .playbackOnly, consumer: Self.consumerID)
    }

    private func deactivateSessionIfNeeded() {
        guard isSessionActive else { return }
        isSessionActive = false
        coordinator.removeInterruptionObserver(id: Self.consumerID)
        coordinator.deactivate(consumer: Self.consumerID)
    }

    /// AVAudioPlayer never auto-resumes after an interruption (AF5); for
    /// sub-second one-shots the honest re-arm is to drop the players and
    /// recreate them on the next play.
    private func handleInterruption(_ event: AudioSessionCoordinator.InterruptionEvent) {
        guard isSessionActive else { return }
        switch event {
        case .began:
            isInterrupted = true
            pingGeneration += 1
            pingPlayer?.stop()
            bowlPlayer?.stop()
            pingPlayer = nil
            bowlPlayer = nil
        case .ended:
            isInterrupted = false
        }
    }
}
