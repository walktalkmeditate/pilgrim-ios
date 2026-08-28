import XCTest
@testable import Pilgrim

final class ThemeExtractorTests: XCTestCase {

    private let moveText = """
        Still circling the move today. If the move happens in fall we lose the garden, \
        and moving means telling her father. The move keeps returning whenever the \
        morning is quiet enough for it to speak. Thirty words of worry now.
        """

    func testRepeatedLemma_becomesTheme() {
        let themes = ThemeExtractor.themes(in: moveText, languageCode: "en")
        let move = themes.first { $0.lemma == "move" }
        XCTAssertNotNil(move)
        XCTAssertGreaterThanOrEqual(move!.mentionCount, 3)
        XCTAssertEqual(move!.mentions.count, move!.mentionCount)
    }

    func testShortText_returnsNoThemes() {
        XCTAssertTrue(ThemeExtractor.themes(in: "only a few words here", languageCode: "en").isEmpty)
    }

    func testWalkingDomain_suppressed() {
        let text = String(repeating: "walking the path uphill on the trail ", count: 10)
        let themes = ThemeExtractor.themes(in: text, languageCode: "en")
        XCTAssertFalse(themes.contains { ThemeExtractor.walkingDomain.contains($0.lemma) })
    }

    func testDeterminism() {
        let a = ThemeExtractor.themes(in: moveText, languageCode: "en")
        let b = ThemeExtractor.themes(in: moveText, languageCode: "en")
        XCTAssertEqual(a, b)
    }

    // MARK: - Noun-only + spoken stoplist (Dossier-First Refit Task 1)

    /// Field-confirmed bug: real-device themes were "was / have / can /
    /// think" — spoken-English scaffolding NLTagger tags as verbs, passing
    /// the old [.noun, .verb, .adjective] filter and winning every
    /// raw-frequency ranking. Pure scaffolding must yield zero themes.
    func testPureScaffolding_yieldsNoThemes() {
        let text = "I was thinking I have to see how it can go, I think I was going to have it " +
            "done, I know I can get it, I think I have been thinking"
        XCTAssertTrue(ThemeExtractor.themes(in: text, languageCode: "en").isEmpty)
    }

    func testNounAmongScaffolding_isTheOnlyTheme() {
        let text = "I was thinking about the music, I have to hear the music, I know the music " +
            "is what I can go back to, I think I was going to have it be the music again"
        let themes = ThemeExtractor.themes(in: text, languageCode: "en")
        XCTAssertEqual(themes.map(\.lemma), ["music"])
    }

    // MARK: - lightNouns gate (ship gate, 2026-08-25): day/days/area

    /// Field-confirmed: place resonance threaded 'day' (17 mentions near the
    /// same ground) and photo adjacency threaded 'area' — generic nouns, the
    /// same class as the already-stoplisted `thing`/`way`.
    func testDayAndArea_stoplisted_yieldNoThemes() {
        let text = "It was a long day, every day feels like the last day, and this whole area " +
            "of the area near the area keeps repeating on me, day after day in this area"
        XCTAssertTrue(ThemeExtractor.themes(in: text, languageCode: "en").isEmpty)
    }

    func testNounAmongDayAndArea_isTheOnlyTheme() {
        let text = "Another long day thinking about the harbor, the harbor sits at the edge of the " +
            "area, and the day always brings me back to the harbor whatever the area looks like"
        let themes = ThemeExtractor.themes(in: text, languageCode: "en")
        XCTAssertEqual(themes.map(\.lemma), ["harbor"])
    }

    // MARK: - Conversational filler (field bug, 2026-08-28)

    /// Whisper's lowercase sentence runs make NLTagger class 'yeah' as a NOUN
    /// (and swallow the following period into the token), so the noun-only
    /// restriction does not stop it: the real device produced 'yeah' / 'yeah.'
    /// as a recurring theme across three walks.
    private let fillerText = "so i was walking. yeah. and then i stopped by the water. yeah. it was " +
        "fine. yeah. and i kept on going for a while. yeah. and then home. yeah. that was it."

    func testFillerRun_yieldsNoThemes() {
        XCTAssertTrue(ThemeExtractor.themes(in: fillerText, languageCode: "en").isEmpty,
                      "conversational filler is not what a walk was about")
    }

    func testHesitationRun_yieldsNoThemes() {
        let text = "hmm. i was out again. hmm. the wind was up and the light was going. hmm. i " +
            "turned back before dark. hmm. that was the whole of it really. hmm."
        XCTAssertTrue(ThemeExtractor.themes(in: text, languageCode: "en").isEmpty)
    }

    func testNounAmongFiller_isTheOnlyTheme() {
        let text = fillerText + " the river was high. the river was high again. i thought about the river."
        XCTAssertEqual(ThemeExtractor.themes(in: text, languageCode: "en").map(\.lemma), ["river"])
    }

    /// The chip and the dossier both print `displayTerm`; a theme identity or
    /// a printed term carrying a period is the punctuation defect one layer
    /// out, whatever produced it.
    func testThemeIdentityAndDisplayTerm_carryOnlyLetters() {
        let text = fillerText + " the river was high. the river was high again. i thought about the river."
        for theme in ThemeExtractor.themes(in: text, languageCode: "en") {
            XCTAssertTrue(theme.lemma.allSatisfy(\.isLetter), "theme lemma '\(theme.lemma)'")
            XCTAssertTrue(theme.displayTerm.allSatisfy(\.isLetter), "displayTerm '\(theme.displayTerm)'")
        }
    }

    // MARK: - lightNouns gate: time/times/person/people/app/apps

    /// Observed as live themes on the same real-device history one pass
    /// before the filler ones surfaced. NLTagger folds `people` → `person`
    /// and `times` → `time`, so the lemma forms are what the filter sees.
    func testTimeAndPeople_stoplisted_yieldNoThemes() {
        let text = "the people were kind and the people walked with me for a time. i met a person " +
            "by the water and the person spoke of time. time after time the people came back. " +
            "the times were strange."
        XCTAssertTrue(ThemeExtractor.themes(in: text, languageCode: "en").isEmpty)
    }

    /// 'app' is the walker talking about Pilgrim itself — meta-noise, never a
    /// life theme.
    func testApp_stoplisted_yieldsNoThemes() {
        let text = "i opened the app again and the app was slow. the apps on this phone are all " +
            "slow. i keep opening the app when i should be looking at the water. apps and apps and apps."
        XCTAssertTrue(ThemeExtractor.themes(in: text, languageCode: "en").isEmpty)
    }

    func testNounAmongGenericNouns_isTheOnlyTheme() {
        let text = "i keep thinking about the harbor when the people are around. the harbor at that " +
            "time of year. person after person passes the harbor and the app is open in my hand. " +
            "the harbor. apps and time."
        XCTAssertEqual(ThemeExtractor.themes(in: text, languageCode: "en").map(\.lemma), ["harbor"])
    }
}
