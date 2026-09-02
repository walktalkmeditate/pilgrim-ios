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
    private var elapsedTimer: Timer?
    private var generation = 0
    private var cancellables: [AnyCancellable] = []
    private let coordinator = AudioSessionCoordinator.shared
    private let soundscape = SoundscapePlayer.shared
    private let voiceGuide = VoiceGuidePlayer.shared

    override init() {
        super.init()
        voiceGuide.playbackDidFinish
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.startPendingIfNeeded() }
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
        player.play()
        startElapsedTimer()
    }

    func stop() {
        pending = nil
        generation += 1
        player?.stop()
        finish(notify: false)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finishedGeneration = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == finishedGeneration else { return }
            self.finish(notify: true)
        }
    }

    // MARK: - Private

    private func start(url: URL, volume: Float) {
        stop()
        let current = soundscape.currentTargetVolume
        preDuckVolume = current
        soundscape.setVolume(current * Float(UserPreferences.voiceGuideDuckLevel.value), animated: true)
        coordinator.activate(for: .playbackOnly, consumer: "honor-voice")
        AudioPriorityQueue.shared.interruptForVoiceGuide()
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.volume = volume
            p.prepareToPlay()
            p.play()
            player = p
            isPlayingWayVoice = true
            elapsedSeconds = 0
            startElapsedTimer()
        } catch {
            print("[WayVoicePlayer] playback error: \(error)")
            finish(notify: true)
        }
    }

    private func startPendingIfNeeded() {
        guard let pending else { return }
        self.pending = nil
        start(url: pending.url, volume: pending.volume)
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            self.elapsedSeconds = player.currentTime
        }
    }

    private func finish(notify: Bool) {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        player = nil
        isPlayingWayVoice = false
        if let volume = preDuckVolume {
            soundscape.setVolume(volume, animated: true)
            preDuckVolume = nil
        }
        coordinator.deactivate(consumer: "honor-voice")
        if notify { onFinished?() }
    }
}
