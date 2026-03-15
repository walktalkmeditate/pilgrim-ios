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
        let mapView = MBMapView(frame: .zero, mapInitOptions: MapInitOptions(styleURI: .light))
        mapView.preferredFramesPerSecond = 30

        mapView.gestures.options.panEnabled = isInteractive
        mapView.gestures.options.pinchEnabled = isInteractive
        mapView.gestures.options.rotateEnabled = false
        mapView.gestures.options.pitchEnabled = false

        if showsUserLocation {
            mapView.location.options.puckType = .puck2D(Puck2DConfiguration.makeDefault(showBearing: false))
        }

        mapView.mapboxMap.onStyleLoaded.observeNext { _ in
            PilgrimMapStyle.applyWabiSabiStyle(to: mapView.mapboxMap)
            self.updateRouteSource(on: mapView, coordinator: context.coordinator)
            self.updateAnnotations(on: mapView, coordinator: context.coordinator)
        }.store(in: &context.coordinator.cancellables)

        context.coordinator.mapView = mapView
        return mapView
    }

    func updateUIView(_ mapView: MBMapView, context: Context) {
        updateRouteSource(on: mapView, coordinator: context.coordinator)
        updateAnnotations(on: mapView, coordinator: context.coordinator)

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

    // MARK: - Route Lines

    private static let sourceId = "pilgrim-route"

    private func updateRouteSource(on mapView: MBMapView, coordinator: Coordinator) {
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

                var layer = LineLayer(id: "pilgrim-route-layer", source: Self.sourceId)
                layer.lineWidth = .constant(4)
                layer.lineCap = .constant(.round)
                layer.lineJoin = .constant(.round)
                layer.lineOpacity = .constant(0.9)
                layer.lineColor = .expression(
                    Exp(.match) {
                        Exp(.get) { "activityType" }
                        "meditating"
                        UIColor.dawn
                        "talking"
                        UIColor.moss
                        SeasonalColorEngine.seasonalColor(named: "stone", intensity: .full)
                    }
                )
                try mapView.mapboxMap.addLayer(layer)
            } catch {
                print("[PilgrimMapView] Failed to add route layer: \(error)")
            }
        }
    }

    // MARK: - Annotations

    private static let meditationImage: UIImage = {
        UIImage(systemName: "brain.head.profile")?
            .withTintColor(.dawn, renderingMode: .alwaysOriginal)
            ?? UIImage()
    }()

    private static let voiceImage: UIImage = {
        UIImage(systemName: "waveform")?
            .withTintColor(.moss, renderingMode: .alwaysOriginal)
            ?? UIImage()
    }()

    private func updateAnnotations(on mapView: MBMapView, coordinator: Coordinator) {
        guard mapView.mapboxMap.isStyleLoaded else { return }

        if coordinator.annotationManager == nil {
            coordinator.annotationManager = mapView.annotations.makePointAnnotationManager()
        }

        guard let manager = coordinator.annotationManager else { return }

        manager.annotations = pinAnnotations.map { pin in
            var annotation = PointAnnotation(coordinate: pin.coordinate)
            switch pin.kind {
            case .meditation:
                annotation.image = .init(image: Self.meditationImage, name: "meditation-pin")
            case .voiceRecording:
                annotation.image = .init(image: Self.voiceImage, name: "voice-pin")
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
        weak var mapView: MBMapView?

        deinit {
            if let manager = annotationManager, let mapView {
                mapView.annotations.removeAnnotationManager(withId: manager.id)
            }
        }
    }
}
