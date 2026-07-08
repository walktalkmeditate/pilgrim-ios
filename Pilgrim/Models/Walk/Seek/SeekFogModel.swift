import CoreGraphics
import Foundation

// MARK: - Fog State Model (pure — rendering lives in PilgrimMapView+SeekFog)

/// What the map should show for a seek: fog over the active clearing, faint
/// halos over found ones, and nothing at all for unrevealed clearings so the
/// chain's count stays hidden (origin R6).
struct SeekFogState: Equatable {

    struct FogCircle: Equatable {
        let id: String
        let center: SeekPoint
        let radiusMeters: Double
        /// 0 = dissolved (arrived/halo), 1...N = distance buckets, thicker far.
        let opacityBucket: Int
        /// Found clearings keep a faint persistent halo after their reveal.
        let isHalo: Bool
    }

    /// The wisp: a dawn crescent hugging the puck's rim on the clearing's
    /// side, so a map glance answers "which way" without hunting the fog.
    /// Attached to the walker (rotation-only), never a floating marker.
    struct Wisp: Equatable {
        let position: SeekPoint
        let bearingDegrees: Double
    }

    let circles: [FogCircle]
    /// Celestial override for the active fog's color (turning or full moon);
    /// nil renders the default fog grey. Fixed per walk. Halos keep dawn.
    let tintHex: String?
    /// Nil when hidden (arrived, revealing, complete, or no walker fix).
    /// Whether a present wisp is *shown* is the renderer's call: it releases
    /// the crescent whenever the fog itself is visible in the viewport.
    let wisp: Wisp?

    init(circles: [FogCircle], tintHex: String? = nil, wisp: Wisp? = nil) {
        self.circles = circles
        self.tintHex = tintHex
        self.wisp = wisp
    }

    /// The active clearing's current bucket — callers feed this back into
    /// the next `fogState` call so hysteresis has a reference point.
    var activeFogBucket: Int? {
        circles.first { !$0.isHalo }?.opacityBucket
    }
}

/// One pulse of the seek heartbeat as the map sees it: the token advances
/// per pulse, and alignment/closeness shape the crescent's flare the same
/// way they already shape the ping and the haptic.
struct SeekPulseVisual: Equatable {
    let token: Int
    let aligned: Bool
    let closeness: Double

    static let none = SeekPulseVisual(token: 0, aligned: false, closeness: 0)
}

enum SeekFogModel {

    /// Bucket k covers distances below boundary k (ascending); anything at or
    /// beyond the last boundary — or with no fix yet — is the thickest bucket.
    static let distanceBucketBoundariesMeters: [Double] = [150, 300, 600, 1200]
    /// A fix must land this fraction beyond a boundary before an adjacent
    /// bucket change applies, so GPS jitter on the line cannot thrash writes.
    static let hysteresisFraction = 0.1
    static let bucketOpacities: [Double] = [0.25, 0.35, 0.45, 0.55, 0.65]
    static let haloOpacity = 0.12
    static let dissolvedOpacity = 0.0

    static var farthestBucket: Int { distanceBucketBoundariesMeters.count + 1 }

    static func fogState(
        chain: SeekChain,
        activeIndex: Int,
        phase: SeekEnginePhase,
        distanceToActiveMeters: Double?,
        previousActiveBucket: Int? = nil,
        tintHex: String? = nil,
        walkerPosition: SeekPoint? = nil
    ) -> SeekFogState {
        let count = chain.clearings.count
        guard count > 0 else { return SeekFogState(circles: []) }
        let clampedActive = min(max(activeIndex, 0), count - 1)
        let haloCount = phase == .complete ? clampedActive + 1 : clampedActive

        var circles: [SeekFogState.FogCircle] = (0..<haloCount).map { index in
            let clearing = chain.clearings[index]
            return SeekFogState.FogCircle(
                id: fogCircleID(forClearingIndex: index),
                center: clearing.center,
                radiusMeters: clearing.radiusMeters,
                opacityBucket: 0,
                isHalo: true
            )
        }

        var wisp: SeekFogState.Wisp?
        if phase != .complete {
            let clearing = chain.clearings[clampedActive]
            let bucket = phase == .guiding
                ? bucketApplyingHysteresis(
                    distanceMeters: distanceToActiveMeters,
                    currentBucket: previousActiveBucket
                )
                : 0
            circles.append(SeekFogState.FogCircle(
                id: fogCircleID(forClearingIndex: clampedActive),
                center: clearing.center,
                radiusMeters: clearing.radiusMeters,
                opacityBucket: bucket,
                isHalo: false
            ))
            wisp = wispPoint(
                walkerPosition: walkerPosition,
                clearingCenter: clearing.center,
                phase: phase
            )
        }

        return SeekFogState(circles: circles, tintHex: tintHex, wisp: wisp)
    }

    static func wispPoint(
        walkerPosition: SeekPoint?,
        clearingCenter: SeekPoint,
        phase: SeekEnginePhase
    ) -> SeekFogState.Wisp? {
        guard phase == .guiding, let walkerPosition else { return nil }
        var bearing = SeekChainGenerator.bearingDegrees(from: walkerPosition, to: clearingCenter)
        if bearing < 0 { bearing += 360 }
        return SeekFogState.Wisp(position: walkerPosition, bearingDegrees: bearing)
    }

    static func opacityBucket(forDistanceMeters distance: Double?) -> Int {
        guard let distance else { return farthestBucket }
        for (index, boundary) in distanceBucketBoundariesMeters.enumerated() where distance < boundary {
            return index + 1
        }
        return farthestBucket
    }

    /// Adjacent-bucket changes only apply once the fix is a margin past the
    /// shared boundary; jumps of 2+ buckets (reroll, first fix) apply as-is.
    static func bucketApplyingHysteresis(distanceMeters: Double?, currentBucket: Int?) -> Int {
        let raw = opacityBucket(forDistanceMeters: distanceMeters)
        guard let current = currentBucket, (1...farthestBucket).contains(current),
              let distance = distanceMeters, raw != current else {
            return raw
        }
        guard abs(raw - current) == 1 else { return raw }
        let boundary = distanceBucketBoundariesMeters[min(raw, current) - 1]
        let margin = boundary * hysteresisFraction
        if raw < current {
            return distance <= boundary - margin ? raw : current
        }
        return distance >= boundary + margin ? raw : current
    }

    static func opacity(forBucket bucket: Int, isHalo: Bool) -> Double {
        if isHalo { return haloOpacity }
        guard bucket >= 1 else { return dissolvedOpacity }
        return bucketOpacities[min(bucket, bucketOpacities.count) - 1]
    }

    /// The crescent opens as the fog nears: a narrow sliver far out, a
    /// full curve close in. Keyed to the fog buckets (nearest first) so
    /// span changes inherit their boundary hysteresis and never thrash.
    static let wispSpanDegreesNearToFar: [Double] = [96, 86, 72, 60, 48]

    static func wispSpanDegrees(forBucket bucket: Int?) -> Double {
        guard let bucket else { return wispSpanDegreesNearToFar[wispSpanDegreesNearToFar.count - 1] }
        let clamped = min(max(bucket, 1), wispSpanDegreesNearToFar.count)
        return wispSpanDegreesNearToFar[clamped - 1]
    }

    static func fogCircleID(forClearingIndex index: Int) -> String {
        "seek-fog-\(index)"
    }
}

// MARK: - Wisp viewport release (pure screen-space geometry)

/// The crescent is a pointer to something beyond sight: the moment the fog
/// itself is on screen — zoomed out to it or walked near it — the pointer
/// is redundant and releases. Screen-space intersection with a hysteresis
/// band so a fog edge grazing the viewport during a pan cannot flicker it.
enum SeekWispVisibilityModel {

    /// The fog must reach this far *into* the viewport before the crescent
    /// releases, and retreat this far *beyond* the edge before it returns.
    static let releaseInsetPoints: CGFloat = 24
    static let returnOutsetPoints: CGFloat = 24

    /// Returns the new released state given the previous one. `fogCenter`
    /// is nil when the fog cannot be projected onto the screen — Mapbox's
    /// `point(for:)` collapses every off-view coordinate to (-1, -1), so an
    /// unprojectable fog is definitionally not visible: the crescent shows.
    static func shouldRelease(
        wasReleased: Bool,
        fogCenter: CGPoint?,
        fogRadiusPoints: CGFloat,
        viewSize: CGSize
    ) -> Bool {
        guard let fogCenter else { return false }
        guard viewSize.width > 0, viewSize.height > 0,
              fogCenter.x.isFinite, fogCenter.y.isFinite, fogRadiusPoints.isFinite else {
            return wasReleased
        }
        let bounds = CGRect(origin: .zero, size: viewSize)
        let rect = wasReleased
            ? bounds.insetBy(dx: -returnOutsetPoints, dy: -returnOutsetPoints)
            : bounds.insetBy(dx: releaseInsetPoints, dy: releaseInsetPoints)
        return circleIntersects(center: fogCenter, radius: fogRadiusPoints, rect: rect)
    }

    static func circleIntersects(center: CGPoint, radius: CGFloat, rect: CGRect) -> Bool {
        guard !rect.isNull, !rect.isEmpty else { return false }
        let dx = max(rect.minX - center.x, 0, center.x - rect.maxX)
        let dy = max(rect.minY - center.y, 0, center.y - rect.maxY)
        return dx * dx + dy * dy <= radius * radius
    }
}
