import Foundation
import Combine

final class AudioManifestService: ObservableObject {

    static let shared = AudioManifestService()

    @Published private(set) var manifest: AudioManifest?
    @Published private(set) var isSyncing = false

    private let downloadManager = AudioDownloadManager.shared
    private let manifestDirectory: URL
    private(set) var initialLoad: Task<Void, Never>?

    private var localManifestURL: URL {
        manifestDirectory.appendingPathComponent("manifest.json")
    }

    private convenience init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.init(manifestDirectory: appSupport.appendingPathComponent("Audio", isDirectory: true))
    }

    /// Init must stay cheap: the first `.shared` touch happens on the main
    /// thread during the welcome entrance (issue #42), so the local-manifest
    /// disk read and JSON decode run in a detached task and only the publish
    /// hops back to main. `manifestDirectory` is injectable for tests.
    init(manifestDirectory: URL) {
        self.manifestDirectory = manifestDirectory
        let localURL = manifestDirectory.appendingPathComponent("manifest.json")
        initialLoad = Self.makeInitialLoad(service: self, localURL: localURL)
    }

    /// Loads off main (disk read + JSON decode) and publishes on main. Taking
    /// `service` as a parameter keeps the publishing closure from capturing the
    /// still-mutable `self` binding inside `init` (Swift 6 concurrency rule).
    private static func makeInitialLoad(service: AudioManifestService, localURL: URL) -> Task<Void, Never> {
        #if DEBUG
        let initStart = CFAbsoluteTimeGetCurrent()
        #endif
        return Task.detached(priority: .utility) { [weak service] in
            guard let loaded = readLocalManifest(at: localURL) else { return }
            await MainActor.run { [service] in
                guard let service, service.manifest == nil else { return }
                service.manifest = loaded
                #if DEBUG
                let dt = (CFAbsoluteTimeGetCurrent() - initStart) * 1000
                print(String(format: "[LaunchProfile] AudioManifestService manifest ready +%.0fms after first access (loaded off main)", dt))
                #endif
            }
        }
    }

    func syncIfNeeded() {
        Task { @MainActor in
            guard !isSyncing else { return }
            isSyncing = true

            await initialLoad?.value

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

    private static func readLocalManifest(at url: URL) -> AudioManifest? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(AudioManifest.self, from: data)
    }

    private func saveLocalManifest(_ manifest: AudioManifest) {
        let url = localManifestURL
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(manifest) else { return }
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            } catch {
                print("[AudioManifestService] Failed to save manifest: \(error)")
            }
        }
    }
}
