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
        let missing = assets.filter { !fileStore.isAvailable($0) }
        guard !missing.isEmpty else { return }
        guard !isDownloading else { return }

        isDownloading = true
        downloadProgress = 0

        Task {
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
                await MainActor.run {
                    self.downloadProgress = Double(completed) / Double(total)
                }
            }

            await MainActor.run {
                self.isDownloading = false
                self.downloadProgress = 1.0
            }
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
