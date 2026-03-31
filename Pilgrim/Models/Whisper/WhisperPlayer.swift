import AVFoundation
import Combine

final class WhisperPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {

    static let shared = WhisperPlayer()

    private var player: AVAudioPlayer?
    private let coordinator = AudioSessionCoordinator.shared
    private let soundscapePlayer = SoundscapePlayer.shared
    private var preDuckVolume: Float?

    @Published private(set) var isPlaying: Bool = false

    private override init() { super.init() }

    func play(_ whisper: WhisperDefinition, volume: Float = 0.8) {
        guard let url = Bundle.main.url(forResource: whisper.audioFileName, withExtension: "m4a") else {
            print("[WhisperPlayer] Audio file not found: \(whisper.audioFileName)")
            return
        }

        let queue = AudioPriorityQueue.shared
        queue.playWhisper(url: url, volume: volume)
    }

    func preview(_ whisper: WhisperDefinition, volume: Float = 0.6) {
        guard let url = Bundle.main.url(forResource: whisper.audioFileName, withExtension: "m4a") else { return }

        stop()

        coordinator.activate(for: .playbackOnly, consumer: "whisper-preview")

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.volume = volume
            p.prepareToPlay()
            p.play()
            player = p
            isPlaying = true
        } catch {
            print("[WhisperPlayer] Preview error: \(error)")
            coordinator.deactivate(consumer: "whisper-preview")
        }
    }

    func stop() {
        guard player != nil else { return }
        player?.stop()
        player = nil
        isPlaying = false
        coordinator.deactivate(consumer: "whisper-preview")
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.player = nil
            self?.isPlaying = false
            self?.coordinator.deactivate(consumer: "whisper-preview")
        }
    }
}
