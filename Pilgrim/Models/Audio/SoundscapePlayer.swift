import AVFoundation
import Combine

final class SoundscapePlayer: NSObject, ObservableObject {

    static let shared = SoundscapePlayer()

    @Published private(set) var isPlaying = false
    @Published private(set) var currentAsset: AudioAsset?

    private var activePlayer: AVAudioPlayer?
    private var fadingOutPlayer: AVAudioPlayer?
    private var fadeTimer: Timer?
    private let coordinator = AudioSessionCoordinator.shared
    private let fileStore = AudioFileStore.shared

    private override init() { super.init() }

    func play(_ asset: AudioAsset, volume: Float = 0.4, fadeDuration: TimeInterval = 2.0) {
        guard asset.type == .soundscape,
              let url = fileStore.localURL(for: asset) else { return }

        if let current = activePlayer, current.isPlaying {
            crossfade(to: url, asset: asset, volume: volume, fadeDuration: fadeDuration)
            return
        }

        coordinator.activate(for: .playbackOnly, consumer: "soundscape")

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0
            player.prepareToPlay()
            player.play()
            activePlayer = player
            currentAsset = asset
            isPlaying = true
            fadeIn(player: player, to: volume, duration: fadeDuration)
        } catch {
            print("[SoundscapePlayer] Playback error: \(error)")
            coordinator.deactivate(consumer: "soundscape")
        }
    }

    func stop(fadeDuration: TimeInterval = 2.0) {
        guard let player = activePlayer else { return }
        isPlaying = false
        currentAsset = nil
        fadeOut(player: player, duration: fadeDuration) { [weak self] in
            player.stop()
            self?.activePlayer = nil
            self?.coordinator.deactivate(consumer: "soundscape")
        }
    }

    func setVolume(_ volume: Float, animated: Bool = true) {
        guard let player = activePlayer else { return }
        if animated {
            player.setVolume(volume, fadeDuration: 0.5)
        } else {
            player.volume = volume
        }
    }

    private func crossfade(to url: URL, asset: AudioAsset, volume: Float, fadeDuration: TimeInterval) {
        guard let oldPlayer = activePlayer else { return }

        fadingOutPlayer = oldPlayer
        fadeOut(player: oldPlayer, duration: fadeDuration) { [weak self] in
            oldPlayer.stop()
            self?.fadingOutPlayer = nil
        }

        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.numberOfLoops = -1
            newPlayer.volume = 0
            newPlayer.prepareToPlay()
            newPlayer.play()
            activePlayer = newPlayer
            currentAsset = asset
            fadeIn(player: newPlayer, to: volume, duration: fadeDuration)
        } catch {
            print("[SoundscapePlayer] Crossfade error: \(error)")
        }
    }

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
