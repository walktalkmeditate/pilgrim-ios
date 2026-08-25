import XCTest
@testable import Pilgrim

/// Rider (T8 review carry-forward): the moon line's top-theme tie-break
/// needs sense-level fixtures beyond the suppression path already covered
/// in `DossierSensesCrossWalkTests` — most-walks-wins when two themes are
/// simultaneously eligible, and the alphabetical fallback when they tie on
/// walk count. Split into its own file — the parent class sits at the
/// file_length gate — following the same-file extension pattern established
/// by `DossierSensesMarkerPhotoTests.swift`. Shares that class's fixtures
/// (`makeInput`, `thread`, `appearance`) via extension.
extension DossierSensesCrossWalkTests {

    private func moonFixture(themeWalkCounts: [(lemma: String, walks: Int)]) -> DossierSenses.Input {
        let lunationStart = DateFactory.makeDate(2024, 5, 8)
        let lunationEnd = DateFactory.makeDate(2024, 6, 6, 12, 0, 0)
        let inLunation = { (i: Int) in lunationStart.addingTimeInterval(Double(i + 1) * 4 * 86400) }
        var dayOffset = 0
        let threads = themeWalkCounts.map { entry -> WalkThread in
            let appearances = (0..<entry.walks).map { _ -> ThreadAppearance in
                defer { dayOffset += 1 }
                return appearance(walk: UUID(), date: inLunation(dayOffset))
            }
            return thread(lemma: entry.lemma, appearances: appearances)
        }
        return makeInput(
            currentWalkUUID: UUID(),
            threads: threads,
            moon: DossierSenses.MoonInput(
                lunationIndex: 300, moonName: "Sturgeon Moon",
                start: lunationStart, end: lunationEnd,
                lastReportedIndex: nil, currentWalkHasWords: true,
                allWalkDates: (0..<5).map(inLunation), wordedWalkDates: (0..<3).map(inLunation)
            )
        )
    }

    func testMoon_twoEligibleThemesDifferingWalkCounts_mostWalksWinsOverAlphabetical() {
        let input = moonFixture(themeWalkCounts: [("art", 1), ("music", 2)])
        XCTAssertEqual(
            DossierSenses.moonLine(input: input, suppressed: [])?.lemma, "music",
            "'art' sorts first alphabetically but 'music' walked twice — walk count outranks alphabetical order"
        )
    }

    func testMoon_twoEligibleThemesTiedOnWalkCount_alphabeticallyEarlierWins() {
        let input = moonFixture(themeWalkCounts: [("music", 2), ("art", 2)])
        XCTAssertEqual(
            DossierSenses.moonLine(input: input, suppressed: [])?.lemma, "art",
            "tied at 2 walks each — 'art' precedes 'music' alphabetically"
        )
    }
}
