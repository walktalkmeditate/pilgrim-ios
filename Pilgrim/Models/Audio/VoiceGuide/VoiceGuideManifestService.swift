import Foundation
import Combine

final class VoiceGuideManifestService: ObservableObject {

    static let shared = VoiceGuideManifestService()

    @Published private(set) var packs: [VoiceGuidePack] = []
    @Published private(set) var isSyncing = false

    private let manifestDirectory: URL
    private var localManifestVersion: String?
    private(set) var initialLoad: Task<Void, Never>?

    private var localManifestURL: URL {
        manifestDirectory.appendingPathComponent("manifest.json")
    }

    private convenience init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.init(manifestDirectory: appSupport.appendingPathComponent("Audio/voiceguide", isDirectory: true))
    }

    /// Init must stay cheap: the first `.shared` touch happens on the main
    /// thread during the welcome entrance (issue #42), so the local-manifest
    /// disk read and JSON decode run in a detached task and only the publish
    /// hops back to main. `manifestDirectory` is injectable for tests.
    init(manifestDirectory: URL) {
        self.manifestDirectory = manifestDirectory
        let localURL = manifestDirectory.appendingPathComponent("manifest.json")
        #if DEBUG
        let initStart = CFAbsoluteTimeGetCurrent()
        #endif
        initialLoad = Task.detached(priority: .utility) { [weak self] in
            guard let loaded = Self.readLocalManifest(at: localURL) else { return }
            await MainActor.run {
                guard let self, self.packs.isEmpty else { return }
                self.packs = loaded.packs
                self.localManifestVersion = loaded.version
                #if DEBUG
                let dt = (CFAbsoluteTimeGetCurrent() - initStart) * 1000
                print(String(format: "[LaunchProfile] VoiceGuideManifestService manifest ready +%.0fms after first access (loaded off main)", dt))
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

            if let remote {
                if localManifestVersion != remote.version {
                    saveLocalManifest(remote)
                }
                packs = remote.packs
            }

            isSyncing = false
        }
    }

    func pack(byId id: String) -> VoiceGuidePack? {
        packs.first { $0.id == id }
    }

    private func fetchRemoteManifest() async -> VoiceGuideManifest? {
        do {
            let (data, response) = try await URLSession.shared.data(from: Config.VoiceGuide.manifestURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return try JSONDecoder().decode(VoiceGuideManifest.self, from: data)
        } catch {
            print("[VoiceGuideManifestService] Failed to fetch manifest: \(error)")
            return nil
        }
    }

    private static func readLocalManifest(at url: URL) -> VoiceGuideManifest? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(VoiceGuideManifest.self, from: data)
    }

    private func saveLocalManifest(_ manifest: VoiceGuideManifest) {
        let url = localManifestURL
        Task.detached(priority: .utility) { [weak self] in
            guard let data = try? JSONEncoder().encode(manifest) else { return }
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            } catch {
                print("[VoiceGuideManifestService] Failed to save manifest: \(error)")
                return
            }
            await MainActor.run {
                self?.localManifestVersion = manifest.version
            }
        }
    }
}
