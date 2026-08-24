import XCTest
@testable import Pilgrim

final class LunationRecapModelTests: XCTestCase {

    private let lunation = LunationCalendar.lunation(at: 300)

    private func context(_ uuid: UUID, lemma: String?, displayTerm: String? = nil, insight: Int = 0) -> TranscriptContext {
        TranscriptContext(
            schemaVersion: 1, recordingUUID: uuid, transcriptHash: "h",
            languageCode: "en", wordCount: 200,
            themes: lemma.map { [Theme(
                lemma: $0, displayTerm: displayTerm ?? $0, mentionCount: 3, salience: 0.015,
                mentions: [ThemeMention(start: 0, length: 4)]
            )] } ?? [],
            markers: MarkerPack(
                wordCount: 200, absolutistCount: 0, firstPersonCount: 0,
                insightCount: insight, causationCount: 0, discrepancyCount: 0,
                futureCount: 0, pastCount: 0, sentiment: nil
            )
        )
    }

    private func build(
        contexts: [TranscriptContext],
        walkIndex: [UUID: (walkUUID: UUID, date: Date)],
        paces: [UUID: Double] = [:],
        released: Set<String> = [],
        backfillComplete: Bool = true
    ) -> LunationRecapModel {
        LunationRecapModelBuilder.model(
            lunation: lunation, moonName: "Sturgeon Moon",
            contexts: contexts, walkIndex: walkIndex,
            paceByRecording: paces, released: released,
            backfillComplete: backfillComplete
        )
    }

    /// Three analyzed walks inside the moon; "move" spoken in two of them.
    private func fixture() -> (contexts: [TranscriptContext], walkIndex: [UUID: (walkUUID: UUID, date: Date)]) {
        let recs = [UUID(), UUID(), UUID()]
        let walks = [UUID(), UUID(), UUID()]
        let contexts = [
            context(recs[0], lemma: "move"),
            context(recs[1], lemma: "move"),
            context(recs[2], lemma: nil)
        ]
        var walkIndex: [UUID: (walkUUID: UUID, date: Date)] = [:]
        for (offset, rec) in recs.enumerated() {
            walkIndex[rec] = (walks[offset], lunation.start.addingTimeInterval(Double(offset + 1) * 86400))
        }
        return (contexts, walkIndex)
    }

    func testModel_countsWalksAndThemes() {
        let (contexts, walkIndex) = fixture()
        let model = build(contexts: contexts, walkIndex: walkIndex)
        XCTAssertEqual(model.walkCount, 3)
        XCTAssertEqual(model.themes.map(\.displayTerm), ["move"])
        XCTAssertEqual(model.themes.first?.walkCount, 2)
        XCTAssertNil(model.quietLine)
    }

    func testThemeLine_countCopyPinned() {
        XCTAssertEqual(
            LunationRecapCopy.themeLine(term: "the move", walkCount: 6, totalWalks: 9),
            "'the move' — walked with you in 6 of 9 walks"
        )
        XCTAssertEqual(
            LunationRecapCopy.themeLine(term: "father", walkCount: 1, totalWalks: 1),
            "'father' — walked with you in 1 of 1 walks",
            "a single-walk moon still uses count copy — spec sparse state"
        )
    }

    func testScopeDivergence_recapAndCardPhrasingsAreStructurallyDistinct() {
        let recap = LunationRecapCopy.themeLine(term: "move", walkCount: 3, totalWalks: 4)
        let card = ThreadsCardCopy.statusNote(for: .recurring(walksInWindow: 3))!
        XCTAssertTrue(recap.contains("walked with you in"))
        XCTAssertFalse(card.contains("walked with you in"))
        XCTAssertTrue(card.hasSuffix("walk now"),
                      "lunation counts vs trailing-window ordinals must never read as the same metric disagreeing")
    }

    func testNewThisMoon_gatedOnBackfill() {
        let (contexts, walkIndex) = fixture()
        XCTAssertEqual(build(contexts: contexts, walkIndex: walkIndex).themes.first?.isNewThisMoon, true)
        XCTAssertEqual(
            build(contexts: contexts, walkIndex: walkIndex, backfillComplete: false).themes.first?.isNewThisMoon,
            false,
            "firsts are full-history origin claims — suppressed until backfill completes"
        )
    }

    func testNewThisMoon_falseWhenThreadPredatesTheMoon() {
        var (contexts, walkIndex) = fixture()
        let earlierRec = UUID()
        contexts.append(context(earlierRec, lemma: "move"))
        walkIndex[earlierRec] = (UUID(), lunation.start.addingTimeInterval(-10 * 86400))
        XCTAssertEqual(build(contexts: contexts, walkIndex: walkIndex).themes.first?.isNewThisMoon, false)
    }

    func testNewThisMoon_falseWhenSiblingLemmaPredatesTheMoon() {
        var (contexts, walkIndex) = fixture()
        let earlierRec = UUID()
        contexts.append(context(earlierRec, lemma: "moving", displayTerm: "move"))
        walkIndex[earlierRec] = (UUID(), lunation.start.addingTimeInterval(-10 * 86400))
        XCTAssertEqual(build(contexts: contexts, walkIndex: walkIndex).themes.first?.isNewThisMoon, false,
                       "a sibling lemma of the same display term predating the moon makes the theme returning, not new — cohorts group over ALL threads")
    }

    func testReleasedFiltering_leavesTheQuietLine() {
        let (contexts, walkIndex) = fixture()
        let model = build(contexts: contexts, walkIndex: walkIndex, released: ["move"])
        XCTAssertTrue(model.themes.isEmpty)
        XCTAssertEqual(model.walkCount, 3, "the moon's walk count stands even when nothing is named")
        XCTAssertEqual(model.quietLine, "nothing held on to name this time")
    }

    func testRecapPathRelease_rebuildDropsThemeAndLeavesQuietLine() {
        let (contexts, walkIndex) = fixture()
        XCTAssertEqual(build(contexts: contexts, walkIndex: walkIndex).themes.map(\.displayTerm), ["move"],
                       "fixture sanity — the theme is present before the release")
        let after = build(contexts: contexts, walkIndex: walkIndex, released: ["move"])
        XCTAssertTrue(after.themes.isEmpty)
        XCTAssertEqual(after.quietLine, "nothing held on to name this time",
                       "the released-token re-key rebuilds the recap the moment the thread view pops — a released theme drops out instead of dead-ending")
    }

    func testZeroAnalyzedWalks_hasItsOwnQuietLine() {
        let model = build(contexts: [], walkIndex: [:])
        XCTAssertEqual(model.walkCount, 0)
        XCTAssertEqual(model.quietLine, "no recorded words walked this moon")
    }

    func testWalksOutsideTheLunation_doNotCount() {
        let rec = UUID()
        let walkIndex = [rec: (walkUUID: UUID(), date: lunation.end.addingTimeInterval(3600))]
        let model = build(contexts: [context(rec, lemma: "move")], walkIndex: walkIndex)
        XCTAssertEqual(model.walkCount, 0, "the window is [start, end) — the close belongs to the next moon")
    }

    func testWalkCount_ignoresWalksWithoutAnalyzedWords() {
        var (contexts, walkIndex) = fixture()
        walkIndex[UUID()] = (UUID(), lunation.start.addingTimeInterval(5 * 86400))
        let model = build(contexts: contexts, walkIndex: walkIndex)
        XCTAssertEqual(model.walkCount, 3,
                       "an untranscribed recording's walk doesn't count — the headline copy scopes the claim to walks with recorded words for exactly this reason")
    }

    func testHeadline_scopedToWalksWithRecordedWords() {
        XCTAssertEqual(LunationRecapCopy.headline(walkCount: 3), "3 walks with recorded words this moon")
        XCTAssertEqual(LunationRecapCopy.headline(walkCount: 1), "1 walk with recorded words this moon",
                       "the qualifier keeps the count honest against a journal showing more walks this moon")
    }

    func testTexture_paceAndInsightFromTheMoonsRecordings() {
        let (contexts, walkIndex) = fixture()
        let insightful = contexts.map { original in
            TranscriptContext(
                schemaVersion: 1, recordingUUID: original.recordingUUID, transcriptHash: "h",
                languageCode: "en", wordCount: 200, themes: original.themes,
                markers: MarkerPack(
                    wordCount: 200, absolutistCount: 0, firstPersonCount: 0,
                    insightCount: 2, causationCount: 0, discrepancyCount: 0,
                    futureCount: 0, pastCount: 0, sentiment: nil
                )
            )
        }
        let paces = Dictionary(uniqueKeysWithValues: walkIndex.keys.map { ($0, 80.0) })
        let model = build(contexts: insightful, walkIndex: walkIndex, paces: paces)
        XCTAssertEqual(model.textureLine, "Spoken slowly, with words of insight.")
    }

    func testInvitationCopy_pinned() {
        XCTAssertEqual(
            LunationRecapCopy.invitation(moonName: "Sturgeon Moon"),
            "The Sturgeon Moon has set — see what walked with you."
        )
    }

    func testClosedLunations_boundedByFirstCard() {
        let suiteName = "PastRecapsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = LunationRecapState(defaults: defaults)
        let now = LunationCalendar.lunation(at: 303).start.addingTimeInterval(86400)

        XCTAssertTrue(PastRecapsListView.closedLunations(now: now, state: state).isEmpty,
                      "no first card, no reachable moons")

        state.markFirstCardShown(now: LunationCalendar.lunation(at: 300).start.addingTimeInterval(86400))
        XCTAssertEqual(
            PastRecapsListView.closedLunations(now: now, state: state).map(\.index),
            [302, 301, 300],
            "every moon closed since first contact, newest first — a missed line never costs the month"
        )
    }

    func testClosedLunations_boundaryEndEqualsFirstShown_excluded() {
        let suiteName = "PastRecapsBoundary-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = LunationRecapState(defaults: defaults)
        state.markFirstCardShown(now: LunationCalendar.lunation(at: 300).end)
        let now = LunationCalendar.lunation(at: 302).start.addingTimeInterval(86400)
        XCTAssertEqual(
            PastRecapsListView.closedLunations(now: now, state: state).map(\.index),
            [301],
            "a moon closing at the exact first-shown instant belongs to backfilled history — the strict `>` is deliberate and pinned"
        )
    }
}
