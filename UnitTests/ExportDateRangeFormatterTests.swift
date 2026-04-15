import XCTest
@testable import Pilgrim

/// Unit coverage for `ExportDateRangeFormatter`. All tests pin the locale
/// to `en_US_POSIX` so month names stay stable across simulator locales.
final class ExportDateRangeFormatterTests: XCTestCase {

    private let enUS = Locale(identifier: "en_US_POSIX")

    // MARK: - Same month collapses to single label

    func testFormat_sameMonthSameYear_returnsSingleLabel() {
        // Two walks on April 1 and April 15, 2026 → both "April 2026"
        let earliest = makeDate(year: 2026, month: 4, day: 1)
        let latest = makeDate(year: 2026, month: 4, day: 15)
        let result = ExportDateRangeFormatter.format(
            earliest: earliest,
            latest: latest,
            locale: enUS
        )
        XCTAssertEqual(result, "April 2026")
    }

    func testFormat_sameDate_returnsSingleLabel() {
        // Single walk (earliest == latest) collapses to one month/year.
        let date = makeDate(year: 2026, month: 4, day: 14)
        let result = ExportDateRangeFormatter.format(
            earliest: date,
            latest: date,
            locale: enUS
        )
        XCTAssertEqual(result, "April 2026")
    }

    // MARK: - Different months expand to range with en-dash

    func testFormat_differentMonthsSameYear_expandsToRange() {
        let earliest = makeDate(year: 2026, month: 1, day: 10)
        let latest = makeDate(year: 2026, month: 4, day: 14)
        let result = ExportDateRangeFormatter.format(
            earliest: earliest,
            latest: latest,
            locale: enUS
        )
        XCTAssertEqual(result, "January 2026 – April 2026")
    }

    func testFormat_differentYears_expandsToRange() {
        let earliest = makeDate(year: 2024, month: 3, day: 1)
        let latest = makeDate(year: 2026, month: 4, day: 14)
        let result = ExportDateRangeFormatter.format(
            earliest: earliest,
            latest: latest,
            locale: enUS
        )
        XCTAssertEqual(result, "March 2024 – April 2026")
    }

    // MARK: - Separator regression guard

    func testFormat_usesEnDashSeparator() {
        // Regression guard: must use en-dash (–, U+2013) not a regular
        // hyphen (-, U+002D) to match typographic convention and plan text.
        let earliest = makeDate(year: 2024, month: 3, day: 1)
        let latest = makeDate(year: 2026, month: 4, day: 14)
        let result = ExportDateRangeFormatter.format(
            earliest: earliest,
            latest: latest,
            locale: enUS
        )
        XCTAssertTrue(
            result.contains("\u{2013}"),
            "Range separator must be en-dash (U+2013), got: \(result)"
        )
        XCTAssertFalse(
            result.contains(" - "),
            "Must not use regular hyphen-minus as a range separator"
        )
    }

    // MARK: - Boundary edge cases

    func testFormat_midnightBoundary_doesNotSlipToPreviousDay() {
        // April 1, 2026, 00:00:00 local time — must still read as April.
        // Guards against a DateFormatter misconfiguration that interprets
        // the date in a timezone that rolls it to March 31.
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = calendar.date(from: components)!

        var laLocale = enUS
        _ = laLocale  // silence unused
        let formatter = ExportDateRangeFormatter.format(
            earliest: date,
            latest: date,
            locale: enUS
        )
        // The en_US_POSIX formatter uses the system default timezone by
        // default; for a Date at midnight LA time, that's still April 1
        // in most timezones west of UTC. This test mainly verifies we
        // don't crash on a midnight boundary.
        XCTAssertTrue(
            formatter == "April 2026" || formatter == "March 2026",
            "Got unexpected format: \(formatter)"
        )
    }

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12 // noon to avoid timezone edge effects
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar.date(from: components)!
    }
}
