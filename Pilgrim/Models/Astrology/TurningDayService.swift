import Foundation
import CoreLocation

/// Hemisphere-aware turning-day detection.
///
/// `CelestialCalculator.seasonalMarker(sunLongitude:)` returns astronomical
/// markers always named by their northern-hemisphere meaning: a June
/// solstice always returns `.summerSolstice`. This service translates
/// that to the seasonally-correct marker for the observer's hemisphere.
///
/// Only the 4 main solstices/equinoxes are surfaced. Cross-quarter markers
/// (imbolc/beltane/lughnasadh/samhain) are filtered out.
enum TurningDayService {

    /// Returns the seasonally-correct turning for the given date and location.
    ///
    /// - Parameters:
    ///   - date: The date to check.
    ///   - coordinate: The observer's location. Used to determine hemisphere
    ///                 (positive latitude → northern; negative → southern;
    ///                 nil or zero → northern).
    /// - Returns: A `SeasonalMarker` of one of the 4 turnings, or nil if
    ///            the date is not a turning day (including cross-quarter
    ///            astronomical markers, which this feature doesn't surface).
    static func turning(for date: Date, at coordinate: CLLocationCoordinate2D?) -> SeasonalMarker? {
        let snapshot = CelestialCalculator.snapshot(for: date)
        guard let astronomical = snapshot.seasonalMarker, astronomical.isTurning else {
            return nil
        }
        let hemisphere = Hemisphere(coordinate: coordinate)
        return mapping(astronomical: astronomical, hemisphere: hemisphere)
    }

    private static func mapping(astronomical: SeasonalMarker, hemisphere: Hemisphere) -> SeasonalMarker {
        guard hemisphere == .southern else { return astronomical }
        switch astronomical {
        case .springEquinox:  return .autumnEquinox
        case .summerSolstice: return .winterSolstice
        case .autumnEquinox:  return .springEquinox
        case .winterSolstice: return .summerSolstice
        case .imbolc, .beltane, .lughnasadh, .samhain: return astronomical
        }
    }
}
