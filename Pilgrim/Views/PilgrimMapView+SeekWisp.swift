import UIKit
import MapboxMaps

// The wisp crescent: which-way affordance on the puck's rim. It breathes
// with the seek's pulse clock (a flare per pulse, GPU-eased — no standing
// timers) and releases whenever the fog itself is visible in the viewport,
// exhaling into the thing it pointed at. Pure decisions live in
// SeekWispVisibilityModel; this file is the Mapbox side.

extension PilgrimMapView {

    enum SeekWispRendering {
        static let layerID = "seek-wisp"
        static let sourceID = "seek-wisp-source"
        static let imageID = "seek-wisp-crescent"
        /// Between pulses the crescent rests dim, almost asleep; each pulse
        /// swells it. Under Reduce Motion it holds steady instead.
        static let restOpacity = 0.55
        static let steadyOpacity = 0.8
        /// Flare peak grows with closeness; an aligned pulse outshines both.
        static let flarePeakBase = 0.75
        static let flarePeakClosenessSpan = 0.15
        static let alignedFlarePeak = 1.0
        /// One shared transition eases every opacity write — swell, settle,
        /// exhale, and return all breathe at the same pace.
        static let breathDuration: TimeInterval = 1.0
        /// The settle write lands just after the swell completes.
        static let flareHoldSeconds: TimeInterval = 1.05
        /// Crescent geometry (points): the arc hugs the puck's rim just
        /// inside the pulsing halo, drawn pointing north and rotated by
        /// bearing at render time.
        static let imageSize = 76.0
        static let arcRadius = 30.0
        static let arcSpanDegrees = 76.0
        /// Camera-change events arrive per frame during gestures; the
        /// visibility check runs at most this often, with `onMapIdle`
        /// providing the authoritative trailing check.
        static let visibilityThrottleSeconds: TimeInterval = 0.12
    }

    /// The wisp rides the walker's own coordinate and only rotates — a
    /// crescent of dawn on the puck's rim, not a floating marker. Screen
    /// geometry is constant across zooms (it is an affordance, not
    /// geography). Opacity is owned by the flare/visibility writes below;
    /// this only manages existence, position, and rotation.
    static func syncWispLayer(
        _ wisp: SeekFogState.Wisp?,
        previous: SeekFogState.Wisp?,
        renderer: SeekFogRenderer,
        on mapView: MBMapView
    ) {
        guard wisp != previous else { return }
        guard let wisp else {
            removeWispLayer(from: mapView, renderer: renderer)
            return
        }
        do {
            if mapView.mapboxMap.layerExists(withId: SeekWispRendering.layerID),
               mapView.mapboxMap.sourceExists(withId: SeekWispRendering.sourceID) {
                try mapView.mapboxMap.updateGeoJSONSource(
                    withId: SeekWispRendering.sourceID,
                    geoJSON: .feature(Feature(geometry: Point(wisp.position.coordinate)))
                )
                try mapView.mapboxMap.setLayerProperty(
                    for: SeekWispRendering.layerID,
                    property: "icon-rotate",
                    value: wisp.bearingDegrees
                )
                return
            }
            removeWispLayer(from: mapView, renderer: renderer)

            try? mapView.mapboxMap.addImage(wispCrescentImage(), id: SeekWispRendering.imageID)

            var source = GeoJSONSource(id: SeekWispRendering.sourceID)
            source.data = .feature(Feature(geometry: Point(wisp.position.coordinate)))
            try mapView.mapboxMap.addSource(source)

            let reduceMotion = UIAccessibility.isReduceMotionEnabled
            var layer = SymbolLayer(id: SeekWispRendering.layerID, source: SeekWispRendering.sourceID)
            layer.iconImage = .constant(.name(SeekWispRendering.imageID))
            layer.iconRotate = .constant(wisp.bearingDegrees)
            layer.iconRotationAlignment = .constant(.map)
            layer.iconAllowOverlap = .constant(true)
            layer.iconIgnorePlacement = .constant(true)
            layer.iconOpacity = .constant(0)
            layer.iconOpacityTransition = StyleTransition(
                duration: reduceMotion ? 0 : SeekWispRendering.breathDuration,
                delay: 0
            )
            try mapView.mapboxMap.addLayer(layer)
            // A released wisp reinstalls at zero (style reload with fog on
            // screen) so the handoff exhale never replays.
            writeWispOpacity(
                renderer.wispReleased ? 0 : wispRestingOpacity(),
                on: mapView
            )
        } catch {
            print("[PilgrimMapView] seek wisp sync failed: \(error)")
        }
    }

    static func removeWispLayer(from mapView: MBMapView, renderer: SeekFogRenderer) {
        renderer.wispReleased = false
        renderer.wispFlareGeneration += 1
        do {
            if mapView.mapboxMap.layerExists(withId: SeekWispRendering.layerID) {
                try mapView.mapboxMap.removeLayer(withId: SeekWispRendering.layerID)
            }
            if mapView.mapboxMap.sourceExists(withId: SeekWispRendering.sourceID) {
                try mapView.mapboxMap.removeSource(withId: SeekWispRendering.sourceID)
            }
        } catch {
            print("[PilgrimMapView] seek wisp removal failed: \(error)")
        }
    }

    // MARK: - Pulse breathing

    /// One breath per pulse: swell to a peak shaped by closeness (warmer
    /// still when aligned), then settle back to rest. Both writes ride the
    /// layer's single opacity transition — the only bookkeeping is the
    /// generation guard that turns a superseded settle into a no-op.
    static func flareSeekWisp(
        _ pulse: SeekPulseVisual,
        on mapView: MBMapView,
        renderer: SeekFogRenderer
    ) {
        guard !UIAccessibility.isReduceMotionEnabled,
              !renderer.wispReleased,
              mapView.mapboxMap.isStyleLoaded,
              mapView.mapboxMap.layerExists(withId: SeekWispRendering.layerID) else { return }
        renderer.wispFlareGeneration += 1
        let generation = renderer.wispFlareGeneration
        let peak = pulse.aligned
            ? SeekWispRendering.alignedFlarePeak
            : SeekWispRendering.flarePeakBase
                + SeekWispRendering.flarePeakClosenessSpan * min(max(pulse.closeness, 0), 1)
        writeWispOpacity(peak, on: mapView)
        let settle = DispatchTime.now() + SeekWispRendering.flareHoldSeconds
        DispatchQueue.main.asyncAfter(deadline: settle) { [weak mapView, weak renderer] in
            guard let mapView, let renderer,
                  renderer.wispFlareGeneration == generation,
                  !renderer.wispReleased,
                  mapView.mapboxMap.layerExists(withId: SeekWispRendering.layerID) else { return }
            writeWispOpacity(SeekWispRendering.restOpacity, on: mapView)
        }
    }

    // MARK: - Viewport release

    /// Wisp viewport release: camera moves re-decide whether the fog is on
    /// screen (throttled — these fire per frame during gestures), and map
    /// idle runs the authoritative trailing check. Both exit on the first
    /// guard for wander maps. Weak captures per AF70.
    static func installSeekWispCameraObservers(on mapView: MBMapView, coordinator: Coordinator) {
        mapView.mapboxMap.onCameraChanged.observe { [weak coordinator, weak mapView] _ in
            guard let coordinator, let mapView else { return }
            evaluateSeekWispVisibility(
                on: mapView, renderer: coordinator.seekFogRenderer, throttled: true
            )
        }.store(in: &coordinator.cancellables)
        mapView.mapboxMap.onMapIdle.observe { [weak coordinator, weak mapView] _ in
            guard let coordinator, let mapView else { return }
            evaluateSeekWispVisibility(
                on: mapView, renderer: coordinator.seekFogRenderer, throttled: false
            )
        }.store(in: &coordinator.cancellables)
    }

    /// Re-decides whether the crescent should be shown, from the active
    /// fog's screen-space footprint. Called from camera changes (throttled),
    /// map idle, and every fog apply. Cheap guards first: wander maps and
    /// seek maps without a wisp exit before touching any projection.
    static func evaluateSeekWispVisibility(
        on mapView: MBMapView,
        renderer: SeekFogRenderer,
        throttled: Bool
    ) {
        guard let state = renderer.lastAppliedState,
              state.wisp != nil,
              let fog = state.circles.first(where: { !$0.isHalo }) else { return }
        let now = CACurrentMediaTime()
        if throttled,
           now - renderer.lastWispVisibilityCheckUptime < SeekWispRendering.visibilityThrottleSeconds {
            return
        }
        renderer.lastWispVisibilityCheckUptime = now
        guard mapView.mapboxMap.isStyleLoaded else { return }

        let center = mapView.mapboxMap.point(for: fog.center.coordinate)
        let zoom = Double(mapView.mapboxMap.cameraState.zoom)
        let metersPerPoint = SeekFogRendering.metersPerPixelEquatorZ0
            * cos(fog.center.latitude * .pi / 180) / pow(2.0, zoom)
        guard metersPerPoint > 0 else { return }

        let released = SeekWispVisibilityModel.shouldRelease(
            wasReleased: renderer.wispReleased,
            fogCenter: center,
            fogRadiusPoints: CGFloat(fog.radiusMeters / metersPerPoint),
            viewSize: mapView.bounds.size
        )
        guard released != renderer.wispReleased,
              mapView.mapboxMap.layerExists(withId: SeekWispRendering.layerID) else { return }
        renderer.wispReleased = released
        renderer.wispFlareGeneration += 1
        if released {
            fireWispHandoffExhale(on: mapView, renderer: renderer)
        } else {
            writeWispOpacity(wispRestingOpacity(), on: mapView)
        }
    }

    /// The handoff: the fog just entered view, so the crescent gives one
    /// final full flare and dissolves into the thing it pointed at.
    private static func fireWispHandoffExhale(on mapView: MBMapView, renderer: SeekFogRenderer) {
        guard !UIAccessibility.isReduceMotionEnabled else {
            writeWispOpacity(0, on: mapView)
            return
        }
        let generation = renderer.wispFlareGeneration
        writeWispOpacity(SeekWispRendering.alignedFlarePeak, on: mapView)
        let dissolve = DispatchTime.now() + SeekWispRendering.flareHoldSeconds
        DispatchQueue.main.asyncAfter(deadline: dissolve) { [weak mapView, weak renderer] in
            guard let mapView, let renderer,
                  renderer.wispFlareGeneration == generation,
                  renderer.wispReleased,
                  mapView.mapboxMap.layerExists(withId: SeekWispRendering.layerID) else { return }
            writeWispOpacity(0, on: mapView)
        }
    }

    private static func wispRestingOpacity() -> Double {
        UIAccessibility.isReduceMotionEnabled
            ? SeekWispRendering.steadyOpacity
            : SeekWispRendering.restOpacity
    }

    private static func writeWispOpacity(_ value: Double, on mapView: MBMapView) {
        do {
            try mapView.mapboxMap.setLayerProperty(
                for: SeekWispRendering.layerID,
                property: "icon-opacity",
                value: value
            )
        } catch {
            print("[PilgrimMapView] seek wisp opacity write failed: \(error)")
        }
    }

    /// A soft arc of dawn drawn pointing north; `icon-rotate` aims it at
    /// the clearing. Two strokes — a wide faint glow under a narrow bright
    /// core — read as light, not as a marker.
    private static func wispCrescentImage() -> UIImage {
        let size = SeekWispRendering.imageSize
        let span = SeekWispRendering.arcSpanDegrees * .pi / 180
        let start = -CGFloat.pi / 2 - CGFloat(span / 2)
        let end = -CGFloat.pi / 2 + CGFloat(span / 2)
        let center = CGPoint(x: size / 2, y: size / 2)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let glow = UIBezierPath(
                arcCenter: center, radius: SeekWispRendering.arcRadius,
                startAngle: start, endAngle: end, clockwise: true
            )
            glow.lineWidth = 9
            glow.lineCapStyle = .round
            SeekFogRendering.haloColor.withAlphaComponent(0.35).setStroke()
            glow.stroke()

            let core = UIBezierPath(
                arcCenter: center, radius: SeekWispRendering.arcRadius,
                startAngle: start + 0.12, endAngle: end - 0.12, clockwise: true
            )
            core.lineWidth = 3.5
            core.lineCapStyle = .round
            SeekFogRendering.haloColor.setStroke()
            core.stroke()
            _ = context
        }
    }
}
