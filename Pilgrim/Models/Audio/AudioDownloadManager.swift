import Foundation
import Combine

final class AudioDownloadManager: ObservableObject {

    static let shared = AudioDownloadManager()

    @Published var downloadProgress: Double = 1.0
    @Published private(set) var isDownloading = false

    private let fileStore = AudioFileStore.shared
    private let session: URLSession
    private let maxConcurrent = 2

    private init() {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = maxConcurrent
        session = URLSession(configuration: config)
    }

    func downloadMissing(assets: [AudioAsset]) {
        Task { @MainActor in
            guard !isDownloading else { return }

            // The availability check stats one file per asset — keep that
            // disk I/O off the main thread (issue #42).
            let store = fileStore
            let missing = await Task.detached(priority: .utility) {
                assets.filter { !store.isAvailable($0) }
            }.value
            guard !missing.isEmpty, !isDownloading else { return }

            isDownloading = true
            downloadProgress = 0

            var completed = 0
            let total = missing.count

            for asset in missing {
                let success = await download(asset: asset)
                if !success {
                    let retrySuccess = await download(asset: asset)
                    if !retrySuccess {
                        print("[AudioDownloadManager] Failed to download \(asset.id) after retry")
                    }
                }
                completed += 1
                downloadProgress = Double(completed) / Double(total)
            }

            isDownloading = false
            downloadProgress = 1.0
        }
    }

    private func download(asset: AudioAsset) async -> Bool {
        let url = Config.Audio.r2BaseURL
            .appendingPathComponent(asset.type.rawValue)
            .appendingPathComponent("\(asset.id).aac")

        do {
            let (tempURL, response) = try await session.download(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return false
            }
            let dest = fileStore.destinationURL(for: asset)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tempURL, to: dest)
            return true
        } catch {
            print("[AudioDownloadManager] Download error for \(asset.id): \(error)")
            return false
        }
    }
}
