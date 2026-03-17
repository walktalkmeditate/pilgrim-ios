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
        XCTAssertFalse(prompt.text.contains("Walking Transcription"))
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

    func testFormatPlaceNames_startOnly_containsNear() {
        let prompt = PromptGenerator.generate(
            style: .reflective,
            recordings: [],
            meditations: [],
            duration: 1800,
            distance: 2000,
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            placeNames: [
                PromptGenerator.PlaceContext(name: "Riverside Park, Manhattan", coordinate: (lat: 40.8, lon: -73.97), role: .start)
            ]
        )
        XCTAssertTrue(prompt.text.contains("Near Riverside Park, Manhattan"))
    }

    func testFormatPlaceNames_startAndEnd_containsArrow() {
        let prompt = PromptGenerator.generate(
            style: .reflective,
            recordings: [],
            meditations: [],
            duration: 1800,
            distance: 2000,
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            placeNames: [
                PromptGenerator.PlaceContext(name: "Riverside Park", coordinate: (lat: 40.8, lon: -73.97), role: .start),
                PromptGenerator.PlaceContext(name: "Central Park", coordinate: (lat: 40.78, lon: -73.96), role: .end)
            ]
        )
        XCTAssertTrue(prompt.text.contains("Started near Riverside Park"))
        XCTAssertTrue(prompt.text.contains("Central Park"))
    }

    func testFormatPlaceNames_empty_omitsLocationSection() {
        let prompt = PromptGenerator.generate(
            style: .reflective,
            recordings: [],
            meditations: [],
            duration: 1800,
            distance: 2000,
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            placeNames: []
        )
        XCTAssertFalse(prompt.text.contains("Location"))
    }

    // MARK: - Task 8: Pace Context

    func testFormatPaceContext_withSpeedData_containsAveragePace() {
        let prompt = PromptGenerator.generate(
            style: .reflective,
            recordings: [],
            meditations: [],
            duration: 1800,
            distance: 2000,
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            routeSpeeds: [1.5, 1.6, 1.4, 1.5, 1.3, 1.7, 1.5, 1.4, 1.6, 1.5, 1.5]
        )
        XCTAssertTrue(prompt.text.contains("Pace"))
        XCTAssertTrue(prompt.text.contains("min/"))
    }

    func testFormatPaceContext_sparseData_omitsPaceSection() {
        let prompt = PromptGenerator.generate(
            style: .reflective,
            recordings: [],
            meditations: [],
            duration: 1800,
            distance: 2000,
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            routeSpeeds: [1.5, 1.6]
        )
        XCTAssertFalse(prompt.text.contains("Pace"))
    }

    func testFormatPaceContext_empty_omitsPaceSection() {
        let prompt = PromptGenerator.generate(
            style: .reflective,
            recordings: [],
            meditations: [],
            duration: 1800,
            distance: 2000,
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            routeSpeeds: []
        )
        XCTAssertFalse(prompt.text.contains("Pace"))
    }

    // MARK: - Task 9: Walk-to-Walk Threading

    func testFormatRecentWalks_withSnippets_containsContinuitySection() {
        let snippets = [
            PromptGenerator.WalkSnippet(
                date: DateFactory.makeDate(2024, 6, 12, 9, 0, 0),
                placeName: nil,
                transcriptionPreview: "I keep thinking about how the river reminds me of home"
            ),
            PromptGenerator.WalkSnippet(
                date: DateFactory.makeDate(2024, 6, 10, 9, 0, 0),
                placeName: nil,
                transcriptionPreview: "Today I noticed I was walking faster than usual"
            )
        ]
        let prompt = PromptGenerator.generate(
            style: .reflective,
            recordings: [],
            meditations: [],
            duration: 1800,
            distance: 2000,
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            recentWalkSnippets: snippets
        )
        XCTAssertTrue(prompt.text.contains("Recent Walk Context"))
        XCTAssertTrue(prompt.text.contains("river reminds me of home"))
    }

    func testFormatRecentWalks_empty_omitsSection() {
        let prompt = PromptGenerator.generate(
            style: .reflective,
            recordings: [],
            meditations: [],
            duration: 1800,
            distance: 2000,
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            recentWalkSnippets: []
        )
        XCTAssertFalse(prompt.text.contains("Recent Walk Context"))
    }

    // MARK: - Task 10: Custom Prompt Generation

    func testGenerateCustom_silentWalk_usesSilentPreamble() {
        let custom = CustomPromptStyle(id: UUID(), title: "Letter", icon: "envelope.fill", instruction: "Write a letter")
        let prompt = PromptGenerator.generateCustom(
            customStyle: custom,
            recordings: [],
            meditations: [],
            duration: 1800,
            distance: 2000,
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        )
        XCTAssertTrue(prompt.text.contains("silence"))
        XCTAssertFalse(prompt.text.contains("voice recordings captured"))
    }

    // MARK: - Silent Walk Prompts

    func testGenerate_silentWalk_usesSilentPreamble() {
        for style in PromptStyle.allCases {
            let prompt = PromptGenerator.generate(
                style: style,
                recordings: [],
                meditations: [],
                duration: 1800,
                distance: 2000,
                startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
            )
            XCTAssertFalse(prompt.text.contains("Walking Transcription"), "Silent \(style) should not have Walking Transcription")
            XCTAssertFalse(prompt.text.isEmpty, "Silent \(style) should produce output")
        }
    }

    func testGenerate_withIntention_containsIntentionFraming() {
        let prompt = PromptGenerator.generate(
            style: .contemplative,
            recordings: [],
            meditations: [],
            duration: 1800,
            distance: 2000,
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            intention: "Find stillness"
        )
        XCTAssertTrue(prompt.text.contains("The walker's intention"))
        XCTAssertTrue(prompt.text.contains("Find stillness"))
        XCTAssertTrue(prompt.text.contains("Ground your response"))
    }

    func testGenerate_withWaypoints_containsWaypointSection() {
        let waypoints = [
            PromptGenerator.WaypointContext(label: "Peaceful", icon: "leaf", timestamp: DateFactory.makeDate(2024, 6, 15, 9, 10, 0), coordinate: (lat: 40.0, lon: -74.0))
        ]
        let prompt = PromptGenerator.generate(
            style: .reflective,
            recordings: [],
            meditations: [],
            duration: 1800,
            distance: 2000,
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            waypoints: waypoints
        )
        XCTAssertTrue(prompt.text.contains("Waypoints marked during walk"))
        XCTAssertTrue(prompt.text.contains("Peaceful"))
    }

    func testGenerateCustom_usesCustomInstruction() {
        let custom = CustomPromptStyle(id: UUID(), title: "Letter", icon: "envelope.fill", instruction: "Write this as a letter to my future self")
        let prompt = PromptGenerator.generateCustom(
            customStyle: custom,
            recordings: [],
            meditations: [],
            duration: 1800,
            distance: 2000,
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        )
        XCTAssertTrue(prompt.text.contains("letter to my future self"))
        XCTAssertNil(prompt.style)
        XCTAssertEqual(prompt.customStyle?.title, "Letter")
    }
}
