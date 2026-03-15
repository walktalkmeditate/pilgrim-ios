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
