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
        guard let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                          appropriateFor: nil, create: true) else {
            // Latched for the life of the process and otherwise invisible:
            // every save would appear to work and could vanish overnight.
            print("[MapboxTileRegionLoader] Application Support unavailable; saved maps will land in a purgeable directory")
            return FileManager.default.temporaryDirectory.appendingPathComponent("pilgrimage-tiles", isDirectory: true)
        }
        return support.appendingPathComponent("pilgrimage-tiles", isDirectory: true)
    }()

    /// The three descriptors every region is loaded with, as value types so
    /// a test can read what the SDK is given without opening a `TileStore`.
    static func descriptorOptions() -> [TilesetDescriptorOptions] {
        // The SDK takes the zoom band as `UInt8`; the spec constants are
        // `Int` so a test can pin them without linking Mapbox.
        let streets = UInt8(PilgrimageTilesDescriptors.streetsZoom.lowerBound)...UInt8(PilgrimageTilesDescriptors.streetsZoom.upperBound)
        let terrain = UInt8(PilgrimageTilesDescriptors.terrainZoom.lowerBound)...UInt8(PilgrimageTilesDescriptors.terrainZoom.upperBound)
        return [
            TilesetDescriptorOptions(styleURI: .light, zoomRange: streets, tilesets: nil),
            TilesetDescriptorOptions(styleURI: .dark, zoomRange: streets, tilesets: nil),
            // The DEM is added at runtime by the wabi-sabi style pass, so it
            // is in neither base style: unnamed here, the hillshade would be
            // blank offline.
            TilesetDescriptorOptions(styleURI: .light, zoomRange: terrain,
                                     tilesets: [PilgrimageTilesDescriptors.terrainTileset])
        ]
    }

    var onChange: ((TileStoreChange) -> Void)?

    private let tileStore: TileStore
    private let offlineManager: OfflineManager
    private let descriptors: [TilesetDescriptor]
    /// Empty until the first asynchronous store read lands, then refreshed
    /// on every `regions()` call. `onChange` fires whenever it is replaced,
    /// which is how a synchronous reader learns the answer arrived.
    private var cached: [TileRegionSummary] = []
    private var cachedPacks: Set<StylePackRequest> = []
    /// `regions()` refreshes on every read, so several store reads can be in
    /// flight at once and they answer in arbitrary order. Only the newest
    /// may write the cache: an older snapshot landing last would put back
    /// regions a removal took out, or byte counts a save has already
    /// overtaken — and `calibrate` divides by those bytes.
    private var refreshGeneration = 0
    /// Callers waiting for the store's next regions answer, whatever it says.
    private var pendingRegionsCompletions: [() -> Void] = []

    init() {
        tileStore = TileStore.shared(for: Self.storeURL)
        offlineManager = OfflineManager()
        descriptors = Self.descriptorOptions().map(offlineManager.createTilesetDescriptor(for:))
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
                    self?.onChange?(.packs)
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
        // One polygon per convex part; the store unions them when it tiles.
        let polygons = request.rings.map { ring in
            [ring.map { LocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }]
        }
        guard let options = TileRegionLoadOptions(geometry: .multiPolygon(MultiPolygon(polygons)),
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
                    // A refresh already in flight is older than this write;
                    // its snapshot would drop the region again.
                    self?.refreshGeneration += 1
                    self?.cached.removeAll { $0.id == summary.id }
                    self?.cached.append(summary)
                    // `refresh()` compares against a sorted array; leaving
                    // this one appended would read as a change on the next
                    // pass and signal a second time for the same save.
                    self?.cached.sort { $0.id < $1.id }
                    self?.onChange?(.regions)
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

    func refreshRegions(completion: @escaping () -> Void) {
        pendingRegionsCompletions.append(completion)
        refresh()
    }

    func removeRegion(id: String) {
        tileStore.removeTileRegion(forId: id)
        // A refresh already in flight is older than this removal; its
        // snapshot would put the region back.
        refreshGeneration += 1
        cached.removeAll { $0.id == id }
        onChange?(.regions)
    }

    // MARK: - Store → cache

    /// The store answers on a worker thread; the cache is what the manager
    /// reads synchronously. A signal only goes out when the answer actually
    /// differs — `regions()` refreshes, so signalling every read would spin
    /// a view that reads `regions()` in its body. The summaries are sorted
    /// because the metadata calls finish in arbitrary order and an unstable
    /// order would read as a change on every pass.
    private func refresh() {
        refreshGeneration += 1
        let token = refreshGeneration
        tileStore.allTileRegions { [weak self] result in
            guard let self, case .success(let regions) = result else { return }
            let group = DispatchGroup()
            var summaries: [TileRegionSummary] = []
            let lock = NSLock()
            for region in regions {
                group.enter()
                self.tileStore.tileRegionMetadata(forId: region.id) { metadataResult in
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
            group.notify(queue: .main) { [weak self] in
                guard let self, token == self.refreshGeneration else { return }
                // Taken out from under the equality guard below, which is
                // silent when the answer matches the cache — and an empty
                // store answering an empty cache is exactly the launch case
                // that has to be heard. A stale token returns above and
                // leaves these for the refresh that overtook it.
                let waiting = self.pendingRegionsCompletions
                self.pendingRegionsCompletions = []
                let sorted = summaries.sorted { $0.id < $1.id }
                if self.cached != sorted {
                    self.cached = sorted
                    self.onChange?(.regions)
                }
                // After the cache is written, never before: a completion reads
                // `regions()` and must see the answer it waited for.
                for completion in waiting { completion() }
            }
        }
        offlineManager.allStylePacks { [weak self] result in
            guard case .success(let packs) = result else { return }
            // A pack whose load was interrupted persists partially and still
            // reports its style URI here; reading it as present would skip
            // it on every later save and leave the offline map without a
            // style.
            let complete = packs.filter { Self.isComplete(completed: Int($0.completedResourceCount), required: Int($0.requiredResourceCount)) }
            let uris = Set(complete.map(\.styleURI))
            DispatchQueue.main.async {
                let present = Set(StylePackRequest.allCases.filter { uris.contains(Self.styleURI($0).rawValue) })
                guard let self, token == self.refreshGeneration, self.cachedPacks != present else { return }
                self.cachedPacks = present
                self.onChange?(.packs)
            }
        }
    }

    /// Mirrors `TileRegionSummary.isComplete`: a `StylePack` reports the same
    /// two counts under different names, so the completeness rule for "is
    /// this style present" has to be the same rule as "is this region done".
    static func isComplete(completed: Int, required: Int) -> Bool {
        required > 0 && completed >= required
    }

    static func mapped(_ error: Error) -> TileRegionLoadingError {
        if let tileError = error as? TileRegionError, case .diskFull = tileError { return .diskFull }
        if let packError = error as? StylePackError, case .diskFull = packError { return .diskFull }
        if WayMediaDownloader.isDiskFull(error) { return .diskFull }
        if let tileError = error as? TileRegionError, case .tileCountExceeded = tileError { return .tileCountExceeded }
        if let tileError = error as? TileRegionError, case .canceled = tileError { return .cancelled }
        return .failed
    }
}
