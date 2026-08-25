import XCTest
@testable import Pilgrim

/// Modal-lean clause coverage — split from `ThreadsDossierTests` to keep
/// both files under the file_length / type_body_length lint gates (same
/// house rule as `ThreadsDossierSensesTests.swift`). Reuses the parent
/// class's `markers`/`context` fixture builders.
extension ThreadsDossierTests {

    func testModalBaseline_needsThreeQualifyingWalks() {
        let walkA = UUID(), walkB = UUID(), walkC = UUID(), currentWalk = UUID()
        let ctxA = context(words: 200, absolutist: 2, modalCounts: ["should": 5])
        let ctxB = context(words: 200, absolutist: 2, modalCounts: ["should": 5])
        let twoWalkIndex: [UUID: UUID] = [ctxA.recordingUUID: walkA, ctxB.recordingUUID: walkB]
        XCTAssertNil(ThreadsDossierFormatter.modalBaseline(
            from: [ctxA, ctxB], walkIndex: twoWalkIndex, excluding: currentWalk
        ), "two prior contexted walks is below the three-walk floor")

        let ctxC = context(words: 200, absolutist: 2, modalCounts: ["should": 5])
        let threeWalkIndex = twoWalkIndex.merging([ctxC.recordingUUID: walkC]) { a, _ in a }
        XCTAssertNotNil(ThreadsDossierFormatter.modalBaseline(
            from: [ctxA, ctxB, ctxC], walkIndex: threeWalkIndex, excluding: currentWalk
        ), "three prior contexted walks meets the floor")
    }

    /// Exact-pin: the shipped clause format, mirroring the absolutist
    /// baseline's own conventions (density-floor-qualified history, "your
    /// usual" phrasing register) but per-walk rather than per-recording.
    func testModalLean_dominantFamilyOverBaseline_firesExactPin() {
        let currentWalk = UUID()
        let walkA = UUID(), walkB = UUID(), walkC = UUID()
        let priorA = context(words: 300, absolutist: 2, modalCounts: ["should": 8])
        let priorB = context(words: 300, absolutist: 2, modalCounts: ["should": 8])
        let priorC = context(words: 300, absolutist: 2, modalCounts: ["should": 8])
        let today = context(words: 400, absolutist: 2, modalCounts: ["should": 31])

        let walkIndex: [UUID: UUID] = [
            priorA.recordingUUID: walkA, priorB.recordingUUID: walkB,
            priorC.recordingUUID: walkC, today.recordingUUID: currentWalk
        ]
        let dossier = ThreadsDossierFormatter.dossier(
            currentRecordings: [(today, nil)],
            allContexts: [priorA, priorB, priorC, today],
            threads: [], currentWalkUUID: currentWalk, backfillComplete: false,
            walkIndex: walkIndex
        )
        XCTAssertTrue(
            dossier!.contains("modal lean: obligation — 'should' ×31 (your usual ~8 per walk)"),
            "actual: \(dossier ?? "nil")"
        )
    }

    func testModalLean_silentWithoutBaseline_firstWalksNeverSpeak() {
        let currentWalk = UUID()
        let today = context(words: 400, absolutist: 2, modalCounts: ["should": 31])
        let dossier = ThreadsDossierFormatter.dossier(
            currentRecordings: [(today, nil)], allContexts: [today],
            threads: [], currentWalkUUID: currentWalk, backfillComplete: false,
            walkIndex: [today.recordingUUID: currentWalk]
        )
        XCTAssertFalse(dossier!.contains("modal lean"), "no baseline exists yet — the clause stays silent")
    }

    func testModalLean_silentWhenBelowMinimumCount() {
        let currentWalk = UUID()
        let walkA = UUID(), walkB = UUID(), walkC = UUID()
        let priorA = context(words: 300, absolutist: 2, modalCounts: ["should": 1])
        let priorB = context(words: 300, absolutist: 2, modalCounts: ["should": 1])
        let priorC = context(words: 300, absolutist: 2, modalCounts: ["should": 1])
        let today = context(words: 400, absolutist: 2, modalCounts: ["should": 9])  // below the count floor
        let walkIndex: [UUID: UUID] = [
            priorA.recordingUUID: walkA, priorB.recordingUUID: walkB,
            priorC.recordingUUID: walkC, today.recordingUUID: currentWalk
        ]
        let dossier = ThreadsDossierFormatter.dossier(
            currentRecordings: [(today, nil)],
            allContexts: [priorA, priorB, priorC, today],
            threads: [], currentWalkUUID: currentWalk, backfillComplete: false,
            walkIndex: walkIndex
        )
        XCTAssertFalse(dossier!.contains("modal lean"), "a family count under 10 is never remarkable, whatever the ratio")
    }

    func testModalLean_silentWhenNotElevatedOverBaseline() {
        let currentWalk = UUID()
        let walkA = UUID(), walkB = UUID(), walkC = UUID()
        let priorA = context(words: 100, absolutist: 2, modalCounts: ["should": 10])
        let priorB = context(words: 100, absolutist: 2, modalCounts: ["should": 10])
        let priorC = context(words: 100, absolutist: 2, modalCounts: ["should": 10])
        // Today's rate (11/300 ≈ 3.7%) sits below the walker's own 10% baseline rate,
        // let alone 2x it — the count floor (11 ≥ 10) alone must not be enough to fire.
        let today = context(words: 300, absolutist: 2, modalCounts: ["should": 11])
        let walkIndex: [UUID: UUID] = [
            priorA.recordingUUID: walkA, priorB.recordingUUID: walkB,
            priorC.recordingUUID: walkC, today.recordingUUID: currentWalk
        ]
        let dossier = ThreadsDossierFormatter.dossier(
            currentRecordings: [(today, nil)],
            allContexts: [priorA, priorB, priorC, today],
            threads: [], currentWalkUUID: currentWalk, backfillComplete: false,
            walkIndex: walkIndex
        )
        XCTAssertFalse(dossier!.contains("modal lean"), "a walker's usual rate this high is not news")
    }

    func testModalLean_silentWithNoModalWordsSpoken() {
        let currentWalk = UUID()
        let today = context(words: 400, absolutist: 2)
        let dossier = ThreadsDossierFormatter.dossier(
            currentRecordings: [(today, nil)], allContexts: [today],
            threads: [], currentWalkUUID: currentWalk, backfillComplete: false,
            walkIndex: [today.recordingUUID: currentWalk]
        )
        XCTAssertFalse(dossier!.contains("modal lean"))
    }

    /// End-to-end wiring check: `ThreadsDossierBuilder.build`'s own
    /// `walkIndex: [UUID: (walkUUID: UUID, date: Date)]` must actually reach
    /// the formatter's per-walk baseline grouping, not just the pure
    /// formatter tests above.
    func testBuilder_modalLean_wiredThroughToRealBuild() {
        let saved = UserPreferences.threadsAfterWalks.value
        defer { UserPreferences.threadsAfterWalks.value = saved }
        UserPreferences.threadsAfterWalks.value = true

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DossierBuilderTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptContextStore(directory: directory)

        let walkA = UUID(), walkB = UUID(), walkC = UUID(), currentWalk = UUID()
        func priorContext() -> TranscriptContext {
            let ctx = TranscriptContext(
                schemaVersion: TranscriptContext.currentSchemaVersion, recordingUUID: UUID(),
                transcriptHash: "h-\(UUID())", languageCode: "en", wordCount: 300, themes: [],
                markers: markers(words: 300, absolutist: 2, modalCounts: ["should": 8])
            )
            store.save(ctx)
            return ctx
        }
        let priorA = priorContext(), priorB = priorContext(), priorC = priorContext()

        let recordingUUID = UUID()
        let text = String(repeating: "should ", count: 31) + String(repeating: "walking word ", count: 85)
        let recording = RecordingContext(
            text: text, timestamp: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            startCoordinate: nil, endCoordinate: nil, wordsPerMinute: nil, recordingUUID: recordingUUID
        )
        let walkIndex: [UUID: (walkUUID: UUID, date: Date)] = [
            priorA.recordingUUID: (walkA, DateFactory.makeDate(2024, 6, 1, 9, 0, 0)),
            priorB.recordingUUID: (walkB, DateFactory.makeDate(2024, 6, 3, 9, 0, 0)),
            priorC.recordingUUID: (walkC, DateFactory.makeDate(2024, 6, 5, 9, 0, 0)),
            recordingUUID: (currentWalk, DateFactory.makeDate(2024, 6, 15, 9, 0, 0))
        ]

        let dossier = ThreadsDossierBuilder.build(
            walkUUID: currentWalk, recordings: [recording], walkIndex: walkIndex, store: store
        )
        XCTAssertTrue(
            dossier!.contains("modal lean: obligation — 'should' ×31 (your usual ~8 per walk)"),
            "actual: \(dossier ?? "nil")"
        )
    }
}
