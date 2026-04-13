import XCTest
@testable import Pilgrim

final class LightReadingTemplatesTests: XCTestCase {

    func testAllTiersHaveAtLeastTwoTemplates() {
        for tier in LightReading.Tier.allCases {
            let templates = LightReadingTemplates.templates(for: tier)
            XCTAssertGreaterThanOrEqual(templates.count, 2,
                "Tier \(tier) should have ≥2 templates, has \(templates.count)")
        }
    }

    func testNoUnfilledPlaceholdersInTemplateText() {
        let knownPlaceholders: Set<String> = [
            "{N}", "{unit}", "{time}", "{pct}", "{showerName}", "{zhr}",
            "{month}", "{year}", "{distanceKm}", "{phaseName}",
            "{season}", "{timeOfDay}"
        ]
        for tier in LightReading.Tier.allCases {
            for template in LightReadingTemplates.templates(for: tier) {
                let text = template.text
                let regex = try! NSRegularExpression(pattern: "\\{[^}]+\\}")
                let range = NSRange(text.startIndex..., in: text)
                regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                    guard let match else { return }
                    let placeholder = String(text[Range(match.range, in: text)!])
                    XCTAssertTrue(knownPlaceholders.contains(placeholder),
                        "Template '\(text)' contains unknown placeholder \(placeholder)")
                }
            }
        }
    }

    func testTemplateCountWithinExpectedRange() {
        let total = LightReading.Tier.allCases
            .map { LightReadingTemplates.templates(for: $0).count }
            .reduce(0, +)
        XCTAssertGreaterThanOrEqual(total, 50)
        XCTAssertLessThanOrEqual(total, 100)
    }

    func testSeasonalMarkerTemplateMatchesPoolTemplate() {
        let pool = LightReadingTemplates.templates(for: .seasonalMarker)
        let allMarkers: [SeasonalMarker] = [
            .springEquinox, .summerSolstice, .autumnEquinox, .winterSolstice,
            .imbolc, .beltane, .lughnasadh, .samhain
        ]
        for marker in allMarkers {
            let specific = LightReadingTemplates.seasonalMarkerTemplate(for: marker)
            XCTAssertTrue(pool.contains { $0.text == specific.text },
                "seasonalMarkerTemplate(for: .\(marker)) must return a template that's also in the pool")
        }
    }

    func testNoExclamationPointsOrEmoji() {
        for tier in LightReading.Tier.allCases {
            for template in LightReadingTemplates.templates(for: tier) {
                XCTAssertFalse(template.text.contains("!"),
                    "Template '\(template.text)' contains '!' — wabi-sabi voice forbids exclamation")
                for scalar in template.text.unicodeScalars {
                    if scalar.value > 127 {
                        let allowedUnicode: Set<UInt32> = [
                            0x2013, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x2026, 0x00B7
                        ]
                        XCTAssertTrue(allowedUnicode.contains(scalar.value),
                            "Template '\(template.text)' contains non-ASCII scalar \(String(format: "U+%04X", scalar.value))")
                    }
                }
            }
        }
    }
}
