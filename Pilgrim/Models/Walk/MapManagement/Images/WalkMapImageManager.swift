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

                processQueue.async {
                    renderSnapshot(
                        coordinates: coordinates,
                        size: request.size.rawSize,
                        darkMode: imageUsesDarkMode,
                        completion: { image in
                            if let image, let id = request.cacheIdentifier(forDarkAppearance: imageUsesDarkMode) {
                                CustomImageCache.mapImageCache.set(mapImage: image, for: id)
                            }

                            DispatchQueue.main.async {
                                completion(image != nil, image)

                                if Config.isDarkModeEnabled != imageUsesDarkMode {
                                    self.requestQueue.add(request)
                                }
                            }
                        }
                    )
                }
            }
        )
    }

    private static func renderSnapshot(
        coordinates: [CLLocationCoordinate2D],
        size: CGSize,
        darkMode: Bool,
        completion: @escaping (UIImage?) -> Void
    ) {
        let lats = coordinates.map { $0.latitude }
        let lons = coordinates.map { $0.longitude }
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            completion(nil)
            return
        }

        let latPad = (maxLat - minLat) * 0.1
        let lonPad = (maxLon - minLon) * 0.1
        let sw = CLLocationCoordinate2D(latitude: minLat - latPad, longitude: minLon - lonPad)
        let ne = CLLocationCoordinate2D(latitude: maxLat + latPad, longitude: maxLon + lonPad)

        let options = MapSnapshotOptions(
            size: size,
            pixelRatio: UIScreen.main.scale
        )
        let snapshotter = Snapshotter(options: options)
        snapshotter.styleURI = .light

        snapshotter.setCamera(to: .init(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            padding: UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        ))

        snapshotter.onStyleLoaded.observeNext { _ in
            snapshotter.setMapStyleContent {
                GeoJSONSource(id: "route")
                    .data(.featureCollection(FeatureCollection(features: [
                        Feature(geometry: .lineString(LineString(coordinates)))
                    ])))

                LineLayer(id: "route-layer", source: "route")
                    .lineWidth(3)
                    .lineCap(.round)
                    .lineJoin(.round)
                    .lineColor(StyleColor(SeasonalColorEngine.seasonalColor(named: "stone", intensity: .full)))
            }

            let camera = snapshotter.camera(
                for: [sw, ne],
                padding: UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10),
                bearing: nil,
                pitch: nil
            )
            snapshotter.setCamera(to: camera)

            snapshotter.start(overlayHandler: nil) { result in
                switch result {
                case .success(let image):
                    completion(image)
                case .failure:
                    completion(nil)
                }
            }
        }.store(in: &snapshotCancellables)
    }

    private static var snapshotCancellables = Set<AnyCancelable>()

    private enum Status {
        case idle, running, suspended
    }
}
