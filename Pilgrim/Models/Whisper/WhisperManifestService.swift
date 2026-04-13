// Pilgrim/Models/Whisper/WhisperManifestService.swift
import Foundation
import Combine

final class WhisperManifestService: ObservableObject {

    static let shared = WhisperManifestService()

    @Published private(set) var manifest: WhisperManifest?
    @Published private(set) var isSyncing = false

    private let fileManager = FileManager.default

    private var localManifestURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Whispers", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("manifest.json")
    }

    private init() {
        loadLocalManifest()
        if manifest == nil {
            loadBootstrapManifest()
        }
    }

    // MARK: - Public lookups
    //
    // All reads must happen on the main thread because @Published state
    // is only mutated on main (via syncIfNeeded's @MainActor Task and
    // synchronous init). If a future caller hits the assert, the call
    // site needs to dispatch to main first.

    func whispers(for category: WhisperCategory) -> [WhisperDefinition] {
        assert(Thread.isMainThread)
        return manifest?.whispers(in: category) ?? []
    }

    func placeableWhispers(for category: WhisperCategory) -> [WhisperDefinition] {
        assert(Thread.isMainThread)
        return manifest?.placeableWhispers(in: category) ?? []
    }

    func whisper(byId id: String) -> WhisperDefinition? {
        assert(Thread.isMainThread)
        return manifest?.whisper(withId: id)
    }

    func placeableCategories() -> [WhisperCategory] {
        assert(Thread.isMainThread)
        return manifest?.placeableCategories ?? []
    }

    // MARK: - Sync

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

            isSyncing = false
        }
    }

    // MARK: - Private

    private func fetchRemoteManifest() async -> WhisperManifest? {
        do {
            let (data, response) = try await URLSession.shared.data(from: Config.Whisper.manifestURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return try Self.decoder.decode(WhisperManifest.self, from: data)
        } catch {
            print("[WhisperManifestService] Failed to fetch manifest: \(error)")
            return nil
        }
    }

    private func loadLocalManifest() {
        guard fileManager.fileExists(atPath: localManifestURL.path),
              let data = try? Data(contentsOf: localManifestURL),
              let saved = try? Self.decoder.decode(WhisperManifest.self, from: data) else {
            return
        }
        manifest = saved
    }

    private func loadBootstrapManifest() {
        guard let url = Bundle.main.url(forResource: "whispers-bootstrap", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let bootstrap = try? Self.decoder.decode(WhisperManifest.self, from: data) else {
            // Shipped builds must include whispers-bootstrap.json so fresh
            // offline installs have a working catalog. If it is missing in
            // dev, fail loudly so the release workflow gap is obvious.
            assertionFailure("Missing whispers-bootstrap.json — run scripts/release.sh bootstrap-whispers and verify the file is in the Pilgrim target's Copy Bundle Resources phase")
            manifest = .empty
            return
        }
        manifest = bootstrap
    }

    private func saveLocalManifest(_ manifest: WhisperManifest) {
        guard let data = try? Self.encoder.encode(manifest) else { return }
        do {
            try data.write(to: localManifestURL)
        } catch {
            print("[WhisperManifestService] Failed to save manifest: \(error)")
        }
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
