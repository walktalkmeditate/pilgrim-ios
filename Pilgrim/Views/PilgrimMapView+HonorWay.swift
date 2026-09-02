import CoreLocation
import MapboxMaps
import UIKit

struct HonorWayState: Equatable {
    let id: String
    let routeCoordinates: [CLLocationCoordinate2D]

    /// `CLLocationCoordinate2D` isn't `Equatable`, so `routeCoordinates` can't
    /// be compared directly — nor does it need to be, since `id` already
    /// identifies a Way's geometry (fixed after acceptance). The count is a
    /// cheap extra guard, not a per-coordinate diff.
    static func == (lhs: HonorWayState, rhs: HonorWayState) -> Bool {
        lhs.id == rhs.id && lhs.routeCoordinates.count == rhs.routeCoordinates.count
    }
}

/// Coordinator-owned bookkeeping for the ghost line and companion.
final class HonorWayRenderer {
    var pendingWay: HonorWayState?
    var pendingCompanion: CLLocationCoordinate2D?
    var appliedWayID: String?
    var companionInstalled = false
    var lastCompanionUpdate: TimeInterval = 0

    func resetForStyleReload() {
        appliedWayID = nil
        companionInstalled = false
    }
}

extension PilgrimMapView {

    enum HonorWayRendering {
        static let sourceID = "honor-way-source"
        static let lineLayerID = "honor-way-line"
        static let companionSourceID = "honor-companion-source"
        static let companionLayerID = "honor-companion"
        static let lineColor = UIColor(hex: "#8A8175")
        static let lineOpacity = 0.35
        static let lineWidth = 4.0
        static let companionRadius = 6.0
        static let companionOpacity = 0.6
        static let companionUpdateInterval: TimeInterval = 2
    }

    static func wayPins(for way: Way, heardVoiceIDs: Set<String>) -> [PilgrimAnnotation] {
        let geometry = WayGeometry(route: way.route)
        return way.moments.map { moment in
            let coordinate = moment.at.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                ?? geometry.coordinate(atFrac: moment.frac)
            let kind: PilgrimAnnotation.Kind
            switch moment.kind {
            case .voice: kind = .wayVoice(id: moment.id, heard: heardVoiceIDs.contains(moment.id))
            case .photo: kind = .wayPhoto(id: moment.id)
            case .rest(let minutes): kind = .wayRest(id: moment.id, minutes: minutes)
            case .meditation(let minutes, _): kind = .waySit(id: moment.id, minutes: minutes)
            case .waypoint(let label, let icon): kind = .wayWaypoint(id: moment.id, label: label, icon: icon)
            }
            return PilgrimAnnotation(coordinate: coordinate, kind: kind)
        }
    }

    static func applyHonorWay(
        _ way: HonorWayState?,
        companion: CLLocationCoordinate2D?,
        on mapView: MBMapView,
        coordinator: Coordinator
    ) {
        let renderer = coordinator.honorWayRenderer
        renderer.pendingWay = way
        renderer.pendingCompanion = companion
        guard coordinator.shouldRender, mapView.mapboxMap.isStyleLoaded else { return }
        applyGhostLine(way, on: mapView, renderer: renderer)
        applyCompanion(companion, on: mapView, renderer: renderer)
    }

    /// Called from `onStyleLoaded` and the foreground flush: layers are gone, reinstall from pending state.
    static func reinstallHonorWay(on mapView: MBMapView, coordinator: Coordinator) {
        let renderer = coordinator.honorWayRenderer
        renderer.resetForStyleReload()
        applyHonorWay(renderer.pendingWay, companion: renderer.pendingCompanion, on: mapView, coordinator: coordinator)
    }

    private static func applyGhostLine(_ way: HonorWayState?, on mapView: MBMapView, renderer: HonorWayRenderer) {
        // Self-heal: a lock/unlock can strip runtime layers without a style event.
        if renderer.appliedWayID != nil, !mapView.mapboxMap.layerExists(withId: HonorWayRendering.lineLayerID) {
            renderer.appliedWayID = nil
        }
        guard let way else {
            // Nothing installed: non-honor maps (summary, journal, wander
            // walks) hit this branch on every updateUIView pass at up to
            // 20 Hz, so skip the remove call rather than issuing throwing
            // style calls for layers that were never added.
            guard renderer.appliedWayID != nil else { return }
            removeGhostLine(from: mapView)
            renderer.appliedWayID = nil
            return
        }
        guard renderer.appliedWayID != way.id else { return }
        removeGhostLine(from: mapView)
        do {
            var source = GeoJSONSource(id: HonorWayRendering.sourceID)
            source.data = .feature(Feature(geometry: .lineString(LineString(way.routeCoordinates))))
            try mapView.mapboxMap.addSource(source)
            var layer = LineLayer(id: HonorWayRendering.lineLayerID, source: HonorWayRendering.sourceID)
            layer.lineWidth = .constant(HonorWayRendering.lineWidth)
            layer.lineCap = .constant(.round)
            layer.lineJoin = .constant(.round)
            layer.lineOpacity = .constant(HonorWayRendering.lineOpacity)
            layer.lineColor = .constant(StyleColor(HonorWayRendering.lineColor))
            try mapView.mapboxMap.addLayer(layer, layerPosition: ghostLinePosition(on: mapView))
            renderer.appliedWayID = way.id
        } catch {
            print("[PilgrimMapView] honor way install failed: \(error)")
        }
    }

    /// Ghost line sits under the casing (and, transitively, the colored
    /// route line on top of it) so the walker's own live route stays the
    /// legible one — same fallback chain as seek fog's `fogLayerPosition`.
    /// Casing and route layer are always torn down and recreated together
    /// (see `PilgrimMapView+RouteSource.swift`), both landing with no
    /// explicit position — i.e. at the top of the stack — so the ghost line
    /// stays below both even after a walking-color change rebuilds them.
    private static func ghostLinePosition(on mapView: MBMapView) -> LayerPosition? {
        if mapView.mapboxMap.layerExists(withId: "pilgrim-route-casing") {
            return .below("pilgrim-route-casing")
        }
        if mapView.mapboxMap.layerExists(withId: "pilgrim-route-layer") {
            return .below("pilgrim-route-layer")
        }
        return nil
    }

    private static func applyCompanion(_ companion: CLLocationCoordinate2D?, on mapView: MBMapView, renderer: HonorWayRenderer) {
        guard let companion else {
            // Nothing installed: same non-honor-map reasoning as the ghost
            // line's nil branch above — skip the remove call entirely.
            guard renderer.companionInstalled else { return }
            removeCompanion(from: mapView)
            renderer.companionInstalled = false
            return
        }
        let feature = Feature(geometry: .point(Point(companion)))
        if renderer.companionInstalled, mapView.mapboxMap.layerExists(withId: HonorWayRendering.companionLayerID) {
            let now = CACurrentMediaTime()
            guard now - renderer.lastCompanionUpdate >= HonorWayRendering.companionUpdateInterval else { return }
            renderer.lastCompanionUpdate = now
            mapView.mapboxMap.updateGeoJSONSource(withId: HonorWayRendering.companionSourceID, geoJSON: .feature(feature))
            return
        }
        removeCompanion(from: mapView)
        do {
            var source = GeoJSONSource(id: HonorWayRendering.companionSourceID)
            source.data = .feature(feature)
            try mapView.mapboxMap.addSource(source)
            var layer = CircleLayer(id: HonorWayRendering.companionLayerID, source: HonorWayRendering.companionSourceID)
            layer.circleRadius = .constant(HonorWayRendering.companionRadius)
            layer.circleColor = .constant(StyleColor(HonorWayRendering.lineColor))
            layer.circleOpacity = .constant(HonorWayRendering.companionOpacity)
            layer.circleStrokeColor = .constant(StyleColor(.white))
            layer.circleStrokeWidth = .constant(1.5)
            layer.circlePitchAlignment = .constant(.map)
            let position: LayerPosition? = mapView.mapboxMap.layerExists(withId: "pilgrim-route-layer")
                ? .above("pilgrim-route-layer") : nil
            try mapView.mapboxMap.addLayer(layer, layerPosition: position)
            renderer.companionInstalled = true
            renderer.lastCompanionUpdate = CACurrentMediaTime()
        } catch {
            print("[PilgrimMapView] companion install failed: \(error)")
        }
    }

    private static func removeGhostLine(from mapView: MBMapView) {
        do {
            if mapView.mapboxMap.layerExists(withId: HonorWayRendering.lineLayerID) {
                try mapView.mapboxMap.removeLayer(withId: HonorWayRendering.lineLayerID)
            }
            if mapView.mapboxMap.sourceExists(withId: HonorWayRendering.sourceID) {
                try mapView.mapboxMap.removeSource(withId: HonorWayRendering.sourceID)
            }
        } catch {
            print("[PilgrimMapView] honor way removal failed: \(error)")
        }
    }

    private static func removeCompanion(from mapView: MBMapView) {
        do {
            if mapView.mapboxMap.layerExists(withId: HonorWayRendering.companionLayerID) {
                try mapView.mapboxMap.removeLayer(withId: HonorWayRendering.companionLayerID)
            }
            if mapView.mapboxMap.sourceExists(withId: HonorWayRendering.companionSourceID) {
                try mapView.mapboxMap.removeSource(withId: HonorWayRendering.companionSourceID)
            }
        } catch {
            print("[PilgrimMapView] companion removal failed: \(error)")
        }
    }

    /// Maps a way* annotation kind to its faded `PointAnnotation`. Lives here
    /// (not `buildPoints`'s switch in PilgrimMapView.swift) so adding a new
    /// Way moment kind doesn't grow that switch's cyclomatic complexity
    /// (task-12-resolutions.md #10).
    static func wayAnnotationPoint(for pin: PilgrimAnnotation, coordinator: Coordinator) -> PointAnnotation {
        switch pin.kind {
        case .wayVoice(_, let heard):
            return wayPoint(pin, symbol: "waveform", tint: heard ? .stone : .fog, coordinator: coordinator)
        case .wayPhoto:
            return wayPoint(pin, symbol: "photo", tint: .stone, coordinator: coordinator)
        case .wayRest:
            return wayPoint(pin, symbol: "cup.and.saucer", tint: .stone, coordinator: coordinator)
        case .waySit:
            return wayPoint(pin, symbol: "circle.circle", tint: .dawn, coordinator: coordinator)
        case .wayWaypoint(_, _, let icon):
            return wayPoint(pin, symbol: icon, tint: .stone, coordinator: coordinator)
        default:
            // Unreachable: buildPoints only routes way* kinds here. A plain
            // PointAnnotation at the pin's coordinate is a harmless fallback
            // if that ever changes, rather than a crash.
            return PointAnnotation(coordinate: pin.coordinate)
        }
    }

    /// Faded pin for a Way moment, sharing `buildPoints`' image-caching
    /// pattern.
    private static func wayPoint(_ pin: PilgrimAnnotation, symbol: String, tint: UIColor, coordinator: Coordinator) -> PointAnnotation {
        var point = PointAnnotation(coordinate: pin.coordinate)
        let glyph = MapGlyph.wayMark(symbol: symbol, tint: tint)
        if let image = MapGlyphImageBuilder.image(for: glyph, size: 22) {
            point.image = .init(image: image, name: MapGlyphImageBuilder.cacheKey(for: glyph))
        }
        point.iconSize = 1.0
        return point
    }
}
