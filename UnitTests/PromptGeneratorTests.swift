import XCTest
@testable import Pilgrim

final class PromptGeneratorTests: XCTestCase {

    func testGenerateAll_returnsOnePerStyle() {
        let prompts = PromptGenerator.generateAll(
            recordings: [],
            duration: 1800,
            distance: 2000,
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        )
        XCTAssertEqual(prompts.count, 6)
        let styles = Set(prompts.map { $0.style })
        XCTAssertEqual(styles.count, PromptStyle.allCases.count)
    }

    func testGenerate_containsTranscriptionText() {
        let recording = PromptGenerator.RecordingContext(
            text: "The birds are singing beautifully today",
            timestamp: DateFactory.makeDate(2024, 6, 15, 9, 5, 0),
            startCoordinate: nil,
            endCoordinate: nil
        )
        let prompt = PromptGenerator.generate(
            style: .reflective,
            recordings: [recording],
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
            endCoordinate: nil
        )
        let prompt = PromptGenerator.generate(
            style: .reflective,
            recordings: [recording],
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
            endCoordinate: nil
        )
        let prompt = PromptGenerator.generate(
            style: .reflective,
            recordings: [recording],
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
            duration: 1800,
            distance: 2000,
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        )
        XCTAssertFalse(prompt.text.isEmpty)
        XCTAssertTrue(prompt.text.contains("Walking Transcription"))
    }
}
