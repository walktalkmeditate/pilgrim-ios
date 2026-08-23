import XCTest
@testable import Pilgrim

final class PromptAssemblerLanguageTests: XCTestCase {

    private let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)

    private func assembled(_ text: String) -> String {
        let context = ActivityContext.make(
            recordings: [RecordingContext(
                text: text, timestamp: start,
                startCoordinate: nil, endCoordinate: nil, wordsPerMinute: nil
            )],
            startDate: start
        )
        return PromptGenerator.generate(style: .reflective, context: context).text
    }

    func testSpanishTranscript_notesDetectedLanguage() {
        let prompt = assembled("Sigo pensando en la mudanza y en si deberíamos irnos de aquí este otoño")
        XCTAssertTrue(prompt.contains("**Detected language:**"))
        XCTAssertTrue(prompt.contains("Spanish"))
    }

    func testNoSpeech_noLanguageNote() {
        let context = ActivityContext.make(startDate: start)
        let prompt = PromptGenerator.generate(style: .reflective, context: context).text
        XCTAssertFalse(prompt.contains("**Detected language:**"))
    }
}
