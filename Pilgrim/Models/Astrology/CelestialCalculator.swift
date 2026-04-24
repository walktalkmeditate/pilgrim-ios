import CoreLocation
import Foundation

enum CelestialCalculator {

    /// Lightweight seasonal-marker lookup. Computes only the sun's longitude
    /// and its proximity to the cardinal/cross-quarter angles — skips all
    /// the planetary-position, lunar-phase, planetary-hour, and element
    /// balance work that the full `snapshot(for:)` does. Use this in hot
    /// paths (SwiftUI body re-evals, per-snapshot loops) where only the
    /// seasonal marker matters.
    static func seasonalMarker(for date: Date) -> SeasonalMarker? {
        let jd = julianDayNumber(from: date)
        let T = julianCenturies(from: jd)
        let sunLon = solarLongitude(T: T)
        return seasonalMarker(sunLongitude: sunLon)
    }

    static func snapshot(for date: Date, system: ZodiacSystem = .tropical) -> CelestialSnapshot {
        let jd = julianDayNumber(from: date)
        let T = julianCenturies(from: jd)

        let positions = Planet.allCases.map { planet in
            planetaryPosition(for: planet, T: T, system: system)
        }

        let sunLon = solarLongitude(T: T)
        let hour = planetaryHour(date: date)
        let balance = elementBalance(positions: positions, system: system)
        let marker = seasonalMarker(sunLongitude: sunLon)


        return CelestialSnapshot(
            positions: positions,
            planetaryHour: hour,
            elementBalance: balance,
            system: system,
            seasonalMarker: marker
        )
    }

    // MARK: - Time Conversions

    static func julianDayNumber(from date: Date) -> Double {
        let calendar = Calendar(identifier: .gregorian)
        var utc = calendar
        utc.timeZone = TimeZone(identifier: "UTC")!

        let components = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let Y = Double(components.year!)
        let M = Double(components.month!)
        let D = Double(components.day!)
            + Double(components.hour!) / 24.0
            + Double(components.minute!) / 1440.0
            + Double(components.second!) / 86400.0

        var y = Y
        var m = M
        if M <= 2 {
            y -= 1
            m += 12
        }

        let A = floor(y / 100)
        let B = 2 - A + floor(A / 4)

        return floor(365.25 * (y + 4716)) + floor(30.6001 * (m + 1)) + D + B - 1524.5
    }

    static func julianCenturies(from jd: Double) -> Double {
        (jd - 2451545.0) / 36525.0
    }

    // MARK: - Solar Longitude (Meeus)

    static func solarLongitude(T: Double) -> Double {
        let L0 = 280.46646 + 36000.76983 * T + 0.0003032 * T * T
        let M = 357.52911 + 35999.05029 * T - 0.0001537 * T * T
        let Mrad = radians(M)

        let C = (1.914602 - 0.004817 * T) * sin(Mrad)
            + (0.019993 - 0.000101 * T) * sin(2 * Mrad)
            + 0.000289 * sin(3 * Mrad)

        return normalize(L0 + C)
    }

    // MARK: - Lunar Longitude (Simplified Meeus)

    static func lunarLongitude(T: Double) -> Double {
        let Lm = 218.3165 + 481267.8813 * T
        let D = 297.8502 + 445267.1115 * T
        let M = 357.5291 + 35999.0503 * T
        let Mm = 134.9634 + 477198.8676 * T
        let F = 93.2720 + 483202.0175 * T

        let longitude = Lm
            + 6.289 * sin(radians(Mm))
            - 1.274 * sin(radians(2 * D - Mm))
            + 0.658 * sin(radians(2 * D))
            + 0.214 * sin(radians(2 * Mm))
            - 0.186 * sin(radians(M))
            - 0.114 * sin(radians(2 * F))

        return normalize(longitude)
    }

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
    /// exercise the wrap-around normalization alongside the phase
    /// classifier. Note: the illumination formula `(1 - cos(θ))/2` is
    /// even-symmetric in θ, so the normalization does not affect this
    /// function's output. We normalize here for consistency with
    /// `lunarPhaseFromLongitudes`, which DOES depend on the sign of the
    /// elongation (new-vs-full and waxing-vs-waning discrimination).
    static func lunarIlluminationFromLongitudes(sunLongitude: Double, moonLongitude: Double) -> Double {
        var diff = moonLongitude - sunLongitude
        if diff < 0 { diff += 360 }
        let phase = radians(diff)
        return (1 - cos(phase)) / 2
    }

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
    static func lunarPhaseName(for date: Date) -> LunarPhase {
        let T = julianCenturies(from: julianDayNumber(from: date))
        let sunLon = solarLongitude(T: T)
        let moonLon = lunarLongitude(T: T)
        return lunarPhaseFromLongitudes(sunLongitude: sunLon, moonLongitude: moonLon)
    }

    /// Testable version taking longitudes directly. Normalizes the
    /// elongation to [0, 360) before bucketing — without this, a moon
    /// that has just wrapped past 360° (e.g. moonLon=10° with sunLon=350°)
    /// would compute as elongation=-340°, fall through all 8 phase cases,
    /// and hit the default branch with the wrong answer.
    static func lunarPhaseFromLongitudes(sunLongitude: Double, moonLongitude: Double) -> LunarPhase {
        var elongation = moonLongitude - sunLongitude
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
        default: return .new
        }
    }

    // MARK: - Planetary Longitudes (Simplified Heliocentric)

    static func mercuryLongitude(T: Double) -> Double {
        let L = normalize(252.2509 + 149472.6746 * T)
        let M = meanAnomaly(L: L, perihelionLongitude: 77.4561)
        let helio = L + 23.4400 * sin(radians(M)) + 2.9818 * sin(radians(2 * M))
        return geocentricForInnerPlanet(helioLongitude: normalize(helio), distance: 0.387, T: T)
    }

    static func venusLongitude(T: Double) -> Double {
        let L = normalize(181.9798 + 58517.8157 * T)
        let M = meanAnomaly(L: L, perihelionLongitude: 131.5637)
        let helio = L + 0.7758 * sin(radians(M)) + 0.0033 * sin(radians(2 * M))
        return geocentricForInnerPlanet(helioLongitude: normalize(helio), distance: 0.723, T: T)
    }

    static func marsLongitude(T: Double) -> Double {
        let L = normalize(355.4330 + 19140.2993 * T)
        let M = meanAnomaly(L: L, perihelionLongitude: 336.0602)
        let helio = L + 10.6912 * sin(radians(M)) + 0.6228 * sin(radians(2 * M))
        return geocentricForOuterPlanet(helioLongitude: normalize(helio), distance: 1.524, T: T)
    }

    static func jupiterLongitude(T: Double) -> Double {
        let L = normalize(34.3515 + 3034.9057 * T)
        let M = meanAnomaly(L: L, perihelionLongitude: 14.3312)
        let helio = L + 5.5549 * sin(radians(M)) + 0.1683 * sin(radians(2 * M))
        return geocentricForOuterPlanet(helioLongitude: normalize(helio), distance: 5.203, T: T)
    }

    static func saturnLongitude(T: Double) -> Double {
        let L = normalize(50.0774 + 1222.1138 * T)
        let M = meanAnomaly(L: L, perihelionLongitude: 93.0572)
        let helio = L + 6.3585 * sin(radians(M)) + 0.2204 * sin(radians(2 * M))
        return geocentricForOuterPlanet(helioLongitude: normalize(helio), distance: 9.537, T: T)
    }

    // MARK: - Geocentric Corrections

    private static func geocentricForInnerPlanet(helioLongitude: Double, distance: Double, T: Double) -> Double {
        let sunLon = solarLongitude(T: T)
        let earthHelioLon = normalize(sunLon + 180.0)
        let diff = radians(helioLongitude - earthHelioLon)
        let elongation = degrees(atan2(sin(diff) * distance, cos(diff) * distance - 1.0))
        return normalize(sunLon + elongation)
    }

    private static func geocentricForOuterPlanet(helioLongitude: Double, distance: Double, T: Double) -> Double {
        let sunLon = solarLongitude(T: T)
        let earthHelioLon = normalize(sunLon + 180.0)
        let diffDeg = helioLongitude - earthHelioLon
        let diffRad = radians(diffDeg)
        let parallax = degrees(atan2(sin(diffRad), cos(diffRad) * distance - 1.0))
        return normalize(helioLongitude + parallax - diffDeg)
    }

    private static func meanAnomaly(L: Double, perihelionLongitude: Double) -> Double {
        normalize(L - perihelionLongitude)
    }

    // MARK: - Retrograde Detection

    static func isRetrograde(planet: Planet, T: Double) -> Bool {
        if planet == .sun || planet == .moon { return false }

        let deltaT = 1.0 / 36525.0
        let lon1 = longitude(for: planet, T: T - deltaT)
        let lon2 = longitude(for: planet, T: T)

        var diff = lon2 - lon1
        if diff > 180 { diff -= 360 }
        if diff < -180 { diff += 360 }

        return diff < 0
    }

    // MARK: - Zodiac Position

    static func zodiacPosition(longitude: Double) -> ZodiacPosition {
        let normalizedLon = normalize(longitude)
        let signIndex = Int(normalizedLon / 30.0) % 12
        let degree = normalizedLon - Double(signIndex) * 30.0
        let sign = ZodiacSign(rawValue: signIndex) ?? .aries
        return ZodiacPosition(sign: sign, degree: degree)
    }

    static func isIngress(longitude: Double) -> Bool {
        let degree = longitude.truncatingRemainder(dividingBy: 30.0)
        return degree < 1.0 || degree > 29.0
    }

    // MARK: - Sidereal Conversion (Lahiri Ayanamsa)

    private static func ayanamsa(T: Double) -> Double {
        let julianYear = 2000.0 + T * 100.0
        return 23.85 + 0.01396 * (julianYear - 2000.0)
    }

    // MARK: - Planetary Hours (Chaldean Sequence)

    static func planetaryHour(date: Date) -> PlanetaryHour {
        let calendar = Calendar.current

        let weekday = calendar.component(.weekday, from: date)
        let dayRuler = chaldeanDayRuler(weekday: weekday)

        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let fractionalHour = Double(hour) + Double(minute) / 60.0

        let isDaytime = fractionalHour >= 6.0 && fractionalHour < 18.0
        let hourIndex: Int

        if isDaytime {
            hourIndex = Int(fractionalHour - 6.0)
        } else {
            let elapsed: Double
            if fractionalHour >= 18.0 {
                elapsed = fractionalHour - 18.0
            } else {
                elapsed = fractionalHour + 6.0
            }
            hourIndex = 12 + Int(elapsed)
        }

        let chaldeanOrder: [Planet] = [.saturn, .jupiter, .mars, .sun, .venus, .mercury, .moon]
        let dayRulerIndex = chaldeanOrder.firstIndex(of: dayRuler)!
        let planetIndex = (dayRulerIndex + hourIndex) % 7
        let hourPlanet = chaldeanOrder[planetIndex]

        return PlanetaryHour(planet: hourPlanet, planetaryDay: dayRuler)
    }

    private static func chaldeanDayRuler(weekday: Int) -> Planet {
        switch weekday {
        case 1: return .sun
        case 2: return .moon
        case 3: return .mars
        case 4: return .mercury
        case 5: return .jupiter
        case 6: return .venus
        case 7: return .saturn
        default: return .sun
        }
    }

    // MARK: - Element Balance

    static func elementBalance(positions: [PlanetaryPosition], system: ZodiacSystem = .tropical) -> ElementBalance {
        var counts: [ZodiacSign.Element: Int] = [:]
        for element in ZodiacSign.Element.allCases {
            counts[element] = 0
        }
        for position in positions {
            let sign = system == .tropical ? position.tropical.sign : position.sidereal.sign
            counts[sign.element, default: 0] += 1
        }
        return ElementBalance(counts: counts)
    }

    // MARK: - Seasonal Markers

    static func seasonalMarker(sunLongitude: Double) -> SeasonalMarker? {
        let lon = normalize(sunLongitude)
        let threshold = 1.5

        if abs(lon - 0.0) < threshold || abs(lon - 360.0) < threshold {
            return .springEquinox
        }
        if abs(lon - 90.0) < threshold { return .summerSolstice }
        if abs(lon - 180.0) < threshold { return .autumnEquinox }
        if abs(lon - 270.0) < threshold { return .winterSolstice }

        if abs(lon - 315.0) < threshold { return .imbolc }
        if abs(lon - 45.0) < threshold { return .beltane }
        if abs(lon - 135.0) < threshold { return .lughnasadh }
        if abs(lon - 225.0) < threshold { return .samhain }

        return nil
    }

    // MARK: - Sunrise Azimuth

    /// Compass azimuth (degrees clockwise from true north) where the sun rises
    /// on the given date at the given location. Returns nil if the sun does
    /// not rise that day (polar night/day).
    ///
    /// Uses the standard formula:
    ///   cos(A) = (sin(δ) - sin(φ) · sin(h)) / (cos(φ) · cos(h))
    /// where δ is the sun's declination, φ is the observer's latitude, and
    /// h is the sun's altitude at sunrise (~-0.833° accounting for refraction
    /// and solar disk radius).
    ///
    /// Accuracy ~1-2 degrees, sufficient for a visual orientation marker.
    static func sunriseAzimuth(at coordinate: CLLocationCoordinate2D, on date: Date) -> CLLocationDirection? {
        let lat = coordinate.latitude
        let T = julianCenturies(from: julianDayNumber(from: date))
        let sunLon = solarLongitude(T: T)

        let obliquity = 23.439291 - 0.0130042 * T
        let declination = degrees(asin(
            sin(radians(obliquity)) * sin(radians(sunLon))
        ))

        let h: Double = -0.833

        let phi = radians(lat)
        let delta = radians(declination)
        let hRad = radians(h)

        let cosLat = cos(phi)
        guard abs(cosLat) > 1e-9 else { return nil }

        let numerator = sin(delta) - sin(phi) * sin(hRad)
        let denominator = cosLat * cos(hRad)
        let cosA = numerator / denominator

        guard cosA >= -1.0 && cosA <= 1.0 else { return nil }

        let azimuth = degrees(acos(cosA))
        return azimuth
    }

    // MARK: - Internal Helpers

    private static func planetaryPosition(for planet: Planet, T: Double, system: ZodiacSystem) -> PlanetaryPosition {
        let lon = longitude(for: planet, T: T)
        let tropicalPos = zodiacPosition(longitude: lon)

        let siderealLon = normalize(lon - ayanamsa(T: T))
        let siderealPos = zodiacPosition(longitude: siderealLon)

        let activeLon = system == .tropical ? lon : siderealLon
        return PlanetaryPosition(
            planet: planet,
            longitude: lon,
            tropical: tropicalPos,
            sidereal: siderealPos,
            isRetrograde: isRetrograde(planet: planet, T: T),
            isIngress: isIngress(longitude: activeLon)
        )
    }

    private static func longitude(for planet: Planet, T: Double) -> Double {
        switch planet {
        case .sun: return solarLongitude(T: T)
        case .moon: return lunarLongitude(T: T)
        case .mercury: return mercuryLongitude(T: T)
        case .venus: return venusLongitude(T: T)
        case .mars: return marsLongitude(T: T)
        case .jupiter: return jupiterLongitude(T: T)
        case .saturn: return saturnLongitude(T: T)
        }
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
