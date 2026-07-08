import UIKit
import MapboxMaps

// MARK: - Fog State Model (pure — rendering below is verified on device)

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

    let circles: [FogCircle]
    /// Celestial override for the active fog's color (turning or full moon);
    /// nil renders the default fog grey. Fixed per walk. Halos keep dawn.
    let tintHex: String?

    init(circles: [FogCircle], tintHex: String? = nil) {
        self.circles = circles
        self.tintHex = tintHex
    }

    /// The active clearing's current bucket — callers feed this back into
    /// the next `fogState` call so hysteresis has a reference point.
    var activeFogBucket: Int? {
        circles.first { !$0.isHalo }?.opacityBucket
    }
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
        tintHex: String? = nil
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
        }

        return SeekFogState(circles: circles, tintHex: tintHex)
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

    static func fogCircleID(forClearingIndex index: Int) -> String {
        "seek-fog-\(index)"
    }
}

// MARK: - Renderer bookkeeping

/// Coordinator-owned fog/ring state, kept in its own class so the main map
/// file only gains one stored property.
final class SeekFogRenderer {
    var pendingState: SeekFogState?
    var lastAppliedState: SeekFogState?
    var appliedCircles: [String: SeekFogState.FogCircle] = [:]
    var hasDeferredUpdate = false
    var lastHandledPulseToken = 0

    /// A style reload wipes every layer; forget what was applied so the next
    /// pass reinstalls from scratch.
    func resetForStyleReload() {
        lastAppliedState = nil
        appliedCircles = [:]
    }
}

// MARK: - Mapbox rendering

extension PilgrimMapView {

    private enum SeekFogRendering {
        // Fixed palette values (light-mode fog/dawn) — adaptive named colors
        // invert in dark mode and become bright halos on the map.
        static let fogColor = UIColor(hex: "#8A8175")
        static let haloColor = UIColor(hex: "#C4956A")
        static let ringColor = UIColor(hex: "#C4956A")
        static let fogTransitionDuration: TimeInterval = 1.5
        static let fogBlur = 1.0
        static let ringLayerID = "seek-pulse-ring"
        static let ringSourceID = "seek-pulse-ring-source"
        static let ringTransitionDuration: TimeInterval = 1.2
        static let ringStartRadiusPixels = 12.0
        static let ringEndRadiusPixels = 80.0
        static let ringStartOpacity = 0.45
        static let ringBlur = 0.6
        static let metersPerPixelEquatorZ0 = 78271.517
    }

    static func applySeekFog(
        _ state: SeekFogState?,
        pulseToken: Int,
        on mapView: MBMapView,
        coordinator: Coordinator
    ) {
        let renderer = coordinator.seekFogRenderer
        renderer.pendingState = state

        guard coordinator.shouldRender else {
            // Pulses are moments, not state: swallow tokens seen while paused
            // so stale rings never fire on resume. Fog state is queued and
            // flushed instead, like deferred route updates.
            renderer.lastHandledPulseToken = pulseToken
            if renderer.lastAppliedState != state {
                renderer.hasDeferredUpdate = true
            }
            return
        }

        applySeekFogNow(state, on: mapView, renderer: renderer)
        if pulseToken != renderer.lastHandledPulseToken {
            renderer.lastHandledPulseToken = pulseToken
            if state != nil {
                fireSeekPulseRing(on: mapView)
            }
        }
    }

    /// Called from `onStyleLoaded` (weak-captured there, AF70): the fresh
    /// style has no seek layers, so reinstall from the pending state.
    static func reinstallSeekFog(on mapView: MBMapView, coordinator: Coordinator) {
        let renderer = coordinator.seekFogRenderer
        renderer.resetForStyleReload()
        guard coordinator.shouldRender else {
            if renderer.pendingState != nil {
                renderer.hasDeferredUpdate = true
            }
            return
        }
        applySeekFogNow(renderer.pendingState, on: mapView, renderer: renderer)
    }

    static func flushDeferredSeekFog(on mapView: MBMapView, coordinator: Coordinator) {
        let renderer = coordinator.seekFogRenderer
        guard renderer.hasDeferredUpdate else { return }
        // Keep the flag while the style is still loading — clearing it before
        // a guaranteed apply silently drops the deferred update.
        guard mapView.mapboxMap.isStyleLoaded else { return }
        renderer.hasDeferredUpdate = false
        applySeekFogNow(renderer.pendingState, on: mapView, renderer: renderer)
    }

    private static func applySeekFogNow(
        _ state: SeekFogState?,
        on mapView: MBMapView,
        renderer: SeekFogRenderer
    ) {
        guard mapView.mapboxMap.isStyleLoaded else { return }
        // Equality early-return (AF20): updateUIView runs on every body
        // evaluation; fog rarely changes. `nil == nil` also keeps the whole
        // seek path from ever touching the style on wander walks.
        if renderer.lastAppliedState == state {
            // Trust, but verify: a lock/unlock cycle can strip runtime layers
            // without any style event (field-confirmed on the SE 3), leaving
            // the bookkeeping claiming fog that no longer exists. One layer
            // probe per pass keeps the map self-healing.
            guard let firstCircle = state?.circles.first,
                  !mapView.mapboxMap.layerExists(withId: firstCircle.id) else { return }
            renderer.resetForStyleReload()
        }
        guard let state else {
            for id in renderer.appliedCircles.keys {
                removeFogCircle(id: id, from: mapView)
            }
            removeRingLayer(from: mapView)
            renderer.appliedCircles = [:]
            renderer.lastAppliedState = nil
            return
        }

        var applied: [String: SeekFogState.FogCircle] = [:]
        for circle in state.circles {
            syncFogCircle(
                circle,
                previous: renderer.appliedCircles[circle.id],
                tintHex: state.tintHex,
                on: mapView
            )
            applied[circle.id] = circle
        }
        for id in renderer.appliedCircles.keys where applied[id] == nil {
            removeFogCircle(id: id, from: mapView)
        }
        renderer.appliedCircles = applied
        renderer.lastAppliedState = state
    }

    private static func syncFogCircle(
        _ circle: SeekFogState.FogCircle,
        previous: SeekFogState.FogCircle?,
        tintHex: String?,
        on mapView: MBMapView
    ) {
        guard let previous else {
            installFogCircle(circle, tintHex: tintHex, on: mapView)
            return
        }
        guard previous != circle else { return }
        if previous.center == circle.center,
           previous.radiusMeters == circle.radiusMeters,
           previous.isHalo == circle.isHalo {
            setFogOpacity(circle, on: mapView)
        } else {
            // Geometry or role changed (reroll, fog → halo): recreate so the
            // entrance-at-zero write below fades the new circle in.
            removeFogCircle(id: circle.id, from: mapView)
            installFogCircle(circle, tintHex: tintHex, on: mapView)
        }
    }

    private static func installFogCircle(
        _ circle: SeekFogState.FogCircle,
        tintHex: String?,
        on mapView: MBMapView
    ) {
        // Transitions are set once at creation; every later opacity write is
        // GPU-eased by them — no timers. Reduce Motion drops them to instant.
        let duration = UIAccessibility.isReduceMotionEnabled ? 0 : SeekFogRendering.fogTransitionDuration
        do {
            var source = GeoJSONSource(id: fogSourceID(for: circle.id))
            source.data = .feature(Feature(geometry: Point(circle.center.coordinate)))
            try mapView.mapboxMap.addSource(source)

            let fogColor = tintHex.map { UIColor(hex: $0) } ?? SeekFogRendering.fogColor
            var layer = CircleLayer(id: circle.id, source: fogSourceID(for: circle.id))
            layer.circleColor = .constant(StyleColor(circle.isHalo ? SeekFogRendering.haloColor : fogColor))
            layer.circleBlur = .constant(SeekFogRendering.fogBlur)
            layer.circlePitchAlignment = .constant(.map)
            layer.circleStrokeWidth = .constant(0)
            layer.circleRadius = .expression(fogRadiusExpression(
                radiusMeters: circle.radiusMeters,
                latitude: circle.center.latitude
            ))
            layer.circleOpacity = .constant(0)
            layer.circleOpacityTransition = StyleTransition(duration: duration, delay: 0)
            layer.circleBlurTransition = StyleTransition(duration: duration, delay: 0)
            try mapView.mapboxMap.addLayer(layer, layerPosition: fogLayerPosition(on: mapView))

            // Entrance: created at opacity 0, target written in the same
            // update pass — the opacity transition renders the fade-in.
            try mapView.mapboxMap.setLayerProperty(
                for: circle.id,
                property: "circle-opacity",
                value: SeekFogModel.opacity(forBucket: circle.opacityBucket, isHalo: circle.isHalo)
            )
        } catch {
            print("[PilgrimMapView] seek fog install failed for \(circle.id): \(error)")
        }
    }

    private static func setFogOpacity(_ circle: SeekFogState.FogCircle, on mapView: MBMapView) {
        do {
            try mapView.mapboxMap.setLayerProperty(
                for: circle.id,
                property: "circle-opacity",
                value: SeekFogModel.opacity(forBucket: circle.opacityBucket, isHalo: circle.isHalo)
            )
        } catch {
            print("[PilgrimMapView] seek fog opacity write failed for \(circle.id): \(error)")
        }
    }

    private static func removeFogCircle(id: String, from mapView: MBMapView) {
        do {
            if mapView.mapboxMap.layerExists(withId: id) {
                try mapView.mapboxMap.removeLayer(withId: id)
            }
            if mapView.mapboxMap.sourceExists(withId: fogSourceID(for: id)) {
                try mapView.mapboxMap.removeSource(withId: fogSourceID(for: id))
            }
        } catch {
            print("[PilgrimMapView] seek fog removal failed for \(id): \(error)")
        }
    }

    /// Geographic sizing: circle-radius is in pixels, so interpolate
    /// exponentially (base 2) over zoom from the meters-per-pixel scale at
    /// z0 (78271.517·cos(lat)) up to z20 at ×2²⁰.
    private static func fogRadiusExpression(radiusMeters: Double, latitude: Double) -> Exp {
        let metersPerPixelAtZ0 = SeekFogRendering.metersPerPixelEquatorZ0 * cos(latitude * .pi / 180)
        let radiusPixelsAtZ0 = radiusMeters / metersPerPixelAtZ0
        return Exp(.interpolate) {
            Exp(.exponential) { 2.0 }
            Exp(.zoom)
            0
            radiusPixelsAtZ0
            20
            radiusPixelsAtZ0 * pow(2.0, 20.0)
        }
    }

    /// Fog sits under the route line so the walked path stays legible.
    private static func fogLayerPosition(on mapView: MBMapView) -> LayerPosition? {
        mapView.mapboxMap.layerExists(withId: "pilgrim-route-casing")
            ? .below("pilgrim-route-casing")
            : nil
    }

    private static func fogSourceID(for circleID: String) -> String {
        "\(circleID)-source"
    }

    // MARK: - Puck pulse ring

    /// One-shot: recreate the ring at the puck with small/visible initial
    /// paint (initial values don't transition), then immediately write
    /// large/transparent — the layer's StyleTransitions ease it out on the
    /// GPU. No timers, no display link, no repeatForever.
    private static func fireSeekPulseRing(on mapView: MBMapView) {
        guard mapView.mapboxMap.isStyleLoaded,
              !UIAccessibility.isReduceMotionEnabled,
              let coordinate = mapView.location.latestLocation?.coordinate else { return }
        removeRingLayer(from: mapView)
        do {
            var source = GeoJSONSource(id: SeekFogRendering.ringSourceID)
            source.data = .feature(Feature(geometry: Point(coordinate)))
            try mapView.mapboxMap.addSource(source)

            var layer = CircleLayer(id: SeekFogRendering.ringLayerID, source: SeekFogRendering.ringSourceID)
            layer.circleColor = .constant(StyleColor(SeekFogRendering.ringColor))
            layer.circleBlur = .constant(SeekFogRendering.ringBlur)
            layer.circleStrokeWidth = .constant(0)
            layer.circleRadius = .constant(SeekFogRendering.ringStartRadiusPixels)
            layer.circleOpacity = .constant(SeekFogRendering.ringStartOpacity)
            layer.circleRadiusTransition = StyleTransition(duration: SeekFogRendering.ringTransitionDuration, delay: 0)
            layer.circleOpacityTransition = StyleTransition(duration: SeekFogRendering.ringTransitionDuration, delay: 0)
            try mapView.mapboxMap.addLayer(layer)

            try mapView.mapboxMap.setLayerProperty(
                for: SeekFogRendering.ringLayerID,
                property: "circle-radius",
                value: SeekFogRendering.ringEndRadiusPixels
            )
            try mapView.mapboxMap.setLayerProperty(
                for: SeekFogRendering.ringLayerID,
                property: "circle-opacity",
                value: 0.0
            )
        } catch {
            print("[PilgrimMapView] seek pulse ring failed: \(error)")
        }
    }

    private static func removeRingLayer(from mapView: MBMapView) {
        do {
            if mapView.mapboxMap.layerExists(withId: SeekFogRendering.ringLayerID) {
                try mapView.mapboxMap.removeLayer(withId: SeekFogRendering.ringLayerID)
            }
            if mapView.mapboxMap.sourceExists(withId: SeekFogRendering.ringSourceID) {
                try mapView.mapboxMap.removeSource(withId: SeekFogRendering.ringSourceID)
            }
        } catch {
            print("[PilgrimMapView] seek pulse ring removal failed: \(error)")
        }
    }
}
