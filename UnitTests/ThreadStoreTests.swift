import XCTest
@testable import Pilgrim

final class ThreadStoreTests: XCTestCase {

    private let base = DateFactory.makeDate(2024, 6, 1, 9, 0, 0)

    private func context(_ uuid: UUID, lemma: String, mentions: Int, words: Int = 200) -> TranscriptContext {
        TranscriptContext(
            schemaVersion: 1, recordingUUID: uuid, transcriptHash: "h",
            languageCode: "en", wordCount: words,
            themes: [Theme(
                lemma: lemma, displayTerm: lemma, mentionCount: mentions,
                salience: Double(mentions) / Double(words),
                mentions: Array(repeating: ThemeMention(start: 0, length: 4), count: mentions)
            )],
            markers: nil
        )
    }

    /// Three walks, ten days apart, all speaking of "move".
    private func fixture() -> (threads: [WalkThread], walkUUIDs: [UUID]) {
        let recordings = [UUID(), UUID(), UUID()]
        let walkUUIDs = [UUID(), UUID(), UUID()]
        let contexts = [
            context(recordings[0], lemma: "move", mentions: 3),
            context(recordings[1], lemma: "move", mentions: 4),
            context(recordings[2], lemma: "move", mentions: 2)
        ]
        var walks: [UUID: (walkUUID: UUID, date: Date)] = [:]
        for (i, rec) in recordings.enumerated() {
            walks[rec] = (walkUUIDs[i], base.addingTimeInterval(Double(i) * 10 * 86400))
        }
        return (ThreadStore.build(contexts: contexts, walks: walks), walkUUIDs)
    }

    func testBuild_groupsByLemmaSortedByDate() {
        let (threads, _) = fixture()
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].appearances.count, 3)
        XCTAssertEqual(threads[0].appearances.map(\.date), threads[0].appearances.map(\.date).sorted())
    }

    func testStatus_firstTimeOnlyWithFullHistoryAndBackfill() {
        let (threads, walkUUIDs) = fixture()
        XCTAssertEqual(ThreadStore.status(of: threads[0], atWalk: walkUUIDs[0], backfillComplete: true), .firstTime)
        XCTAssertNil(ThreadStore.status(of: threads[0], atWalk: walkUUIDs[0], backfillComplete: false),
                     "origin claims are suppressed until backfill completes")
    }

    func testStatus_windowAnchorsToViewedWalkNotToday() {
        let (threads, walkUUIDs) = fixture()
        XCTAssertEqual(
            ThreadStore.status(of: threads[0], atWalk: walkUUIDs[2], backfillComplete: true),
            .recurring(walksInWindow: 3),
            "all three walks fall within 30 days of walk 3's own date, regardless of when this test runs"
        )
    }

    func testStatus_gapBeyondHistoryIsStillNotFirstTime() {
        let recordings = [UUID(), UUID()]
        let walkUUIDs = [UUID(), UUID()]
        let contexts = [
            context(recordings[0], lemma: "father", mentions: 3),
            context(recordings[1], lemma: "father", mentions: 3)
        ]
        let walks: [UUID: (walkUUID: UUID, date: Date)] = [
            recordings[0]: (walkUUIDs[0], base),
            recordings[1]: (walkUUIDs[1], base.addingTimeInterval(45 * 86400))
        ]
        let threads = ThreadStore.build(contexts: contexts, walks: walks)
        XCTAssertEqual(
            ThreadStore.status(of: threads[0], atWalk: walkUUIDs[1], backfillComplete: true),
            .recurring(walksInWindow: 1),
            "a 45-day-old prior appearance means never 'first time', even though it is outside the window"
        )
    }

    func testSalienceDirection_fadingAndFloor() {
        let (threads, _) = fixture()
        XCTAssertEqual(ThreadStore.salienceDirection(of: threads[0]), .fading)
        let (two, _) = { () -> ([WalkThread], [UUID]) in
            let r = [UUID(), UUID()]; let w = [UUID(), UUID()]
            let c = [self.context(r[0], lemma: "x", mentions: 3), self.context(r[1], lemma: "x", mentions: 3)]
            let map: [UUID: (walkUUID: UUID, date: Date)] = [
                r[0]: (w[0], self.base), r[1]: (w[1], self.base.addingTimeInterval(86400))
            ]
            return (ThreadStore.build(contexts: c, walks: map), w)
        }()
        XCTAssertNil(ThreadStore.salienceDirection(of: two[0]), "trend inference needs at least 3 points")
    }
}
