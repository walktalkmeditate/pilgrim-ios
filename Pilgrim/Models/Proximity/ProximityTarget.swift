import CoreLocation

struct ProximityTarget: Hashable {

    let id: String
    let coordinate: CLLocationCoordinate2D
    let radius: CLLocationDistance
    let type: ProximityTargetType

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ProximityTarget, rhs: ProximityTarget) -> Bool {
        lhs.id == rhs.id
    }
}

enum ProximityTargetType: Hashable {
    case whisper
    case cairn
}
