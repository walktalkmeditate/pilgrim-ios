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
        // Use the lightweight `seasonalMarker(for:)` rather than the full
        // `snapshot(for:)` — we only need the marker, not planetary positions.
        // Called per-snapshot in scroll loops and per-body-eval in views,
        // so the saving compounds.
        guard let astronomical = CelestialCalculator.seasonalMarker(for: date),
              astronomical.isTurning else {
            return nil
        }
        let hemisphere = Hemisphere(coordinate: coordinate)
        return mapping(astronomical: astronomical, hemisphere: hemisphere)
    }

    /// Convenience for the common "today, at the user's stored hemisphere"
    /// case. Avoids duplicating the `UserPreferences.hemisphereOverride`
    /// boilerplate at each call site.
    ///
    /// In DEBUG builds, honors `testingDate` if it has been set via the
    /// `--turning-stub <name>` launch arg (parsed in `AppDelegate`). Lets
    /// you visually QA the feature on simulator on any non-turning day.
    static func turningForToday(hemisphere: Hemisphere = Hemisphere.current) -> SeasonalMarker? {
        #if DEBUG
        return turning(for: testingDate ?? Date(), hemisphere: hemisphere)
        #else
        return turning(for: Date(), hemisphere: hemisphere)
        #endif
    }

    #if DEBUG
    /// Override for `turningForToday()` queries. Set via the
    /// `--turning-stub <winter-solstice|summer-solstice|spring-equinox|autumn-equinox>`
    /// launch arg parsed in `AppDelegate`. Affects only the "today" surfaces
    /// (home banner, active-walk watermark, route color, sunrise ray); past
    /// walks still use their actual `startDate`. To test historical surfaces,
    /// start a walk with the stub on, finish it (its `startDate` becomes the
    /// stubbed turning date), then relaunch without the stub.
    nonisolated(unsafe) static var testingDate: Date?
    #endif

    /// Variant that takes a hemisphere directly — skips the synthetic-
    /// coordinate dance that `turning(for:at:)` does internally.
    static func turning(for date: Date, hemisphere: Hemisphere) -> SeasonalMarker? {
        guard let astronomical = CelestialCalculator.seasonalMarker(for: date),
              astronomical.isTurning else {
            return nil
        }
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
