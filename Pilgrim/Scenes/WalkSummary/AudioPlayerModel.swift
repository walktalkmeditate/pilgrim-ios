import AVFoundation

class AudioPlayerModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var currentPath: String?
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var currentTime: TimeInterval = 0
    @Published var totalDuration: TimeInterval = 0
    @Published var playbackSpeed: Float = 1.0

    private static let speeds: [Float] = [1.0, 1.5, 2.0]

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?

    /// Dismissing the owning view mid-playback deallocates the model without
    /// stop() — without this, the 10Hz timer fires no-ops for the rest of
    /// the session and the "audioPlayer" consumer wedges the coordinator
    /// active forever. Avoids stopPlayer() so no @Published writes happen
    /// during deinit.
    deinit {
        progressTimer?.invalidate()
        player?.delegate = nil
        player?.stop()
        AudioSessionCoordinator.shared.deactivate(consumer: "audioPlayer")
    }

    func toggle(relativePath: String) {
        toggle(key: relativePath, url: Self.documentsURL(for: relativePath))
    }

    /// For audio that does not live under Documents (a shared Way's voices
    /// under Application Support): keyed by the file path instead.
    func toggle(url: URL) {
        toggle(key: url.path, url: url)
    }

    private func toggle(key: String, url: URL) {
        if currentPath == key {
            if isPlaying {
                pause()
            } else if player != nil {
                resume()
            }
        } else {
            play(url: url, key: key)
        }
    }

    private static func documentsURL(for relativePath: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(relativePath)
    }

    func cycleSpeed() {
        guard let idx = Self.speeds.firstIndex(of: playbackSpeed) else {
            playbackSpeed = 1.0
            player?.rate = 1.0
            return
        }
        let next = Self.speeds[(idx + 1) % Self.speeds.count]
        playbackSpeed = next
        player?.rate = next
    }

    func play(relativePath: String) {
        play(url: Self.documentsURL(for: relativePath), key: relativePath)
    }

    func play(url: URL) {
        play(url: url, key: url.path)
    }

    private func play(url: URL, key: String) {
        stopPlayer()

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[AudioPlayerModel] File not found: \(url.path)")
            return
        }

        do {
            AudioSessionCoordinator.shared.activate(for: .playbackOnly, consumer: "audioPlayer")
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.volume = 1.0
            p.enableRate = true
            p.rate = playbackSpeed
            p.prepareToPlay()
            guard p.play() else {
                print("[AudioPlayerModel] play() returned false")
                AudioSessionCoordinator.shared.deactivate(consumer: "audioPlayer")
                return
            }
            player = p
            currentPath = key
            totalDuration = p.duration
            isPlaying = true
            startProgressTimer()
        } catch {
            print("[AudioPlayerModel] Playback error: \(error)")
            AudioSessionCoordinator.shared.deactivate(consumer: "audioPlayer")
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopProgressTimer()
    }

    func resume() {
        guard let p = player else { return }
        p.play()
        isPlaying = true
        startProgressTimer()
    }

    func seek(to fraction: Double) {
        guard let p = player else { return }
        p.currentTime = fraction * p.duration
        updateProgress()
    }

    func stop() {
        stopPlayer()
        AudioSessionCoordinator.shared.deactivate(consumer: "audioPlayer")
    }

    private func stopPlayer() {
        stopProgressTimer()
        player?.delegate = nil
        player?.stop()
        player = nil
        currentPath = nil
        isPlaying = false
        progress = 0
        currentTime = 0
        totalDuration = 0
    }

    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func updateProgress() {
        guard let p = player else { return }
        currentTime = p.currentTime
        totalDuration = p.duration
        progress = p.duration > 0 ? p.currentTime / p.duration : 0
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.stopPlayer()
            AudioSessionCoordinator.shared.deactivate(consumer: "audioPlayer")
        }
    }
}
