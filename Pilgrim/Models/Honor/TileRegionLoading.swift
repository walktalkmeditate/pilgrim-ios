import CoreLocation
import Foundation

/// What a region load asks for, with no Mapbox type in it: the manager
/// builds one of these, the production loader turns it into
/// `TileRegionLoadOptions`, and the fake just records it.
struct TileRegionRequest: Equatable {
    let id: String
    /// Closed ring, first coordinate repeated last. WGS84.
    let ring: [CLLocationCoordinate2D]
    /// Stable hash of `ring` so a resumed save can tell a redrawn stage
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
}

/// A handle the manager can cancel. The production loader wraps Mapbox's
/// `Cancelable`; the fake flips a flag.
protocol TileLoadHandle: AnyObject {
    func cancel()
}

/// The one seam between the manager and Mapbox. Every method is
/// synchronous to call and reports through closures on the main queue.
protocol TileRegionLoading: AnyObject {
    /// The store answers asynchronously, so a `regions()` read taken before
    /// the first answer lands sees nothing. This is how that synchronous
    /// reader learns the answer changed and is worth asking again.
    var onChange: (() -> Void)? { get set }

    func hasStylePack(_ pack: StylePackRequest) -> Bool
    func loadStylePack(_ pack: StylePackRequest,
                       completion: @escaping (Result<Void, TileRegionLoadingError>) -> Void) -> TileLoadHandle
    func loadRegion(_ request: TileRegionRequest,
                    progress: @escaping (_ completed: Int, _ required: Int) -> Void,
                    completion: @escaping (Result<TileRegionSummary, TileRegionLoadingError>) -> Void) -> TileLoadHandle
    func regions() -> [TileRegionSummary]
    func removeRegion(id: String)
}
