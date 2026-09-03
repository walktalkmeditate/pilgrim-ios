import AVFoundation
import Combine

final class AudioPriorityQueue: NSObject, ObservableObject, AVAudioPlayerDelegate {

    static let shared = AudioPriorityQueue()

    private var player: AVAudioPlayer?
    private let coordinator = AudioSessionCoordinator.shared
    private let soundscapePlayer = SoundscapePlayer.shared
    private let voiceGuidePlayer = VoiceGuidePlayer.shared

    private var preDuckVolume: Float?
    private var pendingWhisperURL: URL?
    private var cancellables: [AnyCancellable] = []

    @Published private(set) var isPlayingWhisper = false

    override private init() {
        super.init()

        // Subscribing here forces WayVoicePlayer.shared to exist, which
        // registers its own sink on voiceGuidePlayer.playbackDidFinish
        // before ours below. That ordering matters: when a guide prompt
        // ends, WayVoicePlayer's sink must start the next queued Way voice
        // before our sink below releases a held whisper, or the whisper
        // starts for one tick and is immediately cut by interruptForWayVoice.
        WayVoicePlayer.shared.$isPlayingWayVoice
            .removeDuplicates()
            .filter { !$0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.playPendingWhisperIfNeeded()
            }
            .store(in: &cancellables)

        voiceGuidePlayer.playbackDidFinish
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.playPendingWhisperIfNeeded()
            }
            .store(in: &cancellables)
    }

    func playWhisper(url: URL, volume: Float = 0.8) {
        if voiceGuidePlayer.isPlaying || WayVoicePlayer.shared.isPlayingWayVoice {
            pendingWhisperURL = url
            return
        }

        startWhisperPlayback(url: url, volume: volume)
    }

    func stopWhisper() {
        // Cleared above the guard: "stop the whisper" must also drop one that
        // is merely waiting to start, or it surfaces after the walker
        // silenced it.
        pendingWhisperURL = nil
        guard player != nil else { return }
        player?.stop()
        player = nil
        isPlayingWhisper = false
        restoreAndDeactivate()
    }

    func interruptForVoiceGuide() {
        pendingWhisperURL = nil
        guard isPlayingWhisper else { return }
        player?.stop()
        player = nil
        isPlayingWhisper = false
        restoreAndDeactivate()
    }

    /// Same interruption as `interruptForVoiceGuide()` but leaves
    /// `pendingWhisperURL` alone — a whisper held across a run of several
    /// Way voices must survive every voice in that run, not just the first.
    func interruptForWayVoice() {
        guard isPlayingWhisper else { return }
        player?.stop()
        player = nil
        isPlayingWhisper = false
        restoreAndDeactivate()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.player = nil
            self?.isPlayingWhisper = false
            self?.restoreAndDeactivate()
        }
    }

    // MARK: - Private

    private func startWhisperPlayback(url: URL, volume: Float = 0.8) {
        stopWhisper()

        let currentVolume = soundscapePlayer.currentTargetVolume
        preDuckVolume = currentVolume
        let duckLevel = currentVolume * 0.3
        soundscapePlayer.setVolume(duckLevel, animated: true)

        coordinator.activate(for: .playbackOnly, consumer: "whisper")

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.volume = volume
            p.prepareToPlay()
            p.play()
            player = p
            isPlayingWhisper = true
        } catch {
            print("[AudioPriorityQueue] Whisper playback error: \(error)")
            restoreAndDeactivate()
        }
    }

    private func playPendingWhisperIfNeeded() {
        guard let url = pendingWhisperURL, !voiceGuidePlayer.isPlaying, !WayVoicePlayer.shared.isPlayingWayVoice else { return }
        pendingWhisperURL = nil
        startWhisperPlayback(url: url)
    }

    private func restoreAndDeactivate() {
        if let volume = preDuckVolume {
            soundscapePlayer.setVolume(volume, animated: true)
            preDuckVolume = nil
        }
        coordinator.deactivate(consumer: "whisper")
    }
}

#if DEBUG
extension AudioPriorityQueue {
    var _test_pendingWhisperURL: URL? { pendingWhisperURL }
}
#endif
