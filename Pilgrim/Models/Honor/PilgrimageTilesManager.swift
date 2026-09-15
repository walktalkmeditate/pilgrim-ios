// Pilgrim/Models/Honor/PilgrimageTilesManager.swift
import Combine
import CoreLocation
import CryptoKit
import Foundation

/// The saved basemap for the one installed pilgrimage: one tile region per
/// stage, keyed like the stage's Way. A sibling of `PilgrimagePackageManager`
/// with the same shape; every Mapbox call goes through `TileRegionLoading`.
@MainActor
final class PilgrimageTilesManager: ObservableObject {

    enum Status: Equatable {
        case none
        case partial(saved: Int, of: Int)
        case saved(bytes: Int)
    }

    enum Phase: Equatable {
        case idle
        /// `total` counts the two style packs plus one region per stage.
        case saving(done: Int, total: Int)
        case failed(PilgrimageError)
    }

    @Published private(set) var phase: Phase = .idle

    /// Set by `MainCoordinatorView`, like the package manager's.
    var isWalkActive: () -> Bool = { false }

    static let halfWidthMeters = 500.0
    /// One z11 cell of the corridor, both tilesets together, measured against
    /// the tile API on 2026-09-15: 3.8 MB on the Francés, 2.7 MB on the
    /// Nakahechi. The default for every route until its first save
    /// calibrates it. The 10 KB it replaced was a streets tile, and tiles
    /// are not what the store downloads.
    static let seedBytesPerPack = 4_000_000

    /// Shared like the package manager's; the production loader is attached
    /// in `MainCoordinatorView` so this file never imports Mapbox.
    static let shared = PilgrimageTilesManager(loader: MapboxTileRegionLoader())

    private let loader: TileRegionLoading
    private let defaults: UserDefaults

    /// For readers that care only about what is on disk, not about a save's
    /// progress: `objectWillChange` also fires on every `phase` step, and a
    /// reader that re-reads the whole route would do so once per stage of a
    /// save it does not even display.
    let regionsChanged = PassthroughSubject<Void, Never>()

    init(loader: TileRegionLoading, defaults: UserDefaults = .standard) {
        self.loader = loader
        self.defaults = defaults
        // A view that read `status` before the store answered has nothing
        // else to tell it the saved answer has arrived.
        loader.onChange = { [weak self] change in
            guard let self else { return }
            self.objectWillChange.send()
            // Only the regions answer speaks for what is on disk; the packs
            // answer is a round trip ahead of it and says nothing about the
            // store's contents.
            if change == .regions {
                self.regionsChanged.send()
            }
        }
    }

    // MARK: - Geometry and keys

    static func rings(for way: Way) -> [[CLLocationCoordinate2D]] {
        WayGeometry.corridor(around: way.route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) },
                             halfWidthMeters: halfWidthMeters)
    }

    /// SHA-256 of the region version and the corridor's coordinates at
    /// 1e-6°, so a resumed save can tell a redrawn stage — or one saved
    /// under earlier descriptors — from an unchanged one by comparing two
    /// strings.
    static func corridorHash(for way: Way) -> String {
        corridorHash(rings(for: way))
    }

    /// The version goes in first: a region saved under earlier descriptors
    /// then fails the check, reads as unsaved, and the next save reloads it
    /// under the current ones. Then every part in the order `corridor`
    /// emits them: the order is part of the hash, and `corridor` is
    /// deterministic, so the same line always hashes the same and a
    /// reordering would read as a redrawn stage.
    static func corridorHash(_ rings: [[CLLocationCoordinate2D]],
                             version: Int = PilgrimageTilesDescriptors.regionVersion) -> String {
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: version) { Array($0) })
        for ring in rings {
            for point in ring {
                data.append(contentsOf: withUnsafeBytes(of: (point.latitude * 1_000_000).rounded()) { Array($0) })
                data.append(contentsOf: withUnsafeBytes(of: (point.longitude * 1_000_000).rounded()) { Array($0) })
            }
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func regionPrefix(routeId: String) -> String { "pilgrimage:\(routeId):" }

    // MARK: - Status

    /// One store read for a whole route: `regions()` refreshes the loader's
    /// cache, so asking it per stage re-reads once per stage.
    private func regionsById() -> [String: TileRegionSummary] {
        Dictionary(loader.regions().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func region(for way: Way) -> TileRegionSummary? {
        loader.regions().first { $0.id == way.id }
    }

    /// Complete by resource count and loaded for the stage's current line.
    private func isSaved(_ way: Way, region: TileRegionSummary?) -> Bool {
        guard let region, region.isComplete else { return false }
        return region.corridorHash == Self.corridorHash(for: way)
    }

    /// The single-stage entry point, for the morning card.
    func isStageSaved(_ way: Way) -> Bool {
        isSaved(way, region: region(for: way))
    }

    func status(for routeId: String, stages: [Way]) -> Status {
        let byId = regionsById()
        let saved = stages.filter { isSaved($0, region: byId[$0.id]) }
        guard !saved.isEmpty else { return .none }
        let packsPresent = StylePackRequest.allCases.allSatisfy(loader.hasStylePack)
        guard saved.count == stages.count, packsPresent else { return .partial(saved: saved.count, of: stages.count) }
        let bytes = saved.compactMap { byId[$0.id] }.reduce(0) { $0 + $1.completedResourceSize }
        return .saved(bytes: bytes)
    }

    /// What Settings → Data shows, from one store read: how many stages are
    /// saved, and the bytes of every region carrying the route's prefix.
    /// Stale regions count too: after an Update redraws the way each hash
    /// goes stale while the bytes stay on the phone, and Delete has to
    /// reach them.
    struct Footprint: Equatable {
        let savedStages: Int
        let bytes: Int
    }

    func footprint(routeId: String, stages: [Way]) -> Footprint {
        let byId = regionsById()
        let savedStages = stages.filter { isSaved($0, region: byId[$0.id]) }.count
        let prefix = Self.regionPrefix(routeId: routeId)
        let bytes = byId.values.filter { $0.id.hasPrefix(prefix) }.reduce(0) { $0 + $1.completedResourceSize }
        return Footprint(savedStages: savedStages, bytes: bytes)
    }

    // MARK: - Estimate

    static func bytesPerPackKey(routeId: String) -> String { "pilgrimage.tiles.bytesPerPack.\(routeId)" }

    func bytesPerPack(routeId: String) -> Int {
        let stored = defaults.integer(forKey: Self.bytesPerPackKey(routeId: routeId))
        return stored > 0 ? stored : Self.seedBytesPerPack
    }

    /// Distinct z11 cells the whole route's corridor touches. The store
    /// downloads a pack — a z11 tile and every descendant to z14 — whole
    /// whenever the corridor touches any of it, so tiles were the wrong
    /// unit: the Nakahechi's ~2 MB of tiles landed as 596 MB of packs.
    /// Every stage's rings go into one sweep so a cell two stages share is
    /// counted once, as the store holds it once.
    func packCount(for stages: [Way]) -> Int {
        let root = PilgrimageTilesDescriptors.packRootZoom
        return PilgrimageTilesDescriptors.tileCount(rings: stages.flatMap { Self.rings(for: $0) }, zooms: root...root)
    }

    func estimateBytes(for routeId: String, stages: [Way]) -> Int {
        packCount(for: stages) * bytesPerPack(routeId: routeId)
    }

    /// After a save of this route lands: its real bytes over its pack count
    /// replace the seed. Another route's key is never touched.
    func calibrate(routeId: String, stages: [Way]) {
        let byId = regionsById()
        let bytes = stages.compactMap { byId[$0.id] }.reduce(0) { $0 + $1.completedResourceSize }
        let packs = packCount(for: stages)
        guard bytes >= 1, packs >= 1 else { return }
        defaults.set(bytes / packs, forKey: Self.bytesPerPackKey(routeId: routeId))
    }

    // MARK: - Save

    private var inFlight: TileLoadHandle?
    /// The continuation the in-flight load will resume. `cancel()` resumes it
    /// itself, because a cancelled load never reports back.
    private var pending: CheckedContinuation<Void, Error>?
    /// Bumped on every `cancel()`; a completion that lands after its
    /// generation was cancelled is a no-op rather than a state change.
    private var generation = 0

    /// Style packs first, then one region per stage in order, skipping any
    /// region that is complete and still matches its stage's corridor.
    /// `isWalkActive` is re-checked before every load: a save is up to
    /// thirty-five network loads and a walker who taps and then starts
    /// the stage would otherwise carry every remaining load under the walk.
    func save(routeId: String, stages: [Way]) async throws {
        if case .saving = phase { return }
        guard !isWalkActive() else {
            // The row's catch relies on phase carrying every failure; a
            // refusal at the door has to land there like a refusal mid-loop.
            phase = .failed(.walkInProgress)
            throw PilgrimageError.walkInProgress
        }
        // Once the walker is writing regions a launch sweep has no business
        // firing, whatever it was told was installed when it was asked. A
        // save refused at the door writes nothing, so the sweep stays.
        sweepGeneration += 1
        phase = .saving(done: 0, total: StylePackRequest.allCases.count + stages.count)
        let myGeneration = generation
        var done = 0
        do {
            for pack in StylePackRequest.allCases {
                guard !isWalkActive() else { throw PilgrimageError.walkInProgress }
                if !loader.hasStylePack(pack) {
                    try await loadPack(pack, generation: myGeneration)
                }
                // A cancel can land between a load's completion and this
                // hop; without this check the loop would start the next
                // load under a stale generation, whose completion would
                // never resume the save's continuation.
                guard generation == myGeneration else { throw PilgrimageError.incomplete }
                done += 1
                phase = .saving(done: done, total: StylePackRequest.allCases.count + stages.count)
            }
            // One snapshot for the whole loop. Every region the loop goes on
            // to load is one this snapshot said was missing, so nothing it
            // learns later could change a skip decision.
            let byId = regionsById()
            for way in stages.sorted(by: { ($0.stage?.index ?? 0) < ($1.stage?.index ?? 0) }) {
                guard !isWalkActive() else { throw PilgrimageError.walkInProgress }
                if !isSaved(way, region: byId[way.id]) {
                    let rings = Self.rings(for: way)
                    let request = TileRegionRequest(id: way.id, rings: rings,
                                                    corridorHash: Self.corridorHash(rings), acceptExpired: true)
                    try await loadRegion(request, generation: myGeneration)
                }
                // A cancel can land between a load's completion and this
                // hop; without this check the loop would start the next
                // load under a stale generation, whose completion would
                // never resume the save's continuation.
                guard generation == myGeneration else { throw PilgrimageError.incomplete }
                done += 1
                phase = .saving(done: done, total: StylePackRequest.allCases.count + stages.count)
            }
            calibrate(routeId: routeId, stages: stages)
            phase = .idle
        } catch let error as PilgrimageError {
            // A cancel already put the phase back and cleaned up, and a save
            // started since then owns `inFlight`. A genuine failure is shown
            // until the next save or cancel clears it.
            if generation == myGeneration {
                inFlight?.cancel()
                inFlight = nil
                phase = .failed(error)
            }
            throw error
        }
    }

    private func loadPack(_ pack: StylePackRequest, generation myGeneration: Int) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pending = continuation
            inFlight = loader.loadStylePack(pack) { [weak self] result in
                guard let self else {
                    continuation.resume(throwing: PilgrimageError.incomplete)
                    return
                }
                // `cancel()` resumed this continuation already; a late
                // completion resuming it a second time would trap.
                guard self.generation == myGeneration else { return }
                self.pending = nil
                self.inFlight = nil
                continuation.resume(with: result.mapError(Self.mapped))
            }
        }
    }

    private func loadRegion(_ request: TileRegionRequest, generation myGeneration: Int) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pending = continuation
            inFlight = loader.loadRegion(request, progress: { _, _ in }) { [weak self] result in
                guard let self else {
                    continuation.resume(throwing: PilgrimageError.incomplete)
                    return
                }
                // `cancel()` resumed this continuation already; a late
                // completion resuming it a second time would trap.
                guard self.generation == myGeneration else { return }
                self.pending = nil
                self.inFlight = nil
                continuation.resume(with: result.map { _ in () }.mapError(Self.mapped))
            }
        }
    }

    private static func mapped(_ error: TileRegionLoadingError) -> PilgrimageError {
        switch error {
        case .diskFull: return .diskFull
        case .tileCountExceeded: return .mapTooLarge
        case .failed, .cancelled: return .incomplete
        }
    }

    /// Regions already complete stay. The in-flight load is cancelled and
    /// its late completion ignored by generation.
    func cancel() {
        generation += 1
        inFlight?.cancel()
        inFlight = nil
        if let pending {
            self.pending = nil
            pending.resume(throwing: PilgrimageError.incomplete)
        }
        phase = .idle
    }

    deinit {
        inFlight?.cancel()
    }

    // MARK: - Lifecycle

    /// Every region with the route's prefix. Packs no other region references
    /// are freed by the store; the style packs are shared and stay.
    func remove(routeId: String) {
        cancel()
        let prefix = Self.regionPrefix(routeId: routeId)
        for region in loader.regions() where region.id.hasPrefix(prefix) {
            loader.removeRegion(id: region.id)
        }
    }

    /// Update's retired indices: the same range `PilgrimagePackageManager`
    /// hands to `retireMany`. Nothing is downloaded on the walker's behalf.
    func removeRegions(routeId: String, atOrAbove index: Int) {
        let prefix = Self.regionPrefix(routeId: routeId)
        for region in loader.regions() where region.id.hasPrefix(prefix) {
            if let stageIndex = Self.stageIndex(of: region.id, prefix: prefix), stageIndex >= index {
                loader.removeRegion(id: region.id)
            }
        }
    }

    /// Once at launch. The three lifecycle hooks are event-driven and one
    /// path bypasses them: a kill mid-Replace is finished by `installed()`'s
    /// swap-marker branch, never by `remove` or `replace`. Anything the
    /// installed route does not account for goes, so "nothing orphaned" is
    /// a property of the store rather than a promise about call sites.
    func reconcile(installed: (routeId: String, stageCount: Int)?) {
        // The sweep must run on a real snapshot, and never on a save's
        // behalf: a request from a launch with nothing installed would
        // otherwise delete the first region a later save writes.
        sweepGeneration += 1
        let generation = sweepGeneration
        loader.refreshRegions { [weak self] in
            guard let self, self.sweepGeneration == generation else { return }
            self.sweep(installed)
        }
    }

    private var sweepGeneration = 0

    private func sweep(_ installed: (routeId: String, stageCount: Int)?) {
        for region in loader.regions() where region.id.hasPrefix("pilgrimage:") {
            if let installed {
                let prefix = Self.regionPrefix(routeId: installed.routeId)
                // `stageIndex` is nil for a region of another route, so one
                // condition covers a foreign prefix and an unreadable index.
                let index = Self.stageIndex(of: region.id, prefix: prefix)
                if let index, index < installed.stageCount { continue }
            }
            loader.removeRegion(id: region.id)
        }
    }

    private static func stageIndex(of regionId: String, prefix: String) -> Int? {
        guard regionId.hasPrefix(prefix) else { return nil }
        return Int(regionId.dropFirst(prefix.count))
    }
}
