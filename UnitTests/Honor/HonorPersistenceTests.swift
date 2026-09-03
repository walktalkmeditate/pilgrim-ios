import XCTest
@testable import Pilgrim

final class HonorPersistenceTests: XCTestCase {

    func testEventRawValuesRoundTrip() {
        XCTAssertEqual(WalkEvent.EventType(rawValue: 5), .honorMode)
        XCTAssertEqual(WalkEvent.EventType(rawValue: 6), .honorArrival)
        XCTAssertEqual(WalkEvent.EventType.honorMode.rawValue, 5)
        XCTAssertEqual(WalkEvent.EventType.honorArrival.rawValue, 6)
        XCTAssertEqual(WalkEvent.EventType(rawValue: 99), .unknown)
    }

    func testReservedIconIsDisjointFromUserIcons() {
        let userIcons = WaypointChip.presets.map(\.icon) + ["mappin", SeekPersistence.arrivalWaypointIcon]
        XCTAssertFalse(userIcons.contains(HonorPersistence.arrivalWaypointIcon))
        let waypoint = TempWaypoint(uuid: nil, latitude: 0, longitude: 0, label: "x",
                                    icon: HonorPersistence.arrivalWaypointIcon, timestamp: Date())
        XCTAssertTrue(HonorPersistence.isArrivalWaypoint(waypoint))
        XCTAssertFalse(SeekPersistence.isArrivalWaypoint(waypoint))
    }

    func testArrivalLabelCarriesTheWayTitle() {
        XCTAssertEqual(HonorPersistence.arrivalWaypointLabel(wayTitle: "Rúa do Franco → Obradoiro"),
                       "Walked their way: Rúa do Franco → Obradoiro")
    }

    func testPilgrimPackageEventStringsRoundTrip() {
        XCTAssertEqual(PilgrimPackageConverter.workoutEventTypeString(.honorMode), "honorMode")
        XCTAssertEqual(PilgrimPackageConverter.walkEventType(from: "honorArrival"), .honorArrival)
    }
}
