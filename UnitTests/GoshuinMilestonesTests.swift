import XCTest
@testable import Pilgrim

final class GoshuinMilestonesTests: XCTestCase {

    func testFirstWalk_isMilestone() {
        let milestones = GoshuinMilestones.detect(walkCount: 1, walkIndex: 0, walk: nil, allWalks: [])
        XCTAssertTrue(milestones.contains(.firstWalk))
    }

    func testEveryTenth_isMilestone() {
        let m10 = GoshuinMilestones.detect(walkCount: 10, walkIndex: 9, walk: nil, allWalks: [])
        XCTAssertTrue(m10.contains(.nthWalk(10)))

        let m20 = GoshuinMilestones.detect(walkCount: 20, walkIndex: 19, walk: nil, allWalks: [])
        XCTAssertTrue(m20.contains(.nthWalk(20)))
    }

    func testNonMilestone_isEmpty() {
        let m = GoshuinMilestones.detect(walkCount: 7, walkIndex: 6, walk: nil, allWalks: [])
        XCTAssertTrue(m.isEmpty)
    }

    func testSecondWalk_notFirstWalk() {
        let m = GoshuinMilestones.detect(walkCount: 2, walkIndex: 1, walk: nil, allWalks: [])
        XCTAssertFalse(m.contains(.firstWalk))
    }

    // MARK: - Seeking thresholds

    func testFirstUnknown_awardedToTheWalkWithTheFirstArrival() {
        let m = GoshuinMilestones.seekingMilestones(arrivalsInWalk: 2, arrivalsBefore: 0)
        XCTAssertTrue(m.contains(.firstUnknown))
        XCTAssertFalse(m.contains(.unknownsFound(10)))
    }

    func testNoArrivals_earnsNothing() {
        XCTAssertTrue(GoshuinMilestones.seekingMilestones(arrivalsInWalk: 0, arrivalsBefore: 5).isEmpty)
    }

    func testThresholdCrossing_awardedOnceToTheCrossingWalk() {
        let crossing = GoshuinMilestones.seekingMilestones(arrivalsInWalk: 2, arrivalsBefore: 9)
        XCTAssertTrue(crossing.contains(.unknownsFound(10)))
        XCTAssertFalse(crossing.contains(.firstUnknown))

        let after = GoshuinMilestones.seekingMilestones(arrivalsInWalk: 1, arrivalsBefore: 11)
        XCTAssertFalse(after.contains(.unknownsFound(10)))
    }

    func testExactLanding_onThreshold_stillAwards() {
        let m = GoshuinMilestones.seekingMilestones(arrivalsInWalk: 1, arrivalsBefore: 24)
        XCTAssertTrue(m.contains(.unknownsFound(25)))
    }

    func testSeekingLabels() {
        XCTAssertEqual(GoshuinMilestones.label(for: .firstUnknown), "First Unknown")
        XCTAssertEqual(GoshuinMilestones.label(for: .unknownsFound(25)), "25 Unknowns")
    }

    // MARK: - Primary milestone (stable caption)

    func testPrimaryMilestone_isStableAndRanked() {
        let crowded: Set<GoshuinMilestones.Milestone> = [
            .longestWalk, .firstOfSeason("Summer"), .unknownsFound(10),
            .unknownsFound(25), .nthWalk(10), .firstWalk
        ]
        XCTAssertEqual(GoshuinMilestones.primaryMilestone(of: crowded), .firstWalk)
        XCTAssertEqual(
            GoshuinMilestones.primaryMilestone(of: [.unknownsFound(10), .unknownsFound(25), .longestWalk]),
            .unknownsFound(25),
            "the largest crossing is the headline"
        )
        XCTAssertNil(GoshuinMilestones.primaryMilestone(of: []))
    }

    // MARK: - detect() aggregation (arrivalsBefore ordering, exclusion, ties)

    private func seekWalk(uuid: UUID, daysAgo: Int, arrivals: Int) -> TempWalk {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
            .addingTimeInterval(-Double(daysAgo) * 86_400)
        return WalkDataFactory.makeWalk(
            uuid: uuid,
            startDate: start,
            waypoints: (0..<arrivals).map { index in
                TempWaypoint(
                    uuid: nil,
                    latitude: Double(index),
                    longitude: 0,
                    label: SeekPersistence.arrivalWaypointLabel(clearingOrdinal: index + 1),
                    icon: SeekPersistence.arrivalWaypointIcon,
                    timestamp: start.addingTimeInterval(Double(index + 1) * 600)
                )
            }
        )
    }

    private func seekMilestones(for walk: TempWalk, in all: [WalkInterface]) -> Set<GoshuinMilestones.Milestone> {
        GoshuinMilestones.detect(
            walkCount: all.count,
            walkIndex: 4,
            walk: walk,
            allWalks: all,
            arrivalCounts: GoshuinMilestones.arrivalCounts(for: all)
        )
    }

    func testDetect_firstUnknown_goesToTheEarliestArrivalWalk() {
        let earlier = seekWalk(uuid: UUID(), daysAgo: 2, arrivals: 1)
        let later = seekWalk(uuid: UUID(), daysAgo: 0, arrivals: 1)
        let all: [WalkInterface] = [earlier, later]

        XCTAssertTrue(seekMilestones(for: earlier, in: all).contains(.firstUnknown))
        XCTAssertFalse(
            seekMilestones(for: later, in: all).contains(.firstUnknown),
            "the earlier walk's arrivals must count as before the later walk"
        )
    }

    func testDetect_ownArrivalsNeverCountAsBefore() {
        let only = seekWalk(uuid: UUID(), daysAgo: 1, arrivals: 2)
        XCTAssertTrue(
            seekMilestones(for: only, in: [only]).contains(.firstUnknown),
            "a walk's own arrivals must not inflate its arrivalsBefore"
        )
    }

    func testDetect_identicalStartDates_awardFirstUnknownExactlyOnce() {
        let first = seekWalk(uuid: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!, daysAgo: 1, arrivals: 1)
        let second = seekWalk(uuid: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!, daysAgo: 1, arrivals: 1)
        let all: [WalkInterface] = [first, second]

        let awards = [
            seekMilestones(for: first, in: all).contains(.firstUnknown),
            seekMilestones(for: second, in: all).contains(.firstUnknown)
        ]
        XCTAssertEqual(awards.filter { $0 }.count, 1, "a startDate tie must resolve to exactly one first unknown")
    }
}
