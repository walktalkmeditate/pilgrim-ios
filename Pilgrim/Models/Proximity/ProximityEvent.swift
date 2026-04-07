import CoreLocation

struct ProximityEvent {

    let target: ProximityTarget
    let distance: CLLocationDistance
    let direction: Direction

    enum Direction {
        case entered
        case exited
    }
}
