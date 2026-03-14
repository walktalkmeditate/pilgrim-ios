import AVFoundation
import Combine

final class SoundscapePlayer: NSObject, ObservableObject {

    static let shared = SoundscapePlayer()

    @Published private(set) var isPlaying = false
    @Published private(set) var currentAsset: AudioAsset?
    @Published private(set) var isMuted = false

    private var activePlayer: AVAudioPlayer?
    private var targetVolume: Float = 0.4
    private let coordinator = AudioSessionCoordinator.shared
    private let fileStore = AudioFileStore.shared

    private override init() { super.init() }

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
            player.numberOfLoops = -1
            player.volume = 0
            player.prepareToPlay()
            player.play()
            activePlayer = player
            currentAsset = asset
            isPlaying = true
            player.setVolume(volume, fadeDuration: fadeDuration)
        } catch {
            print("[SoundscapePlayer] Playback error: \(error)")
            coordinator.deactivate(consumer: "soundscape")
        }
    }

    func stop(fadeDuration: TimeInterval = 2.0) {
        guard let player = activePlayer else { return }
        isPlaying = false
        currentAsset = nil
        isMuted = false

        if fadeDuration > 0 {
            player.setVolume(0, fadeDuration: fadeDuration)
            DispatchQueue.main.asyncAfter(deadline: .now() + fadeDuration) { [weak self] in
                player.stop()
                if self?.activePlayer === player {
                    self?.activePlayer = nil
                }
                self?.coordinator.deactivate(consumer: "soundscape")
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

    private var fadingOutPlayer: AVAudioPlayer?

    private func crossfade(to url: URL, asset: AudioAsset, volume: Float, fadeDuration: TimeInterval) {
        fadingOutPlayer?.stop()
        fadingOutPlayer = nil

        let oldPlayer = activePlayer
        fadingOutPlayer = oldPlayer
        oldPlayer?.setVolume(0, fadeDuration: fadeDuration)

        targetVolume = volume

        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.numberOfLoops = -1
            newPlayer.volume = 0
            newPlayer.prepareToPlay()
            newPlayer.play()
            activePlayer = newPlayer
            currentAsset = asset
            newPlayer.setVolume(volume, fadeDuration: fadeDuration)

            DispatchQueue.main.asyncAfter(deadline: .now() + fadeDuration) { [weak self] in
                self?.fadingOutPlayer?.stop()
                self?.fadingOutPlayer = nil
            }
        } catch {
            print("[SoundscapePlayer] Crossfade error: \(error)")
        }
    }
}
