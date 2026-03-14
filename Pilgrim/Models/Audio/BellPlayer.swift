import AVFoundation
import UIKit

final class BellPlayer: NSObject, AVAudioPlayerDelegate {

    static let shared = BellPlayer()

    private var player: AVAudioPlayer?
    private let coordinator = AudioSessionCoordinator.shared
    private let fileStore = AudioFileStore.shared

    private override init() { super.init() }

    func play(_ asset: AudioAsset, volume: Float = 0.7, withHaptic: Bool = true) {
        guard asset.type == .bell,
              let url = fileStore.localURL(for: asset) else { return }

        stop()
        coordinator.activate(for: .playbackOnly, consumer: "bell")

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.volume = volume
            p.prepareToPlay()
            p.play()
            player = p

            if withHaptic {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        } catch {
            print("[BellPlayer] Playback error: \(error)")
            coordinator.deactivate(consumer: "bell")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        coordinator.deactivate(consumer: "bell")
    }

    var isPlaying: Bool { player?.isPlaying ?? false }

    var currentDuration: TimeInterval { player?.duration ?? 0 }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.player = nil
            self?.coordinator.deactivate(consumer: "bell")
        }
    }
}
