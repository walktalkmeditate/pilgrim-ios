import XCTest
@testable import Pilgrim

final class MarkerAnalyzerTests: XCTestCase {

    func testAbsolutistCount_exact() {
        let pack = MarkerAnalyzer.compute(
            text: "I always ruin everything. It never works. Never.",
            languageCode: "en"
        )
        XCTAssertEqual(pack?.absolutistCount, 4)  // always, everything, never, never
    }

    func testFirstPersonCount_exact() {
        let pack = MarkerAnalyzer.compute(text: "I told myself my worry is mine to carry", languageCode: "en")
        XCTAssertEqual(pack?.firstPersonCount, 4)  // i, myself, my, mine
    }

    func testInsightAndCausation() {
        let pack = MarkerAnalyzer.compute(
            text: "I realize now it happened because I never rested",
            languageCode: "en"
        )
        XCTAssertEqual(pack?.insightCount, 1)
        XCTAssertEqual(pack?.causationCount, 1)
    }

    func testTemporalLean_future() {
        let pack = MarkerAnalyzer.compute(
            text: "Tomorrow I will call her. I will plan the trip. Soon we will know. It will be fine.",
            languageCode: "en"
        )
        XCTAssertEqual(pack?.temporalLean, "future")
    }

    func testNonEnglish_returnsNil() {
        XCTAssertNil(MarkerAnalyzer.compute(text: "Sigo pensando en la mudanza", languageCode: "es"))
        XCTAssertNil(MarkerAnalyzer.compute(text: "anything", languageCode: nil))
    }

    func testWordCount_lettersOnlyTokens() {
        let pack = MarkerAnalyzer.compute(text: "one two three, four — five!", languageCode: "en")
        XCTAssertEqual(pack?.wordCount, 5)
    }

    /// Field bug: three real recordings with wildly different content all
    /// reported `sentiment -0.60`. Root cause: `NLTagger`'s sentiment model
    /// degrades to a near-constant score once the tagged string passes
    /// roughly 150 words — confirmed by direct measurement, independent of
    /// actual valence. These fixtures are long enough (220+ words) to land
    /// past that threshold, so a regression back to whole-transcript tagging
    /// collapses both to the same score.
    func testSentiment_opposingValence_longTranscripts_produceDifferentScores() {
        let happy = String(repeating: "I am so happy today. The sun is out and everything feels "
            + "wonderful. I love this walk and feel grateful and joyful. ", count: 10)
        let sad = String(repeating: "I am so sad today. Everything feels heavy and I am grieving. "
            + "I hate how things turned out and feel hopeless. ", count: 10)

        let happyPack = MarkerAnalyzer.compute(text: happy, languageCode: "en")
        let sadPack = MarkerAnalyzer.compute(text: sad, languageCode: "en")

        XCTAssertNotEqual(happyPack?.sentiment, sadPack?.sentiment,
                          "two long transcripts with clearly opposite valence must not collapse to the same score")
        XCTAssertGreaterThan(happyPack?.sentiment ?? -99, sadPack?.sentiment ?? 99,
                             "the happier transcript's sentiment must score higher than the sadder one's")
    }

    // MARK: - Modal lean (word-identity, per surface word)

    func testModalFamilies_sixFamiliesWithExactWords() {
        XCTAssertEqual(MarkerLexicons.modalFamilies[.possibility], ["can", "could"])
        XCTAssertEqual(MarkerLexicons.modalFamilies[.obligation], ["should", "must", "ought"])
        XCTAssertEqual(MarkerLexicons.modalFamilies[.counterfactual], ["would"])
        XCTAssertEqual(MarkerLexicons.modalFamilies[.tentative], ["might", "may"])
        XCTAssertEqual(MarkerLexicons.modalFamilies[.intention], ["will"])
        XCTAssertEqual(MarkerLexicons.modalFamilies[.desire], ["want", "need", "wish"])
    }

    func testModalCounts_perSurfaceWord() {
        let pack = MarkerAnalyzer.compute(
            text: "I should call her. I must decide. I should also apologize. Ought I go?",
            languageCode: "en"
        )
        XCTAssertEqual(pack?.modalCounts["should"], 2)
        XCTAssertEqual(pack?.modalCounts["must"], 1)
        XCTAssertEqual(pack?.modalCounts["ought"], 1)
        XCTAssertNil(pack?.modalCounts["would"], "a family member that never occurred is absent, not zero")
    }

    func testModalCounts_nonModalWords_notCounted() {
        let pack = MarkerAnalyzer.compute(text: "The candle can hold canned goods too", languageCode: "en")
        XCTAssertEqual(pack?.modalCounts["can"], 1, "only the standalone word 'can', not substrings inside other words")
    }

    /// A schema-v2 file on disk was written before `modalCounts` existed —
    /// its JSON has no such key. It must still decode (as empty, not throw):
    /// a decode failure would make `loadAllIncludingStaleVersions` silently
    /// drop the file, so the backfill's stale-orphan sweep could never see
    /// or clean it up (see docs/solutions/derived-cache-semantics-are-schema.md).
    func testMarkerPack_decodesLeniently_whenModalCountsKeyMissing() throws {
        let legacyJSON = """
            {"wordCount": 10, "absolutistCount": 1, "firstPersonCount": 1, "insightCount": 0, \
            "causationCount": 0, "discrepancyCount": 0, "futureCount": 0, "pastCount": 0, "sentiment": null}
            """
        let pack = try JSONDecoder().decode(MarkerPack.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(pack.modalCounts, [:])
        XCTAssertEqual(pack.wordCount, 10)
    }
}
