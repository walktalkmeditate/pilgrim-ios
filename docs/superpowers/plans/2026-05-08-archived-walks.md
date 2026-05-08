# Archived Walks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add iOS support for `manifest.archived[]` entries in `.pilgrim` files — strip heavy data (route, photos, audio, transcripts) on import while keeping surface stats, render archived walks as ghost dots in the journey thread, and emit them back to `manifest.archived[]` on re-export. No CoreStore schema migration; archive state lives in a UserDefaults sidecar mapping UUID → archivedAt epoch.

**Architecture:** UUID-keyed sidecar registry (`UserPreferences.archivedWalkRegistry: [String: Double]`) tracks archived state with the timestamp the schema requires for round-trip-stable export. Importer strips heavy CoreStore relationships in-transaction, then deletes audio files post-commit. Exporter branches by registry membership. UI surfaces archive state via a hollow-ring `WalkDotView` variant and a degraded `expandCard` variant that hides irreproducible data and replaces the details button with a non-tappable "Released" footer.

**Tech Stack:** Swift · SwiftUI · Combine · CoreStore (PilgrimV7) · CocoaPods + SPM hybrid · XCTest. **No new dependencies. No schema migration.**

**Spec:** `docs/superpowers/specs/2026-05-08-archived-walks-design.md`

**Branch:** continue on `feat/constellation-mode-and-edit-link` (1.6.0 rolling)

**Project structure note (recap from constellation plan):** the `Pilgrim/` and `UnitTests/` groups are NOT synchronized — new files require explicit `Pilgrim.xcodeproj/project.pbxproj` wiring via the `xcodeproj` ruby gem. Existing helper pattern from earlier tasks:

```bash
ruby -rxcodeproj -e '
project = Xcodeproj::Project.open("Pilgrim.xcodeproj")
target = project.targets.find { |t| t.name == "<TARGET>" }
group = project.main_group.find_subpath("<GROUP_PATH>", false)
existing = group.files.find { |f| f.path == "<FILE_NAME>" }
unless existing
  ref = group.new_reference("<FILE_NAME>")
  target.source_build_phase.add_file_reference(ref)
  project.save
  puts "Added"
end
'
```

---

## File Structure

### Create

| Path | Responsibility |
|---|---|
| `UnitTests/UserPreferencesArchivedTests.swift` | Sidecar registry round-trip, idempotency, race-free concurrent mark |
| `UnitTests/PilgrimPackageImporterArchivedTests.swift` | Import paths: existing-walk strip, stub-walk creation, adversarial-duplicate, backup-restore-skip, surface-stats-non-overwrite |
| `UnitTests/PilgrimPackageExporterArchivedTests.swift` | Export paths: archived → manifest.archived[], non-archived → manifest.walks[], roundtrip with archivedAt stability |
| `UnitTests/ArchivedWalkPrivacyTests.swift` | Programmatic privacy AC: no audio files for UUID after import, routeData == nil |
| `UnitTests/Helpers/ArchivedWalkFixtures.swift` | Reusable `.pilgrim` test fixtures (full walk, archived-only, mixed, adversarial duplicate) |

### Modify

| Path | Change |
|---|---|
| `Pilgrim/Models/Preferences/UserPreferences.swift` | Add `archivedWalkRegistry: UserPreference.Required<[String: Double]>` + helper extension methods |
| `Pilgrim/Models/Data/PilgrimPackage/PilgrimPackageModels.swift` | Add `PilgrimArchivedWalk` struct + `archived: [PilgrimArchivedWalk]?` field on `PilgrimManifest` (optional for back-compat) |
| `Pilgrim/Models/Data/PilgrimPackage/PilgrimPackageImporter.swift` | Branch on `manifest.archived[]`, strip heavy data for matching walks, create stubs for shadows, mark registry post-commit, delete audio files post-commit |
| `Pilgrim/Models/Data/PilgrimPackage/PilgrimPackageBuilder.swift` | Snapshot registry, route walks to `archived[]` when UUID is present, emit degraded payload |
| `Pilgrim/Scenes/Home/WalkDotView.swift` | Add `isArchived: Bool` parameter; hollow-ring rendering branch |
| `Pilgrim/Scenes/Home/InkScrollView.swift` | Pass `isArchived` from registry lookup; degraded `expandCard` variant; replace details button with "Released" footer |
| `Pilgrim/Scenes/Goshuin/GoshuinShareRenderer.swift` | Filter archived walks from `selectSeals`; keep them in `computeStats` |
| `Pilgrim/Scenes/Goshuin/GoshuinMilestones.swift` | Early-return `[]` when input UUID is in registry |
| `Pilgrim/AppDelegate.swift` | Call `OrphanRecordingSweep.run()` on launch |

### Create (sweep helper)

| Path | Responsibility |
|---|---|
| `Pilgrim/Models/Data/OrphanRecordingSweep.swift` | One-time per-launch cleanup of audio files whose owning walk's `voiceRecordings` no longer reference them |

---

## Phase 1 — Sidecar Registry

### Task 1: Add `archivedWalkRegistry` UserPreference + helpers

**Files:**
- Modify: `Pilgrim/Models/Preferences/UserPreferences.swift`
- Create: `UnitTests/UserPreferencesArchivedTests.swift`

- [ ] **Step 1: Write failing tests**

Create `UnitTests/UserPreferencesArchivedTests.swift`:

```swift
import XCTest
@testable import Pilgrim

final class UserPreferencesArchivedTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        UserPreferences.archivedWalkRegistry.value = [:]
    }

    func testIsArchivedWalk_returnsFalseForUnknownUUID() {
        let uuid = UUID()
        XCTAssertFalse(UserPreferences.isArchivedWalk(uuid: uuid))
    }

    func testMarkWalkArchived_persistsUUIDAndTimestamp() {
        let uuid = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        UserPreferences.markWalkArchived(uuid: uuid, archivedAt: date)
        XCTAssertTrue(UserPreferences.isArchivedWalk(uuid: uuid))
        XCTAssertEqual(
            UserPreferences.archivedAt(uuid: uuid)?.timeIntervalSince1970,
            1_700_000_000,
            accuracy: 0.001
        )
    }

    func testUnmarkWalkArchived_removesFromRegistry() {
        let uuid = UUID()
        UserPreferences.markWalkArchived(uuid: uuid, archivedAt: Date())
        UserPreferences.unmarkWalkArchived(uuid: uuid)
        XCTAssertFalse(UserPreferences.isArchivedWalk(uuid: uuid))
        XCTAssertNil(UserPreferences.archivedAt(uuid: uuid))
    }

    func testMarkWalkArchived_idempotentUpdatesTimestamp() {
        let uuid = UUID()
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        let second = Date(timeIntervalSince1970: 1_700_000_500)
        UserPreferences.markWalkArchived(uuid: uuid, archivedAt: first)
        UserPreferences.markWalkArchived(uuid: uuid, archivedAt: second)
        XCTAssertEqual(
            UserPreferences.archivedAt(uuid: uuid)?.timeIntervalSince1970,
            1_700_000_500,
            accuracy: 0.001
        )
        // No duplicate entries:
        XCTAssertEqual(UserPreferences.archivedWalkRegistry.value.count, 1)
    }

    /// Validates that 10 concurrent `markWalkArchived` calls all land
    /// without a lost-update race. Concurrent READS via
    /// `isArchivedWalk` are not explicitly tested here — they go
    /// through `UserDefaults.dictionary(forKey:)` which is per-key
    /// atomic at the UserDefaults layer (an in-flight write doesn't
    /// tear the read; the reader either sees the pre-write or
    /// post-write dictionary, never a half-written one).
    /// (serialized writes + per-key-atomic reads) is sufficient for
    /// the registry's actual access pattern (writes from import
    /// flows, reads from anywhere).
    func testConcurrentMarks_raceFree() {
        let uuids = (0..<10).map { _ in UUID() }
        let date = Date()

        DispatchQueue.concurrentPerform(iterations: 10) { i in
            UserPreferences.markWalkArchived(uuid: uuids[i], archivedAt: date)
        }

        XCTAssertEqual(UserPreferences.archivedWalkRegistry.value.count, 10)
        for uuid in uuids {
            XCTAssertTrue(UserPreferences.isArchivedWalk(uuid: uuid))
        }
    }

    func testEmptyRegistry_isDefaultValue() {
        XCTAssertEqual(UserPreferences.archivedWalkRegistry.value, [:])
    }
}
```

- [ ] **Step 2: Run test command (expect compile failure)**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnitTests/UserPreferencesArchivedTests
```

Expected: build fails — `archivedWalkRegistry`, `isArchivedWalk`, `archivedAt`, `markWalkArchived`, `unmarkWalkArchived` all undefined.

- [ ] **Step 3: Add registry pref**

In `Pilgrim/Models/Preferences/UserPreferences.swift`, add inside `struct UserPreferences { ... }` near the `appearanceMode` declaration:

```swift
    /// UUID string → archivedAt (epoch seconds). Stores walks the user has
    /// archived via the pilgrim-viewer/edit web app; iOS strips heavy data
    /// for these walks and emits them to manifest.archived[] on export.
    /// Empty default. Mutate only via the helpers below — direct .value
    /// assignment from user code is not race-safe.
    static let archivedWalkRegistry = UserPreference.Required<[String: Double]>(
        key: "archivedWalkRegistry",
        defaultValue: [:]
    )
```

- [ ] **Step 4: Add helper extension**

Append to `Pilgrim/Models/Preferences/UserPreferences.swift` (outside the `struct` body, at file scope):

```swift
extension UserPreferences {

    /// Serializes registry mutations. Reads are lock-free (UserDefaults is
    /// per-key atomic); only the read-modify-write needs the queue.
    private static let archivedRegistryQueue = DispatchQueue(
        label: "org.walktalkmeditate.pilgrim.archivedRegistry"
    )

    static func isArchivedWalk(uuid: UUID) -> Bool {
        archivedWalkRegistry.value[uuid.uuidString] != nil
    }

    static func archivedAt(uuid: UUID) -> Date? {
        guard let epoch = archivedWalkRegistry.value[uuid.uuidString] else {
            return nil
        }
        return Date(timeIntervalSince1970: epoch)
    }

    static func markWalkArchived(uuid: UUID, archivedAt: Date) {
        archivedRegistryQueue.sync {
            var registry = archivedWalkRegistry.value
            registry[uuid.uuidString] = archivedAt.timeIntervalSince1970
            archivedWalkRegistry.value = registry
        }
    }

    static func unmarkWalkArchived(uuid: UUID) {
        archivedRegistryQueue.sync {
            var registry = archivedWalkRegistry.value
            registry.removeValue(forKey: uuid.uuidString)
            archivedWalkRegistry.value = registry
        }
    }
}
```

- [ ] **Step 5: Add test file to UnitTests target**

```bash
ruby -rxcodeproj -e '
project = Xcodeproj::Project.open("Pilgrim.xcodeproj")
target = project.targets.find { |t| t.name == "UnitTests" }
group = project.main_group.find_subpath("UnitTests", false)
existing = group.files.find { |f| f.path == "UserPreferencesArchivedTests.swift" }
unless existing
  ref = group.new_reference("UserPreferencesArchivedTests.swift")
  target.source_build_phase.add_file_reference(ref)
  project.save
  puts "Added"
end
'
```

- [ ] **Step 6: Re-run tests**

Same command as Step 2.
Expected: 6/6 tests pass.

- [ ] **Step 7: Commit**

```bash
git add Pilgrim/Models/Preferences/UserPreferences.swift UnitTests/UserPreferencesArchivedTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(prefs): add archivedWalkRegistry sidecar with helpers"
```

---

## Phase 2 — Manifest Schema

### Task 2: Add `PilgrimArchivedWalk` struct + manifest field

**Files:**
- Modify: `Pilgrim/Models/Data/PilgrimPackage/PilgrimPackageModels.swift`

- [ ] **Step 1: Author the new struct + manifest field**

In `Pilgrim/Models/Data/PilgrimPackage/PilgrimPackageModels.swift`, after the existing `struct PilgrimEvent` and before the `// MARK: - Walk` section, add:

```swift
// MARK: - Archived Walk

/// Degraded shadow of a walk the user archived in the pilgrim-viewer/edit
/// web app. Surface stats only — no GPS, photos, audio, or transcripts.
/// Schema must match `interface ArchivedWalk` in
/// `pilgrim-viewer/src/parsers/types.ts` exactly. All numbers are epoch
/// seconds where a date is meant.
struct PilgrimArchivedWalk: Codable {
    let id: UUID
    let startDate: Double      // epoch seconds
    let endDate: Double        // epoch seconds
    let archivedAt: Double     // epoch seconds
    let stats: Stats

    struct Stats: Codable {
        let distance: Double           // meters
        let activeDuration: Double     // seconds
        let talkDuration: Double       // seconds
        let meditateDuration: Double   // seconds
        let steps: Int?
    }
}
```

Then update `PilgrimManifest`:

```swift
struct PilgrimManifest: Codable {
    let schemaVersion: String
    let exportDate: Date
    let appVersion: String
    let walkCount: Int
    let preferences: PilgrimPreferences
    let customPromptStyles: [PilgrimCustomPromptStyle]
    let intentions: [String]
    let events: [PilgrimEvent]
    let archived: [PilgrimArchivedWalk]?    // optional for back-compat

    // Convenience accessor — older `.pilgrim` files without an `archived`
    // field decode as nil; treat as empty.
    var archivedOrEmpty: [PilgrimArchivedWalk] {
        archived ?? []
    }
}
```

**Critical:** the new field is **optional** (`[PilgrimArchivedWalk]?`) with a default-empty accessor. Older `.pilgrim` files written before this change MUST continue to decode without error. Codable's default behavior treats missing optional fields as `nil`, which preserves back-compat.

- [ ] **Step 2: Build to verify**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Pilgrim/Models/Data/PilgrimPackage/PilgrimPackageModels.swift
git commit -m "feat(pilgrim-package): add PilgrimArchivedWalk model"
```

---

## Phase 3 — Test Fixtures

### Task 3: Create reusable `.pilgrim` test fixtures

**Files:**
- Create: `UnitTests/Helpers/ArchivedWalkFixtures.swift`

This file is a centralized fixture builder so subsequent test tasks don't duplicate setup boilerplate.

- [ ] **Step 1: Author the fixture helper**

Create `UnitTests/Helpers/ArchivedWalkFixtures.swift`:

```swift
import Foundation
@testable import Pilgrim

enum ArchivedWalkFixtures {

    /// Build a manifest with the given walks/archived entries. Other
    /// required fields take harmless defaults so tests don't have to
    /// fill in irrelevant fixture noise.
    static func manifest(
        walks: [PilgrimWalk] = [],
        archived: [PilgrimArchivedWalk] = []
    ) -> PilgrimManifest {
        PilgrimManifest(
            schemaVersion: "v6",
            exportDate: Date(timeIntervalSince1970: 1_700_000_000),
            appVersion: "1.6.0",
            walkCount: walks.count,
            preferences: PilgrimPreferences(
                distanceUnit: "km",
                altitudeUnit: "m",
                speedUnit: "min/km",
                energyUnit: "kcal",
                celestialAwareness: true,
                zodiacSystem: "tropical",
                beginWithIntention: false
            ),
            customPromptStyles: [],
            intentions: [],
            events: [],
            archived: archived
        )
    }

    static func archivedWalk(
        id: UUID = UUID(),
        startDateEpoch: Double = 1_700_000_000,
        endDateEpoch: Double = 1_700_001_800,
        archivedAtEpoch: Double = 1_700_500_000,
        distance: Double = 3200,
        activeDuration: Double = 1800,
        talkDuration: Double = 0,
        meditateDuration: Double = 0,
        steps: Int? = nil
    ) -> PilgrimArchivedWalk {
        PilgrimArchivedWalk(
            id: id,
            startDate: startDateEpoch,
            endDate: endDateEpoch,
            archivedAt: archivedAtEpoch,
            stats: .init(
                distance: distance,
                activeDuration: activeDuration,
                talkDuration: talkDuration,
                meditateDuration: meditateDuration,
                steps: steps
            )
        )
    }

    /// Encode a manifest + (optional) walks JSON the way the importer
    /// expects to find it inside an unzipped `.pilgrim` archive.
    static func encodeManifest(_ manifest: PilgrimManifest) throws -> Data {
        try PilgrimDateCoding.makeEncoder().encode(manifest)
    }
}
```

- [ ] **Step 2: Wire into UnitTests target**

```bash
ruby -rxcodeproj -e '
project = Xcodeproj::Project.open("Pilgrim.xcodeproj")
target = project.targets.find { |t| t.name == "UnitTests" }

# Ensure the Helpers group exists (it should — earlier tests use it)
helpers = project.main_group.find_subpath("UnitTests/Helpers", false)
unless helpers
  unit = project.main_group.find_subpath("UnitTests", false)
  helpers = unit.new_group("Helpers", "Helpers")
end

existing = helpers.files.find { |f| f.path == "ArchivedWalkFixtures.swift" }
unless existing
  ref = helpers.new_reference("ArchivedWalkFixtures.swift")
  target.source_build_phase.add_file_reference(ref)
  project.save
  puts "Added"
end
'
```

- [ ] **Step 3: Build to verify**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add UnitTests/Helpers/ArchivedWalkFixtures.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "test(archived): add fixture helpers for archived-walk tests"
```

---

## Phase 4 — Importer

### Task 4: Importer reads `manifest.archived[]` and strips heavy data

**Files:**
- Modify: `Pilgrim/Models/Data/PilgrimPackage/PilgrimPackageImporter.swift`
- Create: `UnitTests/PilgrimPackageImporterArchivedTests.swift`
- Create: `UnitTests/ArchivedWalkPrivacyTests.swift`

This is the largest task. **Read `Pilgrim/Models/Data/PilgrimPackage/PilgrimPackageImporter.swift` end-to-end before starting** — the import pipeline has multiple steps and the archive logic must integrate correctly with them.

The implementer subagent should base its implementation on §4.3 of the spec (`docs/superpowers/specs/2026-05-08-archived-walks-design.md`):
- Step 2 (loop) runs INSIDE the existing CoreStore import transaction
- Strip relationships: `routeData = nil`, `photos`/`voiceRecordings`/`intentionEntries`/`lightReadings` cleared, `transcript = ""`, `notes = nil`
- Surface stats on existing walks are NOT overwritten by archived payload's stats
- Stub-walk creation for shadow archives uses the field defaults in §4.3.5 — **read that table carefully and apply each field**
- Step 3 (backup-restore policy): if a walk's UUID is in BOTH `manifest.walks[]` AND the local registry, the local archive wins (skip the full payload)
- Step 4 (commit): if commit fails, NOTHING is written to UserDefaults
- Step 5 (post-commit): mark registry, then delete audio files; file delete failure is logged but doesn't throw

**TDD sequence (write tests first, then implementation):**

- [ ] **Step 1: Write failing tests**

Create `UnitTests/PilgrimPackageImporterArchivedTests.swift` with the test cases enumerated in §8 of the spec — copy the test names exactly:

- `testArchivedEntryWithLocalWalkStripsHeavyData`
- `testAdversarialDuplicateInWalksAndArchived`
- `testBackupRestoreSkipsAlreadyArchivedWalk`
- `testArchivedEntryCreatesStubWalkWhenNoMatch`
- `testSurfaceStatsNotOverwritten`

For each test:
1. Use `ArchivedWalkFixtures.manifest(...)` and `ArchivedWalkFixtures.archivedWalk(...)` to build the input manifest.
2. For tests that require a pre-existing walk in CoreStore: seed it via `DataManager.dataStack.perform(asynchronous:)` in `setUp` (or a synchronous test helper) with route data, voice recordings, photos.
3. Invoke `PilgrimPackageImporter.import(...)` (or whatever the public entry point is — verify the actual function signature when reading the file).
4. Assert per spec §3 + §8.

Each test is ~30-50 lines. Do not omit any case from the list above.

Also create `UnitTests/ArchivedWalkPrivacyTests.swift` with:

```swift
import XCTest
@testable import Pilgrim

final class ArchivedWalkPrivacyTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        UserPreferences.archivedWalkRegistry.value = [:]
        // Reset CoreStore to a known state — use whatever helper
        // existing tests use; verify the pattern before relying on it.
    }

    /// AC §3 (privacy): after import, archived walk has no audio files
    /// on disk and no routeData in CoreStore.
    func testHeavyDataDeletionAfterImport() throws {
        // Arrange: seed a walk with route data + at least one voice recording
        let walkUUID = UUID()
        // ... seeding logic ...

        // Pre-condition: file exists
        let recordingsDir = /* DataManager's recordings directory URL */
        let preFiles = try FileManager.default.contentsOfDirectory(
            at: recordingsDir, includingPropertiesForKeys: nil
        )
        let preCountForUUID = preFiles.filter { $0.lastPathComponent.contains(walkUUID.uuidString) }.count
        XCTAssertGreaterThan(preCountForUUID, 0)

        // Act: import a manifest archiving this walk
        let manifest = ArchivedWalkFixtures.manifest(
            archived: [ArchivedWalkFixtures.archivedWalk(id: walkUUID)]
        )
        try PilgrimPackageImporter.applyArchivedEntries(from: manifest)
        // (or whichever import entry point applies the archived[] subset —
        //  verify when reading the importer)

        // Assert: file gone, walk's routeData nil
        let postFiles = try FileManager.default.contentsOfDirectory(
            at: recordingsDir, includingPropertiesForKeys: nil
        )
        let postCountForUUID = postFiles.filter { $0.lastPathComponent.contains(walkUUID.uuidString) }.count
        XCTAssertEqual(postCountForUUID, 0)

        let walk: Walk = try XCTUnwrap(
            try DataManager.dataStack.fetchOne(From<Walk>().where(\Walk.uuid == walkUUID))
        )
        XCTAssertNil(walk.routeData)
    }
}
```

The implementer should fill in the seeding/recordings-directory/import-entry-point details when reading the actual `DataManager` and `PilgrimPackageImporter` code — the spec doesn't fix these names because they need to match real code.

- [ ] **Step 2: Run tests (expect failure — feature not built yet)**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnitTests/PilgrimPackageImporterArchivedTests \
  -only-testing:UnitTests/ArchivedWalkPrivacyTests
```

Expected: build fails OR tests fail (importer doesn't yet handle `manifest.archived[]`).

- [ ] **Step 3: Implement importer changes**

In `Pilgrim/Models/Data/PilgrimPackage/PilgrimPackageImporter.swift`:

**Read the existing importer first.** The current flow (per code, not assumption):
- `unpackAndDecode(from: url)` unzips `.pilgrim` to a temp dir, decodes the manifest from `manifest.json`, walks from individual files in `walks/*.json`, returns `(walks: [TempWalk], events: [PilgrimEvent])`. `manifest` is NOT a container of walks — walks are separate file artifacts inside the archive.
- `saveData(walks:events:)` calls `DataManager.saveWalks(objects:)` which performs the CoreStore transaction.

The integration points are therefore:
1. **Extend `unpackAndDecode`** (or a new sibling helper) to also decode the manifest's `archived: [PilgrimArchivedWalk]?` field into a separate output. Return `(walks, events, archivedEntries)`.
2. **Snapshot the registry** at the start of `saveData(...)` (or wherever the orchestrator runs): `let localRegistry = UserPreferences.archivedWalkRegistry.value`.
3. **Backup-restore filter for walks:** before passing `walks` into `DataManager.saveWalks`, filter out any walk whose UUID is already in the local registry — those archived locally must NOT be restored from the file's `walks/` directory (per §4.3 step 3 of the spec). Log skipped UUIDs.
4. **Apply archived entries** in a CoreStore transaction (use the same async pattern `DataManager.saveWalks` uses internally — `DataManager.dataStack.perform(asynchronous:)` or equivalent). For each `PilgrimArchivedWalk`:
   - Lookup `Walk` by UUID using the project's existing fetch helpers.
   - If found: capture file URLs from the walk's voice-recording filenames BEFORE clearing the relationship; then clear `routeData = nil`, `photos`/`voiceRecordings`/`intentionEntries`/`lightReadings` relationships, `transcript = ""`, `notes = nil`. Surface stats (distance, durations, steps) are NOT overwritten.
   - If not found: create a stub `Walk` per §4.3.5 of the spec — read the table carefully and apply each default explicitly. The `_workoutType` rawValue 1 (`.walking`) per CLAUDE.md note is critical; the default isn't 0.
   - Append `(uuid, payload.archivedAt)` to a local `[(UUID, Date)]` map; append captured file URLs to a local `[URL]` array.
5. **Commit the transaction.** If commit throws, the in-memory map and URL list are discarded — the registry is NOT mutated and files are NOT deleted. Error propagates to the caller per `DataManager.deleteAll` rule (CLAUDE.md).
6. **Post-commit (only on success), on the orchestrator's main path:**
   a. For each `(uuid, archivedAt)` in the map, call `UserPreferences.markWalkArchived(uuid:, archivedAt:)`. The helper itself is serialized via its own queue.
   b. For each URL in the file array, delete via do/catch (NOT `try?` — we need the error for logging):

```swift
for url in capturedRecordingURLs {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        // File-deletion failure means the audio survived archive.
        // The walk is correctly archived in CoreStore + registry;
        // the orphan-recording sweep at next launch will catch this.
        // Log for diagnostic; do not throw.
        print("[ArchiveImport] Could not remove \(url.lastPathComponent): \(error)")
    }
}
```

**The exact existing-importer function signatures depend on what's in `PilgrimPackageImporter.swift` today.** The implementer should match the project's existing transaction patterns rather than improvise — read `unpackAndDecode`, `saveData`, and `DataManager.saveWalks` end-to-end before choosing the integration shape. If the existing structure makes any of the steps above awkward (e.g. `unpackAndDecode` is a single function without a clean place to add the archived-decoder hook), pick the smallest sensible refactor and document it in the commit message.

- [ ] **Step 4: Re-run tests**

Same command as Step 2.
Expected: all 6 tests pass.

- [ ] **Step 5: Run full test suite to catch regressions**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: TEST SUCCEEDED across the whole UnitTests target.

- [ ] **Step 6: Wire test files into UnitTests target**

```bash
ruby -rxcodeproj -e '
project = Xcodeproj::Project.open("Pilgrim.xcodeproj")
target = project.targets.find { |t| t.name == "UnitTests" }
group = project.main_group.find_subpath("UnitTests", false)
["PilgrimPackageImporterArchivedTests.swift", "ArchivedWalkPrivacyTests.swift"].each do |name|
  next if group.files.find { |f| f.path == name }
  ref = group.new_reference(name)
  target.source_build_phase.add_file_reference(ref)
end
project.save
puts "Done"
'
```

- [ ] **Step 7: Commit**

```bash
git add Pilgrim/Models/Data/PilgrimPackage/PilgrimPackageImporter.swift UnitTests/PilgrimPackageImporterArchivedTests.swift UnitTests/ArchivedWalkPrivacyTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(import): handle manifest.archived[] with strip + sidecar"
```

---

## Phase 5 — Exporter

### Task 5: Exporter routes archived walks to `manifest.archived[]`

**Files:**
- Modify: `Pilgrim/Models/Data/PilgrimPackage/PilgrimPackageBuilder.swift`
- Create: `UnitTests/PilgrimPackageExporterArchivedTests.swift`

- [ ] **Step 1: Write failing tests**

Create `UnitTests/PilgrimPackageExporterArchivedTests.swift` with the cases from §8 of the spec:

- `testArchivedExportEmitsToManifestArchivedArray` — given a Walk + UUID in registry with `archivedAt = T`, calling the exporter produces a manifest where the walk appears in `archived[]` with `archivedAt == T` and the walk does NOT appear in `walks[]`.
- `testNonArchivedWalkExportEmitsToManifestWalksArray` — control case (no UUIDs in registry → walk in `walks[]`).
- `testRoundtripPreservesArchivedAtAndExcludesHeavyData` — import a fixture archive entry, then re-export, then re-decode the manifest. Assert: `archivedAt` matches the original (no Date.now mutation), and the re-exported `archived[]` entry's keys are exactly `{id, startDate, endDate, archivedAt, stats}` — no leaked heavy-data keys (use a `Decodable` extra-keys assertion or decode into a strict struct that throws on unknown keys).

- [ ] **Step 2: Run tests (expect failure)**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnitTests/PilgrimPackageExporterArchivedTests
```

- [ ] **Step 3: Implement exporter changes**

In `Pilgrim/Models/Data/PilgrimPackage/PilgrimPackageBuilder.swift`:

1. Read the existing `buildPackage(...)` (or whichever public entry point exports walks to `.pilgrim`).
2. At the start of the export logic, snapshot `archivedRegistry = UserPreferences.archivedWalkRegistry.value`. Use this snapshot throughout the function so concurrent imports don't change behavior mid-build.
3. When iterating the user's walks to build the manifest:
   - **`Walk.uuid` is `UUID?` — use optional chaining throughout.** Check `guard let uuid = walk.uuid?.uuidString` once per iteration; skip walks with no UUID (these shouldn't exist in practice but defensive).
   - If `archivedRegistry[uuid]` is non-nil:
     - Build a `PilgrimArchivedWalk` from the walk + the registry's `archivedAt` (NOT `Date.now`)
     - Append to a new `archivedEntries: [PilgrimArchivedWalk]` array
     - **Do NOT** also write a `PilgrimWalk` JSON file for this walk to the `walks/` directory of the archive. The exporter currently emits one JSON file per walk into the unzipped `walks/` directory — archived walks must skip that emission entirely; their data lives only in `manifest.archived[]`.
   - Else: emit the walk via the existing `PilgrimWalk` path (current code path) — JSON file in `walks/`, no manifest entry.
4. When constructing the final `PilgrimManifest`, pass `archived: archivedEntries`.

- [ ] **Step 4: Re-run tests**

Expected: all 3 tests pass.

- [ ] **Step 5: Wire test file into UnitTests target**

```bash
ruby -rxcodeproj -e '
project = Xcodeproj::Project.open("Pilgrim.xcodeproj")
target = project.targets.find { |t| t.name == "UnitTests" }
group = project.main_group.find_subpath("UnitTests", false)
unless group.files.find { |f| f.path == "PilgrimPackageExporterArchivedTests.swift" }
  ref = group.new_reference("PilgrimPackageExporterArchivedTests.swift")
  target.source_build_phase.add_file_reference(ref)
  project.save
  puts "Added"
end
'
```

- [ ] **Step 6: Commit**

```bash
git add Pilgrim/Models/Data/PilgrimPackage/PilgrimPackageBuilder.swift UnitTests/PilgrimPackageExporterArchivedTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(export): route archived walks to manifest.archived[]"
```

---

## Phase 6 — Journey UI

### Task 6: Hollow-ring archived dot in `WalkDotView`

**Files:**
- Modify: `Pilgrim/Scenes/Home/WalkDotView.swift`

- [ ] **Step 1: Add `isArchived` parameter + branch rendering**

In `Pilgrim/Scenes/Home/WalkDotView.swift`, add a parameter `let isArchived: Bool` (default `false` so existing callers compile).

When `isArchived == true`, the body returns:

```swift
Circle()
    .stroke(Color.fog.opacity(0.5), lineWidth: 1)
    .frame(width: normalDiameter * 0.6, height: normalDiameter * 0.6)
    .frame(width: 44, height: 44)             // HIG-min hit target
    .contentShape(Circle())
    .onTapGesture { onTap(snapshot.id) }
```

Skip any twinkle/pulse/halo modifiers normal dots receive — archived dots are still.

The exact integration depends on the current dot rendering structure — read `WalkDotView` first, then choose the cleanest branch point (probably an `if isArchived { ... } else { existing dot ... }` inside the body).

- [ ] **Step 2: Build to verify**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED. (Existing call sites still compile because `isArchived` defaults to `false`.)

- [ ] **Step 3: Commit**

```bash
git add Pilgrim/Scenes/Home/WalkDotView.swift
git commit -m "feat(home): WalkDotView gains isArchived hollow-ring variant"
```

---

### Task 7: `InkScrollView` passes `isArchived` from registry + degraded `expandCard`

**Files:**
- Modify: `Pilgrim/Scenes/Home/InkScrollView.swift`

This is the biggest UI task. **Read the existing `expandCard` in `InkScrollView.swift` (around lines 300-400) end-to-end before modifying.**

- [ ] **Step 1: Pass `isArchived` from the dot's call-site**

Find where `WalkDotView(...)` is instantiated inside `InkScrollView.scrollContent(...)` (search for `WalkDotView(`). Add:

```swift
isArchived: UserPreferences.isArchivedWalk(uuid: snapshot.id)
```

to the constructor call.

- [ ] **Step 2: Add `isExpandedArchived` computed property**

In `InkScrollView`'s body type (struct or class), add:

```swift
private var isExpandedArchived: Bool {
    guard let snapshot = expandedSnapshot else { return false }
    return UserPreferences.isArchivedWalk(uuid: snapshot.id)
}
```

- [ ] **Step 3: Branch the `expandCard` rendering on `isExpandedArchived`**

Walk through `expandCard` per the table in spec §4.5. For each row of that table, either keep the normal rendering OR wrap in `if !isExpandedArchived`. The table's "Archived" column lists what to skip / replace.

Two new visual elements appear when `isExpandedArchived`:

1. **Released tag in top-right of the card header HStack:**

```swift
if isExpandedArchived {
    HStack(spacing: 4) {
        Image(systemName: "circle.dotted")
            .font(.system(size: 10))
        Text("Released")
            .font(Constants.Typography.caption)
    }
    .foregroundColor(.fog)
}
```

(Position: place inside the `HStack {...}` that already holds the date / sharing / celestial / weather row, after the existing trailing items.)

2. **Replace "View details →" button with non-tappable footer text:**

```swift
if isExpandedArchived {
    Text("Released — full record removed")
        .font(Constants.Typography.caption)
        .foregroundColor(.fog)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
} else {
    Button { /* existing logic */ } label: {
        Text("View details \(Image(systemName: "arrow.right"))")
            .font(Constants.Typography.annotation)
            .foregroundColor(.parchment)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.stone.opacity(0.8))
            .clipShape(Capsule())
    }
}
```

3. **Card-level ghost styling.** The expandCard's container modifiers should branch:

```swift
.background(
    RoundedRectangle(cornerRadius: 12)
        .fill(Color.parchmentSecondary.opacity(isExpandedArchived ? 0.5 : 1.0))
)
.overlay(
    RoundedRectangle(cornerRadius: 12)
        .strokeBorder(
            Color.fog.opacity(0.4),
            style: StrokeStyle(lineWidth: 1, dash: isExpandedArchived ? [4, 3] : [])
        )
        .opacity(isExpandedArchived ? 1 : 0)
)
```

Apply the dashed border only when archived; normal walks have no border (or whatever they had — preserve existing behavior).

4. **Footprint shape and stat color:**

- The header's footprint shape: when `isExpandedArchived`, render the same shape but stroked-only (no fill), `.fog` stroke. Existing code: `FootprintShape().fill(seasonColor.opacity(0.3))` becomes:

  ```swift
  if isExpandedArchived {
      FootprintShape()
          .stroke(Color.fog, lineWidth: 1)
          .frame(width: 12, height: 18)
  } else {
      FootprintShape()
          .fill(seasonColor.opacity(0.3))
          .frame(width: 12, height: 18)
  }
  ```

- The date Text's `.foregroundColor(.ink)` becomes `.foregroundColor(isExpandedArchived ? .fog : .ink)`.

5. **Activity bar:** wrap `miniActivityBar(snapshot: snapshot)` in `if !isExpandedArchived` — hidden for archived walks.

6. **Activity pills:** keep the existing `activityPills(snapshot: snapshot)` call. Internally those pills derive presence from durations; for archived walks the visual is naturally a flat presence indicator since the per-second sample data isn't there. Verify the pills component handles archived walks gracefully (no crash on missing per-second data); if it doesn't, add a parameter or an early branch.

- [ ] **Step 4: Build + smoke check on simulator**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -3
```

Boot simulator, install, and tap a walk dot. Confirm the normal expandCard still renders correctly (no archived walks seeded yet, so all dots are normal).

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Scenes/Home/InkScrollView.swift
git commit -m "feat(home): degraded expandCard for archived walks + isArchived dot"
```

---

## Phase 7 — Goshuin Filter

### Task 8: Exclude archived walks from seal selection + milestones

**Files:**
- Modify: `Pilgrim/Scenes/Goshuin/GoshuinShareRenderer.swift`
- Modify: `Pilgrim/Scenes/Goshuin/GoshuinMilestones.swift`

- [ ] **Step 1: Filter `selectSeals` input**

In `Pilgrim/Scenes/Goshuin/GoshuinShareRenderer.swift`, find `private static func selectSeals(from walks: ..., allWalks: ...)`. At the top of the function:

```swift
let archivedRegistry = UserPreferences.archivedWalkRegistry.value
let candidates = walks.filter { walk in
    guard let uuid = walk.uuid?.uuidString else { return true }
    return archivedRegistry[uuid] == nil
}
// existing logic, but iterating `candidates` instead of `walks`
```

`computeStats(walks: walks)` continues to use the unfiltered `walks` array — archived walks contribute to the count + total-distance line. Verify that's the case in the existing code path.

- [ ] **Step 2: Skip archived walks in milestone detection**

In `Pilgrim/Scenes/Goshuin/GoshuinMilestones.swift`, at the top of the public `detect(walkCount:walkIndex:input:allInputs:)` (or whatever the public function signature is — verify when reading), early-return:

```swift
if let uuid = input.uuid?.uuidString,
   UserPreferences.archivedWalkRegistry.value[uuid] != nil {
    return []
}
```

- [ ] **Step 3: Build to verify**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -3
```

- [ ] **Step 4: Commit**

```bash
git add Pilgrim/Scenes/Goshuin/GoshuinShareRenderer.swift Pilgrim/Scenes/Goshuin/GoshuinMilestones.swift
git commit -m "feat(goshuin): exclude archived walks from seal grid + milestones"
```

---

## Phase 8 — Orphan Recording Sweep

### Task 9: Add per-launch sweep for orphaned audio files

**Files:**
- Create: `Pilgrim/Models/Data/OrphanRecordingSweep.swift`
- Modify: `Pilgrim/AppDelegate.swift`

The post-commit file deletion in Task 4 can fail silently (file lock, low storage, permission). This sweep catches any orphan files — audio whose owning walk no longer references it — at next launch. Cheap (file listing, no content inspection).

- [ ] **Step 1: Author the sweep**

Create `Pilgrim/Models/Data/OrphanRecordingSweep.swift`:

```swift
import Foundation
import CoreStore

enum OrphanRecordingSweep {

    /// One-shot at app launch. Lists files in the recordings directory,
    /// matches each filename to the active set of walks' voiceRecording
    /// references, deletes any that don't match. Errors are logged but
    /// never thrown — this is best-effort cleanup.
    static func run() {
        // CoreStore fetches must run on its own context queue. Use the
        // async transaction API; the file enumeration / deletion can
        // happen on the same callback (off the main thread) once we
        // have the referenced-filename set.
        DataManager.dataStack.perform(asynchronous: { transaction in
            try collectReferencedFilenames(in: transaction)
        }, success: { referenced in
            sweepFiles(notMatching: referenced)
        }, failure: { error in
            print("[OrphanRecordingSweep] CoreStore fetch failed: \(error)")
        })
    }

    private static func collectReferencedFilenames(
        in transaction: AsynchronousDataTransaction
    ) throws -> Set<String> {
        var names: Set<String> = []
        let walks: [Walk] = try transaction.fetchAll(From<Walk>())
        for walk in walks {
            // Implementer: match this against the actual `Walk`
            // voiceRecordings relationship + recording-filename property
            // when reading PilgrimV7's Walk entity definition. The
            // accessor names below are placeholders.
            for recording in walk.voiceRecordings ?? [] {
                if let filename = recording.filename {
                    names.insert(filename)
                }
            }
        }
        return names
    }

    private static func sweepFiles(notMatching referenced: Set<String>) {
        // File I/O is safe off-context.
        let recordingsDir = recordingsDirectoryURL()
        let fm = FileManager.default

        guard fm.fileExists(atPath: recordingsDir.path) else { return }

        let allFiles: [URL]
        do {
            allFiles = try fm.contentsOfDirectory(
                at: recordingsDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            print("[OrphanRecordingSweep] could not list \(recordingsDir.path): \(error)")
            return
        }

        for file in allFiles where !referenced.contains(file.lastPathComponent) {
            do {
                try fm.removeItem(at: file)
                print("[OrphanRecordingSweep] removed orphan: \(file.lastPathComponent)")
            } catch {
                print("[OrphanRecordingSweep] could not remove \(file.lastPathComponent): \(error)")
            }
        }
    }

    /// Path to the app's recordings directory. **Implementer: match the
    /// existing `DataManager`'s recordings-cleanup helper** — don't
    /// reinvent the path. If `DataManager` exposes a helper, call it
    /// instead of duplicating the path-building logic.
    private static func recordingsDirectoryURL() -> URL {
        // Placeholder — replace with project's actual helper.
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("recordings")
    }
}
```

**CoreStore concurrency note:** `dataStack.fetchAll(...)` is NOT safe to call from arbitrary background queues. The `perform(asynchronous:)` API dispatches the closure onto CoreStore's own context queue and hands the result back via the success/failure callbacks. File I/O after that is queue-agnostic.

**Note for the implementer:** the placeholder helpers (`recordingsDirectoryURL`, the relationship accessors) need to match the project's actual `DataManager` helpers. Read `DataManager.swift` and the `Walk` entity definition before finalizing — using a path that doesn't match the real recordings directory would produce a no-op sweep (or worse, sweep the wrong directory).

- [ ] **Step 2: Wire into Pilgrim target + add launch hook**

```bash
ruby -rxcodeproj -e '
project = Xcodeproj::Project.open("Pilgrim.xcodeproj")
target = project.targets.find { |t| t.name == "Pilgrim" }
group = project.main_group.find_subpath("Pilgrim/Models/Data", false)
unless group.files.find { |f| f.path == "OrphanRecordingSweep.swift" }
  ref = group.new_reference("OrphanRecordingSweep.swift")
  target.source_build_phase.add_file_reference(ref)
  project.save
  puts "Added"
end
'
```

In `Pilgrim/AppDelegate.swift`, find the `application(_:didFinishLaunchingWithOptions:)` method. After the existing setup but before returning, add:

```swift
OrphanRecordingSweep.run()
```

- [ ] **Step 3: Build to verify**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -3
```

- [ ] **Step 4: Commit**

```bash
git add Pilgrim/Models/Data/OrphanRecordingSweep.swift Pilgrim/AppDelegate.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(import): orphan-recording sweep on app launch"
```

---

### Task 9b: Clean up `archivedWalkRegistry` when a walk is deleted

**Files:**
- Modify: `Pilgrim/Models/Data/DataManager.swift`

If a walk is permanently deleted from CoreStore (e.g. via the existing `DataManager.deleteAll()` flow or any future per-walk delete), its UUID must be removed from `archivedWalkRegistry` too. Otherwise the registry accumulates stale entries that:
- Can't be re-imported sensibly (the underlying walk is gone)
- Could falsely trigger archive behavior if the same UUID ever appeared again (UUID collisions are vanishingly rare in practice but still — clean state beats stale state)

- [ ] **Step 1: Find the walk-delete path**

Read `Pilgrim/Models/Data/DataManager.swift`. Locate `deleteAll()` and any per-walk delete helpers (search `delete(walk:` or similar).

- [ ] **Step 2: Add registry cleanup**

In `deleteAll()`, after the CoreStore transaction commits successfully, add:

```swift
UserPreferences.archivedWalkRegistry.value = [:]
```

Wipe the whole registry — `deleteAll` removes every walk, so every entry is now stale.

For per-walk delete helpers (if they exist), add right after the commit:

```swift
UserPreferences.unmarkWalkArchived(uuid: walkUUID)
```

If neither helper exists today, this step is a no-op for now. Note in the commit message that future per-walk delete code paths must call `unmarkWalkArchived` themselves.

- [ ] **Step 3: Build to verify**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -3
```

- [ ] **Step 4: Commit**

```bash
git add Pilgrim/Models/Data/DataManager.swift
git commit -m "fix(archived): wipe registry when walks are deleted"
```

---

## Phase 9 — Verify + Manual QA

### Task 10: Full test pass + manual visual QA

**No code changes** — this is the verification gate before declaring the feature done. Per the user's instruction, NO TestFlight dispatch from this plan; the user signals when ready.

- [ ] **Step 1: Run the full UnitTests target**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: TEST SUCCEEDED. All existing tests + 18 new tests pass.

- [ ] **Step 2: Manual visual QA — archived walk roundtrip**

Boot iPhone 17 Pro simulator. Install the build. In a separate browser tab, open `pilgrim-viewer/edit` and load a `.pilgrim` file with at least 5 walks. Use the editor to archive one walk, save the file. Re-import to iOS via Settings → Data → Import Data.

Confirm:
- The archived walk's dot in the Pilgrim Log (Journal tab → InkScrollView) renders as a hollow ring, smaller than normal dots, in `.fog` stroke
- Tapping the archived dot opens an expandCard with: ghost border, ghost-color text, `Released` tag in the header, no celestial/weather, no mini-activity-bar, "Released — full record removed" footer (NOT the View details button)
- All other walks render normally (no accidental ghost styling)
- Goshuin sheet (FAB) shows the right total walk count + total distance INCLUDING the archived walk; the seal grid does NOT pin the archived walk

- [ ] **Step 3: Manual visual QA — privacy gate**

Before importing the archive: note the walk's recordings (if any) by inspecting the simulator's app sandbox (Xcode → Devices → Pilgrim app → Download container, or `~/Library/Developer/CoreSimulator/Devices/<udid>/data/Containers/Data/Application/.../Documents/recordings`).

Import the archive. Confirm:
- The recordings directory no longer contains files for the archived walk's UUID
- A second app launch + the orphan sweep produces no errors in the console

- [ ] **Step 4: Manual visual QA — backup-restore-skip**

Take a backup `.pilgrim` BEFORE archiving the walk in the editor. Archive the walk in the editor and import that file to iOS (now the walk is archived locally). Then re-import the BACKUP file (which contains the walk's full data in `walks[]`).

Confirm:
- The walk stays archived (still hollow ring in the journal)
- The walk's routeData is still nil in CoreStore (use Xcode debug → CoreStore inspector or a quick fetch)
- Console shows a log line indicating the backup payload was skipped for the archived walk

- [ ] **Step 5: Document QA results in spec**

Append a `## 13. QA results` section to the spec at
`docs/superpowers/specs/2026-05-08-archived-walks-design.md` capturing
the date, simulator/device versions, and pass/fail of each step above.

- [ ] **Step 6: Commit QA log**

```bash
git add docs/superpowers/specs/2026-05-08-archived-walks-design.md
git commit -m "docs(archived): record manual QA results"
```

---

## Self-Review

### Spec coverage

| Spec section | Plan task |
|---|---|
| §2 In: importer | Task 4 |
| §2 In: exporter | Task 5 |
| §2 In: sidecar pref | Task 1 |
| §2 In: journey UI dots | Task 6, 7 |
| §2 In: degraded expandCard | Task 7 |
| §2 In: Goshuin filter | Task 8 |
| §3 AC: importer behavior | Task 4 (tests) |
| §3 AC: exporter behavior | Task 5 (tests) |
| §3 AC: surface-stats non-overwrite | Task 4 step 1 (testSurfaceStatsNotOverwritten) |
| §3 AC: privacy disk-size | Task 4 (ArchivedWalkPrivacyTests) + Task 10 step 3 |
| §3 AC: roundtrip archivedAt stable | Task 5 (testRoundtripPreservesArchivedAtAndExcludesHeavyData) |
| §3 AC: archived dots ghost styling | Task 6, 7 + Task 10 step 2 |
| §3 AC: Goshuin behavior | Task 8 + Task 10 step 2 |
| §4.1 sidecar storage | Task 1 |
| §4.2 schema (none) | (no task — spec correctly says no schema change) |
| §4.3 importer flow | Task 4 |
| §4.3.5 stub-walk defaults | Task 4 step 3 |
| §4.3.6 orphan sweep | Task 9 |
| Registry cleanup on walk deletion | Task 9b |
| §4.4 exporter flow | Task 5 |
| §4.5 expandCard variant | Task 7 |
| §4.6 dot styling + 44pt hit | Task 6 |
| §4.7 Goshuin filter | Task 8 |
| §5 resource safety | Task 4 step 3 (transaction discipline), Task 9 (sweep) |
| §6 privacy | Task 4 + ArchivedWalkPrivacyTests |
| §7 UI summary | Task 6, 7 |
| §8 testing | Tasks 1, 4, 5 (test files), Task 10 (manual QA) |
| §9 localization | (en hardcoded, no task — matches established pattern) |
| §11 open items 1, 2, 4, 5 | Verification gates in Task 10 manual QA |
| §11 open item 3 (backup-restore) | Resolved as option (b) in §4.3 step 3 + tested in Task 4 (testBackupRestoreSkipsAlreadyArchivedWalk) |

All spec sections mapped. Items 1, 2, 4, 5 in §11 are gated by Task 10 manual QA — they require fixture-or-device verification and aren't unit-testable.

### Placeholder scan

The plan contains placeholder language in two specific spots that the implementer needs to replace by reading actual code:

- **Task 4 Step 3** asks the implementer to "match the project's existing transaction patterns" rather than spelling out the exact CoreStore API. This is intentional — the project's existing importer pattern is the source of truth, and the plan can't predict the exact function signature without code-archaeology that would belong in a separate research task.
- **Task 9 Step 1** has explicit "implementer must replace placeholder helpers" comments for `recordingsDirectoryURL` and the relationship accessors, again because the real `DataManager` helpers are the source of truth.

These are flagged as intentional deferrals to the implementing subagent, not unspecified gaps.

### Type consistency

- `archivedWalkRegistry` — defined Task 1, used Tasks 4, 5, 7, 8
- `PilgrimArchivedWalk` — defined Task 2, used Tasks 4, 5
- `PilgrimManifest.archived` / `archivedOrEmpty` — defined Task 2, used Task 4
- `isArchivedWalk(uuid:)` — defined Task 1, used Tasks 7, 8
- `archivedAt(uuid:)` — defined Task 1, used Task 5
- `markWalkArchived(uuid:archivedAt:)` — defined Task 1, used Task 4
- `OrphanRecordingSweep.run()` — defined Task 9, called from `AppDelegate`

All names consistent across tasks.
