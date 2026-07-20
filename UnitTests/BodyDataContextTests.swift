import XCTest
@testable import Pilgrim

/// The body's data — pauses, climb, the light changing between setting out
/// and coming home — was already recorded but never reached the prompt.
/// Each section must appear only when it means something.
final class BodyDataContextTests: XCTestCase {

    private let start = DateFactory.makeLocalDate(2024, 6, 15, 9, 0, 0)

    // MARK: - Pauses

    func testFormatPauses_empty_isNil() {
        XCTAssertNil(ContextFormatter.formatPauses([]))
    }

    func testFormatPauses_namesCountTotalAndLongest() {
        let pauses = [
            PauseContext(startDate: start.addingTimeInterval(600), duration: 180),
            PauseContext(startDate: start.addingTimeInterval(2400), duration: 300)
        ]
        let text = ContextFormatter.formatPauses(pauses)
        XCTAssertTrue(text?.contains("**Pauses:**") == true)
        XCTAssertTrue(text?.contains("2 times") == true)
        XCTAssertTrue(text?.contains("5 min") == true)
    }

    func testFormatPauses_subMinutePausesAreIgnored() {
        let breath = PauseContext(startDate: start.addingTimeInterval(600), duration: 20)
        XCTAssertNil(ContextFormatter.formatPauses([breath]),
                     "a 20-second pause must not render as 'Paused 1 time (0 min total)'")

        let mixed = [breath, PauseContext(startDate: start.addingTimeInterval(1200), duration: 300)]
        let text = ContextFormatter.formatPauses(mixed)
        XCTAssertTrue(text?.contains("1 time (5 min total)") == true)
    }

    // MARK: - Elevation

    func testFormatElevation_flatWalk_isNil() {
        XCTAssertNil(ContextFormatter.formatElevation(ascent: 5, descent: 5))
        XCTAssertNil(ContextFormatter.formatElevation(ascent: nil, descent: nil))
    }

    func testFormatElevation_climb_isNamed() {
        let text = ContextFormatter.formatElevation(ascent: 120, descent: 80)
        XCTAssertTrue(text?.contains("**Elevation:**") == true)
        XCTAssertTrue(text?.contains("climbed") == true)
    }

    // MARK: - Light crossing

    func testMetadata_walkCrossingIntoNight_namesBothHours() {
        let eveningStart = DateFactory.makeLocalDate(2024, 6, 15, 17, 30, 0)
        let text = ContextFormatter.formatMetadata(
            duration: 10800, distance: 9000, startDate: eveningStart
        )
        XCTAssertTrue(text.contains("began in the evening"))
        XCTAssertTrue(text.contains("ended in the night"))
    }

    func testMetadata_pausedWalk_endsAtWallClockTimeOfDay() {
        let eveningStart = DateFactory.makeLocalDate(2024, 6, 15, 17, 30, 0)
        let text = ContextFormatter.formatMetadata(
            duration: 7200, distance: 6000, startDate: eveningStart, pauseDuration: 3600
        )
        XCTAssertTrue(text.contains("ended in the night"),
                      "an hour of pauses pushes the real end past the active-duration end")
    }

    func testMetadata_walkWithinOneHour_keepsSingleTimeOfDay() {
        let text = ContextFormatter.formatMetadata(
            duration: 1800, distance: 2000, startDate: start
        )
        XCTAssertTrue(text.contains("morning on"))
        XCTAssertFalse(text.contains("began in the"))
    }

    // MARK: - Assembly

    func testAssembler_includesBodySectionsWhenPresent() {
        let context = ActivityContext.make(
            startDate: start,
            pauses: [PauseContext(startDate: start.addingTimeInterval(600), duration: 240)],
            ascent: 150,
            descent: 40
        )
        let prompt = PromptGenerator.generate(style: .contemplative, context: context)
        XCTAssertTrue(prompt.text.contains("**Pauses:**"))
        XCTAssertTrue(prompt.text.contains("**Elevation:**"))
    }

    func testAssembler_omitsBodySectionsWhenAbsent() {
        let prompt = PromptGenerator.generate(
            style: .contemplative,
            context: ActivityContext.make(startDate: start)
        )
        XCTAssertFalse(prompt.text.contains("**Pauses:**"))
        XCTAssertFalse(prompt.text.contains("**Elevation:**"))
    }
}
