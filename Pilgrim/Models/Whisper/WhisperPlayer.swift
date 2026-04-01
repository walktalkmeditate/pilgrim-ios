import AVFoundation
import Combine

final class WhisperPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {

    static let shared = WhisperPlayer()

    private static let cdnBase = URL(string: "https://cdn.pilgrimapp.org/audio/whisper/")!

    private var player: AVAudioPlayer?
    private var avPlayer: AVPlayer?
    private var endObserver: Any?
    private let coordinator = AudioSessionCoordinator.shared

    @Published private(set) var isPlaying: Bool = false

    private override init() { super.init() }

    private func remoteURL(for whisper: WhisperDefinition) -> URL {
        Self.cdnBase.appendingPathComponent("\(whisper.audioFileName).aac")
    }

    func play(_ whisper: WhisperDefinition, volume: Float = 0.8) {
        let url = remoteURL(for: whisper)
        let queue = AudioPriorityQueue.shared
        queue.playWhisper(url: url, volume: volume)
    }

    func preview(_ whisper: WhisperDefinition, volume: Float = 0.6) {
        stop()

        let url = remoteURL(for: whisper)
        coordinator.activate(for: .playbackOnly, consumer: "whisper-preview")

        let playerItem = AVPlayerItem(url: url)
        let ap = AVPlayer(playerItem: playerItem)
        ap.volume = volume
        ap.play()
        avPlayer = ap
        isPlaying = true

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.stop()
        }
    }

    func stop() {
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
        avPlayer?.pause()
        avPlayer = nil
        player?.stop()
        player = nil
        isPlaying = false
        coordinator.deactivate(consumer: "whisper-preview")
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.stop()
        }
    }
}
