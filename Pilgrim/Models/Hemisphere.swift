import Foundation
import CoreLocation

enum Hemisphere: Int {
    case northern = 0
    case southern = 1

    init(coordinate: CLLocationCoordinate2D?) {
        guard let coord = coordinate else {
            self = .northern
            return
        }
        self = coord.latitude < 0 ? .southern : .northern
    }
}
