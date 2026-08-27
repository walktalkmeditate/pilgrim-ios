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
}
