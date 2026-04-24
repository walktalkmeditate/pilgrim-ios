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

    /// Hemisphere stored in `UserPreferences.hemisphereOverride` (populated
    /// once by `HomeViewModel.updateHemisphereIfNeeded()` from the user's
    /// first walk's coordinate). Defaults to `.northern` when no preference
    /// is set yet (new user who has never walked).
    static var current: Hemisphere {
        let raw = UserPreferences.hemisphereOverride.value
        return raw.flatMap { Hemisphere(rawValue: $0) } ?? .northern
    }
}
