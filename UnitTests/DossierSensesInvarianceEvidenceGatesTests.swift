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

    /// A context with no themes and no markers — enough to establish the
    /// recording's analyzed language and nothing else, so a fixture built for
    /// one signal cannot accidentally arm another. Lives here rather than on
    /// the parent class, which sits against the `type_body_length` gate.
    func plainContext(_ uuid: UUID, languageCode: String? = "en") -> TranscriptContext {
        TranscriptContext(
            schemaVersion: TranscriptContext.currentSchemaVersion,
            recordingUUID: uuid, transcriptHash: "h", languageCode: languageCode,
            wordCount: 200, themes: [], markers: nil
        )
    }

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
        let father = steadyThread("father", recordings: [UUID(), UUID(), UUID()], walks: walks)
        let money = steadyThread("money", recordings: [UUID(), UUID(), UUID()], walks: walks)
        let threads = [father, money]
        return DossierSenses.Input(
            currentWalkUUID: walks[0],
            walkStart: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            walkEnd: DateFactory.makeDate(2024, 6, 15, 10, 30, 0),
            totalAscent: 0, elevationSeries: [], photos: [], currentRecordings: [],
            // Markerless English contexts: enough to satisfy the language
            // gate `fusedThemes` reads, not enough to arm any other signal.
            historicalContexts: threads.flatMap(\.appearances).map { plainContext($0.recordingUUID) },
            threads: threads,
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

    // MARK: - Composed block, real signals, production dispatch

    /// Every other `invarianceLines` test drives the stub `evaluate` seam, so
    /// until this one nothing ever built a real MULTI-SIGNAL `Unchanged:`
    /// block out of real signals through the production dispatch — which is
    /// how the `placeFrameLock` denominator bug and the `fusedThemes`
    /// under-reservation both survived a full test suite.
    ///
    /// Two signals, two different themes, one composed block. `fusedThemes`
    /// fires on the identical walk-sets of 'father' and 'money';
    /// `placeFrameLock` fires on 'river', whose three in-window recordings
    /// carry tightly clustered qualifying fixes. `unmovedReturn` must stay
    /// silent for 'river' or it would claim the lemma first (rank 2), so
    /// 'river''s absolutist share deliberately varies 2x across its walks;
    /// `frameConstancy` stays silent because no modal word is spoken.
    private func composedBlockInput() -> DossierSenses.Input {
        let walkStart = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let fusedWalks = [UUID(), UUID(), UUID()]
        let father = steadyThread("father", recordings: [UUID(), UUID(), UUID()], walks: fusedWalks)
        let money = steadyThread("money", recordings: [UUID(), UUID(), UUID()], walks: fusedWalks)
        let riverRecs = [UUID(), UUID(), UUID()]
        let river = steadyThread("river", recordings: riverRecs, walks: [UUID(), UUID(), UUID()])

        var timestamps: [UUID: Date] = [:]
        var fixes: [UUID: DossierSenses.RouteFix] = [:]
        for (offset, rec) in riverRecs.enumerated() {
            timestamps[rec] = walkStart.addingTimeInterval(-Double(offset + 1) * 86400)
            fixes[rec] = DossierSenses.RouteFix(
                coordinate: .init(latitude: 51.5 + Double(offset) * 0.0001, longitude: -0.12),
                horizontalAccuracy: 10, gapSeconds: 5
            )
        }
        // 10 / 20 / 40 absolutist over 1000 words — nowhere near flat, so
        // `unmovedReturn` cannot claim 'river' out from under placeFrameLock.
        let riverContexts = [
            markerContext(riverRecs[0], absolutist: 10, firstPerson: 40, sentiment: -0.2, words: 1000),
            markerContext(riverRecs[1], absolutist: 20, firstPerson: 40, sentiment: -0.2, words: 1000),
            markerContext(riverRecs[2], absolutist: 40, firstPerson: 40, sentiment: -0.2, words: 1000)
        ]
        let fusedContexts = (father.appearances + money.appearances).map { plainContext($0.recordingUUID) }

        return DossierSenses.Input(
            currentWalkUUID: fusedWalks[0],
            walkStart: walkStart,
            walkEnd: walkStart.addingTimeInterval(5400),
            totalAscent: 0, elevationSeries: [], photos: [], currentRecordings: [],
            historicalContexts: fusedContexts + riverContexts,
            threads: [father, money, river],
            backfillComplete: true, walkSnapshots: [], recordingTimestamps: timestamps,
            fixes: fixes, moon: nil
        )
    }

    func testInvarianceLines_realSignals_composeTheUnchangedBlock() {
        let block = ThreadsDossierBuilder.renderUnchangedBlock(
            DossierSenses.invarianceLines(input: composedBlockInput())
        )
        XCTAssertEqual(
            block,
            "**Unchanged:**\n"
                + "'father' and 'money' have appeared in the same 3 walks, never apart.\n"
                + "Every time 'river' was spoken with its location known, it was in the same place "
                + "— on all 3 of its walks in the last 30 days."
        )
    }

    // MARK: - fusedThemes reserves both themes it names

    /// The line prints TWO display terms but anchored on one lemma, so only
    /// the subset was reserved. A lower-ranked signal could then make its own
    /// measured claim about the superset — a second, independent-looking
    /// finding about a theme the first line had already spoken for. Both are
    /// reserved now; `claimedLemmas` is what the engine reads.
    func testFusedThemes_reservesBothThemesItNames() {
        let walks = [UUID(), UUID(), UUID()]
        let input = inputWith(threads: [
            thread("father", walks: walks),
            thread("money", walks: walks)
        ])
        let line = DossierSensesInvariance.fusedThemes(input: input, suppressed: [])
        XCTAssertEqual(line?.lemma, "father")
        XCTAssertEqual(line?.secondaryLemma, "money")
        XCTAssertEqual(line?.claimedLemmas, ["father", "money"])
    }

    func testEngine_secondaryLemmaOfAHigherRankedLine_suppressesLowerRank() {
        let lines = DossierSenses.invarianceLines(
            input: fusedFixtureInput(backfillComplete: true),
            evaluate: { invariant, _, suppressed in
                switch invariant {
                case .fusedThemes:
                    return .init(text: "fused", lemma: "father", secondaryLemma: "money")
                case .unmovedReturn:
                    return suppressed.contains("money")
                        ? nil : .init(text: "a second claim about money", lemma: "money")
                default:
                    return nil
                }
            }
        )
        XCTAssertEqual(lines, ["fused"])
    }

    /// `fusedThemes` reads only themes, so nothing gated it by language.
    /// `TranscriptNLP.contentLemmaMentions` falls back to the lowercased
    /// surface form where NLTagger has no lemma model, which turns two
    /// inflections of one French word into two "themes" that are, of course,
    /// never apart. Identical fixture, analyzed as French: silent.
    func testFusedThemes_nonEnglishRecordings_staySilent() {
        let walks = [UUID(), UUID(), UUID()]
        let input = inputWith(
            threads: [thread("marche", walks: walks), thread("marches", walks: walks)],
            languageCode: "fr"
        )
        XCTAssertNil(DossierSensesInvariance.fusedThemes(input: input, suppressed: []))
    }

    // MARK: - frameConstancy: the sentence names the speech it measured

    /// The evidence is `thread.appearances` — only the recordings that
    /// carried the theme — while the old sentence ("Every walk where 'X'
    /// appears is Y-dominant") made a claim about the WALK. Multi-recording
    /// walks are ordinary: here each walk's OTHER recording is heavily
    /// counterfactual, so every one of these walks is counterfactual-dominant
    /// overall while the speech that carried 'money' is obligation-dominant.
    /// The rendered line must name the speech, not the walk.
    func testFrameConstancy_claimsTheSpeechItMeasured_notTheWholeWalk() {
        let walks = [UUID(), UUID(), UUID()]
        let themed = [UUID(), UUID(), UUID()]
        let unthemed = [UUID(), UUID(), UUID()]
        var contexts = themed.map { modalContext($0, modals: ["should": 9]) }
        // Never referenced by any thread: the walk's other recording, which
        // the walk-scoped reading would have had to account for and didn't.
        contexts += unthemed.map { modalContext($0, modals: ["would": 40]) }
        let input = modalInput(contexts, steadyThread("money", recordings: themed, walks: walks))
        let line = DossierSensesInvariance.frameConstancy(input: input, suppressed: [])
        XCTAssertEqual(
            line?.text,
            "On every walk where 'money' appears, the speech carrying it was obligation-dominant."
        )
        XCTAssertFalse(line?.text.hasPrefix("Every walk where") ?? true,
                       "the sentence must not make a walk-scoped claim from theme-scoped evidence")
    }

    // MARK: - frameConstancy: the mode must beat something

    /// `dominantModalFamily` copied `modalLeanSummary`'s tie mechanics —
    /// declaration order over `ModalFamily.allCases`, strict `>` to replace —
    /// but not the gates that make them safe there
    /// (`modalRemarkableMinCount` 10 plus 2x baseline elevation). With only
    /// `count > 0`, a single "can" made a walk possibility-dominant, and
    /// `possibility` leads `allCases`, so it won every tie.
    func testFrameConstancy_oneModalPerWalk_isNotAFrame() {
        let recs = [UUID(), UUID(), UUID()]
        let input = modalInput(
            recs.map { modalContext($0, modals: ["can": 1]) },
            steadyThread("money", recordings: recs, walks: [UUID(), UUID(), UUID()])
        )
        XCTAssertNil(DossierSensesInvariance.frameConstancy(input: input, suppressed: []),
                     "a single 'can' is not a frame the walker was thinking inside")
    }

    func testFrameConstancy_atTheModalFloor_speaks() {
        let recs = [UUID(), UUID(), UUID()]
        let input = modalInput(
            recs.map {
                modalContext($0, modals: ["can": DossierSensesInvariance.frameConstancyMinModalsPerWalk])
            },
            steadyThread("money", recordings: recs, walks: [UUID(), UUID(), UUID()])
        )
        XCTAssertEqual(
            DossierSensesInvariance.frameConstancy(input: input, suppressed: [])?.text,
            "On every walk where 'money' appears, the speech carrying it was possibility-dominant.",
            "the floor must be a floor, not a mute button"
        )
    }

    /// A tie at the top is not a dominant frame. Declaration order would have
    /// elected `possibility` here — first in `allCases` — silently, on
    /// evidence that says the walk leaned both ways equally.
    func testFrameConstancy_topTwoFamiliesTie_holdsTheSignalSilent() {
        let recs = [UUID(), UUID(), UUID()]
        let input = modalInput(
            recs.map { modalContext($0, modals: ["can": 6, "should": 6]) },
            steadyThread("money", recordings: recs, walks: [UUID(), UUID(), UUID()])
        )
        XCTAssertNil(DossierSensesInvariance.frameConstancy(input: input, suppressed: []),
                     "a tie means no dominant family, not the first one declared")
    }

    // MARK: - Sentiment flatness is symmetric

    /// CV on the +1.0-shifted scale gave `{0.9, 0.5, 0.7}` → 0.096 (flat) and
    /// `{-0.9, -0.5, -0.7}` → 0.544 (not flat) despite an identical standard
    /// deviation: a positive theme earned "it sounds the same each time" while
    /// an identically-varying negative one was refused it. An absolute band on
    /// the raw scale gives both the same answer, whichever answer that is.
    func testSentimentFlatness_isSignSymmetric() {
        XCTAssertEqual(
            DossierSensesInvariance.isSentimentFlat([0.9, 0.5, 0.7]),
            DossierSensesInvariance.isSentimentFlat([-0.9, -0.5, -0.7])
        )
        XCTAssertEqual(
            DossierSensesInvariance.isSentimentFlat([0.2, 0.1, 0.15]),
            DossierSensesInvariance.isSentimentFlat([-0.2, -0.1, -0.15])
        )
    }

    func testSentimentFlatness_steadyMoodIsFlat_swingingMoodIsNot() {
        XCTAssertTrue(DossierSensesInvariance.isSentimentFlat([-0.60, -0.62, -0.58]))
        XCTAssertFalse(DossierSensesInvariance.isSentimentFlat([-0.8, 0.7, 0.0]))
    }

    /// End to end through the rendered line: a steadily NEGATIVE theme was
    /// the case the shifted CV was most likely to refuse, and it is exactly
    /// the walker this feature exists for.
    func testUnmovedReturn_steadilyNegativeSentiment_stillSpeaks() {
        let recs = [UUID(), UUID(), UUID()]
        let contexts = [
            markerContext(recs[0], absolutist: 20, firstPerson: 40, sentiment: -0.72, words: 1000),
            markerContext(recs[1], absolutist: 21, firstPerson: 41, sentiment: -0.68, words: 1000),
            markerContext(recs[2], absolutist: 20, firstPerson: 40, sentiment: -0.70, words: 1000)
        ]
        let thread = steadyThread("grief", recordings: recs, walks: [UUID(), UUID(), UUID()])
        XCTAssertEqual(
            DossierSensesInvariance.unmovedReturn(
                input: flatnessInput(contexts: contexts, thread: thread), suppressed: []
            )?.text,
            "'grief' has returned across 3 walks; it sounds the same each time."
        )
    }
}
