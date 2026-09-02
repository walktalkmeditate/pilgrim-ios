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

    /// A store the test owns end to end: the link and the honor event are
    /// varied independently so the assertion pins the guard rather than
    /// just the happy path.
    func testWayPointsRequireBothTheLinkAndTheHonorEvent() throws {
        let storeDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = WayStore(baseDirectory: storeDir)
        defer { try? FileManager.default.removeItem(at: storeDir) }

        let walkUUID = UUID()
        let wayID = "walk:\(walkUUID.uuidString)"
        let route = [WayPoint(lat: 1, lon: 2, alt: nil, t: 0), WayPoint(lat: 3, lon: 4, alt: nil, t: 60)]
        let way = Way(id: wayID, source: .ownWalk(walkUUID), title: "A Way", departedAt: Date(),
                      tzIdentifier: nil, expires: nil, route: route, totalDistanceMeters: 100,
                      theirActiveSeconds: 60, moments: [], weather: nil)
        try store.save(way)
        try store.link(walkUUID: walkUUID, to: wayID, arrival: nil)

        let honored = WalkDataFactory.makeWalk(
            uuid: walkUUID,
            workoutEvents: [TempWalkEvent(uuid: nil, eventType: .honorMode, timestamp: Date())])
        let honoredInput = SealInput(walk: honored, store: store)
        XCTAssertEqual(honoredInput.wayPoints?.map(\.lat), route.map(\.lat))
        XCTAssertEqual(honoredInput.wayPoints?.map(\.lon), route.map(\.lon))

        // The same walk UUID, the same stored link — only the honor event
        // is missing. If the guard in SealInput.init were ever dropped,
        // this would start reading the store for every walk.
        let plain = WalkDataFactory.makeWalk(uuid: walkUUID)
        let plainInput = SealInput(walk: plain, store: store)
        XCTAssertNil(plainInput.wayPoints, "a link with no honor event must not surface the Way's route")
    }

    func testDetectSealInputOverload_honorsWalkedAwardedAtTheCrossingWalk() {
        func honorWaypoints(count: Int, start: Date) -> [TempWaypoint] {
            (0..<count).map { index in
                TempWaypoint(uuid: nil, latitude: Double(index), longitude: 0, label: "x",
                            icon: HonorPersistence.arrivalWaypointIcon,
                            timestamp: start.addingTimeInterval(Double(index) * 60))
            }
        }
        let earlierStart = DateFactory.makeDate(2024, 6, 10, 9, 0, 0)
        let crossingStart = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let earlierWalk = WalkDataFactory.makeWalk(
            uuid: UUID(), startDate: earlierStart, waypoints: honorWaypoints(count: 9, start: earlierStart))
        let crossingWalk = WalkDataFactory.makeWalk(
            uuid: UUID(), startDate: crossingStart, waypoints: honorWaypoints(count: 1, start: crossingStart))
        let inputs = [SealInput(walk: earlierWalk), SealInput(walk: crossingWalk)]

        let milestones = GoshuinMilestones.detect(
            walkCount: inputs.count, walkIndex: 1, input: inputs[1], allInputs: inputs)

        XCTAssertTrue(milestones.contains(.honorsWalked(10)), "the walk that crosses 10 honor arrivals earns the seal")
    }

    func testComputeAnnotationsRendersHonorArrivalsAsWaypointsWithTheReservedIcon() {
        let label = HonorPersistence.arrivalWaypointLabel(wayTitle: "A Way")
        let walk = WalkDataFactory.makeWalk(waypoints: [
            TempWaypoint(uuid: nil, latitude: 0, longitude: 0, label: label,
                        icon: HonorPersistence.arrivalWaypointIcon, timestamp: Date())
        ])

        let pins = WalkSummaryView.computeAnnotations(for: walk)

        guard let pin = pins.first(where: {
            if case .waypoint = $0.kind { return true } else { return false }
        }), case let .waypoint(pinLabel, icon) = pin.kind else {
            return XCTFail("an honor arrival waypoint must render as a .waypoint pin")
        }
        XCTAssertEqual(pinLabel, label)
        XCTAssertEqual(icon, HonorPersistence.arrivalWaypointIcon, "the reserved honor icon must survive onto the pin")
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
