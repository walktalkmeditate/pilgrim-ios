import XCTest
@testable import Pilgrim

/// Every generated prompt must end with a response contract: the downstream
/// LLM is told how to answer (voice-specific form constraints) and what it
/// may never do (invent details, ignore the walker's language, flatten a
/// two-voice recording into a monologue).
final class PromptResponseContractTests: XCTestCase {

    private let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)

    private func spokenContext() -> ActivityContext {
        ActivityContext.make(
            recordings: [
                RecordingContext(
                    text: "The fog is lifting off the river",
                    timestamp: start.addingTimeInterval(300),
                    startCoordinate: nil,
                    endCoordinate: nil,
                    wordsPerMinute: nil
                )
            ],
            startDate: start
        )
    }

    private func silentContext() -> ActivityContext {
        ActivityContext.make(startDate: start)
    }

    func testEveryStyle_includesContractSection() {
        for prompt in PromptGenerator.generateAll(context: spokenContext()) {
            XCTAssertTrue(prompt.text.contains("**How to respond:**"),
                          "\(prompt.title) must carry a response contract")
        }
    }

    func testAntiFabricationLine_presentEvenOnSilentWalks() {
        for prompt in PromptGenerator.generateAll(context: silentContext()) {
            XCTAssertTrue(prompt.text.contains("never invent"),
                          "\(prompt.title) must forbid fabricated details")
        }
    }

    func testLanguageLine_presentWithSpeech() {
        let prompt = PromptGenerator.generate(style: .reflective, context: spokenContext())
        XCTAssertTrue(prompt.text.contains("in the language"))
    }

    func testLanguageLine_absentWithoutSpeech() {
        let prompt = PromptGenerator.generate(style: .reflective, context: silentContext())
        XCTAssertFalse(prompt.text.contains("in the language"),
                       "no transcript means no language to mirror")
    }

    func testMultiVoiceLine_presentWithSpeech_absentWithout() {
        let spoken = PromptGenerator.generate(style: .contemplative, context: spokenContext())
        XCTAssertTrue(spoken.text.contains("more than one voice"))

        let silent = PromptGenerator.generate(style: .contemplative, context: silentContext())
        XCTAssertFalse(silent.text.contains("more than one voice"))
    }

    func testContemplative_limitsQuestions() {
        let prompt = PromptGenerator.generate(style: .contemplative, context: spokenContext())
        XCTAssertTrue(prompt.text.contains("at most one question"))
    }

    func testCreative_repliesWithThePieceItself() {
        let prompt = PromptGenerator.generate(style: .creative, context: spokenContext())
        XCTAssertTrue(prompt.text.contains("no introduction"))
    }

    func testCustomStyle_carriesSharedContract() {
        let custom = CustomPromptStyle(
            id: UUID(),
            title: "Letters",
            icon: "envelope",
            instruction: "Write me a letter about this walk."
        )
        let prompt = PromptGenerator.generateCustom(customStyle: custom, context: spokenContext())
        XCTAssertTrue(prompt.text.contains("**How to respond:**"))
        XCTAssertTrue(prompt.text.contains("never invent"))
    }
}
