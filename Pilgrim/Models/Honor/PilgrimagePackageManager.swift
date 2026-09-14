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

    /// Guards against a second `download` interleaving with one already in
    /// flight: every `await` below gives the run loop a chance to start
    /// another call, and two overlapping downloads of the same route would
    /// let the second's rollback tear down the first's clean install.
    private var isDownloading = false

    /// `nonisolated`: an init's default-argument expressions run in a
    /// generator function outside the type's actor, the same reasoning as
    /// `PilgrimageCatalogService.defaultSession`.
    nonisolated private static let defaultSession: URLSession = {
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

    /// Also where an interrupted cross-route Replace is finished. `replace`
    /// installs the new route before it takes the old one, so a kill inside
    /// that window leaves two valid packages and nothing in either of them to
    /// say which one the pilgrim chose. The marker says, and is read here
    /// because every screen that asks what is installed asks through this.
    func installed() -> Installed? {
        var found: [Installed] = []
        for routeId in store.pilgrimageRouteIds() {
            guard let dir = store.pilgrimageDirectory(for: routeId),
                  let routeData = try? Data(contentsOf: dir.appendingPathComponent("route.json")),
                  let route = try? PilgrimageWayImporter.route(from: routeData),
                  let release = try? String(contentsOf: dir.appendingPathComponent("release.txt"), encoding: .utf8),
                  PilgrimageCatalogService.isValidRelease(release) else { continue }
            found.append(Installed(routeId: routeId, release: release, route: route))
        }
        // A download in flight is the one time both packages are meant to be
        // there; the swap that wrote the marker is still the one to clear it.
        guard !isDownloading, let abandonedId = replacingMarker else { return found.first }
        if found.count > 1, let abandoned = found.first(where: { $0.routeId == abandonedId }) {
            removeStagesAndPackage(routeId: abandoned.routeId, stageCount: abandoned.route.stageCount)
            found.removeAll { $0.routeId == abandonedId }
        }
        clearReplacingMarker()
        return found.first
    }

    /// Names the route a cross-route Replace is letting go. Its own file
    /// rather than a field in `route.json`, so it survives the removal of
    /// either package.
    static let replacingMarkerName = "replacing.txt"

    private var replacingMarkerURL: URL {
        store.pilgrimageRoot.appendingPathComponent(Self.replacingMarkerName)
    }

    private var replacingMarker: String? {
        guard let routeId = try? String(contentsOf: replacingMarkerURL, encoding: .utf8),
              WayStore.isValidRouteId(routeId) else { return nil }
        return routeId
    }

    private func markReplacing(_ routeId: String) {
        try? FileManager.default.createDirectory(at: store.pilgrimageRoot, withIntermediateDirectories: true)
        try? Data(routeId.utf8).write(to: replacingMarkerURL, options: .atomic)
    }

    private func clearReplacingMarker() {
        try? FileManager.default.removeItem(at: replacingMarkerURL)
    }

    /// What this route already has installed, before this download changes
    /// anything — an Update's rollback has to reach every stage a prior
    /// install left, not just the ones this attempt rewrites.
    private func installedStageCount(for routeId: String) -> Int {
        guard let installed = installed(), installed.routeId == routeId else { return 0 }
        return installed.route.stages.count
    }

    // MARK: - Download

    /// Fetches `route.json` and every stage at the exact release the index
    /// named, into a temporary directory, and swaps the finished set in.
    /// The streaming, the temp writes, and the commit all run off the main
    /// actor, so `phase` can still reach a view between them and a long
    /// commit does not hang the app.
    func download(entry: PilgrimageCatalogEntry, release: String) async throws {
        guard !isWalkActive() else { throw PilgrimageError.walkInProgress }
        guard !isDownloading else { throw PilgrimageError.incomplete }
        isDownloading = true
        defer { isDownloading = false }
        // The route.json fetch below is a full network round trip before
        // the first stage lands — without an early phase, isBusy stays
        // false and a second tap re-enters here and throws a false failure.
        phase = .downloading(done: 0, total: entry.stageCount + 1)

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pilgrimage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let cap = maxPackageBytes
        let session = self.session
        let store = self.store
        let saveStage = self.saveStage
        let previousStageCount = installedStageCount(for: entry.id)
        do {
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            guard let routeURL = PilgrimageCatalogService.packageURL(release: release, routeId: entry.id, file: "route.json") else {
                throw PilgrimageError.notWalkable
            }
            let total = entry.stageCount + 1
            // Counted across every file, not per file: 200 stages each just
            // under the 2 MB per-file cap would otherwise be 400 MB.
            var packageBytes = 0
            let fetched = try await Self.stageRouteFile(entry: entry, routeURL: routeURL, into: temp, session: session)
            packageBytes += fetched.bytes
            try Self.checkBudget(packageBytes, cap: cap)
            phase = .downloading(done: 1, total: total)
            for index in 0..<fetched.route.stageCount {
                guard let stageURL = PilgrimageCatalogService.packageURL(
                    release: release, routeId: entry.id, file: Self.stageFileName(index)) else {
                    throw PilgrimageError.notWalkable
                }
                let stagePlan = StagePlan(routeId: entry.id, url: stageURL, stageCount: fetched.route.stageCount,
                                          expected: fetched.route.stages[index])
                packageBytes += try await Self.stageOneStage(stagePlan, into: temp, session: session)
                try Self.checkBudget(packageBytes, cap: cap)
                phase = .downloading(done: index + 2, total: total)
            }
            // The stages take a whole network round trip each; a walk that
            // began while they streamed would be walking a Way this commit is
            // about to rewrite underneath it. The temp set is swept by the
            // `defer` above, so nothing of the abandoned package is kept.
            guard !isWalkActive() else { throw PilgrimageError.walkInProgress }
            let plan = CommitPlan(routeId: entry.id, release: release, stageCount: fetched.route.stageCount,
                                   previousStageCount: previousStageCount)
            try await Self.commit(plan, from: temp, store: store, saveStage: saveStage)
            phase = .idle
        } catch is CancellationError {
            // A cancelled task is not a failure the pilgrim needs to see:
            // the temp dir is still swept by the `defer` above.
            phase = .idle
            throw CancellationError()
        } catch {
            let failure = (error as? PilgrimageError) ?? .incomplete
            phase = .failed(failure)
            throw failure
        }
    }

    // MARK: - Replace, update, remove

    static func replaceConfirmation(routeName: String) -> String {
        "Replace the \(routeName)? Its stages leave your phone; what you've walked of it is remembered if it comes back. Walks in your journal stay."
    }

    /// The same promise, asked about the route being let go rather than the
    /// one arriving — the Remove alert must not ask about replacing.
    static func removeConfirmation(routeName: String) -> String {
        "Remove the \(routeName)? Its stages leave your phone; what you've walked of it is remembered if it comes back. Walks in your journal stay."
    }

    /// Downloads the new route in full before the old one is touched, so a
    /// failed replace leaves the pilgrim with the route they already had.
    func replace(with entry: PilgrimageCatalogEntry, release: String) async throws {
        guard !isWalkActive() else { throw PilgrimageError.walkInProgress }
        // A replace of the route you already hold is an update by another
        // name: it needs the same shrink tail-sweep and ledger reconciliation,
        // not a bare download that leaves both behind.
        if installed()?.routeId == entry.id {
            try await update(entry: entry, release: release)
            return
        }
        let previous = installed()
        // Written before a byte lands, so a kill anywhere in the swap leaves
        // behind the name of the route being let go.
        if let previous { markReplacing(previous.routeId) }
        do {
            try await download(entry: entry, release: release)
        } catch {
            clearReplacingMarker()
            throw error
        }
        if let previous, previous.routeId != entry.id {
            // The ledger stays: a route that comes back finds its record.
            removeStagesAndPackage(routeId: previous.routeId, stageCount: previous.route.stageCount)
        }
        clearReplacingMarker()
    }

    /// The same swap, then the ledger is reconciled against the stages the
    /// new package actually carries.
    func update(entry: PilgrimageCatalogEntry, release: String) async throws {
        guard !isWalkActive() else { throw PilgrimageError.walkInProgress }
        let previousStageCount = installedStageCount(for: entry.id)
        try await download(entry: entry, release: release)
        guard let fresh = installed(), fresh.routeId == entry.id else { throw PilgrimageError.incomplete }
        // A route that shrank leaves stage Ways above the new count behind;
        // nothing lists them and no next row reaches them, so they go.
        store.retireMany(ids: Self.stageIds(routeId: entry.id,
                                            range: fresh.route.stageCount..<max(previousStageCount, fresh.route.stageCount)))
        if let ledger = ledgers.load(routeId: entry.id) {
            ledgers.save(ledger.reconciled(against: fresh.route.stages))
        }
    }

    func remove(routeId: String) throws {
        guard !isWalkActive() else { throw PilgrimageError.walkInProgress }
        // The same refusal a second download gets: a Remove taken between two
        // stages would be undone by the commit that lands after it, and the
        // route the pilgrim let go would be back on the phone.
        guard !isDownloading else { throw PilgrimageError.incomplete }
        let stageCount = installed().flatMap { $0.routeId == routeId ? $0.route.stageCount : nil }
            ?? PilgrimageWayImporter.maxStageCount
        removeStagesAndPackage(routeId: routeId, stageCount: stageCount)
    }

    /// Takes the stages, `route.json`, and `release.txt`. Never `ledger.json`
    /// — the record of having walked a route outlives the route — and never
    /// the whole of a stage a walk in the journal still names: `retireMany`
    /// keeps a walked stage's `way.json`, its reply, and its index link, so
    /// the summary and the prompt can still say which stage that walk was.
    /// `installed()` keys on `route.json`, so what is kept never reads as
    /// installed, and a re-download overwrites it in place.
    private func removeStagesAndPackage(routeId: String, stageCount: Int) {
        store.retireMany(ids: Self.stageIds(routeId: routeId, range: 0..<stageCount))
        guard let dir = store.pilgrimageDirectory(for: routeId) else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("route.json"))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("release.txt"))
    }

    nonisolated private static func stageIds(routeId: String, range: Range<Int>) -> [String] {
        range.map { WayStore.stageWayId(routeId: routeId, stageIndex: $0) }
    }

    /// The index's `bytes` is a figure the dataset wrote; this is the one the
    /// phone actually paid.
    nonisolated private static func checkBudget(_ bytes: Int, cap: Int) throws {
        guard bytes <= cap else { throw PilgrimageError.incomplete }
    }

    /// The route file must describe the route the catalog offered: a package
    /// whose own idea of itself differs from the index's is not walkable.
    nonisolated private static func stageRouteFile(entry: PilgrimageCatalogEntry, routeURL: URL, into temp: URL, session: URLSession) async throws
        -> (route: PilgrimageRoute, bytes: Int) {
        let data = try await fetch(url: routeURL, cap: PilgrimageWayImporter.maxRouteBytes, session: session)
        let route = try PilgrimageWayImporter.route(from: data)
        guard route.id == entry.id, route.stageCount == entry.stageCount,
              route.stages.count == entry.stageCount else { throw PilgrimageError.notWalkable }
        try write(data, to: temp.appendingPathComponent("route.json"))
        return (route, data.count)
    }

    /// What one stage's fetch needs to know about itself, bundled so the
    /// function below stays under the lint's parameter ceiling — the same
    /// shape `CommitPlan` takes. `expected` is the row `route.json` gave for
    /// this index; the route file is validated as the exact run `0..<count`,
    /// so the positional lookup that produced it is safe.
    private struct StagePlan {
        let routeId: String
        let url: URL
        let stageCount: Int
        let expected: PilgrimageRouteStage
    }

    /// Validated as it lands, then written in the store's own encoding, so
    /// the commit below is a decode-and-save rather than a second parse of
    /// untrusted bytes. Returns the bytes it cost.
    ///
    /// The stage block is checked against `route.json` as well as against
    /// itself: the two files come down separately, and a stage that disagrees
    /// with the route about how many stages there are, or about what this one
    /// is called, would have the morning card and the ledger reading different
    /// packages — "stage 3 of 40" against a route the screen counts as 12, and
    /// a reconciliation that drops entries by a name the route never used.
    nonisolated private static func stageOneStage(_ plan: StagePlan, into temp: URL, session: URLSession) async throws -> Int {
        let index = plan.expected.index
        let data = try await fetch(url: plan.url, cap: PilgrimageWayImporter.maxStageBytes, session: session)
        let way = try PilgrimageWayImporter.way(from: data, routeId: plan.routeId, stageIndex: index)
        guard way.stage?.count == plan.stageCount, way.stage?.name == plan.expected.name else {
            throw PilgrimageError.notWalkable
        }
        try write(try Self.encoder.encode(way), to: temp.appendingPathComponent("\(index).way.json"))
        return data.count
    }

    nonisolated private static func fetch(url: URL, cap: Int, session: URLSession) async throws -> Data {
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
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WayMediaDownloader.isDiskFull(error) ? PilgrimageError.diskFull : PilgrimageError.incomplete
        }
    }

    nonisolated private static func write(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw WayMediaDownloader.isDiskFull(error) ? PilgrimageError.diskFull : PilgrimageError.incomplete
        }
    }

    // MARK: - Commit

    /// What a commit needs to know about itself, bundled so the function
    /// below stays under the lint's parameter ceiling. `previousStageCount`
    /// is what this same route already had installed before this attempt —
    /// an Update overwrites those stages in place, so a rollback has to know
    /// both counts to reach past what this commit itself touched.
    private struct CommitPlan {
        let routeId: String
        let release: String
        let stageCount: Int
        let previousStageCount: Int
    }

    /// The only place a downloaded set becomes the installed route. Every
    /// file has already landed and validated in `temp`, but the writes here
    /// can still fail on a full disk, and a failure rolls back through
    /// whichever of `plan`'s two counts is larger, not just the stages this
    /// commit itself touched. A half-committed route is worse than none: its
    /// stage Ways would sit in the Ways list with no `route.json` to name
    /// them and no `installed()` able to reach them, and a shrinking
    /// Update's untouched tail would orphan the same way.
    nonisolated private static func commit(_ plan: CommitPlan, from temp: URL, store: WayStore, saveStage: (Way) throws -> Void) async throws {
        guard let dir = store.pilgrimageDirectory(for: plan.routeId) else { throw PilgrimageError.notWalkable }
        do {
            for index in 0..<plan.stageCount {
                let data = try Data(contentsOf: temp.appendingPathComponent("\(index).way.json"))
                let way = try Self.decoder.decode(Way.self, from: data)
                try saveStage(way)
            }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try write(try Data(contentsOf: temp.appendingPathComponent("route.json")),
                      to: dir.appendingPathComponent("route.json"))
            try write(Data(plan.release.utf8), to: dir.appendingPathComponent("release.txt"))
        } catch {
            rollBack(routeId: plan.routeId, stageCount: max(plan.previousStageCount, plan.stageCount), store: store)
            if let failure = error as? PilgrimageError { throw failure }
            throw WayMediaDownloader.isDiskFull(error) ? PilgrimageError.diskFull : PilgrimageError.incomplete
        }
    }

    /// Undoes everything a commit could have put down for this route, up
    /// through `stageCount` — not only the indices this attempt itself
    /// wrote, so a shrinking or same-size Update leaves nothing behind
    /// either. The ledger is untouched, so re-downloading restores what was
    /// walked, and so is any stage a walk in the journal still names.
    nonisolated private static func rollBack(routeId: String, stageCount: Int, store: WayStore) {
        store.retireMany(ids: stageIds(routeId: routeId, range: 0..<stageCount))
        guard let dir = store.pilgrimageDirectory(for: routeId) else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("route.json"))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("release.txt"))
    }

    /// The store's own encoding, so a temp file round-trips into exactly the
    /// `way.json` the store would have written. `nonisolated`: read only
    /// from the streaming and commit helpers above, none of which run on the
    /// main actor.
    nonisolated private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    nonisolated private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
