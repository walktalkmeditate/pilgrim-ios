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

    /// All whispers for a category, including retired. Used by WhisperPlayer
    /// when resolving existing placed whispers (map taps, proximity encounters).
    func whispers(for category: WhisperCategory) -> [WhisperDefinition] {
        (manifest?.whispers ?? []).filter { $0.category == category }
    }

    /// Non-retired whispers only. Used by WhisperPlacementSheet for the random
    /// placement pick.
    func placeableWhispers(for category: WhisperCategory) -> [WhisperDefinition] {
        (manifest?.whispers ?? []).filter { $0.category == category && $0.retiredAt == nil }
    }

    /// Full lookup by ID, including retired. Used when resolving the whisper_id
    /// on an existing placement.
    func whisper(byId id: String) -> WhisperDefinition? {
        manifest?.whispers.first { $0.id == id }
    }

    /// Categories that have at least one placeable whisper. WhisperPlacementSheet
    /// uses this to hide empty categories (e.g., when Play has not yet been
    /// populated post-code-ship).
    func placeableCategories() -> [WhisperCategory] {
        WhisperCategory.allCases.filter { !placeableWhispers(for: $0).isEmpty }
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
            print("[WhisperManifestService] No bootstrap manifest found; starting empty")
            manifest = .empty
            return
        }
        manifest = bootstrap
    }

    private func saveLocalManifest(_ manifest: WhisperManifest) {
        guard let data = try? Self.encoder.encode(manifest) else { return }
        try? data.write(to: localManifestURL)
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
