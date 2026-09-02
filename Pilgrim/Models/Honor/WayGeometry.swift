import CoreLocation
import Foundation

/// The only place Honor does geometry. Cumulative haversine distances over
/// the Way's route; every other consumer talks in fracs (0...1 of the
/// total length) or seconds since departure.
struct WayGeometry {

    let points: [WayPoint]
    /// cumulative[i] = meters from the first point to point i.
    let cumulative: [Double]
    let totalMeters: Double
    let totalSeconds: Double

    init(route: [WayPoint]) {
        points = route
        var running = 0.0
        var cum: [Double] = []
        cum.reserveCapacity(route.count)
        for (index, point) in route.enumerated() {
            if index > 0 {
                running += Self.distanceMeters(from: route[index - 1], to: point)
            }
            cum.append(running)
        }
        cumulative = cum
        totalMeters = running
        totalSeconds = route.last.map { $0.t - (route.first?.t ?? 0) } ?? 0
    }

    // MARK: - Frac ↔ coordinate ↔ time

    func coordinate(atFrac frac: Double) -> CLLocationCoordinate2D {
        guard let first = points.first else { return CLLocationCoordinate2D(latitude: 0, longitude: 0) }
        guard points.count > 1, totalMeters > 0 else {
            return CLLocationCoordinate2D(latitude: first.lat, longitude: first.lon)
        }
        let target = min(max(frac, 0), 1) * totalMeters
        let (i, u) = segment(atDistance: target)
        let a = points[i], b = points[i + 1]
        return CLLocationCoordinate2D(latitude: a.lat + (b.lat - a.lat) * u,
                                      longitude: a.lon + (b.lon - a.lon) * u)
    }

    func elapsed(atFrac frac: Double) -> Double {
        guard points.count > 1, totalMeters > 0 else { return 0 }
        let (i, u) = segment(atDistance: min(max(frac, 0), 1) * totalMeters)
        let a = points[i], b = points[i + 1]
        return (a.t + (b.t - a.t) * u) - points[0].t
    }

    func frac(atElapsed elapsed: Double) -> Double {
        guard points.count > 1, totalMeters > 0 else { return 1 }
        let t0 = points[0].t
        if elapsed <= 0 { return 0 }
        if elapsed >= totalSeconds { return 1 }
        for i in 0..<(points.count - 1) {
            let ta = points[i].t - t0, tb = points[i + 1].t - t0
            if elapsed >= ta && elapsed <= tb {
                let u = tb > ta ? (elapsed - ta) / (tb - ta) : 0
                let d = cumulative[i] + (cumulative[i + 1] - cumulative[i]) * u
                return d / totalMeters
            }
        }
        return 1
    }

    // MARK: - Nearest point

    /// Closest point on the polyline to `coordinate`, optionally restricted
    /// to segments whose frac span overlaps `window`. Returns the frac of
    /// the projection and the distance to it in meters.
    func nearest(
        to coordinate: CLLocationCoordinate2D,
        within window: ClosedRange<Double>?
    ) -> (frac: Double, meters: Double) {
        guard let first = points.first else { return (0, .infinity) }
        guard points.count > 1, totalMeters > 0 else {
            return (0, Self.distanceMeters(from: first, to: WayPoint(lat: coordinate.latitude, lon: coordinate.longitude, alt: nil, t: 0)))
        }
        var best: (frac: Double, meters: Double) = (0, .infinity)
        let cosLat = cos(coordinate.latitude * .pi / 180)
        for i in 0..<(points.count - 1) {
            let fa = cumulative[i] / totalMeters, fb = cumulative[i + 1] / totalMeters
            if let window, fb < window.lowerBound || fa > window.upperBound { continue }
            let a = points[i], b = points[i + 1]
            // Local equirectangular projection (meters) is accurate enough
            // for the tens-of-meters decisions the engine makes.
            let ax = (a.lon - coordinate.longitude) * cosLat, ay = a.lat - coordinate.latitude
            let bx = (b.lon - coordinate.longitude) * cosLat, by = b.lat - coordinate.latitude
            let dx = bx - ax, dy = by - ay
            let lengthSq = dx * dx + dy * dy
            let u = lengthSq > 0 ? min(max(-(ax * dx + ay * dy) / lengthSq, 0), 1) : 0
            let px = ax + dx * u, py = ay + dy * u
            let meters = sqrt(px * px + py * py) * 111_320
            if meters < best.meters {
                best = (fa + (fb - fa) * u, meters)
            }
        }
        return best
    }

    // MARK: - Helpers

    private func segment(atDistance d: Double) -> (index: Int, u: Double) {
        var lo = 0, hi = points.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if cumulative[mid] <= d { lo = mid } else { hi = mid }
        }
        let span = cumulative[hi] - cumulative[lo]
        let u = span > 0 ? (d - cumulative[lo]) / span : 0
        return (lo, min(max(u, 0), 1))
    }

    static func distanceMeters(from a: WayPoint, to b: WayPoint) -> Double {
        let r = 6_371_000.0
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLon = (b.lon - a.lon) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.lat * .pi / 180) * cos(b.lat * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(sqrt(h), sqrt(1 - h))
    }
}
