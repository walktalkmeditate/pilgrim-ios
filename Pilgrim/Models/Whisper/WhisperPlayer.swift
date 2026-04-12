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
        seedFromBundleIfEmpty()
    }

    // MARK: - Bundled seed

    /// First-launch seeding: if the cache directory has no whisper audio
    /// files, copy any bundled whisper .aac files into it. Subsequent launches
    /// skip the copy because files already exist.
    private func seedFromBundleIfEmpty() {
        let existing = (try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "aac" } ?? []
        guard existing.isEmpty else { return }

        guard let bundleDir = Bundle.main.url(forResource: "whisper-audio", withExtension: nil) else {
            // Bundle directory not present — fine in dev, files will download on demand
            return
        }

        let bundled = (try? FileManager.default.contentsOfDirectory(at: bundleDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "aac" } ?? []

        for file in bundled {
            let destination = cacheDir.appendingPathComponent(file.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: file, to: destination)
            } catch {
                print("[WhisperPlayer] Failed to seed \(file.lastPathComponent): \(error)")
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
                    let (data, _) = try await URLSession.shared.data(from: remote)
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
