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
    func isStageSaved(_ way: Way) -> Bool {
        guard let region = region(for: way), region.isComplete else { return false }
        return region.corridorHash == Self.corridorHash(for: way)
    }

    func status(for routeId: String, stages: [Way]) -> Status {
        let saved = stages.filter(isStageSaved)
        guard !saved.isEmpty else { return .none }
        let packsPresent = StylePackRequest.allCases.allSatisfy(loader.hasStylePack)
        guard saved.count == stages.count, packsPresent else { return .partial(saved: saved.count, of: stages.count) }
        let bytes = saved.compactMap(region(for:)).reduce(0) { $0 + $1.completedResourceSize }
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
}
