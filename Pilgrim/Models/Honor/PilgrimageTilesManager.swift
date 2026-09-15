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
    /// Measured on three Camino Francés tiles at z14/z15 in the design
    /// session; the seed for that route and the default for any route with
    /// no measurement of its own. Replaced per route after its first save.
    static let seedBytesPerTile = 10_000

    let loader: TileRegionLoading
    private let defaults: UserDefaults

    init(loader: TileRegionLoading, defaults: UserDefaults = .standard) {
        self.loader = loader
        self.defaults = defaults
        // A view that read `status` before the store answered has nothing
        // else to tell it the saved answer has arrived.
        loader.onChange = { [weak self] in self?.objectWillChange.send() }
    }

    // MARK: - Geometry and keys

    static func ring(for way: Way) -> [CLLocationCoordinate2D] {
        WayGeometry.corridor(around: way.route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) },
                             halfWidthMeters: halfWidthMeters)
    }

    /// SHA-256 of the ring's coordinates at 1e-6°, so a resumed save can
    /// tell a redrawn stage from an unchanged one by comparing two strings.
    static func corridorHash(for way: Way) -> String {
        corridorHash(ring(for: way))
    }

    static func corridorHash(_ ring: [CLLocationCoordinate2D]) -> String {
        var data = Data()
        for point in ring {
            data.append(contentsOf: withUnsafeBytes(of: (point.latitude * 1_000_000).rounded()) { Array($0) })
            data.append(contentsOf: withUnsafeBytes(of: (point.longitude * 1_000_000).rounded()) { Array($0) })
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func regionPrefix(routeId: String) -> String { "pilgrimage:\(routeId):" }

    // MARK: - Status

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
        // One store read for the whole route: `regions()` refreshes the
        // loader's cache, so asking it per stage re-reads once per stage.
        let byId = Dictionary(loader.regions().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let saved = stages.filter { isSaved($0, region: byId[$0.id]) }
        guard !saved.isEmpty else { return .none }
        let packsPresent = StylePackRequest.allCases.allSatisfy(loader.hasStylePack)
        guard saved.count == stages.count, packsPresent else { return .partial(saved: saved.count, of: stages.count) }
        let bytes = saved.compactMap { byId[$0.id] }.reduce(0) { $0 + $1.completedResourceSize }
        return .saved(bytes: bytes)
    }

    // MARK: - Estimate

    static func bytesPerTileKey(routeId: String) -> String { "pilgrimage.tiles.bytesPerTile.\(routeId)" }

    func bytesPerTile(routeId: String) -> Int {
        let stored = defaults.integer(forKey: Self.bytesPerTileKey(routeId: routeId))
        return stored > 0 ? stored : Self.seedBytesPerTile
    }

    func tileCount(for stages: [Way]) -> Int {
        stages.reduce(0) { total, way in
            let ring = Self.ring(for: way)
            return total
                + PilgrimageTilesDescriptors.tileCount(ring: ring, zooms: 10...PilgrimageTilesDescriptors.streetsZoom.upperBound)
                + PilgrimageTilesDescriptors.tileCount(ring: ring, zooms: 10...PilgrimageTilesDescriptors.terrainZoom.upperBound)
        }
    }

    func estimateBytes(for routeId: String, stages: [Way]) -> Int {
        tileCount(for: stages) * bytesPerTile(routeId: routeId)
    }

    /// After a save of this route lands: its real bytes over its tile count
    /// replace the seed. Another route's key is never touched.
    func calibrate(routeId: String, stages: [Way]) {
        let bytes = stages.compactMap(region(for:)).reduce(0) { $0 + $1.completedResourceSize }
        let tiles = tileCount(for: stages)
        guard bytes > 0, tiles > 0 else { return }
        defaults.set(bytes / tiles, forKey: Self.bytesPerTileKey(routeId: routeId))
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
        guard !isWalkActive() else { throw PilgrimageError.walkInProgress }
        if case .saving = phase { return }
        phase = .saving(done: 0, total: StylePackRequest.allCases.count + stages.count)
        let myGeneration = generation
        var done = 0
        do {
            for pack in StylePackRequest.allCases {
                guard !isWalkActive() else { throw PilgrimageError.walkInProgress }
                if !loader.hasStylePack(pack) {
                    try await loadPack(pack, generation: myGeneration)
                }
                done += 1
                phase = .saving(done: done, total: StylePackRequest.allCases.count + stages.count)
            }
            for way in stages.sorted(by: { ($0.stage?.index ?? 0) < ($1.stage?.index ?? 0) }) {
                guard !isWalkActive() else { throw PilgrimageError.walkInProgress }
                if !isStageSaved(way) {
                    let ring = Self.ring(for: way)
                    let request = TileRegionRequest(id: way.id, ring: ring,
                                                    corridorHash: Self.corridorHash(ring), acceptExpired: true)
                    try await loadRegion(request, generation: myGeneration)
                }
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

    /// Shared like the package manager's; the production loader is attached
    /// in `MainCoordinatorView` so this file never imports Mapbox.
    static let shared = PilgrimageTilesManager(loader: MapboxTileRegionLoader())

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
        for region in loader.regions() where region.id.hasPrefix("pilgrimage:") {
            guard let installed else {
                loader.removeRegion(id: region.id)
                continue
            }
            let prefix = Self.regionPrefix(routeId: installed.routeId)
            let index = Self.stageIndex(of: region.id, prefix: prefix)
            if !region.id.hasPrefix(prefix) || index == nil || index! >= installed.stageCount {
                loader.removeRegion(id: region.id)
            }
        }
    }

    private static func stageIndex(of regionId: String, prefix: String) -> Int? {
        guard regionId.hasPrefix(prefix) else { return nil }
        return Int(regionId.dropFirst(prefix.count))
    }
}
