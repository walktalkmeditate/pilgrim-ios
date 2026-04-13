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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents([.hour, .minute], from: sunrise)
        XCTAssertEqual(components.hour, 3)
        XCTAssertLessThanOrEqual(abs((components.minute ?? 0) - 47), 2)  // ±2 min tolerance
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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents([.hour, .minute], from: sunset)
        XCTAssertEqual(components.hour, 19)
        XCTAssertLessThanOrEqual(abs((components.minute ?? 0) - 58), 2)
    }

    func testPolarDayReturnsNilSunset() {
        // 80°N in July has midnight sun — the sun never sets or rises.
        let horizon = SolarHorizon.compute(
            date: iso("2024-07-01T12:00:00Z"),
            latitude: 80.0,
            longitude: 0.0
        )
        XCTAssertNil(horizon.sunrise, "80°N in July should have no sunrise (midnight sun)")
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

    func testSolarAltitudeAtMidnightIsNegative() {
        let altitude = SolarHorizon.solarAltitude(
            date: iso("2024-06-21T22:00:00Z"),  // late evening UTC, middle of night in Paris
            latitude: 48.8566,
            longitude: 2.3522
        )
        XCTAssertLessThan(altitude, 0, "Sun should be below horizon at Paris midnight")
    }

    func testSolarAltitudeAtNoonIsHigh() {
        // At 48.8566°N on 2024-06-21, solar altitude at local solar noon should be high (~65°).
        // Using UTC noon is a rough approximation to solar noon.
        let altitude = SolarHorizon.solarAltitude(
            date: iso("2024-06-21T12:00:00Z"),
            latitude: 48.8566,
            longitude: 2.3522
        )
        XCTAssertGreaterThan(altitude, 60, "Sun should be high at Paris near midday on solstice")
    }

    // MARK: - Helpers

    private func iso(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }
}
