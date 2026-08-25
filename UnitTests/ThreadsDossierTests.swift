import XCTest
@testable import Pilgrim

final class ThreadsDossierTests: XCTestCase {

    /// Not `private`: `ThreadsDossierModalLeanTests.swift` (an `extension
    /// ThreadsDossierTests` split into its own file to stay under the
    /// file_length / type_body_length lint gates — same house rule as
    /// `ThreadsDossierSensesTests.swift`) reuses these fixture builders.
    func markers(words: Int, absolutist: Int, modalCounts: [String: Int] = [:]) -> MarkerPack {
        MarkerPack(
            wordCount: words, absolutistCount: absolutist, firstPersonCount: 5,
            insightCount: 2, causationCount: 1, discrepancyCount: 1,
            futureCount: 4, pastCount: 1, sentiment: -0.2, modalCounts: modalCounts
        )
    }

    func context(words: Int, absolutist: Int, modalCounts: [String: Int] = [:]) -> TranscriptContext {
        TranscriptContext(
            schemaVersion: 1, recordingUUID: UUID(), transcriptHash: "h",
            languageCode: "en", wordCount: words, themes: [],
            markers: markers(words: words, absolutist: absolutist, modalCounts: modalCounts)
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

    // Modal-lean coverage lives in ThreadsDossierModalLeanTests.swift (an
    // `extension ThreadsDossierTests` split into its own file to stay under
    // the file_length / type_body_length lint gates).

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
            currentRecordings: [(current, nil)], allContexts: [current],
            threads: [thread], currentWalkUUID: walkB, backfillComplete: false
        )
        XCTAssertFalse(gated!.contains("first spoken"), "origin claims suppressed pre-backfill")
        let open = ThreadsDossierFormatter.dossier(
            currentRecordings: [(current, nil)], allContexts: [current],
            threads: [thread], currentWalkUUID: walkB, backfillComplete: true
        )
        XCTAssertTrue(open!.contains("first spoken"))
    }

    func testAbsenceLines_gatedOnBackfillAndTwoDistinctWalks() {
        let current = context(words: 200, absolutist: 2)
        let walkA = UUID(), walkB = UUID(), walkC = UUID()
        let quietDate1 = DateFactory.makeDate(2024, 6, 1, 9, 0, 0)
        let quietDate2 = DateFactory.makeDate(2024, 6, 5, 9, 0, 0)
        let currentDate = DateFactory.makeDate(2024, 6, 10, 9, 0, 0)
        let quietThread = WalkThread(
            lemma: "father", displayTerm: "father",
            appearances: [
                ThreadAppearance(recordingUUID: UUID(), walkUUID: walkA, date: quietDate1,
                                 mentionCount: 2, salience: 0.02),
                ThreadAppearance(recordingUUID: UUID(), walkUUID: walkB, date: quietDate2,
                                 mentionCount: 2, salience: 0.02)
            ]
        )
        let activeThread = WalkThread(
            lemma: "move", displayTerm: "move",
            appearances: [
                ThreadAppearance(recordingUUID: current.recordingUUID, walkUUID: walkC, date: currentDate,
                                 mentionCount: 3, salience: 0.03)
            ]
        )

        let gated = ThreadsDossierFormatter.dossier(
            currentRecordings: [(current, nil)], allContexts: [current],
            threads: [quietThread, activeThread], currentWalkUUID: walkC, backfillComplete: false
        )
        XCTAssertFalse(gated!.contains("Notably quiet"), "absence claims suppressed pre-backfill")

        let open = ThreadsDossierFormatter.dossier(
            currentRecordings: [(current, nil)], allContexts: [current],
            threads: [quietThread, activeThread], currentWalkUUID: walkC, backfillComplete: true
        )
        XCTAssertTrue(open!.contains("**Quiet this walk:**"))
        XCTAssertTrue(open!.contains("Notably quiet this walk: 'father' — present in 2 of the walker's recent walks."))
    }

    func testAbsenceLines_suppressedWhenCurrentWalkHasNoAppearances() {
        let current = context(words: 200, absolutist: 2)
        let walkA = UUID(), walkB = UUID(), currentWalk = UUID()
        let quietDate1 = DateFactory.makeDate(2024, 6, 1, 9, 0, 0)
        let quietDate2 = DateFactory.makeDate(2024, 6, 5, 9, 0, 0)
        let quietThread = WalkThread(
            lemma: "father", displayTerm: "father",
            appearances: [
                ThreadAppearance(recordingUUID: UUID(), walkUUID: walkA, date: quietDate1,
                                 mentionCount: 2, salience: 0.02),
                ThreadAppearance(recordingUUID: UUID(), walkUUID: walkB, date: quietDate2,
                                 mentionCount: 2, salience: 0.02)
            ]
        )

        let dossier = ThreadsDossierFormatter.dossier(
            currentRecordings: [(current, nil)], allContexts: [current],
            threads: [quietThread], currentWalkUUID: currentWalk, backfillComplete: true
        )
        XCTAssertNotNil(dossier)
        XCTAssertFalse(
            dossier!.contains("**Quiet this walk:**"),
            "no derivable anchor on the current walk means no absence claim, not a fallback to unrelated walks"
        )
        XCTAssertTrue(dossier!.contains("Thought threads"), "marker profiles still render")
    }

    func testPaceCorrelation_slowerThemeGroupNotedOnActiveThread() {
        let walkUUID = UUID()
        let date = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let slowContext = TranscriptContext(
            schemaVersion: 1, recordingUUID: UUID(), transcriptHash: "h1",
            languageCode: "en", wordCount: 200,
            themes: [Theme(lemma: "move", displayTerm: "move", mentionCount: 3, salience: 0.03, mentions: [])],
            markers: markers(words: 200, absolutist: 2)
        )
        let fastContext = TranscriptContext(
            schemaVersion: 1, recordingUUID: UUID(), transcriptHash: "h2",
            languageCode: "en", wordCount: 200, themes: [],
            markers: markers(words: 200, absolutist: 2)
        )
        let thread = WalkThread(
            lemma: "move", displayTerm: "move",
            appearances: [
                ThreadAppearance(recordingUUID: slowContext.recordingUUID, walkUUID: walkUUID, date: date,
                                 mentionCount: 3, salience: 0.03)
            ]
        )

        let dossier = ThreadsDossierFormatter.dossier(
            currentRecordings: [(slowContext, 80), (fastContext, 140)],
            allContexts: [slowContext, fastContext],
            threads: [thread], currentWalkUUID: walkUUID, backfillComplete: false
        )
        XCTAssertTrue(dossier!.contains("spoken more slowly than the rest of this walk"))
    }

    private func themedRecordings(themeWPM: Double, restWPMs: [Double]) -> (
        recordings: [(context: TranscriptContext, wordsPerMinute: Double?)],
        thread: WalkThread,
        walkUUID: UUID
    ) {
        let walkUUID = UUID()
        let date = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let themed = TranscriptContext(
            schemaVersion: 1, recordingUUID: UUID(), transcriptHash: "h1",
            languageCode: "en", wordCount: 200,
            themes: [Theme(lemma: "move", displayTerm: "move", mentionCount: 3, salience: 0.03, mentions: [])],
            markers: markers(words: 200, absolutist: 2)
        )
        var recordings: [(context: TranscriptContext, wordsPerMinute: Double?)] = [(themed, themeWPM)]
        for (index, restWPM) in restWPMs.enumerated() {
            let rest = TranscriptContext(
                schemaVersion: 1, recordingUUID: UUID(), transcriptHash: "rest\(index)",
                languageCode: "en", wordCount: 200, themes: [],
                markers: markers(words: 200, absolutist: 2)
            )
            recordings.append((rest, restWPM))
        }
        let thread = WalkThread(
            lemma: "move", displayTerm: "move",
            appearances: [
                ThreadAppearance(recordingUUID: themed.recordingUUID, walkUUID: walkUUID, date: date,
                                 mentionCount: 3, salience: 0.03)
            ]
        )
        return (recordings, thread, walkUUID)
    }

    func testPaceCorrelation_fasterThemeGroupNotedAsMoreQuickly() {
        let (recordings, thread, walkUUID) = themedRecordings(themeWPM: 140, restWPMs: [80])
        let dossier = ThreadsDossierFormatter.dossier(
            currentRecordings: recordings, allContexts: recordings.map(\.context),
            threads: [thread], currentWalkUUID: walkUUID, backfillComplete: false
        )
        XCTAssertTrue(dossier!.contains("spoken more quickly than the rest of this walk"))
    }

    func testPaceCorrelation_withinFifteenPercent_staysSilent() {
        let (recordings, thread, walkUUID) = themedRecordings(themeWPM: 100, restWPMs: [95])
        let dossier = ThreadsDossierFormatter.dossier(
            currentRecordings: recordings, allContexts: recordings.map(\.context),
            threads: [thread], currentWalkUUID: walkUUID, backfillComplete: false
        )
        XCTAssertFalse(dossier!.contains("spoken more"),
                       "a gap inside ±15% is noise, not a correlation")
    }

    func testPaceCorrelation_emptyRestGroup_staysSilent() {
        let (recordings, thread, walkUUID) = themedRecordings(themeWPM: 100, restWPMs: [])
        let dossier = ThreadsDossierFormatter.dossier(
            currentRecordings: recordings, allContexts: recordings.map(\.context),
            threads: [thread], currentWalkUUID: walkUUID, backfillComplete: false
        )
        XCTAssertNotNil(dossier)
        XCTAssertFalse(dossier!.contains("spoken more"),
                       "with no rest group there is nothing to compare against")
    }

    private func absenceDossier(quietOffsetFromAnchor: TimeInterval) -> String? {
        let current = context(words: 200, absolutist: 2)
        let anchor = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let currentWalk = UUID()
        let quietThread = WalkThread(
            lemma: "father", displayTerm: "father",
            appearances: [
                ThreadAppearance(recordingUUID: UUID(), walkUUID: UUID(),
                                 date: anchor.addingTimeInterval(quietOffsetFromAnchor),
                                 mentionCount: 2, salience: 0.02),
                ThreadAppearance(recordingUUID: UUID(), walkUUID: UUID(),
                                 date: anchor.addingTimeInterval(-5 * 86400),
                                 mentionCount: 2, salience: 0.02)
            ]
        )
        let activeThread = WalkThread(
            lemma: "move", displayTerm: "move",
            appearances: [
                ThreadAppearance(recordingUUID: current.recordingUUID, walkUUID: currentWalk, date: anchor,
                                 mentionCount: 3, salience: 0.03)
            ]
        )
        return ThreadsDossierFormatter.dossier(
            currentRecordings: [(current, nil)], allContexts: [current],
            threads: [quietThread, activeThread], currentWalkUUID: currentWalk, backfillComplete: true
        )
    }

    func testAbsenceWindowBoundary_exactlyThirtyDaysIsInclusive() {
        let dossier = absenceDossier(quietOffsetFromAnchor: -ThreadsDossierFormatter.absenceWindow)
        XCTAssertTrue(dossier!.contains("Notably quiet"),
                      "an appearance exactly at anchor − 30d is inside the absence window")
    }

    func testAbsenceWindowBoundary_oneSecondBeyondIsExcluded() {
        let dossier = absenceDossier(quietOffsetFromAnchor: -ThreadsDossierFormatter.absenceWindow - 1)
        XCTAssertFalse(dossier!.contains("Notably quiet"),
                       "one second beyond the window leaves a single distinct walk — below the floor")
    }

    func testBuilder_emptyWalkIndexWithStoredContexts_doesNotMassPrune() {
        let saved = UserPreferences.threadsAfterWalks.value
        defer { UserPreferences.threadsAfterWalks.value = saved }
        UserPreferences.threadsAfterWalks.value = true

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DossierBuilderTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptContextStore(directory: directory)
        let preExisting = context(words: 200, absolutist: 2)
        store.save(preExisting)

        let recording = RecordingContext(
            text: String(repeating: "the move keeps returning to me today ", count: 6),
            timestamp: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            startCoordinate: nil, endCoordinate: nil, wordsPerMinute: nil,
            recordingUUID: UUID()
        )
        _ = ThreadsDossierBuilder.build(
            walkUUID: UUID(), recordings: [recording], walkIndex: [:], store: store
        )
        XCTAssertTrue(store.hasContext(for: preExisting.recordingUUID),
                      "a failed/empty CoreStore read must not delete every context")
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
