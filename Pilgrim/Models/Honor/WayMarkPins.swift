import CoreLocation
import Foundation

/// Which service points a screen may carry, and what each one looks like.
/// Pure: the map and the walk both ask it, and a spec can too.
enum WayMarkPins {

    /// Below this a whole stage's services read as a rash rather than a map.
    static let drawFromZoom: CGFloat = 13
    /// Inside a town a stage can carry over a hundred at zoom 13.
    static let maxPerScreen = 40

    static func symbol(for kind: WayMarkKind) -> String {
        switch kind {
        case .water: return "drop.fill"
        case .food: return "fork.knife"
        case .bed: return "bed.double.fill"
        case .transport: return "bus.fill"
        case .supply: return "bag.fill"
        case .medical: return "cross.case.fill"
        }
    }

    /// The marks worth drawing right now: nothing when zoomed out, otherwise
    /// the nearest `maxPerScreen` to the walker. Without a fix the stage's
    /// own order stands in, so the overview still shows the first stretch.
    static func pins(marks: [WayMark], zoom: CGFloat, near: CLLocationCoordinate2D?) -> [PilgrimAnnotation] {
        guard zoom >= drawFromZoom, !marks.isEmpty else { return [] }
        let chosen: [WayMark]
        if let near {
            let here = CLLocation(latitude: near.latitude, longitude: near.longitude)
            // Spelled out in steps rather than one chain: the tuple element
            // makes a single expression too much for the type-checker's budget.
            let measured: [(mark: WayMark, meters: CLLocationDistance)] = marks.map { mark in
                (mark: mark, meters: here.distance(from: CLLocation(latitude: mark.at.lat, longitude: mark.at.lon)))
            }
            // A tiebreak on id keeps the selection stable between fixes.
            let nearest = measured.sorted { $0.meters == $1.meters ? $0.mark.id < $1.mark.id : $0.meters < $1.meters }
            chosen = nearest.prefix(maxPerScreen).map(\.mark)
        } else {
            chosen = Array(marks.prefix(maxPerScreen))
        }
        return chosen.map {
            PilgrimAnnotation(coordinate: CLLocationCoordinate2D(latitude: $0.at.lat, longitude: $0.at.lon),
                              kind: .wayMark(id: $0.id, kind: $0.kind))
        }
    }
}
