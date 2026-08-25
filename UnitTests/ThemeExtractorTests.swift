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
}
