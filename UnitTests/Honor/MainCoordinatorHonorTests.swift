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

// MARK: - Stage links

extension MainCoordinatorHonorTests {

    private var frances: PilgrimageCatalogEntry {
        PilgrimageCatalogEntry(id: "camino-frances", name: "Camino Francés", names: [:], country: "ES",
                               region: "Europe", distanceKm: 780, tradition: "christian", stageCount: 33, bytes: 1_000)
    }

    private var catalog: PilgrimageCatalog { PilgrimageCatalog(release: "v1.12.0", routes: [frances]) }

    private func link(focus: Int?) -> HonorRouteLink {
        HonorRouteLink(entry: frances, release: "v1.12.0", focus: focus)
    }

    /// Everything `openStage` reads, answered without a package on disk or a
    /// network. The catalog load fails unless a spec says otherwise, so a
    /// spec that reaches it by accident shows up as a toast. `loadForces`
    /// records the `force` flag of every load, in order.
    private final class LoadLog {
        var forces: [Bool] = []
    }

    private func stub(_ coordinator: MainCoordinator, installed: String? = nil, way: Way? = nil,
                      cached: PilgrimageCatalog? = nil, log: LoadLog = LoadLog(),
                      load: @escaping @MainActor (_ force: Bool) async throws -> PilgrimageCatalog = { _ in throw PilgrimageError.catalogUnreachable }) {
        coordinator.installedRouteId = { installed }
        coordinator.loadStageWay = { $0 == "pilgrimage:camino-frances:13" ? way : nil }
        coordinator.cachedCatalog = { cached }
        coordinator.loadCatalog = { force in
            log.forces.append(force)
            return try await load(force)
        }
    }

    @MainActor
    func testStageLinkForAnInstalledStageOpensItsOverview() async throws {
        let coordinator = MainCoordinator()
        let way = try makeWay()
        stub(coordinator, installed: "camino-frances", way: way)

        coordinator.openStage(routeId: "camino-frances", index: 13)
        await coordinator.waitForImport()

        XCTAssertEqual(coordinator.honorOverviewWay?.id, way.id, "a downloaded stage never waits on the catalog")
        XCTAssertNil(coordinator.honorRouteLink)
        XCTAssertNil(coordinator.pendingLinkToast)
    }

    @MainActor
    func testStageLinkForARouteNotOnThePhoneOpensTheRouteFocused() async {
        let coordinator = MainCoordinator()
        stub(coordinator, cached: catalog)

        coordinator.openStage(routeId: "camino-frances", index: 13)
        await coordinator.waitForImport()

        XCTAssertEqual(coordinator.honorRouteLink, link(focus: 13))
        XCTAssertNil(coordinator.honorOverviewWay)
    }

    @MainActor
    func testStageLinkLoadsTheCatalogWhenNoneIsInHand() async {
        let coordinator = MainCoordinator()
        let gate = AsyncGate()
        let catalog = self.catalog
        stub(coordinator, load: { _ in
            await gate.wait()
            return catalog
        })

        coordinator.openStage(routeId: "camino-frances", index: 13)
        await settle()
        XCTAssertEqual(coordinator.pendingLinkToast, "reaching for the route…")

        gate.open()
        await coordinator.waitForImport()

        XCTAssertEqual(coordinator.honorRouteLink, link(focus: 13))
        XCTAssertNil(coordinator.pendingLinkToast)
    }

    @MainActor
    func testStageLinkForARouteEvenAFreshCatalogLacksSaysSo() async {
        let coordinator = MainCoordinator()
        let log = LoadLog()
        let empty = PilgrimageCatalog(release: "v1.12.0", routes: [])
        stub(coordinator, cached: empty, log: log, load: { _ in empty })

        coordinator.openStage(routeId: "camino-frances", index: 13)
        await coordinator.waitForImport()

        XCTAssertEqual(coordinator.pendingLinkToast, "this route isn't in Pilgrim yet")
        XCTAssertNil(coordinator.honorRouteLink)
        XCTAssertEqual(log.forces, [true], "one forced load, then the refusal")
    }

    @MainActor
    func testStageLinkForARouteAddedSinceTheCachedCatalogForcesOneLoad() async {
        let coordinator = MainCoordinator()
        let log = LoadLog()
        let fresh = catalog
        stub(coordinator, cached: PilgrimageCatalog(release: "v1.11.0", routes: []), log: log, load: { _ in fresh })

        coordinator.openStage(routeId: "camino-frances", index: 13)
        await coordinator.waitForImport()

        XCTAssertEqual(coordinator.honorRouteLink, link(focus: 13))
        XCTAssertEqual(log.forces, [true])
    }

    @MainActor
    func testStageLinkForARouteInTheCachedCatalogNeverLoads() async {
        let coordinator = MainCoordinator()
        let log = LoadLog()
        stub(coordinator, cached: catalog, log: log)

        coordinator.openStage(routeId: "camino-frances", index: 13)
        await coordinator.waitForImport()

        XCTAssertEqual(coordinator.honorRouteLink, link(focus: 13))
        XCTAssertEqual(log.forces, [])
    }

    @MainActor
    func testStageLinkWithNoCatalogInHandLoadsUnforcedThenForcesOnceIfTheRouteIsMissing() async {
        let coordinator = MainCoordinator()
        let log = LoadLog()
        let empty = PilgrimageCatalog(release: "v1.12.0", routes: [])
        stub(coordinator, log: log, load: { _ in empty })

        coordinator.openStage(routeId: "camino-frances", index: 13)
        await coordinator.waitForImport()

        XCTAssertEqual(coordinator.pendingLinkToast, "this route isn't in Pilgrim yet")
        XCTAssertEqual(log.forces, [false, true])
    }

    @MainActor
    func testStageLinkWithTheCatalogOutOfReachSaysSo() async {
        let coordinator = MainCoordinator()
        stub(coordinator)

        coordinator.openStage(routeId: "camino-frances", index: 13)
        await coordinator.waitForImport()

        XCTAssertEqual(coordinator.pendingLinkToast, PilgrimageCopy.line(for: .catalogUnreachable))
        XCTAssertNil(coordinator.honorRouteLink)
    }

    func testStageLinkWhileWalkingSetsTheToast() throws {
        let coordinator = MainCoordinator()
        addTeardownBlock { coordinator.cancelWalk() }
        coordinator.startWalk()
        _ = try XCTUnwrap(coordinator.activeWalkViewModel, "the guard under test only means something with a walk running")

        coordinator.openStage(routeId: "camino-frances", index: 13)

        XCTAssertEqual(coordinator.pendingLinkToast, "finish this walk first")
        XCTAssertNil(coordinator.honorRouteLink)
        XCTAssertNil(coordinator.pendingRouteLink)
    }

    @MainActor
    func testStageLinkOverTheWaysSheetParksUntilItCloses() async {
        let coordinator = MainCoordinator()
        stub(coordinator, cached: catalog)
        coordinator.chooseWay()

        coordinator.openStage(routeId: "camino-frances", index: 13)
        await coordinator.waitForImport()

        XCTAssertFalse(coordinator.honorWaysPresented)
        XCTAssertNil(coordinator.honorRouteLink, "the route sheet must wait for the Ways sheet to finish closing")
        XCTAssertEqual(coordinator.pendingRouteLink, link(focus: 13))

        coordinator.promotePendingHonorWay()

        XCTAssertEqual(coordinator.honorRouteLink, link(focus: 13))
        XCTAssertNil(coordinator.pendingRouteLink)
    }

    @MainActor
    func testStageLinkOverAnOverviewClosesItAndOpensOnDismiss() async throws {
        let coordinator = MainCoordinator()
        addTeardownBlock { coordinator.cancelWalk() }
        stub(coordinator, cached: catalog)
        coordinator.openOverview(for: try makeWay())

        coordinator.openStage(routeId: "camino-frances", index: 13)
        await coordinator.waitForImport()

        XCTAssertNil(coordinator.honorOverviewWay)
        XCTAssertNil(coordinator.honorRouteLink)
        XCTAssertEqual(coordinator.pendingRouteLink, link(focus: 13))

        coordinator.handleOverviewDismiss()

        XCTAssertEqual(coordinator.honorRouteLink, link(focus: 13))
        XCTAssertNil(coordinator.activeWalkViewModel)
    }

    @MainActor
    func testABeginInFlightWinsOverAStageLink() async throws {
        let coordinator = MainCoordinator()
        addTeardownBlock { coordinator.cancelWalk() }
        stub(coordinator, cached: catalog)
        let way = try makeWay()
        coordinator.openOverview(for: way)
        coordinator.startHonor(way: way)

        coordinator.openStage(routeId: "camino-frances", index: 13)
        await coordinator.waitForImport()

        XCTAssertNil(coordinator.honorRouteLink)
        XCTAssertNil(coordinator.pendingRouteLink)
        XCTAssertEqual(coordinator.pendingStartWay?.id, way.id)
    }

    func testChoosingAStageInsideTheRouteSheetParksTheWay() throws {
        let coordinator = MainCoordinator()
        let way = try makeWay()
        coordinator.honorRouteLink = link(focus: 13)

        coordinator.openOverview(for: way)

        XCTAssertNil(coordinator.honorRouteLink)
        XCTAssertNil(coordinator.honorOverviewWay, "the overview must wait for the route sheet to finish closing")
        XCTAssertEqual(coordinator.pendingHonorWay?.id, way.id)

        coordinator.promotePendingHonorWay()

        XCTAssertEqual(coordinator.honorOverviewWay?.id, way.id)
    }

    func testASecondStageLinkSwapsTheOpenRouteSheet() {
        let coordinator = MainCoordinator()
        coordinator.honorRouteLink = link(focus: 13)

        coordinator.openRouteLink(link(focus: 19))

        XCTAssertEqual(coordinator.honorRouteLink, link(focus: 19))
        XCTAssertNil(coordinator.pendingRouteLink)
    }

    @MainActor
    func testStageLinkCancelsAShareImportInFlight() async throws {
        let coordinator = MainCoordinator()
        let held = heldImport(try makeWay())
        coordinator.importShare = held.fetch
        stub(coordinator, cached: catalog)

        coordinator.openWay(shareId: "Qoi4YmPHLN")
        XCTAssertEqual(coordinator.honorImportState, .fetching)
        coordinator.openStage(routeId: "camino-frances", index: 13)
        await coordinator.waitForImport()
        held.release()
        await settle()

        XCTAssertEqual(coordinator.honorImportState, .idle)
        XCTAssertEqual(coordinator.honorRouteLink, link(focus: 13))
        XCTAssertNil(coordinator.honorOverviewWay, "the cancelled share import must land nothing")
    }

    @MainActor
    func testStageLinkOverASummaryParksUntilItCloses() async {
        let coordinator = MainCoordinator()
        stub(coordinator, cached: catalog)
        coordinator.completedSnapshot = makeWalk()

        coordinator.openStage(routeId: "camino-frances", index: 13)
        await coordinator.waitForImport()

        XCTAssertNil(coordinator.honorRouteLink, "a route sheet over the summary would never appear")
        XCTAssertEqual(coordinator.pendingRouteLink, link(focus: 13))

        coordinator.completedSnapshot = nil
        coordinator.handleSummaryDismiss()

        XCTAssertEqual(coordinator.honorRouteLink, link(focus: 13))
    }

    @MainActor
    func testNewestLinkWinsOverAnOlderShareParkedBehindASummary() throws {
        let coordinator = MainCoordinator()
        let way = try makeWay()
        coordinator.completedSnapshot = makeWalk()
        coordinator.openOverview(for: way)

        coordinator.openRouteLink(link(focus: 13))
        coordinator.completedSnapshot = nil
        coordinator.handleSummaryDismiss()

        XCTAssertEqual(coordinator.honorRouteLink, link(focus: 13))
        XCTAssertNil(coordinator.honorOverviewWay)
        XCTAssertNil(coordinator.pendingHonorWay)
        XCTAssertNil(coordinator.pendingRouteLink)
    }

    func testAnOverviewRequestedWhileARouteLinkIsParkedIsNotStranded() throws {
        let coordinator = MainCoordinator()
        let first = try makeWay()
        let second = try makeWay()
        coordinator.openOverview(for: first)
        coordinator.openRouteLink(link(focus: 13))

        coordinator.openOverview(for: second)
        coordinator.handleOverviewDismiss()

        XCTAssertEqual(coordinator.honorOverviewWay?.id, second.id)
        XCTAssertNil(coordinator.pendingHonorWay)
        XCTAssertNil(coordinator.pendingRouteLink)
    }

    func testAnOverviewItemSwapDoesNotPromoteAParkedRouteLink() throws {
        let coordinator = MainCoordinator()
        coordinator.openOverview(for: try makeWay())
        coordinator.openOverview(for: try makeWay())
        coordinator.pendingRouteLink = link(focus: 13)

        coordinator.handleOverviewDismiss()

        XCTAssertNil(coordinator.honorRouteLink, "the incoming overview is showing; a route sheet now would stack")
        XCTAssertNotNil(coordinator.honorOverviewWay)
    }

    func testWalkAgainOnAWalkTooShortToBuildKeepsAParkedRouteLink() {
        let coordinator = MainCoordinator()
        coordinator.completedSnapshot = makeWalk()
        coordinator.openRouteLink(link(focus: 13))
        let tooShort = WalkDataFactory.makeWalk(uuid: UUID(), startDate: start,
                                                endDate: start.addingTimeInterval(180), routeData: [])

        coordinator.walkAgain(tooShort)

        XCTAssertEqual(coordinator.pendingRouteLink, link(focus: 13))
        XCTAssertNil(coordinator.pendingHonorWay)
    }

    func testAWayParkedBehindAWalkAgainOverviewIsNotStranded() throws {
        let coordinator = MainCoordinator()
        let shared = try makeWay()
        coordinator.completedSnapshot = makeWalk()
        coordinator.openRouteLink(link(focus: 13))
        coordinator.walkAgain(makeWalk())
        coordinator.completedSnapshot = nil
        coordinator.handleSummaryDismiss()
        XCTAssertNotNil(coordinator.honorOverviewWay)
        XCTAssertNil(coordinator.pendingRouteLink, "walking again is the newest request")

        coordinator.openOverview(for: shared)
        coordinator.handleOverviewDismiss()

        XCTAssertEqual(coordinator.honorOverviewWay?.id, shared.id)
        XCTAssertNil(coordinator.pendingHonorWay)
        XCTAssertNil(coordinator.pendingRouteLink)
    }

    func testBeginClearsAWayParkedBehindTheOverview() throws {
        let coordinator = MainCoordinator()
        addTeardownBlock { coordinator.cancelWalk() }
        let way = try makeWay()
        coordinator.openOverview(for: way)
        coordinator.pendingHonorWay = try makeWay()
        coordinator.pendingRouteLink = link(focus: 13)

        coordinator.startHonor(way: way)
        coordinator.handleOverviewDismiss()

        XCTAssertNotNil(coordinator.activeWalkViewModel)
        XCTAssertNil(coordinator.pendingHonorWay)
        XCTAssertNil(coordinator.pendingRouteLink)
    }

    @MainActor
    func testAStageLinkReplacedBeforeItsTaskRunsLandsNothing() async throws {
        let coordinator = MainCoordinator()
        let held = heldImport(try makeWay())
        coordinator.importShare = held.fetch
        stub(coordinator, cached: catalog)

        coordinator.openStage(routeId: "camino-frances", index: 13)
        coordinator.openWay(shareId: "Qoi4YmPHLN")
        await settle()

        XCTAssertNil(coordinator.honorRouteLink)
        XCTAssertNil(coordinator.pendingRouteLink)
        held.release()
        await settle()
    }

    func testNewestLinkWinsWhileTheWaysSheetIsStillClosing() throws {
        let coordinator = MainCoordinator()
        let way = try makeWay()
        coordinator.chooseWay()
        coordinator.openRouteLink(link(focus: 13))

        coordinator.openOverview(for: way)
        coordinator.promotePendingHonorWay()

        XCTAssertEqual(coordinator.honorOverviewWay?.id, way.id)
        XCTAssertNil(coordinator.honorRouteLink, "the older route link must not stack on the newer overview")
        XCTAssertNil(coordinator.pendingRouteLink)
    }

    @MainActor
    func testACancelledStageLinkLandsNothing() async {
        let coordinator = MainCoordinator()
        let gate = AsyncGate()
        let catalog = self.catalog
        stub(coordinator, load: { _ in
            await gate.wait()
            return catalog
        })

        coordinator.importShare = { _ in throw WayError.unavailable }
        coordinator.openStage(routeId: "camino-frances", index: 13)
        await settle()
        coordinator.openWay(shareId: "Qoi4YmPHLN")
        gate.open()
        await settle()

        XCTAssertNil(coordinator.honorRouteLink, "the replaced stage link must land nothing")
        XCTAssertNil(coordinator.pendingRouteLink)
    }

    func testAnUnrecognisedLinkSaysANewerPilgrimIsNeeded() {
        let coordinator = MainCoordinator()

        coordinator.open(.unrecognised)

        XCTAssertEqual(coordinator.pendingLinkToast, "this link needs a newer Pilgrim")
        XCTAssertNil(coordinator.honorRouteLink)
        XCTAssertEqual(coordinator.honorImportState, .idle)
    }

    @MainActor
    func testAStageDestinationOpensTheStage() async {
        let coordinator = MainCoordinator()
        stub(coordinator, cached: catalog)

        coordinator.open(.stage(routeId: "camino-frances", index: 13))
        await coordinator.waitForImport()

        XCTAssertEqual(coordinator.honorRouteLink, link(focus: 13))
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
