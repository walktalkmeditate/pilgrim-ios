import AVFoundation
import Combine

final class SoundscapePlayer: NSObject, ObservableObject {

    static let shared = SoundscapePlayer()

    @Published private(set) var isPlaying = false
    @Published private(set) var currentAsset: AudioAsset?
    @Published private(set) var isMuted = false

    private var activePlayer: AVAudioPlayer?
    private var fadingOutPlayer: AVAudioPlayer?
    private var targetVolume: Float = 0.4
    var currentTargetVolume: Float { targetVolume }
    private let coordinator = AudioSessionCoordinator.shared
    private let fileStore = AudioFileStore.shared

    private var loopMonitor: Timer?
    private let crossfadeDuration: TimeInterval = 4.0
    private var resumeOnInterruptionEnd = false

    override private init() {
        super.init()
        coordinator.addInterruptionObserver(id: "soundscape") { [weak self] event in
            self?.handleInterruption(event)
        }
    }

    /// AVAudioPlayer does not auto-resume after a system interruption (call,
    /// Siri, alarm) — without this, the soundscape stays silent forever while
    /// `isPlaying` claims otherwise and the loop monitor reads a frozen
    /// `currentTime`.
    func handleInterruption(_ event: AudioSessionCoordinator.InterruptionEvent) {
        switch event {
        case .began:
            guard isPlaying else { return }
            resumeOnInterruptionEnd = true
            activePlayer?.pause()
            fadingOutPlayer?.stop()
            fadingOutPlayer = nil
            stopLoopMonitor()
            isPlaying = false
        case .ended(let shouldResume):
            guard resumeOnInterruptionEnd else { return }
            resumeOnInterruptionEnd = false
            guard shouldResume else { return }
            if let player = activePlayer, player.play() {
                isPlaying = true
                startLoopMonitor()
            } else if let asset = currentAsset {
                play(asset, volume: targetVolume)
            }
        }
    }

    func play(_ asset: AudioAsset, volume: Float = 0.4, fadeDuration: TimeInterval = 2.0) {
        guard asset.type == .soundscape,
              let url = fileStore.localURL(for: asset) else { return }

        isMuted = false

        if activePlayer != nil, currentAsset?.id != asset.id {
            crossfade(to: url, asset: asset, volume: volume, fadeDuration: fadeDuration)
            return
        }

        stop(fadeDuration: 0)
        coordinator.activate(for: .playbackOnly, consumer: "soundscape")
        targetVolume = volume

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = 0
            player.volume = 0
            player.prepareToPlay()
            player.play()
            activePlayer = player
            currentAsset = asset
            isPlaying = true
            player.setVolume(volume, fadeDuration: fadeDuration)
            startLoopMonitor()
        } catch {
            print("[SoundscapePlayer] Playback error: \(error)")
            coordinator.deactivate(consumer: "soundscape")
        }
    }

    func stop(fadeDuration: TimeInterval = 2.0) {
        stopLoopMonitor()
        resumeOnInterruptionEnd = false
        fadingOutPlayer?.stop()
        fadingOutPlayer = nil

        guard let player = activePlayer else { return }
        isPlaying = false
        currentAsset = nil
        isMuted = false

        if fadeDuration > 0 {
            player.setVolume(0, fadeDuration: fadeDuration)
            DispatchQueue.main.asyncAfter(deadline: .now() + fadeDuration) { [weak self] in
                player.stop()
                guard let self else { return }
                if self.activePlayer === player {
                    self.activePlayer = nil
                    self.coordinator.deactivate(consumer: "soundscape")
                }
            }
        } else {
            player.stop()
            activePlayer = nil
            coordinator.deactivate(consumer: "soundscape")
        }
    }

    func setVolume(_ volume: Float, animated: Bool = true) {
        targetVolume = volume
        guard let player = activePlayer, !isMuted else { return }
        if animated {
            player.setVolume(volume, fadeDuration: 0.5)
        } else {
            player.volume = volume
        }
    }

    func toggleMute() {
        if isMuted {
            isMuted = false
            activePlayer?.setVolume(targetVolume, fadeDuration: 1.5)
        } else {
            isMuted = true
            activePlayer?.setVolume(0, fadeDuration: 1.5)
        }
    }

    private func crossfade(to url: URL, asset: AudioAsset, volume: Float, fadeDuration: TimeInterval) {
        stopLoopMonitor()
        fadingOutPlayer?.stop()
        fadingOutPlayer = nil

        let oldPlayer = activePlayer
        fadingOutPlayer = oldPlayer
        oldPlayer?.setVolume(0, fadeDuration: fadeDuration)

        targetVolume = volume

        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.numberOfLoops = 0
            newPlayer.volume = 0
            newPlayer.prepareToPlay()
            newPlayer.play()
            activePlayer = newPlayer
            currentAsset = asset
            isPlaying = true
            newPlayer.setVolume(volume, fadeDuration: fadeDuration)
            startLoopMonitor()

            scheduleFadeOutCleanup(of: oldPlayer, after: fadeDuration)
        } catch {
            print("[SoundscapePlayer] Crossfade error: \(error)")
            fadingOutPlayer?.stop()
            fadingOutPlayer = nil
            activePlayer = nil
            isPlaying = false
            currentAsset = nil
            isMuted = false
            stopLoopMonitor()
            coordinator.deactivate(consumer: "soundscape")
        }
    }

    /// Identity-guarded so a stale cleanup (scheduled by an earlier
    /// crossfade) can't cut a newer fade-out short — the closure only acts
    /// if the player it was scheduled for is still the one fading out.
    private func scheduleFadeOutCleanup(of oldPlayer: AVAudioPlayer?, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak oldPlayer] in
            guard let self, let oldPlayer, self.fadingOutPlayer === oldPlayer else { return }
            oldPlayer.stop()
            self.fadingOutPlayer = nil
        }
    }

    private func startLoopMonitor() {
        stopLoopMonitor()
        guard let player = activePlayer else { return }

        if player.duration < crossfadeDuration + 1 {
            player.numberOfLoops = -1
            return
        }

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkLoopBoundary()
        }
        RunLoop.main.add(timer, forMode: .common)
        loopMonitor = timer
    }

    private func stopLoopMonitor() {
        loopMonitor?.invalidate()
        loopMonitor = nil
    }

    private func checkLoopBoundary() {
        guard let player = activePlayer, fadingOutPlayer == nil else { return }
        let remaining = player.duration - player.currentTime
        if remaining < crossfadeDuration + 0.5 {
            loopCrossfade()
        }
    }

    private func loopCrossfade() {
        stopLoopMonitor()

        guard let asset = currentAsset,
              let url = fileStore.localURL(for: asset) else {
            stop(fadeDuration: 0)
            return
        }

        fadingOutPlayer?.stop()
        fadingOutPlayer = nil

        let oldPlayer = activePlayer
        fadingOutPlayer = oldPlayer
        oldPlayer?.setVolume(0, fadeDuration: crossfadeDuration)

        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.numberOfLoops = 0
            newPlayer.volume = 0
            newPlayer.prepareToPlay()
            newPlayer.play()
            activePlayer = newPlayer
            let fadeTarget: Float = isMuted ? 0 : targetVolume
            newPlayer.setVolume(fadeTarget, fadeDuration: crossfadeDuration)
            startLoopMonitor()

            scheduleFadeOutCleanup(of: oldPlayer, after: crossfadeDuration)
        } catch {
            print("[SoundscapePlayer] Loop crossfade error: \(error)")
            fadingOutPlayer?.stop()
            fadingOutPlayer = nil
            activePlayer = nil
            isPlaying = false
            currentAsset = nil
            isMuted = false
            stopLoopMonitor()
            coordinator.deactivate(consumer: "soundscape")
        }
    }

    #if DEBUG
    var _test_activePlayer: AVAudioPlayer? { activePlayer }
    var _test_fadingOutPlayer: AVAudioPlayer? { fadingOutPlayer }
    #endif
}
