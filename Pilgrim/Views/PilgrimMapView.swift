import SwiftUI
import MapboxMaps
import CoreLocation
import Combine
typealias MBMapView = MapboxMaps.MapView

struct PilgrimMapView: UIViewRepresentable {

    private static let renderFPS: Int = 30

    var isInteractive: Bool = true
    var showsUserLocation: Bool = true
    var followsUserLocation: Bool = false
    var routeSegments: [RouteSegment] = []
    var pinAnnotations: [PilgrimAnnotation] = []
    var onAnnotationTap: ((PilgrimAnnotation) -> Void)?
    /// When non-nil, the photo pin matching this `localIdentifier` is rendered with a
    /// brighter highlighted halo. Used by the reliquary to keep the carousel and the map
    /// visually synchronized.
    var activePhotoID: String?
    @Binding var cameraCenter: CLLocationCoordinate2D?
    @Binding var cameraZoom: CGFloat
    @Binding var isMeditating: Bool
    var cameraBounds: MapCameraBounds?
    var cameraDuration: TimeInterval = 0.4
    /// Bottom padding (in points) reserved for an overlay sheet. The map
    /// shifts its content so the user puck / fit bounds appear above this
    /// region instead of being hidden under a bottom sheet.
    var bottomInset: CGFloat = 0
    /// Initial camera for the underlying `MapView` — applied once at
    /// construction via `MapInitOptions(cameraOptions:)` so the very first
    /// rendered frame lands near the user rather than at Mapbox's default
    /// world view. Ignored after creation; later camera moves go through
    /// `cameraCenter`/`cameraBounds`/follow-puck as usual.
    var initialCamera: MapCameraSeed.Seed?
    /// When `true`, the map starts invisible and fades in once the style
    /// has loaded. Intended for full-screen immersive maps (active walk)
    /// where the first-paint is visually jarring. Off by default so the
    /// walk summary and other embedded maps keep their existing reveal
    /// choreography.
    var fadesInOnStyleLoad: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    init(
        isInteractive: Bool = true,
        showsUserLocation: Bool = true,
        followsUserLocation: Bool = false,
        routeSegments: [RouteSegment] = [],
        pinAnnotations: [PilgrimAnnotation] = [],
        onAnnotationTap: ((PilgrimAnnotation) -> Void)? = nil,
        activePhotoID: String? = nil,
        cameraCenter: Binding<CLLocationCoordinate2D?> = .constant(nil),
        cameraZoom: Binding<CGFloat> = .constant(14),
        cameraBounds: MapCameraBounds? = nil,
        cameraDuration: TimeInterval = 0.4,
        bottomInset: CGFloat = 0,
        initialCamera: MapCameraSeed.Seed? = nil,
        fadesInOnStyleLoad: Bool = false,
        isMeditating: Binding<Bool> = .constant(false)
    ) {
        self.isInteractive = isInteractive
        self.showsUserLocation = showsUserLocation
        self.followsUserLocation = followsUserLocation
        self.routeSegments = routeSegments
        self.pinAnnotations = pinAnnotations
        self.onAnnotationTap = onAnnotationTap
        self.activePhotoID = activePhotoID
        self._cameraCenter = cameraCenter
        self._cameraZoom = cameraZoom
        self._isMeditating = isMeditating
        self.cameraBounds = cameraBounds
        self.cameraDuration = cameraDuration
        self.bottomInset = bottomInset
        self.initialCamera = initialCamera
        self.fadesInOnStyleLoad = fadesInOnStyleLoad
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MBMapView {
        let isDark = colorScheme == .dark
        let styleURI: StyleURI = isDark ? .dark : .light
        let cameraOptions: CameraOptions
        if let seed = initialCamera {
            cameraOptions = CameraOptions(center: seed.center, zoom: seed.zoom)
        } else {
            cameraOptions = CameraOptions()
        }
        let mapView = MBMapView(
            frame: .zero,
            mapInitOptions: MapInitOptions(cameraOptions: cameraOptions, styleURI: styleURI)
        )
        mapView.preferredFramesPerSecond = Self.renderFPS

        if fadesInOnStyleLoad {
            mapView.alpha = 0
            // Failsafe: if `onStyleLoaded` never fires (airplane mode on a
            // cold-cache device, style server 5xx, etc.) the user would be
            // stuck looking at parchment forever. Force the fade after 3s
            // regardless so a broken map at least becomes visible.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak mapView] in
                guard let mapView, mapView.alpha < 1 else { return }
                UIView.animate(withDuration: 0.3) { mapView.alpha = 1 }
            }
        }

        mapView.gestures.options.panEnabled = isInteractive
        mapView.gestures.options.pinchEnabled = isInteractive
        mapView.gestures.options.rotateEnabled = false
        mapView.gestures.options.pitchEnabled = false

        mapView.ornaments.options.scaleBar.visibility = .hidden
        mapView.ornaments.options.compass.visibility = .hidden
        mapView.ornaments.options.attributionButton.position = .bottomLeading

        configurePuck(on: mapView)

        context.coordinator.currentColorScheme = colorScheme

        let shouldFade = fadesInOnStyleLoad
        mapView.mapboxMap.onStyleLoaded.observeNext { [coordinator = context.coordinator] _ in
            let mode: PilgrimMapStyle.Mode = coordinator.currentColorScheme == .dark ? .dark : .light
            PilgrimMapStyle.applyWabiSabiStyle(to: mapView.mapboxMap, mode: mode)
            if shouldFade, mapView.alpha < 1 {
                UIView.animate(withDuration: 0.5, delay: 0, options: [.curveEaseOut]) {
                    mapView.alpha = 1
                }
            }
            coordinator.lastSegments = []
            if let old = coordinator.circleManager { mapView.annotations.removeAnnotationManager(withId: old.id) }
            if let old = coordinator.pointManager { mapView.annotations.removeAnnotationManager(withId: old.id) }
            coordinator.circleManager = nil
            coordinator.pointManager = nil
            Self.applyRouteSource(coordinator.pendingSegments, on: mapView, coordinator: coordinator)
            Self.applyAnnotations(coordinator.pendingAnnotations, activePhotoID: coordinator.pendingActivePhotoID, on: mapView, coordinator: coordinator)
        }.store(in: &context.coordinator.cancellables)

        context.coordinator.mapView = mapView
        context.coordinator.startObservingAppLifecycle()
        context.coordinator.isMeditating = isMeditating
        return mapView
    }

    func updateUIView(_ mapView: MBMapView, context: Context) {
        if context.coordinator.isMeditating != isMeditating {
            context.coordinator.isMeditating = isMeditating
        }
        context.coordinator.pendingSegments = routeSegments
        context.coordinator.pendingAnnotations = pinAnnotations
        context.coordinator.pendingActivePhotoID = activePhotoID
        context.coordinator.onAnnotationTap = onAnnotationTap
        context.coordinator.currentPinAnnotations = pinAnnotations

        if !context.coordinator.tapGestureAdded, onAnnotationTap != nil {
            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
            mapView.addGestureRecognizer(tap)
            context.coordinator.tapGestureAdded = true
        }

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
        Self.applyAnnotations(pinAnnotations, activePhotoID: activePhotoID, on: mapView, coordinator: context.coordinator)

        if followsUserLocation {
            let padding = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
            let insetChanged = abs(context.coordinator.lastBottomInset - bottomInset) > 0.5
            if !context.coordinator.isFollowing || insetChanged {
                context.coordinator.isFollowing = true
                context.coordinator.lastBottomInset = bottomInset
                mapView.viewport.transition(
                    to: mapView.viewport.makeFollowPuckViewportState(
                        options: FollowPuckViewportStateOptions(padding: padding, zoom: 16)
                    )
                )
            }
        } else {
            context.coordinator.isFollowing = false
            context.coordinator.lastBottomInset = bottomInset

            if let bounds = cameraBounds {
                let camera = mapView.mapboxMap.camera(
                    for: [bounds.sw, bounds.ne],
                    padding: UIEdgeInsets(top: 40, left: 30, bottom: 40 + bottomInset, right: 30),
                    bearing: nil,
                    pitch: nil
                )
                mapView.camera.ease(to: camera, duration: cameraDuration)
            } else if let center = cameraCenter {
                let camera: CameraOptions
                if bottomInset > 0 {
                    let padding = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
                    camera = CameraOptions(center: center, padding: padding, zoom: cameraZoom)
                } else {
                    camera = CameraOptions(center: center, zoom: cameraZoom)
                }
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

                if let old = coordinator.circleManager { mapView.annotations.removeAnnotationManager(withId: old.id) }
                if let old = coordinator.pointManager { mapView.annotations.removeAnnotationManager(withId: old.id) }
                coordinator.circleManager = nil
                coordinator.pointManager = nil
            } catch {
                print("[PilgrimMapView] Failed to add route layer: \(error)")
            }
        }
    }

    // MARK: - Annotations

    private static func applyAnnotations(_ pinAnnotations: [PilgrimAnnotation], activePhotoID: String?, on mapView: MBMapView, coordinator: Coordinator) {
        guard mapView.mapboxMap.isStyleLoaded else { return }

        // Install (or refresh) the "photo image loaded" callback on
        // the photo marker loader. Each async PHImageManager result
        // triggers a redraw so the placeholder is replaced by the
        // real photo thumbnail. Captured weakly to avoid a retain
        // cycle — the coordinator owns the loader (which owns the
        // closure), we just want the closure to bail if the map
        // view has been torn down.
        coordinator.photoMarkerLoader.onImageLoaded = { [weak mapView, weak coordinator] in
            guard let mapView = mapView, let coordinator = coordinator else { return }
            Self.applyAnnotations(
                coordinator.currentPinAnnotations,
                activePhotoID: coordinator.pendingActivePhotoID,
                on: mapView,
                coordinator: coordinator
            )
        }

        let routeLayerExists = mapView.mapboxMap.layerExists(withId: "pilgrim-route-layer")
        let layerPosition: LayerPosition? = routeLayerExists ? .above("pilgrim-route-layer") : nil

        if coordinator.circleManager == nil {
            if let pos = layerPosition {
                coordinator.circleManager = mapView.annotations.makeCircleAnnotationManager(layerPosition: pos)
            } else {
                coordinator.circleManager = mapView.annotations.makeCircleAnnotationManager()
            }
        }
        if let circleManager = coordinator.circleManager {
            circleManager.annotations = buildCircles(from: pinAnnotations, activePhotoID: activePhotoID)
        }

        if coordinator.pointManager == nil {
            if let pos = layerPosition {
                coordinator.pointManager = mapView.annotations.makePointAnnotationManager(layerPosition: pos)
            } else {
                coordinator.pointManager = mapView.annotations.makePointAnnotationManager()
            }
        }
        if let pointManager = coordinator.pointManager {
            pointManager.annotations = buildPoints(from: pinAnnotations, coordinator: coordinator)
            pointManager.iconAllowOverlap = true
        }
    }

    private static func buildCircles(from pinAnnotations: [PilgrimAnnotation], activePhotoID: String? = nil) -> [CircleAnnotation] {
        var circles: [CircleAnnotation] = []
        for pin in pinAnnotations {
            if let glow = glowCircle(for: pin, activePhotoID: activePhotoID) {
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
            case .photo:
                // Photo pins render as PointAnnotations with the
                // actual photo thumbnail (or a parchment-filled
                // placeholder while loading). The glow halo is still
                // drawn here via `glowCircle` above. No filled
                // CircleAnnotation in the middle — the thumbnail IS
                // the marker.
                continue
            case .waypoint, .whisper, .cairn:
                continue
            }
            circles.append(circle)
        }
        return circles
    }

    private static func glowCircle(for pin: PilgrimAnnotation, activePhotoID: String? = nil) -> CircleAnnotation? {
        switch pin.kind {
        case .endPoint:
            var glow = CircleAnnotation(centerCoordinate: pin.coordinate)
            glow.circleRadius = 18
            glow.circleColor = StyleColor(UIColor.stone)
            glow.circleOpacity = 0.15
            glow.circleStrokeWidth = 0
            return glow
        case .photo(let localIdentifier):
            let isActive = activePhotoID == localIdentifier
            var glow = CircleAnnotation(centerCoordinate: pin.coordinate)
            glow.circleRadius = isActive ? 28 : 22
            glow.circleColor = StyleColor(UIColor.stone)
            glow.circleOpacity = isActive ? 0.32 : 0.18
            glow.circleStrokeWidth = 0
            return glow
        default:
            return nil
        }
    }

    private static func buildPoints(
        from pinAnnotations: [PilgrimAnnotation],
        coordinator: Coordinator
    ) -> [PointAnnotation] {
        var points: [PointAnnotation] = []
        for pin in pinAnnotations {
            switch pin.kind {
            case .waypoint(_, let icon):
                var point = PointAnnotation(coordinate: pin.coordinate)
                if let image = renderSFSymbol(icon, size: 18, color: .stone) {
                    point.image = .init(image: image, name: icon)
                }
                point.iconSize = 1.0
                points.append(point)
            case .whisper(let categoryColor, _):
                var point = PointAnnotation(coordinate: pin.coordinate)
                let colorKey = String(format: "whisper-%02X%02X%02X",
                    Int((categoryColor.cgColor.components?[0] ?? 0) * 255),
                    Int((categoryColor.cgColor.components?[1] ?? 0) * 255),
                    Int((categoryColor.cgColor.components?[2] ?? 0) * 255))
                if let image = renderSFSymbol("wind", size: 14, color: categoryColor) {
                    point.image = .init(image: image, name: colorKey)
                }
                point.iconSize = 1.0
                points.append(point)
            case .cairn(_, let tier):
                var point = PointAnnotation(coordinate: pin.coordinate)
                let iconSize: CGFloat = 12 + CGFloat(tier.rawValue)
                if let image = renderSFSymbol("mountain.2", size: iconSize, color: .moss) {
                    point.image = .init(image: image, name: "cairn-\(tier.rawValue)")
                }
                point.iconSize = 1.0
                points.append(point)
            case .photo(let localIdentifier):
                // Try synchronous load first — works instantly for
                // local photos (~10-50ms). Falls back to async +
                // placeholder only for iCloud-only photos where a
                // network fetch would block the main thread.
                var point = PointAnnotation(coordinate: pin.coordinate)
                if let image = coordinator.photoMarkerLoader.image(for: localIdentifier)
                    ?? coordinator.photoMarkerLoader.loadImageSync(localIdentifier: localIdentifier) {
                    point.image = .init(image: image, name: "photo-\(localIdentifier)")
                } else {
                    // iCloud-only or deleted — async fallback with
                    // placeholder. When the download finishes,
                    // `onImageLoaded` fires and re-applies
                    // annotations so the placeholder swaps out.
                    coordinator.photoMarkerLoader.loadImage(localIdentifier: localIdentifier)
                    point.image = .init(image: Self.cachedPhotoPlaceholder(), name: "photo-placeholder")
                }
                point.iconSize = 1.0
                points.append(point)
            default:
                break
            }
        }
        return points
    }

    /// Lazy-initialised stone placeholder so we only build it once
    /// per process. Used while each real photo thumbnail is loading.
    /// Returns non-optional — `PhotoMarkerImageBuilder.placeholder()`
    /// is a pure Core Graphics helper that never fails.
    private static var _cachedPhotoPlaceholder: UIImage?
    private static func cachedPhotoPlaceholder() -> UIImage {
        if let cached = _cachedPhotoPlaceholder { return cached }
        let image = PhotoMarkerImageBuilder.placeholder()
        _cachedPhotoPlaceholder = image
        return image
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
        var lastBottomInset: CGFloat = 0
        var lastSegments: [RouteSegment] = []
        var pendingSegments: [RouteSegment] = []
        var pendingAnnotations: [PilgrimAnnotation] = []
        var pendingActivePhotoID: String?
        var currentColorScheme: ColorScheme = .light
        weak var mapView: MBMapView?
        var onAnnotationTap: ((PilgrimAnnotation) -> Void)?
        var currentPinAnnotations: [PilgrimAnnotation] = []
        var tapGestureAdded = false

        /// Loads circular photo-marker images for photo pin
        /// annotations. Encapsulated in its own class so the
        /// Coordinator stays under SwiftLint's type body length.
        /// `buildPoints` reads the cache synchronously; cache misses
        /// kick off an async load that invokes `onImageLoaded` once
        /// complete, which the Coordinator wires to trigger a redraw.
        let photoMarkerLoader = PhotoMarkerImageLoader()

        fileprivate var isAppInBackground: Bool = false

        fileprivate var isMeditating: Bool = false {
            didSet { refreshRenderState() }
        }

        fileprivate var shouldRender: Bool {
            !isAppInBackground && !isMeditating
        }

        func startObservingAppLifecycle() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleDidEnterBackground),
                name: UIApplication.didEnterBackgroundNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleWillEnterForeground),
                name: UIApplication.willEnterForegroundNotification,
                object: nil
            )
        }

        @objc private func handleDidEnterBackground() {
            isAppInBackground = true
            refreshRenderState()
        }

        @objc private func handleWillEnterForeground() {
            isAppInBackground = false
            refreshRenderState()
        }

        private func refreshRenderState() {
            guard let mapView else { return }
            mapView.preferredFramesPerSecond = shouldRender ? PilgrimMapView.renderFPS : 0
        }

        @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView, let onAnnotationTap else { return }
            let tapPoint = gesture.location(in: mapView)
            let tapCoord = mapView.mapboxMap.coordinate(for: tapPoint)
            let tapLoc = CLLocation(latitude: tapCoord.latitude, longitude: tapCoord.longitude)

            var closest: (annotation: PilgrimAnnotation, distance: CLLocationDistance)?
            for pin in currentPinAnnotations {
                switch pin.kind {
                case .whisper, .cairn, .photo:
                    let pinLoc = CLLocation(latitude: pin.coordinate.latitude, longitude: pin.coordinate.longitude)
                    let dist = tapLoc.distance(from: pinLoc)
                    if dist < 25, closest == nil || dist < closest!.distance {
                        closest = (pin, dist)
                    }
                default:
                    break
                }
            }

            if let match = closest {
                onAnnotationTap(match.annotation)
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
            if let mapView {
                if let manager = circleManager { mapView.annotations.removeAnnotationManager(withId: manager.id) }
                if let manager = pointManager { mapView.annotations.removeAnnotationManager(withId: manager.id) }
            }
        }
    }
}
