// Pilgrim/Models/Honor/MapboxTileRegionLoader.swift
import CoreLocation
import Foundation
import MapboxMaps
import Turf

/// The one file that speaks to Mapbox's offline API. Everything above it
/// talks in `TileRegionRequest` and `TileRegionSummary`.
final class MapboxTileRegionLoader: TileRegionLoading {

    final class Handle: TileLoadHandle {
        private let cancelable: Cancelable
        init(_ cancelable: Cancelable) { self.cancelable = cancelable }
        func cancel() { cancelable.cancel() }
    }

    /// Under Application Support, never Caches: Caches is purgeable under
    /// storage pressure and a walker on day 20 could lose day 21's maps.
    /// `TileStore.shared(for:)` excludes its path from iCloud backup.
    static let storeURL: URL = {
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("pilgrimage-tiles", isDirectory: true)
    }()
    static let usesExplicitStorePath = true
    static let descriptorZoomRanges = (streets: PilgrimageTilesDescriptors.streetsZoom,
                                       terrain: PilgrimageTilesDescriptors.terrainZoom)
    static let terrainTilesets = [PilgrimageTilesDescriptors.terrainTileset]

    private let tileStore: TileStore
    private let offlineManager: OfflineManager
    private let descriptors: [TilesetDescriptor]
    /// Refreshed from the store on every `regions()`; the manager reads it
    /// synchronously and the store answers asynchronously.
    private var cached: [TileRegionSummary] = []
    private var cachedPacks: Set<StylePackRequest> = []

    init() {
        tileStore = TileStore.shared(for: Self.storeURL)
        offlineManager = OfflineManager()
        // The SDK takes the zoom band as `UInt8`; the spec constants are
        // `Int` so a test can pin them without linking Mapbox.
        let streetsBand = UInt8(Self.descriptorZoomRanges.streets.lowerBound)...UInt8(Self.descriptorZoomRanges.streets.upperBound)
        let terrainBand = UInt8(Self.descriptorZoomRanges.terrain.lowerBound)...UInt8(Self.descriptorZoomRanges.terrain.upperBound)
        let streetsLight = TilesetDescriptorOptions(styleURI: .light, zoomRange: streetsBand, tilesets: nil)
        let streetsDark = TilesetDescriptorOptions(styleURI: .dark, zoomRange: streetsBand, tilesets: nil)
        let terrain = TilesetDescriptorOptions(styleURI: .light, zoomRange: terrainBand,
                                               tilesets: Self.terrainTilesets)
        descriptors = [streetsLight, streetsDark, terrain].map(offlineManager.createTilesetDescriptor(for:))
        refresh()
    }

    private static func styleURI(_ pack: StylePackRequest) -> StyleURI {
        pack == .light ? .light : .dark
    }

    // MARK: - TileRegionLoading

    func hasStylePack(_ pack: StylePackRequest) -> Bool { cachedPacks.contains(pack) }

    func loadStylePack(_ pack: StylePackRequest,
                       completion: @escaping (Result<Void, TileRegionLoadingError>) -> Void) -> TileLoadHandle {
        guard let options = StylePackLoadOptions(glyphsRasterizationMode: .ideographsRasterizedLocally) else {
            completion(.failure(.failed))
            return Handle(AnyCancelable {})
        }
        let cancelable = offlineManager.loadStylePack(for: Self.styleURI(pack), loadOptions: options) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.cachedPacks.insert(pack)
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(Self.mapped(error)))
                }
            }
        }
        return Handle(cancelable)
    }

    func loadRegion(_ request: TileRegionRequest,
                    progress: @escaping (Int, Int) -> Void,
                    completion: @escaping (Result<TileRegionSummary, TileRegionLoadingError>) -> Void) -> TileLoadHandle {
        let ring = request.ring.map { LocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        guard let options = TileRegionLoadOptions(geometry: .polygon(Polygon([ring])),
                                                  descriptors: descriptors,
                                                  metadata: ["corridorHash": request.corridorHash],
                                                  acceptExpired: request.acceptExpired) else {
            completion(.failure(.failed))
            return Handle(AnyCancelable {})
        }
        let cancelable = tileStore.loadTileRegion(forId: request.id, loadOptions: options, progress: { loadProgress in
            DispatchQueue.main.async {
                progress(Int(loadProgress.completedResourceCount), Int(loadProgress.requiredResourceCount))
            }
        }, completion: { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let region):
                    let summary = TileRegionSummary(id: region.id,
                                                    completedResourceCount: Int(region.completedResourceCount),
                                                    requiredResourceCount: Int(region.requiredResourceCount),
                                                    completedResourceSize: Int(region.completedResourceSize),
                                                    metadata: ["corridorHash": request.corridorHash])
                    self?.cached.removeAll { $0.id == summary.id }
                    self?.cached.append(summary)
                    completion(.success(summary))
                case .failure(let error):
                    completion(.failure(Self.mapped(error)))
                }
            }
        })
        return Handle(cancelable)
    }

    func regions() -> [TileRegionSummary] {
        refresh()
        return cached
    }

    func removeRegion(id: String) {
        tileStore.removeTileRegion(forId: id)
        cached.removeAll { $0.id == id }
    }

    // MARK: - Store → cache

    /// The store answers on a worker thread; the cache is what the manager
    /// reads. A read that lands mid-refresh sees the previous answer, which
    /// is at most one save behind.
    private func refresh() {
        tileStore.allTileRegions { [weak self] result in
            guard case .success(let regions) = result else { return }
            let group = DispatchGroup()
            var summaries: [TileRegionSummary] = []
            let lock = NSLock()
            for region in regions {
                group.enter()
                self?.tileStore.tileRegionMetadata(forId: region.id) { metadataResult in
                    let hash = ((try? metadataResult.get()) as? [String: String])?["corridorHash"] ?? ""
                    let summary = TileRegionSummary(id: region.id,
                                                    completedResourceCount: Int(region.completedResourceCount),
                                                    requiredResourceCount: Int(region.requiredResourceCount),
                                                    completedResourceSize: Int(region.completedResourceSize),
                                                    metadata: ["corridorHash": hash])
                    lock.lock(); summaries.append(summary); lock.unlock()
                    group.leave()
                }
            }
            group.notify(queue: .main) { self?.cached = summaries }
        }
        offlineManager.allStylePacks { [weak self] result in
            guard case .success(let packs) = result else { return }
            let uris = Set(packs.map(\.styleURI))
            DispatchQueue.main.async {
                self?.cachedPacks = Set(StylePackRequest.allCases.filter { uris.contains(Self.styleURI($0).rawValue) })
            }
        }
    }

    private static func mapped(_ error: Error) -> TileRegionLoadingError {
        if WayMediaDownloader.isDiskFull(error) { return .diskFull }
        if let tileError = error as? TileRegionError, case .canceled = tileError { return .cancelled }
        return .failed
    }
}
