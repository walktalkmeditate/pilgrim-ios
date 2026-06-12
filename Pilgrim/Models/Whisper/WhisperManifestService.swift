// Pilgrim/Models/Whisper/WhisperManifestService.swift
import Foundation
import Combine

final class WhisperManifestService: ObservableObject {

    static let shared = WhisperManifestService()

    @Published private(set) var manifest: WhisperManifest?
    @Published private(set) var isSyncing = false

    private let manifestDirectory: URL
    private(set) var initialLoad: Task<Void, Never>?

    private var localManifestURL: URL {
        manifestDirectory.appendingPathComponent("manifest.json")
    }

    private convenience init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.init(
            manifestDirectory: appSupport.appendingPathComponent("Whispers", isDirectory: true),
            bootstrapManifestURL: { Bundle.main.url(forResource: "whispers-bootstrap", withExtension: "json") }
        )
    }

    /// Init must stay cheap: the first `.shared` touch happens on the main
    /// thread during the welcome entrance (issue #42), so the local-manifest /
    /// bootstrap disk reads and JSON decodes run in a detached task and only
    /// the publish hops back to main. Parameters are injectable for tests.
    init(manifestDirectory: URL, bootstrapManifestURL: @escaping () -> URL?) {
        self.manifestDirectory = manifestDirectory
        let localURL = manifestDirectory.appendingPathComponent("manifest.json")
        #if DEBUG
        let initStart = CFAbsoluteTimeGetCurrent()
        #endif
        initialLoad = Task.detached(priority: .utility) { [weak self] in
            let loaded = Self.loadInitialManifest(localURL: localURL, bootstrapURL: bootstrapManifestURL())
            await MainActor.run {
                guard let self, self.manifest == nil else { return }
                self.manifest = loaded
                #if DEBUG
                let dt = (CFAbsoluteTimeGetCurrent() - initStart) * 1000
                print(String(format: "[LaunchProfile] WhisperManifestService manifest ready +%.0fms after first access (loaded off main)", dt))
                #endif
            }
        }
    }

    // MARK: - Public lookups
    //
    // All reads must happen on the main thread because @Published state
    // is only mutated on main (via syncIfNeeded's @MainActor Task and the
    // initial load's MainActor publish). If a future caller hits the
    // assert, the call site needs to dispatch to main first. Until the
    // initial load lands, lookups return empty results.

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

    private static func loadInitialManifest(localURL: URL, bootstrapURL: URL?) -> WhisperManifest {
        if FileManager.default.fileExists(atPath: localURL.path),
           let data = try? Data(contentsOf: localURL),
           let saved = try? decoder.decode(WhisperManifest.self, from: data) {
            return saved
        }
        guard let bootstrapURL,
              let data = try? Data(contentsOf: bootstrapURL),
              let bootstrap = try? decoder.decode(WhisperManifest.self, from: data) else {
            // Shipped builds must include whispers-bootstrap.json so fresh
            // offline installs have a working catalog. If it is missing in
            // dev, fail loudly so the release workflow gap is obvious.
            assertionFailure("Missing whispers-bootstrap.json — run scripts/release.sh bootstrap-whispers and verify the file is in the Pilgrim target's Copy Bundle Resources phase")
            return .empty
        }
        return bootstrap
    }

    private func saveLocalManifest(_ manifest: WhisperManifest) {
        let url = localManifestURL
        Task.detached(priority: .utility) {
            guard let data = try? Self.encoder.encode(manifest) else { return }
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            } catch {
                print("[WhisperManifestService] Failed to save manifest: \(error)")
            }
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
