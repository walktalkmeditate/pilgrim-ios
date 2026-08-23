import XCTest
@testable import Pilgrim

final class ThreadsDossierTests: XCTestCase {

    private func markers(words: Int, absolutist: Int) -> MarkerPack {
        MarkerPack(
            wordCount: words, absolutistCount: absolutist, firstPersonCount: 5,
            insightCount: 2, causationCount: 1, discrepancyCount: 1,
            futureCount: 4, pastCount: 1, sentiment: -0.2
        )
    }

    private func context(words: Int, absolutist: Int) -> TranscriptContext {
        TranscriptContext(
            schemaVersion: 1, recordingUUID: UUID(), transcriptHash: "h",
            languageCode: "en", wordCount: words, themes: [],
            markers: markers(words: words, absolutist: absolutist)
        )
    }

    func testDensitiesOnlyAtFloor_smallSampleGetsRawCounts() {
        let small = context(words: 40, absolutist: 2)
        let line = ThreadsDossierFormatter.markerLine(for: small, baseline: nil)
        XCTAssertTrue(line.contains("40 words"))
        XCTAssertTrue(line.contains("small sample"))
        XCTAssertFalse(line.contains("%"))

        let large = context(words: 400, absolutist: 8)
        let largeLine = ThreadsDossierFormatter.markerLine(for: large, baseline: nil)
        XCTAssertTrue(largeLine.contains("%"))
        XCTAssertTrue(largeLine.contains("400 words"))
    }

    func testPersonalBaseline_needsFiveQualifyingRecordings() {
        let four = (0..<4).map { _ in context(words: 200, absolutist: 2) }
        XCTAssertNil(ThreadsDossierFormatter.personalBaseline(from: four))
        let five = four + [context(words: 200, absolutist: 2)]
        XCTAssertNotNil(ThreadsDossierFormatter.personalBaseline(from: five))
    }

    func testBaselineComparison_usesWalkersOwnHistory() {
        let history = (0..<5).map { _ in context(words: 200, absolutist: 2) }  // 1% baseline
        let baseline = ThreadsDossierFormatter.personalBaseline(from: history)!
        let today = context(words: 200, absolutist: 6)  // 3%
        let line = ThreadsDossierFormatter.markerLine(for: today, baseline: baseline)
        XCTAssertTrue(line.contains("your usual"))
    }

    func testBuilder_toggleOffReturnsNil() {
        let saved = UserPreferences.threadsAfterWalks.value
        defer { UserPreferences.threadsAfterWalks.value = saved }
        UserPreferences.threadsAfterWalks.value = false

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DossierBuilderTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = RecordingContext(
            text: String(repeating: "the move keeps returning to me today ", count: 6),
            timestamp: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            startCoordinate: nil, endCoordinate: nil, wordsPerMinute: nil,
            recordingUUID: UUID()
        )
        XCTAssertNil(ThreadsDossierBuilder.build(
            walkUUID: UUID(), recordings: [recording], walkIndex: [:],
            store: TranscriptContextStore(directory: directory)
        ), "off means off everywhere — no dossier, no analysis surfaced")
    }

    func testBuilder_toggleOnBuildsAndPersistsFallback() {
        let saved = UserPreferences.threadsAfterWalks.value
        defer { UserPreferences.threadsAfterWalks.value = saved }
        UserPreferences.threadsAfterWalks.value = true

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DossierBuilderTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptContextStore(directory: directory)
        let uuid = UUID()
        let recording = RecordingContext(
            text: String(repeating: "the move keeps returning to me today ", count: 6),
            timestamp: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            startCoordinate: nil, endCoordinate: nil, wordsPerMinute: nil,
            recordingUUID: uuid
        )
        let dossier = ThreadsDossierBuilder.build(
            walkUUID: UUID(), recordings: [recording], walkIndex: [:], store: store
        )
        XCTAssertNotNil(dossier, "an empty store still yields marker profiles — the spec's degradation")
        XCTAssertTrue(dossier!.contains("Thought threads"))
        XCTAssertTrue(store.hasContext(for: uuid), "fallback analysis persists under the real UUID and self-heals")
    }

    func testDossierFormatter_originGatedOnBackfill() {
        let current = context(words: 200, absolutist: 2)
        let walkA = UUID(), walkB = UUID()
        let thread = WalkThread(
            lemma: "move", displayTerm: "move",
            appearances: [
                ThreadAppearance(recordingUUID: UUID(), walkUUID: walkA,
                                 date: DateFactory.makeDate(2024, 6, 1, 9, 0, 0),
                                 mentionCount: 3, salience: 0.02),
                ThreadAppearance(recordingUUID: current.recordingUUID, walkUUID: walkB,
                                 date: DateFactory.makeDate(2024, 6, 10, 9, 0, 0),
                                 mentionCount: 3, salience: 0.02)
            ]
        )
        let gated = ThreadsDossierFormatter.dossier(
            currentRecordingContexts: [current], allContexts: [current],
            threads: [thread], currentWalkUUID: walkB, backfillComplete: false
        )
        XCTAssertFalse(gated!.contains("first spoken"), "origin claims suppressed pre-backfill")
        let open = ThreadsDossierFormatter.dossier(
            currentRecordingContexts: [current], allContexts: [current],
            threads: [thread], currentWalkUUID: walkB, backfillComplete: true
        )
        XCTAssertTrue(open!.contains("first spoken"))
    }

    func testAssembler_omitsDossierWhenNil() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let prompt = PromptAssembler.assemble(
            context: ActivityContext.make(startDate: start),
            voice: PromptStyle.allCases[0].voice
        )
        XCTAssertFalse(prompt.contains("Thought threads"))
    }

    func testAssembler_includesDossierAndHandlingNote() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let context = ActivityContext.make(startDate: start, threadsDossier: "**Thought threads (on-device analysis):**\ntest")
        let prompt = PromptAssembler.assemble(context: context, voice: PromptStyle.allCases[0].voice)
        XCTAssertTrue(prompt.contains("Thought threads"))
        XCTAssertTrue(prompt.contains("not assessments"))
    }
}
