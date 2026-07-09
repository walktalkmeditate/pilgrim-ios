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
}
