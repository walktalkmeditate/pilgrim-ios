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

    func testContentLemmas_unifiesInflections() throws {
        try XCTSkipUnless(NLAssetAvailability.lemmaAvailable,
                          "no NL lemma model is available on this runner; the lemma layer is " +
                          "unvalidated here — the device harness is the real gate for it")
        let lemmas = TranscriptNLP.contentLemmas(in: "Grieving again today. I grieved all spring.")
        XCTAssertEqual(lemmas.filter { $0 == "grieve" }.count, 2)
    }

    func testContentLemmas_dropsFunctionWords() throws {
        try XCTSkipUnless(NLAssetAvailability.lemmaAvailable,
                          "no NL lemma model is available on this runner; the lemma layer is " +
                          "unvalidated here — the device harness is the real gate for it")
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

    // MARK: - Punctuation may never reach a lemma (field bug, 2026-08-28)

    /// Whisper writes long lowercase runs, and NLTagger's `.word` unit does
    /// not split a sentence-final period off the word before it when the next
    /// word isn't capitalized — the token range swallows the period and the
    /// token is classed as a content word, so `.omitPunctuation` never sees
    /// it. These are the shapes that produced 'yeah.' as a real-device theme.
    private static let punctuationTrapTexts = [
        "so i was walking. yeah. and then the garden. yeah. it was fine. yeah. okay.",
        "yeah.yeah.yeah. the garden.the garden.",
        "i walked to st. mary. mr. jones was there. yeah. etc. and so on.",
        "i walked 5.5 miles today and it was 5.5 miles",
        "don't the walk's edge isn't it",
        "mm-hmm the well-being of the walk mm-hmm"
    ]

    /// The invariant, independent of which tagger quirk produced it: a lemma
    /// is a word, so every character in it is a letter.
    func testContentLemmaMentions_lemmasCarryOnlyLetters() {
        for text in Self.punctuationTrapTexts {
            for mention in TranscriptNLP.contentLemmaMentions(in: text) {
                XCTAssertTrue(
                    mention.lemma.allSatisfy(\.isLetter),
                    "lemma '\(mention.lemma)' carries a non-letter (from: \(text))"
                )
            }
        }
    }

    /// `surface` becomes the displayed term on the Recurring chips and in the
    /// dossier, so it must be a word too — a chip reading "garden." is the
    /// same defect one layer out.
    func testContentLemmaMentions_surfacesCarryOnlyLetters() {
        for text in Self.punctuationTrapTexts {
            for mention in TranscriptNLP.contentLemmaMentions(in: text) {
                XCTAssertTrue(
                    mention.surface.allSatisfy(\.isLetter),
                    "surface '\(mention.surface)' carries a non-letter (from: \(text))"
                )
            }
        }
    }

    /// The fabricated-invariant shape itself: one spoken word must not become
    /// two lemmas because a period rode along on some of its occurrences.
    /// Here the first "garden." is the glued token and the other two are
    /// bare — under the old fallback that read as 'garden.' ×1 and 'garden'
    /// ×2, two threads where the walker said one word.
    func testContentLemmaMentions_trailingPeriodDoesNotForkTheLemma() throws {
        try XCTSkipUnless(NLAssetAvailability.lemmaAvailable,
                          "no NL lemma model is available on this runner; the lemma layer is " +
                          "unvalidated here — the device harness is the real gate for it")
        let text = "i walked for a while. and then the garden. and i sat in the garden and the garden was quiet."
        let lemmas = TranscriptNLP.contentLemmaMentions(in: text).map(\.lemma)
        XCTAssertEqual(lemmas.filter { $0 == "garden" }.count, 3)
        XCTAssertFalse(lemmas.contains("garden."))
    }

    /// Offsets must still land on the word after the range is narrowed.
    func testMentions_carryCharacterOffsets_afterPunctuationTrim() {
        let text = "so i sat in the garden. yeah. the garden again."
        for mention in TranscriptNLP.contentLemmaMentions(in: text) {
            let start = text.index(text.startIndex, offsetBy: mention.start)
            let end = text.index(start, offsetBy: mention.length)
            XCTAssertEqual(String(text[start..<end]).lowercased(), mention.surface)
        }
    }
}
