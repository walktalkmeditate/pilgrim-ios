import SwiftUI
import MapboxMaps
import CoreLocation
import Combine

typealias MBMapView = MapboxMaps.MapView

struct PilgrimMapView: UIViewRepresentable {

    var isInteractive: Bool = true
    var showsUserLocation: Bool = true
    var followsUserLocation: Bool = false
    var routeSegments: [RouteSegment] = []
    var pinAnnotations: [PilgrimAnnotation] = []
    @Binding var cameraCenter: CLLocationCoordinate2D?
    @Binding var cameraZoom: CGFloat
    var cameraBounds: MapCameraBounds?
    var cameraDuration: TimeInterval = 0.4
    @Environment(\.colorScheme) private var colorScheme

    init(
        isInteractive: Bool = true,
        showsUserLocation: Bool = true,
        followsUserLocation: Bool = false,
        routeSegments: [RouteSegment] = [],
        pinAnnotations: [PilgrimAnnotation] = [],
        cameraCenter: Binding<CLLocationCoordinate2D?> = .constant(nil),
        cameraZoom: Binding<CGFloat> = .constant(14),
        cameraBounds: MapCameraBounds? = nil,
        cameraDuration: TimeInterval = 0.4
    ) {
        self.isInteractive = isInteractive
        self.showsUserLocation = showsUserLocation
        self.followsUserLocation = followsUserLocation
        self.routeSegments = routeSegments
        self.pinAnnotations = pinAnnotations
        self._cameraCenter = cameraCenter
        self._cameraZoom = cameraZoom
        self.cameraBounds = cameraBounds
        self.cameraDuration = cameraDuration
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MBMapView {
        let isDark = colorScheme == .dark
        let styleURI: StyleURI = isDark ? .dark : .light
        let mapView = MBMapView(frame: .zero, mapInitOptions: MapInitOptions(styleURI: styleURI))
        mapView.preferredFramesPerSecond = 30

        mapView.gestures.options.panEnabled = isInteractive
        mapView.gestures.options.pinchEnabled = isInteractive
        mapView.gestures.options.rotateEnabled = false
        mapView.gestures.options.pitchEnabled = false

        mapView.ornaments.options.scaleBar.visibility = .hidden
        mapView.ornaments.options.compass.visibility = .hidden
        mapView.ornaments.options.attributionButton.position = .bottomLeading

        configurePuck(on: mapView)

        context.coordinator.currentColorScheme = colorScheme

        mapView.mapboxMap.onStyleLoaded.observeNext { [coordinator = context.coordinator] _ in
            let mode: PilgrimMapStyle.Mode = coordinator.currentColorScheme == .dark ? .dark : .light
            PilgrimMapStyle.applyWabiSabiStyle(to: mapView.mapboxMap, mode: mode)
            coordinator.lastSegments = []
            Self.applyRouteSource(coordinator.pendingSegments, on: mapView, coordinator: coordinator)
            Self.applyAnnotations(coordinator.pendingAnnotations, on: mapView, coordinator: coordinator)
        }.store(in: &context.coordinator.cancellables)

        context.coordinator.mapView = mapView
        return mapView
    }

    func updateUIView(_ mapView: MBMapView, context: Context) {
        context.coordinator.pendingSegments = routeSegments
        context.coordinator.pendingAnnotations = pinAnnotations

        mapView.gestures.options.panEnabled = isInteractive
        mapView.gestures.options.pinchEnabled = isInteractive

        if colorScheme != context.coordinator.currentColorScheme {
            context.coordinator.currentColorScheme = colorScheme
            context.coordinator.lastSegments = []
            let newStyle: StyleURI = colorScheme == .dark ? .dark : .light
            mapView.mapboxMap.loadStyle(newStyle)
            return
        }

        Self.applyRouteSource(routeSegments, on: mapView, coordinator: context.coordinator)
        Self.applyAnnotations(pinAnnotations, on: mapView, coordinator: context.coordinator)

        if followsUserLocation {
            if !context.coordinator.isFollowing {
                context.coordinator.isFollowing = true
                mapView.viewport.transition(
                    to: mapView.viewport.makeFollowPuckViewportState(
                        options: FollowPuckViewportStateOptions(zoom: 16)
                    )
                )
            }
        } else {
            context.coordinator.isFollowing = false

            if let bounds = cameraBounds {
                let camera = mapView.mapboxMap.camera(
                    for: [bounds.sw, bounds.ne],
                    padding: UIEdgeInsets(top: 40, left: 30, bottom: 40, right: 30),
                    bearing: nil,
                    pitch: nil
                )
                mapView.camera.ease(to: camera, duration: cameraDuration)
            } else if let center = cameraCenter {
                let camera = CameraOptions(center: center, zoom: cameraZoom)
                mapView.camera.ease(to: camera, duration: cameraDuration)
            }
        }
    }

    // MARK: - Puck

    private func configurePuck(on mapView: MBMapView) {
        guard showsUserLocation else { return }

        let stoneColor = SeasonalColorEngine.seasonalColor(named: "stone", intensity: .full)

        let puckSize = CGSize(width: 22.0, height: 22.0)
        let renderer = UIGraphicsImageRenderer(size: puckSize)
        let puckImage = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: puckSize)
            ctx.cgContext.setFillColor(stoneColor.cgColor)
            ctx.cgContext.fillEllipse(in: rect)
            let innerRect = rect.insetBy(dx: 4, dy: 4)
            ctx.cgContext.setFillColor(UIColor.white.withAlphaComponent(0.9).cgColor)
            ctx.cgContext.fillEllipse(in: innerRect)
        }

        var config = Puck2DConfiguration(topImage: puckImage, scale: .constant(1.0))
        config.showsAccuracyRing = false
        config.pulsing = .init(color: stoneColor.withAlphaComponent(0.3), radius: .constant(40))
        mapView.location.options.puckType = .puck2D(config)
    }

    // MARK: - Route Lines

    private static let sourceId = "pilgrim-route"

    private static func applyRouteSource(_ routeSegments: [RouteSegment], on mapView: MBMapView, coordinator: Coordinator) {
        guard mapView.mapboxMap.isStyleLoaded else { return }
        guard routeSegments != coordinator.lastSegments else { return }
        coordinator.lastSegments = routeSegments

        var features: [Feature] = []
        for segment in routeSegments where segment.coordinates.count > 1 {
            var feature = Feature(geometry: .lineString(LineString(segment.coordinates)))
            feature.properties = ["activityType": .string(segment.activityType)]
            features.append(feature)
        }

        let collection = FeatureCollection(features: features)

        if mapView.mapboxMap.sourceExists(withId: Self.sourceId) {
            do {
                try mapView.mapboxMap.updateGeoJSONSource(
                    withId: Self.sourceId,
                    geoJSON: .featureCollection(collection)
                )
            } catch {
                print("[PilgrimMapView] Failed to update route source: \(error)")
            }
        } else {
            do {
                var source = GeoJSONSource(id: Self.sourceId)
                source.data = .featureCollection(collection)
                try mapView.mapboxMap.addSource(source)

                var casing = LineLayer(id: "pilgrim-route-casing", source: Self.sourceId)
                casing.lineWidth = .constant(10)
                casing.lineCap = .constant(.round)
                casing.lineJoin = .constant(.round)
                casing.lineOpacity = .constant(0.3)
                casing.lineColor = .constant(StyleColor(.white))
                try mapView.mapboxMap.addLayer(casing)

                var layer = LineLayer(id: "pilgrim-route-layer", source: Self.sourceId)
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
                        UIColor.moss
                    }
                )
                try mapView.mapboxMap.addLayer(layer)
            } catch {
                print("[PilgrimMapView] Failed to add route layer: \(error)")
            }
        }
    }

    // MARK: - Annotations

    private static func applyAnnotations(_ pinAnnotations: [PilgrimAnnotation], on mapView: MBMapView, coordinator: Coordinator) {
        if coordinator.circleManager == nil {
            coordinator.circleManager = mapView.annotations.makeCircleAnnotationManager()
        }

        guard let circleManager = coordinator.circleManager else { return }

        var circles: [CircleAnnotation] = []

        for pin in pinAnnotations {
            if case .endPoint = pin.kind {
                var glow = CircleAnnotation(centerCoordinate: pin.coordinate)
                glow.circleRadius = 18
                glow.circleColor = StyleColor(UIColor.stone)
                glow.circleOpacity = 0.15
                glow.circleStrokeWidth = 0
                circles.append(glow)
            }

            var circle = CircleAnnotation(centerCoordinate: pin.coordinate)
            switch pin.kind {
            case .meditation(let duration):
                let minRadius: Double = 10
                let maxRadius: Double = 24
                let scale = min(duration / 600, 1.0)
                circle.circleRadius = minRadius + (maxRadius - minRadius) * scale
                circle.circleColor = StyleColor(UIColor.dawn)
                circle.circleOpacity = 0.7
                circle.circleStrokeColor = StyleColor(UIColor.dawn)
                circle.circleStrokeWidth = 2
                circle.circleStrokeOpacity = 1.0
            case .voiceRecording:
                circle.circleRadius = 8
                circle.circleColor = StyleColor(UIColor.rust)
                circle.circleOpacity = 0.8
                circle.circleStrokeColor = StyleColor(UIColor.rust)
                circle.circleStrokeWidth = 1.5
                circle.circleStrokeOpacity = 1.0
            case .waypoint:
                continue
            case .startPoint:
                circle.circleRadius = 6
                circle.circleColor = StyleColor(UIColor.parchment)
                circle.circleOpacity = 0.9
                circle.circleStrokeColor = StyleColor(UIColor.stone)
                circle.circleStrokeWidth = 2
                circle.circleStrokeOpacity = 1.0
            case .endPoint:
                circle.circleRadius = 7
                circle.circleColor = StyleColor(UIColor.ink)
                circle.circleOpacity = 0.9
                circle.circleStrokeColor = StyleColor(UIColor.stone)
                circle.circleStrokeWidth = 2
                circle.circleStrokeOpacity = 1.0
            case .whisper(let categoryColor, let isNearby):
                circle.circleRadius = isNearby ? 10 : 7
                circle.circleColor = StyleColor(categoryColor.withAlphaComponent(0.15))
                circle.circleOpacity = isNearby ? 0.9 : 0.6
                circle.circleStrokeColor = StyleColor(categoryColor)
                circle.circleStrokeWidth = 2
                circle.circleStrokeOpacity = 1.0
                if isNearby {
                    var pulse = CircleAnnotation(centerCoordinate: pin.coordinate)
                    pulse.circleRadius = 16
                    pulse.circleColor = StyleColor(categoryColor)
                    pulse.circleOpacity = 0.08
                    pulse.circleStrokeWidth = 0
                    circles.append(pulse)
                }
            case .cairn(_, let tier):
                circle.circleRadius = tier.circleRadius
                circle.circleColor = StyleColor(UIColor.stone)
                circle.circleOpacity = tier.opacity
                circle.circleStrokeColor = StyleColor(UIColor.stone)
                circle.circleStrokeWidth = tier.glows ? 3.0 : 1.5
                circle.circleStrokeOpacity = 1.0
                if tier.glows {
                    var glow = CircleAnnotation(centerCoordinate: pin.coordinate)
                    glow.circleRadius = tier.circleRadius + 8
                    glow.circleColor = StyleColor(UIColor.stone)
                    glow.circleOpacity = 0.12
                    glow.circleStrokeWidth = 0
                    circles.append(glow)
                }
            }
            circles.append(circle)
        }

        circleManager.annotations = circles

        if coordinator.pointManager == nil {
            coordinator.pointManager = mapView.annotations.makePointAnnotationManager()
        }

        guard let pointManager = coordinator.pointManager else { return }

        var points: [PointAnnotation] = []
        for pin in pinAnnotations {
            if case .waypoint(_, let icon) = pin.kind {
                var point = PointAnnotation(coordinate: pin.coordinate)
                if let image = Self.renderSFSymbol(icon, size: 18, color: .stone) {
                    point.image = .init(image: image, name: icon)
                }
                point.iconSize = 1.0
                points.append(point)
            }
        }
        pointManager.annotations = points
        pointManager.iconAllowOverlap = true
    }

    private static func renderSFSymbol(_ name: String, size: CGFloat, color: UIColor) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .medium)
        guard let symbol = UIImage(systemName: name, withConfiguration: config)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: symbol.size, format: format)
        return renderer.image { _ in symbol.draw(at: .zero) }
    }

    // MARK: - Coordinator

    class Coordinator {
        var cancellables = Set<AnyCancelable>()
        var circleManager: CircleAnnotationManager?
        var pointManager: PointAnnotationManager?
        var isFollowing = false
        var lastSegments: [RouteSegment] = []
        var pendingSegments: [RouteSegment] = []
        var pendingAnnotations: [PilgrimAnnotation] = []
        var currentColorScheme: ColorScheme = .light
        weak var mapView: MBMapView?

        deinit {
            if let mapView {
                if let manager = circleManager { mapView.annotations.removeAnnotationManager(withId: manager.id) }
                if let manager = pointManager { mapView.annotations.removeAnnotationManager(withId: manager.id) }
            }
        }
    }
}
