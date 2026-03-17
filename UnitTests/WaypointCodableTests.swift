import XCTest
@testable import Pilgrim

final class WaypointCodableTests: XCTestCase {

    func testWaypoint_roundTrips() throws {
        let original = TempWaypoint(
            uuid: UUID(),
            latitude: 40.7128,
            longitude: -74.0060,
            label: "Peaceful",
            icon: "leaf",
            timestamp: Date()
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TempWaypoint.self, from: data)
        XCTAssertEqual(decoded.latitude, original.latitude)
        XCTAssertEqual(decoded.longitude, original.longitude)
        XCTAssertEqual(decoded.label, original.label)
        XCTAssertEqual(decoded.icon, original.icon)
    }

    func testWorkout_decodesWithoutWaypointsKey() throws {
        let workout = TempWalk(
            uuid: UUID(),
            workoutType: .walking,
            distance: 1000,
            steps: 1500,
            startDate: Date(),
            endDate: Date(),
            burnedEnergy: nil,
            isRace: false,
            comment: nil,
            isUserModified: false,
            healthKitUUID: nil,
            finishedRecording: true,
            ascend: 0,
            descend: 0,
            activeDuration: 600,
            pauseDuration: 0,
            dayIdentifier: "2024-06-15",
            heartRates: [],
            routeData: [],
            pauses: [],
            workoutEvents: []
        )

        let data = try JSONEncoder().encode(workout)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "_waypoints")
        let stripped = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(TempWalk.self, from: stripped)
        XCTAssertTrue(decoded.waypoints.isEmpty)
        XCTAssertEqual(decoded.distance, 1000)
    }

    func testWorkout_decodesWithWaypoints() throws {
        let waypoint = TempWaypoint(
            uuid: nil,
            latitude: 51.5,
            longitude: -0.12,
            label: "Beautiful",
            icon: "eye",
            timestamp: Date()
        )
        let workout = TempWalk(
            uuid: UUID(),
            workoutType: .walking,
            distance: 2000,
            steps: 3000,
            startDate: Date(),
            endDate: Date(),
            burnedEnergy: nil,
            isRace: false,
            comment: "Walk in peace",
            isUserModified: false,
            healthKitUUID: nil,
            finishedRecording: true,
            ascend: 10,
            descend: 5,
            activeDuration: 1200,
            pauseDuration: 0,
            dayIdentifier: "2024-06-15",
            heartRates: [],
            routeData: [],
            pauses: [],
            workoutEvents: [],
            waypoints: [waypoint]
        )

        let data = try JSONEncoder().encode(workout)
        let decoded = try JSONDecoder().decode(TempWalk.self, from: data)
        XCTAssertEqual(decoded.waypoints.count, 1)
        XCTAssertEqual(decoded.waypoints.first?.label, "Beautiful")
    }
}
