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
        let queryDate = effectiveQueryDate(for: date)
        guard let astronomical = CelestialCalculator.seasonalMarker(for: queryDate),
              astronomical.isTurning else {
            return nil
        }
        let hemisphere = Hemisphere(coordinate: coordinate)
        return mapping(astronomical: astronomical, hemisphere: hemisphere)
    }

    /// Convenience for the common "today, at the user's stored hemisphere"
    /// case. Avoids duplicating the `UserPreferences.hemisphereOverride`
    /// boilerplate at each call site. In DEBUG with `testingDate` set,
    /// resolves to the stubbed turning (via `effectiveQueryDate`).
    static func turningForToday(hemisphere: Hemisphere = Hemisphere.current) -> SeasonalMarker? {
        turning(for: Date(), hemisphere: hemisphere)
    }

    #if DEBUG
    /// Override for ALL turning queries during simulator QA. Set via the
    /// `--turning-stub <winter-solstice|summer-solstice|spring-equinox|autumn-equinox>`
    /// launch arg parsed in `AppDelegate`. When set, every call to
    /// `turning(for:at:)` / `turning(for:hemisphere:)` / `turningForToday()`
    /// uses this date instead of the caller's date — making every walk
    /// (today's, historical, the one you're about to start) classify as
    /// the stubbed turning. Lets the full feature surface — banner, route
    /// color, watermark, ray, scroll markers, summary kanji, seal color,
    /// share payload — render at once for visual QA.
    nonisolated(unsafe) static var testingDate: Date?
    #endif

    /// Variant that takes a hemisphere directly — skips the synthetic-
    /// coordinate dance that `turning(for:at:)` does internally.
    static func turning(for date: Date, hemisphere: Hemisphere) -> SeasonalMarker? {
        let queryDate = effectiveQueryDate(for: date)
        guard let astronomical = CelestialCalculator.seasonalMarker(for: queryDate),
              astronomical.isTurning else {
            return nil
        }
        return mapping(astronomical: astronomical, hemisphere: hemisphere)
    }

    /// In DEBUG with `testingDate` set, queries for dates that fall on the
    /// real "today" are routed through the stubbed turning. Queries for
    /// historical dates (yesterday, last week, last year) are NOT affected
    /// — past walks keep their actual classification.
    ///
    /// This means: while the stub is on, the home banner shows the stubbed
    /// turning, and any walk you do today inherits the stubbed turning's
    /// treatment everywhere (route color, summary kanji, seal color, share
    /// payload). Walks from any other day classify normally.
    private static func effectiveQueryDate(for date: Date) -> Date {
        #if DEBUG
        guard let stub = testingDate, Calendar.current.isDateInToday(date) else {
            return date
        }
        return stub
        #else
        return date
        #endif
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
