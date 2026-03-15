import XCTest
@testable import Pilgrim

final class LunarPhaseTests: XCTestCase {

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "UTC")
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return components.date!
    }

    func testKnownNewMoon_returnsNewMoon() {
        let phase = LunarPhase.current(date: date(2024, 1, 11))
        XCTAssertEqual(phase.name, "New Moon")
        XCTAssertLessThan(phase.illumination, 0.05)
    }

    func testHalfSynodicCycleFromNewMoon_returnsFullMoon() {
        let refNewMoon = date(2000, 1, 6, hour: 18)
        let fullMoonDate = Calendar.current.date(byAdding: .day, value: 15, to: refNewMoon)!
        let phase = LunarPhase.current(date: fullMoonDate)
        XCTAssertEqual(phase.name, "Full Moon")
        XCTAssertGreaterThan(phase.illumination, 0.95)
    }

    func testIllumination_alwaysInUnitRange() {
        for dayOffset in 0..<365 {
            let testDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: date(2024, 1, 1))!
            let phase = LunarPhase.current(date: testDate)
            XCTAssertGreaterThanOrEqual(phase.illumination, 0, "Day offset \(dayOffset)")
            XCTAssertLessThanOrEqual(phase.illumination, 1, "Day offset \(dayOffset)")
        }
    }

    func testIsWaxing_consistentWithPhaseName() {
        let waxingNames = ["New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous"]
        for dayOffset in 0..<365 {
            let testDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: date(2024, 1, 1))!
            let phase = LunarPhase.current(date: testDate)
            let shouldBeWaxing = waxingNames.contains(phase.name)
            XCTAssertEqual(phase.isWaxing, shouldBeWaxing, "\(phase.name) on day \(dayOffset): isWaxing=\(phase.isWaxing)")
        }
    }

    func testDateBeforeReferenceNewMoon_producesValidPhase() {
        let phase = LunarPhase.current(date: date(1999, 6, 15))
        XCTAssertGreaterThanOrEqual(phase.illumination, 0)
        XCTAssertLessThanOrEqual(phase.illumination, 1)
        XCTAssertFalse(phase.name.isEmpty)
    }

    func testAllEightPhaseNames_occurWithinOneCycle() {
        let expectedNames: Set<String> = [
            "New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
            "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent"
        ]
        var foundNames: Set<String> = []
        for day in 0..<30 {
            let testDate = Calendar.current.date(byAdding: .day, value: day, to: date(2024, 1, 11))!
            foundNames.insert(LunarPhase.current(date: testDate).name)
        }
        XCTAssertEqual(foundNames, expectedNames)
    }
}
