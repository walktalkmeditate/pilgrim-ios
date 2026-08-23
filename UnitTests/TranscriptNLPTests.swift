import XCTest
import NaturalLanguage
@testable import Pilgrim

final class TranscriptNLPTests: XCTestCase {

    func testDetectLanguage_english() {
        XCTAssertEqual(TranscriptNLP.detectLanguage("I keep thinking about the move and whether we should go"), "en")
    }

    func testDetectLanguage_spanish() {
        XCTAssertEqual(TranscriptNLP.detectLanguage("Sigo pensando en la mudanza y en si deberíamos irnos de aquí"), "es")
    }

    func testContentLemmas_unifiesInflections() {
        let lemmas = TranscriptNLP.contentLemmas(in: "Grieving again today. I grieved all spring.")
        XCTAssertEqual(lemmas.filter { $0 == "grieve" }.count, 2)
    }

    func testContentLemmas_dropsFunctionWords() {
        let lemmas = TranscriptNLP.contentLemmas(in: "the river and the fog were with me")
        XCTAssertFalse(lemmas.contains("the"))
        XCTAssertFalse(lemmas.contains("and"))
        XCTAssertTrue(lemmas.contains("river"))
        XCTAssertTrue(lemmas.contains("fog"))
    }

    func testMentions_carryCharacterOffsets() {
        let text = "fog on the river"
        let mention = TranscriptNLP.contentLemmaMentions(in: text).first { $0.lemma == "river" }
        XCTAssertNotNil(mention)
        let start = text.index(text.startIndex, offsetBy: mention!.start)
        let end = text.index(start, offsetBy: mention!.length)
        XCTAssertEqual(String(text[start..<end]), "river")
    }

    func testRelated_synonymPair() throws {
        try XCTSkipIf(NLEmbedding.wordEmbedding(for: .english) == nil, "word embeddings unavailable in this environment")
        XCTAssertTrue(TranscriptNLP.related("river", "water", languageCode: "en"))
        XCTAssertFalse(TranscriptNLP.related("river", "deadline", languageCode: "en"))
    }

    func testRelated_exactMatchNeedsNoEmbedding() {
        XCTAssertTrue(TranscriptNLP.related("move", "move", languageCode: "zz"))
    }
}
