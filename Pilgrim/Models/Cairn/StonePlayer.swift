import AVFoundation

final class StonePlayer: NSObject, AVAudioPlayerDelegate {

    static let shared = StonePlayer()

    private var player: AVAudioPlayer?
    private let coordinator = AudioSessionCoordinator.shared

    private override init() { super.init() }

    func playForCount(_ count: Int) {
        if player != nil {
            player?.stop()
            player = nil
            coordinator.deactivate(consumer: "stone")
        }

        let tier = soundTier(for: count)
        let fileName = "stone-tier-\(tier)"
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "m4a") else {
            print("[StonePlayer] Audio file not found: \(fileName)")
            return
        }

        coordinator.activate(for: .playbackOnly, consumer: "stone")

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.volume = Float(UserPreferences.bellVolume.value)
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            print("[StonePlayer] Playback error: \(error)")
            coordinator.deactivate(consumer: "stone")
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.player = nil
            self?.coordinator.deactivate(consumer: "stone")
        }
    }

    private func soundTier(for count: Int) -> Int {
        switch count {
        case 108...: return 7
        case 77...: return 6
        case 42...: return 5
        case 12...: return 4
        case 7...: return 3
        case 3...: return 2
        default: return 1
        }
    }
}
