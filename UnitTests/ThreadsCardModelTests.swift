import XCTest
import CoreStore
@testable import Pilgrim

@MainActor
final class ThreadsCardModelTests: XCTestCase {

    private let base = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)

    private func appearance(recording: UUID, walk: UUID, date: Date, mentions: Int, salience: Double) -> ThreadAppearance {
        ThreadAppearance(recordingUUID: recording, walkUUID: walk, date: date,
                         mentionCount: mentions, salience: salience)
    }

    private func context(_ uuid: UUID, words: Int = 200, language: String? = "en") -> TranscriptContext {
        TranscriptContext(
            schemaVersion: 1, recordingUUID: uuid, transcriptHash: "h",
            languageCode: language, wordCount: words, themes: [], markers: nil
        )
    }

    private func singleThemeFixture(
        earlierDates: [Date] = [],
        backfillComplete: Bool = true
    ) -> ThreadsCardModel? {
        let rec = UUID(), walk = UUID()
        var appearances = earlierDates.map {
            appearance(recording: UUID(), walk: UUID(), date: $0, mentions: 2, salience: 0.01)
        }
        appearances.append(appearance(recording: rec, walk: walk, date: base, mentions: 3, salience: 0.015))
        let thread = WalkThread(lemma: "move", displayTerm: "the move", appearances: appearances)
        return ThreadsCardModelBuilder.model(
            walkUUID: walk,
            threads: [thread],
            recordings: [(uuid: rec, transcript: "words", wordsPerMinute: nil)],
            contextsByRecording: [rec: context(rec)],
            backfillComplete: backfillComplete
        )
    }

    func testModel_firstTimeStatusRequiresBackfill() {
        XCTAssertEqual(singleThemeFixture()?.themes.first?.statusNote, "first time")
        XCTAssertNil(singleThemeFixture(backfillComplete: false)?.themes.first?.statusNote,
                     "origin claims stay suppressed pre-backfill — the chip shows without a note")
    }

    func testModel_ordinalStatusThroughHistory() {
        let model = singleThemeFixture(earlierDates: [
            base.addingTimeInterval(-10 * 86400),
            base.addingTimeInterval(-5 * 86400)
        ])
        XCTAssertEqual(model?.themes.first?.statusNote, "third walk now")
    }

    func testStatusCopy_returningAndCap() {
        XCTAssertEqual(ThreadsCardCopy.statusNote(for: .recurring(walksInWindow: 1)), "returning")
        XCTAssertEqual(ThreadsCardCopy.statusNote(for: .recurring(walksInWindow: 2)), "second walk now")
        XCTAssertEqual(ThreadsCardCopy.statusNote(for: .recurring(walksInWindow: 12)), "twelfth walk now")
        XCTAssertEqual(ThreadsCardCopy.statusNote(for: .recurring(walksInWindow: 13)), "with you again")
        XCTAssertNil(ThreadsCardCopy.statusNote(for: nil))
    }

    func testModel_topFourBySalienceDeterministicTies() {
        let walk = UUID()
        let recordings = (0..<5).map { _ in UUID() }
        // "elm" is built BEFORE "dawn" and the two tie exactly on mentions
        // and salience — the top-4 cut is decided by the alphabetical
        // tie-break, not insertion order.
        let lemmas = ["alder", "birch", "cedar", "elm", "dawn"]
        let mentionCounts = [5, 4, 3, 2, 2]
        let threads = lemmas.enumerated().map { index, lemma in
            WalkThread(lemma: lemma, displayTerm: lemma, appearances: [
                appearance(recording: recordings[index], walk: walk, date: base,
                           mentions: mentionCounts[index], salience: Double(mentionCounts[index]) / 200)
            ])
        }
        let contexts = Dictionary(uniqueKeysWithValues: recordings.map { ($0, context($0)) })
        let model = ThreadsCardModelBuilder.model(
            walkUUID: walk, threads: threads,
            recordings: recordings.map { (uuid: $0, transcript: "words", wordsPerMinute: nil) },
            contextsByRecording: contexts, backfillComplete: true
        )
        XCTAssertEqual(model?.themes.map(\.displayTerm), ["alder", "birch", "cedar", "dawn"],
                       "top four by salience; 'dawn' and 'elm' tie exactly and the alphabetical tie-break keeps 'dawn'")
    }

    func testModel_cohortMergesSharedDisplayTerm() {
        let walk = UUID()
        let recA = UUID(), recB = UUID()
        let threads = [
            WalkThread(lemma: "move", displayTerm: "the move", appearances: [
                appearance(recording: recA, walk: walk, date: base, mentions: 3, salience: 0.015)
            ]),
            WalkThread(lemma: "moving", displayTerm: "the move", appearances: [
                appearance(recording: recB, walk: walk, date: base, mentions: 2, salience: 0.01)
            ])
        ]
        let contexts = [recA: context(recA), recB: context(recB)]
        let model = ThreadsCardModelBuilder.model(
            walkUUID: walk, threads: threads,
            recordings: [(uuid: recA, transcript: "w", wordsPerMinute: nil),
                         (uuid: recB, transcript: "w", wordsPerMinute: nil)],
            contextsByRecording: contexts, backfillComplete: true
        )
        XCTAssertEqual(model?.themes.count, 1, "two lemmas, one chip")
        XCTAssertEqual(model?.themes.first?.lemmas, ["move", "moving"])
    }

    func testCohortStatus_firstTimeOnlyIfNoLemmaAppearedEarlier() {
        let walk = UUID()
        let recNow = UUID()
        let threads = [
            WalkThread(lemma: "move", displayTerm: "the move", appearances: [
                appearance(recording: recNow, walk: walk, date: base, mentions: 3, salience: 0.015)
            ]),
            WalkThread(lemma: "moving", displayTerm: "the move", appearances: [
                appearance(recording: UUID(), walk: UUID(),
                           date: base.addingTimeInterval(-10 * 86400), mentions: 2, salience: 0.01)
            ])
        ]
        let model = ThreadsCardModelBuilder.model(
            walkUUID: walk, threads: threads,
            recordings: [(uuid: recNow, transcript: "w", wordsPerMinute: nil)],
            contextsByRecording: [recNow: context(recNow)], backfillComplete: true
        )
        XCTAssertEqual(model?.themes.first?.statusNote, "second walk now",
                       "a first-time claim is only true if NO lemma in the cohort appeared earlier")
    }

    func testCohortLemmas_includeSiblingsAbsentFromThisWalk() {
        let walk = UUID()
        let recNow = UUID()
        let threads = [
            WalkThread(lemma: "move", displayTerm: "the move", appearances: [
                appearance(recording: recNow, walk: walk, date: base, mentions: 3, salience: 0.015)
            ]),
            WalkThread(lemma: "moving", displayTerm: "the move", appearances: [
                appearance(recording: UUID(), walk: UUID(),
                           date: base.addingTimeInterval(-10 * 86400), mentions: 2, salience: 0.01)
            ])
        ]
        let model = ThreadsCardModelBuilder.model(
            walkUUID: walk, threads: threads,
            recordings: [(uuid: recNow, transcript: "w", wordsPerMinute: nil)],
            contextsByRecording: [recNow: context(recNow)], backfillComplete: true
        )
        XCTAssertEqual(model?.themes.first?.lemmas, ["move", "moving"],
                       "release acts on every lemma sharing the display term — including a sibling with no appearance in this walk")
    }

    func testModel_noActiveThreads_returnsNil() {
        let rec = UUID()
        XCTAssertNil(ThreadsCardModelBuilder.model(
            walkUUID: UUID(), threads: [],
            recordings: [(uuid: rec, transcript: "w", wordsPerMinute: nil)],
            contextsByRecording: [rec: context(rec)], backfillComplete: true
        ), "no theme, no card — the summary stays pixel-identical")
    }

    func testTexture_slowPaceAndInsight() {
        XCTAssertEqual(
            ThreadsTexture.line(meanWordsPerMinute: 80, hasInsight: true),
            "Spoken slowly, with words of insight."
        )
        XCTAssertEqual(
            ThreadsTexture.line(meanWordsPerMinute: 180, hasInsight: false),
            "Spoken quickly."
        )
        XCTAssertEqual(
            ThreadsTexture.line(meanWordsPerMinute: nil, hasInsight: true),
            "With words of insight."
        )
    }

    func testTexture_weakSignalsOmitEverything() {
        XCTAssertNil(ThreadsTexture.line(meanWordsPerMinute: 120, hasInsight: false),
                     "a conversational pace and no insight words is not a texture — the line is omitted")
    }

    func testInsightWords_exactTraceableSurfacesDeduped() {
        let words = ThreadsTexture.insightWords(in: [
            "I realize now what I noticed before.",
            "I realize it again with new awareness."
        ])
        XCTAssertEqual(words, ["realize", "noticed", "awareness"],
                       "spoken order, deduplicated — the exact words the clause traces to")
    }

    func testModel_belowFloorInsight_noClaimNoTap() {
        let rec = UUID(), walk = UUID()
        let thread = WalkThread(lemma: "move", displayTerm: "the move", appearances: [
            appearance(recording: rec, walk: walk, date: base, mentions: 3, salience: 0.015)
        ])
        let model = ThreadsCardModelBuilder.model(
            walkUUID: walk, threads: [thread],
            recordings: [(uuid: rec, transcript: "I realize the move", wordsPerMinute: 80)],
            contextsByRecording: [rec: context(rec)], backfillComplete: true
        )
        XCTAssertEqual(model?.textureLine, "Spoken slowly.",
                       "a single insight word sits below the floor — the claim never appears in the line")
        XCTAssertEqual(model?.hasInsight, false,
                       "the model exposes the same floor decision the view must gate on")
    }

    func testModel_nonEnglishRecordings_noInsightClause() {
        let rec = UUID(), walk = UUID()
        let thread = WalkThread(lemma: "mudanza", displayTerm: "mudanza", appearances: [
            appearance(recording: rec, walk: walk, date: base, mentions: 3, salience: 0.015)
        ])
        let model = ThreadsCardModelBuilder.model(
            walkUUID: walk, threads: [thread],
            recordings: [(uuid: rec, transcript: "I realize I notice awareness", wordsPerMinute: nil)],
            contextsByRecording: [rec: context(rec, language: "es")], backfillComplete: true
        )
        XCTAssertTrue(model?.insightWords.isEmpty == true,
                      "the insight lexicon is English-validated — other languages degrade to themes-only")
    }

    func testCopy_neverEmitsDigits() {
        for walks in 1...40 {
            let note = ThreadsCardCopy.statusNote(for: .recurring(walksInWindow: walks)) ?? ""
            XCTAssertNil(note.rangeOfCharacter(from: .decimalDigits),
                         "principle 1: ordinal words, never metric digits (failed at \(walks))")
        }
    }

    private func seedWalkWithVoiceRecording(
        in stack: DataStack, walkUUID: UUID, recordingUUID: UUID
    ) throws -> Walk {
        try stack.perform(synchronous: { transaction in
            let walk = transaction.create(Into<Walk>())
            walk._uuid .= walkUUID
            walk._workoutType .= .walking
            walk._startDate .= Date(timeIntervalSince1970: 1_700_000_000)
            walk._endDate .= Date(timeIntervalSince1970: 1_700_001_800)
            walk._distance .= 1000
            walk._activeDuration .= 1800
            walk._pauseDuration .= 0
            walk._talkDuration .= 0
            walk._meditateDuration .= 0
            walk._ascend .= 0
            walk._descend .= 0
            walk._isRace .= false
            walk._isUserModified .= false
            walk._finishedRecording .= true
            walk._dayIdentifier .= "20231115"

            let recording = transaction.create(Into<VoiceRecording>())
            recording._uuid .= recordingUUID
            recording._fileRelativePath .= "Recordings/X/a.m4a"
            recording._workout .= walk
        })
        return try XCTUnwrap(stack.fetchOne(From<Walk>().where(\._uuid == walkUUID)))
    }

    /// I1 residual: `onTranscriptionSave`/`onRetranscribe` mutate the summary's
    /// `transcriptions` dict synchronously, but `DataManager
    /// .updateVoiceRecordingTranscription` only re-analyzes inside its async
    /// CoreStore write completion — a reload triggered by the mutation can
    /// win the race and read the pre-edit context. The loader must hash-check
    /// and re-analyze inline, the ThreadsDossierBuilder discipline, so the
    /// card never survives on a stale analysis.
    func testLoader_staleStoredContext_reAnalyzesInlineAndDropsEditedAwayTheme() async throws {
        let savedToggle = UserPreferences.threadsAfterWalks.value
        defer { UserPreferences.threadsAfterWalks.value = savedToggle }
        UserPreferences.threadsAfterWalks.value = true

        let previousDataStack = DataManager.dataStack
        let stack = DataStack(PilgrimV7.schema)
        try stack.addStorageAndWait(InMemoryStore())
        DataManager.dataStack = stack
        defer { DataManager.dataStack = previousDataStack }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThreadsCardLoaderTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptContextStore(directory: directory)

        let releasedSuite = "ThreadsCardLoaderTests-\(UUID().uuidString)"
        let releasedDefaults = try XCTUnwrap(UserDefaults(suiteName: releasedSuite))
        defer { releasedDefaults.removePersistentDomain(forName: releasedSuite) }
        let releasedStore = ReleasedThreadsStore(defaults: releasedDefaults)

        let walkUUID = UUID(), recordingUUID = UUID()
        let walk = try seedWalkWithVoiceRecording(in: stack, walkUUID: walkUUID, recordingUUID: recordingUUID)

        // Analyzed and stored BEFORE the edit landed — "move" is baked into
        // the stale context still sitting on disk.
        let staleTranscript = String(repeating: "the move keeps returning to me today ", count: 6)
        store.save(TranscriptContextAnalyzer.analyze(recordingUUID: recordingUUID, transcript: staleTranscript))

        // The edit removed every mention of "move", and is too short to
        // surface any theme of its own — the recomputed context should carry
        // no themes at all.
        let editedTranscript = "Just a quiet morning with nothing much on my mind."

        let model = await ThreadsCardLoader.load(
            walk: walk,
            transcriptions: [recordingUUID: editedTranscript],
            store: store,
            releasedStore: releasedStore
        )

        XCTAssertNil(model, "the edit removed the only theme — a stale reload must not still name 'the move'")

        // The loader's inline re-analysis must stay in-memory: the transcription
        // choke point is the sole persistent writer, because it alone carries the
        // ASR flaggedFragments needed to filter hallucinated themes. The store on
        // disk should still hold the pre-edit (stale) context, not the loader's.
        let persisted = store.context(for: recordingUUID, matching: TranscriptContextStore.hash(of: staleTranscript))
        XCTAssertNotNil(persisted, "a loader-triggered re-analysis must never persist — the stored context stays the stale one until the choke point writes fresh")
    }
}
