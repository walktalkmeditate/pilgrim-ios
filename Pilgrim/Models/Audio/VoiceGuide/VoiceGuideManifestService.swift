import Foundation
import Combine

final class VoiceGuideManifestService: ObservableObject {

    static let shared = VoiceGuideManifestService()

    @Published private(set) var packs: [VoiceGuidePack] = []
    @Published private(set) var isSyncing = false

    private let fileManager = FileManager.default

    private var localManifestURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Audio/voiceguide", isDirectory: true)
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

            if let remote {
                let localVersion = (try? Data(contentsOf: localManifestURL))
                    .flatMap { try? JSONDecoder().decode(VoiceGuideManifest.self, from: $0) }?
                    .version

                if localVersion != remote.version {
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

    private func loadLocalManifest() {
        guard fileManager.fileExists(atPath: localManifestURL.path),
              let data = try? Data(contentsOf: localManifestURL),
              let saved = try? JSONDecoder().decode(VoiceGuideManifest.self, from: data) else {
            return
        }
        packs = saved.packs
    }

    private func saveLocalManifest(_ manifest: VoiceGuideManifest) {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: localManifestURL)
    }
}
