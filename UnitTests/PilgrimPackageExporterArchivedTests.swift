import XCTest
import CoreStore
@testable import Pilgrim

/// Tests for the archived-walk export path in `PilgrimPackageConverter` and
/// `PilgrimPackageBuilder`. Verifies that walks in `archivedWalkRegistry` are
/// emitted to `manifest.archived[]` and NOT as `walks/UUID.json` files, and
/// that non-archived walks continue to emit normally.
///
/// Note: `PilgrimPackageBuilder.build` uses `DataManager.dataStack` (the
/// global singleton) and cannot be driven with an injected stack. The tests
/// below exercise the converter-level helpers that implement the routing
/// decision — `buildArchivedEntry` and the updated `buildManifest` — directly.
/// This mirrors Task 4's precedent of testing what is reachable without a
/// live DataStack.
final class PilgrimPackageExporterArchivedTests: XCTestCase {

    private let startEpoch: Double = 1_700_000_000
    private let endEpoch: Double   = 1_700_001_800
    private let archivedAtEpoch: Double = 1_700_500_000

    override func setUp() {
        super.setUp()
        UserPreferences.archivedWalkRegistry.value = [:]
    }

    override func tearDown() {
        UserPreferences.archivedWalkRegistry.value = [:]
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeWalk(
        uuid: UUID,
        distance: Double = 3200,
        activeDuration: Double = 1800,
        talkDuration: Double = 120,
        meditateDuration: Double = 300,
        steps: Int? = 4500
    ) -> TempWalk {
        TempWalk(
            uuid: uuid,
            workoutType: .walking,
            distance: distance,
            steps: steps,
            startDate: Date(timeIntervalSince1970: startEpoch),
            endDate: Date(timeIntervalSince1970: endEpoch),
            burnedEnergy: nil,
            isRace: false,
            comment: "test intention",
            isUserModified: false,
            healthKitUUID: nil,
            finishedRecording: true,
            ascend: 10,
            descend: 8,
            activeDuration: activeDuration,
            pauseDuration: 0,
            dayIdentifier: "20231115",
            talkDuration: talkDuration,
            meditateDuration: meditateDuration,
            heartRates: [],
            routeData: [],
            pauses: [],
            workoutEvents: [],
            voiceRecordings: [],
            activityIntervals: [],
            favicon: "leaf"
        )
    }

    // MARK: - Test 1: Archived walk emits to manifest.archived[], not to walks[]

    /// Verifies that a walk whose UUID is in the registry:
    ///   - produces a `PilgrimArchivedWalk` entry with the correct id and archivedAt
    ///   - does NOT produce a `PilgrimWalk` JSON entry (builder checks entry != nil before converting)
    func testArchivedExportEmitsToManifestArchivedArray() throws {
        let uuid = UUID()
        UserPreferences.markWalkArchived(uuid: uuid, archivedAt: Date(timeIntervalSince1970: archivedAtEpoch))

        let walk = makeWalk(uuid: uuid)
        let registry = UserPreferences.archivedWalkRegistry.value

        let archivedEntry = PilgrimPackageConverter.buildArchivedEntry(walk: walk, registry: registry)
        XCTAssertNotNil(archivedEntry, "Walk in registry must produce an archived entry")

        let entry = try XCTUnwrap(archivedEntry)
        XCTAssertEqual(entry.id, uuid, "id must match walk UUID")
        XCTAssertEqual(entry.archivedAt, archivedAtEpoch, accuracy: 0.001,
                       "archivedAt must come from registry, not Date.now")
        XCTAssertEqual(entry.startDate, startEpoch, accuracy: 0.001)
        XCTAssertEqual(entry.endDate, endEpoch, accuracy: 0.001)

        // The builder skips convert() when buildArchivedEntry returns non-nil.
        // Verify the manifest carries the entry and no walk file entry.
        let manifest = PilgrimPackageConverter.buildManifest(
            walkCount: 0,
            events: [],
            archivedEntries: [entry]
        )
        XCTAssertEqual(manifest.walkCount, 0, "walkCount must be 0 — archived walk not counted as a file walk")
        XCTAssertEqual(manifest.archived?.count, 1, "manifest.archived must hold the one entry")
        XCTAssertEqual(manifest.archived?.first?.id, uuid)
    }

    // MARK: - Test 2: Non-archived walk emits to walks[], manifest.archived[] stays nil

    /// Control: walk NOT in registry gets a `PilgrimWalk` conversion and no archived entry.
    func testNonArchivedWalkExportEmitsToManifestWalksArray() throws {
        let uuid = UUID()
        let walk = makeWalk(uuid: uuid)
        let registry = UserPreferences.archivedWalkRegistry.value

        let archivedEntry = PilgrimPackageConverter.buildArchivedEntry(walk: walk, registry: registry)
        XCTAssertNil(archivedEntry, "Walk not in registry must produce no archived entry")

        let pilgrimWalk = PilgrimPackageConverter.convert(walk: walk, system: .tropical, celestialEnabled: false)
        XCTAssertNotNil(pilgrimWalk, "Non-archived walk must still emit as a PilgrimWalk")
        XCTAssertEqual(pilgrimWalk?.id, uuid)

        let manifest = PilgrimPackageConverter.buildManifest(
            walkCount: 1,
            events: [],
            archivedEntries: []
        )
        XCTAssertNil(manifest.archived, "manifest.archived must be nil when no archived walks exist")
        XCTAssertEqual(manifest.walkCount, 1)
    }

    // MARK: - Test 3: Roundtrip preserves archivedAt and excludes heavy-data keys

    /// Encodes an archived entry and verifies:
    ///   - archivedAt survives roundtrip exactly (uses registry value, not Date.now)
    ///   - the JSON object has ONLY the five expected top-level keys
    func testRoundtripPreservesArchivedAtAndExcludesHeavyData() throws {
        let uuid = UUID()
        UserPreferences.markWalkArchived(uuid: uuid, archivedAt: Date(timeIntervalSince1970: archivedAtEpoch))

        let walk = makeWalk(uuid: uuid, distance: 3200, activeDuration: 1800,
                             talkDuration: 120, meditateDuration: 300, steps: 4500)
        let registry = UserPreferences.archivedWalkRegistry.value

        let entry = try XCTUnwrap(PilgrimPackageConverter.buildArchivedEntry(walk: walk, registry: registry))

        XCTAssertEqual(entry.archivedAt, archivedAtEpoch, accuracy: 0.001,
                       "archivedAt must equal the registry epoch, not Date.now")
        XCTAssertEqual(entry.stats.distance, 3200, accuracy: 0.001)
        XCTAssertEqual(entry.stats.activeDuration, 1800, accuracy: 0.001)
        XCTAssertEqual(entry.stats.talkDuration, 120, accuracy: 0.001)
        XCTAssertEqual(entry.stats.meditateDuration, 300, accuracy: 0.001)
        XCTAssertEqual(entry.stats.steps, 4500)

        // Encode to JSON and verify ONLY the expected top-level keys are present.
        // This ensures no heavy-data fields (route, pauses, voiceRecordings, etc.) leak.
        let encoder = PilgrimDateCoding.makeEncoder()
        let entryData = try encoder.encode(entry)
        let dict = try XCTUnwrap(
            JSONSerialization.jsonObject(with: entryData) as? [String: Any]
        )
        let expectedKeys: Set<String> = ["id", "startDate", "endDate", "archivedAt", "stats"]
        XCTAssertEqual(Set(dict.keys), expectedKeys,
                       "archived entry must have exactly {id, startDate, endDate, archivedAt, stats}")
    }
}
