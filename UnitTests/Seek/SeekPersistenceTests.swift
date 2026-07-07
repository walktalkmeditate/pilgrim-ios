import XCTest
@testable import Pilgrim

final class SeekPersistenceTests: XCTestCase {

    // MARK: - EventType Raw Values

    func testEventType_seekRawValues_roundTrip() {
        XCTAssertEqual(WalkEvent.EventType(rawValue: 3), .seekMode)
        XCTAssertEqual(WalkEvent.EventType(rawValue: 4), .seekArrival)
        XCTAssertEqual(WalkEvent.EventType.seekMode.rawValue, 3)
        XCTAssertEqual(WalkEvent.EventType.seekArrival.rawValue, 4)
    }

    func testEventType_legacyRawValues_unchanged() {
        XCTAssertEqual(WalkEvent.EventType.lap.rawValue, 0)
        XCTAssertEqual(WalkEvent.EventType.marker.rawValue, 1)
        XCTAssertEqual(WalkEvent.EventType.segment.rawValue, 2)
        XCTAssertEqual(WalkEvent.EventType.unknown.rawValue, -1)
    }

    func testEventType_unknownRawValues_fallBackToUnknown() {
        XCTAssertEqual(WalkEvent.EventType(rawValue: 99), .unknown)
        XCTAssertEqual(WalkEvent.EventType(rawValue: 5), .unknown)
        XCTAssertEqual(WalkEvent.EventType(rawValue: -5), .unknown)
    }

    func testEventType_decodesFutureRawValue_asUnknown() throws {
        let decoded = try JSONDecoder().decode(WalkEvent.EventType.self, from: Data("99".utf8))
        XCTAssertEqual(decoded, .unknown)
    }

    // MARK: - WalkBuilder Events Channel

    func testBuilder_eventsAppearInFinalSnapshot() {
        let builder = WalkBuilder()
        settleCombineSchedulers()

        var snapshot: TempWalk?
        builder.onSnapshotCreated = { snapshot = $0 }

        builder.setStatus(.ready)
        builder.setStatus(.recording)
        builder.addWorkoutEvent(TempWalkEvent(uuid: nil, eventType: .seekMode, timestamp: Date()))
        builder.addWorkoutEvent(TempWalkEvent(uuid: nil, eventType: .seekArrival, timestamp: Date()))
        builder.setStatus(.ready)
        settleCombineSchedulers()

        XCTAssertEqual(snapshot?.workoutEvents.map(\.eventType), [.seekMode, .seekArrival])
    }

    func testBuilder_eventsAppearInCheckpointSnapshot() {
        let builder = WalkBuilder()
        settleCombineSchedulers()

        builder.setStatus(.ready)
        builder.setStatus(.recording)
        builder.addWorkoutEvent(TempWalkEvent(uuid: nil, eventType: .seekMode, timestamp: Date()))
        builder.addWorkoutEvent(TempWalkEvent(uuid: nil, eventType: .seekArrival, timestamp: Date()))

        let checkpoint = builder.createCheckpointSnapshot()

        XCTAssertEqual(checkpoint?.workoutEvents.map(\.eventType), [.seekMode, .seekArrival])
        XCTAssertEqual(checkpoint?.finishedRecording, false)
    }

    func testBuilder_eventsSurviveContinueFromSnapshot() {
        let builder = WalkBuilder()
        settleCombineSchedulers()

        var snapshot: TempWalk?
        builder.onSnapshotCreated = { snapshot = $0 }

        builder.setStatus(.ready)
        builder.setStatus(.recording)
        builder.addWorkoutEvent(TempWalkEvent(uuid: nil, eventType: .seekMode, timestamp: Date()))
        builder.setStatus(.ready)
        settleCombineSchedulers()

        guard let first = snapshot else {
            XCTFail("expected a snapshot from the first recording")
            return
        }

        builder.setStatus(.ready)
        builder.continueWalk(from: first)
        builder.addWorkoutEvent(TempWalkEvent(uuid: nil, eventType: .seekArrival, timestamp: Date()))

        var second: TempWalk?
        builder.onSnapshotCreated = { second = $0 }
        builder.setStatus(.ready)
        settleCombineSchedulers()

        XCTAssertEqual(second?.workoutEvents.map(\.eventType), [.seekMode, .seekArrival])
    }

    func testBuilder_eventsClearOnFreshReset() {
        let builder = WalkBuilder()
        settleCombineSchedulers()

        builder.setStatus(.ready)
        builder.setStatus(.recording)
        builder.addWorkoutEvent(TempWalkEvent(uuid: nil, eventType: .seekMode, timestamp: Date()))
        builder.setStatus(.ready)
        settleCombineSchedulers()

        builder.setStatus(.ready)
        builder.setStatus(.recording)
        let checkpoint = builder.createCheckpointSnapshot()

        XCTAssertEqual(checkpoint?.workoutEvents.count, 0)
    }

    // MARK: - Checkpoint JSON Round-Trip

    func testCheckpoint_roundTripsSeekEvents() throws {
        let walkUUID = UUID()
        let walk = WalkDataFactory.makeWalk(
            uuid: walkUUID,
            finishedRecording: false,
            workoutEvents: [
                WalkDataFactory.makeWorkoutEvent(eventType: .seekMode),
                WalkDataFactory.makeWorkoutEvent(eventType: .seekArrival)
            ]
        )
        let checkpoint = WalkCheckpoint(walkUUID: walkUUID, walk: walk)

        let data = try JSONEncoder().encode(checkpoint)
        let decoded = try JSONDecoder().decode(WalkCheckpoint.self, from: data)

        XCTAssertEqual(decoded.walkUUID, walkUUID)
        XCTAssertEqual(decoded.walk.workoutEvents.map(\.eventType), [.seekMode, .seekArrival])
    }

    func testCheckpoint_preSeekShape_stillDecodes() throws {
        // Pre-seek builds wrote `_workoutEvents: []` (the write path hardcoded
        // an empty array) and U3 adds no Codable fields, so a checkpoint with
        // no events is byte-identical in shape to a pre-seek file.
        let walkUUID = UUID()
        let walk = WalkDataFactory.makeWalk(uuid: walkUUID, finishedRecording: false)
        let data = try JSONEncoder().encode(WalkCheckpoint(walkUUID: walkUUID, walk: walk))

        let decoded = try JSONDecoder().decode(WalkCheckpoint.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, WalkCheckpoint.currentSchemaVersion)
        XCTAssertTrue(decoded.walk.workoutEvents.isEmpty)
    }

    // MARK: - .pilgrim Round-Trip

    func testPilgrimPackage_roundTripsSeekEventsAndArrivalIcon() throws {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let walk = WalkDataFactory.makeWalk(
            uuid: UUID(),
            workoutEvents: [
                TempWalkEvent(uuid: UUID(), eventType: .seekMode, timestamp: start),
                TempWalkEvent(uuid: UUID(), eventType: .seekArrival, timestamp: start.addingTimeInterval(600))
            ],
            waypoints: [TempWaypoint(
                uuid: UUID(),
                latitude: 48.8584,
                longitude: 2.2945,
                label: SeekPersistence.arrivalWaypointLabel(clearingOrdinal: 1),
                icon: SeekPersistence.arrivalWaypointIcon,
                timestamp: start.addingTimeInterval(600)
            )]
        )

        let exported = try XCTUnwrap(
            PilgrimPackageConverter.convert(walk: walk, system: .tropical, celestialEnabled: false)
        )
        XCTAssertEqual(exported.workoutEvents.map(\.type), ["seekMode", "seekArrival"])

        let data = try PilgrimDateCoding.makeEncoder().encode(exported)
        let reimported = try PilgrimDateCoding.makeDecoder().decode(PilgrimWalk.self, from: data)
        let restored = PilgrimPackageConverter.convertToTemp(walk: reimported)

        XCTAssertEqual(restored.workoutEvents.map(\.eventType), [.seekMode, .seekArrival])
        XCTAssertEqual(restored.waypoints.map(\.icon), [SeekPersistence.arrivalWaypointIcon])
        XCTAssertEqual(restored.waypoints.map(\.label), ["First clearing"])
    }

    // MARK: - Reserved Icon

    func testArrivalIcon_isDistinctFromUserPickableIcons() {
        var userIcons = Set(WaypointChip.presets.map(\.icon))
        // Custom-note icon hardcoded in WaypointMarkingSheet's Mark button.
        userIcons.insert("mappin")

        XCTAssertFalse(userIcons.contains(SeekPersistence.arrivalWaypointIcon))
    }

    func testIsArrivalWaypoint_matchesByIconOnly() {
        let arrival = TempWaypoint(
            uuid: nil, latitude: 0, longitude: 0,
            label: "anything", icon: SeekPersistence.arrivalWaypointIcon, timestamp: Date()
        )
        let user = TempWaypoint(
            uuid: nil, latitude: 0, longitude: 0,
            label: "First clearing", icon: "leaf", timestamp: Date()
        )

        XCTAssertTrue(SeekPersistence.isArrivalWaypoint(arrival))
        XCTAssertFalse(SeekPersistence.isArrivalWaypoint(user))
    }

    // MARK: - Arrival Labels

    func testArrivalWaypointLabel_ordinals() {
        XCTAssertEqual(SeekPersistence.arrivalWaypointLabel(clearingOrdinal: 1), "First clearing")
        XCTAssertEqual(SeekPersistence.arrivalWaypointLabel(clearingOrdinal: 2), "Second clearing")
        XCTAssertEqual(SeekPersistence.arrivalWaypointLabel(clearingOrdinal: 3), "Third clearing")
        XCTAssertEqual(SeekPersistence.arrivalWaypointLabel(clearingOrdinal: 4), "Clearing 4")
    }
}
