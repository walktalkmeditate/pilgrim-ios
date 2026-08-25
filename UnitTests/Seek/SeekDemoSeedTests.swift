import XCTest
@testable import Pilgrim

#if DEBUG
final class SeekDemoSeedTests: XCTestCase {

    private let startDate = DateFactory.makeDate(2026, 7, 4, 8, 0, 0)

    private func makeDemoSeekWalk() throws -> NewWalk {
        let spec = try XCTUnwrap(
            ScreenshotDataSeeder.walks.first { !$0.events.isEmpty },
            "The seeder should carry a demo seek walk"
        )
        return ScreenshotDataSeeder.makeWalk(from: spec, startDate: startDate, index: 0)
    }

    func testDemoSeekWalk_marksSeekModeAndTwoArrivals() throws {
        let walk = try makeDemoSeekWalk()
        let events = walk.workoutEvents.map(\.eventType)

        XCTAssertEqual(events.filter { $0 == .seekMode }.count, 1)
        XCTAssertEqual(events.filter { $0 == .seekArrival }.count, 2)
    }

    func testDemoSeekWalk_arrivalWaypointsCarryReservedIcon() throws {
        let walk = try makeDemoSeekWalk()
        let arrivals = walk.waypoints.filter { SeekPersistence.isArrivalWaypoint($0) }

        XCTAssertEqual(arrivals.count, 2)
        XCTAssertTrue(arrivals.allSatisfy { $0.icon == SeekPersistence.arrivalWaypointIcon })
    }

    func testDemoSeekWalk_summaryTellsTwoClearingStory() throws {
        let walk = try makeDemoSeekWalk()

        XCTAssertTrue(SeekSummaryModel.isSeekWalk(events: walk.workoutEvents.map(\.eventType)))
        let data = try XCTUnwrap(SeekSummaryModel.summaryData(for: walk))
        XCTAssertEqual(data.groups.count, 2)
        XCTAssertEqual(data.groups.map(\.ordinal), [1, 2])
        XCTAssertEqual(data.groups[0].waypointIDs.count, 1, "The Grateful mark should group into the first clearing")
    }

    func testExistingDemoWalks_stayWanderWalks() {
        let wanderSpecs = ScreenshotDataSeeder.walks.filter { $0.events.isEmpty }

        XCTAssertEqual(wanderSpecs.count, 5)
        XCTAssertTrue(wanderSpecs.allSatisfy { $0.waypoints.isEmpty })
    }

    /// Without a shared, repeated lemma across at least two demo transcripts,
    /// ThemeExtractor's 25-word and 2-mention floors mean no theme can ever
    /// form in demo mode — the intention chips and dossier would be
    /// permanently unreachable for screenshots and QA. Runs the real analysis
    /// + aggregation pipeline over the seeder's own transcripts, the same way
    /// ThreadsDossierTests exercises it.
    func testDemoTranscripts_shareThemeAcrossTwoDistinctWalks() {
        var walksIndex: [UUID: (walkUUID: UUID, date: Date)] = [:]
        var contexts: [TranscriptContext] = []

        for (index, spec) in ScreenshotDataSeeder.walks.enumerated() {
            guard let transcript = spec.transcription else { continue }
            let recordingUUID = UUID()
            let walkUUID = UUID()
            let date = startDate.addingTimeInterval(Double(index) * 86400)
            walksIndex[recordingUUID] = (walkUUID, date)
            contexts.append(TranscriptContextAnalyzer.analyze(recordingUUID: recordingUUID, transcript: transcript))
        }

        let threads = ThreadStore.build(contexts: contexts, walks: walksIndex)
        let spanningTwoWalks = threads.filter { Set($0.appearances.map(\.walkUUID)).count >= 2 }

        XCTAssertFalse(spanningTwoWalks.isEmpty,
                       "demo transcripts must share a theme across at least two walks so the intention " +
                       "chips and dossier are reachable in demo mode")
    }
}
#endif
