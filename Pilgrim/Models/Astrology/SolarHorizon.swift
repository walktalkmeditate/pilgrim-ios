import Foundation

/// Sunrise/sunset/solar altitude calculations for an observer at a
/// specific latitude and longitude on a specific date. Uses the NOAA
/// simplified solar position algorithm — accurate to ~1 minute for
/// sunrise/sunset times between 1950 and 2050.
///
/// Reference: https://gml.noaa.gov/grad/solcalc/calcdetails.html
enum SolarHorizon {

    struct HorizonTimes {
        /// The instant of sunrise on the given date at the given location,
        /// or `nil` if the sun does not cross the horizon that day (polar
        /// night OR midnight sun — both return nil for both fields).
        let sunrise: Date?
        /// The instant of sunset on the given date at the given location,
        /// or `nil` if the sun does not cross the horizon that day (polar
        /// night OR midnight sun — both return nil for both fields).
        let sunset: Date?
        /// Solar noon — always non-nil regardless of polar conditions.
        let solarNoon: Date
    }

    /// Compute sunrise, sunset, and solar noon for a date at an observer
    /// location. The input `date` only needs to identify the correct UTC
    /// day; the returned times are the actual instants of sunrise/sunset
    /// on that day.
    static func compute(date: Date, latitude: Double, longitude: Double) -> HorizonTimes {
        let julianDay = CelestialCalculator.julianDayNumber(from: date)
        let T = CelestialCalculator.julianCenturies(from: julianDay)

        let (declination, equationOfTime) = solarPosition(T: T)

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
        let julianDay = CelestialCalculator.julianDayNumber(from: date)
        let T = CelestialCalculator.julianCenturies(from: julianDay)

        let (declination, equationOfTime) = solarPosition(T: T)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let utcHours = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60.0 + Double(components.second ?? 0) / 3600.0
        let localSolarTime = utcHours + longitude / 15.0 + equationOfTime / 60.0
        let hourAngle = 15.0 * (localSolarTime - 12.0)

        let altitude = degrees(asin(
            sin(radians(latitude)) * sin(radians(declination))
            + cos(radians(latitude)) * cos(radians(declination)) * cos(radians(hourAngle))
        ))
        return altitude
    }

    // MARK: - Internal helpers

    private static func solarPosition(T: Double) -> (declination: Double, equationOfTime: Double) {
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

        return (declination, equationOfTime)
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
