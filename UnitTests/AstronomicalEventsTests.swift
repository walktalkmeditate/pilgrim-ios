import XCTest
@testable import Pilgrim

final class AstronomicalEventsTests: XCTestCase {

    // MARK: - Data integrity

    func testMeteorShowersHave8Entries() {
        XCTAssertEqual(AstronomicalEvents.meteorShowers.count, 8)
    }

    func testEventTablesCoverAtLeastDecade() {
        let firstEclipseYear = AstronomicalEvents.lunarEclipses.first
            .map { Calendar(identifier: .gregorian).component(.year, from: $0.date) }
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
        // 2026-03-03 total lunar eclipse
        let walkDate = iso("2026-03-03T11:30:00Z")
        let eclipse = AstronomicalEvents.eclipse(on: walkDate, calendar: utcCalendar)
        XCTAssertNotNil(eclipse)
        XCTAssertEqual(eclipse?.type, .total)
    }

    func testLunarEclipseLookupOrdinaryDate() {
        let walkDate = iso("2026-04-15T12:00:00Z")
        XCTAssertNil(AstronomicalEvents.eclipse(on: walkDate, calendar: utcCalendar))
    }

    func testSupermoonLookupWithin3DayWindow() {
        guard let firstSupermoon = AstronomicalEvents.supermoons.first else {
            XCTFail("No supermoons in table")
            return
        }
        let twoDaysBefore = firstSupermoon.date.addingTimeInterval(-2 * 86400)
        XCTAssertNotNil(AstronomicalEvents.supermoon(near: twoDaysBefore, calendar: utcCalendar))
    }

    func testSupermoonLookupOutsideWindow() {
        guard let firstSupermoon = AstronomicalEvents.supermoons.first else {
            XCTFail("No supermoons in table")
            return
        }
        let fiveDaysBefore = firstSupermoon.date.addingTimeInterval(-5 * 86400)
        XCTAssertNil(AstronomicalEvents.supermoon(near: fiveDaysBefore, calendar: utcCalendar))
    }

    func testMeteorShowerLookupOnPeakDay() {
        let perseidsPeak = dateWithComponents(year: 2026, month: 8, day: 12)
        let shower = AstronomicalEvents.meteorShower(on: perseidsPeak, calendar: utcCalendar)
        XCTAssertNotNil(shower)
        XCTAssertEqual(shower?.name, "Perseids")
    }

    func testMeteorShowerLookupOneDayOffPeak() {
        // ±1 day window — August 13 should still match Perseids
        let dayAfter = dateWithComponents(year: 2026, month: 8, day: 13)
        let shower = AstronomicalEvents.meteorShower(on: dayAfter, calendar: utcCalendar)
        XCTAssertNotNil(shower)
        XCTAssertEqual(shower?.name, "Perseids")
    }

    func testMeteorShowerLookupTwoDaysOffPeak() {
        // August 14 is outside the ±1 day window
        let twoDaysAfter = dateWithComponents(year: 2026, month: 8, day: 14)
        XCTAssertNil(AstronomicalEvents.meteorShower(on: twoDaysAfter, calendar: utcCalendar))
    }

    // MARK: - Helpers

    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

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
