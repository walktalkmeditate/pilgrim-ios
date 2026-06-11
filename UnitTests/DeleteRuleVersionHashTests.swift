import XCTest
import CoreData
import CoreStore
@testable import Pilgrim

/// AF7 mechanism test: decides whether walk→child delete rules can be
/// `.cascade` WITHOUT a schema migration.
///
/// CoreData's entity version hash is documented to exclude relationship
/// delete rules, but the audit plan requires proof, not trust: a hash
/// shift would make every existing store "incompatible" at launch — the
/// exact disaster the zero-migration constraint forbids. The synthetic
/// probe pair below differs ONLY in `deleteRule` on the parent's to-many
/// side. If the hashes match and a store written with the nullify model
/// opens as compatible under the cascade model, the cascade mechanism is
/// safe for `PilgrimV7` (which carries no `versionLock`, so no lock-hash
/// check applies either).
///
/// Disposition (verified by these tests passing): the hash is unchanged →
/// `PilgrimV7.Walk`'s eight child relationships declare `.cascade` and the
/// delete transactions (`DataManager.deleteObject`,
/// `replaceWalksInTransaction`) rely on it instead of explicit child
/// deletion.
final class DeleteRuleVersionHashTests: XCTestCase {

    // MARK: - Synthetic probe schemas (differ only in deleteRule)

    private enum NullifyProbe {
        final class Parent: CoreStoreObject {
            let name = Value.Required<String>("name", initial: "")
            let children = Relationship.ToManyOrdered<Child>("children", inverse: { $0.parent })
        }
        final class Child: CoreStoreObject {
            let name = Value.Required<String>("name", initial: "")
            let parent = Relationship.ToOne<Parent>("parent")
        }
    }

    private enum CascadeProbe {
        final class Parent: CoreStoreObject {
            let name = Value.Required<String>("name", initial: "")
            let children = Relationship.ToManyOrdered<Child>("children", inverse: { $0.parent }, deleteRule: .cascade)
        }
        final class Child: CoreStoreObject {
            let name = Value.Required<String>("name", initial: "")
            let parent = Relationship.ToOne<Parent>("parent")
        }
    }

    private static let nullifySchema = CoreStoreSchema(
        modelVersion: "HashProbeNullify",
        entities: [
            Entity<NullifyProbe.Parent>("HashProbeParent"),
            Entity<NullifyProbe.Child>("HashProbeChild")
        ]
    )

    private static let cascadeSchema = CoreStoreSchema(
        modelVersion: "HashProbeCascade",
        entities: [
            Entity<CascadeProbe.Parent>("HashProbeParent"),
            Entity<CascadeProbe.Child>("HashProbeChild")
        ]
    )

    // MARK: - Mechanism proof

    func test_deleteRule_doesNotChangeEntityVersionHashes() {
        let nullifyHashes = Self.nullifySchema.rawModel().entityVersionHashesByName
        let cascadeHashes = Self.cascadeSchema.rawModel().entityVersionHashesByName

        XCTAssertEqual(nullifyHashes.keys.sorted(), cascadeHashes.keys.sorted())
        for (name, hash) in nullifyHashes {
            XCTAssertEqual(
                hash, cascadeHashes[name],
                "deleteRule changed the version hash of \(name) — cascade would force a migration"
            )
        }
    }

    func test_storeWrittenWithNullifyModel_isCompatibleWithCascadeModel() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("delete-rule-probe-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let storeURL = tempDir.appendingPathComponent("probe.sqlite")
        let coordinator = NSPersistentStoreCoordinator(
            managedObjectModel: Self.nullifySchema.rawModel()
        )
        try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: storeURL,
            options: nil
        )

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: storeURL,
            options: nil
        )

        XCTAssertTrue(
            Self.cascadeSchema.rawModel().isConfiguration(
                withName: nil,
                compatibleWithStoreMetadata: metadata
            ),
            "an existing store must open under the cascade model with no migration"
        )
    }

    // MARK: - Cascade behavior on the real PilgrimV7 schema

    private var stack: DataStack!

    override func setUpWithError() throws {
        try super.setUpWithError()
        stack = DataStack(PilgrimV7.schema)
        try stack.addStorageAndWait(InMemoryStore())
    }

    override func tearDownWithError() throws {
        stack = nil
        try super.tearDownWithError()
    }

    private func seedWalkWithAllChildTypes(uuid: UUID) throws {
        try stack.perform(synchronous: { transaction in
            let walk = transaction.create(Into<Walk>())
            walk._uuid .= uuid
            walk._workoutType .= .walking
            walk._startDate .= Date(timeIntervalSince1970: 1_700_000_000)
            walk._endDate .= Date(timeIntervalSince1970: 1_700_001_800)
            walk._distance .= 3200
            walk._activeDuration .= 1800
            walk._pauseDuration .= 0
            walk._talkDuration .= 0
            walk._meditateDuration .= 0
            walk._ascend .= 10
            walk._descend .= 8
            walk._isRace .= false
            walk._isUserModified .= false
            walk._finishedRecording .= true
            walk._dayIdentifier .= "20231115"

            let pause = transaction.create(Into<WalkPause>())
            pause._uuid .= UUID()
            pause._workout .= walk

            let walkEvent = transaction.create(Into<WalkEvent>())
            walkEvent._uuid .= UUID()
            walkEvent._workout .= walk

            let route = transaction.create(Into<RouteDataSample>())
            route._uuid .= UUID()
            route._workout .= walk

            let heartRate = transaction.create(Into<HeartRateDataSample>())
            heartRate._uuid .= UUID()
            heartRate._workout .= walk

            let recording = transaction.create(Into<VoiceRecording>())
            recording._uuid .= UUID()
            recording._fileRelativePath .= "Recordings/X/a.m4a"
            recording._workout .= walk

            let interval = transaction.create(Into<ActivityInterval>())
            interval._uuid .= UUID()
            interval._workout .= walk

            let waypoint = transaction.create(Into<Waypoint>())
            waypoint._uuid .= UUID()
            waypoint._workout .= walk

            let photo = transaction.create(Into<WalkPhoto>())
            photo._uuid .= UUID()
            photo._workout .= walk

            let event = transaction.create(Into<Event>())
            event._uuid .= UUID()
            event._title .= "Journey"
            event._workouts.value.append(walk)
        })
    }

    private func assertChildRowCounts(
        _ expected: Int,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(try stack.fetchCount(From<WalkPause>()), expected, "WalkPause: \(message)", file: file, line: line)
        XCTAssertEqual(try stack.fetchCount(From<WalkEvent>()), expected, "WalkEvent: \(message)", file: file, line: line)
        XCTAssertEqual(try stack.fetchCount(From<RouteDataSample>()), expected, "RouteDataSample: \(message)", file: file, line: line)
        XCTAssertEqual(try stack.fetchCount(From<HeartRateDataSample>()), expected, "HeartRateDataSample: \(message)", file: file, line: line)
        XCTAssertEqual(try stack.fetchCount(From<VoiceRecording>()), expected, "VoiceRecording: \(message)", file: file, line: line)
        XCTAssertEqual(try stack.fetchCount(From<ActivityInterval>()), expected, "ActivityInterval: \(message)", file: file, line: line)
        XCTAssertEqual(try stack.fetchCount(From<Waypoint>()), expected, "Waypoint: \(message)", file: file, line: line)
        XCTAssertEqual(try stack.fetchCount(From<WalkPhoto>()), expected, "WalkPhoto: \(message)", file: file, line: line)
    }

    func test_deleteWalk_cascadesAllChildRows_butSparesEvents() throws {
        let uuid = UUID()
        try seedWalkWithAllChildTypes(uuid: uuid)
        try assertChildRowCounts(1, "seed must create one row per child type")

        try stack.perform(synchronous: { transaction in
            if let walk = try transaction.fetchOne(From<Walk>().where(\._uuid == uuid)) {
                transaction.delete(walk)
            } else {
                XCTFail("seeded walk not found")
            }
        })

        try assertChildRowCounts(0, "deleting the walk must remove every child row")
        XCTAssertEqual(
            try stack.fetchCount(From<Event>()), 1,
            "journeys (Event) must survive walk deletion — nullify, not cascade"
        )
    }

    func test_replaceWalks_leavesNoOrphanedChildRows() throws {
        let uuid = UUID()
        try seedWalkWithAllChildTypes(uuid: uuid)

        let tended = WalkDataFactory.makeWalk(
            uuid: uuid,
            comment: "tended",
            routeData: [WalkDataFactory.makeRouteDataSample()],
            voiceRecordings: [WalkDataFactory.makeVoiceRecording()]
        )

        let done = expectation(description: "replaceWalks")
        DataManager.replaceWalks(objects: [tended], dataStack: stack) { success, _, _, replaced, _ in
            XCTAssertTrue(success)
            XCTAssertEqual(replaced, 1)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        XCTAssertEqual(
            try stack.fetchCount(From<RouteDataSample>()), 1,
            "only the tended walk's route sample may remain — the original's must not be orphaned"
        )
        XCTAssertEqual(
            try stack.fetchCount(From<VoiceRecording>()), 1,
            "only the tended walk's recording may remain — the original's must not be orphaned"
        )
        XCTAssertEqual(try stack.fetchCount(From<WalkPause>()), 0)
        XCTAssertEqual(try stack.fetchCount(From<WalkPhoto>()), 0)
        XCTAssertEqual(try stack.fetchCount(From<Waypoint>()), 0)
        XCTAssertEqual(try stack.fetchCount(From<HeartRateDataSample>()), 0)
        XCTAssertEqual(try stack.fetchCount(From<ActivityInterval>()), 0)
    }
}
