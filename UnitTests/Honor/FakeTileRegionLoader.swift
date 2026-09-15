import Foundation
@testable import Pilgrim

/// Records every call, completes on demand, and fails when told to. Loads
/// are queued so a test can complete them one at a time and observe the
/// manager between them.
final class FakeTileRegionLoader: TileRegionLoading {

    final class Handle: TileLoadHandle {
        private(set) var isCancelled = false
        func cancel() { isCancelled = true }
    }

    struct PendingRegion {
        let request: TileRegionRequest
        let progress: (Int, Int) -> Void
        let completion: (Result<TileRegionSummary, TileRegionLoadingError>) -> Void
        let handle: Handle
    }

    struct PendingPack {
        let pack: StylePackRequest
        let completion: (Result<Void, TileRegionLoadingError>) -> Void
        let handle: Handle
    }

    private(set) var stylePacks: Set<StylePackRequest> = []
    private(set) var stored: [String: TileRegionSummary] = [:]
    private(set) var regionRequests: [TileRegionRequest] = []
    private(set) var packRequests: [StylePackRequest] = []
    private(set) var removedIds: [String] = []
    private(set) var pendingRegions: [PendingRegion] = []
    private(set) var pendingPacks: [PendingPack] = []

    /// When set, `completeNextRegion()` fails with it instead of storing.
    var nextRegionFailure: TileRegionLoadingError?
    /// Resource count a completed region reports; tests that care set it.
    var requiredResourcesPerRegion = 10
    var bytesPerRegion = 100_000

    func hasStylePack(_ pack: StylePackRequest) -> Bool { stylePacks.contains(pack) }

    func loadStylePack(_ pack: StylePackRequest,
                       completion: @escaping (Result<Void, TileRegionLoadingError>) -> Void) -> TileLoadHandle {
        packRequests.append(pack)
        let handle = Handle()
        pendingPacks.append(PendingPack(pack: pack, completion: completion, handle: handle))
        return handle
    }

    func loadRegion(_ request: TileRegionRequest,
                    progress: @escaping (Int, Int) -> Void,
                    completion: @escaping (Result<TileRegionSummary, TileRegionLoadingError>) -> Void) -> TileLoadHandle {
        regionRequests.append(request)
        let handle = Handle()
        pendingRegions.append(PendingRegion(request: request, progress: progress, completion: completion, handle: handle))
        return handle
    }

    func regions() -> [TileRegionSummary] { Array(stored.values) }

    func removeRegion(id: String) {
        removedIds.append(id)
        stored[id] = nil
    }

    // MARK: - Driving the fake

    func completeNextPack() {
        guard !pendingPacks.isEmpty else { return }
        let pending = pendingPacks.removeFirst()
        stylePacks.insert(pending.pack)
        pending.completion(.success(()))
    }

    func completeNextRegion() {
        guard !pendingRegions.isEmpty else { return }
        let pending = pendingRegions.removeFirst()
        if let failure = nextRegionFailure {
            nextRegionFailure = nil
            pending.completion(.failure(failure))
            return
        }
        let summary = TileRegionSummary(id: pending.request.id,
                                        completedResourceCount: requiredResourcesPerRegion,
                                        requiredResourceCount: requiredResourcesPerRegion,
                                        completedResourceSize: bytesPerRegion,
                                        metadata: ["corridorHash": pending.request.corridorHash])
        stored[summary.id] = summary
        pending.completion(.success(summary))
    }

    /// Seeds a region as though a previous save stored it.
    func seed(id: String, corridorHash: String, complete: Bool = true, bytes: Int = 100_000) {
        stored[id] = TileRegionSummary(id: id,
                                       completedResourceCount: complete ? 10 : 4,
                                       requiredResourceCount: 10,
                                       completedResourceSize: bytes,
                                       metadata: ["corridorHash": corridorHash])
    }

    func seedStylePacks() { stylePacks = Set(StylePackRequest.allCases) }
}
