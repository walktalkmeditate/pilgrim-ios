import Foundation
import Combine

final class AudioManifestService: ObservableObject {

    static let shared = AudioManifestService()

    @Published private(set) var manifest: AudioManifest?
    @Published private(set) var isSyncing = false

    private let fileManager = FileManager.default
    private let downloadManager = AudioDownloadManager.shared

    private var localManifestURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Audio", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("manifest.json")
    }

    private init() {
        loadLocalManifest()
    }

    func syncIfNeeded() {
        Task { @MainActor in
            guard !isSyncing else { return }
            isSyncing = true

            let remote = await fetchRemoteManifest()

            guard let remote else {
                isSyncing = false
                return
            }

            if manifest?.version != remote.version {
                saveLocalManifest(remote)
                manifest = remote
            }

            if let current = manifest {
                downloadManager.downloadMissing(assets: current.assets)
            }

            isSyncing = false
        }
    }

    func bells(for usage: AudioAsset.UsageTag? = nil) -> [AudioAsset] {
        guard let manifest else { return [] }
        let bells = manifest.bells
        guard let usage else { return bells }
        return bells.filter { $0.usageTags.contains(usage) }
    }

    var soundscapes: [AudioAsset] {
        manifest?.soundscapes ?? []
    }

    func asset(byId id: String) -> AudioAsset? {
        manifest?.assets.first { $0.id == id }
    }

    private func fetchRemoteManifest() async -> AudioManifest? {
        do {
            let (data, response) = try await URLSession.shared.data(from: Config.Audio.manifestURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return try JSONDecoder().decode(AudioManifest.self, from: data)
        } catch {
            print("[AudioManifestService] Failed to fetch manifest: \(error)")
            return nil
        }
    }

    private func loadLocalManifest() {
        guard fileManager.fileExists(atPath: localManifestURL.path),
              let data = try? Data(contentsOf: localManifestURL),
              let saved = try? JSONDecoder().decode(AudioManifest.self, from: data) else {
            return
        }
        manifest = saved
    }

    private func saveLocalManifest(_ manifest: AudioManifest) {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: localManifestURL)
    }
}
