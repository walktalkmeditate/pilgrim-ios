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
    @Environment(\.colorScheme) private var colorScheme

    init(
        isInteractive: Bool = true,
        showsUserLocation: Bool = true,
        followsUserLocation: Bool = false,
        routeSegments: [RouteSegment] = [],
        pinAnnotations: [PilgrimAnnotation] = [],
        cameraCenter: Binding<CLLocationCoordinate2D?> = .constant(nil),
        cameraZoom: Binding<CGFloat> = .constant(14),
        cameraBounds: MapCameraBounds? = nil
    ) {
        self.isInteractive = isInteractive
        self.showsUserLocation = showsUserLocation
        self.followsUserLocation = followsUserLocation
        self.routeSegments = routeSegments
        self.pinAnnotations = pinAnnotations
        self._cameraCenter = cameraCenter
        self._cameraZoom = cameraZoom
        self.cameraBounds = cameraBounds
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
                mapView.camera.ease(to: camera, duration: 0.4)
            } else if let center = cameraCenter {
                let camera = CameraOptions(center: center, zoom: cameraZoom)
                mapView.camera.ease(to: camera, duration: 0.4)
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

                let isDark = coordinator.currentColorScheme == .dark
                let walkColor = isDark
                    ? SeasonalColorEngine.seasonalColor(named: "parchment", intensity: .moderate)
                    : SeasonalColorEngine.seasonalColor(named: "stone", intensity: .full)

                var casing = LineLayer(id: "pilgrim-route-casing", source: Self.sourceId)
                casing.lineWidth = .constant(7)
                casing.lineCap = .constant(.round)
                casing.lineJoin = .constant(.round)
                casing.lineOpacity = .constant(isDark ? 0.4 : 0.2)
                casing.lineColor = .constant(StyleColor(isDark ? UIColor.white : UIColor.black))
                try mapView.mapboxMap.addLayer(casing)

                var layer = LineLayer(id: "pilgrim-route-layer", source: Self.sourceId)
                layer.lineWidth = .constant(4)
                layer.lineCap = .constant(.round)
                layer.lineJoin = .constant(.round)
                layer.lineOpacity = .constant(1.0)
                layer.lineColor = .expression(
                    Exp(.match) {
                        Exp(.get) { "activityType" }
                        "meditating"
                        UIColor.dawn
                        "talking"
                        UIColor.moss
                        walkColor
                    }
                )
                try mapView.mapboxMap.addLayer(layer)
            } catch {
                print("[PilgrimMapView] Failed to add route layer: \(error)")
            }
        }
    }

    // MARK: - Annotations

    private static let voiceImage: UIImage = {
        UIImage(systemName: "waveform")?
            .withTintColor(.moss, renderingMode: .alwaysOriginal)
            ?? UIImage()
    }()

    private static let startImage: UIImage = {
        renderCircle(size: 14, color: .moss, borderColor: .white, borderWidth: 2)
    }()

    private static let endImage: UIImage = {
        renderCircle(size: 14, color: .stone, borderColor: .white, borderWidth: 2)
    }()

    private static func meditationImage(duration: TimeInterval) -> UIImage {
        let minSize: CGFloat = 18
        let maxSize: CGFloat = 44
        let scale = CGFloat(min(duration / 600, 1.0))
        let size = minSize + (maxSize - minSize) * scale
        return renderCircle(size: size, color: .dawn.withAlphaComponent(0.7), borderColor: .dawn, borderWidth: 1.5)
    }

    private static func renderCircle(size: CGFloat, color: UIColor, borderColor: UIColor, borderWidth: CGFloat) -> UIImage {
        let totalSize = CGSize(width: size + borderWidth * 2, height: size + borderWidth * 2)
        let renderer = UIGraphicsImageRenderer(size: totalSize)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: totalSize)
            ctx.cgContext.setFillColor(borderColor.cgColor)
            ctx.cgContext.fillEllipse(in: rect)
            let inner = rect.insetBy(dx: borderWidth, dy: borderWidth)
            ctx.cgContext.setFillColor(color.cgColor)
            ctx.cgContext.fillEllipse(in: inner)
        }
    }

    private static func applyAnnotations(_ pinAnnotations: [PilgrimAnnotation], on mapView: MBMapView, coordinator: Coordinator) {
        guard mapView.mapboxMap.isStyleLoaded else { return }

        if coordinator.annotationManager == nil {
            coordinator.annotationManager = mapView.annotations.makePointAnnotationManager()
        }

        guard let manager = coordinator.annotationManager else { return }

        manager.annotations = pinAnnotations.map { pin in
            var annotation = PointAnnotation(coordinate: pin.coordinate)
            switch pin.kind {
            case .meditation(let duration):
                let img = Self.meditationImage(duration: duration)
                annotation.image = .init(image: img, name: "meditation-\(Int(duration))")
            case .voiceRecording:
                annotation.image = .init(image: Self.voiceImage, name: "voice-pin")
            case .startPoint:
                annotation.image = .init(image: Self.startImage, name: "start-pin")
            case .endPoint:
                annotation.image = .init(image: Self.endImage, name: "end-pin")
            }
            return annotation
        }
    }

    // MARK: - Coordinator

    class Coordinator {
        var cancellables = Set<AnyCancelable>()
        var annotationManager: PointAnnotationManager?
        var isFollowing = false
        var lastSegments: [RouteSegment] = []
        var pendingSegments: [RouteSegment] = []
        var pendingAnnotations: [PilgrimAnnotation] = []
        var currentColorScheme: ColorScheme = .light
        weak var mapView: MBMapView?

        deinit {
            if let manager = annotationManager, let mapView {
                mapView.annotations.removeAnnotationManager(withId: manager.id)
            }
        }
    }
}
