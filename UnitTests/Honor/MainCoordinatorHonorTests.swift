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

    func testWalkAgainParksTheWayBuiltFromTheWalk() throws {
        let coordinator = MainCoordinator()
        let uuid = UUID()

        coordinator.walkAgain(makeWalk(uuid: uuid))

        XCTAssertEqual(coordinator.pendingHonorWay?.id, "walk:\(uuid.uuidString)")
        XCTAssertNil(coordinator.honorOverviewWay, "the summary sheet is still closing")
    }
}
