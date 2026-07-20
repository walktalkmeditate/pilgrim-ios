import XCTest
@testable import Pilgrim

/// The downstream model shouldn't read Pilgrim's data as fitness telemetry.
/// The practice lexicon teaches it the walk's ritual grammar — what a wander
/// is, what a Seek means, what this seek's story was — in the app's own
/// vocabulary.
final class PracticeLexiconTests: XCTestCase {

    private let start = DateFactory.makeLocalDate(2024, 6, 15, 8, 30, 0)

    func testWanderWalk_explainsItself() {
        let context = ActivityContext.make(startDate: start)
        let prompt = PromptGenerator.generate(style: .contemplative, context: context)
        XCTAssertTrue(prompt.text.contains("**About this practice:**"))
        XCTAssertTrue(prompt.text.contains("the path chose itself"))
    }

    func testSeekWalk_explainsTheSurrender() {
        let context = ActivityContext.make(
            startDate: start,
            mode: .seek,
            seekStory: SeekStoryContext(arrivalTimes: [start.addingTimeInterval(1800)])
        )
        let prompt = PromptGenerator.generate(style: .contemplative, context: context)
        XCTAssertTrue(prompt.text.contains("surrendered"))
        XCTAssertTrue(prompt.text.contains("consent to be led"))
    }

    func testSeekStory_arrivalsCarryTheirHours() {
        let morningArrival = DateFactory.makeLocalDate(2024, 6, 15, 9, 30, 0)
        let eveningArrival = DateFactory.makeLocalDate(2024, 6, 15, 18, 30, 0)
        let context = ActivityContext.make(
            startDate: start,
            mode: .seek,
            seekStory: SeekStoryContext(arrivalTimes: [morningArrival, eveningArrival])
        )
        let prompt = PromptGenerator.generate(style: .reflective, context: context)
        XCTAssertTrue(prompt.text.contains("2 clearings"))
        XCTAssertTrue(prompt.text.contains("morning"))
        XCTAssertTrue(prompt.text.contains("evening"))
    }

    func testSeekStory_zeroArrivalIsHonored() {
        let context = ActivityContext.make(
            startDate: start,
            mode: .seek,
            seekStory: SeekStoryContext(arrivalTimes: [])
        )
        let prompt = PromptGenerator.generate(style: .contemplative, context: context)
        XCTAssertTrue(prompt.text.contains("No clearing was reached"))
    }

    func testWalkPracticeModel_noSeekEvent_isWander() {
        let practice = WalkPracticeModel.practice(events: [(.marker, start)])
        XCTAssertEqual(practice.mode, .wander)
        XCTAssertNil(practice.seekStory)
    }

    func testWalkPracticeModel_seekEvent_collectsSortedArrivals() {
        let late = start.addingTimeInterval(2800)
        let early = start.addingTimeInterval(1400)
        let practice = WalkPracticeModel.practice(events: [
            (.seekMode, start), (.seekArrival, late), (.seekArrival, early)
        ])
        XCTAssertEqual(practice.mode, .seek)
        XCTAssertEqual(practice.seekStory?.arrivalTimes, [early, late])
    }

    func testWalkPracticeModel_seekWithoutArrivals_keepsEmptyStory() {
        let practice = WalkPracticeModel.practice(events: [(.seekMode, start)])
        XCTAssertEqual(practice.mode, .seek)
        XCTAssertEqual(practice.seekStory?.arrivalTimes, [])
    }

    func testCustomStyle_carriesTheLexicon() {
        let custom = CustomPromptStyle(
            id: UUID(), title: "Letters", icon: "envelope",
            instruction: "Write me a letter about this walk."
        )
        let context = ActivityContext.make(startDate: start)
        let prompt = PromptGenerator.generateCustom(customStyle: custom, context: context)
        XCTAssertTrue(prompt.text.contains("**About this practice:**"))
    }
}
