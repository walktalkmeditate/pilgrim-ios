import CoreLocation

struct PilgrimAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let kind: Kind

    enum Kind {
        case meditation
        case voiceRecording(label: String)
    }
}

struct MapCameraBounds: Equatable {
    let sw: CLLocationCoordinate2D
    let ne: CLLocationCoordinate2D

    static func == (lhs: MapCameraBounds, rhs: MapCameraBounds) -> Bool {
        lhs.sw.latitude == rhs.sw.latitude
            && lhs.sw.longitude == rhs.sw.longitude
            && lhs.ne.latitude == rhs.ne.latitude
            && lhs.ne.longitude == rhs.ne.longitude
    }
}
