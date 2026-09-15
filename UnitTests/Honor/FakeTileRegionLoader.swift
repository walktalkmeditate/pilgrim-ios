import Foundation
import XCTest
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

    /// Fired wherever the real loader fires it, and labelled the way the
    /// real loader labels it — `.regions` on a stored region and a removal,
    /// `.packs` on a stored pack — so a test cannot prove the opposite of
    /// what production does.
    var onChange: ((TileStoreChange) -> Void)?

    var stylePacks: Set<StylePackRequest> = []
    private(set) var stored: [String: TileRegionSummary] = [:]
    private(set) var regionsReadCount = 0
    var regionRequests: [TileRegionRequest] = []
    private(set) var packRequests: [StylePackRequest] = []
    private(set) var removedIds: [String] = []
    private(set) var pendingRegions: [PendingRegion] = []
    private(set) var pendingPacks: [PendingPack] = []

    /// Whether there is a load for a test to complete. A test that drives the
    /// fake before the save has reached its next load parks the save on a
    /// continuation nobody will resume.
    var hasPendingWork: Bool { !pendingRegions.isEmpty || !pendingPacks.isEmpty }

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

    func regions() -> [TileRegionSummary] {
        regionsReadCount += 1
        return Array(stored.values)
    }

    private var pendingRegionsCompletions: [() -> Void] = []

    /// Never answered inline: production always answers asynchronously, and
    /// a fake that answered on the spot would let a test prove a launch
    /// sweep ran before the store had spoken. `releaseRegions()` is the
    /// store speaking.
    func refreshRegions(completion: @escaping () -> Void) {
        regionsReadCount += 1
        pendingRegionsCompletions.append(completion)
    }

    func removeRegion(id: String) {
        removedIds.append(id)
        stored[id] = nil
        onChange?(.regions)
    }

    // MARK: - Driving the fake

    /// Driving a completion with nothing pending means the test is a step
    /// ahead of the manager. Returning quietly leaves the manager waiting on
    /// a continuation nobody will resume, which hangs the whole suite rather
    /// than failing the one test that mis-sequenced.
    func completeNextPack() {
        guard !pendingPacks.isEmpty else {
            XCTFail("completeNextPack called with nothing pending")
            return
        }
        let pending = pendingPacks.removeFirst()
        stylePacks.insert(pending.pack)
        onChange?(.packs)
        pending.completion(.success(()))
    }

    func completeNextRegion() {
        guard !pendingRegions.isEmpty else {
            XCTFail("completeNextRegion called with nothing pending")
            return
        }
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
        onChange?(.regions)
        pending.completion(.success(summary))
    }

    /// The store answering: what the real loader does when a regions read
    /// lands — every completion waiting on it runs, once, after the cache.
    /// The real loader is silent when the answer matches its cache, and an
    /// empty store answering an empty cache is the launch case; a fake that
    /// signalled there would let a test pass on a signal production never
    /// sends.
    func releaseRegions() {
        let waiting = pendingRegionsCompletions
        pendingRegionsCompletions = []
        for completion in waiting { completion() }
        if !stored.isEmpty { onChange?(.regions) }
    }

    /// The style-pack answer on its own. On a phone that has saved maps this
    /// is the signal that arrives first, one round trip ahead of the regions.
    func firePacksChange() {
        onChange?(.packs)
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
