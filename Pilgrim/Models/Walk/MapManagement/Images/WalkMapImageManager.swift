import UIKit
import MapboxMaps
import CoreLocation

enum WalkMapImageManager {

    private static var internalStatus = Status.idle {
        didSet {
            if oldValue == .suspended {
                executeNextInQueue()
            }
        }
    }
    private static var requestQueue = WalkMapImageQueue()
    private static let processQueue = DispatchQueue(label: "processQueue", qos: .userInitiated)

    public static func execute(_ request: WalkMapImageRequest) {
        if let id = request.cacheIdentifier(), let image = CustomImageCache.mapImageCache.getMapImage(for: id) {
            request.completion(true, image)
            return
        }

        requestQueue.add(request)
        if internalStatus == .idle {
            executeNextInQueue()
        }
    }

    public static func suspendRenderProcess() {
        processQueue.suspend()
        internalStatus = .suspended
    }

    public static func resumeRenderProcess() {
        processQueue.resume()
        internalStatus = .idle
    }

    private static func executeNextInQueue() {
        if internalStatus == .suspended { return }

        guard let request = requestQueue.pendingRequests.first else {
            internalStatus = .idle
            return
        }

        internalStatus = .running

        let imageUsesDarkMode = Config.isDarkModeEnabled
        let completion: (Bool, UIImage?) -> Void = { (success, image) in
            requestQueue.remove(request)
            DispatchQueue.main.async {
                request.completion(success, image)
                executeNextInQueue()
            }
        }

        guard let uuid = request.walkUUID else {
            completion(false, nil)
            return
        }

        DataManager.asyncLocationCoordinatesQuery(
            for: Primitive<Walk>(uuid: uuid),
            completion: { error, coordinates in
                guard error == nil, coordinates.count > 1 else {
                    completion(false, nil)
                    return
                }

                let size = request.size.rawSize

                processQueue.async {
                    let lats = coordinates.map { $0.latitude }
                    let lons = coordinates.map { $0.longitude }
                    guard let minLat = lats.min(), let maxLat = lats.max(),
                          let minLon = lons.min(), let maxLon = lons.max() else {
                        completion(false, nil)
                        return
                    }

                    let latPad = (maxLat - minLat) * 0.1
                    let lonPad = (maxLon - minLon) * 0.1
                    let sw = CLLocationCoordinate2D(latitude: minLat - latPad, longitude: minLon - lonPad)
                    let ne = CLLocationCoordinate2D(latitude: maxLat + latPad, longitude: maxLon + lonPad)
                    let center = CLLocationCoordinate2D(
                        latitude: (minLat + maxLat) / 2,
                        longitude: (minLon + maxLon) / 2
                    )

                    DispatchQueue.main.async {
                        let scale = UIScreen.main.scale
                        renderSnapshot(
                            coordinates: coordinates,
                            center: center,
                            sw: sw,
                            ne: ne,
                            size: size,
                            screenScale: scale,
                            completion: { image in
                                if let image, let id = request.cacheIdentifier(forDarkAppearance: imageUsesDarkMode) {
                                    CustomImageCache.mapImageCache.set(mapImage: image, for: id)
                                }

                                completion(image != nil, image)

                                if Config.isDarkModeEnabled != imageUsesDarkMode {
                                    self.requestQueue.add(request)
                                }
                            }
                        )
                    }
                }
            }
        )
    }

    private static var activeSnapshot: SnapshotOperation?

    @MainActor
    private static func renderSnapshot(
        coordinates: [CLLocationCoordinate2D],
        center: CLLocationCoordinate2D,
        sw: CLLocationCoordinate2D,
        ne: CLLocationCoordinate2D,
        size: CGSize,
        screenScale: CGFloat,
        completion: @escaping (UIImage?) -> Void
    ) {
        activeSnapshot?.invalidate()

        let options = MapSnapshotOptions(size: size, pixelRatio: screenScale)
        let snapshotter = Snapshotter(options: options)
        snapshotter.styleURI = .light
        snapshotter.setCamera(to: .init(center: center))

        let operation = SnapshotOperation(snapshotter: snapshotter, completion: completion)
        activeSnapshot = operation

        operation.timeoutItem = DispatchWorkItem { [weak operation] in
            guard let operation, !operation.isComplete else { return }
            operation.complete(with: nil)
            activeSnapshot = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: operation.timeoutItem!)

        operation.cancellable = snapshotter.onStyleLoaded.observeNext { [weak operation] _ in
            guard let operation, !operation.isComplete else { return }

            do {
                var source = GeoJSONSource(id: "route")
                source.data = .featureCollection(FeatureCollection(features: [
                    Feature(geometry: .lineString(LineString(coordinates)))
                ]))
                try snapshotter.addSource(source)

                var layer = LineLayer(id: "route-layer", source: "route")
                layer.lineWidth = .constant(3)
                layer.lineCap = .constant(.round)
                layer.lineJoin = .constant(.round)
                layer.lineColor = .constant(StyleColor(
                    SeasonalColorEngine.seasonalColor(named: "stone", intensity: .full)
                ))
                try snapshotter.addLayer(layer)
            } catch {
                print("[WalkMapImageManager] Failed to add route layer: \(error)")
            }

            let camera = snapshotter.camera(
                for: [sw, ne],
                padding: UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10),
                bearing: nil,
                pitch: nil
            )
            snapshotter.setCamera(to: camera)

            snapshotter.start(overlayHandler: nil) { [weak operation] result in
                guard let operation, !operation.isComplete else { return }
                switch result {
                case .success(let image):
                    operation.complete(with: image)
                case .failure(let error):
                    print("[WalkMapImageManager] Snapshot failed: \(error)")
                    operation.complete(with: nil)
                }
                activeSnapshot = nil
            }
        }
    }

    private class SnapshotOperation {
        let snapshotter: Snapshotter
        private let onComplete: (UIImage?) -> Void
        var cancellable: AnyCancelable?
        var timeoutItem: DispatchWorkItem?
        private(set) var isComplete = false

        init(snapshotter: Snapshotter, completion: @escaping (UIImage?) -> Void) {
            self.snapshotter = snapshotter
            self.onComplete = completion
        }

        func complete(with image: UIImage?) {
            guard !isComplete else { return }
            isComplete = true
            timeoutItem?.cancel()
            cancellable?.cancel()
            onComplete(image)
        }

        func invalidate() {
            guard !isComplete else { return }
            isComplete = true
            timeoutItem?.cancel()
            cancellable?.cancel()
            onComplete(nil)
        }
    }

    private enum Status {
        case idle, running, suspended
    }
}
