import XCTest
@testable import Pilgrim

final class ObliqueVoiceTests: XCTestCase {

    func testStyle_existsWithTitleAndDescription() {
        XCTAssertTrue(PromptStyle.allCases.contains(.oblique))
        XCTAssertEqual(PromptStyle.oblique.title, "Oblique")
        XCTAssertEqual(PromptStyle.oblique.description, "What has not moved")
    }

    func testPolicy_hoistsUnchangedBlock() {
        XCTAssertTrue(ObliqueVoice().contextPolicy.hoistsUnchangedBlock)
        XCTAssertTrue(ObliqueVoice().contextPolicy.includesMarkerLines)
    }

    func testConstraints_banContentlessReframeInstructions() {
        let joined = ObliqueVoice().responseConstraints(hasSpeech: true).joined(separator: " ")
        XCTAssertTrue(joined.contains("perhaps consider"))
        XCTAssertTrue(joined.contains("outside the box"))
        XCTAssertTrue(joined.contains("never assert a pattern that block does not show"))
    }

    func testConstraints_areExactlyFour() {
        XCTAssertEqual(ObliqueVoice().responseConstraints(hasSpeech: true).count, 4)
    }

    func testAssembler_obliqueHoistsBlockAboveTranscription() {
        let context = ActivityContext.make(
            recordings: [RecordingContext(
                text: "the river was loud today", timestamp: DateFactory.makeDate(2024, 6, 15, 9, 5, 0),
                startCoordinate: nil, endCoordinate: nil, wordsPerMinute: 100,
                recordingUUID: UUID(), endTimestamp: nil
            )],
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            unchangedBlock: "**Unchanged:**\n'river' has returned across 4 walks."
        )
        let prompt = PromptAssembler.assemble(context: context, voice: ObliqueVoice())
        let unchangedIndex = prompt.range(of: "**Unchanged:**")?.lowerBound
        let transcriptionIndex = prompt.range(of: "**Walking Transcription:**")?.lowerBound
        XCTAssertNotNil(unchangedIndex)
        XCTAssertNotNil(transcriptionIndex)
        XCTAssertLessThan(unchangedIndex!, transcriptionIndex!)
    }

    // MARK: - Picker gate

    /// The gate is the presence of the `Unchanged:` block itself, not a
    /// walk-count threshold — `unchangedBlock` is already nil whenever the
    /// current walk is silent, history is thin, or history is deep but
    /// nothing has held still yet (`DossierSensesInvariance.minimumInvariantWalks`
    /// qualifying walks are required before any signal can fire). Checking
    /// the block directly is the only gate that cannot tell `ObliqueVoice`
    /// to read a block that is not in the prompt.
    func testAvailability_obliqueGatedOnUnchangedBlockPresence() {
        XCTAssertFalse(PromptStyle.oblique.isAvailable(unchangedBlockPresent: false))
        XCTAssertTrue(PromptStyle.oblique.isAvailable(unchangedBlockPresent: true))
    }

    func testAvailability_otherStylesAlwaysAvailable() {
        for style in PromptStyle.allCases where style != .oblique {
            XCTAssertTrue(style.isAvailable(unchangedBlockPresent: false))
        }
    }

    func testWaitingCopy_onlyObliqueHasIt() {
        XCTAssertEqual(PromptStyle.oblique.waitingCopy, "Still listening. A few more walks with your voice.")
        XCTAssertNil(PromptStyle.reflective.waitingCopy)
    }

    /// Deliberate symmetry: the gate means Oblique is never assembled with
    /// `hasSpeech: false` (a silent current walk yields no `unchangedBlock`,
    /// which is the gate). The `hasSpeech: false` branch exists only for
    /// protocol conformance and must read identically to the reachable
    /// branch — pinned here so the two can never quietly drift apart.
    func testPreambleAndInstruction_hasSpeechFalseMatchesHasSpeechTrue() {
        let voice = ObliqueVoice()
        XCTAssertEqual(voice.preamble(hasSpeech: false), voice.preamble(hasSpeech: true))
        XCTAssertEqual(voice.instruction(hasSpeech: false), voice.instruction(hasSpeech: true))
    }
}
