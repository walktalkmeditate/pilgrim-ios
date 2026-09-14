import XCTest
import CoreLocation
import CoreStore
@testable import Pilgrim

/// A stage walk the OS killed mid-way: what the checkpoint has to carry for
/// next launch to bind the recovered walk back to its Way and write the stage
/// into the route's ledger. Cases of `PilgrimageStageWalkTests` (its stage
/// fixture builds the Way); a file of their own only because that one is at
/// SwiftLint's length gate.
extension PilgrimageStageWalkTests {

    func testACheckpointCarriesTheWayAndTheEnginesLastWord() {
        let vm = honorWalk(way: stageWay())
        vm.builder.setStatus(.ready)
        vm.startRecording()
        XCTAssertNil(vm.honorCheckpointState?.outcome, "no fix yet, so no stage joined")

        vm.honorEngine?.processLocation(fix(atLongitude: 0.002694))
        let state = vm.honorCheckpointState
        XCTAssertEqual(state?.wayId, WayStore.stageWayId(routeId: "camino-frances", stageIndex: 0))
        XCTAssertEqual(state?.outcome?.progressFrac ?? 0, 0.3, accuracy: 0.02)
        XCTAssertEqual(state?.outcome?.arrived, false)
        vm.teardownHonor()
    }

    func testAWanderWalksCheckpointCarriesNoWay() {
        let vm = ActiveWalkViewModel()
        XCTAssertNil(vm.honorCheckpointState)
    }

    func testACrashedStageWalkFindsItsWayAndItsLedgerAtNextLaunch() throws {
        let way = stageWay(index: 4)
        try store.save(way)
        try useInMemoryStack()

        let walkUUID = UUID()
        try writeCheckpoint(walkUUID: walkUUID, wayId: way.id,
                            outcome: HonorStageOutcome(progressFrac: 0.58, arrived: false))

        XCTAssertNotNil(recover(), "the crashed walk must still be saved")

        XCTAssertEqual(store.wayLink(forWalk: walkUUID)?.wayId, way.id)
        let ledger = try XCTUnwrap(PilgrimageLedgerStore(store: store).load(routeId: "camino-frances"))
        XCTAssertEqual(ledger.stages["4"]?.name, "Saint-Jean-Pied-de-Port to Roncesvalles")
        XCTAssertEqual(ledger.stages["4"]?.stoppedAtFrac ?? 0, 0.58, accuracy: 0.001)
        XCTAssertEqual(ledger.stages["4"]?.completed, false)
    }

    /// A walk that crashed while the walker was still approaching earned no
    /// ledger entry, but the Way is still theirs — the summary must show its
    /// stage block either way.
    func testACrashBeforeTheStageWasJoinedLinksTheWayAndWritesNoLedger() throws {
        let way = stageWay()
        try store.save(way)
        try useInMemoryStack()

        let walkUUID = UUID()
        try writeCheckpoint(walkUUID: walkUUID, wayId: way.id, outcome: nil)

        XCTAssertNotNil(recover())

        XCTAssertEqual(store.wayLink(forWalk: walkUUID)?.wayId, way.id)
        XCTAssertNil(PilgrimageLedgerStore(store: store).load(routeId: "camino-frances"),
                     "an approach is not a stage walked")
    }

    func testACheckpointFromBeforeTheWayIdStillRecoversAsAPlainWalk() throws {
        try store.save(stageWay())
        try useInMemoryStack()

        let walkUUID = UUID()
        try writeCheckpoint(walkUUID: walkUUID, wayId: nil, outcome: nil,
                            forcedSchemaVersion: WalkCheckpoint.minimumRecoverableSchemaVersion)

        XCTAssertNotNil(recover(), "a walk crashed under the previous build is not thrown away")

        XCTAssertNil(store.wayLink(forWalk: walkUUID))
        XCTAssertNil(PilgrimageLedgerStore(store: store).load(routeId: "camino-frances"))
    }

    // MARK: - Helpers

    private func fix(atLongitude longitude: Double) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: longitude),
                   altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: start)
    }

    /// The recovery path writes into the real store, so it needs one that
    /// isn't the walker's. Restored when the test ends.
    private func useInMemoryStack() throws {
        let previous = DataManager.dataStack
        addTeardownBlock { DataManager.dataStack = previous }
        let stack = DataStack(PilgrimV7.schema)
        try stack.addStorageAndWait(InMemoryStore())
        DataManager.dataStack = stack
    }

    /// `forcedSchemaVersion` rewrites the encoded JSON rather than the struct,
    /// which is the only way to produce a checkpoint an older build wrote.
    private func writeCheckpoint(
        walkUUID: UUID,
        wayId: String?,
        outcome: HonorStageOutcome?,
        forcedSchemaVersion: Int? = nil
    ) throws {
        let checkpoint = WalkCheckpoint(
            walkUUID: walkUUID, walk: WalkDataFactory.makeWalk(uuid: walkUUID), wayId: wayId,
            honorProgressFrac: outcome?.progressFrac, honorArrived: outcome?.arrived)
        var data = try JSONEncoder().encode(checkpoint)
        if let forcedSchemaVersion {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            object["schemaVersion"] = forcedSchemaVersion
            data = try JSONSerialization.data(withJSONObject: object)
        }
        let url = WalkSessionGuard.checkpointFileURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    }

    /// The gate is this test's own and only ever gets one of its two signals,
    /// so the orphan sweep — which would delete real recordings — never runs.
    private func recover() -> Date? {
        var recovered: Date?
        let done = expectation(description: "recovery completion")
        WalkSessionGuard.recoverIfNeeded(sweepGate: OrphanSweepGate {}, wayStore: store) { date in
            recovered = date
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        return recovered
    }
}
