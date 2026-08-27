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
}
