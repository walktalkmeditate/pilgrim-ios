import Combine
import Foundation

/// One route at a time, all or nothing. Files land in a temporary directory
/// and are validated there; only a complete, valid set is moved into the
/// store. A failure mid-way leaves the phone exactly as it was.
@MainActor
final class PilgrimagePackageManager: ObservableObject {

    static let shared = PilgrimagePackageManager()

    struct Installed: Equatable {
        let routeId: String
        let release: String
        let route: PilgrimageRoute
    }

    enum Phase: Equatable {
        case idle
        /// `total` counts `route.json` plus every stage file.
        case downloading(done: Int, total: Int)
        case failed(PilgrimageError)
    }

    @Published private(set) var phase: Phase = .idle

    /// Set by `MainCoordinatorView`. Downloading a second route, Replace,
    /// Update, and Remove are all refused while a walk is on.
    var isWalkActive: () -> Bool = { false }

    /// The commit's one write to the store, behind a seam so a spec can fail
    /// it mid-loop and prove the rollback below.
    var saveStage: (Way) throws -> Void

    /// The whole package's ceiling, counted on the bytes that actually land.
    /// Injectable so a spec need not serve 50 MB to prove it holds.
    var maxPackageBytes = PilgrimageCatalogService.maxPackageBytes

    let store: WayStore
    let ledgers: PilgrimageLedgerStore
    private let session: URLSession

    private static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    init(store: WayStore = .shared,
         ledgers: PilgrimageLedgerStore = PilgrimageLedgerStore(),
         session: URLSession = PilgrimagePackageManager.defaultSession) {
        self.store = store
        self.ledgers = ledgers
        self.session = session
        // Captures the parameter, not `self`: assigned before `self` is fully
        // initialized and free of a retain cycle either way.
        self.saveStage = { try store.save($0) }
    }

    /// Zero-padded from 00, widening only when a route needs it — the shape
    /// the build step emits.
    static func stageFileName(_ index: Int) -> String {
        String(format: index < 100 ? "stage-%02d.json" : "stage-%03d.json", index)
    }

    // MARK: - What is on the phone

    func installed() -> Installed? {
        for routeId in store.pilgrimageRouteIds() {
            guard let dir = store.pilgrimageDirectory(for: routeId),
                  let routeData = try? Data(contentsOf: dir.appendingPathComponent("route.json")),
                  let route = try? PilgrimageWayImporter.route(from: routeData),
                  let release = try? String(contentsOf: dir.appendingPathComponent("release.txt"), encoding: .utf8),
                  PilgrimageCatalogService.isValidRelease(release) else { continue }
            return Installed(routeId: routeId, release: release, route: route)
        }
        return nil
    }

    /// True when the catalog names a release the installed package was not
    /// built at. Any difference counts: the index only ever moves forward.
    func hasUpdate(catalogRelease: String) -> Bool {
        guard let installed = installed(), PilgrimageCatalogService.isValidRelease(catalogRelease) else { return false }
        return installed.release != catalogRelease
    }

    // MARK: - Download

    /// Fetches `route.json` and every stage at the exact release the index
    /// named, into a temporary directory, and swaps the finished set in.
    func download(entry: PilgrimageCatalogEntry, release: String) async throws {
        guard !isWalkActive() else { throw PilgrimageError.walkInProgress }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pilgrimage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        do {
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            let total = entry.stageCount + 1
            // Counted across every file, not per file: 200 stages each just
            // under the 2 MB per-file cap would otherwise be 400 MB.
            var packageBytes = 0
            let fetched = try await stageRouteFile(entry: entry, release: release, into: temp)
            packageBytes += fetched.bytes
            try checkBudget(packageBytes)
            phase = .downloading(done: 1, total: total)
            for index in 0..<fetched.route.stageCount {
                packageBytes += try await stageOneStage(entry: entry, release: release, index: index, into: temp)
                try checkBudget(packageBytes)
                phase = .downloading(done: index + 2, total: total)
            }
            try commit(routeId: entry.id, release: release, stageCount: fetched.route.stageCount, from: temp)
            phase = .idle
        } catch {
            let failure = (error as? PilgrimageError) ?? .incomplete
            phase = .failed(failure)
            throw failure
        }
    }

    /// The index's `bytes` is a figure the dataset wrote; this is the one the
    /// phone actually paid.
    private func checkBudget(_ bytes: Int) throws {
        guard bytes <= maxPackageBytes else { throw PilgrimageError.incomplete }
    }

    /// The route file must describe the route the catalog offered: a package
    /// whose own idea of itself differs from the index's is not walkable.
    private func stageRouteFile(entry: PilgrimageCatalogEntry, release: String, into temp: URL) async throws
        -> (route: PilgrimageRoute, bytes: Int) {
        let data = try await fetch(routeId: entry.id, release: release, file: "route.json",
                                   cap: PilgrimageWayImporter.maxRouteBytes)
        let route = try PilgrimageWayImporter.route(from: data)
        guard route.id == entry.id, route.stageCount == entry.stageCount,
              route.stages.count == entry.stageCount else { throw PilgrimageError.notWalkable }
        try write(data, to: temp.appendingPathComponent("route.json"))
        return (route, data.count)
    }

    /// Validated as it lands, then written in the store's own encoding, so
    /// the commit below is a decode-and-save rather than a second parse of
    /// untrusted bytes. Returns the bytes it cost.
    @discardableResult
    private func stageOneStage(entry: PilgrimageCatalogEntry, release: String, index: Int, into temp: URL) async throws -> Int {
        let data = try await fetch(routeId: entry.id, release: release, file: Self.stageFileName(index),
                                   cap: PilgrimageWayImporter.maxStageBytes)
        let way = try PilgrimageWayImporter.way(from: data, routeId: entry.id, stageIndex: index)
        try write(try Self.encoder.encode(way), to: temp.appendingPathComponent("\(index).way.json"))
        return data.count
    }

    private func fetch(routeId: String, release: String, file: String, cap: Int) async throws -> Data {
        guard let url = PilgrimageCatalogService.packageURL(release: release, routeId: routeId, file: file) else {
            throw PilgrimageError.notWalkable
        }
        do {
            let (bytes, response) = try await session.bytes(from: url)
            // Checked before draining: an oversized declared length must not
            // cost a full download first.
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.expectedContentLength <= Int64(cap) else { throw PilgrimageError.incomplete }
            var buffer = Data()
            buffer.reserveCapacity(min(cap, 256 * 1024))
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count > cap { throw PilgrimageError.incomplete }
            }
            return buffer
        } catch let error as PilgrimageError {
            throw error
        } catch {
            throw WayMediaDownloader.isDiskFull(error) ? PilgrimageError.diskFull : PilgrimageError.incomplete
        }
    }

    private func write(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw WayMediaDownloader.isDiskFull(error) ? PilgrimageError.diskFull : PilgrimageError.incomplete
        }
    }

    // MARK: - Commit

    /// The only place a downloaded set becomes the installed route. Every
    /// file has already landed and validated in `temp`, but the writes here
    /// can still fail on a full disk — so each stage saved is remembered and
    /// taken back up if a later one throws. A half-committed route is worse
    /// than none: its stage Ways would sit in the Ways list with no
    /// `route.json` to name them and no `installed()` able to reach them.
    private func commit(routeId: String, release: String, stageCount: Int, from temp: URL) throws {
        guard let dir = store.pilgrimageDirectory(for: routeId) else { throw PilgrimageError.notWalkable }
        var saved: [Int] = []
        do {
            for index in 0..<stageCount {
                let data = try Data(contentsOf: temp.appendingPathComponent("\(index).way.json"))
                let way = try Self.decoder.decode(Way.self, from: data)
                try saveStage(way)
                saved.append(index)
            }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try write(try Data(contentsOf: temp.appendingPathComponent("route.json")),
                      to: dir.appendingPathComponent("route.json"))
            try write(Data(release.utf8), to: dir.appendingPathComponent("release.txt"))
        } catch {
            rollBack(routeId: routeId, savedStageIndices: saved)
            if let failure = error as? PilgrimageError { throw failure }
            throw WayMediaDownloader.isDiskFull(error) ? PilgrimageError.diskFull : PilgrimageError.incomplete
        }
    }

    /// Undoes everything this commit put down. An Update that fails here
    /// leaves the route removed rather than half-replaced — the earlier
    /// package's stages were already overwritten by the time the failure
    /// landed, so "nothing" is the only honest state left. The ledger is
    /// untouched, so re-downloading restores what was walked.
    private func rollBack(routeId: String, savedStageIndices: [Int]) {
        for index in savedStageIndices {
            store.delete(id: WayStore.stageWayId(routeId: routeId, stageIndex: index))
        }
        guard let dir = store.pilgrimageDirectory(for: routeId) else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("route.json"))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("release.txt"))
    }

    /// The store's own encoding, so a temp file round-trips into exactly the
    /// `way.json` the store would have written.
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
