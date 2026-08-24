import XCTest
@testable import Pilgrim

final class ThreadsReleaseFilteringTests: XCTestCase {

    private let base = DateFactory.makeDate(2024, 6, 1, 9, 0, 0)

    private func context(_ uuid: UUID, lemma: String, mentions: Int) -> TranscriptContext {
        TranscriptContext(
            schemaVersion: 1, recordingUUID: uuid, transcriptHash: "h",
            languageCode: "en", wordCount: 200,
            themes: [Theme(
                lemma: lemma, displayTerm: lemma, mentionCount: mentions,
                salience: Double(mentions) / 200,
                mentions: Array(repeating: ThemeMention(start: 0, length: 4), count: mentions)
            )],
            markers: nil
        )
    }

    func testBuild_dropsReleasedLemmas() {
        let rec = UUID(), walk = UUID()
        let contexts = [context(rec, lemma: "move", mentions: 3)]
        let walks = [rec: (walkUUID: walk, date: base)]
        XCTAssertEqual(ThreadStore.build(contexts: contexts, walks: walks).count, 1)
        XCTAssertTrue(ThreadStore.build(contexts: contexts, walks: walks, released: ["move"]).isEmpty)
    }

    func testBuild_cohortLemmasBothDrop() {
        let recA = UUID(), recB = UUID(), walk = UUID()
        let contexts = [
            context(recA, lemma: "move", mentions: 3),
            context(recB, lemma: "moving", mentions: 2)
        ]
        let walks = [recA: (walkUUID: walk, date: base), recB: (walkUUID: walk, date: base)]
        let threads = ThreadStore.build(contexts: contexts, walks: walks, released: ["move", "moving"])
        XCTAssertTrue(threads.isEmpty, "release acts on the display term's full lemma cohort")
    }

    private var recurringText: String {
        "The move is here. The move is near. The move is real. The move returns. " +
        "The garden waits. The garden grows. The garden helps."
    }

    func testRecurringWord_skipsReleasedAndPromotesNext() {
        let context = ActivityContext.make(
            recordings: [RecordingContext(
                text: recurringText, timestamp: base,
                startCoordinate: nil, endCoordinate: nil, wordsPerMinute: nil
            )],
            startDate: base
        )
        let unfiltered = AttentionDirectives.detect(context: context, releasedLemmas: []).joined()
        XCTAssertTrue(unfiltered.contains("'move'"))
        let filtered = AttentionDirectives.detect(context: context, releasedLemmas: ["move"]).joined()
        XCTAssertFalse(filtered.contains("'move'"))
        XCTAssertTrue(filtered.contains("'garden'"), "the next-ranked candidate is promoted")
    }

    func testIntentionEcho_exemptFromRelease() {
        let context = ActivityContext.make(
            recordings: [RecordingContext(
                text: recurringText, timestamp: base,
                startCoordinate: nil, endCoordinate: nil, wordsPerMinute: nil
            )],
            startDate: base,
            intention: "sit with the move"
        )
        let joined = AttentionDirectives.detect(context: context, releasedLemmas: ["move"]).joined()
        XCTAssertTrue(joined.contains("intention spoke of"),
                      "the echo quotes the walker's own stated intention — walker-authored, not app-noticed")
    }

    func testDossierBuilder_releaseVisibleOnNextOpen() {
        let saved = UserPreferences.threadsAfterWalks.value
        defer { UserPreferences.threadsAfterWalks.value = saved }
        UserPreferences.threadsAfterWalks.value = true

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReleaseFilteringTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptContextStore(directory: directory)

        let suiteName = "ReleaseFilteringTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let releasedStore = ReleasedThreadsStore(defaults: defaults)

        let transcript = "The move is on my mind today. The move would change everything for us. " +
            "The move keeps returning whenever the morning turns quiet enough to hear it speak plainly."
        let recUUID = UUID(), walkUUID = UUID()
        let recording = RecordingContext(
            text: transcript, timestamp: base,
            startCoordinate: nil, endCoordinate: nil, wordsPerMinute: nil,
            recordingUUID: recUUID
        )
        let walkIndex = [recUUID: (walkUUID: walkUUID, date: base)]

        let before = ThreadsDossierBuilder.build(
            walkUUID: walkUUID, recordings: [recording], walkIndex: walkIndex,
            store: store, releasedStore: releasedStore
        )
        XCTAssertTrue(before?.contains("'move'") == true)

        releasedStore.release(displayTerm: "move", lemmas: ["move"])
        let after = ThreadsDossierBuilder.build(
            walkUUID: walkUUID, recordings: [recording], walkIndex: walkIndex,
            store: store, releasedStore: releasedStore
        )
        XCTAssertNotNil(after, "marker profiles still render — release removes noticing, not analysis")
        XCTAssertFalse(after!.contains("'move'"),
                       "the released token invalidates the memo — visible on the very next open")
    }

    func testSuggestions_selectOverFilteredThreadsExcludesReleased() {
        let recA = UUID(), recB = UUID()
        let contexts = [
            context(recA, lemma: "move", mentions: 3),
            context(recB, lemma: "move", mentions: 3)
        ]
        let walks = [
            recA: (walkUUID: UUID(), date: base),
            recB: (walkUUID: UUID(), date: base.addingTimeInterval(5 * 86400))
        ]
        let filtered = ThreadStore.build(contexts: contexts, walks: walks, released: ["move"])
        XCTAssertTrue(ThreadIntentionSuggestions.select(
            threads: filtered, asOf: base.addingTimeInterval(6 * 86400)
        ).isEmpty, "select over release-filtered threads yields nothing — ranking only; the async current() wiring is pinned by Task 8's testCurrent_releaseVisibleOnNextCall")
    }
}
