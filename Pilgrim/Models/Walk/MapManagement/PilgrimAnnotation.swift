import CoreLocation
import UIKit

struct PilgrimAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let kind: Kind

    enum Kind: Equatable {
        case meditation(duration: TimeInterval)
        case voiceRecording(label: String)
        case waypoint(label: String, icon: String)
        /// A seek arrival on the summary map: a dawn halo in the hour's
        /// light it was found under (fixed hex — the record keeps the sky
        /// palette), not a pin. Live walks keep `.waypoint` — their halo
        /// comes from the fog layer.
        case seekArrival(label: String, lightHex: String)
        case startPoint
        case endPoint
        case whisper(categoryColor: UIColor, isNearby: Bool)
        case cairn(stoneCount: Int, tier: CairnTier)
        case photo(localIdentifier: String)
    }
}

/// Equality ignores `id` (a fresh UUID per instance) so that two annotation
/// lists computed from the same map content compare equal. This is what lets
/// `PilgrimMapView.applyAnnotations` skip the rebuild when nothing changed
/// (AF20) and the view model avoid republishing identical pin sets (AF43).
extension PilgrimAnnotation: Equatable {
    static func == (lhs: PilgrimAnnotation, rhs: PilgrimAnnotation) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.kind == rhs.kind
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
