import AVFoundation
import Combine

final class SoundscapePlayer: NSObject, ObservableObject {

    static let shared = SoundscapePlayer()

    @Published private(set) var isPlaying = false
    @Published private(set) var currentAsset: AudioAsset?
    @Published private(set) var isMuted = false

    private var activePlayer: AVAudioPlayer?
    private var fadingOutPlayer: AVAudioPlayer?
    private var loopTimer: Timer?
    private var targetVolume: Float = 0.4
    private var currentURL: URL?
    private let coordinator = AudioSessionCoordinator.shared
    private let fileStore = AudioFileStore.shared
    private let crossfadeDuration: TimeInterval = 3.0

    private override init() { super.init() }

    func play(_ asset: AudioAsset, volume: Float = 0.4, fadeDuration: TimeInterval = 2.0) {
        guard asset.type == .soundscape,
              let url = fileStore.localURL(for: asset) else { return }

        isMuted = false

        if let current = activePlayer, current.isPlaying, currentAsset?.id != asset.id {
            crossfade(to: url, asset: asset, volume: volume, fadeDuration: fadeDuration)
            return
        }

        coordinator.activate(for: .playbackOnly, consumer: "soundscape")
        targetVolume = volume
        currentURL = url

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = 0
            player.volume = 0
            player.prepareToPlay()
            player.play()
            activePlayer = player
            currentAsset = asset
            isPlaying = true
            fadeIn(player: player, to: volume, duration: fadeDuration)
            scheduleLoopCrossfade(for: player)
        } catch {
            print("[SoundscapePlayer] Playback error: \(error)")
            coordinator.deactivate(consumer: "soundscape")
        }
    }

    func stop(fadeDuration: TimeInterval = 2.0) {
        cancelLoopTimer()
        guard let player = activePlayer else { return }
        isPlaying = false
        currentAsset = nil
        currentURL = nil
        isMuted = false
        fadeOut(player: player, duration: fadeDuration) { [weak self] in
            player.stop()
            self?.activePlayer = nil
            self?.fadingOutPlayer?.stop()
            self?.fadingOutPlayer = nil
            self?.coordinator.deactivate(consumer: "soundscape")
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

    // MARK: - Loop Crossfade

    private func scheduleLoopCrossfade(for player: AVAudioPlayer) {
        cancelLoopTimer()
        let triggerTime = max(0, player.duration - crossfadeDuration)
        loopTimer = Timer.scheduledTimer(withTimeInterval: triggerTime, repeats: false) { [weak self] _ in
            self?.performLoopCrossfade()
        }
    }

    private func performLoopCrossfade() {
        guard let url = currentURL, isPlaying else { return }

        let oldPlayer = activePlayer
        fadingOutPlayer = oldPlayer
        if let old = oldPlayer {
            fadeOut(player: old, duration: crossfadeDuration) { [weak self] in
                old.stop()
                if self?.fadingOutPlayer === old {
                    self?.fadingOutPlayer = nil
                }
            }
        }

        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.numberOfLoops = 0
            newPlayer.volume = 0
            newPlayer.prepareToPlay()
            newPlayer.play()
            activePlayer = newPlayer
            fadeIn(player: newPlayer, to: targetVolume, duration: crossfadeDuration)
            scheduleLoopCrossfade(for: newPlayer)
        } catch {
            print("[SoundscapePlayer] Loop crossfade error: \(error)")
        }
    }

    private func cancelLoopTimer() {
        loopTimer?.invalidate()
        loopTimer = nil
    }

    // MARK: - Crossfade Between Different Soundscapes

    private func crossfade(to url: URL, asset: AudioAsset, volume: Float, fadeDuration: TimeInterval) {
        cancelLoopTimer()
        guard let oldPlayer = activePlayer else { return }

        fadingOutPlayer = oldPlayer
        fadeOut(player: oldPlayer, duration: fadeDuration) { [weak self] in
            oldPlayer.stop()
            self?.fadingOutPlayer = nil
        }

        targetVolume = volume
        currentURL = url

        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.numberOfLoops = 0
            newPlayer.volume = 0
            newPlayer.prepareToPlay()
            newPlayer.play()
            activePlayer = newPlayer
            currentAsset = asset
            fadeIn(player: newPlayer, to: volume, duration: fadeDuration)
            scheduleLoopCrossfade(for: newPlayer)
        } catch {
            print("[SoundscapePlayer] Crossfade error: \(error)")
        }
    }

    // MARK: - Fade Helpers

    private func fadeIn(player: AVAudioPlayer, to volume: Float, duration: TimeInterval) {
        player.setVolume(volume, fadeDuration: duration)
    }

    private func fadeOut(player: AVAudioPlayer, duration: TimeInterval, completion: @escaping () -> Void) {
        player.setVolume(0, fadeDuration: duration)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            completion()
        }
    }
}
