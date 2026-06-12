import UIKit
import MapboxMaps

// MARK: - Route Lines
//
// The walk route lives in a single GeoJSON source rendered by two line
// layers (casing + colored line). `RouteSourcePlanner` keeps per-sample
// updates bounded (AF9/AF46): the steady-state path rewrites only the small
// "tail" feature via partial source updates instead of re-serializing and
// re-uploading the entire route once per GPS fix.
extension PilgrimMapView {

    static let routeSourceId = "pilgrim-route"

    static func applyRouteSource(_ routeSegments: [RouteSegment], walkingColor: UIColor = .moss, on mapView: MBMapView, coordinator: Coordinator) {
        guard mapView.mapboxMap.isStyleLoaded else { return }

        // If walkingColor changed since the layer was last applied (e.g., a
        // walk crossed midnight into a turning day, or the user's hemisphere
        // preference flipped), tear down the existing layers + source so the
        // creation path below re-runs with the new color baked into the
        // match expression. Without this, the layer's lineColor would stay
        // frozen at whatever color was current when it was first created.
        if coordinator.lastAppliedWalkingColor != walkingColor {
            removeRouteLayersAndSource(from: mapView)
            coordinator.routePlanner.reset()
        }

        if !mapView.mapboxMap.sourceExists(withId: Self.routeSourceId) {
            coordinator.routePlanner.reset()
            let plan = coordinator.routePlanner.plan(for: routeSegments)
            var chunks: [RouteSourcePlanner.Chunk] = []
            if case .fullRebuild(let rebuilt) = plan { chunks = rebuilt }
            createRouteSourceAndLayers(
                features: chunks.map(feature(from:)),
                walkingColor: walkingColor,
                on: mapView,
                coordinator: coordinator
            )
            return
        }

        switch coordinator.routePlanner.plan(for: routeSegments) {
        case .noChange:
            return

        case .fullRebuild(let chunks):
            mapView.mapboxMap.updateGeoJSONSource(
                withId: Self.routeSourceId,
                geoJSON: .featureCollection(FeatureCollection(features: chunks.map(feature(from:))))
            )

        case .incremental(let addedChunks, let tailAction):
            if !addedChunks.isEmpty {
                mapView.mapboxMap.addGeoJSONSourceFeatures(
                    forSourceId: Self.routeSourceId,
                    features: addedChunks.map(feature(from:))
                )
            }
            switch tailAction {
            case .none:
                break
            case .set(let tail, let isNew):
                if isNew {
                    mapView.mapboxMap.addGeoJSONSourceFeatures(
                        forSourceId: Self.routeSourceId,
                        features: [feature(from: tail)]
                    )
                } else {
                    mapView.mapboxMap.updateGeoJSONSourceFeatures(
                        forSourceId: Self.routeSourceId,
                        features: [feature(from: tail)]
                    )
                }
            case .remove:
                mapView.mapboxMap.removeGeoJSONSourceFeatures(
                    forSourceId: Self.routeSourceId,
                    featureIds: [RouteSourcePlanner.tailFeatureID]
                )
            }
        }
    }

    /// Every feature carries a unique identifier — Mapbox's partial GeoJSON
    /// updates require it ("generated IDs" are incompatible with
    /// add/update/removeGeoJSONSourceFeatures).
    private static func feature(from chunk: RouteSourcePlanner.Chunk) -> Feature {
        var feature = Feature(geometry: .lineString(LineString(chunk.coordinates)))
        feature.identifier = .string(chunk.id)
        feature.properties = ["activityType": .string(chunk.activityType)]
        return feature
    }

    private static func removeRouteLayersAndSource(from mapView: MBMapView) {
        do {
            if mapView.mapboxMap.layerExists(withId: "pilgrim-route-layer") {
                try mapView.mapboxMap.removeLayer(withId: "pilgrim-route-layer")
            }
            if mapView.mapboxMap.layerExists(withId: "pilgrim-route-casing") {
                try mapView.mapboxMap.removeLayer(withId: "pilgrim-route-casing")
            }
            if mapView.mapboxMap.sourceExists(withId: Self.routeSourceId) {
                try mapView.mapboxMap.removeSource(withId: Self.routeSourceId)
            }
        } catch {
            print("[PilgrimMapView] Failed to remove route layer for color update: \(error)")
        }
    }

    private static func createRouteSourceAndLayers(
        features: [Feature],
        walkingColor: UIColor,
        on mapView: MBMapView,
        coordinator: Coordinator
    ) {
        do {
            var source = GeoJSONSource(id: Self.routeSourceId)
            source.data = .featureCollection(FeatureCollection(features: features))
            try mapView.mapboxMap.addSource(source)

            var casing = LineLayer(id: "pilgrim-route-casing", source: Self.routeSourceId)
            casing.lineWidth = .constant(10)
            casing.lineCap = .constant(.round)
            casing.lineJoin = .constant(.round)
            casing.lineOpacity = .constant(0.3)
            casing.lineColor = .constant(StyleColor(.white))
            try mapView.mapboxMap.addLayer(casing)

            var layer = LineLayer(id: "pilgrim-route-layer", source: Self.routeSourceId)
            layer.lineWidth = .constant(6)
            layer.lineCap = .constant(.round)
            layer.lineJoin = .constant(.round)
            layer.lineOpacity = .constant(1.0)
            layer.lineColor = .expression(
                Exp(.match) {
                    Exp(.get) { "activityType" }
                    "meditating"
                    UIColor.dawn
                    "talking"
                    UIColor.rust
                    walkingColor
                }
            )
            try mapView.mapboxMap.addLayer(layer)
            coordinator.lastAppliedWalkingColor = walkingColor

            // Recreate the annotation managers above the fresh route layer.
            if let old = coordinator.circleManager { mapView.annotations.removeAnnotationManager(withId: old.id) }
            if let old = coordinator.pointManager { mapView.annotations.removeAnnotationManager(withId: old.id) }
            coordinator.circleManager = nil
            coordinator.pointManager = nil
            coordinator.lastAppliedAnnotations = nil
        } catch {
            print("[PilgrimMapView] Failed to add route layer: \(error)")
        }
    }
}
