import AVFoundation
import Combine

final class WhisperPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {

    static let shared = WhisperPlayer()

    private static let cdnBase = URL(string: "https://cdn.pilgrimapp.org/audio/whisper/")!

    private var player: AVAudioPlayer?
    private let coordinator = AudioSessionCoordinator.shared
    private let cacheDir: URL

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isDownloading: Bool = false

    private override init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDir = appSupport.appendingPathComponent("Whispers", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        super.init()
    }

    private func localURL(for whisper: WhisperDefinition) -> URL {
        cacheDir.appendingPathComponent("\(whisper.audioFileName).aac")
    }

    private func remoteURL(for whisper: WhisperDefinition) -> URL {
        Self.cdnBase.appendingPathComponent("\(whisper.audioFileName).aac")
    }

    func isAvailable(_ whisper: WhisperDefinition) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: whisper).path)
    }

    var allDownloaded: Bool {
        WhisperCatalog.all.allSatisfy { isAvailable($0) }
    }

    func downloadAll() {
        guard !isDownloading else { return }
        let missing = WhisperCatalog.all.filter { !isAvailable($0) }
        guard !missing.isEmpty else { return }

        isDownloading = true
        Task {
            for whisper in missing {
                let remote = remoteURL(for: whisper)
                let local = localURL(for: whisper)
                do {
                    let (data, _) = try await URLSession.shared.data(from: remote)
                    try data.write(to: local)
                } catch {
                    print("[WhisperPlayer] Failed to download \(whisper.audioFileName): \(error)")
                }
            }
            await MainActor.run { self.isDownloading = false }
        }
    }

    func play(_ whisper: WhisperDefinition, volume: Float = 0.8) {
        let url = isAvailable(whisper) ? localURL(for: whisper) : remoteURL(for: whisper)
        let queue = AudioPriorityQueue.shared
        queue.playWhisper(url: url, volume: volume)
    }

    func preview(_ whisper: WhisperDefinition, volume: Float = 0.6) {
        let url = isAvailable(whisper) ? localURL(for: whisper) : remoteURL(for: whisper)
        stop()
        coordinator.activate(for: .playbackOnly, consumer: "whisper-preview")

        do {
            let data = try Data(contentsOf: url)
            let p = try AVAudioPlayer(data: data)
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
