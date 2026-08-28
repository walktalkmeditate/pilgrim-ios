import XCTest
@testable import Pilgrim

/// Each voice receives only the context blocks its policy allows —
/// `JournalingVoice` and `CreativeVoice` were folding absolutist-word
/// percentages and sentiment scores into prompts whose instructions never
/// asked for them. The policy is a filter applied at assembly time over an
/// `ActivityContext` still built once per prompt-screen-open; it never
/// triggers a second dossier build.
final class PromptContextPolicyTests: XCTestCase {

    // MARK: - Default policy

    func testDefaultPolicy_isFull() {
        XCTAssertTrue(ReflectiveVoice().contextPolicy.includesMarkerLines)
        XCTAssertTrue(ContemplativeVoice().contextPolicy.includesMarkerLines)
        XCTAssertTrue(PhilosophicalVoice().contextPolicy.includesMarkerLines)
        XCTAssertTrue(ReflectiveVoice().contextPolicy.includesThreadAnalysis)
        XCTAssertTrue(ContemplativeVoice().contextPolicy.includesThreadAnalysis)
        XCTAssertTrue(PhilosophicalVoice().contextPolicy.includesThreadAnalysis)
        XCTAssertFalse(ReflectiveVoice().contextPolicy.hoistsUnchangedBlock)
    }

    func testJournalingVoice_excludesMarkerLinesButKeepsThreadAnalysis() {
        XCTAssertFalse(JournalingVoice().contextPolicy.includesMarkerLines)
        XCTAssertTrue(JournalingVoice().contextPolicy.includesThreadAnalysis)
    }

    func testCreativeVoice_excludesMarkersAndThreadAnalysis() {
        XCTAssertFalse(CreativeVoice().contextPolicy.includesMarkerLines)
        XCTAssertFalse(CreativeVoice().contextPolicy.includesThreadAnalysis)
    }

    func testGratitudeVoice_excludesMarkersAndThreadAnalysis() {
        XCTAssertFalse(GratitudeVoice().contextPolicy.includesMarkerLines)
        XCTAssertFalse(GratitudeVoice().contextPolicy.includesThreadAnalysis)
    }

    func testCustomStyle_getsFullPolicyViaProtocolDefault() {
        let custom = CustomPromptStyle(
            id: UUID(), title: "Test", icon: "star", instruction: "Reflect on this walk."
        )
        XCTAssertTrue(custom.contextPolicy.includesMarkerLines)
        XCTAssertTrue(custom.contextPolicy.includesThreadAnalysis)
        XCTAssertFalse(custom.contextPolicy.hoistsUnchangedBlock)
    }

    // MARK: - Assembler integration

    private func contextWithDossiers() -> ActivityContext {
        .make(
            recordings: [RecordingContext(
                text: "the river was loud today", timestamp: DateFactory.makeDate(2024, 6, 15, 9, 5, 0),
                startCoordinate: nil, endCoordinate: nil, wordsPerMinute: 100,
                recordingUUID: UUID(), endTimestamp: nil
            )],
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            threadsDossier: "**Thought threads:**\nRecording 1: absolutist words 2.3%",
            threadsDossierWithoutMarkers: "**Thought threads:**\n'river' — 3 walks",
            unchangedBlock: "**Unchanged:**\n'river' has returned across 4 walks."
        )
    }

    func testAssembler_journaling_omitsMarkerPercentages() {
        let prompt = PromptAssembler.assemble(context: contextWithDossiers(), voice: JournalingVoice())
        XCTAssertFalse(prompt.contains("absolutist words 2.3%"))
    }

    func testAssembler_journaling_keepsThreadAnalysis() {
        let prompt = PromptAssembler.assemble(context: contextWithDossiers(), voice: JournalingVoice())
        XCTAssertTrue(prompt.contains("'river' — 3 walks"))
    }

    func testAssembler_reflective_keepsMarkerPercentages() {
        let prompt = PromptAssembler.assemble(context: contextWithDossiers(), voice: ReflectiveVoice())
        XCTAssertTrue(prompt.contains("absolutist words 2.3%"))
    }

    /// The brief's own selection sketch branches only on `includesMarkerLines`,
    /// which would hand Creative and Gratitude the markers-free-but-threads-on
    /// variant — still leaking thread analysis they asked to suppress. The
    /// selection must consult `includesThreadAnalysis` too.
    func testAssembler_creative_omitsThreadAnalysisEntirely() {
        let prompt = PromptAssembler.assemble(context: contextWithDossiers(), voice: CreativeVoice())
        XCTAssertFalse(prompt.contains("absolutist words 2.3%"))
        XCTAssertFalse(prompt.contains("'river' — 3 walks"))
    }

    func testAssembler_gratitude_omitsThreadAnalysisEntirely() {
        let prompt = PromptAssembler.assemble(context: contextWithDossiers(), voice: GratitudeVoice())
        XCTAssertFalse(prompt.contains("absolutist words 2.3%"))
        XCTAssertFalse(prompt.contains("'river' — 3 walks"))
    }

    func testAssembler_nonObliqueVoices_neverSeeUnchangedBlock() {
        for voice: PromptVoice in [
            ContemplativeVoice(), ReflectiveVoice(), CreativeVoice(),
            GratitudeVoice(), PhilosophicalVoice(), JournalingVoice()
        ] {
            let prompt = PromptAssembler.assemble(context: contextWithDossiers(), voice: voice)
            XCTAssertFalse(prompt.contains("**Unchanged:**"))
        }
    }

    /// The live defect this task fixes, pinned directly: Journaling's own
    /// response contract must never carry the interpretive key that explains
    /// how to read an absolutist share or modal lean — those referents were
    /// never printed in the dossier Journaling actually receives. Handing the
    /// key anyway would be worse than the original defect: vocabulary with no
    /// referent that the model would have to invent one for.
    func testAssembler_journaling_contractOmitsInterpretiveKey() {
        let prompt = PromptAssembler.assemble(context: contextWithDossiers(), voice: JournalingVoice())
        XCTAssertFalse(prompt.contains("Read the absolutist-word share"))
        XCTAssertFalse(prompt.contains("Read the modal lean"))
    }

    /// Same reasoning for Creative and Gratitude: their dossier is fully
    /// suppressed, so their response contract must carry no interpretive key
    /// at all — not even the clinical-language guard sentence, which is
    /// conditioned on `threadsDossier` being non-nil.
    func testAssembler_creativeAndGratitude_contractCarriesNoThreadsLanguage() {
        for voice: PromptVoice in [CreativeVoice(), GratitudeVoice()] {
            let prompt = PromptAssembler.assemble(context: contextWithDossiers(), voice: voice)
            XCTAssertFalse(prompt.contains("Read the absolutist-word share"))
            XCTAssertFalse(prompt.contains("Read the modal lean"))
            XCTAssertFalse(prompt.contains("descriptive on-device linguistic signals"))
        }
    }

    // MARK: - Review fix: Creative/Gratitude read Noticed:, not nothing

    /// `threadsDossierSensesOnly` mirrors what `ThreadsDossierBuilder` would
    /// actually hand it: just `**Noticed:**`, with a markerColoring line that
    /// must never have been in there in the first place (pinned at the
    /// builder level by `testMarkerColoring_neverReachesSensesOnlyVariant`) —
    /// this fixture asserts the same absence survives all the way to the
    /// assembled prompt.
    private func contextWithSensesOnlyDossier() -> ActivityContext {
        .make(
            recordings: [RecordingContext(
                text: "the river was loud today", timestamp: DateFactory.makeDate(2024, 6, 15, 9, 5, 0),
                startCoordinate: nil, endCoordinate: nil, wordsPerMinute: 100,
                recordingUUID: UUID(), endTimestamp: nil
            )],
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            threadsDossier: "**Thought threads (on-device linguistic analysis):**\nRecording 1: absolutist words 2.3%; self-focus 4.1%; sentiment 0.20\n\n**Threads across recent walks:**\n'river' — 3 walks\n\n**Noticed:**\n'river' has surfaced on 2 walks — twice near the same stretch of ground.",
            threadsDossierWithoutMarkers: "**Thought threads (on-device linguistic analysis):**\n\n**Threads across recent walks:**\n'river' — 3 walks\n\n**Noticed:**\n'river' has surfaced on 2 walks — twice near the same stretch of ground.",
            threadsDossierSensesOnly: "**Noticed:**\n'river' has surfaced on 2 walks — twice near the same stretch of ground."
        )
    }

    func testAssembler_creative_receivesNoticedBlock() {
        let prompt = PromptAssembler.assemble(context: contextWithSensesOnlyDossier(), voice: CreativeVoice())
        XCTAssertTrue(prompt.contains("**Noticed:**"))
        XCTAssertTrue(prompt.contains("'river' has surfaced on 2 walks"))
    }

    func testAssembler_creative_omitsMarkerAndSentimentFigures() {
        let prompt = PromptAssembler.assemble(context: contextWithSensesOnlyDossier(), voice: CreativeVoice())
        XCTAssertFalse(prompt.contains("absolutist words"))
        XCTAssertFalse(prompt.contains("self-focus"))
        XCTAssertFalse(prompt.contains("sentiment"))
    }

    func testAssembler_creative_omitsThreadSection() {
        let prompt = PromptAssembler.assemble(context: contextWithSensesOnlyDossier(), voice: CreativeVoice())
        XCTAssertFalse(prompt.contains("Threads across recent walks"))
        XCTAssertFalse(prompt.contains("Quiet this walk"))
    }

    /// The builder guarantees `threadsDossierSensesOnly` never carries a
    /// markerColoring line in the first place (pinned end-to-end at the
    /// builder level by `testMarkerColoring_neverReachesSensesOnlyVariant`
    /// in `ThreadsDossierSensesMarkerColoringLeakTests.swift`); this fixture
    /// mirrors that real shape and checks the assembled Creative prompt
    /// reflects it.
    func testAssembler_creative_omitsMarkerColoringLine() {
        let prompt = PromptAssembler.assemble(context: contextWithSensesOnlyDossier(), voice: CreativeVoice())
        XCTAssertFalse(prompt.contains("Absolutist words cluster around"))
    }

    func testAssembler_gratitude_receivesNoticedBlockWithoutThreadAnalysis() {
        let prompt = PromptAssembler.assemble(context: contextWithSensesOnlyDossier(), voice: GratitudeVoice())
        XCTAssertTrue(prompt.contains("**Noticed:**"))
        XCTAssertFalse(prompt.contains("absolutist words"))
        XCTAssertFalse(prompt.contains("Threads across recent walks"))
    }

    /// The policy leak, pinned the right way round. `includesThreadAnalysis:
    /// false` was read as "this voice receives no cross-walk thread claim",
    /// and the senses-only dossier was handed over on that premise — but four
    /// of the eight senses (`placeResonance`, `moonLine`, `weatherWeave`,
    /// `intentionLineage`) name a theme and count the walks it surfaced in,
    /// which is a cross-walk thread claim by any reading. Creative and
    /// Gratitude received exactly those claims and, because the guard was
    /// keyed on the policy rather than on the block actually selected, no
    /// instruction at all on how not to read them. The guard now follows the
    /// dossier.
    ///
    /// The interpretive key still teaches nothing: its probes look for marker
    /// phrasings ("absolutist words", "raw counts only", "modal lean:") that
    /// the senses-only variant never prints, so the accretion is the guard
    /// alone — vocabulary with no referent stays out, exactly as before.
    func testAssembler_creativeAndGratitude_sensesOnlyDossier_carriesTheClinicalGuard() {
        for voice: PromptVoice in [CreativeVoice(), GratitudeVoice()] {
            let prompt = PromptAssembler.assemble(context: contextWithSensesOnlyDossier(), voice: voice)
            XCTAssertTrue(prompt.contains("never produce clinical or diagnostic language"),
                          "a block that names a theme and counts walks is a thread claim, guard and all")
            XCTAssertFalse(prompt.contains("Read the absolutist-word share"))
            XCTAssertFalse(prompt.contains("Read the modal lean"),
                           "the senses-only variant prints no marker figures, so the key must stay silent")
        }
    }
}
