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
}
#endif
