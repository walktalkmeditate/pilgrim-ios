import Foundation

/// Formats a pair of walk dates as a human-readable range for the export
/// confirmation sheet. Collapses same-month ranges to a single label
/// (`"April 2026"`) and expands cross-month ranges with an en-dash
/// (`"March 2024 – April 2026"`) — matching the plan's example wording.
///
/// Takes an explicit `Locale` parameter so tests can pin to
/// `en_US_POSIX` for stable output across simulator locales.
enum ExportDateRangeFormatter {

    static func format(
        earliest: Date,
        latest: Date,
        locale: Locale = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "MMMM yyyy"

        let earliestText = formatter.string(from: earliest)
        let latestText = formatter.string(from: latest)

        if earliestText == latestText {
            return earliestText
        }
        return "\(earliestText) – \(latestText)"
    }
}
