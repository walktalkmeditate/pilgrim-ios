import XCTest
@testable import Pilgrim

final class ThreadIntentionSuggestionsTests: XCTestCase {

    private let asOf = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)

    private func thread(_ displayTerm: String, walkDates: [(UUID, Date)]) -> WalkThread {
        WalkThread(
            lemma: displayTerm,
            displayTerm: displayTerm,
            appearances: walkDates.map { walkUUID, date in
                ThreadAppearance(recordingUUID: UUID(), walkUUID: walkUUID, date: date, mentionCount: 2, salience: 0.02)
            }
        )
    }

    func testSelect_qualifiesAtTwoDistinctWalksInWindow() {
        let move = thread("the move", walkDates: [
            (UUID(), asOf.addingTimeInterval(-5 * 86400)),
            (UUID(), asOf.addingTimeInterval(-10 * 86400))
        ])
        XCTAssertEqual(ThreadIntentionSuggestions.select(threads: [move], asOf: asOf), ["walk with 'the move'"])
    }

    func testSelect_excludedAtOneDistinctWalk() {
        let walkUUID = UUID()
        let solo = thread("father", walkDates: [
            (walkUUID, asOf.addingTimeInterval(-2 * 86400)),
            (walkUUID, asOf.addingTimeInterval(-1 * 86400))
        ])
        XCTAssertTrue(ThreadIntentionSuggestions.select(threads: [solo], asOf: asOf).isEmpty,
                      "two appearances in the same walk are not two distinct walks")
    }

    func testSelect_excludedWhenAppearancesOutsideWindow() {
        let stale = thread("garden", walkDates: [
            (UUID(), asOf.addingTimeInterval(-40 * 86400)),
            (UUID(), asOf.addingTimeInterval(-35 * 86400))
        ])
        XCTAssertTrue(ThreadIntentionSuggestions.select(threads: [stale], asOf: asOf).isEmpty)
    }

    func testSelect_capHonoredWithDeterministicOrder() {
        let three = thread("river", walkDates: [
            (UUID(), asOf.addingTimeInterval(-1 * 86400)),
            (UUID(), asOf.addingTimeInterval(-2 * 86400)),
            (UUID(), asOf.addingTimeInterval(-3 * 86400))
        ])
        let alsoThree = thread("worry", walkDates: [
            (UUID(), asOf.addingTimeInterval(-1 * 86400)),
            (UUID(), asOf.addingTimeInterval(-2 * 86400)),
            (UUID(), asOf.addingTimeInterval(-3 * 86400))
        ])
        let two = thread("father", walkDates: [
            (UUID(), asOf.addingTimeInterval(-1 * 86400)),
            (UUID(), asOf.addingTimeInterval(-2 * 86400))
        ])
        let selected = ThreadIntentionSuggestions.select(threads: [two, three, alsoThree], asOf: asOf)
        XCTAssertEqual(selected, ["walk with 'river'", "walk with 'worry'"],
                       "count desc, then term asc — 'father' at count 2 is capped out by the two count-3 threads")
    }

    func testSelect_phraseFormatPinned() {
        let move = thread("the move", walkDates: [
            (UUID(), asOf.addingTimeInterval(-5 * 86400)),
            (UUID(), asOf.addingTimeInterval(-10 * 86400))
        ])
        XCTAssertEqual(ThreadIntentionSuggestions.select(threads: [move], asOf: asOf), ["walk with 'the move'"])
    }

    func testSelect_dedupesIdenticalPhrasesBeforeCap() {
        let move = thread("the move", walkDates: [
            (UUID(), asOf.addingTimeInterval(-1 * 86400)),
            (UUID(), asOf.addingTimeInterval(-2 * 86400)),
            (UUID(), asOf.addingTimeInterval(-3 * 86400))
        ])
        let moving = WalkThread(
            lemma: "moving", displayTerm: "the move",
            appearances: [
                ThreadAppearance(recordingUUID: UUID(), walkUUID: UUID(),
                                 date: asOf.addingTimeInterval(-1 * 86400), mentionCount: 2, salience: 0.02),
                ThreadAppearance(recordingUUID: UUID(), walkUUID: UUID(),
                                 date: asOf.addingTimeInterval(-2 * 86400), mentionCount: 2, salience: 0.02),
                ThreadAppearance(recordingUUID: UUID(), walkUUID: UUID(),
                                 date: asOf.addingTimeInterval(-3 * 86400), mentionCount: 2, salience: 0.02)
            ]
        )
        let river = thread("river", walkDates: [
            (UUID(), asOf.addingTimeInterval(-1 * 86400)),
            (UUID(), asOf.addingTimeInterval(-2 * 86400))
        ])
        XCTAssertEqual(
            ThreadIntentionSuggestions.select(threads: [move, moving, river], asOf: asOf),
            ["walk with 'the move'", "walk with 'river'"],
            "two lemmas sharing a display term yield one chip, and the cap still fills from the next distinct phrase"
        )
    }

    func testSelect_windowBoundary_exactlyThirtyDaysIsInclusive() {
        let tide = thread("tide", walkDates: [
            (UUID(), asOf.addingTimeInterval(-ThreadIntentionSuggestions.recurrenceWindow)),
            (UUID(), asOf.addingTimeInterval(-1 * 86400))
        ])
        XCTAssertEqual(ThreadIntentionSuggestions.select(threads: [tide], asOf: asOf), ["walk with 'tide'"],
                       "an appearance exactly at asOf − 30d is inside the window")
    }

    func testSelect_windowBoundary_oneSecondBeyondIsExcluded() {
        let tide = thread("tide", walkDates: [
            (UUID(), asOf.addingTimeInterval(-ThreadIntentionSuggestions.recurrenceWindow - 1)),
            (UUID(), asOf.addingTimeInterval(-1 * 86400))
        ])
        XCTAssertTrue(ThreadIntentionSuggestions.select(threads: [tide], asOf: asOf).isEmpty,
                      "one second beyond the window leaves a single distinct walk — below the floor")
    }

    func testFieldGate_passed_chipsAreLive() {
        XCTAssertFalse(ThreadIntentionSuggestions.pendingFieldGate,
                       "field gate passed 2026-08-24 (spec addendum) — chips ship live in 1.12.0")
    }

    @MainActor
    func testCurrent_releaseVisibleOnNextCall() async {
        let saved = UserPreferences.threadsAfterWalks.value
        defer { UserPreferences.threadsAfterWalks.value = saved }
        UserPreferences.threadsAfterWalks.value = true

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuggestionsWiring-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptContextStore(directory: directory)

        let suiteName = "SuggestionsWiring-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let releasedStore = ReleasedThreadsStore(defaults: defaults)

        let base = DateFactory.makeDate(2024, 6, 1, 9, 0, 0)
        let recA = UUID(), recB = UUID()
        let walkIndex: [UUID: (walkUUID: UUID, date: Date)] = [
            recA: (UUID(), base),
            recB: (UUID(), base.addingTimeInterval(5 * 86400))
        ]
        for rec in [recA, recB] {
            _ = store.save(TranscriptContext(
                schemaVersion: 1, recordingUUID: rec, transcriptHash: "h",
                languageCode: "en", wordCount: 200,
                themes: [Theme(lemma: "move", displayTerm: "the move", mentionCount: 3,
                               salience: 0.015, mentions: [ThemeMention(start: 0, length: 4)])],
                markers: nil
            ))
        }

        let asOf = base.addingTimeInterval(6 * 86400)
        let before = await ThreadIntentionSuggestions.current(
            asOf: asOf, store: store, releasedStore: releasedStore, walkIndex: walkIndex
        )
        XCTAssertEqual(before, ["walk with 'the move'"],
                       "fixture sanity — the suggestion is live before the release")

        releasedStore.release(displayTerm: "the move", lemmas: ["move"])
        let after = await ThreadIntentionSuggestions.current(
            asOf: asOf, store: store, releasedStore: releasedStore, walkIndex: walkIndex
        )
        XCTAssertTrue(after.isEmpty,
                      "current()'s own build path filters released lemmas and its memo re-keys on the released token — visible on the very next call")
    }

    @MainActor
    func testCurrent_toggleOff_returnsEmptyWithoutTouchingTheStore() async {
        let saved = UserPreferences.threadsAfterWalks.value
        defer { UserPreferences.threadsAfterWalks.value = saved }
        UserPreferences.threadsAfterWalks.value = false

        let suggestions = await ThreadIntentionSuggestions.current()
        XCTAssertTrue(suggestions.isEmpty,
                      "off means off — the guard fires before any walk index or store read")
    }
}
