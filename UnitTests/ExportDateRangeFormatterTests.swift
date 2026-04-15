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

    func testFormat_doesNotCrashOnMidnightDate() {
        // Regression smoke test: historically, code that extracts month
        // components from a Date via string manipulation could slip
        // across day boundaries on midnight timestamps. The format
        // helper uses DateFormatter which handles this correctly, but
        // guard against regressions that crash or return an empty
        // string on boundary dates.
        let midnight = makeDate(year: 2026, month: 4, day: 1, hour: 0)
        let result = ExportDateRangeFormatter.format(
            earliest: midnight,
            latest: midnight,
            locale: enUS
        )
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains("2026"))
    }

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar.date(from: components)!
    }
}
