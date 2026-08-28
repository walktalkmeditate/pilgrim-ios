import XCTest
@testable import Pilgrim

final class DossierSensesInvarianceTests: XCTestCase {

    private func emptyInput() -> DossierSenses.Input {
        DossierSenses.Input(
            currentWalkUUID: UUID(),
            walkStart: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            walkEnd: DateFactory.makeDate(2024, 6, 15, 10, 30, 0),
            totalAscent: 0, elevationSeries: [], photos: [],
            currentRecordings: [], historicalContexts: [], threads: [],
            backfillComplete: true, walkSnapshots: [], recordingTimestamps: [:],
            fixes: [:], moon: nil
        )
    }

    private func stub(_ firing: [DossierSenses.Invariant: DossierSenses.SenseLine])
        -> (DossierSenses.Invariant, DossierSenses.Input, Set<String>) -> DossierSenses.SenseLine? {
        { invariant, _, _ in firing[invariant] }
    }

    func testEngine_allFiring_capsAtThreeInPriorityOrder() {
        let lines = DossierSenses.invarianceLines(
            input: emptyInput(),
            evaluate: stub([
                .fusedThemes: .init(text: "fused", lemma: "father"),
                .unmovedReturn: .init(text: "unmoved", lemma: "work"),
                .frameConstancy: .init(text: "frame", lemma: "money"),
                .placeFrameLock: .init(text: "place", lemma: "river")
            ])
        )
        XCTAssertEqual(lines, ["fused", "unmoved", "frame"])
    }

    func testEngine_lemmaClaimedByHigherRank_suppressesLowerRank() {
        let lines = DossierSenses.invarianceLines(
            input: emptyInput(),
            evaluate: stub([
                .fusedThemes: .init(text: "fused", lemma: "work"),
                .unmovedReturn: .init(text: "unmoved", lemma: "work"),
                .frameConstancy: .init(text: "frame", lemma: "money")
            ])
        )
        XCTAssertEqual(lines, ["fused", "frame"])
    }

    func testEngine_nilLemmaNeverSuppresses() {
        let lines = DossierSenses.invarianceLines(
            input: emptyInput(),
            evaluate: stub([
                .fusedThemes: .init(text: "a", lemma: nil),
                .unmovedReturn: .init(text: "b", lemma: nil)
            ])
        )
        XCTAssertEqual(lines, ["a", "b"])
    }

    func testEngine_noneFiring_returnsEmpty() {
        XCTAssertTrue(DossierSenses.invarianceLines(input: emptyInput(), evaluate: stub([:])).isEmpty)
    }

    func testInvariantOrder_isTheSpecPriorityOrder() {
        XCTAssertEqual(
            DossierSenses.Invariant.allCases,
            [.fusedThemes, .unmovedReturn, .frameConstancy, .placeFrameLock, .unarrivedIntention]
        )
    }

    func testUnarrivedIntention_isDarkByDefault() {
        XCTAssertTrue(DossierSensesInvariance.pendingFieldGate)
    }

    /// Internal, not private, so the split files that extend this class can
    /// share it — same widening the other fixtures here already took.
    func thread(_ lemma: String, walks: [UUID], salience: Double = 0.5) -> WalkThread {
        WalkThread(
            lemma: lemma,
            displayTerm: lemma,
            appearances: walks.map {
                ThreadAppearance(
                    recordingUUID: UUID(), walkUUID: $0,
                    date: DateFactory.makeDate(2024, 6, 1, 9, 0, 0),
                    mentionCount: 3, salience: salience
                )
            }
        )
    }

    /// Every appearance gets an English-analyzed context, because production
    /// always has one: `ThreadStore.build` derives threads from exactly the
    /// contexts `DossierSensesInvariance.englishRecordings` scans. An empty
    /// `historicalContexts` is not a realistic shape, and leaving it empty
    /// would have hidden the language gate from every fixture here.
    func inputWith(threads: [WalkThread], languageCode: String? = "en") -> DossierSenses.Input {
        DossierSenses.Input(
            currentWalkUUID: threads.first?.appearances.first?.walkUUID ?? UUID(),
            walkStart: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            walkEnd: DateFactory.makeDate(2024, 6, 15, 10, 30, 0),
            totalAscent: 0, elevationSeries: [], photos: [],
            currentRecordings: [],
            historicalContexts: threads.flatMap(\.appearances).map {
                plainContext($0.recordingUUID, languageCode: languageCode)
            },
            threads: threads,
            backfillComplete: true, walkSnapshots: [], recordingTimestamps: [:],
            fixes: [:], moon: nil
        )
    }

    /// "in the same 3 walks", never "in 3 of 3 walks": on the identical-set
    /// branch `shared == outer` by construction, so the denominator has
    /// nothing to contrast with and reads as "all of your walks" — a claim
    /// about the walker's whole history that neither theme's walk-set
    /// supports. The nested branch below keeps both counts, where they
    /// genuinely differ.
    func testFusedThemes_identicalWalkSets_fires() {
        let walks = [UUID(), UUID(), UUID()]
        let input = inputWith(threads: [
            thread("father", walks: walks),
            thread("money", walks: walks)
        ])
        let line = DossierSensesInvariance.fusedThemes(input: input, suppressed: [])
        XCTAssertEqual(
            line?.text,
            "'father' and 'money' have appeared in the same 3 walks, never apart."
        )
        XCTAssertEqual(line?.lemma, "father")
    }

    func testFusedThemes_identicalWalkSets_neverRendersAReferentFreeDenominator() {
        let walks = [UUID(), UUID(), UUID()]
        let input = inputWith(threads: [
            thread("father", walks: walks),
            thread("money", walks: walks)
        ])
        let line = DossierSensesInvariance.fusedThemes(input: input, suppressed: [])
        XCTAssertFalse(line?.text.contains("3 of 3") ?? true)
    }

    func testFusedThemes_nestedWalkSet_fires() {
        let subsetWalks = [UUID(), UUID(), UUID()]
        let supersetWalks = subsetWalks + [UUID(), UUID()]
        let input = inputWith(threads: [
            thread("father", walks: subsetWalks),
            thread("money", walks: supersetWalks)
        ])
        let line = DossierSensesInvariance.fusedThemes(input: input, suppressed: [])
        XCTAssertEqual(
            line?.text,
            "'father' has appeared in 3 walks, always alongside 'money' — which walked 5 in all."
        )
        XCTAssertEqual(line?.lemma, "father")
    }

    func testFusedThemes_nestedWalkSet_doesNotClaimSymmetricNeverApart() {
        let subsetWalks = [UUID(), UUID(), UUID()]
        let supersetWalks = subsetWalks + [UUID(), UUID()]
        let input = inputWith(threads: [
            thread("father", walks: subsetWalks),
            thread("money", walks: supersetWalks)
        ])
        let line = DossierSensesInvariance.fusedThemes(input: input, suppressed: [])
        XCTAssertFalse(line?.text.contains("never apart") ?? true)
    }

    func testFusedThemes_belowMinimumWalks_staysSilent() {
        let walks = [UUID(), UUID()]
        let input = inputWith(threads: [
            thread("father", walks: walks),
            thread("money", walks: walks)
        ])
        XCTAssertNil(DossierSensesInvariance.fusedThemes(input: input, suppressed: []))
    }

    func testFusedThemes_partialOverlap_staysSilent() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let input = inputWith(threads: [
            thread("father", walks: [a, b, c]),
            thread("money", walks: [b, c, d])
        ])
        XCTAssertNil(DossierSensesInvariance.fusedThemes(input: input, suppressed: []))
    }

    func testFusedThemes_suppressedLemma_staysSilent() {
        let walks = [UUID(), UUID(), UUID()]
        let input = inputWith(threads: [
            thread("father", walks: walks),
            thread("money", walks: walks)
        ])
        XCTAssertNil(DossierSensesInvariance.fusedThemes(input: input, suppressed: ["father"]))
    }

    /// Internal, not private, so the split files that extend this class can
    /// share it — the same widening `steadyThread`/`modalContext`/`modalInput`
    /// already took for `DossierSensesInvarianceFrameConstancyCoverageTests`.
    func markerContext(
        _ uuid: UUID, absolutist: Int, firstPerson: Int, sentiment: Double, words: Int = 200
    ) -> TranscriptContext {
        TranscriptContext(
            schemaVersion: TranscriptContext.currentSchemaVersion,
            recordingUUID: uuid, transcriptHash: "h", languageCode: "en",
            wordCount: words, themes: [],
            markers: MarkerPack(
                wordCount: words, absolutistCount: absolutist, firstPersonCount: firstPerson,
                insightCount: 2, causationCount: 2, discrepancyCount: 1,
                futureCount: 3, pastCount: 3, sentiment: sentiment, modalCounts: [:]
            )
        )
    }

    func steadyThread(_ lemma: String, recordings: [UUID], walks: [UUID]) -> WalkThread {
        WalkThread(
            lemma: lemma, displayTerm: lemma,
            appearances: zip(recordings, walks).map { rec, walk in
                ThreadAppearance(
                    recordingUUID: rec, walkUUID: walk,
                    date: DateFactory.makeDate(2024, 6, 1, 9, 0, 0),
                    mentionCount: 3, salience: 0.5
                )
            }
        )
    }

    func testUnmovedReturn_steadySalienceFlatMarkers_fires() {
        let recs = [UUID(), UUID(), UUID()]
        let input = DossierSenses.Input(
            currentWalkUUID: UUID(),
            walkStart: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            walkEnd: DateFactory.makeDate(2024, 6, 15, 10, 30, 0),
            totalAscent: 0, elevationSeries: [], photos: [], currentRecordings: [],
            historicalContexts: [
                markerContext(recs[0], absolutist: 10, firstPerson: 20, sentiment: -0.2),
                markerContext(recs[1], absolutist: 10, firstPerson: 21, sentiment: -0.2),
                markerContext(recs[2], absolutist: 11, firstPerson: 20, sentiment: -0.21)
            ],
            threads: [steadyThread("work", recordings: recs, walks: [UUID(), UUID(), UUID()])],
            backfillComplete: true, walkSnapshots: [], recordingTimestamps: [:],
            fixes: [:], moon: nil
        )
        let line = DossierSensesInvariance.unmovedReturn(input: input, suppressed: [])
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.text.contains("work"))
        XCTAssertTrue(line!.text.contains("3 walks"))
    }

    func testUnmovedReturn_markersVary_staysSilent() {
        let recs = [UUID(), UUID(), UUID()]
        let input = DossierSenses.Input(
            currentWalkUUID: UUID(),
            walkStart: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            walkEnd: DateFactory.makeDate(2024, 6, 15, 10, 30, 0),
            totalAscent: 0, elevationSeries: [], photos: [], currentRecordings: [],
            historicalContexts: [
                markerContext(recs[0], absolutist: 2, firstPerson: 5, sentiment: -0.8),
                markerContext(recs[1], absolutist: 20, firstPerson: 40, sentiment: 0.7),
                markerContext(recs[2], absolutist: 11, firstPerson: 20, sentiment: 0.0)
            ],
            threads: [steadyThread("work", recordings: recs, walks: [UUID(), UUID(), UUID()])],
            backfillComplete: true, walkSnapshots: [], recordingTimestamps: [:],
            fixes: [:], moon: nil
        )
        XCTAssertNil(DossierSensesInvariance.unmovedReturn(input: input, suppressed: []))
    }

    func testUnmovedReturn_belowDensityFloor_staysSilent() {
        let recs = [UUID(), UUID(), UUID()]
        let input = DossierSenses.Input(
            currentWalkUUID: UUID(),
            walkStart: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            walkEnd: DateFactory.makeDate(2024, 6, 15, 10, 30, 0),
            totalAscent: 0, elevationSeries: [], photos: [], currentRecordings: [],
            historicalContexts: recs.map {
                markerContext($0, absolutist: 1, firstPerson: 2, sentiment: -0.2, words: 40)
            },
            threads: [steadyThread("work", recordings: recs, walks: [UUID(), UUID(), UUID()])],
            backfillComplete: true, walkSnapshots: [], recordingTimestamps: [:],
            fixes: [:], moon: nil
        )
        XCTAssertNil(DossierSensesInvariance.unmovedReturn(input: input, suppressed: []))
    }

    /// A thread can gather multiple recordings within the same walk (two
    /// voice memos on one outing), so appearance count and distinct-walk
    /// count diverge. The rendered line reports a WALK count — pin the
    /// exact wording so a future edit can't silently report appearances
    /// instead (the Task 3 lesson: an unpinned rendered claim shipped
    /// false because only non-nil was asserted).
    func testUnmovedReturn_reportsDistinctWalkCount_notAppearanceCount() {
        let recs = [UUID(), UUID(), UUID(), UUID()]
        let walkA = UUID(), walkB = UUID(), walkC = UUID()
        let input = DossierSenses.Input(
            currentWalkUUID: UUID(),
            walkStart: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            walkEnd: DateFactory.makeDate(2024, 6, 15, 10, 30, 0),
            totalAscent: 0, elevationSeries: [], photos: [], currentRecordings: [],
            historicalContexts: [
                markerContext(recs[0], absolutist: 10, firstPerson: 20, sentiment: -0.2),
                markerContext(recs[1], absolutist: 10, firstPerson: 21, sentiment: -0.2),
                markerContext(recs[2], absolutist: 11, firstPerson: 20, sentiment: -0.21),
                markerContext(recs[3], absolutist: 10, firstPerson: 20, sentiment: -0.2)
            ],
            // Four appearances (two recordings on walkA), three distinct walks.
            threads: [steadyThread("work", recordings: recs, walks: [walkA, walkA, walkB, walkC])],
            backfillComplete: true, walkSnapshots: [], recordingTimestamps: [:],
            fixes: [:], moon: nil
        )
        let line = DossierSensesInvariance.unmovedReturn(input: input, suppressed: [])
        XCTAssertEqual(
            line?.text,
            "'work' has returned across 3 walks; it sounds the same each time."
        )
    }

    /// `minimumInvariantWalks` is a walk count (see `fusedThemes`, which
    /// gates on `Set(appearances.map(\.walkUUID)).count`, and
    /// `ThreadsDossierFormatter.modalBaselineFloorWalks`, whose comment
    /// spells out exactly this: "a walker who talks in three short bursts
    /// on one walk isn't three 'prior' data points"). Three recordings that
    /// clear the density floor but land on only two walks must not satisfy
    /// the floor — three bursts on one walk is not three returns.
    func testUnmovedReturn_threeRecordingsOnTwoWalks_staysSilent() {
        let recs = [UUID(), UUID(), UUID()]
        let walkA = UUID(), walkB = UUID()
        let input = DossierSenses.Input(
            currentWalkUUID: UUID(),
            walkStart: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            walkEnd: DateFactory.makeDate(2024, 6, 15, 10, 30, 0),
            totalAscent: 0, elevationSeries: [], photos: [], currentRecordings: [],
            historicalContexts: [
                markerContext(recs[0], absolutist: 10, firstPerson: 20, sentiment: -0.2),
                markerContext(recs[1], absolutist: 10, firstPerson: 21, sentiment: -0.2),
                markerContext(recs[2], absolutist: 11, firstPerson: 20, sentiment: -0.21)
            ],
            // Three qualifying recordings, but only two distinct walks.
            threads: [steadyThread("work", recordings: recs, walks: [walkA, walkA, walkB])],
            backfillComplete: true, walkSnapshots: [], recordingTimestamps: [:],
            fixes: [:], moon: nil
        )
        XCTAssertNil(DossierSensesInvariance.unmovedReturn(input: input, suppressed: []))
    }

    /// A walk whose only recording never clears the density floor
    /// contributes no evidence toward "sounds the same" and must not
    /// inflate the reported walk count — the count must match exactly the
    /// walks the flatness claim can vouch for.
    func testUnmovedReturn_unevidencedWalk_excludedFromReportedCount() {
        let recs = [UUID(), UUID(), UUID(), UUID()]
        let walkA = UUID(), walkB = UUID(), walkC = UUID(), walkD = UUID()
        let input = DossierSenses.Input(
            currentWalkUUID: UUID(),
            walkStart: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            walkEnd: DateFactory.makeDate(2024, 6, 15, 10, 30, 0),
            totalAscent: 0, elevationSeries: [], photos: [], currentRecordings: [],
            historicalContexts: [
                markerContext(recs[0], absolutist: 10, firstPerson: 20, sentiment: -0.2),
                markerContext(recs[1], absolutist: 10, firstPerson: 21, sentiment: -0.2),
                markerContext(recs[2], absolutist: 11, firstPerson: 20, sentiment: -0.21),
                // walkD's only recording is too short to be evidence of anything.
                markerContext(recs[3], absolutist: 1, firstPerson: 1, sentiment: 0.9, words: 40)
            ],
            threads: [steadyThread("work", recordings: recs, walks: [walkA, walkB, walkC, walkD])],
            backfillComplete: true, walkSnapshots: [], recordingTimestamps: [:],
            fixes: [:], moon: nil
        )
        let line = DossierSensesInvariance.unmovedReturn(input: input, suppressed: [])
        XCTAssertEqual(
            line?.text,
            "'work' has returned across 3 walks; it sounds the same each time."
        )
    }

    func modalContext(_ uuid: UUID, modals: [String: Int], words: Int = 200) -> TranscriptContext {
        TranscriptContext(
            schemaVersion: TranscriptContext.currentSchemaVersion,
            recordingUUID: uuid, transcriptHash: "h", languageCode: "en",
            wordCount: words, themes: [],
            markers: MarkerPack(
                wordCount: words, absolutistCount: 5, firstPersonCount: 10,
                insightCount: 2, causationCount: 2, discrepancyCount: 1,
                futureCount: 3, pastCount: 3, sentiment: -0.1, modalCounts: modals
            )
        )
    }

    func modalInput(_ contexts: [TranscriptContext], _ thread: WalkThread) -> DossierSenses.Input {
        DossierSenses.Input(
            currentWalkUUID: UUID(),
            walkStart: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            walkEnd: DateFactory.makeDate(2024, 6, 15, 10, 30, 0),
            totalAscent: 0, elevationSeries: [], photos: [], currentRecordings: [],
            historicalContexts: contexts, threads: [thread],
            backfillComplete: true, walkSnapshots: [], recordingTimestamps: [:],
            fixes: [:], moon: nil
        )
    }

    func testFrameConstancy_sameFamilyEveryWalk_fires() {
        let recs = [UUID(), UUID(), UUID()]
        let input = modalInput(
            [
                modalContext(recs[0], modals: ["should": 12, "can": 2]),
                modalContext(recs[1], modals: ["should": 9, "might": 1]),
                modalContext(recs[2], modals: ["must": 7, "could": 2])
            ],
            steadyThread("money", recordings: recs, walks: [UUID(), UUID(), UUID()])
        )
        let line = DossierSensesInvariance.frameConstancy(input: input, suppressed: [])
        XCTAssertEqual(
            line?.text,
            "On every walk where 'money' appears, the speech carrying it was obligation-dominant."
        )
        XCTAssertEqual(line?.lemma, "money")
    }

    func testFrameConstancy_familyVaries_staysSilent() {
        let recs = [UUID(), UUID(), UUID()]
        let input = modalInput(
            [
                modalContext(recs[0], modals: ["should": 12]),
                modalContext(recs[1], modals: ["could": 11]),
                modalContext(recs[2], modals: ["would": 9])
            ],
            steadyThread("money", recordings: recs, walks: [UUID(), UUID(), UUID()])
        )
        XCTAssertNil(DossierSensesInvariance.frameConstancy(input: input, suppressed: []))
    }

    func testFrameConstancy_noModalsAtAll_staysSilent() {
        let recs = [UUID(), UUID(), UUID()]
        let input = modalInput(
            recs.map { modalContext($0, modals: [:]) },
            steadyThread("money", recordings: recs, walks: [UUID(), UUID(), UUID()])
        )
        XCTAssertNil(DossierSensesInvariance.frameConstancy(input: input, suppressed: []))
    }

    /// The Task 4 lesson, replayed here: `families` must be keyed on
    /// distinct WALKS, not qualifying recordings. Three obligation-dominant
    /// recordings that all land on the SAME walk are one data point, not
    /// three — below `minimumInvariantWalks`, this must stay silent even
    /// though three recordings individually "qualify".
    func testFrameConstancy_threeRecordingsOnOneWalk_staysSilent() {
        let recs = [UUID(), UUID(), UUID()]
        let walkA = UUID()
        let input = modalInput(
            [
                modalContext(recs[0], modals: ["should": 5]),
                modalContext(recs[1], modals: ["should": 4]),
                modalContext(recs[2], modals: ["must": 3])
            ],
            steadyThread("money", recordings: recs, walks: [walkA, walkA, walkA])
        )
        XCTAssertNil(DossierSensesInvariance.frameConstancy(input: input, suppressed: []))
    }

    /// Design decision (documented on `frameConstancy` itself): when a walk
    /// has two recordings, their modal counts are SUMMED into one combined
    /// total before a dominant family is picked for that walk — mirroring
    /// `ThreadsDossierFormatter.modalLeanSummary`, which sums a walk's
    /// recordings before naming today's dominant family, rather than
    /// picking one recording's dominance to represent the whole walk.
    ///
    /// Pinned here: walkA's two recordings disagree individually (rec0
    /// alone is counterfactual-dominant 3-0, rec1 alone is
    /// obligation-dominant 2-0), but summed ("would": 3, "should": 2) the
    /// walk is counterfactual-dominant. Picking "last recording wins"
    /// would report obligation for walkA and break the match with walkB
    /// and walkC — this test fails under that alternative.
    func testFrameConstancy_recordingsOnSameWalk_combineByModalCountSum() {
        let walkA = UUID(), walkB = UUID(), walkC = UUID()
        let recs = [UUID(), UUID(), UUID(), UUID()]
        let input = modalInput(
            [
                modalContext(recs[0], modals: ["would": 3]),
                modalContext(recs[1], modals: ["should": 2]),
                modalContext(recs[2], modals: ["would": 5]),
                modalContext(recs[3], modals: ["would": 4, "might": 1])
            ],
            steadyThread("worry", recordings: recs, walks: [walkA, walkA, walkB, walkC])
        )
        let line = DossierSensesInvariance.frameConstancy(input: input, suppressed: [])
        XCTAssertEqual(
            line?.text,
            "On every walk where 'worry' appears, the speech carrying it was counterfactual-dominant."
        )
    }
}
