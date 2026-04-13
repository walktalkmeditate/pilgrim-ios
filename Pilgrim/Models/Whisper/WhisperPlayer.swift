// Pilgrim/Models/Whisper/WhisperPlayer.swift
import AVFoundation

final class WhisperPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {

    static let shared = WhisperPlayer()

    private var player: AVAudioPlayer?
    private let coordinator = AudioSessionCoordinator.shared
    private let cacheDir: URL
    private var previewTask: Task<Void, Never>?
    private var prefetchTasks: [WhisperCategory: Task<Void, Never>] = [:]

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isPrefetching: Bool = false

    override private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDir = appSupport.appendingPathComponent("Whispers", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        super.init()
        seedMissingBundledFiles()
    }

    // MARK: - Bundled seed

    /// Per-file bundled seeding. For every whisper in the manifest, if the
    /// audio file is missing from the on-disk cache but present in the app
    /// bundle, copy it across.
    ///
    /// This handles three cases with one pass:
    ///  - Fresh install: cache is empty, all bundled files get copied.
    ///  - App update that adds new bundled whispers (e.g., a Play drop):
    ///    existing files stay, new ones get seeded — so users upgrading
    ///    from a pre-release build don't have to re-download everything.
    ///  - Partially-seeded cache (rare, e.g., prior launch crashed mid-copy):
    ///    the remaining files finish on the next launch.
    ///
    /// The check is cheap: one stat(2) per whisper per launch, called once
    /// from init. Missing bundled files fall through to the network path in
    /// `play()` and `preview()`.
    private func seedMissingBundledFiles() {
        let whispers = WhisperManifestService.shared.manifest?.whispers ?? []
        for whisper in whispers {
            let destination = cacheDir.appendingPathComponent("\(whisper.audioFileName).aac")
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
            guard let source = Bundle.main.url(forResource: whisper.audioFileName, withExtension: "aac") else { continue }
            do {
                try FileManager.default.copyItem(at: source, to: destination)
            } catch {
                print("[WhisperPlayer] Failed to seed \(whisper.audioFileName): \(error)")
            }
        }
    }

    // MARK: - Lookups

    private func localURL(for whisper: WhisperDefinition) -> URL {
        cacheDir.appendingPathComponent("\(whisper.audioFileName).aac")
    }

    private func remoteURL(for whisper: WhisperDefinition) -> URL {
        Config.Whisper.cdnBaseURL.appendingPathComponent("\(whisper.audioFileName).aac")
    }

    func isAvailable(_ whisper: WhisperDefinition) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: whisper).path)
    }

    /// Rejects truncated downloads by comparing actual bytes against the
    /// Content-Length header (when present). Returns true if the response
    /// looks complete.
    private static func isResponseComplete(data: Data, response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
        if let expected = http.value(forHTTPHeaderField: "Content-Length"),
           let expectedSize = Int(expected),
           data.count != expectedSize {
            print("[WhisperPlayer] Truncated download: expected \(expectedSize) bytes, got \(data.count)")
            return false
        }
        return true
    }

    // MARK: - Prefetch

    /// Best-effort background download of all uncached whispers in a category.
    /// Called when the user selects a category in WhisperPlacementSheet, so
    /// by the time they tap "Leave Whisper", the picked file is almost always
    /// already local.
    func prefetchCategory(_ category: WhisperCategory) {
        prefetchTasks[category]?.cancel()
        let uncached = WhisperManifestService.shared
            .whispers(for: category)
            .filter { !isAvailable($0) }
        guard !uncached.isEmpty else { return }

        isPrefetching = true
        prefetchTasks[category] = Task { [weak self] in
            guard let self else { return }
            for whisper in uncached {
                guard !Task.isCancelled else { break }
                let remote = remoteURL(for: whisper)
                let local = localURL(for: whisper)
                do {
                    let (data, response) = try await URLSession.shared.data(from: remote)
                    guard Self.isResponseComplete(data: data, response: response) else { continue }
                    try data.write(to: local)
                } catch {
                    if !Task.isCancelled {
                        print("[WhisperPlayer] Prefetch failed for \(whisper.audioFileName): \(error)")
                    }
                }
            }
            await MainActor.run {
                // If this task was cancelled mid-flight, a replacement
                // prefetch for the same category has already claimed the
                // slot — don't erase it or reset isPrefetching.
                guard !Task.isCancelled else { return }
                self.prefetchTasks[category] = nil
                self.isPrefetching = !self.prefetchTasks.isEmpty
            }
        }
    }

    // MARK: - Play / preview (unchanged semantics)

    func play(_ whisper: WhisperDefinition, volume: Float = 0.8) {
        if isAvailable(whisper) {
            AudioPriorityQueue.shared.playWhisper(url: localURL(for: whisper), volume: volume)
        } else {
            Task { [weak self] in
                guard let self else { return }
                let remote = remoteURL(for: whisper)
                let local = localURL(for: whisper)
                do {
                    let (data, response) = try await URLSession.shared.data(from: remote)
                    guard Self.isResponseComplete(data: data, response: response) else { return }
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
                    let (data, response) = try await URLSession.shared.data(from: remoteURL(for: whisper))
                    guard !Task.isCancelled else { return }
                    guard Self.isResponseComplete(data: data, response: response) else {
                        await MainActor.run { self.coordinator.deactivate(consumer: "whisper-preview") }
                        return
                    }
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
