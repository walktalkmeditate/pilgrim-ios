import XCTest
@testable import Pilgrim

/// Signal 5 (unarrived intention, shipped dark): the walker deliberately
/// set out carrying a word on `minimumInvariantWalks`+ walks, and that
/// word's thread is still `.steady`. New file, not an addition to
/// `DossierSensesInvarianceTests.swift` — the parent sits at 458 lines,
/// close enough to the `file_length` warning gate of 500 that this
/// signal's tests would push it over. Same split pattern as
/// `DossierSensesInvarianceFrameConstancyCoverageTests.swift` and
/// `DossierSensesInvariancePlaceFrameLockTests.swift`.
extension DossierSensesInvarianceTests {

    private func snapshot(_ walkUUID: UUID, intention: String, date: Date) -> DossierSenses.WalkSnapshotRow {
        DossierSenses.WalkSnapshotRow(walkUUID: walkUUID, startDate: date, intention: intention, weatherCondition: nil)
    }

    private func intentionInput(
        threads: [WalkThread], walkSnapshots: [DossierSenses.WalkSnapshotRow]
    ) -> DossierSenses.Input {
        DossierSenses.Input(
            currentWalkUUID: threads.first?.appearances.first?.walkUUID ?? UUID(),
            walkStart: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            walkEnd: DateFactory.makeDate(2024, 6, 15, 10, 30, 0),
            totalAscent: 0, elevationSeries: [], photos: [], currentRecordings: [],
            historicalContexts: [], threads: threads, backfillComplete: true,
            walkSnapshots: walkSnapshots, recordingTimestamps: [:], fixes: [:], moon: nil
        )
    }

    func testUnarrivedIntention_engineFires_whenCalledDirectly() {
        let walks = [UUID(), UUID(), UUID()]
        let recs = [UUID(), UUID(), UUID()]
        let snapshots = walks.map {
            DossierSenses.WalkSnapshotRow(
                walkUUID: $0, startDate: DateFactory.makeDate(2024, 6, 1, 9, 0, 0),
                intention: "walk with patience", weatherCondition: nil
            )
        }
        let thread = WalkThread(
            lemma: "patience", displayTerm: "patience",
            appearances: zip(recs, walks).map { rec, walk in
                ThreadAppearance(
                    recordingUUID: rec, walkUUID: walk,
                    date: DateFactory.makeDate(2024, 6, 1, 9, 0, 0),
                    mentionCount: 3, salience: 0.5
                )
            }
        )
        let input = DossierSenses.Input(
            currentWalkUUID: walks[0],
            walkStart: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            walkEnd: DateFactory.makeDate(2024, 6, 15, 10, 30, 0),
            totalAscent: 0, elevationSeries: [], photos: [], currentRecordings: [],
            historicalContexts: [], threads: [thread], backfillComplete: true,
            walkSnapshots: snapshots, recordingTimestamps: [:], fixes: [:], moon: nil
        )
        let line = DossierSensesInvariance.unarrivedIntention(input: input, suppressed: [])
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.text.contains("patience"))
    }

    func testUnarrivedIntention_isSuppressedFromEngineOutputByTheFlag() {
        let walks = [UUID(), UUID(), UUID()]
        let recs = [UUID(), UUID(), UUID()]
        let snapshots = walks.map {
            DossierSenses.WalkSnapshotRow(
                walkUUID: $0, startDate: DateFactory.makeDate(2024, 6, 1, 9, 0, 0),
                intention: "walk with patience", weatherCondition: nil
            )
        }
        let thread = WalkThread(
            lemma: "patience", displayTerm: "patience",
            appearances: zip(recs, walks).map { rec, walk in
                ThreadAppearance(
                    recordingUUID: rec, walkUUID: walk,
                    date: DateFactory.makeDate(2024, 6, 1, 9, 0, 0),
                    mentionCount: 3, salience: 0.5
                )
            }
        )
        let input = DossierSenses.Input(
            currentWalkUUID: walks[0],
            walkStart: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            walkEnd: DateFactory.makeDate(2024, 6, 15, 10, 30, 0),
            totalAscent: 0, elevationSeries: [], photos: [], currentRecordings: [],
            historicalContexts: [], threads: [thread], backfillComplete: true,
            walkSnapshots: snapshots, recordingTimestamps: [:], fixes: [:], moon: nil
        )
        XCTAssertNil(DossierSenses.evaluateInvariant(.unarrivedIntention, input: input, suppressed: []))
        XCTAssertTrue(DossierSenses.invarianceLines(input: input).isEmpty)
    }

    /// Pins the exact rendered wording (the Task 3 lesson, replayed here):
    /// non-nil plus a `contains` check is not enough to catch a future edit
    /// that quietly changes what N counts.
    func testUnarrivedIntention_rendersExactWording() {
        let walks = [UUID(), UUID(), UUID()]
        let recs = [UUID(), UUID(), UUID()]
        let snapshots = walks.map {
            snapshot($0, intention: "walk with patience", date: DateFactory.makeDate(2024, 6, 1, 9, 0, 0))
        }
        let thread = steadyThread("patience", recordings: recs, walks: walks)
        let line = DossierSensesInvariance.unarrivedIntention(
            input: intentionInput(threads: [thread], walkSnapshots: snapshots), suppressed: []
        )
        XCTAssertEqual(line?.text, "'patience' was set as an intention on 3 walks; it has not shifted since.")
        XCTAssertEqual(line?.lemma, "patience")
    }

    /// `intentionWalks[lemma]` (from intention TEXT) and the thread's own
    /// appearance walks (from what the walker actually talked about) are
    /// different sets. Here the thread only ever APPEARS on 3 walks
    /// (steady, minimum met on its own); the walker also wrote "carry
    /// patience" as an intention on 2 further walks where patience was
    /// never actually spoken about — no thread appearance those days. A
    /// naive implementation reports `intentionWalks.count` (5): a claim the
    /// steadiness verdict never measured. The rendered N must be the
    /// intersection (3), not the raw intention-text count (5).
    func testUnarrivedIntention_doesNotOverclaimWalksThreadNeverAppearedOn() {
        let threadWalks = [UUID(), UUID(), UUID()]
        let recs = [UUID(), UUID(), UUID()]
        let thread = steadyThread("patience", recordings: recs, walks: threadWalks)

        let intentionOnlyWalks = [UUID(), UUID()]
        let snapshots = (threadWalks + intentionOnlyWalks).map {
            snapshot($0, intention: "carry patience", date: DateFactory.makeDate(2024, 6, 1, 9, 0, 0))
        }
        let line = DossierSensesInvariance.unarrivedIntention(
            input: intentionInput(threads: [thread], walkSnapshots: snapshots), suppressed: []
        )
        XCTAssertEqual(line?.text, "'patience' was set as an intention on 3 walks; it has not shifted since.")
    }

    /// The floor must be met by the INTERSECTION, not by intention-text
    /// walks alone. Intention "patience" is set on 3 walks (clears
    /// `minimumInvariantWalks` on its own), but the thread only actually
    /// appears on 1 of those 3 — the other 2 intention-walks have no
    /// thread evidence at all. The thread's own appearance set ({A, B, C})
    /// is independently steady, so an implementation that judges
    /// steadiness over the full unfiltered thread (ignoring which walks
    /// the intention-text set actually overlaps) would incorrectly fire
    /// with N=3. Bound coverage is 1 walk, below the floor — must stay
    /// silent.
    func testUnarrivedIntention_overlapBelowFloor_staysSilentEvenThoughFullThreadIsSteady() {
        let walkA = UUID(), walkB = UUID(), walkC = UUID()
        let recs = [UUID(), UUID(), UUID()]
        let thread = steadyThread("patience", recordings: recs, walks: [walkA, walkB, walkC])

        let unrelatedWalks = [UUID(), UUID()]
        let snapshots = ([walkA] + unrelatedWalks).map {
            snapshot($0, intention: "carry patience", date: DateFactory.makeDate(2024, 6, 1, 9, 0, 0))
        }
        XCTAssertNil(
            DossierSensesInvariance.unarrivedIntention(
                input: intentionInput(threads: [thread], walkSnapshots: snapshots), suppressed: []
            )
        )
    }

    /// "has not shifted since" needs a temporal anchor: the direction
    /// verdict must be judged over the walks the intention was actually
    /// carried on, not the thread's whole unrelated history. Six walks in
    /// date order: W1-W3 (no intention set) sit flat at salience 0.5;
    /// W4-W6 (intention "patience" set on all three) rise sharply from
    /// 0.1 to 0.1 to 0.9. Judged over the FULL thread, thirds of 6 average
    /// (0.5, 0.5) early vs (0.1, 0.9) late — a coincidental cancellation
    /// that reads as flat/steady. Judged over just the bound W4-W6 walks
    /// (what the sentence actually claims to speak for), thirds of 3 are
    /// 0.1 early vs 0.9 late — a rise far past `ThreadStore
    /// .directionThreshold`. The bound implementation must catch this
    /// shift and stay silent; an implementation that judges the full,
    /// unfiltered thread would wrongly claim "it has not shifted since."
    func testUnarrivedIntention_judgesDirectionOverBoundWalksOnly_notFullUnrelatedHistory() {
        let walks = (0..<6).map { _ in UUID() }
        let recs = (0..<6).map { _ in UUID() }
        let dates = (0..<6).map { DateFactory.makeDate(2024, 6, 1 + $0, 9, 0, 0) }
        let saliences = [0.5, 0.5, 0.5, 0.1, 0.1, 0.9]

        let thread = WalkThread(
            lemma: "patience", displayTerm: "patience",
            appearances: (0..<6).map { i in
                ThreadAppearance(
                    recordingUUID: recs[i], walkUUID: walks[i], date: dates[i],
                    mentionCount: 3, salience: saliences[i]
                )
            }
        )
        // Intention "patience" is only ever set, in text, on the last 3 walks.
        let snapshots = (3..<6).map { i in
            snapshot(walks[i], intention: "carry patience", date: dates[i])
        }
        XCTAssertNil(
            DossierSensesInvariance.unarrivedIntention(
                input: intentionInput(threads: [thread], walkSnapshots: snapshots), suppressed: []
            )
        )
    }
}
