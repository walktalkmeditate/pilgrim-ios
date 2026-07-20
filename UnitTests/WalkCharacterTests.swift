import XCTest
@testable import Pilgrim

/// Two different walks must not open with identical prose. WalkCharacter
/// distills what made this walk distinct (length, hour, moon, stillness)
/// into a preamble note every style — including custom styles — carries.
final class WalkCharacterTests: XCTestCase {

    private let morning = DateFactory.makeLocalDate(2024, 6, 15, 10, 0, 0)
    private let night = DateFactory.makeLocalDate(2024, 6, 15, 21, 30, 0)

    private let halfMoon = LunarPhase(illumination: 0.5, age: 7.4, name: "First Quarter")
    private let fullMoon = LunarPhase(illumination: 0.99, age: 14.7, name: "Full Moon")

    func testNote_ordinaryDayWalk_isNil() {
        let context = ActivityContext.make(duration: 1800, startDate: morning, lunarPhase: halfMoon)
        XCTAssertNil(WalkCharacter.note(context: context))
    }

    func testNote_longNightWalk_namesBoth() {
        let context = ActivityContext.make(duration: 5400, startDate: night, lunarPhase: halfMoon)
        let note = WalkCharacter.note(context: context)
        XCTAssertTrue(note?.contains("long walk") == true)
        XCTAssertTrue(note?.contains("night") == true)
    }

    func testNote_briefWalk_honorsBrevity() {
        let context = ActivityContext.make(duration: 600, startDate: morning, lunarPhase: halfMoon)
        XCTAssertTrue(WalkCharacter.note(context: context)?.contains("brief") == true)
    }

    func testNote_fullMoon_isNamed() {
        let context = ActivityContext.make(duration: 1800, startDate: morning, lunarPhase: fullMoon)
        XCTAssertTrue(WalkCharacter.note(context: context)?.contains("full moon") == true)
    }

    func testNote_meditatedWalk_namesStillness() {
        let meditation = MeditationContext(
            startDate: morning.addingTimeInterval(600),
            endDate: morning.addingTimeInterval(1200),
            duration: 600
        )
        let context = ActivityContext.make(
            meditations: [meditation], duration: 1800, startDate: morning, lunarPhase: halfMoon
        )
        XCTAssertTrue(WalkCharacter.note(context: context)?.contains("stillness") == true)
    }

    func testAssembler_weavesNoteIntoEveryStyle() {
        let context = ActivityContext.make(duration: 5400, startDate: night, lunarPhase: halfMoon)
        for prompt in PromptGenerator.generateAll(context: context) {
            XCTAssertTrue(prompt.text.contains("long walk"),
                          "\(prompt.title) must carry the walk's character")
        }
    }

    func testCustomStyle_sharesStandardPreambleAndNote() {
        let custom = CustomPromptStyle(
            id: UUID(), title: "Letters", icon: "envelope",
            instruction: "Write me a letter about this walk."
        )
        let context = ActivityContext.make(duration: 5400, startDate: night, lunarPhase: halfMoon)
        let prompt = PromptGenerator.generateCustom(customStyle: custom, context: context)
        XCTAssertTrue(prompt.text.contains(StandardPreamble.text(hasSpeech: false)),
                      "custom styles must share the standard preamble, not a hardcoded copy")
        XCTAssertTrue(prompt.text.contains("long walk"))
    }
}
