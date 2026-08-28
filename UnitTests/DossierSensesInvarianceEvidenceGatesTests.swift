import XCTest
@testable import Pilgrim

/// Final-review coverage for the two gates that decide whether an invariant
/// has the evidence its sentence claims: `unmovedReturn`'s flatness must be
/// weighted per WALK (the unit its rendered claim names), and the whole
/// invariance track must stay silent until `ThreadsBackfill` has finished,
/// because every invariant is a coverage claim over the walker's whole
/// record. New file, not an addition to `DossierSensesInvarianceTests.swift`
/// — the parent sits at 458 lines against the `file_length` gate of 500, the
/// same split pattern as
/// `DossierSensesInvarianceFrameConstancyCoverageTests.swift` and
/// `DossierSensesInvariancePlaceFrameLockTests.swift`.
extension DossierSensesInvarianceTests {

    private func flatnessInput(
        contexts: [TranscriptContext], thread: WalkThread, backfillComplete: Bool = true
    ) -> DossierSenses.Input {
        DossierSenses.Input(
            currentWalkUUID: UUID(),
            walkStart: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            walkEnd: DateFactory.makeDate(2024, 6, 15, 10, 30, 0),
            totalAscent: 0, elevationSeries: [], photos: [], currentRecordings: [],
            historicalContexts: contexts, threads: [thread],
            backfillComplete: backfillComplete, walkSnapshots: [], recordingTimestamps: [:],
            fixes: [:], moon: nil
        )
    }

    /// A theme with 10 qualifying recordings across 3 walks, split 8/1/1.
    /// Walk A's eight recordings each sit at an absolutist share of .020,
    /// walk B at .028, walk C at .014 — so walk B is genuinely 2x walk C,
    /// which is not "it sounds the same each time" by any reading a walker
    /// would recognize.
    ///
    /// Recording-weighted, the CV over all ten values is ~0.156, under the
    /// 0.20 ceiling: the eight near-identical appearances on one walk drag
    /// the spread down until the real 2x gap between the other two walks
    /// disappears. Walk-weighted — the three per-walk means, which is the
    /// unit the rendered sentence actually names — the CV is ~0.277 and the
    /// signal correctly stays silent.
    private func lopsidedWalkSplit() -> (contexts: [TranscriptContext], thread: WalkThread) {
        let walkA = UUID(), walkB = UUID(), walkC = UUID()
        let recs = (0..<10).map { _ in UUID() }
        // 200 words each: 4 absolutist = .020, 5.6 -> 28/1000 via 1000 words.
        var contexts: [TranscriptContext] = []
        for rec in recs.prefix(8) {
            contexts.append(markerContext(rec, absolutist: 20, firstPerson: 40, sentiment: -0.2, words: 1000))
        }
        contexts.append(markerContext(recs[8], absolutist: 28, firstPerson: 40, sentiment: -0.2, words: 1000))
        contexts.append(markerContext(recs[9], absolutist: 14, firstPerson: 40, sentiment: -0.2, words: 1000))
        let walks = Array(repeating: walkA, count: 8) + [walkB, walkC]
        return (contexts, steadyThread("work", recordings: recs, walks: walks))
    }

    /// The fixture must actually be recording-flat, or the test below proves
    /// nothing about the aggregation — it would just be a fixture that fails
    /// every way of computing it.
    func testUnmovedReturn_lopsidedFixture_isFlatPerRecordingButNotPerWalk() {
        let perRecording = Array(repeating: 0.020, count: 8) + [0.028, 0.014]
        XCTAssertTrue(DossierSensesInvariance.isFlat(perRecording),
                      "the pre-fix, recording-weighted computation passes on this fixture")
        XCTAssertFalse(DossierSensesInvariance.isFlat([0.020, 0.028, 0.014]),
                       "the same evidence, weighted per walk, correctly fails")
    }

    func testUnmovedReturn_eightRecordingsOnOneWalkOutvotingTwoOthers_staysSilent() {
        let fixture = lopsidedWalkSplit()
        XCTAssertNil(
            DossierSensesInvariance.unmovedReturn(
                input: flatnessInput(contexts: fixture.contexts, thread: fixture.thread), suppressed: []
            ),
            "the claim is walk-scoped, so the flatness it rests on must be too"
        )
    }

    /// The same 8/1/1 shape with the two single-recording walks brought into
    /// line: the signal must still be able to fire, or the fix above would
    /// have been a mute button rather than a correction.
    func testUnmovedReturn_lopsidedButGenuinelyFlatAcrossWalks_stillFires() {
        let walkA = UUID(), walkB = UUID(), walkC = UUID()
        let recs = (0..<10).map { _ in UUID() }
        var contexts: [TranscriptContext] = []
        for rec in recs.prefix(8) {
            contexts.append(markerContext(rec, absolutist: 20, firstPerson: 40, sentiment: -0.2, words: 1000))
        }
        contexts.append(markerContext(recs[8], absolutist: 21, firstPerson: 40, sentiment: -0.2, words: 1000))
        contexts.append(markerContext(recs[9], absolutist: 19, firstPerson: 40, sentiment: -0.2, words: 1000))
        let walks = Array(repeating: walkA, count: 8) + [walkB, walkC]
        let thread = steadyThread("work", recordings: recs, walks: walks)
        let line = DossierSensesInvariance.unmovedReturn(
            input: flatnessInput(contexts: contexts, thread: thread), suppressed: []
        )
        XCTAssertEqual(line?.text, "'work' has returned across 3 walks; it sounds the same each time.")
    }

    // MARK: - Backfill gate

    /// A fixture that qualifies on every other count, so the only thing
    /// holding the block silent is `backfillComplete`. Rendered through the
    /// real `evaluateInvariant` dispatch, not the stub — the gate has to
    /// hold for the production path.
    private func fusedFixtureInput(backfillComplete: Bool) -> DossierSenses.Input {
        let walks = [UUID(), UUID(), UUID()]
        let recs = [UUID(), UUID(), UUID()]
        let father = steadyThread("father", recordings: recs, walks: walks)
        let money = steadyThread("money", recordings: [UUID(), UUID(), UUID()], walks: walks)
        return DossierSenses.Input(
            currentWalkUUID: walks[0],
            walkStart: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            walkEnd: DateFactory.makeDate(2024, 6, 15, 10, 30, 0),
            totalAscent: 0, elevationSeries: [], photos: [], currentRecordings: [],
            historicalContexts: [], threads: [father, money],
            backfillComplete: backfillComplete, walkSnapshots: [], recordingTimestamps: [:],
            fixes: [:], moon: nil
        )
    }

    func testInvarianceLines_qualifyingFixture_firesWhenBackfillComplete() {
        let lines = DossierSenses.invarianceLines(input: fusedFixtureInput(backfillComplete: true))
        XCTAssertEqual(lines, ["'father' and 'money' have appeared in the same 3 walks, never apart."])
    }

    /// `ThreadsBackfill` is battery-gated and single-flight, so a
    /// partly-analyzed record is an ordinary state. Every invariant is a
    /// coverage claim ("never apart", "each time", "every walk") and a
    /// coverage claim over a partial record is false about the record it
    /// names — the same gate `ThreadsDossierFormatter` puts on its weaker
    /// origin-date and `Quiet this walk` claims.
    func testInvarianceLines_sameFixture_staysSilentWhileBackfillIncomplete() {
        XCTAssertTrue(DossierSenses.invarianceLines(input: fusedFixtureInput(backfillComplete: false)).isEmpty)
    }

    /// The gate sits above the per-invariant dispatch, so it holds even when
    /// every signal is stubbed to fire — a future signal cannot opt out of
    /// it by being added to `Invariant.allCases`.
    func testInvarianceLines_backfillIncomplete_silencesEvenAStubThatAlwaysFires() {
        let lines = DossierSenses.invarianceLines(
            input: fusedFixtureInput(backfillComplete: false),
            evaluate: { _, _, _ in DossierSenses.SenseLine(text: "always", lemma: nil) }
        )
        XCTAssertTrue(lines.isEmpty)
    }
}
