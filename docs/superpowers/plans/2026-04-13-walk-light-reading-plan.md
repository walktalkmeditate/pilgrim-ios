# Walk Light Reading Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an astronomical "light reading" card to the post-walk share area that surfaces one true sentence about the sky at the moment of the walk, deterministically computed per-walk.

**Architecture:** Pure-function astronomy layer (extended `CelestialCalculator` + new `SolarHorizon`) feeds a priority-ladder `LightReadingGenerator` that picks a template from hand-written pools and fills in real values. Rare events (eclipses, supermoons, meteor showers) come from pre-generated static tables rather than runtime computation. Reveal state is persisted in a single UserDefaults key.

**Tech Stack:** Swift / SwiftUI / existing CelestialCalculator.swift / NaturalLanguage.framework (not needed for V1) / Python 3 + skyfield for the one-time event table generator.

**Spec reference:** `docs/superpowers/specs/2026-04-13-walk-light-reading-design.md`

---

### Task 1: Extend CelestialCalculator with lunar illumination and phase

**Files:**
- Modify: `Pilgrim/Models/Astrology/CelestialCalculator.swift`
- Test: `UnitTests/CelestialCalculatorIlluminationTests.swift` (new)

- [ ] **Step 1: Write the failing test**

Create `UnitTests/CelestialCalculatorIlluminationTests.swift`:
```swift
import XCTest
@testable import Pilgrim

final class CelestialCalculatorIlluminationTests: XCTestCase {

    func testLunarIlluminationKnownFullMoon() {
        // 2026-03-03 11:33 UTC is a known full moon (also total lunar eclipse).
        let date = iso("2026-03-03T11:33:00Z")
        let T = CelestialCalculator.julianCenturies(from: CelestialCalculator.julianDayNumber(from: date))
        let illum = CelestialCalculator.lunarIllumination(T: T)
        XCTAssertGreaterThan(illum, 0.98, "Full moon should be >98% illuminated")
    }

    func testLunarIlluminationKnownNewMoon() {
        // 2026-02-17 12:01 UTC is a known new moon.
        let date = iso("2026-02-17T12:01:00Z")
        let T = CelestialCalculator.julianCenturies(from: CelestialCalculator.julianDayNumber(from: date))
        let illum = CelestialCalculator.lunarIllumination(T: T)
        XCTAssertLessThan(illum, 0.02, "New moon should be <2% illuminated")
    }

    func testLunarIlluminationWrapAround() {
        // The B1 regression guard. Construct a synthetic case where moonLon
        // would compute as negative without the normalization, and assert
        // the result is still a valid "new moon" illumination (near 0).
        //
        // We can't easily construct the exact scenario via a real date,
        // so this test exercises the math by calling a version that takes
        // the longitudes directly.
        let illum = CelestialCalculator.lunarIlluminationFromLongitudes(
            sunLongitude: 355.0,
            moonLongitude: 5.0
        )
        // Expected phase angle = +10° (moon 10° past sun), illumination ≈ (1 - cos(10°))/2 ≈ 0.0076
        XCTAssertLessThan(illum, 0.02, "Moon 10° past sun should be <2% illuminated, not near full")
    }

    func testLunarPhaseNameFullMoon() {
        let date = iso("2026-03-03T11:33:00Z")
        let phase = CelestialCalculator.lunarPhaseName(for: date)
        XCTAssertEqual(phase, .full)
    }

    func testLunarPhaseNameNewMoon() {
        let date = iso("2026-02-17T12:01:00Z")
        let phase = CelestialCalculator.lunarPhaseName(for: date)
        XCTAssertEqual(phase, .new)
    }

    func testLunarPhaseNameWaxingGibbous() {
        // A date roughly 3 days before full moon
        let date = iso("2026-02-28T12:00:00Z")
        let phase = CelestialCalculator.lunarPhaseName(for: date)
        XCTAssertEqual(phase, .waxingGibbous)
    }

    // MARK: - Helpers

    private func iso(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)!
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/CelestialCalculatorIlluminationTests 2>&1 | tail -20
```

Expected: all 6 tests fail with "lunarIllumination / lunarIlluminationFromLongitudes / lunarPhaseName not defined".

- [ ] **Step 3: Add `lunarIllumination` to CelestialCalculator**

Edit `Pilgrim/Models/Astrology/CelestialCalculator.swift` — add after the existing `lunarLongitude(T:)` function (around line 92):

```swift
    // MARK: - Lunar Illumination

    /// Illumination fraction of the moon as visible from Earth, in [0, 1].
    /// 0 = new moon, 1 = full moon. Derived from the ecliptic-longitude
    /// elongation of the moon from the sun.
    static func lunarIllumination(T: Double) -> Double {
        let sunLon = solarLongitude(T: T)
        let moonLon = lunarLongitude(T: T)
        return lunarIlluminationFromLongitudes(sunLongitude: sunLon, moonLongitude: moonLon)
    }

    /// Testable version that takes longitudes directly so unit tests can
    /// exercise the wrap-around normalization without having to construct
    /// a real date that produces the exact longitudes.
    static func lunarIlluminationFromLongitudes(sunLongitude: Double, moonLongitude: Double) -> Double {
        // Normalize the elongation to [0, 360). Without this, a moon at
        // longitude 10° with sun at 350° would compute as -340° instead
        // of +20°, and cos() would flip the sign — reporting ~full moon
        // when the real answer is ~new moon.
        var diff = moonLongitude - sunLongitude
        if diff < 0 { diff += 360 }
        let phase = radians(diff)
        return (1 - cos(phase)) / 2
    }
```

- [ ] **Step 4: Add `LunarPhase` enum and `lunarPhaseName(for:)`**

Still in `CelestialCalculator.swift`, add below the illumination functions:

```swift
    // MARK: - Lunar Phase Classification

    enum LunarPhase: String {
        case new
        case waxingCrescent
        case firstQuarter
        case waxingGibbous
        case full
        case waningGibbous
        case lastQuarter
        case waningCrescent

        var displayName: String {
            switch self {
            case .new: return "new"
            case .waxingCrescent: return "waxing crescent"
            case .firstQuarter: return "first quarter"
            case .waxingGibbous: return "waxing gibbous"
            case .full: return "full"
            case .waningGibbous: return "waning gibbous"
            case .lastQuarter: return "last quarter"
            case .waningCrescent: return "waning crescent"
            }
        }
    }

    /// Classify the moon's current phase for a given UTC date.
    /// Uses the ecliptic-longitude elongation to determine both the
    /// illumination percentage and whether the moon is waxing or waning.
    static func lunarPhaseName(for date: Date) -> LunarPhase {
        let T = julianCenturies(from: julianDayNumber(from: date))
        let sunLon = solarLongitude(T: T)
        let moonLon = lunarLongitude(T: T)
        var elongation = moonLon - sunLon
        if elongation < 0 { elongation += 360 }
        // Elongation is now in [0, 360). Divide into 8 phase buckets of 45° each,
        // centered on new moon (0°), first quarter (90°), full (180°), last quarter (270°).
        switch elongation {
        case 0..<22.5, 337.5..<360: return .new
        case 22.5..<67.5: return .waxingCrescent
        case 67.5..<112.5: return .firstQuarter
        case 112.5..<157.5: return .waxingGibbous
        case 157.5..<202.5: return .full
        case 202.5..<247.5: return .waningGibbous
        case 247.5..<292.5: return .lastQuarter
        case 292.5..<337.5: return .waningCrescent
        default: return .new  // unreachable with normalized input
        }
    }
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/CelestialCalculatorIlluminationTests 2>&1 | tail -20
```

Expected: 6/6 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Pilgrim/Models/Astrology/CelestialCalculator.swift UnitTests/CelestialCalculatorIlluminationTests.swift
git commit -m "feat(celestial): add lunar illumination and phase name

Adds two pure-math helpers used by the upcoming light reading feature:
- lunarIllumination(T:) returns the moon's illuminated fraction [0, 1]
- lunarPhaseName(for:) classifies one of 8 standard phases

The illumination formula normalizes moonLon-sunLon to [0, 360) before
converting to radians, which fixes a subtle wrap-around bug that would
misreport a new moon as nearly full when the moon's ecliptic longitude
crosses 360°.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Create SolarHorizon.swift (sunrise/sunset/solar altitude)

**Files:**
- Create: `Pilgrim/Models/Astrology/SolarHorizon.swift`
- Test: `UnitTests/SolarHorizonTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `UnitTests/SolarHorizonTests.swift`:
```swift
import XCTest
@testable import Pilgrim

final class SolarHorizonTests: XCTestCase {

    // Paris: 48.8566°N, 2.3522°E
    // 2024-06-21 (summer solstice): sunrise ~05:47 local (03:47 UTC), sunset ~21:58 local (19:58 UTC)
    // Published values from timeanddate.com / USNO.

    func testSunriseParisJune21() {
        let horizon = SolarHorizon.compute(
            date: iso("2024-06-21T12:00:00Z"),
            latitude: 48.8566,
            longitude: 2.3522
        )
        guard let sunrise = horizon.sunrise else {
            XCTFail("Expected a sunrise time at Paris in June")
            return
        }
        let components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: sunrise)
        XCTAssertEqual(components.hour, 3)
        XCTAssertEqual(components.minute ?? 0, 47, accuracy: 2)  // ±2 min tolerance
    }

    func testSunsetParisJune21() {
        let horizon = SolarHorizon.compute(
            date: iso("2024-06-21T12:00:00Z"),
            latitude: 48.8566,
            longitude: 2.3522
        )
        guard let sunset = horizon.sunset else {
            XCTFail("Expected a sunset time at Paris in June")
            return
        }
        let components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: sunset)
        XCTAssertEqual(components.hour, 19)
        XCTAssertEqual(components.minute ?? 0, 58, accuracy: 2)
    }

    func testPolarDayReturnsNilSunset() {
        // 80°N in July has midnight sun — the sun never sets.
        let horizon = SolarHorizon.compute(
            date: iso("2024-07-01T12:00:00Z"),
            latitude: 80.0,
            longitude: 0.0
        )
        XCTAssertNil(horizon.sunset, "80°N in July should have no sunset (midnight sun)")
    }

    func testPolarNightReturnsNilSunrise() {
        // 80°N in December has polar night — the sun never rises.
        let horizon = SolarHorizon.compute(
            date: iso("2024-12-15T12:00:00Z"),
            latitude: 80.0,
            longitude: 0.0
        )
        XCTAssertNil(horizon.sunrise, "80°N in December should have no sunrise (polar night)")
    }

    func testSolarAltitudeAtNoonSummerSolstice() {
        // At 48.8566°N on 2024-06-21 at solar noon, sun altitude ≈ 64.6°
        // (90° - (48.8566° - 23.44°) = 64.58°)
        let altitude = SolarHorizon.solarAltitude(
            date: iso("2024-06-21T12:00:00Z"),  // ~1 PM Paris solar time — approximate
            latitude: 48.8566,
            longitude: 2.3522
        )
        XCTAssertEqual(altitude, 64.6, accuracy: 2.0)
    }

    func testSolarAltitudeAtMidnightIsNegative() {
        let altitude = SolarHorizon.solarAltitude(
            date: iso("2024-06-21T22:00:00Z"),  // late evening UTC, middle of night in Paris
            latitude: 48.8566,
            longitude: 2.3522
        )
        XCTAssertLessThan(altitude, 0, "Sun should be below horizon at Paris midnight")
    }

    // MARK: - Helpers

    private func iso(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/SolarHorizonTests 2>&1 | tail -20
```

Expected: all tests fail with "SolarHorizon not defined".

- [ ] **Step 3: Implement SolarHorizon.swift**

Create `Pilgrim/Models/Astrology/SolarHorizon.swift`:

```swift
import Foundation

/// Sunrise/sunset/solar altitude calculations for an observer at a
/// specific latitude and longitude on a specific date. Uses the NOAA
/// simplified solar position algorithm — accurate to ~1 minute for
/// sunrise/sunset times between 1950 and 2050.
///
/// Reference: https://gml.noaa.gov/grad/solcalc/calcdetails.html
enum SolarHorizon {

    struct HorizonTimes {
        let sunrise: Date?   // nil at polar night
        let sunset: Date?    // nil at midnight sun
        let solarNoon: Date
    }

    /// Compute sunrise, sunset, and solar noon for a date at an observer
    /// location. The input `date` only needs to identify the correct UTC
    /// day; the returned times are the actual instants of sunrise/sunset
    /// on that day.
    static func compute(date: Date, latitude: Double, longitude: Double) -> HorizonTimes {
        let julianDay = julianDayNumber(from: date)
        let T = julianCenturies(from: julianDay)

        let solarMeanAnomaly = normalize(357.52911 + 35999.05029 * T - 0.0001537 * T * T)
        let geomMeanLongitude = normalize(280.46646 + 36000.76983 * T + 0.0003032 * T * T)

        let eccentricity = 0.016708634 - 0.000042037 * T - 0.0000001267 * T * T

        let equationOfCenter =
            sin(radians(solarMeanAnomaly)) * (1.914602 - 0.004817 * T - 0.000014 * T * T)
            + sin(radians(2 * solarMeanAnomaly)) * (0.019993 - 0.000101 * T)
            + sin(radians(3 * solarMeanAnomaly)) * 0.000289

        let trueLongitude = geomMeanLongitude + equationOfCenter

        let apparentLongitude = trueLongitude - 0.00569 - 0.00478 * sin(radians(125.04 - 1934.136 * T))

        let meanObliquity = 23.0 + (26.0 + ((21.448 - T * (46.815 + T * (0.00059 - T * 0.001813)))) / 60.0) / 60.0
        let correctedObliquity = meanObliquity + 0.00256 * cos(radians(125.04 - 1934.136 * T))

        let declination = degrees(asin(sin(radians(correctedObliquity)) * sin(radians(apparentLongitude))))

        let varY = tan(radians(correctedObliquity / 2)) * tan(radians(correctedObliquity / 2))

        let equationOfTime = 4.0 * degrees(
            varY * sin(2 * radians(geomMeanLongitude))
            - 2 * eccentricity * sin(radians(solarMeanAnomaly))
            + 4 * eccentricity * varY * sin(radians(solarMeanAnomaly)) * cos(2 * radians(geomMeanLongitude))
            - 0.5 * varY * varY * sin(4 * radians(geomMeanLongitude))
            - 1.25 * eccentricity * eccentricity * sin(2 * radians(solarMeanAnomaly))
        )

        // Hour angle at sunrise (using -0.833° for atmospheric refraction + sun radius)
        let cosHourAngle = (cos(radians(90.833)) - sin(radians(latitude)) * sin(radians(declination)))
                         / (cos(radians(latitude)) * cos(radians(declination)))

        var sunriseMinutes: Double? = nil
        var sunsetMinutes: Double? = nil

        if cosHourAngle > -1 && cosHourAngle < 1 {
            let hourAngle = degrees(acos(cosHourAngle))  // degrees
            let solarNoonUTC = 720 - 4 * longitude - equationOfTime  // minutes past UTC midnight
            sunriseMinutes = solarNoonUTC - hourAngle * 4
            sunsetMinutes = solarNoonUTC + hourAngle * 4
        }
        // else: polar night (cosHourAngle > 1) or midnight sun (< -1)

        let solarNoonMinutes = 720 - 4 * longitude - equationOfTime
        let startOfDay = startOfUTCDay(for: date)

        return HorizonTimes(
            sunrise: sunriseMinutes.map { startOfDay.addingTimeInterval($0 * 60) },
            sunset: sunsetMinutes.map { startOfDay.addingTimeInterval($0 * 60) },
            solarNoon: startOfDay.addingTimeInterval(solarNoonMinutes * 60)
        )
    }

    /// Solar altitude above the horizon at a given instant and location, in degrees.
    /// Positive = above horizon, negative = below. -0.833° is sunrise/sunset,
    /// -6° is civil twilight edge, -12° nautical, -18° astronomical night.
    static func solarAltitude(date: Date, latitude: Double, longitude: Double) -> Double {
        let julianDay = julianDayNumber(from: date)
        let T = julianCenturies(from: julianDay)

        let solarMeanAnomaly = normalize(357.52911 + 35999.05029 * T - 0.0001537 * T * T)
        let geomMeanLongitude = normalize(280.46646 + 36000.76983 * T + 0.0003032 * T * T)
        let equationOfCenter =
            sin(radians(solarMeanAnomaly)) * (1.914602 - 0.004817 * T - 0.000014 * T * T)
            + sin(radians(2 * solarMeanAnomaly)) * (0.019993 - 0.000101 * T)
            + sin(radians(3 * solarMeanAnomaly)) * 0.000289

        let trueLongitude = geomMeanLongitude + equationOfCenter
        let apparentLongitude = trueLongitude - 0.00569 - 0.00478 * sin(radians(125.04 - 1934.136 * T))

        let meanObliquity = 23.0 + (26.0 + ((21.448 - T * (46.815 + T * (0.00059 - T * 0.001813)))) / 60.0) / 60.0
        let correctedObliquity = meanObliquity + 0.00256 * cos(radians(125.04 - 1934.136 * T))
        let declination = degrees(asin(sin(radians(correctedObliquity)) * sin(radians(apparentLongitude))))

        // Compute the local hour angle
        let components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
        let utcHours = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60.0 + Double(components.second ?? 0) / 3600.0
        let localSolarTime = utcHours + longitude / 15.0
        let hourAngle = 15.0 * (localSolarTime - 12.0)

        let altitude = degrees(asin(
            sin(radians(latitude)) * sin(radians(declination))
            + cos(radians(latitude)) * cos(radians(declination)) * cos(radians(hourAngle))
        ))
        return altitude
    }

    // MARK: - Internal helpers

    private static func julianDayNumber(from date: Date) -> Double {
        // Delegate to CelestialCalculator's existing implementation
        CelestialCalculator.julianDayNumber(from: date)
    }

    private static func julianCenturies(from jd: Double) -> Double {
        CelestialCalculator.julianCenturies(from: jd)
    }

    private static func startOfUTCDay(for date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.startOfDay(for: date)
    }

    private static func normalize(_ degrees: Double) -> Double {
        var result = degrees.truncatingRemainder(dividingBy: 360.0)
        if result < 0 { result += 360.0 }
        return result
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180.0
    }

    private static func degrees(_ radians: Double) -> Double {
        radians * 180.0 / .pi
    }
}
```

- [ ] **Step 4: Run tests and verify all pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/SolarHorizonTests 2>&1 | tail -20
```

Expected: 6/6 tests pass. If any values are off by more than the tolerance, cross-check the expected values against timeanddate.com or NOAA's solar calculator.

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Astrology/SolarHorizon.swift UnitTests/SolarHorizonTests.swift
git commit -m "feat(celestial): add SolarHorizon for sunrise/sunset/solar altitude

NOAA simplified solar position algorithm. Given a date and observer
lat/lon, computes sunrise/sunset times and solar altitude at an instant.
Accurate to ~1 minute for sunrise/sunset between 1950-2050.

Used by the upcoming light reading feature to classify walks into
twilight / golden hour / deep night / sunrise-sunset proximity tiers.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Write Python generator for astronomical event tables

**Files:**
- Create: `scripts/generate_astronomical_events.py`
- Create: `scripts/requirements-astronomical-events.txt`

- [ ] **Step 1: Install dependencies**

```bash
cd /Users/rubberduck/GitHub/momentmaker/pilgrim-ios
python3 -m pip install --user skyfield
```

- [ ] **Step 2: Create the generator script**

Create `scripts/generate_astronomical_events.py`:

```python
#!/usr/bin/env python3
"""
Generate Pilgrim/Models/Astrology/AstronomicalEvents.swift from Skyfield
ephemerides. Run once per release (or whenever the coverage window is
running out).

Outputs:
- Lunar eclipses 2026-2045 from NASA's de440 ephemeris
- Full-moon perigee events (supermoons) 2026-2045
- Major annual meteor showers (static list from IMO)

The output Swift file is committed to the repo. The script is not part
of the app build.
"""

from datetime import datetime, timedelta, timezone
from skyfield.api import load
from skyfield import almanac

START_YEAR = 2026
END_YEAR = 2045

SUPERMOON_PERIGEE_THRESHOLD_KM = 360_000  # commonly used definition
METEOR_SHOWERS = [
    ("Quadrantids", 1, 3, 120),
    ("Lyrids", 4, 22, 18),
    ("Eta Aquariids", 5, 6, 50),
    ("Perseids", 8, 12, 100),
    ("Orionids", 10, 21, 20),
    ("Leonids", 11, 17, 15),
    ("Geminids", 12, 14, 150),
    ("Ursids", 12, 22, 10),
]


def unix_time(dt):
    return int(dt.replace(tzinfo=timezone.utc).timestamp())


def find_lunar_eclipses(ts, eph, start, end):
    """Find all lunar eclipses in [start, end] using Skyfield almanac."""
    t0 = ts.utc(start.year, start.month, start.day)
    t1 = ts.utc(end.year, end.month, end.day)

    # Skyfield doesn't ship a built-in lunar eclipse finder, so we
    # detect by finding full moons where the moon is near the ecliptic
    # (latitude < ~0.9° from the Earth-Sun line, the penumbral limit).
    times, types = almanac.find_discrete(t0, t1, almanac.moon_phases(eph))
    full_moon_times = [t for t, typ in zip(times, types) if typ == 2]  # phase 2 = full

    eclipses = []
    earth = eph["earth"]
    moon = eph["moon"]
    sun = eph["sun"]

    for t in full_moon_times:
        # Compute the moon's ecliptic latitude at this moment.
        pos = earth.at(t).observe(moon).ecliptic_latlon()
        latitude_deg = pos[0].degrees
        if abs(latitude_deg) < 0.9:  # within penumbral zone
            # Classify: |lat| < 0.25° → total, < 0.55° → partial, < 0.9° → penumbral
            abs_lat = abs(latitude_deg)
            if abs_lat < 0.25:
                eclipse_type = "total"
                magnitude = 1.0 + (0.25 - abs_lat) * 2  # rough estimate
            elif abs_lat < 0.55:
                eclipse_type = "partial"
                magnitude = 0.5 + (0.55 - abs_lat) * 2
            else:
                eclipse_type = "penumbral"
                magnitude = 0.5
            eclipses.append((t.utc_datetime(), eclipse_type, round(magnitude, 2)))
    return eclipses


def find_supermoons(ts, eph, start, end):
    """Find all full moons where the moon's distance is less than
    SUPERMOON_PERIGEE_THRESHOLD_KM."""
    t0 = ts.utc(start.year, start.month, start.day)
    t1 = ts.utc(end.year, end.month, end.day)

    times, types = almanac.find_discrete(t0, t1, almanac.moon_phases(eph))
    full_moon_times = [t for t, typ in zip(times, types) if typ == 2]

    supermoons = []
    earth = eph["earth"]
    moon = eph["moon"]
    for t in full_moon_times:
        distance_km = (earth.at(t).observe(moon).distance().km)
        if distance_km < SUPERMOON_PERIGEE_THRESHOLD_KM:
            supermoons.append((t.utc_datetime(), int(distance_km)))
    return supermoons


def format_swift_file(eclipses, supermoons, showers):
    lines = [
        "import Foundation",
        "",
        "// AUTO-GENERATED by scripts/generate_astronomical_events.py.",
        "// Do not edit by hand. Re-run the generator to update.",
        f"// Coverage: {START_YEAR}-{END_YEAR}",
        "",
        "enum AstronomicalEvents {",
        "",
        "    static let lunarEclipses: [LunarEclipseEvent] = [",
    ]
    for dt, etype, mag in eclipses:
        ut = unix_time(dt)
        iso = dt.strftime("%Y-%m-%dT%H:%M:%SZ")
        lines.append(f"        LunarEclipseEvent(unixTime: {ut}, type: .{etype}, magnitude: {mag}),  // {iso}")
    lines.append("    ]")
    lines.append("")
    lines.append("    static let supermoons: [SupermoonEvent] = [")
    for dt, dist in supermoons:
        ut = unix_time(dt)
        iso = dt.strftime("%Y-%m-%dT%H:%M:%SZ")
        lines.append(f"        SupermoonEvent(unixTime: {ut}, distanceKm: {dist}),  // {iso}")
    lines.append("    ]")
    lines.append("")
    lines.append("    static let meteorShowers: [MeteorShowerEvent] = [")
    for name, month, day, zhr in showers:
        lines.append(f'        MeteorShowerEvent(name: "{name}", peakMonth: {month}, peakDay: {day}, zhr: {zhr}),')
    lines.append("    ]")
    lines.append("")
    lines.append("""    struct LunarEclipseEvent {
        let unixTime: Int64
        let type: EclipseType
        let magnitude: Double
        var date: Date { Date(timeIntervalSince1970: TimeInterval(unixTime)) }
    }

    struct SupermoonEvent {
        let unixTime: Int64
        let distanceKm: Int
        var date: Date { Date(timeIntervalSince1970: TimeInterval(unixTime)) }
    }

    struct MeteorShowerEvent {
        let name: String
        let peakMonth: Int
        let peakDay: Int
        let zhr: Int
    }

    enum EclipseType { case penumbral, partial, total }
}""")
    return "\n".join(lines)


def main():
    print("Loading Skyfield ephemeris (may download ~18 MB on first run)...")
    ts = load.timescale()
    eph = load("de440.bsp")

    start = datetime(START_YEAR, 1, 1)
    end = datetime(END_YEAR, 12, 31)

    print(f"Computing lunar eclipses {START_YEAR}-{END_YEAR}...")
    eclipses = find_lunar_eclipses(ts, eph, start, end)
    print(f"  found {len(eclipses)} eclipses")

    print(f"Computing supermoons {START_YEAR}-{END_YEAR}...")
    supermoons = find_supermoons(ts, eph, start, end)
    print(f"  found {len(supermoons)} supermoons")

    print("Writing AstronomicalEvents.swift...")
    content = format_swift_file(eclipses, supermoons, METEOR_SHOWERS)
    output_path = "Pilgrim/Models/Astrology/AstronomicalEvents.swift"
    with open(output_path, "w") as f:
        f.write(content + "\n")
    print(f"  wrote {output_path}")
    print("Done. Review the generated file, add it to Xcode, and commit.")


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Run the generator**

```bash
cd /Users/rubberduck/GitHub/momentmaker/pilgrim-ios
python3 scripts/generate_astronomical_events.py
```

Expected output: a new `Pilgrim/Models/Astrology/AstronomicalEvents.swift` file with ~30 eclipse entries, ~80 supermoon entries, and 8 meteor shower entries.

- [ ] **Step 4: Review the output**

Open `Pilgrim/Models/Astrology/AstronomicalEvents.swift` and sanity-check a few known dates:
- 2025-03-14 total lunar eclipse (should be present — if running for 2026+, may not be in range)
- 2026-03-03 total lunar eclipse (should be present)
- 2026-11-05 supermoon (should be present)

Spot-check 2-3 entries against external sources like timeanddate.com/astronomy/eclipses.html.

- [ ] **Step 5: Add the file to the Xcode project**

Open `Pilgrim.xcworkspace`, drag `AstronomicalEvents.swift` into the `Pilgrim/Models/Astrology/` group, ensure it's added to the Pilgrim target.

- [ ] **Step 6: Build to verify it compiles**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add scripts/generate_astronomical_events.py Pilgrim/Models/Astrology/AstronomicalEvents.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(celestial): add astronomical event tables for 2026-2045

- scripts/generate_astronomical_events.py generates the Swift data file
  from Skyfield's DE440 ephemeris. Run once per year or whenever the
  coverage window runs short.
- Pilgrim/Models/Astrology/AstronomicalEvents.swift is the generated
  file: ~30 lunar eclipses, ~80 supermoons, 8 major meteor showers.

Used by the upcoming light reading feature's rare-event tiers. Lookup
is a linear scan over ~100 entries — faster than any runtime ephemeris
calculation.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Create AstronomicalEvents lookup helpers and tests

**Files:**
- Modify: `Pilgrim/Models/Astrology/AstronomicalEvents.swift` (add extension with lookup methods)
- Test: `UnitTests/AstronomicalEventsTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `UnitTests/AstronomicalEventsTests.swift`:
```swift
import XCTest
@testable import Pilgrim

final class AstronomicalEventsTests: XCTestCase {

    // MARK: - Data integrity

    func testMeteorShowersHave8Entries() {
        XCTAssertEqual(AstronomicalEvents.meteorShowers.count, 8)
    }

    func testEventTablesCoverAtLeastDecade() {
        let firstEclipseYear = AstronomicalEvents.lunarEclipses.first?.date
            .map { Calendar(identifier: .gregorian).component(.year, from: $0) }
        XCTAssertNotNil(firstEclipseYear)
        XCTAssertLessThanOrEqual(firstEclipseYear ?? 9999, 2026)
    }

    func testEclipsesChronologicallyOrdered() {
        let times = AstronomicalEvents.lunarEclipses.map(\.unixTime)
        XCTAssertEqual(times, times.sorted(), "Eclipses must be sorted by unixTime")
    }

    func testSupermoonsChronologicallyOrdered() {
        let times = AstronomicalEvents.supermoons.map(\.unixTime)
        XCTAssertEqual(times, times.sorted(), "Supermoons must be sorted by unixTime")
    }

    func testNoDuplicateEclipses() {
        let times = AstronomicalEvents.lunarEclipses.map(\.unixTime)
        XCTAssertEqual(Set(times).count, times.count, "No duplicate eclipse times")
    }

    // MARK: - Lookup helpers

    func testLunarEclipseLookupKnownDate() {
        // 2026-03-03 total lunar eclipse (≈11:33 UTC)
        let walkDate = iso("2026-03-03T11:30:00Z")
        let eclipse = AstronomicalEvents.eclipse(on: walkDate)
        XCTAssertNotNil(eclipse)
        XCTAssertEqual(eclipse?.type, .total)
    }

    func testLunarEclipseLookupOrdinaryDate() {
        let walkDate = iso("2026-04-15T12:00:00Z")
        XCTAssertNil(AstronomicalEvents.eclipse(on: walkDate))
    }

    func testSupermoonLookupWithin3DayWindow() {
        // Any known supermoon date in 2026 — check 2 days before still matches
        guard let firstSupermoon = AstronomicalEvents.supermoons.first else {
            XCTFail("No supermoons in table")
            return
        }
        let twoDaysBefore = firstSupermoon.date.addingTimeInterval(-2 * 86400)
        XCTAssertNotNil(AstronomicalEvents.supermoon(near: twoDaysBefore))
    }

    func testSupermoonLookupOutsideWindow() {
        guard let firstSupermoon = AstronomicalEvents.supermoons.first else {
            XCTFail("No supermoons in table")
            return
        }
        let fourDaysBefore = firstSupermoon.date.addingTimeInterval(-4 * 86400)
        XCTAssertNil(AstronomicalEvents.supermoon(near: fourDaysBefore))
    }

    func testMeteorShowerLookupOnPeakDay() {
        // August 12 is the Perseids peak day
        let perseidsPeak = dateWithComponents(year: 2026, month: 8, day: 12)
        let shower = AstronomicalEvents.meteorShower(on: perseidsPeak)
        XCTAssertNotNil(shower)
        XCTAssertEqual(shower?.name, "Perseids")
    }

    func testMeteorShowerLookupOneDayOffPeak() {
        // ±1 day window — August 13 should still match Perseids
        let dayAfter = dateWithComponents(year: 2026, month: 8, day: 13)
        let shower = AstronomicalEvents.meteorShower(on: dayAfter)
        XCTAssertNotNil(shower)
        XCTAssertEqual(shower?.name, "Perseids")
    }

    func testMeteorShowerLookupTwoDaysOffPeak() {
        // August 14 is outside the ±1 day window
        let twoDaysAfter = dateWithComponents(year: 2026, month: 8, day: 14)
        XCTAssertNil(AstronomicalEvents.meteorShower(on: twoDaysAfter))
    }

    // MARK: - Helpers

    private func iso(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    private func dateWithComponents(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: data-integrity tests pass (the data file already exists from Task 3), but lookup-helper tests fail with "eclipse(on:) / supermoon(near:) / meteorShower(on:) not defined".

- [ ] **Step 3: Add lookup helpers**

Append to `Pilgrim/Models/Astrology/AstronomicalEvents.swift` (before the closing brace):

```swift
    // MARK: - Lookup helpers

    /// Find a lunar eclipse whose date matches the given walk date within
    /// ±12 hours. Uses the walker's local date for the comparison.
    static func eclipse(on walkDate: Date, calendar: Calendar = .current) -> LunarEclipseEvent? {
        let walkLocalDay = calendar.startOfDay(for: walkDate)
        return lunarEclipses.first { event in
            let eventLocalDay = calendar.startOfDay(for: event.date)
            return eventLocalDay == walkLocalDay
        }
    }

    /// Find a supermoon within ±3 days of the walk date, comparing against
    /// the walker's local date.
    static func supermoon(near walkDate: Date, calendar: Calendar = .current) -> SupermoonEvent? {
        let walkLocalDay = calendar.startOfDay(for: walkDate)
        return supermoons.first { event in
            let eventLocalDay = calendar.startOfDay(for: event.date)
            let daysBetween = abs(calendar.dateComponents([.day], from: eventLocalDay, to: walkLocalDay).day ?? 999)
            return daysBetween <= 3
        }
    }

    /// Find a major meteor shower whose peak is within ±1 day of the walk
    /// date (in the walker's local date).
    static func meteorShower(on walkDate: Date, calendar: Calendar = .current) -> MeteorShowerEvent? {
        let components = calendar.dateComponents([.month, .day], from: walkDate)
        guard let month = components.month, let day = components.day else { return nil }
        return meteorShowers.first { shower in
            // Match ±1 day in (month, day) space, handling month boundaries naively
            // (peak days near month ends might technically need to roll over, but
            // none of our 8 showers peak within 1 day of a month boundary except
            // Ursids on Dec 22 which is safely mid-month).
            if month == shower.peakMonth && abs(day - shower.peakDay) <= 1 {
                return true
            }
            return false
        }
    }
```

- [ ] **Step 4: Run tests to verify all pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/AstronomicalEventsTests 2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Astrology/AstronomicalEvents.swift UnitTests/AstronomicalEventsTests.swift
git commit -m "feat(celestial): add lookup helpers for astronomical events

Three matching functions with local-date semantics:
- eclipse(on:) exact-day match
- supermoon(near:) ±3 day window
- meteorShower(on:) ±1 day window

Uses Calendar.current by default (configurable for tests) so time-zone
shifts in the walker's location work correctly without a data-model
change to walks.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Create LightReading struct, Tier enum, and stableSeed helper

**Files:**
- Create: `Pilgrim/Models/LightReading/LightReading.swift`
- Test: `UnitTests/LightReadingModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `UnitTests/LightReadingModelTests.swift`:
```swift
import XCTest
@testable import Pilgrim

final class LightReadingModelTests: XCTestCase {

    // MARK: - Tier Comparable

    func testTierOrderingByRarity() {
        XCTAssertLessThan(LightReading.Tier.lunarEclipse, .supermoon)
        XCTAssertLessThan(LightReading.Tier.supermoon, .seasonalMarker)
        XCTAssertLessThan(LightReading.Tier.seasonalMarker, .meteorShowerPeak)
        XCTAssertLessThan(LightReading.Tier.meteorShowerPeak, .fullMoon)
        XCTAssertLessThan(LightReading.Tier.fullMoon, .newMoon)
        XCTAssertLessThan(LightReading.Tier.newMoon, .deepNight)
        XCTAssertLessThan(LightReading.Tier.deepNight, .sunriseSunset)
        XCTAssertLessThan(LightReading.Tier.sunriseSunset, .twilight)
        XCTAssertLessThan(LightReading.Tier.twilight, .goldenHour)
        XCTAssertLessThan(LightReading.Tier.goldenHour, .moonPhase)
    }

    // MARK: - stableSeed

    func testStableSeedFromFixedUUID() {
        let uuid = UUID(uuidString: "12345678-1234-5678-1234-567812345678")!
        let seed1 = LightReading.stableSeed(from: uuid)
        let seed2 = LightReading.stableSeed(from: uuid)
        XCTAssertEqual(seed1, seed2, "Same UUID must always produce same seed")
    }

    func testStableSeedKnownValue() {
        // The UUID bytes are known: 12 34 56 78 12 34 56 78 ...
        let uuid = UUID(uuidString: "12345678-1234-5678-1234-567812345678")!
        let seed = LightReading.stableSeed(from: uuid)
        // First 8 bytes packed big-endian: 0x12 34 56 78 12 34 56 78
        let expected: UInt64 = 0x1234_5678_1234_5678
        XCTAssertEqual(seed, expected)
    }

    func testStableSeedDifferentUUIDsDifferSeeds() {
        let uuid1 = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let uuid2 = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        XCTAssertNotEqual(LightReading.stableSeed(from: uuid1), LightReading.stableSeed(from: uuid2))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: all tests fail with "LightReading not defined".

- [ ] **Step 3: Create the file**

Create `Pilgrim/Models/LightReading/LightReading.swift`:

```swift
import Foundation

struct LightReading: Equatable {
    let sentence: String
    let tier: Tier
    let symbolName: String  // SF Symbol name

    enum Tier: Int, Comparable, CaseIterable {
        case lunarEclipse
        case supermoon
        case seasonalMarker
        case meteorShowerPeak
        case fullMoon
        case newMoon
        case deepNight
        case sunriseSunset
        case twilight
        case goldenHour
        case moonPhase

        static func < (lhs: Tier, rhs: Tier) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Derive a stable UInt64 seed from a UUID's raw bytes. Swift's built-in
    /// UUID.hashValue is randomized per process launch, so using it as a seed
    /// produces non-deterministic results across app restarts. Packing the
    /// first 8 bytes of the UUID directly guarantees a stable seed for the
    /// same walk forever.
    static func stableSeed(from uuid: UUID) -> UInt64 {
        let bytes = uuid.uuid
        var seed: UInt64 = 0
        seed = (seed << 8) | UInt64(bytes.0)
        seed = (seed << 8) | UInt64(bytes.1)
        seed = (seed << 8) | UInt64(bytes.2)
        seed = (seed << 8) | UInt64(bytes.3)
        seed = (seed << 8) | UInt64(bytes.4)
        seed = (seed << 8) | UInt64(bytes.5)
        seed = (seed << 8) | UInt64(bytes.6)
        seed = (seed << 8) | UInt64(bytes.7)
        return seed
    }
}

/// A simple seeded random number generator for deterministic template
/// selection. Uses a linear congruential generator because we only need
/// "different numbers for different seeds", not cryptographic quality.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Ensure seed is nonzero (LCG with state=0 is stuck)
        self.state = seed == 0 ? 1 : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
```

- [ ] **Step 4: Add the file to Xcode, build, and run tests**

Drag into `Pilgrim/Models/LightReading/` in the project navigator, add to Pilgrim target.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/LightReadingModelTests 2>&1 | tail -20
```

Expected: 4/4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/LightReading/LightReading.swift UnitTests/LightReadingModelTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(light-reading): add core model, Tier enum, stableSeed helper

- LightReading struct: sentence, tier, symbolName (SF Symbol)
- Tier enum with 11 rarity-ordered cases, Comparable
- stableSeed(from:) derives a UInt64 from UUID raw bytes, giving
  cross-launch determinism that UUID.hashValue can't provide
- SeededGenerator: LCG RandomNumberGenerator for template picking

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Write LightReadingTemplates with all 70 phrasings

**Files:**
- Create: `Pilgrim/Models/LightReading/LightReadingTemplates.swift`
- Test: `UnitTests/LightReadingTemplatesTests.swift`

This task is primarily authoring. Draft the full template collection based on the examples in the spec (`docs/superpowers/specs/2026-04-13-walk-light-reading-design.md`). Author in the Pilgrim wabi-sabi voice.

- [ ] **Step 1: Write the failing tests**

Create `UnitTests/LightReadingTemplatesTests.swift`:
```swift
import XCTest
@testable import Pilgrim

final class LightReadingTemplatesTests: XCTestCase {

    func testAllTiersHaveAtLeastTwoTemplates() {
        for tier in LightReading.Tier.allCases {
            let templates = LightReadingTemplates.templates(for: tier)
            XCTAssertGreaterThanOrEqual(templates.count, 2,
                "Tier \(tier) should have ≥2 templates, has \(templates.count)")
        }
    }

    func testNoUnfilledPlaceholders() {
        // Every placeholder in every template must match a known key.
        let knownPlaceholders: Set<String> = [
            "{N}", "{time}", "{minutes}", "{pct}", "{showerName}", "{zhr}",
            "{month}", "{year}", "{distanceKm}", "{phaseName}", "{marker}",
            "{flavor}", "{eclipseDate}"
        ]
        for tier in LightReading.Tier.allCases {
            for template in LightReadingTemplates.templates(for: tier) {
                let text = template.text
                let regex = try! NSRegularExpression(pattern: "\\{[^}]+\\}")
                let range = NSRange(text.startIndex..., in: text)
                regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                    guard let match else { return }
                    let placeholder = String(text[Range(match.range, in: text)!])
                    XCTAssertTrue(knownPlaceholders.contains(placeholder),
                        "Template '\(text)' contains unknown placeholder \(placeholder)")
                }
            }
        }
    }

    func testTemplateCountWithinExpectedRange() {
        let total = LightReading.Tier.allCases
            .map { LightReadingTemplates.templates(for: $0).count }
            .reduce(0, +)
        XCTAssertGreaterThanOrEqual(total, 50)
        XCTAssertLessThanOrEqual(total, 100)
    }
}
```

- [ ] **Step 2: Create the templates file**

Create `Pilgrim/Models/LightReading/LightReadingTemplates.swift`:

```swift
import Foundation

struct LightReadingTemplate {
    let text: String  // template with {placeholder} tokens
}

enum LightReadingTemplates {

    static func templates(for tier: LightReading.Tier) -> [LightReadingTemplate] {
        switch tier {
        case .lunarEclipse: return lunarEclipse
        case .supermoon: return supermoon
        case .seasonalMarker: return seasonalMarker
        case .meteorShowerPeak: return meteorShowerPeak
        case .fullMoon: return fullMoon
        case .newMoon: return newMoon
        case .deepNight: return deepNight
        case .sunriseSunset: return sunriseSunset
        case .twilight: return twilight
        case .goldenHour: return goldenHour
        case .moonPhase: return moonPhase
        }
    }

    // MARK: - Tier-specific template pools
    // Each pool has 4-8 hand-written templates in the Pilgrim wabi-sabi voice.

    private static let lunarEclipse: [LightReadingTemplate] = [
        LightReadingTemplate(text: "This walk happened during a total lunar eclipse. The moon turned red."),
        LightReadingTemplate(text: "A partial lunar eclipse shadowed the moon during this walk."),
        LightReadingTemplate(text: "You walked under a penumbral lunar eclipse. The moon dimmed but never darkened."),
        LightReadingTemplate(text: "A lunar eclipse shaped the sky while you walked."),
    ]

    private static let supermoon: [LightReadingTemplate] = [
        LightReadingTemplate(text: "You walked under the {month} supermoon — the full moon at its closest to Earth."),
        LightReadingTemplate(text: "This was a supermoon walk. The moon appeared larger and brighter than most."),
        LightReadingTemplate(text: "The supermoon of {month} {year} watched over this walk."),
        LightReadingTemplate(text: "A supermoon lit the sky during this walk."),
    ]

    private static let seasonalMarker: [LightReadingTemplate] = [
        LightReadingTemplate(text: "You walked on the spring equinox. The turning point of the year, light lengthening."),
        LightReadingTemplate(text: "You walked on the summer solstice. The longest day of the year."),
        LightReadingTemplate(text: "You walked on the autumn equinox. The year tipping toward winter."),
        LightReadingTemplate(text: "You walked on the winter solstice. The longest night of the year. Light begins to return tomorrow."),
        LightReadingTemplate(text: "You walked on Imbolc — halfway from the solstice to the equinox."),
        LightReadingTemplate(text: "You walked on Beltane — halfway to the summer solstice."),
        LightReadingTemplate(text: "You walked on Lughnasadh — halfway to the autumn equinox."),
        LightReadingTemplate(text: "You walked on Samhain — halfway to the winter solstice."),
    ]

    private static let meteorShowerPeak: [LightReadingTemplate] = [
        LightReadingTemplate(text: "This walk happened on the peak night of the {showerName} — up to {zhr} meteors per hour."),
        LightReadingTemplate(text: "You walked through the peak of the {showerName} meteor shower."),
        LightReadingTemplate(text: "The {showerName} radiant was overhead during this walk."),
        LightReadingTemplate(text: "This walk coincided with the {showerName} at peak."),
    ]

    private static let fullMoon: [LightReadingTemplate] = [
        LightReadingTemplate(text: "The full moon watched over this walk — {pct}% illuminated."),
        LightReadingTemplate(text: "You walked under a full moon, {pct}% lit."),
        LightReadingTemplate(text: "A full moon accompanied this walk. The brightest sky of the month."),
        LightReadingTemplate(text: "The moon was full during this walk — {pct}% illuminated."),
    ]

    private static let newMoon: [LightReadingTemplate] = [
        LightReadingTemplate(text: "This walk happened under the dark of the new moon. Stars at their clearest."),
        LightReadingTemplate(text: "You walked during a new moon. The sky belonged to the stars."),
        LightReadingTemplate(text: "No moon tonight. A dark sky kept you company."),
        LightReadingTemplate(text: "The moon hid during this walk — a new moon, stars unveiled."),
    ]

    private static let deepNight: [LightReadingTemplate] = [
        LightReadingTemplate(text: "This walk happened in full dark. No moon, no twilight — just the stars."),
        LightReadingTemplate(text: "You walked in astronomical night. The sky was as dark as it gets."),
        LightReadingTemplate(text: "Moonless, past twilight — you walked under the deepest dark of the night."),
        LightReadingTemplate(text: "The sky was fully dark during this walk. Stars were at their brightest."),
    ]

    private static let sunriseSunset: [LightReadingTemplate] = [
        LightReadingTemplate(text: "Your walk began {N} minutes before sunrise. The sun rose at {time}."),
        LightReadingTemplate(text: "Your walk began {N} minutes after sunset. The sun had set at {time}."),
        LightReadingTemplate(text: "You walked into the sunrise at {time}."),
        LightReadingTemplate(text: "You walked into the sunset at {time}."),
        LightReadingTemplate(text: "Your walk began {N} minutes after sunrise. Morning had just begun."),
        LightReadingTemplate(text: "Your walk began {N} minutes before sunset. You chased the last light."),
    ]

    private static let twilight: [LightReadingTemplate] = [
        LightReadingTemplate(text: "You walked through civil twilight — the blue hour between day and night."),
        LightReadingTemplate(text: "You walked through nautical twilight. The brightest stars had come out."),
        LightReadingTemplate(text: "This walk happened in astronomical twilight — the sky going dark."),
        LightReadingTemplate(text: "Blue hour followed you on this walk."),
    ]

    private static let goldenHour: [LightReadingTemplate] = [
        LightReadingTemplate(text: "You walked through the last hour of golden light."),
        LightReadingTemplate(text: "Golden hour followed you the whole way."),
        LightReadingTemplate(text: "Your walk began in the warm hour before sunset."),
        LightReadingTemplate(text: "You walked in golden hour — the soft low sun of early evening."),
    ]

    private static let moonPhase: [LightReadingTemplate] = [
        LightReadingTemplate(text: "You walked under a {phaseName} moon, {pct}% illuminated."),
        LightReadingTemplate(text: "A {phaseName} moon was in the sky during this walk."),
        LightReadingTemplate(text: "This walk took place under a {phaseName} moon — {pct}% lit."),
        LightReadingTemplate(text: "A {phaseName} moon, {pct}% full, accompanied this walk."),
    ]
}
```

- [ ] **Step 3: Run tests to verify all pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/LightReadingTemplatesTests 2>&1 | tail -20
```

- [ ] **Step 4: Commit**

```bash
git add Pilgrim/Models/LightReading/LightReadingTemplates.swift UnitTests/LightReadingTemplatesTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(light-reading): add 50 hand-written templates across 11 tiers

Each tier has 4-8 sentence templates with {placeholder} tokens.
Voice: wabi-sabi, quiet, no exclamation points, no emoji.

Test coverage guarantees every tier has at least 2 templates and
that no template contains an unknown placeholder token.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Implement LightReadingGenerator (priority ladder + feature extraction)

**Files:**
- Create: `Pilgrim/Models/LightReading/LightReadingGenerator.swift`
- Test: `UnitTests/LightReadingGeneratorTests.swift`

This is the largest single task. The generator ties together all prior tasks.

- [ ] **Step 1: Write the failing tests** — see full test plan in the spec's "Test plan" section. Drop the full test file (~250 lines) into `UnitTests/LightReadingGeneratorTests.swift`.

Core tests to write first:
- `testBaselineAlwaysFires` — a walk with no distinguishing features returns `moonPhase`
- `testSeasonalMarkerAtEquinox` — walk on 2024-03-20 returns `seasonalMarker`
- `testFullMoonTier` — walk on a known full moon returns `fullMoon`
- `testSunriseSunsetWindow` — walk within 30 min of sunrise returns `sunriseSunset`
- `testLunarEclipseBeatsAllOthers` — walk during 2026-03-03 eclipse returns `lunarEclipse`
- `testSameWalkDeterministic` — two calls with same walk return identical sentences

- [ ] **Step 2: Run tests to verify they fail**

Expected: all tests fail with "LightReadingGenerator not defined".

- [ ] **Step 3: Implement the generator**

Create `Pilgrim/Models/LightReading/LightReadingGenerator.swift`. Rough structure (~180 lines):

```swift
import Foundation

enum LightReadingGenerator {

    static func generate(for walk: WalkInterface) -> LightReading {
        let seed = seedFor(walk: walk)
        var rng = SeededGenerator(seed: seed)
        let features = extractFeatures(from: walk)

        // Priority ladder — first tier to fire wins.
        if let reading = evaluateEclipse(features: features, rng: &rng) { return reading }
        if let reading = evaluateSupermoon(features: features, rng: &rng) { return reading }
        if let reading = evaluateSeasonalMarker(features: features, rng: &rng) { return reading }
        if let reading = evaluateMeteorShower(features: features, rng: &rng) { return reading }
        if let reading = evaluateFullMoon(features: features, rng: &rng) { return reading }
        if let reading = evaluateNewMoon(features: features, rng: &rng) { return reading }
        if let reading = evaluateDeepNight(features: features, rng: &rng) { return reading }
        if let reading = evaluateSunriseSunset(features: features, rng: &rng) { return reading }
        if let reading = evaluateTwilight(features: features, rng: &rng) { return reading }
        if let reading = evaluateGoldenHour(features: features, rng: &rng) { return reading }

        // Baseline: always fires
        return evaluateMoonPhase(features: features, rng: &rng)
    }

    // MARK: - Feature extraction

    private struct Features {
        let walkDate: Date
        let latitude: Double?
        let longitude: Double?
        let illumination: Double
        let phase: CelestialCalculator.LunarPhase
        let horizon: SolarHorizon.HorizonTimes?
        let solarAltitude: Double?
    }

    private static func extractFeatures(from walk: WalkInterface) -> Features {
        let walkDate = walk.startDate
        let latitude = walk.startLocation?.latitude
        let longitude = walk.startLocation?.longitude

        let T = CelestialCalculator.julianCenturies(from: CelestialCalculator.julianDayNumber(from: walkDate))
        let illumination = CelestialCalculator.lunarIllumination(T: T)
        let phase = CelestialCalculator.lunarPhaseName(for: walkDate)

        var horizon: SolarHorizon.HorizonTimes?
        var altitude: Double?
        if let lat = latitude, let lon = longitude {
            horizon = SolarHorizon.compute(date: walkDate, latitude: lat, longitude: lon)
            altitude = SolarHorizon.solarAltitude(date: walkDate, latitude: lat, longitude: lon)
        }

        return Features(
            walkDate: walkDate,
            latitude: latitude,
            longitude: longitude,
            illumination: illumination,
            phase: phase,
            horizon: horizon,
            solarAltitude: altitude
        )
    }

    // MARK: - Tier evaluators

    // Each evaluator returns `LightReading?` — nil if this tier doesn't fire.
    // Implementation for each follows the spec's priority ladder section.

    private static func evaluateEclipse(features: Features, rng: inout SeededGenerator) -> LightReading? {
        guard let event = AstronomicalEvents.eclipse(on: features.walkDate) else { return nil }
        let templates = LightReadingTemplates.templates(for: .lunarEclipse)
        let template = templates.randomElement(using: &rng) ?? templates[0]
        return LightReading(
            sentence: template.text,  // TODO: fill in {type}, {minutes}, etc if present
            tier: .lunarEclipse,
            symbolName: "moon.circle.fill"
        )
    }

    // ... similar evaluators for supermoon, seasonalMarker, meteorShowerPeak,
    // fullMoon, newMoon, deepNight, sunriseSunset, twilight, goldenHour, moonPhase

    // MARK: - Placeholder filling

    private static func fill(template: String, with values: [String: String]) -> String {
        var result = template
        for (key, value) in values {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }

    // MARK: - Seed

    private static func seedFor(walk: WalkInterface) -> UInt64 {
        if let uuid = walk.uuid {
            return LightReading.stableSeed(from: uuid)
        }
        return UInt64(walk.startDate.timeIntervalSince1970)
    }
}
```

The tier evaluators are straightforward conditionals. Each reads the relevant feature (illumination, solar altitude, etc.), decides whether to fire, picks a template with the seeded RNG, fills in placeholders, and returns a `LightReading`.

**Key implementation details**:
- `evaluateSeasonalMarker` uses `CelestialCalculator.seasonalMarker(sunLongitude:)` and filters for ±24h window against walker's local date
- `evaluateFullMoon` checks `illumination >= 0.95`
- `evaluateDeepNight` checks `altitude <= -18 && illumination <= 0.10`
- `evaluateSunriseSunset` compares `walkDate` against `horizon.sunrise` and `horizon.sunset` (±30 min)

- [ ] **Step 4: Run tests to verify all pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/LightReadingGeneratorTests 2>&1 | tail -20
```

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/LightReading/LightReadingGenerator.swift UnitTests/LightReadingGeneratorTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(light-reading): implement generator with 11-tier priority ladder

Given a walk, evaluate all 11 tiers in rarity order (lunarEclipse
through moonPhase baseline) and return the first one that fires.
Each tier reads its relevant feature (illumination, solar altitude,
sunrise/sunset times) and picks a template from its pool using the
walk's stable seed. Placeholders are filled with real computed values.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Create WalkSharingTracker for reveal-state persistence

**Files:**
- Create: `Pilgrim/Models/LightReading/WalkSharingTracker.swift`
- Test: `UnitTests/WalkSharingTrackerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `UnitTests/WalkSharingTrackerTests.swift`:
```swift
import XCTest
@testable import Pilgrim

final class WalkSharingTrackerTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "WalkSharingTrackerTests")!
        defaults.removePersistentDomain(forName: "WalkSharingTrackerTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "WalkSharingTrackerTests")
        super.tearDown()
    }

    func testHasNotSharedInitially() {
        let tracker = WalkSharingTracker(defaults: defaults)
        XCTAssertFalse(tracker.hasShared(walkUUID: "abc"))
    }

    func testMarkSharedStoresUUID() {
        let tracker = WalkSharingTracker(defaults: defaults)
        tracker.markShared(walkUUID: "abc")
        XCTAssertTrue(tracker.hasShared(walkUUID: "abc"))
    }

    func testMarkMultipleWalksAccumulates() {
        let tracker = WalkSharingTracker(defaults: defaults)
        tracker.markShared(walkUUID: "walk-1")
        tracker.markShared(walkUUID: "walk-2")
        tracker.markShared(walkUUID: "walk-3")
        XCTAssertTrue(tracker.hasShared(walkUUID: "walk-1"))
        XCTAssertTrue(tracker.hasShared(walkUUID: "walk-2"))
        XCTAssertTrue(tracker.hasShared(walkUUID: "walk-3"))
    }

    func testMarkSharedUsesSingleKey() {
        let tracker = WalkSharingTracker(defaults: defaults)
        tracker.markShared(walkUUID: "walk-1")
        tracker.markShared(walkUUID: "walk-2")
        let allKeys = defaults.dictionaryRepresentation().keys.filter { $0.contains("sharedWalk") || $0.contains("hasSharedWalk") }
        XCTAssertEqual(allKeys.count, 1, "Should use exactly one UserDefaults key")
    }
}
```

- [ ] **Step 2-4: Run tests (fail), implement, run (pass)**

Create `Pilgrim/Models/LightReading/WalkSharingTracker.swift`:
```swift
import Foundation

final class WalkSharingTracker {
    private let key = "sharedWalkUUIDs"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func hasShared(walkUUID: String) -> Bool {
        sharedUUIDs.contains(walkUUID)
    }

    func markShared(walkUUID: String) {
        var uuids = sharedUUIDs
        uuids.insert(walkUUID)
        defaults.set(Array(uuids), forKey: key)
    }

    private var sharedUUIDs: Set<String> {
        Set(defaults.array(forKey: key) as? [String] ?? [])
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/LightReading/WalkSharingTracker.swift UnitTests/WalkSharingTrackerTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(light-reading): add WalkSharingTracker for reveal-state persistence

Single UserDefaults key 'sharedWalkUUIDs' holds the set of walk UUIDs
the user has shared. Prevents the per-walk key explosion pattern that
would accumulate thousands of keys over years of use.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Create WalkLightReadingCard SwiftUI view

**Files:**
- Create: `Pilgrim/Views/WalkLightReadingCard.swift`

- [ ] **Step 1: Implement the card**

```swift
import SwiftUI

struct WalkLightReadingCard: View {
    let reading: LightReading
    let isRevealed: Bool

    var body: some View {
        VStack(spacing: Constants.UI.Padding.normal) {
            Image(systemName: reading.symbolName)
                .font(.title2)
                .foregroundColor(.stone)
                .accessibilityHidden(true)

            Text(reading.sentence)
                .font(Constants.Typography.body)
                .foregroundColor(.ink)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, Constants.UI.Padding.normal)

            Text("— a light reading")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog.opacity(0.6))
                .italic()
        }
        .padding(.vertical, Constants.UI.Padding.big)
        .padding(.horizontal, Constants.UI.Padding.normal)
        .frame(maxWidth: .infinity)
        .background(Color.parchment)
        .cornerRadius(Constants.UI.CornerRadius.normal)
        .opacity(isRevealed ? 1 : 0)
        .scaleEffect(isRevealed ? 1 : 0.97)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("A light reading for this walk: \(reading.sentence)")
        .onLongPressGesture {
            UIPasteboard.general.string = reading.sentence
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

- [ ] **Step 3: Commit**

```bash
git add Pilgrim/Views/WalkLightReadingCard.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(light-reading): add WalkLightReadingCard SwiftUI view

Renders one light reading as a parchment card with an SF Symbol
header, the reading sentence, and a small caption. Fades in via
the isRevealed binding (consumer animates the transition). Long-
press copies the sentence to pasteboard.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Integrate into WalkSummaryView

**Files:**
- Modify: `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift`

- [ ] **Step 1: Add state properties**

Near the other `@State` declarations (around line 17):
```swift
@State private var lightReading: LightReading?
@State private var hasRevealedLightReading = false
private let sharingTracker = WalkSharingTracker()
```

- [ ] **Step 2: Insert the card in the VStack**

Around line 71, above `shareCard`:
```swift
if let reading = lightReading {
    WalkLightReadingCard(reading: reading, isRevealed: hasRevealedLightReading)
}
```

- [ ] **Step 3: Compute the reading in onAppear**

Extend the existing `.onAppear`:
```swift
.onAppear {
    // ... existing setup code ...
    lightReading = LightReadingGenerator.generate(for: walk)
    if let uuid = walk.uuid?.uuidString {
        hasRevealedLightReading = sharingTracker.hasShared(walkUUID: uuid)
    }
}
```

- [ ] **Step 4: Hook the reveal into the Share button**

Find the Share button inside `shareCard` (around line 786) and wrap its action to also trigger the reveal. Exact wiring depends on the existing share button implementation — may need to wrap the action closure or use an `onTapGesture` modifier.

```swift
// Before:
Button("Share") { ... existing share action ... }

// After:
Button("Share") {
    ... existing share action ...
    if let uuid = walk.uuid?.uuidString {
        sharingTracker.markShared(walkUUID: uuid)
        withAnimation(.easeInOut(duration: 1.2)) {
            hasRevealedLightReading = true
        }
    }
}
```

- [ ] **Step 5: Build and run in simulator**

Launch the app, open a walk summary, verify:
- The card does NOT appear before tapping Share
- Tapping Share reveals the card with a fade
- Scrolling back shows the card is still there
- Closing and reopening the walk summary renders the card immediately

- [ ] **Step 6: Commit**

```bash
git add Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift
git commit -m "feat(light-reading): wire WalkLightReadingCard into WalkSummaryView

Generate the light reading on onAppear, insert the card above
shareCard, and reveal it on first Share tap. Reveal state persists
across app launches via WalkSharingTracker.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: End-to-end smoke test and TestFlight

- [ ] **Step 1: Manual smoke test on a set of real historical walks**

Open the app, navigate to several past walks with diverse features:
- A walk from around a known full moon — verify `fullMoon` or `supermoon` reading
- A walk from early morning — verify `sunriseSunset` or `goldenHour` reading
- A walk from midday on an ordinary day — verify `moonPhase` baseline
- A walk from around September 22 — verify `seasonalMarker` (autumn equinox)
- A walk from August 12 — verify `meteorShowerPeak` (Perseids)

For each, tap Share, verify the card appears, scroll back to verify it persists.

- [ ] **Step 2: Run full test suite**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests 2>&1 | tail -10
```

Expected: all tests pass.

- [ ] **Step 3: Dispatch TestFlight build**

```bash
gh workflow run testflight.yml --ref main 2>&1
```

- [ ] **Step 4: Announce to user**

Report:
- Implementation complete, X commits on main
- TestFlight run URL
- Notable decisions made during implementation
- Any spec items that turned out differently than expected

---

## Post-implementation checklist

- [ ] All 11 tasks complete
- [ ] All unit tests pass (expected ~35 new tests added by this feature)
- [ ] Manual smoke test against 5+ real walks confirms readings feel right
- [ ] TestFlight build succeeds
- [ ] Spec document updated with any implementation learnings (if applicable)
- [ ] `CHANGELOG.md` (if the project has one) updated with the feature

## Execution notes

- Tasks 1–4 are independent and can be done in any order (or in parallel if using subagent-driven-development). Task 4 depends on Task 3 having generated the data file.
- Tasks 5–7 form a sequential chain: LightReading struct → Templates → Generator. Can't parallelize.
- Task 8 is independent and can be done any time after Task 5.
- Tasks 9–10 depend on Tasks 5 and 7 being done.
- Task 11 depends on everything.

Suggested execution order if working solo: 1 → 2 → 3 → 4 → 5 → 8 → 6 → 7 → 9 → 10 → 11. This front-loads the astronomy primitives and data, then builds the model/template/generator chain, then wires up the UI.
