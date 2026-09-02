import XCTest
import CoreStore
@testable import Pilgrim

/// What an honor walk leaves behind once it is over: the prompt lexicon's
/// reading of its events, the seals it earns, the mark it raises on the ink
/// scroll, the summary numbers, and the journal snapshot the scroll reads.
final class HonorJournalTests: XCTestCase {

    private var stack: DataStack!
    private var previousDataStack: DataStack!

    override func setUpWithError() throws {
        try super.setUpWithError()
        previousDataStack = DataManager.dataStack
        stack = DataStack(PilgrimV7.schema)
        try stack.addStorageAndWait(InMemoryStore())
        DataManager.dataStack = stack
    }

    override func tearDownWithError() throws {
        DataManager.dataStack = previousDataStack
        stack = nil
        try super.tearDownWithError()
    }

    func testPracticeModelReadsHonorEvents() {
        let now = Date()
        let practice = WalkPracticeModel.practice(events: [(.honorMode, now), (.honorArrival, now.addingTimeInterval(60))])
        XCTAssertEqual(practice.mode, .honor)
        XCTAssertEqual(practice.honorStory?.arrived, true)
        let plain = WalkPracticeModel.practice(events: [(.honorMode, now)])
        XCTAssertEqual(plain.honorStory?.arrived, false)
    }

    func testHonorMilestonesMirrorSeeking() {
        XCTAssertEqual(GoshuinMilestones.honorMilestones(arrivalsInWalk: 1, arrivalsBefore: 0), [.firstHonor])
        XCTAssertEqual(GoshuinMilestones.honorMilestones(arrivalsInWalk: 1, arrivalsBefore: 9), [.honorsWalked(10)])
        XCTAssertEqual(GoshuinMilestones.honorMilestones(arrivalsInWalk: 0, arrivalsBefore: 9), [])
        XCTAssertEqual(GoshuinMilestones.label(for: .firstHonor), "First Honor")
        XCTAssertEqual(GoshuinMilestones.label(for: .honorsWalked(25)), "25 Ways Walked")
    }

    func testSceneryRaisesStaffsForAnHonorArrival() {
        let snapshot = WalkSnapshot(
            id: UUID(), startDate: Date(), distance: 3000, duration: 1800, averagePace: 10, cumulativeDistance: 3000,
            talkDuration: 0, meditateDuration: 0, favicon: nil, isShared: false, weatherCondition: nil,
            isSeek: false, foundPlaces: 0, threshold: nil, isHonor: true, honorArrivals: 1)
        XCTAssertEqual(SceneryGenerator.scenery(for: snapshot)?.type, .staffs)
    }

    func testSummaryDataNeedsTheHonorEvent() {
        let way = Way(id: "walk:x", source: .ownWalk(UUID()), title: "Old walk", departedAt: Date(), tzIdentifier: nil,
                      expires: nil, route: [], totalDistanceMeters: 0, theirActiveSeconds: 600, moments: [], weather: nil)
        let plain = WalkDataFactory.makeWalk()
        XCTAssertNil(HonorSummaryModel.summaryData(for: plain, way: way, link: nil, replies: [:]))
        let honored = WalkDataFactory.makeWalk(
            activeDuration: 540,
            workoutEvents: [TempWalkEvent(uuid: nil, eventType: .honorMode, timestamp: Date()),
                            TempWalkEvent(uuid: nil, eventType: .honorArrival, timestamp: Date())])
        let link = WayLink(wayId: "walk:x", theirSeconds: 600, yourSeconds: 540)
        let data = HonorSummaryModel.summaryData(for: honored, way: way, link: link, replies: [2: "r"])
        XCTAssertEqual(data?.wayTitle, "Old walk")
        XCTAssertEqual(data?.repliesMade, 1)
        XCTAssertEqual(data?.arrivedBeforeTheirsSeconds, 60)
        let unlinked = HonorSummaryModel.summaryData(for: honored, way: way, link: nil, replies: [:])
        XCTAssertNil(unlinked?.arrivedBeforeTheirsSeconds, "no delta without the engine's record")
    }

    func testSealInputCountsHonorArrivalsAndCarriesNoWayPointsWithoutALink() {
        let arrival = TempWaypoint(uuid: nil, latitude: 1, longitude: 1, label: "x",
                                   icon: HonorPersistence.arrivalWaypointIcon, timestamp: Date())
        let walk = WalkDataFactory.makeWalk(uuid: UUID(), waypoints: [arrival])
        let input = SealInput(walk: walk)
        XCTAssertEqual(input.honorArrivalCount, 1)
        XCTAssertEqual(input.foundPlaceCount, 0)
        XCTAssertNil(input.wayPoints)
    }

    /// Follows `DataManagerThreadsDeletionTests`' in-memory stack setup.
    func testJournalSnapshotsMarkHonorWalks() throws {
        let walk = WalkDataFactory.makeWalk(
            uuid: UUID(),
            workoutEvents: [TempWalkEvent(uuid: nil, eventType: .honorMode, timestamp: Date())],
            waypoints: [TempWaypoint(uuid: nil, latitude: 1, longitude: 1, label: "x",
                                     icon: HonorPersistence.arrivalWaypointIcon, timestamp: Date())])
        let saved = expectation(description: "saved")
        DataManager.saveWalk(object: walk) { success, _, _ in XCTAssertTrue(success); saved.fulfill() }
        wait(for: [saved], timeout: 5)
        let viewModel = HomeViewModel()
        let snapshot = try XCTUnwrap(viewModel.walkSnapshots.first)
        XCTAssertTrue(snapshot.isHonor)
        XCTAssertEqual(snapshot.honorArrivals, 1)
        XCTAssertFalse(snapshot.isSeek)
    }
}
