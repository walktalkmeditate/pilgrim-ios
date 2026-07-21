import AVFoundation

final class StonePlayer: NSObject, AVAudioPlayerDelegate {

    static let shared = StonePlayer()

    private var player: AVAudioPlayer?
    private let coordinator = AudioSessionCoordinator.shared

    override private init() { super.init() }

    func playForCount(_ count: Int) {
        if player != nil {
            player?.stop()
            player = nil
            coordinator.deactivate(consumer: "stone")
        }

        let tier = soundTier(for: count)
        let fileName = "stone-tier-\(tier)"
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "m4a")
                ?? Bundle.main.url(forResource: "stone-tier-1", withExtension: "m4a") else {
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
        CairnTier.soundTier(forStoneCount: count)
    }
}
