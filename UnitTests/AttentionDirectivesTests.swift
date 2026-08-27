import XCTest
import NaturalLanguage
@testable import Pilgrim

/// The assembler injects a dossier of context; attention directives turn it
/// into pursuit — deterministic pattern detection that tells the downstream
/// model what is remarkable about *this* walk. Each detector must fire only
/// when its pattern is genuinely present.
final class AttentionDirectivesTests: XCTestCase {

    private let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)

    private func recording(_ text: String, offset: TimeInterval = 300, wpm: Double? = nil) -> RecordingContext {
        RecordingContext(
            text: text,
            timestamp: start.addingTimeInterval(offset),
            startCoordinate: nil,
            endCoordinate: nil,
            wordsPerMinute: wpm
        )
    }

    private func joined(_ context: ActivityContext) -> String {
        AttentionDirectives.detect(context: context).joined(separator: "\n")
    }

    // MARK: - Pace shift

    func testPaceShift_slowingFinalThird_fires() {
        let speeds = Array(repeating: 1.5, count: 20) + Array(repeating: 1.2, count: 20) + Array(repeating: 0.9, count: 20)
        let context = ActivityContext.make(startDate: start, routeSpeeds: speeds)
        XCTAssertTrue(joined(context).contains("slowed"))
    }

    func testPaceShift_uniformPace_doesNotFire() {
        let context = ActivityContext.make(startDate: start, routeSpeeds: Array(repeating: 1.4, count: 60))
        XCTAssertFalse(joined(context).contains("slowed"))
        XCTAssertFalse(joined(context).contains("quickened"))
    }

    // MARK: - Stillness

    func testStillness_longStillRunWithoutMeditation_fires() {
        let speeds = Array(repeating: 1.4, count: 40) + Array(repeating: 0.0, count: 20) + Array(repeating: 1.4, count: 40)
        let context = ActivityContext.make(duration: 3600, startDate: start, routeSpeeds: speeds)
        XCTAssertTrue(joined(context).contains("stillness"))
    }

    func testStillness_coveredByMeditation_doesNotFire() {
        let speeds = Array(repeating: 1.4, count: 40) + Array(repeating: 0.0, count: 20) + Array(repeating: 1.4, count: 40)
        let meditation = MeditationContext(
            startDate: start.addingTimeInterval(600),
            endDate: start.addingTimeInterval(1500),
            duration: 900
        )
        let context = ActivityContext.make(
            meditations: [meditation], duration: 3600, startDate: start, routeSpeeds: speeds
        )
        XCTAssertFalse(joined(context).contains("stillness"),
                       "stillness explained by a logged meditation is not news")
    }

    func testStillness_coveredByRecordedPause_doesNotFire() {
        let speeds = Array(repeating: 1.4, count: 40) + Array(repeating: 0.0, count: 20) + Array(repeating: 1.4, count: 40)
        let pause = PauseContext(startDate: start.addingTimeInterval(600), duration: 900)
        let context = ActivityContext.make(
            duration: 3600, startDate: start, routeSpeeds: speeds, pauses: [pause]
        )
        XCTAssertFalse(joined(context).contains("stillness"),
                       "stillness explained by a recorded pause is not news — the Pauses line already tells it")
    }

    func testStillness_invalidNegativeSpeeds_doNotCountAsStillness() {
        let speeds = Array(repeating: 1.4, count: 40) + Array(repeating: -1.0, count: 20) + Array(repeating: 1.4, count: 40)
        let context = ActivityContext.make(duration: 3600, startDate: start, routeSpeeds: speeds)
        XCTAssertFalse(joined(context).contains("stillness"),
                       "negative speeds are invalid GPS fixes, not a still walker")
    }

    // MARK: - Intention echo

    func testIntentionEcho_intentionWordSpoken_fires() {
        let context = ActivityContext.make(
            recordings: [recording("I keep coming back to release, letting the grip soften")],
            startDate: start,
            intention: "Release what I cannot carry"
        )
        XCTAssertTrue(joined(context).contains("surfaces again"))
    }

    func testIntentionEcho_inflectedSurface_quotesSpokenFormWithoutAgain() {
        let context = ActivityContext.make(
            recordings: [recording("worrying through the pines")],
            startDate: start,
            intention: "worry less"
        )
        let text = joined(context)
        XCTAssertTrue(text.contains("'worrying' surfaces in"),
                      "the echo must quote what the walker actually said")
        XCTAssertFalse(text.contains("surfaces again"),
                       "'again' is only honest for an exact surface repeat")
    }

    func testIntentionEcho_mixedInflections_prefersExactSurfaceAcrossMentions() {
        let context = ActivityContext.make(
            recordings: [recording("worrying on the way out, but the worry itself eased by the bridge")],
            startDate: start,
            intention: "worry less"
        )
        let text = joined(context)
        XCTAssertTrue(text.contains("'worry' surfaces again"),
                      "an exact surface repeat anywhere in the spoken mentions earns 'again', "
                      + "even when an inflection appears first")
        XCTAssertFalse(text.contains("'worrying' surfaces"),
                       "the exact match outranks the earlier inflected mention")
    }

    func testIntentionEcho_noOverlap_doesNotFire() {
        let context = ActivityContext.make(
            recordings: [recording("The bakery smelled wonderful this morning")],
            startDate: start,
            intention: "Release what I cannot carry"
        )
        XCTAssertFalse(joined(context).contains("surfaces again"))
    }

    // MARK: - Recurring word

    func testRecurringWord_wordReturnsThreeTimes_fires() {
        let context = ActivityContext.make(
            recordings: [
                recording("The river was high today"),
                recording("I crossed the river at the old bridge", offset: 900),
                recording("Something about the river keeps pulling me", offset: 1500)
            ],
            startDate: start
        )
        XCTAssertTrue(joined(context).contains("river"))
        XCTAssertTrue(joined(context).contains("returns"))
    }

    func testRecurringWord_allWordsUnique_doesNotFire() {
        let context = ActivityContext.make(
            recordings: [recording("Cold wind moving between bare branches")],
            startDate: start
        )
        XCTAssertFalse(joined(context).contains("returns"))
    }

    // MARK: - First vs last recording
    //
    // Full behavioural coverage (pace shift, subject divergence, and the
    // silent cases) lives in AttentionDirectivesFirstVersusLastTests below —
    // gated per PR (task 3 of the oblique-voice plan): the directive used to
    // fire unconditionally on any walk with two recordings, presupposing
    // its own conclusion. These two just confirm the assembler wiring.

    func testFirstVersusLast_paceShiftBetweenRecordings_fires() {
        let context = ActivityContext.make(
            recordings: [
                recording("Setting out heavy", wpm: 100),
                recording("Coming home lighter", offset: 3000, wpm: 140)
            ],
            startDate: start
        )
        XCTAssertTrue(joined(context).contains("attend to what moved between them"))
    }

    func testFirstVersusLast_singleRecording_doesNotFire() {
        let context = ActivityContext.make(
            recordings: [recording("Just one thought today")],
            startDate: start
        )
        XCTAssertFalse(joined(context).contains("attend to what moved between them"))
    }

    // MARK: - Cap and assembly

    func testDirectives_cappedAtFour() {
        let speeds = Array(repeating: 1.5, count: 30)
            + Array(repeating: 0.0, count: 30)
            + Array(repeating: 0.8, count: 30)
        let context = ActivityContext.make(
            recordings: [
                recording("Release the river from its banks", wpm: 100),
                recording("The river again, release again", offset: 900),
                recording("Still the river", offset: 1500, wpm: 150)
            ],
            duration: 3600,
            startDate: start,
            routeSpeeds: speeds,
            intention: "Release what I cannot carry"
        )
        // Five detectors have something to fire here (stillness, pace shift,
        // intention echo, recurring word, and first-vs-last via the 50% wpm
        // change) — the cap must still hold at four.
        XCTAssertLessThanOrEqual(AttentionDirectives.detect(context: context).count, 4)
    }

    func testAssembler_includesSectionOnlyWhenDirectivesFire() {
        let quiet = ActivityContext.make(startDate: start)
        let quietPrompt = PromptGenerator.generate(style: .reflective, context: quiet)
        XCTAssertFalse(quietPrompt.text.contains("**Attend to:**"))

        let telling = ActivityContext.make(
            recordings: [recording("Setting out", wpm: 100), recording("Returning", offset: 3000, wpm: 140)],
            startDate: start
        )
        let tellingPrompt = PromptGenerator.generate(style: .reflective, context: telling)
        XCTAssertTrue(tellingPrompt.text.contains("**Attend to:**"))
    }

    // MARK: - Semantic upgrade (Thought Threads Stage 1)

    func testIntentionEcho_lemmaVariantFires() throws {
        try XCTSkipIf(NLEmbedding.wordEmbedding(for: .english) == nil,
                      "word embeddings unavailable in this environment")
        let context = ActivityContext.make(
            recordings: [recording("I have been grieving all morning on this path")],
            startDate: start,
            intention: "sit with grief"
        )
        XCTAssertTrue(joined(context).contains("intention spoke of"))
    }

    func testIntentionEcho_sharedLemmaFires() {
        let context = ActivityContext.make(
            recordings: [recording("walking my worry out under the pines")],
            startDate: start,
            intention: "worry less"
        )
        XCTAssertTrue(joined(context).contains("intention spoke of"))
    }

    func testRecurringWord_countsAcrossInflections() {
        let context = ActivityContext.make(
            recordings: [recording("Moving is hard. We moved before. This move feels different.")],
            startDate: start
        )
        XCTAssertTrue(joined(context).contains("returns 3 times"))
    }

    func testRecurringWord_ignoresFunctionWordsWithoutStoplist() {
        let context = ActivityContext.make(
            recordings: [recording("because because because because the the the the")],
            startDate: start
        )
        XCTAssertFalse(joined(context).contains("returns"))
    }

    /// Field-confirmed bug: "think" is a light/modal verb NLTagger tags as
    /// content — it dominated raw-frequency counts on real devices without
    /// carrying any meaning. `SpokenStoplist.scaffoldLemmas` excludes it.
    func testRecurringWord_scaffoldVerb_doesNotFire() {
        let context = ActivityContext.make(
            recordings: [recording("I think I think I think I think about it")],
            startDate: start
        )
        XCTAssertFalse(joined(context).contains("returns"))
    }

    /// Design decision (modal-lean spec): modal verbs are a STATE signal
    /// that belongs in the markers channel with word identity, never in the
    /// recurring-word TOPIC channel — a flat walk's "can ×57" is noise
    /// there, not a theme ("the verb of the hollow" made it work once; it
    /// doesn't generalize). `SpokenStoplist.scaffoldLemmas` now excludes all
    /// six modal families.
    func testRecurringWord_modalVerb_doesNotFire() {
        let context = ActivityContext.make(
            recordings: [recording("I can do it. You can too. We can go now. It can work.")],
            startDate: start
        )
        XCTAssertFalse(joined(context).contains("returns"))
    }
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
        let text = "the garden hedge grows beside the stone wall near the orchard gate"
        let lines = directives([
            recording(text, wpm: 100, minutesIn: 0),
            recording(text, wpm: 102, minutesIn: 20)
        ])
        XCTAssertFalse(lines.contains(where: isFirstVersusLast))
    }

    func testFirstVersusLast_paceShift_fires() {
        let text = "the garden hedge grows beside the stone wall near the orchard gate"
        let lines = directives([
            recording(text, wpm: 100, minutesIn: 0),
            recording(text, wpm: 140, minutesIn: 20)
        ])
        XCTAssertTrue(lines.contains { isFirstVersusLast($0) && $0.contains("faster") })
    }

    func testFirstVersusLast_paceSlowed_namesSlower() {
        let text = "the garden hedge grows beside the stone wall near the orchard gate"
        let lines = directives([
            recording(text, wpm: 140, minutesIn: 0),
            recording(text, wpm: 100, minutesIn: 20)
        ])
        XCTAssertTrue(lines.contains { isFirstVersusLast($0) && $0.contains("more slowly") })
    }

    func testFirstVersusLast_subjectDiverged_fires() {
        let lines = directives([
            recording("the garden hedge grows beside the stone wall near the orchard gate",
                      wpm: 100, minutesIn: 0),
            recording("my brother telephoned about the mortgage payment and the lawyer's invoice",
                      wpm: 101, minutesIn: 20)
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

    func testFirstVersusLast_missingPaceAndSameSubject_staysSilent() {
        let text = "the garden hedge grows beside the stone wall near the orchard gate"
        let lines = directives([
            recording(text, wpm: nil, minutesIn: 0),
            recording(text, wpm: nil, minutesIn: 20)
        ])
        XCTAssertFalse(lines.contains(where: isFirstVersusLast))
    }

    func testFirstVersusLast_singleRecording_staysSilent() {
        let lines = directives([
            recording("the garden hedge grows beside the stone wall", wpm: 100, minutesIn: 0)
        ])
        XCTAssertFalse(lines.contains(where: isFirstVersusLast))
    }

    /// Regression for the Jaccard length-asymmetry bug: when the last
    /// recording's vocabulary is a strict subset of the first's — a short
    /// closing note that only repeats words already spoken at length — the
    /// subject has not diverged at all, but Jaccard (`intersection / union`)
    /// collapses to `|smaller| / |larger|` and can cross the ceiling anyway.
    /// Here the first recording carries 32 unique content lemmas and the
    /// closing note's 6 are all drawn from that set: Jaccard would be
    /// 6/32 ≈ 0.19 — under the 0.20 ceiling, so the old computation fired
    /// "shares little vocabulary" on a walk that never left its subject. The
    /// overlap coefficient (`intersection / min(|first|, |last|)`) is 1.0
    /// here, correctly silent.
    func testFirstVersusLast_lastRecordingSubsetOfFirst_staysSilent() {
        let openingReflection = """
        I started down the garden path early this morning, past the stone \
        wall and under the old oak trees, thinking about my mother and the \
        letters she used to write, the garden she tended for thirty years, \
        the roses along the fence, the smell of rain on the hedges, and how \
        the light falls differently now that autumn is coming, the leaves \
        turning gold and copper along the orchard gate near the pond.
        """
        let closingNote = "The garden path, the stone wall, the orchard gate again."
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
    func testFirstVersusLast_firstPaceZero_fallsThroughToSubjectBranch() {
        let lines = directives([
            recording("the garden hedge grows beside the stone wall near the orchard gate",
                      wpm: 0, minutesIn: 0),
            recording("my brother telephoned about the mortgage payment and the lawyer's invoice",
                      wpm: 101, minutesIn: 20)
        ])
        XCTAssertTrue(lines.contains { isFirstVersusLast($0) && $0.contains("shares little vocabulary") },
                      "firstPace == 0 must not fire a pace claim from a divide-by-zero; it must fall through to subject")
    }

    /// `wordsPerMinute` is persisted asynchronously and is nil on the
    /// walk-recovery path, so an asymmetric nil (one recording has a value,
    /// the other doesn't) is a live production shape, not an edge case.
    /// `if let firstPace = ..., let lastPace = ...` must fail closed on
    /// either side and fall through to the subject branch.
    func testFirstVersusLast_lastPaceMissing_fallsThroughToSubjectBranch() {
        let lines = directives([
            recording("the garden hedge grows beside the stone wall near the orchard gate",
                      wpm: 100, minutesIn: 0),
            recording("my brother telephoned about the mortgage payment and the lawyer's invoice",
                      wpm: nil, minutesIn: 20)
        ])
        XCTAssertTrue(lines.contains { isFirstVersusLast($0) && $0.contains("shares little vocabulary") },
                      "a missing last-recording pace must fall through to subject, not crash or stay silent")
    }

    func testFirstVersusLast_firstPaceMissing_fallsThroughToSubjectBranch() {
        let lines = directives([
            recording("the garden hedge grows beside the stone wall near the orchard gate",
                      wpm: nil, minutesIn: 0),
            recording("my brother telephoned about the mortgage payment and the lawyer's invoice",
                      wpm: 100, minutesIn: 20)
        ])
        XCTAssertTrue(lines.contains { isFirstVersusLast($0) && $0.contains("shares little vocabulary") },
                      "a missing first-recording pace must fall through to subject, not crash or stay silent")
    }
}
