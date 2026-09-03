import AVFoundation
import Combine
import Foundation

protocol WayVoicePlaying: AnyObject {
    var onFinished: (() -> Void)? { get set }
    /// `volume` is the voice's target level; the caller halves it for ambience.
    func play(url: URL, volume: Float)
    func pause()
    func resume()
    func stop()
}

/// Plays one Way voice at a time. Modeled on AudioPriorityQueue, not on the
/// settings preview player: it ducks the soundscape, waits for a guide
/// prompt to finish before starting, and holds community whispers while
/// it plays. Consumer "honor-voice"; deactivated in every exit path.
final class WayVoicePlayer: NSObject, ObservableObject, WayVoicePlaying, AVAudioPlayerDelegate {

    static let shared = WayVoicePlayer()

    @Published private(set) var isPlayingWayVoice = false
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    var onFinished: (() -> Void)?

    private var player: AVAudioPlayer?
    private var pending: (url: URL, volume: Float)?
    private var preDuckVolume: Float?
    /// Set only by `pauseForGuide()`, so a walker's own pause is never
    /// undone by a guide prompt ending.
    private var pausedByGuide = false
    private var elapsedTimer: Timer?
    private var cancellables: [AnyCancellable] = []
    private let coordinator = AudioSessionCoordinator.shared
    private let soundscape = SoundscapePlayer.shared
    private let voiceGuide = VoiceGuidePlayer.shared

    override init() {
        super.init()
        voiceGuide.playbackDidFinish
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.guideDidFinish() }
            .store(in: &cancellables)
    }

    deinit { elapsedTimer?.invalidate() }

    func play(url: URL, volume: Float) {
        if voiceGuide.isPlaying {
            pending = (url, volume)
            return
        }
        start(url: url, volume: volume)
    }

    func pause() {
        player?.pause()
        elapsedTimer?.invalidate()
    }

    func resume() {
        guard let player else { return }
        // A guide prompt may have taken the duck over while this voice was
        // held; take it back rather than speaking over a soundscape at full
        // volume.
        if preDuckVolume == nil {
            preDuckVolume = soundscape.currentTargetVolume
            soundscape.setVolume(Float(UserPreferences.voiceGuideDuckLevel.value), animated: true)
        }
        player.play()
        startElapsedTimer()
    }

    /// Hands a starting guide prompt the soundscape level this player ducked
    /// FROM, so the guide's own restore lands on the walker's level instead
    /// of on this duck — exactly one owner of the duck at a time. A voice
    /// that is actually speaking is also held for the length of the prompt
    /// and resumed when it ends; a voice the walker paused is left paused.
    /// `isPlayingWayVoice` deliberately stays true either way: a whisper
    /// waiting on this voice must keep waiting.
    func pauseForGuide() -> Float? {
        guard player != nil, !pausedByGuide else { return nil }
        if player?.isPlaying == true {
            pausedByGuide = true
            pause()
        }
        let inherited = preDuckVolume
        preDuckVolume = nil
        return inherited
    }

    func stop() {
        pending = nil
        player?.stop()
        finish(notify: false)
    }

    /// The delegate hands back the exact `AVAudioPlayer` it was invoked on;
    /// `stop()`/`start()` always nil or replace `player` first, so a callback
    /// that lands after either is guaranteed to fail the identity check.
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, player === self.player else { return }
            self.finish(notify: true)
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, player === self.player else { return }
            self.finish(notify: true)
        }
    }

    // MARK: - Private

    private func start(url: URL, volume: Float) {
        // Between two voices in one run the session stays activated and the
        // soundscape stays ducked from the ORIGINAL level: releasing and
        // re-ducking here was an audible swell plus session churn every few
        // hundred metres.
        pending = nil
        player?.stop()
        finish(notify: false, releaseSession: false)
        AudioPriorityQueue.shared.interruptForWayVoice()
        if preDuckVolume == nil {
            preDuckVolume = soundscape.currentTargetVolume
            soundscape.setVolume(Float(UserPreferences.voiceGuideDuckLevel.value), animated: true)
        }
        coordinator.activate(for: .playbackOnly, consumer: "honor-voice")
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.volume = volume
            p.prepareToPlay()
            guard p.play() else {
                finish(notify: true)
                return
            }
            player = p
            isPlayingWayVoice = true
            elapsedSeconds = 0
            startElapsedTimer()
        } catch {
            print("[WayVoicePlayer] playback error: \(error)")
            finish(notify: true)
        }
    }

    /// A guide prompt ended. A prompt that replaced another one emits too, so
    /// re-check before acting: while a guide is still speaking, both the held
    /// voice and the pending one keep waiting.
    private func guideDidFinish() {
        guard !voiceGuide.isPlaying else { return }
        // A newer voice queued while the guide spoke supersedes a held one,
        // exactly as it would have superseded a playing one.
        if pending != nil {
            pausedByGuide = false
            startPendingIfNeeded()
            return
        }
        if pausedByGuide {
            pausedByGuide = false
            // `resume()` takes the duck back: the guide restored the
            // soundscape to the walker's level on its way out.
            resume()
            return
        }
        startPendingIfNeeded()
    }

    private func startPendingIfNeeded() {
        guard let pending else { return }
        self.pending = nil
        start(url: pending.url, volume: pending.volume)
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            self.elapsedSeconds = player.currentTime
        }
        RunLoop.main.add(timer, forMode: .common)
        elapsedTimer = timer
    }

    /// `releaseSession: false` is the one-run case — `start()` retiring the
    /// previous voice before the next one begins. Every other exit gives the
    /// soundscape and the session back.
    private func finish(notify: Bool, releaseSession: Bool = true) {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        player = nil
        elapsedSeconds = 0
        isPlayingWayVoice = false
        pausedByGuide = false
        if releaseSession {
            if let volume = preDuckVolume {
                soundscape.setVolume(volume, animated: true)
                preDuckVolume = nil
            }
            coordinator.deactivate(consumer: "honor-voice")
        }
        if notify { onFinished?() }
    }
}
