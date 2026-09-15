import CoreLocation
import Foundation

/// What a region load asks for, with no Mapbox type in it: the manager
/// builds one of these, the production loader turns it into
/// `TileRegionLoadOptions`, and the fake just records it.
struct TileRegionRequest: Equatable {
    let id: String
    /// Closed rings, one per convex part of the corridor, each with its
    /// first coordinate repeated last. WGS84.
    let rings: [[CLLocationCoordinate2D]]
    /// Stable hash of `rings` so a resumed save can tell a redrawn stage
    /// from an unchanged one without re-deriving the geometry.
    let corridorHash: String
    let acceptExpired: Bool

    static func == (lhs: TileRegionRequest, rhs: TileRegionRequest) -> Bool {
        lhs.id == rhs.id && lhs.corridorHash == rhs.corridorHash && lhs.acceptExpired == rhs.acceptExpired
    }
}

enum StylePackRequest: String, CaseIterable {
    case light, dark
}

/// Our own view of a stored region. `metadata` is the JSON object the load
/// was given; the manager reads `corridorHash` back out of it.
struct TileRegionSummary: Equatable {
    let id: String
    let completedResourceCount: Int
    let requiredResourceCount: Int
    let completedResourceSize: Int
    let metadata: [String: String]

    var isComplete: Bool { requiredResourceCount > 0 && completedResourceCount >= requiredResourceCount }
    var corridorHash: String? { metadata["corridorHash"] }
}

enum TileRegionLoadingError: Error, Equatable {
    case failed
    case diskFull
    case cancelled
    /// The store's 750-unique-pack ceiling: the SDK refuses the region
    /// before downloading anything, so a retry would refuse the same way.
    case tileCountExceeded
}

/// A handle the manager can cancel. The production loader wraps Mapbox's
/// `Cancelable`; the fake flips a flag.
protocol TileLoadHandle: AnyObject {
    func cancel()
}

/// Which of the store's two answers arrived. They are separate round trips
/// that land at different times — the style packs come back from one call,
/// the regions from `allTileRegions` plus a metadata read each — and on a
/// phone that has saved maps the packs answer is reliably first. A reader
/// waiting for what is on disk must not be woken by the packs.
enum TileStoreChange: Equatable {
    case regions
    case packs
}

/// The one seam between the manager and Mapbox. Every method is
/// synchronous to call and reports through closures on the main queue.
protocol TileRegionLoading: AnyObject {
    /// The store answers asynchronously, so a `regions()` read taken before
    /// the first answer lands sees nothing. This is how that synchronous
    /// reader learns an answer arrived and is worth asking again — and which
    /// answer it was.
    var onChange: ((TileStoreChange) -> Void)? { get set }

    func hasStylePack(_ pack: StylePackRequest) -> Bool
    func loadStylePack(_ pack: StylePackRequest,
                       completion: @escaping (Result<Void, TileRegionLoadingError>) -> Void) -> TileLoadHandle
    func loadRegion(_ request: TileRegionRequest,
                    progress: @escaping (_ completed: Int, _ required: Int) -> Void,
                    completion: @escaping (Result<TileRegionSummary, TileRegionLoadingError>) -> Void) -> TileLoadHandle
    func regions() -> [TileRegionSummary]
    /// Asks the store for its regions and calls back when that answer has
    /// landed — even when the answer is "nothing changed" — so a launch-time
    /// reader can act on a real snapshot rather than on an empty cache.
    /// Unlike `onChange`, this fires on the answer, not on a difference: an
    /// empty store answers "no regions", which equals the empty cache and
    /// signals nothing at all.
    func refreshRegions(completion: @escaping () -> Void)
    func removeRegion(id: String)
}
