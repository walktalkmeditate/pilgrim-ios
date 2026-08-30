import XCTest
import NaturalLanguage
@testable import Pilgrim

/// Shared transcript fixtures for the `firstVersusLast` gate, which now
/// carries floors on both branches: the pace branch needs
/// `minimumWordsToJudgePace` words on each side, the subject branch
/// `minimumLemmasToJudgeSubject` content lemmas. Short throwaway lines no
/// longer reach either branch, so the fixtures have to be walk-sized.
enum DirectiveFixtures {
    static let heavyOpening = "Setting out heavy this morning, the pack digging into both shoulders, "
        + "the road ahead grey and long, and my legs already complaining about the hill still ahead of me."
    static let lighterClosing = "Coming home lighter now, the pack somehow easier, the same road under "
        + "my feet but shorter, and the evening air cool against my face as the town appears."

    /// ~17 content lemmas, zero overlap with `familyDebt`.
    static let gardenWall = "The garden hedge grows beside the stone wall near the orchard gate, where "
        + "old apple trees drop ripe fruit onto the wet grass beneath the crooked fence."
    /// ~15 content lemmas, zero overlap with `gardenWall`.
    static let familyDebt = "My brother telephoned about the mortgage payment, the lawyer's invoice, "
        + "unpaid council tax, and a solicitor's letter concerning my late father's estate and the empty house."
    /// Spoken scaffolding only — every lemma here is in
    /// `SpokenStoplist.scaffoldLemmas`, so it carries no subject at all
    /// despite clearing a raw-lemma count of eighteen.
    static let scaffoldingOnly = "I think I know what you mean, and I want to go and see. Let me take it. "
        + "I feel we should keep it. I could say it might be the kind of thing we would need."
    /// A closing note padded with the words the theme layer already calls
    /// meaningless. Nine carry real subject; the rest are `filler` and
    /// `lightNouns` — 'okay', 'yeah', 'nothing', 'people', 'area', 'one',
    /// 'time', 'app'. Under `scaffoldLemmas` alone it counts fifteen and
    /// clears `minimumLemmasToJudgeSubject`; under the shared content-word
    /// definition it counts ten and does not.
    static let paddedClosing = "Okay. Nothing much today, yeah. People pass by in this area, one at a "
        + "time. The app pinged. Anyway, my brother telephoned about the mortgage payment and the lawyer's invoice."
    /// Long enough to be detected as Spanish, short of nothing else.
    static let spanishOpening = "Esta mañana caminé por el sendero del huerto, junto al muro de piedra, "
        + "mirando los manzanos viejos y la hierba mojada bajo la valla torcida del jardín."
}

/// `firstVersusLast` used to fire on every walk with two recordings and
/// presuppose its own conclusion — told to measure what changed, the model
/// finds change, including on walks where nothing did. These tests pin the
/// gated behaviour: it fires only on a pace shift (free from
/// `wordsPerMinute`) or a subject that genuinely diverged (two bounded
/// lemma passes, never one per recording).
final class AttentionDirectivesFirstVersusLastTests: XCTestCase {

    private static let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)

    private func recording(_ text: String, wpm: Double?, minutesIn: Int) -> RecordingContext {
        RecordingContext(
            text: text,
            timestamp: Self.start.addingTimeInterval(TimeInterval(minutesIn * 60)),
            startCoordinate: nil,
            endCoordinate: nil,
            wordsPerMinute: wpm,
            recordingUUID: UUID(),
            endTimestamp: nil
        )
    }

    private func directives(_ recordings: [RecordingContext]) -> [String] {
        AttentionDirectives.detect(
            context: .make(recordings: recordings, startDate: Self.start),
            detectedLanguageCode: "en"
        )
    }

    private func isFirstVersusLast(_ line: String) -> Bool {
        line.contains("attend to what moved between them")
    }

    func testFirstVersusLast_sameSubjectSamePace_staysSilent() {
        let lines = directives([
            recording(DirectiveFixtures.gardenWall, wpm: 100, minutesIn: 0),
            recording(DirectiveFixtures.gardenWall, wpm: 102, minutesIn: 20)
        ])
        XCTAssertFalse(lines.contains(where: isFirstVersusLast))
    }

    func testFirstVersusLast_paceShift_fires() {
        let lines = directives([
            recording(DirectiveFixtures.gardenWall, wpm: 100, minutesIn: 0),
            recording(DirectiveFixtures.gardenWall, wpm: 140, minutesIn: 20)
        ])
        XCTAssertTrue(lines.contains { isFirstVersusLast($0) && $0.contains("faster") })
    }

    func testFirstVersusLast_paceSlowed_namesSlower() {
        let lines = directives([
            recording(DirectiveFixtures.gardenWall, wpm: 140, minutesIn: 0),
            recording(DirectiveFixtures.gardenWall, wpm: 100, minutesIn: 20)
        ])
        XCTAssertTrue(lines.contains { isFirstVersusLast($0) && $0.contains("more slowly") })
    }

    /// A very short opening note makes `wordsPerMinute` meaningless — a
    /// handful of words timed over a couple of seconds clears a 15% relative
    /// delta on nothing but rounding. The pace branch carries its own word
    /// floor for the same reason the subject branch carries a lemma floor.
    func testFirstVersusLast_paceSwingOnTwoShortNotes_staysSilent() {
        let lines = directives([
            recording("Setting out heavy.", wpm: 100, minutesIn: 0),
            recording("Coming home lighter.", wpm: 140, minutesIn: 20)
        ])
        XCTAssertFalse(lines.contains(where: isFirstVersusLast),
                       "two three-word notes cannot carry a speaking-rate claim")
    }

    func testFirstVersusLast_subjectDiverged_fires() throws {
        try XCTSkipUnless(NLAssetAvailability.lemmaAvailable,
                          "no NL lemma model is available on this runner; the lemma layer is " +
                          "unvalidated here — the device harness is the real gate for it")
        let lines = directives([
            recording(DirectiveFixtures.gardenWall, wpm: 100, minutesIn: 0),
            recording(DirectiveFixtures.familyDebt, wpm: 101, minutesIn: 20)
        ])
        XCTAssertTrue(lines.contains { isFirstVersusLast($0) && $0.contains("shares little vocabulary") })
    }

    func testFirstVersusLast_tooFewLemmasToJudge_staysSilent() {
        let lines = directives([
            recording("yes", wpm: 100, minutesIn: 0),
            recording("no", wpm: 101, minutesIn: 20)
        ])
        XCTAssertFalse(lines.contains(where: isFirstVersusLast))
    }

    /// A sign-off is not a subject. It clears the old five-lemma floor
    /// comfortably and shares nothing with a long opening, so the overlap
    /// coefficient reads zero and the directive fired — telling the model to
    /// find meaning in "heading back down the hill".
    func testFirstVersusLast_shortSignOffAfterLongOpening_staysSilent() {
        let lines = directives([
            recording(DirectiveFixtures.gardenWall, wpm: nil, minutesIn: 0),
            recording("Okay, that is everything for now — heading back down the hill, tired but glad.",
                      wpm: nil, minutesIn: 40)
        ])
        XCTAssertFalse(lines.contains(where: isFirstVersusLast),
                       "a closing sign-off carries too little subject to judge divergence against")
    }

    /// `recurringWord` already filters `SpokenStoplist.scaffoldLemmas`; the
    /// subject branch did not, so a recording made entirely of spoken
    /// scaffolding counted eighteen "lemmas" and cleared the floor on words
    /// that carry no subject at all.
    func testFirstVersusLast_scaffoldingOnlyClosing_staysSilent() {
        let lines = directives([
            recording(DirectiveFixtures.gardenWall, wpm: nil, minutesIn: 0),
            recording(DirectiveFixtures.scaffoldingOnly, wpm: nil, minutesIn: 40)
        ])
        XCTAssertFalse(lines.contains(where: isFirstVersusLast),
                       "spoken scaffolding is not vocabulary the subject can diverge from")
    }

    /// The same shape as `scaffoldingOnlyClosing`, one release later. PR #74
    /// declared conversational filler and a handful of light nouns to be
    /// noise and wired that into theme extraction alone; the subject branch
    /// kept subtracting `scaffoldLemmas` only, so those same words still
    /// counted toward the lemma floor and still sat in the overlap
    /// coefficient's denominator. A padded closing note reached fifteen
    /// "content" lemmas on ten words of subject and fired "shares little
    /// vocabulary" on a walk whose closing note said almost nothing.
    func testFirstVersusLast_closingPaddedWithFillerAndLightNouns_staysSilent() {
        let lines = directives([
            recording(DirectiveFixtures.gardenWall, wpm: nil, minutesIn: 0),
            recording(DirectiveFixtures.paddedClosing, wpm: nil, minutesIn: 40)
        ])
        XCTAssertFalse(lines.contains(where: isFirstVersusLast),
                       "'okay', 'yeah', 'people', 'area' and 'app' are not vocabulary a subject can diverge from")
    }

    /// A walker who opens in one language and closes in another has not
    /// changed subject — the lemma sets simply cannot be compared. Whichever
    /// guard catches it first (no lemma model for the second language, or the
    /// two detected codes differing), the directive must stay silent.
    func testFirstVersusLast_bilingualWalk_staysSilent() {
        let lines = directives([
            recording(DirectiveFixtures.gardenWall, wpm: nil, minutesIn: 0),
            recording(DirectiveFixtures.spanishOpening, wpm: nil, minutesIn: 40)
        ])
        XCTAssertFalse(lines.contains(where: isFirstVersusLast),
                       "a language switch is not a subject shift")
    }

    /// The subject branch is only meaningful where NLTagger has a real lemma
    /// model. Without one, `TranscriptNLP.contentLemmas` falls back to the
    /// lowercased surface form, so every inflection of the same word counts
    /// as a distinct lemma and overlap is depressed systematically — an
    /// inflected language would read as permanent divergence.
    func testLemmatizableLanguage_englishTranscript_resolves() throws {
        try XCTSkipUnless(NLAssetAvailability.lemmaAvailable,
                          "no NL lemma model is available on this runner; the lemma layer is " +
                          "unvalidated here — the device harness is the real gate for it")
        XCTAssertEqual(AttentionDirectives.lemmatizableLanguage(of: DirectiveFixtures.gardenWall), "en")
    }

    func testLemmatizableLanguage_languageWithoutALemmaModel_returnsNil() throws {
        let spanish = NLTagger.availableTagSchemes(for: .word, language: .spanish)
        try XCTSkipUnless(!spanish.contains(.lemma),
                          "this OS ships a Spanish lemma model, so Spanish is a legitimate subject language here")
        XCTAssertNil(AttentionDirectives.lemmatizableLanguage(of: DirectiveFixtures.spanishOpening))
    }

    func testLemmatizableLanguage_unrecognizableText_returnsNil() {
        XCTAssertNil(AttentionDirectives.lemmatizableLanguage(of: "..."))
    }

    func testFirstVersusLast_missingPaceAndSameSubject_staysSilent() {
        let lines = directives([
            recording(DirectiveFixtures.gardenWall, wpm: nil, minutesIn: 0),
            recording(DirectiveFixtures.gardenWall, wpm: nil, minutesIn: 20)
        ])
        XCTAssertFalse(lines.contains(where: isFirstVersusLast))
    }

    func testFirstVersusLast_singleRecording_staysSilent() {
        let lines = directives([
            recording(DirectiveFixtures.gardenWall, wpm: 100, minutesIn: 0)
        ])
        XCTAssertFalse(lines.contains(where: isFirstVersusLast))
    }

    /// Regression for the Jaccard length-asymmetry bug: when the last
    /// recording's vocabulary is a strict subset of the first's — a short
    /// closing note that only repeats words already spoken at length — the
    /// subject has not diverged at all, but Jaccard (`intersection / union`)
    /// collapses to `|smaller| / |larger|` and can cross the ceiling anyway.
    /// Here the first recording carries ~32 unique content lemmas and the
    /// closing note's ~14 are all drawn from that set: Jaccard would be
    /// 14/32 ≈ 0.44 — but on the original 6-lemma note it read 6/32 ≈ 0.19,
    /// under the 0.20 ceiling, so the old computation fired "shares little
    /// vocabulary" on a walk that never left its subject. The closing note is
    /// sized to clear `minimumLemmasToJudgeSubject` so this still exercises
    /// the overlap computation rather than passing on the floor. The overlap
    /// coefficient (`intersection / min(|first|, |last|)`) is 1.0 here,
    /// correctly silent.
    func testFirstVersusLast_lastRecordingSubsetOfFirst_staysSilent() {
        let openingReflection = """
        I started down the garden path early this morning, past the stone \
        wall and under the old oak trees, thinking about my mother and the \
        letters she used to write, the garden she tended for thirty years, \
        the roses along the fence, the smell of rain on the hedges, and how \
        the light falls differently now that autumn is coming, the leaves \
        turning gold and copper along the orchard gate near the pond.
        """
        let closingNote = "The garden path, the stone wall, the orchard gate, the old oak trees, "
            + "my mother's letters, the roses, the hedges, the pond again."
        let lines = directives([
            recording(openingReflection, wpm: nil, minutesIn: 0),
            recording(closingNote, wpm: nil, minutesIn: 45)
        ])
        XCTAssertFalse(lines.contains(where: isFirstVersusLast),
                       "a closing note that only repeats the opening's own vocabulary is the same subject, not a divergent one")
    }

    // MARK: - Guard paths (firstPace == 0, asymmetric nil wordsPerMinute)

    /// `firstPace > 0` guards the pace branch's division. Without it,
    /// `firstPace == 0` would divide by zero (`(lastPace - 0) / 0`), which
    /// in Swift's floating-point arithmetic produces `.infinity` rather than
    /// trapping — `abs(change) >= paceShiftThreshold` would then be
    /// trivially true and fire a bogus pace claim on every walk with a
    /// zero-wpm first recording. Must fall through to the subject branch
    /// instead, which — using the same divergent-subject fixture as
    /// `testFirstVersusLast_subjectDiverged_fires` — genuinely fires here.
    func testFirstVersusLast_firstPaceZero_fallsThroughToSubjectBranch() throws {
        try XCTSkipUnless(NLAssetAvailability.lemmaAvailable,
                          "no NL lemma model is available on this runner; the lemma layer is " +
                          "unvalidated here — the device harness is the real gate for it")
        let lines = directives([
            recording(DirectiveFixtures.gardenWall, wpm: 0, minutesIn: 0),
            recording(DirectiveFixtures.familyDebt, wpm: 101, minutesIn: 20)
        ])
        XCTAssertTrue(lines.contains { isFirstVersusLast($0) && $0.contains("shares little vocabulary") },
                      "firstPace == 0 must not fire a pace claim from a divide-by-zero; it must fall through to subject")
    }

    /// `wordsPerMinute` is persisted asynchronously and is nil on the
    /// walk-recovery path, so an asymmetric nil (one recording has a value,
    /// the other doesn't) is a live production shape, not an edge case.
    /// `if let firstPace = ..., let lastPace = ...` must fail closed on
    /// either side and fall through to the subject branch.
    func testFirstVersusLast_lastPaceMissing_fallsThroughToSubjectBranch() throws {
        try XCTSkipUnless(NLAssetAvailability.lemmaAvailable,
                          "no NL lemma model is available on this runner; the lemma layer is " +
                          "unvalidated here — the device harness is the real gate for it")
        let lines = directives([
            recording(DirectiveFixtures.gardenWall, wpm: 100, minutesIn: 0),
            recording(DirectiveFixtures.familyDebt, wpm: nil, minutesIn: 20)
        ])
        XCTAssertTrue(lines.contains { isFirstVersusLast($0) && $0.contains("shares little vocabulary") },
                      "a missing last-recording pace must fall through to subject, not crash or stay silent")
    }

    func testFirstVersusLast_firstPaceMissing_fallsThroughToSubjectBranch() throws {
        try XCTSkipUnless(NLAssetAvailability.lemmaAvailable,
                          "no NL lemma model is available on this runner; the lemma layer is " +
                          "unvalidated here — the device harness is the real gate for it")
        let lines = directives([
            recording(DirectiveFixtures.gardenWall, wpm: nil, minutesIn: 0),
            recording(DirectiveFixtures.familyDebt, wpm: 100, minutesIn: 20)
        ])
        XCTAssertTrue(lines.contains { isFirstVersusLast($0) && $0.contains("shares little vocabulary") },
                      "a missing first-recording pace must fall through to subject, not crash or stay silent")
    }
}
