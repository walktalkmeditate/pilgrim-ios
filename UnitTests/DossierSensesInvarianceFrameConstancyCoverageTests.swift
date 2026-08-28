import XCTest
@testable import Pilgrim

/// FIX 1 + FIX 2 review carry-forward (Task 5 review): pinning
/// `frameConstancy`'s full-coverage requirement and the N-1-agree
/// near-miss boundary. Split into its own file — the parent class sits at
/// the file_length gate — following the same-file extension pattern
/// established by `DossierSensesCrossWalkMoonTests.swift`. Shares the
/// parent's fixtures (`modalContext`, `modalInput`, `steadyThread`) via
/// extension.
extension DossierSensesInvarianceTests {

    private func nonEnglishContext(_ uuid: UUID) -> TranscriptContext {
        TranscriptContext(
            schemaVersion: TranscriptContext.currentSchemaVersion,
            recordingUUID: uuid, transcriptHash: "h", languageCode: "es",
            wordCount: 200, themes: [], markers: nil
        )
    }

    /// FIX 1: the rendered claim covers every walk in the theme's walk-set
    /// ("On every walk where X appears, the speech carrying it was
    /// Y-dominant"). That is false the moment one walk in the theme's
    /// walk-set has no modal evidence to check against it. Three walks
    /// agree obligation-dominant; a fourth walk's only recording is
    /// non-English (`markers == nil`), so it can never be checked.
    /// Dropping that walk from the pool (the pre-fix behavior) let the
    /// other three speak for a walk the line never looked at. Coverage
    /// must fail closed: the whole signal stays silent, not partial.
    func testFrameConstancy_oneWalkNonEnglish_holdsSignalSilent() {
        let recs = [UUID(), UUID(), UUID(), UUID()]
        let walkA = UUID(), walkB = UUID(), walkC = UUID(), walkD = UUID()
        let input = modalInput(
            [
                modalContext(recs[0], modals: ["should": 5]),
                modalContext(recs[1], modals: ["must": 4]),
                modalContext(recs[2], modals: ["ought": 3]),
                nonEnglishContext(recs[3])
            ],
            steadyThread("money", recordings: recs, walks: [walkA, walkB, walkC, walkD])
        )
        XCTAssertNil(DossierSensesInvariance.frameConstancy(input: input, suppressed: []))
    }

    /// FIX 1, the other way a walk can lack modal evidence: the recording
    /// IS English (`markers` present) but no modal word was spoken at
    /// all, so `modalCounts` is empty. Coverage must fail the same way —
    /// this exercises the guard's other branch, not just `markers == nil`
    /// above.
    func testFrameConstancy_oneWalkNoModalWordsSpoken_holdsSignalSilent() {
        let recs = [UUID(), UUID(), UUID(), UUID()]
        let walkA = UUID(), walkB = UUID(), walkC = UUID(), walkD = UUID()
        let input = modalInput(
            [
                modalContext(recs[0], modals: ["should": 5]),
                modalContext(recs[1], modals: ["must": 4]),
                modalContext(recs[2], modals: ["ought": 3]),
                modalContext(recs[3], modals: [:])
            ],
            steadyThread("money", recordings: recs, walks: [walkA, walkB, walkC, walkD])
        )
        XCTAssertNil(DossierSensesInvariance.frameConstancy(input: input, suppressed: []))
    }

    /// FIX 2: pin the near-miss boundary. Existing coverage
    /// (`testFrameConstancy_familyVaries_staysSilent`) only proves full
    /// three-way disagreement stays silent. Two walks obligation-dominant,
    /// one counterfactual-dominant — full modal coverage on all three, so
    /// this isolates disagreement from coverage — must also stay silent.
    /// The `allSatisfy` logic is provably correct either way; this is
    /// what makes that provable rather than assumed.
    func testFrameConstancy_twoOfThreeAgree_oneDiffers_staysSilent() {
        let recs = [UUID(), UUID(), UUID()]
        let input = modalInput(
            [
                modalContext(recs[0], modals: ["should": 12]),
                modalContext(recs[1], modals: ["must": 9]),
                modalContext(recs[2], modals: ["would": 7])
            ],
            steadyThread("money", recordings: recs, walks: [UUID(), UUID(), UUID()])
        )
        XCTAssertNil(DossierSensesInvariance.frameConstancy(input: input, suppressed: []))
    }
}
