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

    private func thread(_ lemma: String, walks: [UUID], salience: Double = 0.5) -> WalkThread {
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

    private func inputWith(threads: [WalkThread]) -> DossierSenses.Input {
        DossierSenses.Input(
            currentWalkUUID: threads.first?.appearances.first?.walkUUID ?? UUID(),
            walkStart: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            walkEnd: DateFactory.makeDate(2024, 6, 15, 10, 30, 0),
            totalAscent: 0, elevationSeries: [], photos: [],
            currentRecordings: [], historicalContexts: [], threads: threads,
            backfillComplete: true, walkSnapshots: [], recordingTimestamps: [:],
            fixes: [:], moon: nil
        )
    }

    func testFusedThemes_identicalWalkSets_fires() {
        let walks = [UUID(), UUID(), UUID()]
        let input = inputWith(threads: [
            thread("father", walks: walks),
            thread("money", walks: walks)
        ])
        let line = DossierSensesInvariance.fusedThemes(input: input, suppressed: [])
        XCTAssertEqual(
            line?.text,
            "'father' and 'money' have appeared in 3 of 3 walks together, never apart."
        )
        XCTAssertEqual(line?.lemma, "father")
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
}
