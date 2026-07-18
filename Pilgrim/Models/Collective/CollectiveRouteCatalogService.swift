// Pilgrim/Models/Collective/CollectiveRouteCatalogService.swift
import Foundation
import Combine

/// Owns the collective-route artifact: loads a catalog from disk at launch,
/// refreshes it from the CDN, publishes whichever is current. Shaped after
/// `WhisperManifestService` — the cheap init, detached load, service-as-parameter
/// and await-before-compare each close a stall this app has already shipped once.
final class CollectiveRouteCatalogService: ObservableObject {

    static let shared = CollectiveRouteCatalogService()

    @Published private(set) var catalog: CollectiveRouteCatalog?
    @Published private(set) var isSyncing = false

    private let catalogDirectory: URL
    private let fetchRemoteData: () async -> Data?
    private(set) var initialLoad: Task<Void, Never>?
    /// Exposed for tests: nothing in the app awaits a sync, so without a handle they could only poll for its effects.
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
    /// hops back to main. Parameters are injectable for tests, the network included
    /// — the version comparison is the point of this unit.
    init(catalogDirectory: URL,
         bootstrapCatalogURL: @escaping () -> URL?,
         fetchRemoteData: @escaping () async -> Data? = { await CollectiveRouteCatalogService.fetchPublishedCatalog() }) {
        self.catalogDirectory = catalogDirectory
        self.fetchRemoteData = fetchRemoteData
        // Through the stored property, so the load path cannot drift from where saveLocalCatalog writes.
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
    // Reads must happen on main, because @Published state is only mutated there.
    // A caller that trips the assert needs to dispatch to main first. Until the
    // initial load lands these return nil, and no surface may assume otherwise.

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
        // Before the task is built, not inside it: a re-entrant call would otherwise
        // swap `syncTask` for a handle that returns at once, reading as a finished sync.
        guard !isSyncing else { return }

        syncTask = Task { @MainActor in
            isSyncing = true

            // Before the comparison, never after: a fast network response would
            // otherwise be overwritten by the bootstrap decode still in flight.
            await initialLoad?.value

            guard let data = await fetchRemoteData() else {
                isSyncing = false
                return
            }

            // Off main: this closure is @MainActor, so an inline decode would put
            // a JSON parse and the canonical sort on the main thread at launch —
            // issue #42's shape, on an artifact that can grow without a release.
            let decode = Task.detached(priority: .utility) {
                try? Self.decoder.decode(CollectiveRouteCatalog.self, from: data)
            }
            // An empty catalog is rejected like an undecodable one: arrays are optional
            // and elements decode lossily, so a bake dropping a field only Swift needs
            // — `companyLine` — parses cleanly into nothing and would cache dark.
            guard let remote = await decode.value, !remote.entries.isEmpty else {
                isSyncing = false
                return
            }

            // Inequality rather than `>`: the version carries no ordering, so a
            // curator reverting to a prior artifact has to reach devices too.
            if catalog?.version != remote.version {
                catalog = remote
                await saveLocalCatalog(data)
            }

            isSyncing = false
        }
    }

    // MARK: - Private

    private static func fetchPublishedCatalog() async -> Data? {
        // Bypass URLCache: the CDN serves this with an ETag but no Cache-Control,
        // so URLSession falls back to heuristic freshness and may replay a body the
        // curator has already rolled back — on the launch where the rollback has to land.
        var request = URLRequest(url: Config.Collective.routeCatalogURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return data
        } catch {
            print("[CollectiveRouteCatalogService] Failed to fetch catalog: \(error)")
            return nil
        }
    }

    /// Cache, then bundled bootstrap. An entry-less cached file is passed over rather
    /// than adopted — a build shipped before the sync guard could have written one,
    /// and serving it would shadow a working bootstrap for every offline launch.
    private static func loadInitialCatalog(localURL: URL, bootstrapURL: URL?) -> CollectiveRouteCatalog {
        if FileManager.default.fileExists(atPath: localURL.path),
           let data = try? Data(contentsOf: localURL),
           let saved = try? decoder.decode(CollectiveRouteCatalog.self, from: data),
           !saved.entries.isEmpty {
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

    /// Caches the exact bytes the CDN served rather than re-encoding the decoded
    /// catalog: a round-trip would strip every field this app ignores today,
    /// handing the next launch a thinner artifact than the one fetched.
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
