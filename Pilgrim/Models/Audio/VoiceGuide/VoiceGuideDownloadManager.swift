import Foundation
import Combine

@MainActor
final class VoiceGuideDownloadManager: ObservableObject {

    static let shared = VoiceGuideDownloadManager()

    @Published var downloadProgress: [String: Double] = [:]
    @Published private(set) var activeDownloads: Set<String> = []
    /// Packs whose download finished with at least one file still missing
    /// (AF23). The settings row reads this to replace the silent revert-to-
    /// arrow with a visible "tap to retry" affordance.
    @Published private(set) var downloadErrors: Set<String> = []

    private let fileStore = VoiceGuideFileStore.shared
    private let session: URLSession
    private var downloadTasks: [String: Task<Void, Never>] = [:]

    private init() {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 2
        session = URLSession(configuration: config)
    }

    func downloadPack(_ pack: VoiceGuidePack) {
        guard !activeDownloads.contains(pack.id) else { return }

        activeDownloads.insert(pack.id)
        downloadErrors.remove(pack.id)
        downloadProgress[pack.id] = 0

        let task = Task {
            let allPrompts = pack.prompts + (pack.meditationPrompts ?? [])
            let missing = allPrompts.filter { !fileStore.isAvailable($0, packId: pack.id) }
            let total = missing.count
            guard total > 0 else {
                await MainActor.run {
                    self.downloadProgress[pack.id] = 1.0
                    self.activeDownloads.remove(pack.id)
                    self.downloadTasks[pack.id] = nil
                }
                return
            }

            var completed = 0
            var failures = 0
            for prompt in missing {
                guard !Task.isCancelled else { break }
                var success = await download(prompt: prompt, packId: pack.id)
                if !success {
                    success = await download(prompt: prompt, packId: pack.id)
                }
                if !success { failures += 1 }
                completed += 1
                let progressSnapshot = Double(completed) / Double(total)
                await MainActor.run {
                    self.downloadProgress[pack.id] = progressSnapshot
                }
            }

            let didFail = failures > 0 && !Task.isCancelled
            await MainActor.run {
                _ = self.activeDownloads.remove(pack.id)
                self.downloadTasks[pack.id] = nil
                if didFail {
                    self.downloadErrors.insert(pack.id)
                }
            }
        }
        downloadTasks[pack.id] = task
    }

    func cancelDownload(packId: String) {
        downloadTasks[packId]?.cancel()
        downloadTasks[packId] = nil
        activeDownloads.remove(packId)
        downloadProgress[packId] = nil
        downloadErrors.remove(packId)
    }

    private func download(prompt: VoiceGuidePrompt, packId: String) async -> Bool {
        let url = Config.VoiceGuide.baseURL
            .appendingPathComponent(packId)
            .appendingPathComponent("\(prompt.id).aac")

        do {
            let (tempURL, response) = try await session.download(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return false
            }
            let dest = fileStore.destinationURL(for: prompt, packId: packId)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tempURL, to: dest)
            return true
        } catch {
            print("[VoiceGuideDownloadManager] Download error for \(prompt.id): \(error)")
            return false
        }
    }
}
