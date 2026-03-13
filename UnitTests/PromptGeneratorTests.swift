import XCTest
@testable import Pilgrim

final class PromptGeneratorTests: XCTestCase {

    func testGenerateAll_returnsOnePerStyle() {
        let prompts = PromptGenerator.generateAll(
            recordings: [],
            meditations: [],
            duration: 1800,
            distance: 2000,
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        )
        XCTAssertEqual(prompts.count, 6)
        let styles = Set(prompts.compactMap { $0.style })
        XCTAssertEqual(styles.count, PromptStyle.allCases.count)
    }

    func testGenerate_containsTranscriptionText() {
        let recording = PromptGenerator.RecordingContext(
            text: "The birds are singing beautifully today",
            timestamp: DateFactory.makeDate(2024, 6, 15, 9, 5, 0),
            startCoordinate: nil,
            endCoordinate: nil,
            wordsPerMinute: nil
        )
        let prompt = PromptGenerator.generate(
            style: .reflective,
            recordings: [recording],
            meditations: [],
            duration: 1800,
            distance: 2000,
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        )
        XCTAssertTrue(prompt.text.contains("The birds are singing beautifully today"))
    }

    func testGenerate_containsFormattedDuration() {
        let prompt = PromptGenerator.generate(
            style: .contemplative,
            recordings: [],
            meditations: [],
            duration: 1800,
            distance: 2000,
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        )
        XCTAssertTrue(prompt.text.contains("30 minutes"))
    }

    func testTimeOfDay_earlyMorning() {
        let prompt = PromptGenerator.generate(
            style: .contemplative,
            recordings: [],
            meditations: [],
            duration: 1800,
            distance: 2000,
            startDate: DateFactory.makeLocalDate(2024, 6, 15, 5, 0, 0)
        )
        XCTAssertTrue(prompt.text.contains("early morning"))
    }

    func testTimeOfDay_midday() {
        let prompt = PromptGenerator.generate(
            style: .contemplative,
            recordings: [],
            meditations: [],
            duration: 1800,
            distance: 2000,
            startDate: DateFactory.makeLocalDate(2024, 6, 15, 12, 0, 0)
        )
        XCTAssertTrue(prompt.text.contains("midday"))
    }

    func testTimeOfDay_night() {
        let prompt = PromptGenerator.generate(
            style: .contemplative,
            recordings: [],
            meditations: [],
            duration: 1800,
            distance: 2000,
            startDate: DateFactory.makeLocalDate(2024, 6, 15, 22, 0, 0)
        )
        XCTAssertTrue(prompt.text.contains("night"))
    }

    func testGenerate_recordingWithGPS_containsCoordinates() {
        let recording = PromptGenerator.RecordingContext(
            text: "Walking in the park",
            timestamp: DateFactory.makeDate(2024, 6, 15, 9, 5, 0),
            startCoordinate: (lat: 48.85660, lon: 2.35220),
            endCoordinate: nil,
            wordsPerMinute: nil
        )
        let prompt = PromptGenerator.generate(
            style: .reflective,
            recordings: [recording],
            meditations: [],
            duration: 1800,
            distance: 2000,
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        )
        XCTAssertTrue(prompt.text.contains("GPS"))
        XCTAssertTrue(prompt.text.contains("48.85660"))
    }

    func testGenerate_recordingWithoutGPS_omitsCoordinates() {
        let recording = PromptGenerator.RecordingContext(
            text: "Walking in the park",
            timestamp: DateFactory.makeDate(2024, 6, 15, 9, 5, 0),
            startCoordinate: nil,
            endCoordinate: nil,
            wordsPerMinute: nil
        )
        let prompt = PromptGenerator.generate(
            style: .reflective,
            recordings: [recording],
            meditations: [],
            duration: 1800,
            distance: 2000,
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        )
        XCTAssertFalse(prompt.text.contains("GPS"))
    }

    func testGenerate_emptyRecordings_producesValidPrompt() {
        let prompt = PromptGenerator.generate(
            style: .journaling,
            recordings: [],
            meditations: [],
            duration: 1800,
            distance: 2000,
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        )
        XCTAssertFalse(prompt.text.isEmpty)
        XCTAssertTrue(prompt.text.contains("Walking Transcription"))
    }

    func testGeneratedPrompt_builtInStyle_titleFromStyle() {
        let prompt = GeneratedPrompt(style: .reflective, customStyle: nil, text: "test")
        XCTAssertEqual(prompt.title, "Reflective")
        XCTAssertEqual(prompt.icon, "eye.fill")
        XCTAssertEqual(prompt.subtitle, "Identify patterns and emotional undercurrents")
    }

    func testGeneratedPrompt_customStyle_titleFromCustom() {
        let custom = CustomPromptStyle(id: UUID(), title: "My Style", icon: "star.fill", instruction: "Do something creative")
        let prompt = GeneratedPrompt(style: nil, customStyle: custom, text: "test")
        XCTAssertEqual(prompt.title, "My Style")
        XCTAssertEqual(prompt.icon, "star.fill")
        XCTAssertEqual(prompt.subtitle, "Do something creative")
    }

    func testGenerate_recordingWithWPM_containsPaceLabel() {
        let recording = PromptGenerator.RecordingContext(
            text: "Quick excited thoughts",
            timestamp: DateFactory.makeDate(2024, 6, 15, 9, 5, 0),
            startCoordinate: nil,
            endCoordinate: nil,
            wordsPerMinute: 85
        )
        let prompt = PromptGenerator.generate(
            style: .reflective,
            recordings: [recording],
            meditations: [],
            duration: 1800,
            distance: 2000,
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        )
        XCTAssertTrue(prompt.text.contains("~85 wpm"))
        XCTAssertTrue(prompt.text.contains("slow/thoughtful"))
    }

    func testGenerate_recordingWithoutWPM_omitsPaceLabel() {
        let recording = PromptGenerator.RecordingContext(
            text: "Just walking",
            timestamp: DateFactory.makeDate(2024, 6, 15, 9, 5, 0),
            startCoordinate: nil,
            endCoordinate: nil,
            wordsPerMinute: nil
        )
        let prompt = PromptGenerator.generate(
            style: .reflective,
            recordings: [recording],
            meditations: [],
            duration: 1800,
            distance: 2000,
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        )
        XCTAssertFalse(prompt.text.contains("wpm"))
    }
}
