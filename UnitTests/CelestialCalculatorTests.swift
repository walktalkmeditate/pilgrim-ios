import XCTest
@testable import Pilgrim

final class CelestialCalculatorTests: XCTestCase {

    // MARK: - Julian Day Number

    func testJulianDayNumber_j2000Epoch() {
        let date = DateFactory.makeUTCDate(2000, 1, 1, 12, 0, 0)
        let jd = CelestialCalculator.julianDayNumber(from: date)
        XCTAssertEqual(jd, 2451545.0, accuracy: 0.01)
    }

    func testJulianCenturies_j2000_isZero() {
        let T = CelestialCalculator.julianCenturies(from: 2451545.0)
        XCTAssertEqual(T, 0.0, accuracy: 0.0001)
    }

    // MARK: - Solar Longitude (verified against published ephemeris)

    func testSolarLongitude_vernalEquinox2024() {
        let date = DateFactory.makeUTCDate(2024, 3, 20, 3, 6, 0)
        let jd = CelestialCalculator.julianDayNumber(from: date)
        let T = CelestialCalculator.julianCenturies(from: jd)
        let lon = CelestialCalculator.solarLongitude(T: T)
        XCTAssertEqual(lon, 0.0, accuracy: 1.5)
    }

    func testSolarLongitude_summerSolstice2024() {
        let date = DateFactory.makeUTCDate(2024, 6, 20, 20, 51, 0)
        let jd = CelestialCalculator.julianDayNumber(from: date)
        let T = CelestialCalculator.julianCenturies(from: jd)
        let lon = CelestialCalculator.solarLongitude(T: T)
        XCTAssertEqual(lon, 90.0, accuracy: 1.5)
    }

    func testSolarLongitude_winterSolstice2024() {
        let date = DateFactory.makeUTCDate(2024, 12, 21, 9, 21, 0)
        let jd = CelestialCalculator.julianDayNumber(from: date)
        let T = CelestialCalculator.julianCenturies(from: jd)
        let lon = CelestialCalculator.solarLongitude(T: T)
        XCTAssertEqual(lon, 270.0, accuracy: 1.5)
    }

    // MARK: - Zodiac Sign Mapping

    func testZodiacPosition_aries() {
        let pos = CelestialCalculator.zodiacPosition(longitude: 15.0)
        XCTAssertEqual(pos.sign, .aries)
        XCTAssertEqual(pos.degree, 15.0, accuracy: 0.01)
    }

    func testZodiacPosition_pisces() {
        let pos = CelestialCalculator.zodiacPosition(longitude: 350.0)
        XCTAssertEqual(pos.sign, .pisces)
        XCTAssertEqual(pos.degree, 20.0, accuracy: 0.01)
    }

    func testZodiacPosition_signBoundary() {
        let pos = CelestialCalculator.zodiacPosition(longitude: 30.0)
        XCTAssertEqual(pos.sign, .taurus)
        XCTAssertEqual(pos.degree, 0.0, accuracy: 0.01)
    }

    // MARK: - Ingress Detection

    func testIngress_nearSignBoundary_true() {
        XCTAssertTrue(CelestialCalculator.isIngress(longitude: 0.5))
        XCTAssertTrue(CelestialCalculator.isIngress(longitude: 29.5))
        XCTAssertTrue(CelestialCalculator.isIngress(longitude: 60.2))
    }

    func testIngress_midSign_false() {
        XCTAssertFalse(CelestialCalculator.isIngress(longitude: 15.0))
        XCTAssertFalse(CelestialCalculator.isIngress(longitude: 45.0))
    }

    // MARK: - Retrograde

    func testSunAndMoon_neverRetrograde() {
        let date = DateFactory.makeUTCDate(2024, 6, 15, 12, 0, 0)
        let jd = CelestialCalculator.julianDayNumber(from: date)
        let T = CelestialCalculator.julianCenturies(from: jd)
        XCTAssertFalse(CelestialCalculator.isRetrograde(planet: .sun, T: T))
        XCTAssertFalse(CelestialCalculator.isRetrograde(planet: .moon, T: T))
    }

    // MARK: - Seasonal Markers

    func testSeasonalMarker_springEquinox() {
        XCTAssertEqual(CelestialCalculator.seasonalMarker(sunLongitude: 0.5), .springEquinox)
        XCTAssertEqual(CelestialCalculator.seasonalMarker(sunLongitude: 359.5), .springEquinox)
    }

    func testSeasonalMarker_summerSolstice() {
        XCTAssertEqual(CelestialCalculator.seasonalMarker(sunLongitude: 90.0), .summerSolstice)
    }

    func testSeasonalMarker_crossQuarterDays() {
        XCTAssertEqual(CelestialCalculator.seasonalMarker(sunLongitude: 315.0), .imbolc)
        XCTAssertEqual(CelestialCalculator.seasonalMarker(sunLongitude: 45.0), .beltane)
        XCTAssertEqual(CelestialCalculator.seasonalMarker(sunLongitude: 135.0), .lughnasadh)
        XCTAssertEqual(CelestialCalculator.seasonalMarker(sunLongitude: 225.0), .samhain)
    }

    func testSeasonalMarker_midSign_nil() {
        XCTAssertNil(CelestialCalculator.seasonalMarker(sunLongitude: 55.0))
    }

    // MARK: - Full Snapshot

    func testSnapshot_returnsAllPlanets() {
        let date = DateFactory.makeUTCDate(2024, 6, 15, 12, 0, 0)
        let snapshot = CelestialCalculator.snapshot(for: date, system: .tropical)
        XCTAssertEqual(snapshot.positions.count, 7)
        XCTAssertNotNil(snapshot.position(for: .sun))
        XCTAssertNotNil(snapshot.position(for: .moon))
        XCTAssertNotNil(snapshot.position(for: .saturn))
    }

    func testSnapshot_tropicalSystem() {
        let date = DateFactory.makeUTCDate(2024, 6, 15, 12, 0, 0)
        let snapshot = CelestialCalculator.snapshot(for: date, system: .tropical)
        XCTAssertEqual(snapshot.system, .tropical)
        let sun = snapshot.position(for: .sun)!
        XCTAssertEqual(sun.tropical.sign, .gemini)
    }

    func testSnapshot_siderealOffset() {
        let date = DateFactory.makeUTCDate(2024, 6, 15, 12, 0, 0)
        let snapshot = CelestialCalculator.snapshot(for: date, system: .tropical)
        let sunPos = snapshot.position(for: .sun)!
        let tropicalDeg = Double(sunPos.tropical.sign.rawValue) * 30 + sunPos.tropical.degree
        let siderealDeg = Double(sunPos.sidereal.sign.rawValue) * 30 + sunPos.sidereal.degree
        let offset = tropicalDeg - siderealDeg
        XCTAssertEqual(offset, 24.0, accuracy: 1.0)
    }

    func testSnapshot_elementBalance_sumsToSeven() {
        let date = DateFactory.makeUTCDate(2024, 6, 15, 12, 0, 0)
        let snapshot = CelestialCalculator.snapshot(for: date)
        let total = snapshot.elementBalance.counts.values.reduce(0, +)
        XCTAssertEqual(total, 7)
    }

    func testSnapshot_planetaryHour_notNil() {
        let date = DateFactory.makeUTCDate(2024, 6, 15, 12, 0, 0)
        let snapshot = CelestialCalculator.snapshot(for: date)
        XCTAssertNotNil(snapshot.planetaryHour.planet)
    }

    // MARK: - Dual System Consistency

    func testDualSystem_sameDate_differentPositions() {
        let date = DateFactory.makeUTCDate(2024, 3, 20, 12, 0, 0)
        let snapshot = CelestialCalculator.snapshot(for: date, system: .tropical)
        let sunPos = snapshot.position(for: .sun)!
        XCTAssertNotEqual(sunPos.tropical.sign, sunPos.sidereal.sign)
    }
}

extension DateFactory {
    static func makeUTCDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }
}
