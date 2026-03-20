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
}
