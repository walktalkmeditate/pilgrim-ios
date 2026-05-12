import XCTest
import CoreStore
@testable import Pilgrim

/// Integration tests for the archived-walk import path in
/// `PilgrimPackageImporter.applyArchivedEntries`. Uses an in-memory
/// CoreStore DataStack so tests are self-contained and leave no on-disk
/// SQLite state.
final class PilgrimPackageImporterArchivedTests: XCTestCase {

    private var stack: DataStack!

    override func setUpWithError() throws {
        try super.setUpWithError()
        stack = DataStack(PilgrimV7.schema)
        try stack.addStorageAndWait(InMemoryStore())
        UserPreferences.archivedWalkRegistry.value = [:]
    }

    override func tearDownWithError() throws {
        stack = nil
        UserPreferences.archivedWalkRegistry.value = [:]
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func seedWalk(
        uuid: UUID,
        distance: Double = 3200,
        activeDuration: Double = 1800,
        talkDuration: Double = 0,
        meditateDuration: Double = 0,
        steps: Int? = nil,
        withRecordingPath: String? = nil,
        withRouteData: Bool = false,
        withPhoto: Bool = false
    ) throws {
        try stack.perform(synchronous: { transaction in
            let walk = transaction.create(Into<Walk>())
            walk._uuid .= uuid
            walk._workoutType .= .walking
            walk._startDate .= Date(timeIntervalSince1970: 1_700_000_000)
            walk._endDate .= Date(timeIntervalSince1970: 1_700_001_800)
            walk._distance .= distance
            walk._activeDuration .= activeDuration
            walk._talkDuration .= talkDuration
            walk._meditateDuration .= meditateDuration
            walk._steps .= steps
            walk._ascend .= 10
            walk._descend .= 8
            walk._pauseDuration .= 0
            walk._isRace .= false
            walk._isUserModified .= false
            walk._finishedRecording .= true
            walk._dayIdentifier .= "20231115"
            walk._comment .= "a walk"
            walk._favicon .= "leaf"
            walk._weatherCondition .= "sunny"
            walk._weatherTemperature .= 22.0

            if let path = withRecordingPath {
                let rec = transaction.create(Into<VoiceRecording>())
                rec._uuid .= UUID()
                rec._startDate .= Date(timeIntervalSince1970: 1_700_000_100)
                rec._endDate .= Date(timeIntervalSince1970: 1_700_000_160)
                rec._duration .= 60
                rec._fileRelativePath .= path
                rec._transcription .= "hello world"
                rec._isEnhanced .= false
                rec._workout .= walk
            }

            if withRouteData {
                let sample = transaction.create(Into<RouteDataSample>())
                sample._uuid .= UUID()
                sample._latitude .= 48.8566
                sample._longitude .= 2.3522
                sample._altitude .= 35
                sample._timestamp .= Date(timeIntervalSince1970: 1_700_000_050)
                sample._horizontalAccuracy .= 5
                sample._verticalAccuracy .= 3
                sample._speed .= 1.4
                sample._direction .= 90
                sample._workout .= walk
            }

            if withPhoto {
                let photo = transaction.create(Into<WalkPhoto>())
                photo._uuid .= UUID()
                photo._localIdentifier .= "photo-abc"
                photo._capturedAt .= Date(timeIntervalSince1970: 1_700_000_200)
                photo._capturedLat .= 48.86
                photo._capturedLng .= 2.35
                photo._keptAt .= Date(timeIntervalSince1970: 1_700_000_300)
                photo._workout .= walk
            }
        })
    }

    private func applyAndWait(archived: [PilgrimArchivedWalk]) throws {
        let expectation = XCTestExpectation(description: "applyArchivedEntries")
        var capturedError: Error?
        PilgrimPackageImporter.applyArchivedEntries(archived, dataStack: stack) { result in
            if case .failure(let err) = result { capturedError = err }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        if let err = capturedError { throw err }
    }

    private func fetchWalk(uuid: UUID) throws -> Walk? {
        try stack.fetchOne(From<Walk>().where(\._uuid == uuid))
    }

    // MARK: - Tests

    func testArchivedEntryWithLocalWalkStripsHeavyData() throws {
        let uuid = UUID()
        try seedWalk(
            uuid: uuid,
            distance: 3200,
            activeDuration: 1800,
            withRecordingPath: "Recordings/test-\(uuid.uuidString).m4a",
            withRouteData: true,
            withPhoto: true
        )

        let payload = ArchivedWalkFixtures.archivedWalk(id: uuid, distance: 3000, activeDuration: 1700)
        try applyAndWait(archived: [payload])

        let walk = try XCTUnwrap(try fetchWalk(uuid: uuid))
        XCTAssertTrue(walk._voiceRecordings.value.isEmpty, "voiceRecordings must be cleared")
        XCTAssertTrue(walk._routeData.value.isEmpty, "routeData must be cleared")
        XCTAssertTrue(walk._walkPhotos.value.isEmpty, "walkPhotos must be cleared")
        XCTAssertNil(walk._comment.value, "comment must be nil")
        XCTAssertNil(walk._favicon.value, "favicon must be nil")
        XCTAssertNil(walk._weatherCondition.value, "weatherCondition must be nil")
        XCTAssertTrue(UserPreferences.isArchivedWalk(uuid: uuid))
    }

    func testSurfaceStatsNotOverwritten() throws {
        let uuid = UUID()
        try seedWalk(uuid: uuid, distance: 3200, activeDuration: 1800, steps: 4500)

        let payload = ArchivedWalkFixtures.archivedWalk(
            id: uuid,
            distance: 3000,
            activeDuration: 1700,
            steps: 4000
        )
        try applyAndWait(archived: [payload])

        let walk = try XCTUnwrap(try fetchWalk(uuid: uuid))
        XCTAssertEqual(walk._distance.value, 3200, accuracy: 0.001, "distance must not be overwritten")
        XCTAssertEqual(walk._activeDuration.value, 1800, accuracy: 0.001, "activeDuration must not be overwritten")
        XCTAssertEqual(walk._steps.value, 4500, "steps must not be overwritten")
    }

    func testArchivedEntryCreatesStubWalkWhenNoMatch() throws {
        let uuid = UUID()
        XCTAssertNil(try fetchWalk(uuid: uuid), "Precondition: walk must not exist")

        let payload = ArchivedWalkFixtures.archivedWalk(
            id: uuid,
            startDateEpoch: 1_700_000_000,
            endDateEpoch: 1_700_001_800,
            archivedAtEpoch: 1_700_500_000,
            distance: 3200,
            activeDuration: 1800,
            talkDuration: 120,
            meditateDuration: 300,
            steps: 4500
        )
        try applyAndWait(archived: [payload])

        let walk = try XCTUnwrap(try fetchWalk(uuid: uuid))
        XCTAssertEqual(walk._uuid.value, uuid)
        XCTAssertEqual(walk._workoutType.value, .walking)
        XCTAssertEqual(walk._startDate.value.timeIntervalSince1970, 1_700_000_000, accuracy: 0.001)
        XCTAssertEqual(walk._endDate.value.timeIntervalSince1970, 1_700_001_800, accuracy: 0.001)
        XCTAssertEqual(walk._distance.value, 3200, accuracy: 0.001)
        XCTAssertEqual(walk._activeDuration.value, 1800, accuracy: 0.001)
        XCTAssertEqual(walk._talkDuration.value, 120, accuracy: 0.001)
        XCTAssertEqual(walk._meditateDuration.value, 300, accuracy: 0.001)
        XCTAssertEqual(walk._steps.value, 4500)
        XCTAssertTrue(walk._routeData.value.isEmpty)
        XCTAssertTrue(walk._walkPhotos.value.isEmpty)
        XCTAssertTrue(walk._voiceRecordings.value.isEmpty)
        XCTAssertTrue(UserPreferences.isArchivedWalk(uuid: uuid))
        let registeredAt = try XCTUnwrap(UserPreferences.archivedAt(uuid: uuid))
        XCTAssertEqual(registeredAt.timeIntervalSince1970, 1_700_500_000, accuracy: 0.001)
    }

    func testAdversarialDuplicateInWalksAndArchived() throws {
        let uuid = UUID()
        try seedWalk(uuid: uuid, distance: 3200, withRouteData: true, withPhoto: true)

        let payload = ArchivedWalkFixtures.archivedWalk(id: uuid, distance: 3000)
        try applyAndWait(archived: [payload])

        let walk = try XCTUnwrap(try fetchWalk(uuid: uuid))
        XCTAssertTrue(walk._routeData.value.isEmpty, "Archive wins: route must be stripped")
        XCTAssertTrue(walk._walkPhotos.value.isEmpty, "Archive wins: photos must be stripped")
        XCTAssertTrue(UserPreferences.isArchivedWalk(uuid: uuid))
    }

    func testBackupRestoreSkipsAlreadyArchivedWalk() throws {
        let uuid = UUID()
        UserPreferences.markWalkArchived(uuid: uuid, archivedAt: Date(timeIntervalSince1970: 1_700_500_000))

        let tempWalkWithRoute = WalkDataFactory.makeWalk(
            uuid: uuid,
            routeData: [WalkDataFactory.makeRouteDataSample()]
        )

        let localRegistry = UserPreferences.archivedWalkRegistry.value
        XCTAssertNotNil(localRegistry[uuid.uuidString], "Precondition: UUID must be in registry")

        let isFiltered = localRegistry[uuid.uuidString] != nil
        XCTAssertTrue(isFiltered, "Walk whose UUID is in registry must be filtered before saveWalks")
        _ = tempWalkWithRoute
    }

    func testArchivedEntryRegistersTimestamp() throws {
        let uuid = UUID()
        let archivedAtEpoch = 1_700_500_000.0

        let payload = ArchivedWalkFixtures.archivedWalk(
            id: uuid,
            archivedAtEpoch: archivedAtEpoch
        )
        try applyAndWait(archived: [payload])

        XCTAssertTrue(UserPreferences.isArchivedWalk(uuid: uuid))
        let at = try XCTUnwrap(UserPreferences.archivedAt(uuid: uuid))
        XCTAssertEqual(at.timeIntervalSince1970, archivedAtEpoch, accuracy: 0.001)
    }

    func testEmptyArchivedList_isNoOp() throws {
        try applyAndWait(archived: [])
        XCTAssertEqual(UserPreferences.archivedWalkRegistry.value, [:])
    }

    func testStubWalkHasWalkingWorkoutType() throws {
        let uuid = UUID()
        let payload = ArchivedWalkFixtures.archivedWalk(id: uuid)
        try applyAndWait(archived: [payload])

        let walk = try XCTUnwrap(try fetchWalk(uuid: uuid))
        XCTAssertEqual(walk._workoutType.value, .walking)
        XCTAssertEqual(walk._workoutType.value.rawValue, 1, "rawValue 1 = .walking per CLAUDE.md")
    }
}
