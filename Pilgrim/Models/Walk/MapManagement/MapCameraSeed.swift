import CoreLocation
import CoreStore

/// Best-available starting camera for a Mapbox walk map.
///
/// Without a seed, Mapbox initializes its camera at a default world view,
/// which reads as a jarring teleport when it then snaps to the user's
/// actual location one frame later. Seeding the initial `CameraOptions`
/// at construction time — rather than easing to it after creation — means
/// the first rendered frame already lands near the walker, so the user
/// never sees the flash.
enum MapCameraSeed {

    struct Seed {
        let center: CLLocationCoordinate2D
        let zoom: CGFloat
    }

    /// Preferred seed for the active walk screen. Order of preference:
    ///
    /// 1. Cached current location from CoreLocation (zoom 16, matches the
    ///    follow-puck zoom so the camera doesn't scale once the real fix
    ///    arrives).
    /// 2. Final coordinate of the most recent walk (zoom 14, wider view
    ///    because the user has almost certainly moved since then — a
    ///    wider frame absorbs the jump when the puck appears).
    /// 3. `nil` — first walk, no permission, simulator without a set
    ///    location. Mapbox falls back to its default camera.
    static func forActiveWalk() -> Seed? {
        if let current = cachedCurrentLocation() {
            return Seed(center: current, zoom: 16)
        }
        if let lastEnd = lastWalkEndCoordinate() {
            return Seed(center: lastEnd, zoom: 14)
        }
        return nil
    }

    private static func cachedCurrentLocation() -> CLLocationCoordinate2D? {
        let manager = CLLocationManager()
        let status = manager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            return nil
        }
        guard let location = manager.location else { return nil }
        guard location.horizontalAccuracy > 0,
              location.horizontalAccuracy < 200 else { return nil }
        guard abs(location.timestamp.timeIntervalSinceNow) < 24 * 60 * 60 else {
            return nil
        }
        return location.coordinate
    }

    private static func lastWalkEndCoordinate() -> CLLocationCoordinate2D? {
        do {
            let walk = try DataManager.dataStack.fetchOne(
                From<Walk>().orderBy(.descending(\._startDate))
            )
            guard let sample = walk?.routeData.last else { return nil }
            let coord = sample.clLocationCoordinate2D
            guard CLLocationCoordinate2DIsValid(coord),
                  abs(coord.latitude) > 0.0001 || abs(coord.longitude) > 0.0001 else {
                return nil
            }
            return coord
        } catch {
            return nil
        }
    }
}
