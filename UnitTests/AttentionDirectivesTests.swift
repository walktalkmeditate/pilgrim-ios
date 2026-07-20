import XCTest
@testable import Pilgrim

/// The assembler injects a dossier of context; attention directives turn it
/// into pursuit — deterministic pattern detection that tells the downstream
/// model what is remarkable about *this* walk. Each detector must fire only
/// when its pattern is genuinely present.
final class AttentionDirectivesTests: XCTestCase {

    private let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)

    private func recording(_ text: String, offset: TimeInterval = 300) -> RecordingContext {
        RecordingContext(
            text: text,
            timestamp: start.addingTimeInterval(offset),
            startCoordinate: nil,
            endCoordinate: nil,
            wordsPerMinute: nil
        )
    }

    private func joined(_ context: ActivityContext) -> String {
        AttentionDirectives.detect(context: context).joined(separator: "\n")
    }

    // MARK: - Pace shift

    func testPaceShift_slowingFinalThird_fires() {
        let speeds = Array(repeating: 1.5, count: 20) + Array(repeating: 1.2, count: 20) + Array(repeating: 0.9, count: 20)
        let context = ActivityContext.make(startDate: start, routeSpeeds: speeds)
        XCTAssertTrue(joined(context).contains("slowed"))
    }

    func testPaceShift_uniformPace_doesNotFire() {
        let context = ActivityContext.make(startDate: start, routeSpeeds: Array(repeating: 1.4, count: 60))
        XCTAssertFalse(joined(context).contains("slowed"))
        XCTAssertFalse(joined(context).contains("quickened"))
    }

    // MARK: - Stillness

    func testStillness_longStillRunWithoutMeditation_fires() {
        let speeds = Array(repeating: 1.4, count: 40) + Array(repeating: 0.0, count: 20) + Array(repeating: 1.4, count: 40)
        let context = ActivityContext.make(duration: 3600, startDate: start, routeSpeeds: speeds)
        XCTAssertTrue(joined(context).contains("stillness"))
    }

    func testStillness_coveredByMeditation_doesNotFire() {
        let speeds = Array(repeating: 1.4, count: 40) + Array(repeating: 0.0, count: 20) + Array(repeating: 1.4, count: 40)
        let meditation = MeditationContext(
            startDate: start.addingTimeInterval(600),
            endDate: start.addingTimeInterval(1500),
            duration: 900
        )
        let context = ActivityContext.make(
            meditations: [meditation], duration: 3600, startDate: start, routeSpeeds: speeds
        )
        XCTAssertFalse(joined(context).contains("stillness"),
                       "stillness explained by a logged meditation is not news")
    }

    // MARK: - Intention echo

    func testIntentionEcho_intentionWordSpoken_fires() {
        let context = ActivityContext.make(
            recordings: [recording("I keep coming back to release, letting the grip soften")],
            startDate: start,
            intention: "Release what I cannot carry"
        )
        XCTAssertTrue(joined(context).contains("surfaces again"))
    }

    func testIntentionEcho_noOverlap_doesNotFire() {
        let context = ActivityContext.make(
            recordings: [recording("The bakery smelled wonderful this morning")],
            startDate: start,
            intention: "Release what I cannot carry"
        )
        XCTAssertFalse(joined(context).contains("surfaces again"))
    }

    // MARK: - Recurring word

    func testRecurringWord_wordReturnsThreeTimes_fires() {
        let context = ActivityContext.make(
            recordings: [
                recording("The river was high today"),
                recording("I crossed the river at the old bridge", offset: 900),
                recording("Something about the river keeps pulling me", offset: 1500)
            ],
            startDate: start
        )
        XCTAssertTrue(joined(context).contains("river"))
        XCTAssertTrue(joined(context).contains("returns"))
    }

    func testRecurringWord_allWordsUnique_doesNotFire() {
        let context = ActivityContext.make(
            recordings: [recording("Cold wind moving between bare branches")],
            startDate: start
        )
        XCTAssertFalse(joined(context).contains("returns"))
    }

    // MARK: - First vs last recording

    func testFirstVersusLast_twoRecordings_fires() {
        let context = ActivityContext.make(
            recordings: [recording("Setting out heavy"), recording("Coming home lighter", offset: 3000)],
            startDate: start
        )
        XCTAssertTrue(joined(context).contains("first recording"))
    }

    func testFirstVersusLast_singleRecording_doesNotFire() {
        let context = ActivityContext.make(
            recordings: [recording("Just one thought today")],
            startDate: start
        )
        XCTAssertFalse(joined(context).contains("first recording"))
    }

    // MARK: - Cap and assembly

    func testDirectives_cappedAtFour() {
        let speeds = Array(repeating: 1.5, count: 30)
            + Array(repeating: 0.0, count: 30)
            + Array(repeating: 0.8, count: 30)
        let context = ActivityContext.make(
            recordings: [
                recording("Release the river from its banks"),
                recording("The river again, release again", offset: 900),
                recording("Still the river", offset: 1500)
            ],
            duration: 3600,
            startDate: start,
            routeSpeeds: speeds,
            intention: "Release what I cannot carry"
        )
        XCTAssertLessThanOrEqual(AttentionDirectives.detect(context: context).count, 4)
    }

    func testAssembler_includesSectionOnlyWhenDirectivesFire() {
        let quiet = ActivityContext.make(startDate: start)
        let quietPrompt = PromptGenerator.generate(style: .reflective, context: quiet)
        XCTAssertFalse(quietPrompt.text.contains("**Attend to:**"))

        let telling = ActivityContext.make(
            recordings: [recording("Setting out"), recording("Returning", offset: 3000)],
            startDate: start
        )
        let tellingPrompt = PromptGenerator.generate(style: .reflective, context: telling)
        XCTAssertTrue(tellingPrompt.text.contains("**Attend to:**"))
    }
}
