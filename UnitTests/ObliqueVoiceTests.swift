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
}
