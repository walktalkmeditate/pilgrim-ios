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

    func testLunarPhaseFromLongitudesWrapAround() {
        // Regression guard: without the "if elongation < 0 { elongation += 360 }"
        // normalization in lunarPhaseFromLongitudes, this case computes
        // elongation = 40 - 350 = -310°, which falls through all 8 switch cases
        // and hits the default branch returning .new instead of .waxingCrescent.
        //
        // Walking through the math:
        //   sunLon = 350°, moonLon = 40° (moon has wrapped past 360°)
        //   raw diff = 40 - 350 = -310°  (misses all 8 named buckets → default .new)
        //   normalized diff = -310 + 360 = 50° (true elongation)
        //   50° is in [22.5°, 67.5°) → waxingCrescent
        let phase = CelestialCalculator.lunarPhaseFromLongitudes(
            sunLongitude: 350.0,
            moonLongitude: 40.0
        )
        XCTAssertEqual(phase, .waxingCrescent, "Wrap-around case should be classified as waxing crescent, not new moon (regression guard for normalization)")
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
