import XCTest
@testable import Pilgrim

/// AF60: two sheet presentations must never change in one update. These pin
/// the park-and-promote handoff that keeps the Ways sheet, the overview, and
/// the walk itself from ever being requested at the same time.
final class MainCoordinatorHonorTests: XCTestCase {

    private let start = DateFactory.makeDate(2026, 5, 1, 8, 0, 0)

    private func makeWalk(uuid: UUID = UUID()) -> TempWalk {
        let route = (0..<4).map { i in
            TempRouteDataSample(uuid: nil, timestamp: start.addingTimeInterval(Double(i) * 60),
                                latitude: 42.88, longitude: -8.54 + Double(i) * 0.00122, altitude: 300,
                                horizontalAccuracy: 5, verticalAccuracy: 5, speed: 1.4, direction: 90)
        }
        return WalkDataFactory.makeWalk(uuid: uuid, startDate: start,
                                        endDate: start.addingTimeInterval(180), routeData: route)
    }

    private func makeWay() throws -> Way {
        try XCTUnwrap(OwnWalkWayBuilder.make(from: makeWalk()))
    }

    func testOpenOverviewFromTheWaysSheetParksWithoutPresenting() throws {
        let coordinator = MainCoordinator()
        let way = try makeWay()
        coordinator.chooseWay()

        coordinator.openOverview(for: way)

        XCTAssertFalse(coordinator.honorWaysPresented)
        XCTAssertNil(coordinator.honorOverviewWay, "the overview must wait for the Ways sheet to finish closing")
        XCTAssertEqual(coordinator.pendingHonorWay?.id, way.id)
    }

    func testPromotePendingHonorWayPresentsTheParkedWay() throws {
        let coordinator = MainCoordinator()
        let way = try makeWay()
        coordinator.chooseWay()
        coordinator.openOverview(for: way)

        coordinator.promotePendingHonorWay()

        XCTAssertEqual(coordinator.honorOverviewWay?.id, way.id)
        XCTAssertNil(coordinator.pendingHonorWay)
    }

    func testOpenOverviewWithNoSheetUpPresentsDirectly() throws {
        let coordinator = MainCoordinator()
        let way = try makeWay()

        coordinator.openOverview(for: way)

        XCTAssertEqual(coordinator.honorOverviewWay?.id, way.id)
        XCTAssertNil(coordinator.pendingHonorWay)
    }

    func testStartHonorParksTheWayAndClosesTheOverview() throws {
        let coordinator = MainCoordinator()
        let way = try makeWay()
        coordinator.openOverview(for: way)

        coordinator.startHonor(way: way)

        XCTAssertNil(coordinator.honorOverviewWay)
        XCTAssertEqual(coordinator.pendingStartWay?.id, way.id)
        XCTAssertNil(coordinator.activeWalkViewModel, "the walk must wait for the overview to finish closing")
    }

    func testHandleOverviewDismissStartsTheHonorWalk() throws {
        let coordinator = MainCoordinator()
        // Registered before the XCTUnwrap below can throw, so a failed
        // unwrap still cancels any walk the coordinator started rather than
        // leaking a live view model into the rest of the suite.
        addTeardownBlock { coordinator.cancelWalk() }
        let way = try makeWay()
        coordinator.openOverview(for: way)
        coordinator.startHonor(way: way)

        coordinator.handleOverviewDismiss()

        let vm = try XCTUnwrap(coordinator.activeWalkViewModel)
        XCTAssertEqual(vm.mode, .honor)
        XCTAssertEqual(vm.way?.id, way.id)
        XCTAssertNil(coordinator.pendingStartWay)
    }

    func testHandleOverviewDismissWithNothingParkedStartsNoWalk() {
        let coordinator = MainCoordinator()
        addTeardownBlock { coordinator.cancelWalk() }

        coordinator.handleOverviewDismiss()

        XCTAssertNil(coordinator.activeWalkViewModel)
    }

    func testOpenWayWhileWalkingSetsTheToast() throws {
        let coordinator = MainCoordinator()
        addTeardownBlock { coordinator.cancelWalk() }
        coordinator.startWalk()
        _ = try XCTUnwrap(coordinator.activeWalkViewModel, "the guard under test only means something with a walk running")

        coordinator.openWay(shareId: "Qoi4YmPHLN")

        XCTAssertEqual(coordinator.pendingLinkToast, "finish this walk first")
        XCTAssertEqual(coordinator.honorImportState, .idle, "no import may start underneath a walk")
    }

    func testOpenOverviewOverASummarySheetParksInsteadOfPresenting() throws {
        let coordinator = MainCoordinator()
        let way = try makeWay()
        coordinator.completedSnapshot = makeWalk()

        coordinator.openOverview(for: way)

        XCTAssertNil(coordinator.honorOverviewWay, "an overview presented over the summary sheet would never appear")
        XCTAssertEqual(coordinator.pendingHonorWay?.id, way.id)

        coordinator.completedSnapshot = nil
        coordinator.handleSummaryDismiss()
        XCTAssertEqual(coordinator.honorOverviewWay?.id, way.id, "the summary's dismiss promotes the park")
    }

    // MARK: - Import races (C4)

    /// Holds an import open so a spec can decide what happens between the
    /// tap and the resolution.
    private func heldImport(_ way: Way) -> (fetch: (String) async throws -> Way, release: () -> Void) {
        let gate = AsyncGate()
        return ({ _ in
            await gate.wait()
            return way
        }, { gate.open() })
    }

    @MainActor
    func testImportResolvingAfterBeginPresentsNoOverview() async throws {
        let coordinator = MainCoordinator()
        addTeardownBlock { coordinator.cancelWalk() }
        let way = try makeWay()
        let held = heldImport(way)
        coordinator.importShare = held.fetch

        coordinator.openWay(shareId: "Qoi4YmPHLN")
        // Begin lands while the fetch is still in the air.
        coordinator.startHonor(way: way)
        held.release()
        await coordinator.waitForImport()

        XCTAssertNil(coordinator.honorOverviewWay, "a Begin already in flight wins the sheet")
        XCTAssertNil(coordinator.pendingHonorWay)
        XCTAssertEqual(coordinator.honorImportState, .idle)
    }

    @MainActor
    func testImportResolvingDuringAWalkPresentsNoOverview() async throws {
        let coordinator = MainCoordinator()
        addTeardownBlock { coordinator.cancelWalk() }
        let way = try makeWay()
        let held = heldImport(way)
        coordinator.importShare = held.fetch

        coordinator.openWay(shareId: "Qoi4YmPHLN")
        coordinator.startWalk()
        _ = try XCTUnwrap(coordinator.activeWalkViewModel)
        held.release()
        await coordinator.waitForImport()

        XCTAssertNil(coordinator.honorOverviewWay, "nothing interrupts a walk already under way")
        XCTAssertNil(coordinator.pendingHonorWay)
    }

    @MainActor
    func testGatherForAWayNoLongerShowingInstallsNoSink() async throws {
        let coordinator = MainCoordinator()
        let way = try makeWay()

        // Control: while the Way is the one showing, the hop resolves the
        // state — which proves the settle budget below is enough to have run.
        coordinator.honorOverviewWay = way
        coordinator.gather(way)
        await settle()
        XCTAssertEqual(coordinator.honorImportState, .ready, "an own-walk Way carries its media already")

        coordinator.honorImportState = .idle
        coordinator.honorOverviewWay = nil
        coordinator.gather(way)
        await settle()

        XCTAssertEqual(coordinator.honorImportState, .idle,
                       "a gather for a Way that is no longer showing must leave the state alone")
    }

    /// Lets the coordinator's `Task { @MainActor … }` hops run. Each spec
    /// using this carries a control assertion proving the budget suffices.
    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }

    func testWalkAgainParksTheWayBuiltFromTheWalk() throws {
        let coordinator = MainCoordinator()
        let uuid = UUID()

        coordinator.walkAgain(makeWalk(uuid: uuid))

        XCTAssertEqual(coordinator.pendingHonorWay?.id, "walk:\(uuid.uuidString)")
        XCTAssertNil(coordinator.honorOverviewWay, "the summary sheet is still closing")
    }
}

/// A one-shot gate: `wait()` suspends until `open()` is called, and returns
/// at once after. Lets a spec hold an async call open across other work
/// without a sleep or a wall-clock deadline.
private final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isOpen {
                lock.unlock()
                continuation.resume()
            } else {
                waiting.append(continuation)
                lock.unlock()
            }
        }
    }

    func open() {
        lock.lock()
        isOpen = true
        let pending = waiting
        waiting = []
        lock.unlock()
        pending.forEach { $0.resume() }
    }
}
