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
}
