import CoreLocation

/// Plans Mapbox GeoJSON source updates for the growing walk route so that
/// per-GPS-sample work stays bounded (AF9/AF46).
///
/// The route is represented in the source as a series of immutable, sealed
/// "chunk" LineString features plus one mutable "tail" feature that tracks
/// the open end of the route. Each new sample only rewrites the tail
/// (≤ `chunkSize` + 1 coordinates); once the tail outgrows `chunkSize` it is
/// sealed into a chunk and a fresh tail begins. Adjacent features overlap by
/// one coordinate so the rendered line stays continuous.
///
/// The planner is pure state-in/plan-out: `PilgrimMapView` translates plans
/// into `addGeoJSONSourceFeatures` / `updateGeoJSONSourceFeatures` calls.
/// Anything that is not append-only growth (recovery reseed, style reload,
/// color change) falls back to a full rebuild.
struct RouteSourcePlanner {

    static let defaultChunkSize = 200
    static let tailFeatureID = "route-tail"

    struct Chunk {
        let id: String
        let activityType: String
        let coordinates: [CLLocationCoordinate2D]
    }

    enum TailAction: Equatable {
        case none
        case set(Chunk, isNew: Bool)
        case remove
    }

    enum Plan: Equatable {
        case noChange
        /// Replace the whole source contents with these features.
        case fullRebuild([Chunk])
        /// Append the sealed chunks, then apply the tail action.
        case incremental(addedChunks: [Chunk], tailAction: TailAction)
    }

    let chunkSize: Int

    private(set) var segments: [RouteSegment] = []
    /// Coordinates of the LAST segment already sealed into chunk features.
    private var sealedCoordCount = 0
    private var nextChunkIndex = 0
    /// Whether the tail feature currently exists in the source.
    private var tailExists = false

    init(chunkSize: Int = RouteSourcePlanner.defaultChunkSize) {
        self.chunkSize = chunkSize
    }

    mutating func reset() {
        segments = []
        sealedCoordCount = 0
        nextChunkIndex = 0
        tailExists = false
    }

    mutating func plan(for newSegments: [RouteSegment]) -> Plan {
        guard newSegments != segments else { return .noChange }
        guard isAppendOnlyGrowth(to: newSegments) else { return rebuild(with: newSegments) }
        return planIncremental(for: newSegments)
    }

    // MARK: - Growth Detection

    /// True when `newSegments` only extends the current route: every earlier
    /// segment unchanged, the previously-open segment same-typed and at least
    /// as long (an activity transition appends the boundary coordinate to the
    /// closing segment), and at most one new segment opened. Growth from
    /// empty is a full rebuild — `reset()` always pairs with a source
    /// teardown, and the creation path only consumes `.fullRebuild` plans.
    private func isAppendOnlyGrowth(to newSegments: [RouteSegment]) -> Bool {
        guard !segments.isEmpty else { return false }
        guard newSegments.count == segments.count || newSegments.count == segments.count + 1 else {
            return false
        }
        for index in 0..<(segments.count - 1) where newSegments[index] != segments[index] {
            return false
        }
        let oldOpen = segments[segments.count - 1]
        let counterpart = newSegments[segments.count - 1]
        return counterpart.activityType == oldOpen.activityType
            && counterpart.coordinates.count >= oldOpen.coordinates.count
    }

    // MARK: - Planning

    private mutating func planIncremental(for newSegments: [RouteSegment]) -> Plan {
        var added: [Chunk] = []
        var openSegmentChanged = false

        if newSegments.count > segments.count, !segments.isEmpty {
            // The previously-open segment closed at an activity transition.
            // Seal its unsealed remainder (including the shared boundary
            // coordinate) so the tail feature can move to the new segment.
            let closing = newSegments[segments.count - 1]
            let start = tailStart
            if closing.coordinates.count - start >= 2 {
                added.append(makeChunk(
                    coordinates: Array(closing.coordinates[start...]),
                    activityType: closing.activityType
                ))
            }
            sealedCoordCount = 0
            openSegmentChanged = true
        }

        guard let open = newSegments.last else {
            segments = newSegments
            return .incremental(addedChunks: added, tailAction: tailExists ? .remove : .none)
        }
        let coords = open.coordinates

        while coords.count - tailStart > chunkSize + 1 {
            let start = tailStart
            let end = start + chunkSize
            added.append(makeChunk(
                coordinates: Array(coords[start...end]),
                activityType: open.activityType
            ))
            sealedCoordCount = end + 1
        }

        let tailCoords = Array(coords[min(tailStart, coords.count)...])
        let tailAction: TailAction
        if tailCoords.count >= 2 {
            let tail = Chunk(id: Self.tailFeatureID, activityType: open.activityType, coordinates: tailCoords)
            tailAction = .set(tail, isNew: !tailExists)
            tailExists = true
        } else if tailExists && openSegmentChanged {
            // New open segment has a single coordinate (the transition
            // boundary) — the old tail geometry was just sealed into a
            // chunk, so drop the stale tail feature until the segment grows.
            tailAction = .remove
            tailExists = false
        } else {
            tailAction = .none
        }

        segments = newSegments
        return .incremental(addedChunks: added, tailAction: tailAction)
    }

    private mutating func rebuild(with newSegments: [RouteSegment]) -> Plan {
        nextChunkIndex = 0
        sealedCoordCount = 0
        tailExists = false
        segments = newSegments

        var chunks: [Chunk] = []
        for segment in newSegments.dropLast() where segment.coordinates.count > 1 {
            chunks.append(makeChunk(coordinates: segment.coordinates, activityType: segment.activityType))
        }

        if let open = newSegments.last {
            let coords = open.coordinates
            while coords.count - tailStart > chunkSize + 1 {
                let start = tailStart
                let end = start + chunkSize
                chunks.append(makeChunk(
                    coordinates: Array(coords[start...end]),
                    activityType: open.activityType
                ))
                sealedCoordCount = end + 1
            }
            let tailCoords = Array(coords[min(tailStart, coords.count)...])
            if tailCoords.count >= 2 {
                chunks.append(Chunk(id: Self.tailFeatureID, activityType: open.activityType, coordinates: tailCoords))
                tailExists = true
            }
        }

        return .fullRebuild(chunks)
    }

    // MARK: - Helpers

    /// First coordinate index of the open segment's unsealed span. Overlaps
    /// the last sealed chunk by one coordinate so the line stays continuous.
    private var tailStart: Int {
        sealedCoordCount == 0 ? 0 : sealedCoordCount - 1
    }

    private mutating func makeChunk(coordinates: [CLLocationCoordinate2D], activityType: String) -> Chunk {
        defer { nextChunkIndex += 1 }
        return Chunk(id: "route-chunk-\(nextChunkIndex)", activityType: activityType, coordinates: coordinates)
    }
}

extension RouteSourcePlanner.Chunk: Equatable {
    static func == (lhs: RouteSourcePlanner.Chunk, rhs: RouteSourcePlanner.Chunk) -> Bool {
        lhs.id == rhs.id
            && lhs.activityType == rhs.activityType
            && lhs.coordinates.count == rhs.coordinates.count
            && zip(lhs.coordinates, rhs.coordinates).allSatisfy {
                $0.latitude == $1.latitude && $0.longitude == $1.longitude
            }
    }
}
