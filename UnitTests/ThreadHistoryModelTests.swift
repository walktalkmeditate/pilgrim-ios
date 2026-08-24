import XCTest
import CoreLocation
@testable import Pilgrim

final class ThreadHistoryModelTests: XCTestCase {

    private let base = DateFactory.makeDate(2024, 6, 1, 9, 0, 0)

    private func appearance(recording: UUID, walk: UUID, date: Date, mentions: Int = 2) -> ThreadAppearance {
        ThreadAppearance(recordingUUID: recording, walkUUID: walk, date: date,
                         mentionCount: mentions, salience: 0.01)
    }

    func testEntries_newestFirstWithOriginOnOldest() {
        let recs = [UUID(), UUID(), UUID()]
        let thread = WalkThread(lemma: "move", displayTerm: "the move", appearances: recs.enumerated().map {
            appearance(recording: $1, walk: UUID(), date: base.addingTimeInterval(Double($0) * 86400))
        })
        let entries = ThreadHistoryModelBuilder.entries(
            cohort: [thread], contextsByRecording: [:], transcriptsByRecording: [:],
            backfillComplete: true
        )
        XCTAssertEqual(entries.map(\.recordingUUID), [recs[2], recs[1], recs[0]])
        XCTAssertEqual(entries.map(\.isOrigin), [false, false, true],
                       "the oldest entry carries 'where it began'")
    }

    func testEntries_backfillIncomplete_suppressesOrigin() {
        let recs = [UUID(), UUID()]
        let thread = WalkThread(lemma: "move", displayTerm: "the move", appearances: recs.enumerated().map {
            appearance(recording: $1, walk: UUID(), date: base.addingTimeInterval(Double($0) * 86400))
        })
        let entries = ThreadHistoryModelBuilder.entries(
            cohort: [thread], contextsByRecording: [:], transcriptsByRecording: [:],
            backfillComplete: false
        )
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { !$0.isOrigin },
                      "origin claims stay suppressed pre-backfill — no 'where it began' footer, no origin-map action")
    }

    func testEntries_onePerRecordingAcrossCohort() {
        let rec = UUID(), walk = UUID()
        let cohort = [
            WalkThread(lemma: "move", displayTerm: "the move",
                       appearances: [appearance(recording: rec, walk: walk, date: base, mentions: 3)]),
            WalkThread(lemma: "moving", displayTerm: "the move",
                       appearances: [appearance(recording: rec, walk: walk, date: base, mentions: 2)])
        ]
        let entries = ThreadHistoryModelBuilder.entries(
            cohort: cohort, contextsByRecording: [:], transcriptsByRecording: [:],
            backfillComplete: true
        )
        XCTAssertEqual(entries.count, 1, "two cohort lemmas in one recording is still one moment")
    }

    func testExcerpt_realOffsetsFromAnalyzer() {
        let transcript = "A long quiet morning on the water. The river kept speaking to me about " +
            "patience and the river answered its own question before I could. Nothing else needed saying today."
        let uuid = UUID()
        let context = TranscriptContextAnalyzer.analyze(recordingUUID: uuid, transcript: transcript)
        XCTAssertTrue(context.themes.contains { $0.lemma == "river" }, "fixture sanity")
        let excerpt = ThreadHistoryModelBuilder.excerpt(
            for: ["river"], context: context, transcript: transcript
        )
        XCTAssertNotNil(excerpt)
        XCTAssertTrue(excerpt!.contains("river"))
    }

    func testExcerpt_hashMismatchReturnsNil() {
        let transcript = "The river again today, and the river once more — twenty five words of it, " +
            "give or take, spoken slowly into the morning air."
        let context = TranscriptContextAnalyzer.analyze(recordingUUID: UUID(), transcript: transcript)
        XCTAssertNil(ThreadHistoryModelBuilder.excerpt(
            for: ["river"], context: context, transcript: transcript + " edited"
        ), "stored offsets are only trusted against the exact transcript they were computed from")
    }

    func testSlice_graphemeSafeAroundEmoji() {
        let transcript = "🚶‍♂️🌫️🌊 the river again"
        let mentionStart = transcript.distance(
            from: transcript.startIndex,
            to: transcript.range(of: "river")!.lowerBound
        )
        let excerpt = ThreadHistoryModelBuilder.slice(
            transcript, around: ThemeMention(start: mentionStart, length: 5), radius: 60
        )
        XCTAssertNotNil(excerpt)
        XCTAssertTrue(excerpt!.contains("river"),
                      "multi-scalar emoji before the mention must not shift the slice")
    }

    func testSlice_outOfBoundsMentionReturnsNil() {
        XCTAssertNil(ThreadHistoryModelBuilder.slice(
            "short", around: ThemeMention(start: 40, length: 5), radius: 60
        ))
        XCTAssertNil(ThreadHistoryModelBuilder.slice(
            "short", around: ThemeMention(start: 2, length: 40), radius: 60
        ))
    }

    func testSlice_ellipsesOnlyWhereTruncated() {
        let transcript = String(repeating: "before ", count: 30) + "river" + String(repeating: " after", count: 30)
        let mentionStart = transcript.distance(
            from: transcript.startIndex,
            to: transcript.range(of: "river")!.lowerBound
        )
        let middle = ThreadHistoryModelBuilder.slice(
            transcript, around: ThemeMention(start: mentionStart, length: 5), radius: 30
        )
        XCTAssertTrue(middle!.hasPrefix("…") && middle!.hasSuffix("…"))

        let atStart = ThreadHistoryModelBuilder.slice(
            "river first then much more text follows on and on and on and on and on and on and on",
            around: ThemeMention(start: 0, length: 5), radius: 30
        )
        XCTAssertFalse(atStart!.hasPrefix("…"), "no leading ellipsis when the slice reaches the start")
    }

    func testSlice_noWhitespaceWindow_degeneratesToBareEllipsis() {
        let transcript = String(repeating: "a", count: 200)
        let excerpt = ThreadHistoryModelBuilder.slice(
            transcript, around: ThemeMention(start: 100, length: 5), radius: 30
        )
        XCTAssertEqual(excerpt, "…",
                       "a truncated window with no whitespace trims to a bare ellipsis — pinned so any future formatting change is deliberate, not accidental")
    }

    func testOriginResolver_toleranceBoundary() {
        let start = base
        let sample: (Date) -> (timestamp: Date, latitude: Double, longitude: Double) = {
            ($0, 43.0, -8.5)
        }
        XCTAssertNotNil(ThreadOriginResolver.coordinate(
            recordingStart: start, samples: [sample(start.addingTimeInterval(120))]
        ), "a fix exactly at the tolerance edge still counts")
        XCTAssertNil(ThreadOriginResolver.coordinate(
            recordingStart: start, samples: [sample(start.addingTimeInterval(121))]
        ), "beyond tolerance the coordinate is a guess — the action hides instead")
        XCTAssertNil(ThreadOriginResolver.coordinate(recordingStart: start, samples: []))
    }

    func testOriginResolver_picksNearestSample() {
        let start = base
        let coordinate = ThreadOriginResolver.coordinate(
            recordingStart: start,
            samples: [
                (start.addingTimeInterval(-90), 1.0, 1.0),
                (start.addingTimeInterval(10), 2.0, 2.0),
                (start.addingTimeInterval(60), 3.0, 3.0)
            ]
        )
        XCTAssertEqual(coordinate?.latitude, 2.0)
    }
}
