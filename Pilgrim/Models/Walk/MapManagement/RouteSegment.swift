import CoreLocation

struct RouteSegment: Equatable {
    let coordinates: [CLLocationCoordinate2D]
    let activityType: String

    static func == (lhs: RouteSegment, rhs: RouteSegment) -> Bool {
        lhs.activityType == rhs.activityType
            && lhs.coordinates.count == rhs.coordinates.count
            && lhs.coordinates.last?.latitude == rhs.coordinates.last?.latitude
            && lhs.coordinates.last?.longitude == rhs.coordinates.last?.longitude
    }
}
