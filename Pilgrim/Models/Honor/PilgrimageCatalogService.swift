import Combine
import Foundation

/// `Hashable` as well as `Identifiable`: the route view is pushed with
/// `navigationDestination(item:)`, which takes a `Hashable` item.
struct PilgrimageCatalogEntry: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let name: String
    let names: [String: String]
    let country: String?
    let region: String?
    let distanceKm: Double
    let tradition: String?
    let stageCount: Int
    let bytes: Int
    /// Curated places per stage beyond the start and end towns, as the
    /// build's coverage report measured them.
    let placesPerStage: Double
    /// The build's own verdict: fewer than half this route's stages carry a
    /// curated place. True of the Camino Francés today, so the catalog says
    /// so rather than letting the route promise more than it holds.
    let sparse: Bool

    /// The two coverage fields default, so a literal that does not care
    /// about them stays short and an older cache is the only thing that has
    /// to be refetched.
    init(id: String, name: String, names: [String: String], country: String?, region: String?,
         distanceKm: Double, tradition: String?, stageCount: Int, bytes: Int,
         placesPerStage: Double = 0, sparse: Bool = false) {
        self.id = id
        self.name = name
        self.names = names
        self.country = country
        self.region = region
        self.distanceKm = distanceKm
        self.tradition = tradition
        self.stageCount = stageCount
        self.bytes = bytes
        self.placesPerStage = placesPerStage
        self.sparse = sparse
    }
}

struct PilgrimageCatalog: Codable, Equatable {
    /// The git tag every package file is then pinned to, so a route's stages
    /// are always from one build.
    let release: String
    let routes: [PilgrimageCatalogEntry]
}

/// The dataset's index, read from the repository's default branch at most
/// once a day. Nothing here reaches for a package: the catalog only says
/// which routes exist, how big they are, and which release to pin to.
@MainActor
final class PilgrimageCatalogService: ObservableObject {

    static let shared = PilgrimageCatalogService()

    /// `@main`, never `@v1`: jsDelivr caches a tag URL permanently, so a tag
    /// that the release step moves still serves the bytes it first saw — the
    /// `v1` alias returns a March index with three routes while `v1.6.0` has
    /// seven. A branch ref refreshes on jsDelivr's own 12 h cycle, and the
    /// 24 h cache below sits on top of it. Package files stay pinned to the
    /// exact `release` tag the index names, because those tags never move.
    static let indexURL = URL(string: "https://cdn.jsdelivr.net/gh/walktalkmeditate/open-pilgrimages@main/index.json")!
    private static let packageBase = "https://cdn.jsdelivr.net/gh/walktalkmeditate/open-pilgrimages"

    static let maxIndexBytes = 256 * 1024
    static let cacheLifetime: TimeInterval = 24 * 3600
    static let maxDistanceKm = 10_000.0
    static let maxStageCount = 200
    static let maxPackageBytes = 50 * 1024 * 1024
    /// A stage cannot plausibly carry fifty curated places; anything beyond
    /// this is a broken report, not a rich route.
    static let maxPlacesPerStage = 50.0

    @Published private(set) var catalog: PilgrimageCatalog?

    private let session: URLSession
    private let directory: URL
    private let now: () -> Date

    /// The overview's copy promises a quick answer, so the catalog gets its
    /// own short-lived session rather than `.shared`'s multi-minute defaults —
    /// the same reasoning as `WayImporter.defaultSession`. `nonisolated`:
    /// an init's default-argument expressions run in a generator function
    /// outside the type's actor, so a `@MainActor`-inferred static here
    /// would not build.
    nonisolated private static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    nonisolated private static var defaultDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Pilgrimages", isDirectory: true)
    }

    init(session: URLSession = PilgrimageCatalogService.defaultSession,
         directory: URL = PilgrimageCatalogService.defaultDirectory,
         now: @escaping () -> Date = Date.init) {
        self.session = session
        self.directory = directory
        self.now = now
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - URLs

    /// Package files are pinned to the exact tag the index named. Both the
    /// release and the route id are validated before either reaches a URL,
    /// and the file name is drawn from a closed set — a path is never built
    /// from a string the dataset chose.
    static func packageURL(release: String, routeId: String, file: String) -> URL? {
        guard isValidRelease(release), WayStore.isValidRouteId(routeId),
              file.range(of: "\\A(route\\.json|stage-[0-9]{2,3}\\.json)\\z", options: .regularExpression) != nil,
              let url = URL(string: "\(packageBase)@\(release)/routes/\(routeId)/ways/\(file)") else { return nil }
        return url
    }

    static func isValidRelease(_ release: String) -> Bool {
        release.range(of: "\\Av[0-9]+\\.[0-9]+\\.[0-9]+\\z", options: .regularExpression) != nil
    }

    // MARK: - Loading

    /// Serves the cache while it is under a day old, then asks the CDN. A
    /// failed fetch with a cache on disk degrades silently to that cache —
    /// the catalog still shows what is on the phone.
    @discardableResult
    func load(force: Bool = false) async throws -> PilgrimageCatalog {
        let cached = readCache()
        if !force, let cached, now().timeIntervalSince(cached.fetchedAt) < Self.cacheLifetime {
            catalog = cached.catalog
            return cached.catalog
        }
        do {
            let fresh = try Self.parse(try await fetchIndex())
            writeCache(Cached(fetchedAt: now(), catalog: fresh))
            catalog = fresh
            return fresh
        } catch {
            if let cached {
                catalog = cached.catalog
                return cached.catalog
            }
            throw PilgrimageError.catalogUnreachable
        }
    }

    /// A route's `route.json` before its package is downloaded, so the route
    /// screen can list the stages the pilgrim is being offered. Same byte cap
    /// and same validation as the download path; cached beside the index so
    /// reopening a route costs nothing. The preview never writes into the
    /// package folder — only `PilgrimagePackageManager` installs a route.
    func routePreview(entry: PilgrimageCatalogEntry, release: String) async throws -> PilgrimageRoute {
        if let cached = readRoutePreview(routeId: entry.id, release: release) { return cached }
        guard let url = Self.packageURL(release: release, routeId: entry.id, file: "route.json") else {
            throw PilgrimageError.notWalkable
        }
        let data = try await Self.fetch(url, cap: PilgrimageWayImporter.maxRouteBytes, session: session)
        let route = try PilgrimageWayImporter.route(from: data)
        // The same identity check the download makes: a route file that
        // disagrees with the index is not the route being offered.
        guard route.id == entry.id, route.stageCount == entry.stageCount,
              route.stages.count == entry.stageCount else { throw PilgrimageError.notWalkable }
        writeRoutePreview(data, routeId: entry.id, release: release)
        return route
    }

    /// Keyed by release as well as route: a preview from an older build must
    /// never stand in for the stages the current index names.
    private func routePreviewURL(routeId: String, release: String) -> URL? {
        guard WayStore.isValidRouteId(routeId), Self.isValidRelease(release) else { return nil }
        return directory.appendingPathComponent("route-\(routeId)-\(release).json")
    }

    private func readRoutePreview(routeId: String, release: String) -> PilgrimageRoute? {
        guard let url = routePreviewURL(routeId: routeId, release: release),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? PilgrimageWayImporter.route(from: data)
    }

    private func writeRoutePreview(_ data: Data, routeId: String, release: String) {
        guard let url = routePreviewURL(routeId: routeId, release: release) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func fetchIndex() async throws -> Data {
        try await Self.fetch(Self.indexURL, cap: Self.maxIndexBytes, session: session)
    }

    /// Streamed with a cap, checked before draining: an oversized declared
    /// length must not cost a full download first.
    ///
    /// `nonisolated`, and handed the session rather than reading it off
    /// `self`: the drain is a byte at a time, and on the main actor a quarter
    /// of a megabyte of index would run the whole of it between the screen's
    /// frames. This is the shape `PilgrimagePackageManager.fetch` already has.
    nonisolated private static func fetch(_ url: URL, cap: Int, session: URLSession) async throws -> Data {
        do {
            let (bytes, response) = try await session.bytes(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.expectedContentLength <= Int64(cap) else { throw PilgrimageError.catalogUnreachable }
            var buffer = Data()
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count > cap { throw PilgrimageError.catalogUnreachable }
            }
            return buffer
        } catch let error as PilgrimageError {
            throw error
        } catch {
            throw PilgrimageError.catalogUnreachable
        }
    }

    // MARK: - Parsing

    private struct IndexFile: Decodable {
        struct Ways: Decodable {
            let stageCount: Int
            let bytes: Int
            /// Both optional: an index written before the build measured
            /// coverage still parses, as a dense route with no figure.
            let placesPerStage: Double?
            let sparse: Bool?
        }
        struct Route: Decodable {
            let id: String
            let name: [String: String]
            let region: String?
            let country: String?
            let distanceKm: Double
            let tradition: String?
            let ways: Ways?
        }
        let release: String
        let routes: [Route]
    }

    /// A route without a `ways` entry failed the build's length gate and the
    /// app hides it; a route the build only flagged `sparse` is still listed,
    /// and says so on its card. A route whose id or numbers fail validation
    /// is dropped rather than failing the whole catalog: one bad row must not
    /// cost the pilgrim every route.
    static func parse(_ data: Data) throws -> PilgrimageCatalog {
        guard let file = try? JSONDecoder().decode(IndexFile.self, from: data),
              isValidRelease(file.release) else { throw PilgrimageError.catalogUnreachable }
        let routes = file.routes.compactMap { row -> PilgrimageCatalogEntry? in
            guard let ways = row.ways, WayStore.isValidRouteId(row.id),
                  row.distanceKm.isFinite, (0...maxDistanceKm).contains(row.distanceKm),
                  (1...maxStageCount).contains(ways.stageCount),
                  (0..<maxPackageBytes).contains(ways.bytes),
                  ways.placesPerStage.map({ $0.isFinite && (0...maxPlacesPerStage).contains($0) }) ?? true
            else { return nil }
            let names = row.name.filter { $0.key.range(of: "\\A[a-z]{2,3}\\z", options: .regularExpression) != nil }
            guard let display = names["en"] ?? names.sorted(by: { $0.key < $1.key }).first?.value else { return nil }
            return PilgrimageCatalogEntry(
                id: row.id,
                name: String(display.prefix(PilgrimageWayImporter.maxStageNameCharacters)),
                names: names.mapValues { String($0.prefix(PilgrimageWayImporter.maxStageNameCharacters)) },
                country: row.country.map { String($0.prefix(WayImporter.maxLabelCharacters)) },
                region: row.region.map { String($0.prefix(WayImporter.maxLabelCharacters)) },
                distanceKm: row.distanceKm,
                tradition: row.tradition.map { String($0.prefix(WayImporter.maxLabelCharacters)) },
                stageCount: ways.stageCount,
                bytes: ways.bytes,
                placesPerStage: ways.placesPerStage ?? 0,
                sparse: ways.sparse ?? false)
        }
        // First wins: a repeated id downstream would trap `Dictionary(uniqueKeysWithValues:)`
        // and hand `List` two rows with the same `Identifiable` id.
        var seenIds = Set<String>()
        let deduped = routes.filter { seenIds.insert($0.id).inserted }
        return PilgrimageCatalog(release: file.release, routes: deduped)
    }

    // MARK: - Cache

    private struct Cached: Codable {
        let fetchedAt: Date
        let catalog: PilgrimageCatalog
    }

    private var cacheURL: URL { directory.appendingPathComponent("catalog.json") }

    /// A cache written by a build that did not know about the coverage
    /// fields fails to decode and is simply refetched — there is nothing in
    /// it worth a migration.
    private func readCache() -> Cached? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Cached.self, from: data)
    }

    private func writeCache(_ cached: Cached) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(cached).write(to: cacheURL, options: .atomic)
    }
}
