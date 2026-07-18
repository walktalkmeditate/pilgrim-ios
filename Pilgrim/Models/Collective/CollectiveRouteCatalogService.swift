// Pilgrim/Models/Collective/CollectiveRouteCatalogService.swift
import Foundation
import Combine

/// Owns the collective-route artifact: loads a catalog from disk at launch,
/// refreshes it from the CDN, and publishes whichever is current.
///
/// Shaped after `WhisperManifestService` deliberately rather than approximately.
/// The pieces that look like ceremony — the cheap convenience init, the detached
/// initial load, the service-as-parameter load factory, the await before the
/// version comparison — are each closing a specific failure this app has already
/// shipped once.
final class CollectiveRouteCatalogService: ObservableObject {

    static let shared = CollectiveRouteCatalogService()

    @Published private(set) var catalog: CollectiveRouteCatalog?
    @Published private(set) var isSyncing = false

    private let catalogDirectory: URL
    private let fetchRemoteData: () async -> Data?
    private(set) var initialLoad: Task<Void, Never>?
    /// Exposed for the same reason as `initialLoad`: nothing in the app awaits a
    /// sync, so without a handle the tests could only poll for its effects.
    private(set) var syncTask: Task<Void, Never>?

    private static let cacheFileName = "routes.json"

    private var localCatalogURL: URL {
        catalogDirectory.appendingPathComponent(Self.cacheFileName)
    }

    private convenience init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.init(
            catalogDirectory: appSupport.appendingPathComponent("CollectiveRoutes", isDirectory: true),
            bootstrapCatalogURL: { Bundle.main.url(forResource: "collective-routes-bootstrap", withExtension: "json") }
        )
    }

    /// Init must stay cheap: the first `.shared` touch happens on the main
    /// thread during the welcome entrance (issue #42), so the cache / bootstrap
    /// disk reads and JSON decodes run in a detached task and only the publish
    /// hops back to main. Parameters are injectable for tests.
    ///
    /// The network is injectable too, which `WhisperManifestService` does not
    /// need to be — its remote path has no test. This one's version comparison
    /// is the whole point of the unit, and it cannot be exercised through
    /// `URLSession.shared`.
    init(catalogDirectory: URL,
         bootstrapCatalogURL: @escaping () -> URL?,
         fetchRemoteData: @escaping () async -> Data? = { await CollectiveRouteCatalogService.fetchPublishedCatalog() }) {
        self.catalogDirectory = catalogDirectory
        self.fetchRemoteData = fetchRemoteData
        // Read through the stored property rather than re-deriving the path, so
        // the load path cannot drift from where saveLocalCatalog writes.
        initialLoad = Self.makeInitialLoad(service: self, localURL: localCatalogURL, bootstrapCatalogURL: bootstrapCatalogURL)
    }

    /// Loads off main (disk reads + JSON decodes, including bootstrap fallback)
    /// and publishes on main. Taking `service` as a parameter keeps the
    /// publishing closure from capturing the still-mutable `self` binding inside
    /// `init` (Swift 6 concurrency rule).
    private static func makeInitialLoad(
        service: CollectiveRouteCatalogService,
        localURL: URL,
        bootstrapCatalogURL: @escaping () -> URL?
    ) -> Task<Void, Never> {
        #if DEBUG
        let initStart = CFAbsoluteTimeGetCurrent()
        #endif
        return Task.detached(priority: .utility) { [weak service] in
            let loaded = loadInitialCatalog(localURL: localURL, bootstrapURL: bootstrapCatalogURL())
            await MainActor.run { [service] in
                guard let service, service.catalog == nil else { return }
                service.catalog = loaded
                #if DEBUG
                let dt = (CFAbsoluteTimeGetCurrent() - initStart) * 1000
                print(String(format: "[LaunchProfile] CollectiveRouteCatalogService catalog ready +%.0fms after first access (loaded off main)", dt))
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
    // initial load lands, lookups return nothing — every surface has to
    // tolerate that window rather than assume a catalog on first frame.

    func dailyLine(for date: Date, collectiveKm: Double?) -> String? {
        assert(Thread.isMainThread)
        return catalog?.dailyLine(for: date, collectiveKm: collectiveKm)
    }

    func contributionLine(for date: Date, walkKm: Double) -> String? {
        assert(Thread.isMainThread)
        return catalog?.contributionLine(for: date, walkKm: walkKm)
    }

    // MARK: - Sync

    func syncIfNeeded() {
        syncTask = Task { @MainActor in
            guard !isSyncing else { return }
            isSyncing = true

            // Before the comparison, never after: a fast network response
            // would otherwise be published and then overwritten by the
            // bootstrap decode still in flight.
            await initialLoad?.value

            guard let data = await fetchRemoteData() else {
                isSyncing = false
                return
            }

            // Decoded off main. This closure is @MainActor, so decoding inline
            // would put a JSON parse and the canonical sort on the main thread
            // at launch — the same shape as issue #42's stall, on an artifact
            // that is curator-editable and can grow without an app release.
            // The raw bytes stay in scope for the cache write below.
            let decode = Task.detached(priority: .utility) {
                try? Self.decoder.decode(CollectiveRouteCatalog.self, from: data)
            }
            guard let remote = await decode.value else {
                isSyncing = false
                return
            }

            // Inequality rather than `>`: the version is content-derived and
            // carries no ordering, so a curator reverting to a prior artifact
            // has to reach devices too.
            if catalog?.version != remote.version {
                catalog = remote
                await saveLocalCatalog(data)
            }

            isSyncing = false
        }
    }

    // MARK: - Private

    private static func fetchPublishedCatalog() async -> Data? {
        do {
            let (data, response) = try await URLSession.shared.data(from: Config.Collective.routeCatalogURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return data
        } catch {
            print("[CollectiveRouteCatalogService] Failed to fetch catalog: \(error)")
            return nil
        }
    }

    private static func loadInitialCatalog(localURL: URL, bootstrapURL: URL?) -> CollectiveRouteCatalog {
        if FileManager.default.fileExists(atPath: localURL.path),
           let data = try? Data(contentsOf: localURL),
           let saved = try? decoder.decode(CollectiveRouteCatalog.self, from: data) {
            return saved
        }
        guard let bootstrapURL,
              let data = try? Data(contentsOf: bootstrapURL),
              let bootstrap = try? decoder.decode(CollectiveRouteCatalog.self, from: data) else {
            // Shipped builds must include collective-routes-bootstrap.json so
            // fresh offline installs still rotate a route. If it is missing in
            // dev, fail loudly so the release workflow gap is obvious.
            assertionFailure("Missing collective-routes-bootstrap.json — run scripts/regen-route-bootstrap.sh and verify the file is in the Pilgrim target's Copy Bundle Resources phase")
            return .empty
        }
        return bootstrap
    }

    /// Caches the exact bytes the CDN served instead of re-encoding the decoded
    /// catalog. `CollectiveRouteCatalog` is decode-only by design, and a
    /// round-trip through an encoder would strip every field this app ignores
    /// today — handing the next launch a thinner artifact than the one fetched,
    /// and one that a later app version could no longer grow into.
    private func saveLocalCatalog(_ data: Data) async {
        let url = localCatalogURL
        await Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            } catch {
                print("[CollectiveRouteCatalogService] Failed to save catalog: \(error)")
            }
        }.value
    }

    private static let decoder = JSONDecoder()
}
