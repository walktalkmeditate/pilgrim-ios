import AVFoundation

final class WhisperPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {

    static let shared = WhisperPlayer()

    private static let cdnBase = URL(string: "https://cdn.pilgrimapp.org/audio/whisper/")!

    private var player: AVAudioPlayer?
    private let coordinator = AudioSessionCoordinator.shared
    private let cacheDir: URL
    private var downloadTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isDownloading: Bool = false

    override private init() {
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
        downloadTask = Task { [weak self] in
            guard let self else { return }
            for whisper in missing {
                guard !Task.isCancelled else { break }
                let remote = remoteURL(for: whisper)
                let local = localURL(for: whisper)
                do {
                    let (data, _) = try await URLSession.shared.data(from: remote)
                    try data.write(to: local)
                } catch {
                    if !Task.isCancelled {
                        print("[WhisperPlayer] Failed to download \(whisper.audioFileName): \(error)")
                    }
                }
            }
            await MainActor.run { self.isDownloading = false }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
    }

    func play(_ whisper: WhisperDefinition, volume: Float = 0.8) {
        if isAvailable(whisper) {
            AudioPriorityQueue.shared.playWhisper(url: localURL(for: whisper), volume: volume)
        } else {
            Task { [weak self] in
                guard let self else { return }
                let remote = remoteURL(for: whisper)
                let local = localURL(for: whisper)
                do {
                    let (data, _) = try await URLSession.shared.data(from: remote)
                    try data.write(to: local)
                    await MainActor.run {
                        AudioPriorityQueue.shared.playWhisper(url: local, volume: volume)
                    }
                } catch {
                    print("[WhisperPlayer] Download-and-play failed: \(error)")
                }
            }
        }
    }

    func preview(_ whisper: WhisperDefinition, volume: Float = 0.6) {
        stop()
        coordinator.activate(for: .playbackOnly, consumer: "whisper-preview")

        if isAvailable(whisper) {
            playLocal(localURL(for: whisper), volume: volume)
        } else {
            previewTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let (data, _) = try await URLSession.shared.data(from: remoteURL(for: whisper))
                    guard !Task.isCancelled else { return }
                    await MainActor.run { self.playData(data, volume: volume) }
                } catch {
                    if !Task.isCancelled {
                        print("[WhisperPlayer] Preview download error: \(error)")
                    }
                    await MainActor.run { self.coordinator.deactivate(consumer: "whisper-preview") }
                }
            }
        }
    }

    private func playLocal(_ url: URL, volume: Float) {
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

    private func playData(_ data: Data, volume: Float) {
        do {
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
        previewTask?.cancel()
        previewTask = nil
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
