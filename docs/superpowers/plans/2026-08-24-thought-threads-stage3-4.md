# Thought Threads — Stage 3+4 Implementation Plan

> **Superseded (2026-08-24):** the card, thread history, releases, and lunation recap this plan shipped were removed the same day after real-device contact — see the Stage 3 field verdict in `docs/superpowers/specs/2026-08-22-thought-threads-design.md` and `docs/superpowers/plans/2026-08-24-threads-dossier-first.md`. The engine, dossier, and intention chips survive.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The engine earns its surfaces. Stage 3+4 ships the "What walked with you" card, the thread history view with excerpts and the origin map, "Let this one go" releases with a `.pilgrim` carve-out, the lunation recap with its walk-dated invitation, and flips the intention chips live — everything specified in `docs/superpowers/specs/2026-08-22-thought-threads-design.md` "### Stage 3 — card + thread view" and the whole "## Stage 3+4 addendum (2026-08-24)".

**Architecture:** All new logic lives as pure model builders in `Pilgrim/Models/Threads/` (testable without UI), with thin SwiftUI files in `Pilgrim/Scenes/WalkSummary/` and `Pilgrim/Scenes/Settings/`. `ThreadStore.build` gains a released-lemma filter parameter — the single choke point covering card, thread view, dossier trajectories, quiet-this-walk lines, intention chips, and the recap; `AttentionDirectives.recurringWord` gets the one bypass-path skip. The released set is a new UserDefaults-backed store with its own change token, cleared by Delete All Data, and round-tripped through the `.pilgrim` preferences block (the sanctioned carve-out); welcome-backs are recorded as decisions too, so import merge is latest-decision-wins per cohort and a stale backup can never silently override a walker's later reversal. Lunation machinery extends `LunarPhase`'s existing constants. Nothing touches the CoreStore schema, `SharePayload`, or the network.

**Tech Stack:** Swift, SwiftUI, CoreStore (reads only, existing helpers), CoreLocation (route-sample lookup + reverse geocoding), Mapbox via the existing `PilgrimMapView`, XCTest.

## Global Constraints

- iOS 18 minimum; no new dependencies; no CoreStore schema changes (`PilgrimV7` stays current). Frozen identifiers stay frozen: `_workout`, `"workout"`, `"Workout"` etc. are SQL names — never "fix" them.
- Nothing leaves the device. The released set's ONLY egress is the `.pilgrim` preferences block (spec: scoped carve-out, `zodiacSystem` precedent — the lemmas already appear verbatim in exported transcripts). `TranscriptContext`, `MarkerPack`, and `WalkThread` never appear in `Pilgrim/Models/Share/` or `Pilgrim/Models/Data/PilgrimPackage/`; `ReleasedThread`/`WelcomedBackThread` appear in `PilgrimPackage` only in the three sanctioned carve-out sites (models field, converter mapping, importer merge — the released list and the welcome-back list travel together so latest-decision-wins merge works across backups). Task 9's grep gates enforce exactly this.
- The journal is untouched — no file under any Journal scene changes in this plan.
- **No directional words in UI** ("rising", "fading", trend talk) and no metric digits in card/status copy. Ordinal words ("third walk now") and dates are fine. Digits are allowed ONLY where the spec sanctions them: the recap's "in N of M walks" counts, the recap headline's walks-with-recorded-words count ("3 walks with recorded words this moon" — scoped so it never reads as the journal's walk total disagreeing), and thread-view dates.
- `threadsAfterWalks` off means off everywhere: card, thread navigation, chips, recap invitation, and both settings rows all gate on it.
- Deterministic output everywhere: same inputs, same UI. Ties break by the existing `recurringWord` convention (highest count, then alphabetical).
- **pbxproj, the 4-entries lesson:** every new Swift file needs FOUR entries in `Pilgrim.xcodeproj/project.pbxproj` — a `PBXBuildFile`, a `PBXFileReference`, a children entry in the right `PBXGroup`, and a `PBXSourcesBuildPhase` entry in the right target (app files → `Pilgrim` target, test files → `UnitTests` target). Copy the entry pattern of a sibling file in the same group. A file missing any one of the four compiles on your machine and breaks the build for everyone else.
- Test command (per class): `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/<ClassName> 2>&1 | tail -20`
- **Suite reconciliation:** the pre-plan full-suite baseline is **1269** "Test Case '...' started" lines. After each task, the delta must equal the tests you added (count via `grep -c "Test Case '.*' started" <log>` — anchor on `started`; the unanchored form also matches the passed/failed lines and counts roughly double — or `xcrun xcresulttool`). A test file that silently never joined the target is exactly the failure mode this reconciliation catches.
- Comment policy: self-documenting code; comments only for constraints code can't show. SwiftLint errors at 750 lines/type and 100 lines/function (60 lines/function is only a warning) — keep new SwiftUI in focused files; WalkSummary additions go in a `WalkSummaryView+Threads.swift` extension (the `+Map.swift` pattern), with only `@State` declarations and one-line slots added to the main struct. `WalkSummaryView`'s main struct already sits ~669 lines against the 750 error ceiling: Tasks 3, 4, and 7 each run `swiftlint lint Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift` after touching it, so a crossing is caught in the task that caused it, not at Task 9.
- The custom `ProgressView` shadows SwiftUI's — qualify as `SwiftUI.ProgressView` if ever needed.
- Typography: `Constants.Typography.*` only. Spacing: `Constants.UI.Padding.*`. Colors: the wabi-sabi palette (ink, fog, moss, stone, parchment, dawn).
- CoreStore fetches assert main-thread: every `DataManager.*Index()`/`*Snapshot()` call happens on the main actor; detached tasks receive plain values.

---

### Task 1: ReleasedThreadsStore — the persisted released set

**Files:**
- Create: `Pilgrim/Models/Threads/ReleasedThreadsStore.swift`
- Modify: `Pilgrim/Models/Data/PilgrimPackage/PilgrimPackageModels.swift` (`PilgrimPreferences` gains an optional field + new `PilgrimReleasedThread` struct)
- Modify: `Pilgrim/Models/Data/PilgrimPackage/PilgrimPackageConverter.swift` (`buildManifest` export + `releasedThreads(from:)` import mapping)
- Modify: `Pilgrim/Models/Data/PilgrimPackage/PilgrimPackageImporter.swift` (`DecodedPackage` field + merge on import success)
- Modify: `Pilgrim/Models/Data/DataManager.swift` (seam + `deleteAll` clearing hook)
- Test: `UnitTests/ReleasedThreadsStoreTests.swift`, `UnitTests/ReleasedThreadsPackageTests.swift`, extend `UnitTests/DataManagerThreadsDeletionTests.swift`, extend `UnitTests/PilgrimPackageExporterArchivedTests.swift` (setUp clear only — the new buildManifest defaults read the test host's standard defaults)

**Interfaces:**
- Consumes: `UserDefaults`, `PilgrimDateCoding` (existing `.secondsSince1970` manifest coding), `DataManager.deleteAll` success path (DataManager.swift:842-859), `PilgrimPackageImporter.importPackage` success hook (PilgrimPackageImporter.swift:84-92).
- Produces (used by Tasks 2, 3, 5, 7):
  - `struct ReleasedThread: Codable, Equatable` — `{ displayTerm: String, lemmas: [String], releasedAt: Date }`
  - `struct WelcomedBackThread: Codable, Equatable` — `{ displayTerm: String, welcomedBackAt: Date }` (a welcome-back is a decision too — recorded so import merge can apply latest-decision-wins; this is what makes the spec's reversibility promise survive backups)
  - `final class ReleasedThreadsStore` — `static let shared`; `init(defaults: UserDefaults)`; `var changeCount: Int` (session memo token, bumps on every mutation); `var all: [ReleasedThread]` (releasedAt-descending, term-ascending); `var welcomedBack: [WelcomedBackThread]` (term-ascending, for export); `var releasedLemmas: Set<String>`; `var isEmpty: Bool` (released list only — the settings row keys off it); `func release(displayTerm:lemmas:releasedAt:)` (merges cohorts for an already-released term, clears the term's welcome-back record); `func welcomeBack(displayTerm:at:)` (removes the cohort atomically, records the decision with its date); `func merge(released:welcomedBack:)` (import merge, latest decision wins per cohort — an imported release older than a local welcome-back does NOT re-release, and vice versa; two releases union lemmas keeping the earlier date so repeated imports stay stable); `func clear()` (Delete All hook, clears both lists)
  - `struct PilgrimReleasedThread: Codable` — `{ term: String, lemmas: [String], releasedAt: Date }`
  - `struct PilgrimWelcomedBackThread: Codable` — `{ term: String, welcomedBackAt: Date }`
  - `PilgrimPreferences.releasedThreads: [PilgrimReleasedThread]?` + `PilgrimPreferences.welcomedBackThreads: [PilgrimWelcomedBackThread]?` (nil-defaulted init parameters — every existing construction site compiles unchanged; old `.pilgrim` files decode nil; old importers ignore the unknown keys)
  - `PilgrimPackageConverter.releasedThreads(from: PilgrimPreferences) -> [ReleasedThread]` + `.welcomedBackThreads(from:) -> [WelcomedBackThread]`
  - `DecodedPackage.releasedThreads: [ReleasedThread]` + `.welcomedBackThreads: [WelcomedBackThread]`
  - `DataManager.releasedThreadsStore: ReleasedThreadsStore` (test seam, defaults `.shared`)

- [ ] **Step 1: Write the failing tests**

`UnitTests/ReleasedThreadsStoreTests.swift`:

```swift
import XCTest
@testable import Pilgrim

final class ReleasedThreadsStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: ReleasedThreadsStore!
    private let released = DateFactory.makeDate(2026, 8, 20, 9, 0, 0)

    override func setUpWithError() throws {
        suiteName = "ReleasedThreadsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = ReleasedThreadsStore(defaults: defaults)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testRelease_persistsAcrossInstances() {
        store.release(displayTerm: "the move", lemmas: ["move", "moving"], releasedAt: released)
        let reopened = ReleasedThreadsStore(defaults: defaults)
        XCTAssertEqual(reopened.all, [
            ReleasedThread(displayTerm: "the move", lemmas: ["move", "moving"], releasedAt: released)
        ])
    }

    func testRelease_mergesCohortForSameTermKeepingFirstDate() {
        store.release(displayTerm: "the move", lemmas: ["move"], releasedAt: released)
        store.release(displayTerm: "the move", lemmas: ["moving"],
                      releasedAt: released.addingTimeInterval(86400))
        XCTAssertEqual(store.all, [
            ReleasedThread(displayTerm: "the move", lemmas: ["move", "moving"], releasedAt: released)
        ])
    }

    func testWelcomeBack_removesCohortAtomically() {
        store.release(displayTerm: "the move", lemmas: ["move", "moving"], releasedAt: released)
        store.release(displayTerm: "father", lemmas: ["father"], releasedAt: released)
        store.welcomeBack(displayTerm: "the move")
        XCTAssertEqual(store.all.map(\.displayTerm), ["father"])
        XCTAssertEqual(store.releasedLemmas, ["father"])
    }

    func testReleasedLemmas_unionAcrossEntries() {
        store.release(displayTerm: "the move", lemmas: ["move", "moving"], releasedAt: released)
        store.release(displayTerm: "father", lemmas: ["father"], releasedAt: released)
        XCTAssertEqual(store.releasedLemmas, ["move", "moving", "father"])
    }

    func testChangeCount_bumpsOnEveryMutation() {
        let before = store.changeCount
        store.release(displayTerm: "a", lemmas: ["a"], releasedAt: released)
        store.welcomeBack(displayTerm: "a")
        store.clear()
        XCTAssertEqual(store.changeCount, before + 3)
    }

    func testAll_sortedNewestFirstThenTerm() {
        store.release(displayTerm: "b", lemmas: ["b"], releasedAt: released)
        store.release(displayTerm: "a", lemmas: ["a"], releasedAt: released)
        store.release(displayTerm: "c", lemmas: ["c"], releasedAt: released.addingTimeInterval(86400))
        XCTAssertEqual(store.all.map(\.displayTerm), ["c", "a", "b"])
    }

    func testMerge_unionsByTermKeepingEarliestDate() {
        store.release(displayTerm: "the move", lemmas: ["move"], releasedAt: released)
        store.merge(released: [
            ReleasedThread(displayTerm: "the move", lemmas: ["moving"],
                           releasedAt: released.addingTimeInterval(-86400)),
            ReleasedThread(displayTerm: "father", lemmas: ["father"], releasedAt: released)
        ], welcomedBack: [])
        XCTAssertEqual(Set(store.all.map(\.displayTerm)), ["the move", "father"])
        let move = store.all.first { $0.displayTerm == "the move" }
        XCTAssertEqual(move?.lemmas, ["move", "moving"])
        XCTAssertEqual(move?.releasedAt, released.addingTimeInterval(-86400))
    }

    func testMerge_staleImportedRelease_doesNotUndoWelcomeBack() {
        store.release(displayTerm: "father", lemmas: ["father"], releasedAt: released)
        store.welcomeBack(displayTerm: "father", at: released.addingTimeInterval(7 * 86400))
        store.merge(released: [
            ReleasedThread(displayTerm: "father", lemmas: ["father"], releasedAt: released)
        ], welcomedBack: [])
        XCTAssertTrue(store.all.isEmpty,
                      "the walker's welcome-back is the later decision — importing an old backup never silently re-releases")
        XCTAssertEqual(store.welcomedBack.map(\.displayTerm), ["father"])
    }

    func testMerge_staleImportedWelcomeBack_doesNotUndoRelease() {
        store.release(displayTerm: "father", lemmas: ["father"], releasedAt: released)
        store.merge(released: [], welcomedBack: [
            WelcomedBackThread(displayTerm: "father",
                               welcomedBackAt: released.addingTimeInterval(-86400))
        ])
        XCTAssertEqual(store.all.map(\.displayTerm), ["father"],
                       "released again after that welcome-back — the newer local release stands")
    }

    func testClear_emptiesEverything() {
        store.release(displayTerm: "a", lemmas: ["a"], releasedAt: released)
        store.welcomeBack(displayTerm: "a")
        store.release(displayTerm: "b", lemmas: ["b"], releasedAt: released)
        store.clear()
        XCTAssertTrue(store.isEmpty)
        XCTAssertTrue(store.welcomedBack.isEmpty)
        XCTAssertTrue(ReleasedThreadsStore(defaults: defaults).isEmpty)
    }
}
```

`UnitTests/ReleasedThreadsPackageTests.swift`:

```swift
import XCTest
@testable import Pilgrim

final class ReleasedThreadsPackageTests: XCTestCase {

    private let released = DateFactory.makeDate(2026, 8, 20, 9, 0, 0)

    private func preferences(
        releasedThreads: [PilgrimReleasedThread]?,
        welcomedBack: [PilgrimWelcomedBackThread]? = nil
    ) -> PilgrimPreferences {
        PilgrimPreferences(
            distanceUnit: "km", altitudeUnit: "m", speedUnit: "km/h", energyUnit: "kJ",
            celestialAwareness: false, zodiacSystem: "tropical", beginWithIntention: false,
            releasedThreads: releasedThreads,
            welcomedBackThreads: welcomedBack
        )
    }

    func testPreferences_roundTripWithReleasedThreads() throws {
        let original = preferences(
            releasedThreads: [
                PilgrimReleasedThread(term: "the move", lemmas: ["move", "moving"], releasedAt: released)
            ],
            welcomedBack: [
                PilgrimWelcomedBackThread(term: "father", welcomedBackAt: released)
            ]
        )
        let data = try PilgrimDateCoding.makeEncoder().encode(original)
        let decoded = try PilgrimDateCoding.makeDecoder().decode(PilgrimPreferences.self, from: data)
        XCTAssertEqual(decoded.releasedThreads?.count, 1)
        XCTAssertEqual(decoded.releasedThreads?[0].term, "the move")
        XCTAssertEqual(decoded.releasedThreads?[0].lemmas, ["move", "moving"])
        XCTAssertEqual(decoded.releasedThreads?[0].releasedAt, released)
        XCTAssertEqual(decoded.welcomedBackThreads?.map(\.term), ["father"])
        XCTAssertEqual(decoded.welcomedBackThreads?.first?.welcomedBackAt, released)
    }

    func testPreferences_oldJSONWithoutKey_decodesNil() throws {
        let old = """
        {"distanceUnit":"km","altitudeUnit":"m","speedUnit":"km/h","energyUnit":"kJ",
        "celestialAwareness":false,"zodiacSystem":"tropical","beginWithIntention":false}
        """
        let decoded = try PilgrimDateCoding.makeDecoder()
            .decode(PilgrimPreferences.self, from: Data(old.utf8))
        XCTAssertNil(decoded.releasedThreads)
        XCTAssertNil(decoded.welcomedBackThreads)
    }

    func testBuildManifest_mapsReleasedThreads() {
        let manifest = PilgrimPackageConverter.buildManifest(
            walkCount: 0, events: [],
            releasedThreads: [ReleasedThread(displayTerm: "the move", lemmas: ["move"], releasedAt: released)],
            welcomedBackThreads: [WelcomedBackThread(displayTerm: "father", welcomedBackAt: released)]
        )
        XCTAssertEqual(manifest.preferences.releasedThreads?.map(\.term), ["the move"])
        XCTAssertEqual(manifest.preferences.releasedThreads?.first?.releasedAt, released)
        XCTAssertEqual(manifest.preferences.welcomedBackThreads?.map(\.term), ["father"])
    }

    func testBuildManifest_emptyReleasedSet_omitsKey() throws {
        let manifest = PilgrimPackageConverter.buildManifest(
            walkCount: 0, events: [], releasedThreads: [], welcomedBackThreads: []
        )
        XCTAssertNil(manifest.preferences.releasedThreads)
        XCTAssertNil(manifest.preferences.welcomedBackThreads)
        let json = String(decoding: try PilgrimDateCoding.makeEncoder().encode(manifest), as: UTF8.self)
        XCTAssertFalse(json.contains("releasedThreads"),
                       "a walker who released nothing exports a byte-identical preferences block")
        XCTAssertFalse(json.contains("welcomedBackThreads"))
    }

    func testImportMapping_fromPreferences() {
        let mapped = PilgrimPackageConverter.releasedThreads(from: preferences(releasedThreads: [
            PilgrimReleasedThread(term: "father", lemmas: ["father"], releasedAt: released)
        ]))
        XCTAssertEqual(mapped, [
            ReleasedThread(displayTerm: "father", lemmas: ["father"], releasedAt: released)
        ])
        XCTAssertEqual(PilgrimPackageConverter.releasedThreads(from: preferences(releasedThreads: nil)), [])
        XCTAssertEqual(
            PilgrimPackageConverter.welcomedBackThreads(from: preferences(
                releasedThreads: nil,
                welcomedBack: [PilgrimWelcomedBackThread(term: "father", welcomedBackAt: released)]
            )),
            [WelcomedBackThread(displayTerm: "father", welcomedBackAt: released)]
        )
        XCTAssertEqual(PilgrimPackageConverter.welcomedBackThreads(from: preferences(releasedThreads: nil)), [])
    }
}
```

Append to `UnitTests/DataManagerThreadsDeletionTests.swift` (inside the existing class, mirroring its `testDeleteAll` expectation pattern):

```swift
    func testDeleteAll_clearsReleasedThreads() {
        let suiteName = "ReleasedThreadsDeleteAll-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let released = ReleasedThreadsStore(defaults: defaults)
        released.release(displayTerm: "the move", lemmas: ["move"])
        DataManager.releasedThreadsStore = released
        defer { DataManager.releasedThreadsStore = .shared }

        let deleted = expectation(description: "deleted all")
        DataManager.deleteAll { success, _ in
            XCTAssertTrue(success)
            deleted.fulfill()
        }
        wait(for: [deleted], timeout: 5)
        XCTAssertTrue(released.isEmpty, "Delete All Data clears the released set with everything else")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/ReleasedThreadsStoreTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'ReleasedThreadsStore' in scope` (build error counts as red).

- [ ] **Step 3: Implement the store**

`Pilgrim/Models/Threads/ReleasedThreadsStore.swift`:

```swift
import Foundation

/// A walker's decision to stop noticing a thread. Cohort-scoped: releasing a
/// display term releases every lemma that shared it at release time, and
/// welcome-back restores the cohort atomically. Releasing is wabi-sabi, not
/// deletion — the words remain in their transcripts; the app simply stops
/// noticing.
struct ReleasedThread: Codable, Equatable {
    let displayTerm: String
    let lemmas: [String]
    let releasedAt: Date
}

/// A welcome-back is a decision too, recorded with its date so import merge
/// can honor whichever decision came last. Without the record, a stale
/// backup's release would silently override the walker's later reversal —
/// the spec's reversibility promise has to survive backups.
struct WelcomedBackThread: Codable, Equatable {
    let displayTerm: String
    let welcomedBackAt: Date
}

/// UserDefaults-persisted released set. Releases and welcome-backs are
/// walker decisions, not derived analysis — they survive relaunch, ride in
/// the `.pilgrim` preferences block (the sanctioned carve-out), and Delete
/// All Data clears them with everything else. Analysis and stored contexts
/// are untouched by release, so it is fully reversible.
final class ReleasedThreadsStore {

    static let shared = ReleasedThreadsStore(defaults: .standard)

    static let defaultsKey = "releasedThreads"
    static let welcomedBackKey = "welcomedBackThreads"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var _changeCount = 0

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Session-scoped memo token, bumped on every mutation — folded into the
    /// dossier-builder and suggestions memo keys so a release is visible on
    /// the very next prompt or sheet open.
    var changeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _changeCount
    }

    /// Newest release first, ties broken by term — the settings list order.
    var all: [ReleasedThread] {
        lock.lock()
        defer { lock.unlock() }
        return loadReleased()
    }

    /// Welcome-back records, term-ascending — exported beside the released
    /// list so import merge can compare decisions by date.
    var welcomedBack: [WelcomedBackThread] {
        lock.lock()
        defer { lock.unlock() }
        return loadWelcomedBack()
    }

    var releasedLemmas: Set<String> {
        Set(all.flatMap(\.lemmas))
    }

    var isEmpty: Bool { all.isEmpty }

    func release(displayTerm: String, lemmas: [String], releasedAt: Date = Date()) {
        mutate { entries, welcomes in
            welcomes.removeAll { $0.displayTerm == displayTerm }
            if let index = entries.firstIndex(where: { $0.displayTerm == displayTerm }) {
                entries[index] = ReleasedThread(
                    displayTerm: displayTerm,
                    lemmas: Set(entries[index].lemmas).union(lemmas).sorted(),
                    releasedAt: entries[index].releasedAt
                )
            } else {
                entries.append(ReleasedThread(
                    displayTerm: displayTerm, lemmas: lemmas.sorted(), releasedAt: releasedAt
                ))
            }
        }
    }

    func welcomeBack(displayTerm: String, at date: Date = Date()) {
        mutate { entries, welcomes in
            entries.removeAll { $0.displayTerm == displayTerm }
            welcomes.removeAll { $0.displayTerm == displayTerm }
            welcomes.append(WelcomedBackThread(displayTerm: displayTerm, welcomedBackAt: date))
        }
    }

    /// Import merge: latest decision wins, per cohort. Two releases union
    /// their lemmas and keep the earlier date so repeated imports stay
    /// stable; a release and a welcome-back for the same term are compared
    /// by date and the older decision yields. On a tie the local state
    /// stands — re-importing the same package is a no-op.
    func merge(released importedReleased: [ReleasedThread],
               welcomedBack importedWelcomedBack: [WelcomedBackThread]) {
        guard !importedReleased.isEmpty || !importedWelcomedBack.isEmpty else { return }
        mutate { entries, welcomes in
            for thread in importedReleased {
                if let welcome = welcomes.first(where: { $0.displayTerm == thread.displayTerm }),
                   welcome.welcomedBackAt >= thread.releasedAt {
                    continue // the walker's welcome-back is the later decision — never silently re-release
                }
                welcomes.removeAll { $0.displayTerm == thread.displayTerm }
                if let index = entries.firstIndex(where: { $0.displayTerm == thread.displayTerm }) {
                    entries[index] = ReleasedThread(
                        displayTerm: thread.displayTerm,
                        lemmas: Set(entries[index].lemmas).union(thread.lemmas).sorted(),
                        releasedAt: min(entries[index].releasedAt, thread.releasedAt)
                    )
                } else {
                    entries.append(thread)
                }
            }
            for welcome in importedWelcomedBack {
                if let entry = entries.first(where: { $0.displayTerm == welcome.displayTerm }),
                   entry.releasedAt >= welcome.welcomedBackAt {
                    continue // released again after that welcome-back — the newer release stands
                }
                entries.removeAll { $0.displayTerm == welcome.displayTerm }
                if let index = welcomes.firstIndex(where: { $0.displayTerm == welcome.displayTerm }) {
                    welcomes[index] = WelcomedBackThread(
                        displayTerm: welcome.displayTerm,
                        welcomedBackAt: max(welcomes[index].welcomedBackAt, welcome.welcomedBackAt)
                    )
                } else {
                    welcomes.append(welcome)
                }
            }
        }
    }

    /// Delete All Data hook — walker decisions clear with everything else.
    func clear() {
        mutate { entries, welcomes in
            entries.removeAll()
            welcomes.removeAll()
        }
    }

    private func mutate(_ body: (inout [ReleasedThread], inout [WelcomedBackThread]) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var entries = loadReleased()
        var welcomes = loadWelcomedBack()
        body(&entries, &welcomes)
        entries.sort { ($0.releasedAt, $1.displayTerm) > ($1.releasedAt, $0.displayTerm) }
        welcomes.sort { $0.displayTerm < $1.displayTerm }
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
        if let data = try? JSONEncoder().encode(welcomes) {
            defaults.set(data, forKey: Self.welcomedBackKey)
        }
        _changeCount += 1
    }

    private func loadReleased() -> [ReleasedThread] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let entries = try? JSONDecoder().decode([ReleasedThread].self, from: data) else { return [] }
        return entries
    }

    private func loadWelcomedBack() -> [WelcomedBackThread] {
        guard let data = defaults.data(forKey: Self.welcomedBackKey),
              let entries = try? JSONDecoder().decode([WelcomedBackThread].self, from: data) else { return [] }
        return entries
    }
}
```

- [ ] **Step 4: Wire the `.pilgrim` carve-out and the Delete All hook**

1. `PilgrimPackageModels.swift` — replace the `PilgrimPreferences` struct (line 60) and add the new struct directly below it. The explicit init keeps the new field nil-defaulted so the converter and every test fixture compile unchanged:

```swift
struct PilgrimPreferences: Codable {
    let distanceUnit: String
    let altitudeUnit: String
    let speedUnit: String
    let energyUnit: String
    let celestialAwareness: Bool
    let zodiacSystem: String
    let beginWithIntention: Bool
    /// Released thought threads — the one sanctioned derived-data carve-out
    /// (walker decisions, like zodiacSystem; the lemmas already appear
    /// verbatim in the exported transcripts). Welcome-backs ride beside the
    /// releases: both are decisions, and import merge compares them by date
    /// so a stale backup's release can never override a later reversal.
    /// Optional so pre-1.12 files decode and pre-1.12 importers ignore the
    /// unknown keys.
    let releasedThreads: [PilgrimReleasedThread]?
    let welcomedBackThreads: [PilgrimWelcomedBackThread]?

    init(
        distanceUnit: String,
        altitudeUnit: String,
        speedUnit: String,
        energyUnit: String,
        celestialAwareness: Bool,
        zodiacSystem: String,
        beginWithIntention: Bool,
        releasedThreads: [PilgrimReleasedThread]? = nil,
        welcomedBackThreads: [PilgrimWelcomedBackThread]? = nil
    ) {
        self.distanceUnit = distanceUnit
        self.altitudeUnit = altitudeUnit
        self.speedUnit = speedUnit
        self.energyUnit = energyUnit
        self.celestialAwareness = celestialAwareness
        self.zodiacSystem = zodiacSystem
        self.beginWithIntention = beginWithIntention
        self.releasedThreads = releasedThreads
        self.welcomedBackThreads = welcomedBackThreads
    }
}

struct PilgrimReleasedThread: Codable {
    let term: String
    let lemmas: [String]
    let releasedAt: Date
}

struct PilgrimWelcomedBackThread: Codable {
    let term: String
    let welcomedBackAt: Date
}
```

2. `PilgrimPackageConverter.swift` — in `buildManifest` (line 241), add two defaulted parameters and pass the mapped fields into the `PilgrimPreferences(...)` construction (line 252):

```swift
    static func buildManifest(
        walkCount: Int,
        events: [PilgrimEvent],
        archivedEntries: [PilgrimArchivedWalk] = [],
        releasedThreads: [ReleasedThread] = ReleasedThreadsStore.shared.all,
        welcomedBackThreads: [WelcomedBackThread] = ReleasedThreadsStore.shared.welcomedBack
    ) -> PilgrimManifest {
```

and inside, extend the existing `PilgrimPreferences(` construction with:

```swift
            beginWithIntention: UserPreferences.beginWithIntention.value,
            releasedThreads: releasedThreads.isEmpty ? nil : releasedThreads.map {
                PilgrimReleasedThread(term: $0.displayTerm, lemmas: $0.lemmas, releasedAt: $0.releasedAt)
            },
            welcomedBackThreads: welcomedBackThreads.isEmpty ? nil : welcomedBackThreads.map {
                PilgrimWelcomedBackThread(term: $0.displayTerm, welcomedBackAt: $0.welcomedBackAt)
            }
```

Add the import mapping helpers next to `convertEvents(_:)`:

```swift
    /// Import-side mapping for the released-threads carve-out. Pure, so the
    /// importer's merge stays a one-liner and this stays testable.
    static func releasedThreads(from preferences: PilgrimPreferences) -> [ReleasedThread] {
        (preferences.releasedThreads ?? []).map {
            ReleasedThread(displayTerm: $0.term, lemmas: $0.lemmas, releasedAt: $0.releasedAt)
        }
    }

    static func welcomedBackThreads(from preferences: PilgrimPreferences) -> [WelcomedBackThread] {
        (preferences.welcomedBackThreads ?? []).map {
            WelcomedBackThread(displayTerm: $0.term, welcomedBackAt: $0.welcomedBackAt)
        }
    }
```

3. `PilgrimPackageImporter.swift` — add `let releasedThreads: [ReleasedThread]` and `let welcomedBackThreads: [WelcomedBackThread]` to `DecodedPackage` (line 54), populate them in `unpackAndDecode`'s final `DecodedPackage(...)` construction with `releasedThreads: PilgrimPackageConverter.releasedThreads(from: manifest.preferences)` and `welcomedBackThreads: PilgrimPackageConverter.welcomedBackThreads(from: manifest.preferences)`, and in the `importPackage` success hook (line 86) add the merge between the tombstone clear and the backfill reset:

```swift
                        if case .success = result {
                            TranscriptContextStore.shared.clearTombstones(for: importedRecordingUUIDs)
                            ReleasedThreadsStore.shared.merge(
                                released: package.releasedThreads,
                                welcomedBack: package.welcomedBackThreads
                            )
                            ThreadsBackfill.reset()
                        }
```

Any test fixture constructing `DecodedPackage` directly gains `releasedThreads: [], welcomedBackThreads: []`.

4. `DataManager.swift` — add the seam next to the existing `transcriptContextStore` seam:

```swift
    /// Injection seam for tests; production always uses the shared store.
    static var releasedThreadsStore: ReleasedThreadsStore = .shared
```

and in `deleteAll`'s `.success` branch (line 844-855), after `UserPreferences.clearArchivedRegistry()`:

```swift
                releasedThreadsStore.clear()
```

The call sits in the transaction-success completion, preserving the Data Safety rule: walker decisions are only cleared once the database wipe committed.

5. `UnitTests/PilgrimPackageExporterArchivedTests.swift` — `buildManifest`'s new defaults read `ReleasedThreadsStore.shared`, i.e. the test host's persistent standard defaults. Add (or extend) `setUpWithError` in that class so a simulator that dogfooded a release can't inject `releasedThreads` into these manifests:

```swift
        UserDefaults.standard.removeObject(forKey: ReleasedThreadsStore.defaultsKey)
        UserDefaults.standard.removeObject(forKey: ReleasedThreadsStore.welcomedBackKey)
```

- [ ] **Step 5: Run the test classes — PASS**

Run: `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/ReleasedThreadsStoreTests -only-testing:UnitTests/ReleasedThreadsPackageTests -only-testing:UnitTests/DataManagerThreadsDeletionTests -only-testing:UnitTests/PilgrimPackageExporterArchivedTests 2>&1 | tail -20`
Expected: PASS — 10 + 5 new tests plus the new deleteAll clearing test, and the existing DataManagerThreadsDeletionTests / PilgrimPackageExporterArchivedTests still green.

- [ ] **Step 6: Commit**

```bash
git add Pilgrim/Models/Threads/ReleasedThreadsStore.swift Pilgrim/Models/Data/PilgrimPackage/PilgrimPackageModels.swift Pilgrim/Models/Data/PilgrimPackage/PilgrimPackageConverter.swift Pilgrim/Models/Data/PilgrimPackage/PilgrimPackageImporter.swift Pilgrim/Models/Data/DataManager.swift UnitTests/ReleasedThreadsStoreTests.swift UnitTests/ReleasedThreadsPackageTests.swift UnitTests/DataManagerThreadsDeletionTests.swift UnitTests/PilgrimPackageExporterArchivedTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(threads): released set — cohort releases, latest-decision-wins merge, Delete All clearing, .pilgrim carve-out"
```

---

### Task 2: Filtering integration — released cohorts vanish everywhere

**Files:**
- Modify: `Pilgrim/Models/Threads/ThreadStore.swift` (`build` gains `released` parameter)
- Modify: `Pilgrim/Models/Prompt/AttentionDirectives.swift` (`detect` + `recurringWord` gain the released skip)
- Modify: `Pilgrim/Models/Threads/ThreadsDossierBuilder.swift` (released filter + memo token)
- Modify: `Pilgrim/Models/Threads/ThreadIntentionSuggestions.swift` (released filter + memo token + injectable walkIndex)
- Test: `UnitTests/ThreadsReleaseFilteringTests.swift`, extend `UnitTests/AttentionDirectivesTests.swift` (setUp clear only — the new detect default reads the test host's standard defaults)

**Interfaces:**
- Consumes: `ReleasedThreadsStore` (Task 1); existing `ThreadStore` / `AttentionDirectives` / builder / suggestions surfaces.
- Produces (used by Tasks 3, 4, 7):
  - `ThreadStore.build(contexts:walks:released:)` — `released: Set<String> = []`; a released lemma founds no thread, covering card, thread view, dossier trajectories, quiet-this-walk lines, chips, and the recap in one place.
  - `AttentionDirectives.detect(context:detectedLanguageCode:releasedLemmas:)` — `releasedLemmas: Set<String> = ReleasedThreadsStore.shared.releasedLemmas`; only `recurringWord` consumes it (the one surfacing path that bypasses ThreadStore); the next-ranked candidate is promoted. `intentionEcho` is deliberately exempt — it only quotes words from the walker's own stated intention.
  - `ThreadsDossierBuilder.build(walkUUID:recordings:walkIndex:store:releasedStore:)` — memo key now includes the released store's change token.
  - `ThreadIntentionSuggestions.current(asOf:store:releasedStore:walkIndex:)` — same token in its memo key; `walkIndex` is injectable (nil = live CoreStore index) so Task 8's wiring test can drive `current()` end to end.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Pilgrim

final class ThreadsReleaseFilteringTests: XCTestCase {

    private let base = DateFactory.makeDate(2024, 6, 1, 9, 0, 0)

    private func context(_ uuid: UUID, lemma: String, mentions: Int) -> TranscriptContext {
        TranscriptContext(
            schemaVersion: 1, recordingUUID: uuid, transcriptHash: "h",
            languageCode: "en", wordCount: 200,
            themes: [Theme(
                lemma: lemma, displayTerm: lemma, mentionCount: mentions,
                salience: Double(mentions) / 200,
                mentions: Array(repeating: ThemeMention(start: 0, length: 4), count: mentions)
            )],
            markers: nil
        )
    }

    func testBuild_dropsReleasedLemmas() {
        let rec = UUID(), walk = UUID()
        let contexts = [context(rec, lemma: "move", mentions: 3)]
        let walks = [rec: (walkUUID: walk, date: base)]
        XCTAssertEqual(ThreadStore.build(contexts: contexts, walks: walks).count, 1)
        XCTAssertTrue(ThreadStore.build(contexts: contexts, walks: walks, released: ["move"]).isEmpty)
    }

    func testBuild_cohortLemmasBothDrop() {
        let recA = UUID(), recB = UUID(), walk = UUID()
        let contexts = [
            context(recA, lemma: "move", mentions: 3),
            context(recB, lemma: "moving", mentions: 2)
        ]
        let walks = [recA: (walkUUID: walk, date: base), recB: (walkUUID: walk, date: base)]
        let threads = ThreadStore.build(contexts: contexts, walks: walks, released: ["move", "moving"])
        XCTAssertTrue(threads.isEmpty, "release acts on the display term's full lemma cohort")
    }

    private var recurringText: String {
        "The move is here. The move is near. The move is real. The move returns. " +
        "The garden waits. The garden grows. The garden helps."
    }

    func testRecurringWord_skipsReleasedAndPromotesNext() {
        let context = ActivityContext.make(
            recordings: [RecordingContext(
                text: recurringText, timestamp: base,
                startCoordinate: nil, endCoordinate: nil, wordsPerMinute: nil
            )],
            startDate: base
        )
        let unfiltered = AttentionDirectives.detect(context: context, releasedLemmas: []).joined()
        XCTAssertTrue(unfiltered.contains("'move'"))
        let filtered = AttentionDirectives.detect(context: context, releasedLemmas: ["move"]).joined()
        XCTAssertFalse(filtered.contains("'move'"))
        XCTAssertTrue(filtered.contains("'garden'"), "the next-ranked candidate is promoted")
    }

    func testIntentionEcho_exemptFromRelease() {
        let context = ActivityContext.make(
            recordings: [RecordingContext(
                text: recurringText, timestamp: base,
                startCoordinate: nil, endCoordinate: nil, wordsPerMinute: nil
            )],
            startDate: base,
            intention: "sit with the move"
        )
        let joined = AttentionDirectives.detect(context: context, releasedLemmas: ["move"]).joined()
        XCTAssertTrue(joined.contains("intention spoke of"),
                      "the echo quotes the walker's own stated intention — walker-authored, not app-noticed")
    }

    func testDossierBuilder_releaseVisibleOnNextOpen() {
        let saved = UserPreferences.threadsAfterWalks.value
        defer { UserPreferences.threadsAfterWalks.value = saved }
        UserPreferences.threadsAfterWalks.value = true

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReleaseFilteringTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptContextStore(directory: directory)

        let suiteName = "ReleaseFilteringTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let releasedStore = ReleasedThreadsStore(defaults: defaults)

        let transcript = "The move is on my mind today. The move would change everything for us. " +
            "The move keeps returning whenever the morning turns quiet enough to hear it speak plainly."
        let recUUID = UUID(), walkUUID = UUID()
        let recording = RecordingContext(
            text: transcript, timestamp: base,
            startCoordinate: nil, endCoordinate: nil, wordsPerMinute: nil,
            recordingUUID: recUUID
        )
        let walkIndex = [recUUID: (walkUUID: walkUUID, date: base)]

        let before = ThreadsDossierBuilder.build(
            walkUUID: walkUUID, recordings: [recording], walkIndex: walkIndex,
            store: store, releasedStore: releasedStore
        )
        XCTAssertTrue(before?.contains("'move'") == true)

        releasedStore.release(displayTerm: "move", lemmas: ["move"])
        let after = ThreadsDossierBuilder.build(
            walkUUID: walkUUID, recordings: [recording], walkIndex: walkIndex,
            store: store, releasedStore: releasedStore
        )
        XCTAssertNotNil(after, "marker profiles still render — release removes noticing, not analysis")
        XCTAssertFalse(after!.contains("'move'"),
                       "the released token invalidates the memo — visible on the very next open")
    }

    func testSuggestions_selectOverFilteredThreadsExcludesReleased() {
        let recA = UUID(), recB = UUID()
        let contexts = [
            context(recA, lemma: "move", mentions: 3),
            context(recB, lemma: "move", mentions: 3)
        ]
        let walks = [
            recA: (walkUUID: UUID(), date: base),
            recB: (walkUUID: UUID(), date: base.addingTimeInterval(5 * 86400))
        ]
        let filtered = ThreadStore.build(contexts: contexts, walks: walks, released: ["move"])
        XCTAssertTrue(ThreadIntentionSuggestions.select(
            threads: filtered, asOf: base.addingTimeInterval(6 * 86400)
        ).isEmpty, "select over release-filtered threads yields nothing — ranking only; the async current() wiring is pinned by Task 8's testCurrent_releaseVisibleOnNextCall")
    }
}
```

- [ ] **Step 2: Run to verify failure** (`-only-testing:UnitTests/ThreadsReleaseFilteringTests`). Expected: FAIL — `build(contexts:walks:released:)` and `detect(context:releasedLemmas:)` don't exist yet (build error is red).

- [ ] **Step 3: Implement the ThreadStore filter**

In `ThreadStore.swift`, replace the `build` signature and its inner loop (only the two marked lines change):

```swift
    static func build(
        contexts: [TranscriptContext],
        walks: [UUID: (walkUUID: UUID, date: Date)],
        released: Set<String> = []
    ) -> [WalkThread] {
        var appearancesByLemma: [String: [ThreadAppearance]] = [:]
        var displayCounts: [String: [String: Int]] = [:]

        for context in contexts {
            guard let walk = walks[context.recordingUUID] else { continue }
            for theme in context.themes where !released.contains(theme.lemma) {
                appearancesByLemma[theme.lemma, default: []].append(ThreadAppearance(
                    recordingUUID: context.recordingUUID,
                    walkUUID: walk.walkUUID,
                    date: walk.date,
                    mentionCount: theme.mentionCount,
                    salience: theme.salience
                ))
                displayCounts[theme.lemma, default: [:]][theme.displayTerm, default: 0] += theme.mentionCount
            }
        }
        // ...remainder of build unchanged...
```

- [ ] **Step 4: Implement the recurringWord skip**

In `AttentionDirectives.swift`, replace the `detect` signature and body head plus `recurringWord`:

```swift
    /// `detectedLanguageCode` defaults to nil ("detect here") so direct
    /// callers stay unchanged; PromptGenerator.resolvedDerivations passes
    /// its precomputed code so the echo skips its own detection pass.
    /// `releasedLemmas` feeds only recurringWord — the one surfacing path
    /// that bypasses ThreadStore; intentionEcho is deliberately exempt
    /// because it quotes the walker's own stated intention.
    static func detect(
        context: ActivityContext,
        detectedLanguageCode: String? = nil,
        releasedLemmas: Set<String> = ReleasedThreadsStore.shared.releasedLemmas
    ) -> [String] {
        // Lemmatizing the full transcript is the expensive step; do it once
        // here and share it between the two detectors that need it.
        let spokenMentions = context.hasSpeech
            ? TranscriptNLP.contentLemmaMentions(in: context.recordings.map(\.text).joined(separator: " "))
            : []
        let directives = [
            stillness(context),
            paceShift(context),
            intentionEcho(context, spokenMentions: spokenMentions, detectedLanguageCode: detectedLanguageCode),
            recurringWord(context, spokenMentions: spokenMentions, releasedLemmas: releasedLemmas),
            firstVersusLast(context)
        ].compactMap { $0 }
        return Array(directives.prefix(maxDirectives))
    }
```

```swift
    /// The most-repeated content lemma across all recordings, excluding any
    /// lemma the intention already claimed and any released lemma — the
    /// next-ranked candidate is promoted, so a release never silences the
    /// directive, only redirects it. Shown as its most frequent surface form
    /// so the walker's own inflection is echoed back.
    private static func recurringWord(
        _ context: ActivityContext,
        spokenMentions mentions: [TranscriptNLP.LemmaMention],
        releasedLemmas: Set<String>
    ) -> String? {
        guard context.hasSpeech else { return nil }
        let intentionLemmas = context.intention
            .map { Set(TranscriptNLP.contentLemmas(in: $0)) } ?? []

        var counts: [String: Int] = [:]
        var surfaces: [String: [String: Int]] = [:]
        for mention in mentions
        where !intentionLemmas.contains(mention.lemma) && !releasedLemmas.contains(mention.lemma) {
            counts[mention.lemma, default: 0] += 1
            surfaces[mention.lemma, default: [:]][mention.surface, default: 0] += 1
        }

        guard let (lemma, count) = counts.filter({ $0.value >= 3 })
            .min(by: { ($0.value, $1.key) > ($1.value, $0.key) }) else { return nil }
        let display = surfaces[lemma]?
            .min(by: { ($0.value, $1.key) > ($1.value, $0.key) })?.key ?? lemma

        return "The word '\(display)' returns \(count) times across the recordings — it may be doing quiet work."
    }
```

(`PromptAssembler.walkRecord` and `PromptGenerator.resolvedDerivations` call sites compile unchanged via the default — verify with a build.)

- [ ] **Step 5: Fold the released token into both memo keys**

Replace `ThreadsDossierBuilder.swift`'s memo declaration and the head of `build` (everything from the guard through the memo check; the body below is unchanged except the two marked lines):

```swift
    private static var memo: (
        changeCount: Int, releasedToken: Int, walkUUID: UUID,
        backfillComplete: Bool, dossier: String?
    )?
    private static let memoLock = NSLock()

    static func build(
        walkUUID: UUID,
        recordings: [RecordingContext],
        walkIndex: [UUID: (walkUUID: UUID, date: Date)],
        store: TranscriptContextStore = .shared,
        releasedStore: ReleasedThreadsStore = .shared
    ) -> String? {
        guard UserPreferences.threadsAfterWalks.value, !recordings.isEmpty else { return nil }
        // One consistent read each, captured before any store mutation: a
        // mid-build mutation leaves the memoized tokens stale, so the next
        // call rebuilds instead of absorbing the mutation unseen.
        let backfillComplete = ThreadsBackfill.isComplete
        let preBuildChangeCount = store.changeCount
        let releasedToken = releasedStore.changeCount
        let released = releasedStore.releasedLemmas
        memoLock.lock()
        let cached = memo
        memoLock.unlock()
        if let cached, cached.changeCount == preBuildChangeCount,
           cached.releasedToken == releasedToken,
           cached.walkUUID == walkUUID, cached.backfillComplete == backfillComplete {
            return cached.dossier
        }
```

then, further down, the two changed lines:

```swift
        let threads = ThreadStore.build(contexts: allContexts, walks: walkIndex, released: released)
```

and the memo write:

```swift
        memoLock.lock()
        memo = (preBuildChangeCount, releasedToken, walkUUID, backfillComplete, dossier)
        memoLock.unlock()
        return dossier
```

In `ThreadIntentionSuggestions.swift`, replace the memo declaration and `current`:

```swift
    private static var memo: (changeCount: Int, releasedToken: Int, day: Date, suggestions: [String])?
    private static let memoLock = NSLock()
```

```swift
    @MainActor
    static func current(
        asOf: Date = Date(),
        store: TranscriptContextStore = .shared,
        releasedStore: ReleasedThreadsStore = .shared,
        walkIndex: [UUID: (walkUUID: UUID, date: Date)]? = nil
    ) async -> [String] {
        guard !pendingFieldGate else { return [] }
        guard UserPreferences.threadsAfterWalks.value else { return [] }
        // walkIndex is injectable for Task 8's wiring test; production
        // callers pass nil and read the live CoreStore index on the main actor.
        let walkIndex = walkIndex ?? DataManager.voiceRecordingWalkIndex()
        guard !walkIndex.isEmpty else { return [] }

        let day = Calendar.current.startOfDay(for: asOf)
        let preLoadChangeCount = store.changeCount
        let releasedToken = releasedStore.changeCount
        let released = releasedStore.releasedLemmas
        memoLock.lock()
        let cached = memo
        memoLock.unlock()
        if let cached, cached.changeCount == preLoadChangeCount,
           cached.releasedToken == releasedToken, cached.day == day {
            return cached.suggestions
        }

        return await Task.detached(priority: .userInitiated) {
            let threads = ThreadStore.build(contexts: store.loadAll(), walks: walkIndex, released: released)
            let suggestions = select(threads: threads, asOf: asOf)
            memoLock.lock()
            memo = (preLoadChangeCount, releasedToken, day, suggestions)
            memoLock.unlock()
            return suggestions
        }.value
    }
```

- [ ] **Step 6: Run the new class, then the neighbors it touched**

First, in `UnitTests/AttentionDirectivesTests.swift`, add (or extend) `setUpWithError` with the same two-key clear as Task 1's exporter tests — `detect`'s new default reads `ReleasedThreadsStore.shared` from the test host's persistent standard defaults, and a simulator that dogfooded a release would otherwise flake the recurring-word assertions non-reproducibly:

```swift
        UserDefaults.standard.removeObject(forKey: ReleasedThreadsStore.defaultsKey)
        UserDefaults.standard.removeObject(forKey: ReleasedThreadsStore.welcomedBackKey)
```

Run: `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/ThreadsReleaseFilteringTests -only-testing:UnitTests/ThreadStoreTests -only-testing:UnitTests/ThreadsDossierTests -only-testing:UnitTests/ThreadIntentionSuggestionsTests -only-testing:UnitTests/AttentionDirectivesTests 2>&1 | tail -20`
Expected: PASS — 6 new tests; every pre-existing test in the four neighbor classes untouched by the defaulted parameters.

- [ ] **Step 7: Commit**

```bash
git add Pilgrim/Models/Threads/ThreadStore.swift Pilgrim/Models/Prompt/AttentionDirectives.swift Pilgrim/Models/Threads/ThreadsDossierBuilder.swift Pilgrim/Models/Threads/ThreadIntentionSuggestions.swift UnitTests/ThreadsReleaseFilteringTests.swift UnitTests/AttentionDirectivesTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(threads): released cohorts vanish everywhere — one ThreadStore filter, one recurringWord skip, tokened memos"
```

---

### Task 3: The card — "What walked with you"

**Files:**
- Create: `Pilgrim/Models/Threads/ThreadsTexture.swift`
- Create: `Pilgrim/Models/Threads/ThreadsCardModel.swift`
- Create: `Pilgrim/Scenes/WalkSummary/ThreadsCardSection.swift`
- Create: `Pilgrim/Scenes/WalkSummary/WalkSummaryView+Threads.swift`
- Modify: `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift` (one `@State`, one slot in the VStack, one `.task`, `transcriptions` drops `private`, init gains a `showsThreadsCard` recursion-cut flag)
- Test: `UnitTests/ThreadsCardModelTests.swift`

**Interfaces:**
- Consumes: `ThreadStore.build(contexts:walks:released:)` + `ThreadStore.status` (Task 2), `TranscriptContextStore.shared.loadAll()`, `DataManager.voiceRecordingWalkIndex()`, `ThreadsBackfill.isComplete`, `MarkerLexicons.insight`, `TranscriptNLP.wordTokens`, `ContextFormatter.speakingPaceLabel` thresholds (<100 slow, ≥170 rapid — mirrored as constants here), `FlowLayout` (defined in `IntentionSettingView.swift`, internal — reusable).
- Produces (used by Tasks 4, 5, 6, 7):
  - `struct ThreadsCardTheme: Equatable, Identifiable` — `{ displayTerm: String, lemmas: [String], statusNote: String? }`, `id == displayTerm`
  - `struct ThreadsCardModel: Equatable` — `{ themes: [ThreadsCardTheme], textureLine: String?, insightWords: [String] }`
  - `ThreadsCardCopy.statusNote(for: ThreadStatus?) -> String?` — ordinal words, never digits
  - `ThreadsCardModelBuilder.model(walkUUID:threads:recordings:contextsByRecording:backfillComplete:) -> ThreadsCardModel?` (pure) and `ThreadsCardModelBuilder.mergedThread(displayTerm:cohort:)`
  - `ThreadsTexture.insightWords(in:) / .paceClause(meanWordsPerMinute:) / .line(meanWordsPerMinute:hasInsight:)`
  - `ThreadsCardLoader.load(walk:transcriptions:store:releasedStore:) async -> ThreadsCardModel?` (`@MainActor`; nil when toggle off, nothing transcribed, or no theme survives)
  - `ThreadsCardSection(model:)` view; `WalkSummaryView.threadsCardSlot` + `loadThreadsCard()` in the new extension

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Pilgrim

final class ThreadsCardModelTests: XCTestCase {

    private let base = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)

    private func appearance(recording: UUID, walk: UUID, date: Date, mentions: Int, salience: Double) -> ThreadAppearance {
        ThreadAppearance(recordingUUID: recording, walkUUID: walk, date: date,
                         mentionCount: mentions, salience: salience)
    }

    private func context(_ uuid: UUID, words: Int = 200, language: String? = "en") -> TranscriptContext {
        TranscriptContext(
            schemaVersion: 1, recordingUUID: uuid, transcriptHash: "h",
            languageCode: language, wordCount: words, themes: [], markers: nil
        )
    }

    private func singleThemeFixture(
        earlierDates: [Date] = [],
        backfillComplete: Bool = true
    ) -> ThreadsCardModel? {
        let rec = UUID(), walk = UUID()
        var appearances = earlierDates.map {
            appearance(recording: UUID(), walk: UUID(), date: $0, mentions: 2, salience: 0.01)
        }
        appearances.append(appearance(recording: rec, walk: walk, date: base, mentions: 3, salience: 0.015))
        let thread = WalkThread(lemma: "move", displayTerm: "the move", appearances: appearances)
        return ThreadsCardModelBuilder.model(
            walkUUID: walk,
            threads: [thread],
            recordings: [(uuid: rec, transcript: "words", wordsPerMinute: nil)],
            contextsByRecording: [rec: context(rec)],
            backfillComplete: backfillComplete
        )
    }

    func testModel_firstTimeStatusRequiresBackfill() {
        XCTAssertEqual(singleThemeFixture()?.themes.first?.statusNote, "first time")
        XCTAssertNil(singleThemeFixture(backfillComplete: false)?.themes.first?.statusNote,
                     "origin claims stay suppressed pre-backfill — the chip shows without a note")
    }

    func testModel_ordinalStatusThroughHistory() {
        let model = singleThemeFixture(earlierDates: [
            base.addingTimeInterval(-10 * 86400),
            base.addingTimeInterval(-5 * 86400)
        ])
        XCTAssertEqual(model?.themes.first?.statusNote, "third walk now")
    }

    func testStatusCopy_returningAndCap() {
        XCTAssertEqual(ThreadsCardCopy.statusNote(for: .recurring(walksInWindow: 1)), "returning")
        XCTAssertEqual(ThreadsCardCopy.statusNote(for: .recurring(walksInWindow: 2)), "second walk now")
        XCTAssertEqual(ThreadsCardCopy.statusNote(for: .recurring(walksInWindow: 12)), "twelfth walk now")
        XCTAssertEqual(ThreadsCardCopy.statusNote(for: .recurring(walksInWindow: 13)), "with you again")
        XCTAssertNil(ThreadsCardCopy.statusNote(for: nil))
    }

    func testModel_topFourBySalienceDeterministicTies() {
        let walk = UUID()
        let recordings = (0..<5).map { _ in UUID() }
        // "elm" is built BEFORE "dawn" and the two tie exactly on mentions
        // and salience — the top-4 cut is decided by the alphabetical
        // tie-break, not insertion order.
        let lemmas = ["alder", "birch", "cedar", "elm", "dawn"]
        let mentionCounts = [5, 4, 3, 2, 2]
        let threads = lemmas.enumerated().map { index, lemma in
            WalkThread(lemma: lemma, displayTerm: lemma, appearances: [
                appearance(recording: recordings[index], walk: walk, date: base,
                           mentions: mentionCounts[index], salience: Double(mentionCounts[index]) / 200)
            ])
        }
        let contexts = Dictionary(uniqueKeysWithValues: recordings.map { ($0, context($0)) })
        let model = ThreadsCardModelBuilder.model(
            walkUUID: walk, threads: threads,
            recordings: recordings.map { (uuid: $0, transcript: "words", wordsPerMinute: nil) },
            contextsByRecording: contexts, backfillComplete: true
        )
        XCTAssertEqual(model?.themes.map(\.displayTerm), ["alder", "birch", "cedar", "dawn"],
                       "top four by salience; 'dawn' and 'elm' tie exactly and the alphabetical tie-break keeps 'dawn'")
    }

    func testModel_cohortMergesSharedDisplayTerm() {
        let walk = UUID()
        let recA = UUID(), recB = UUID()
        let threads = [
            WalkThread(lemma: "move", displayTerm: "the move", appearances: [
                appearance(recording: recA, walk: walk, date: base, mentions: 3, salience: 0.015)
            ]),
            WalkThread(lemma: "moving", displayTerm: "the move", appearances: [
                appearance(recording: recB, walk: walk, date: base, mentions: 2, salience: 0.01)
            ])
        ]
        let contexts = [recA: context(recA), recB: context(recB)]
        let model = ThreadsCardModelBuilder.model(
            walkUUID: walk, threads: threads,
            recordings: [(uuid: recA, transcript: "w", wordsPerMinute: nil),
                         (uuid: recB, transcript: "w", wordsPerMinute: nil)],
            contextsByRecording: contexts, backfillComplete: true
        )
        XCTAssertEqual(model?.themes.count, 1, "two lemmas, one chip")
        XCTAssertEqual(model?.themes.first?.lemmas, ["move", "moving"])
    }

    func testCohortStatus_firstTimeOnlyIfNoLemmaAppearedEarlier() {
        let walk = UUID()
        let recNow = UUID()
        let threads = [
            WalkThread(lemma: "move", displayTerm: "the move", appearances: [
                appearance(recording: recNow, walk: walk, date: base, mentions: 3, salience: 0.015)
            ]),
            WalkThread(lemma: "moving", displayTerm: "the move", appearances: [
                appearance(recording: UUID(), walk: UUID(),
                           date: base.addingTimeInterval(-10 * 86400), mentions: 2, salience: 0.01)
            ])
        ]
        let model = ThreadsCardModelBuilder.model(
            walkUUID: walk, threads: threads,
            recordings: [(uuid: recNow, transcript: "w", wordsPerMinute: nil)],
            contextsByRecording: [recNow: context(recNow)], backfillComplete: true
        )
        XCTAssertEqual(model?.themes.first?.statusNote, "second walk now",
                       "a first-time claim is only true if NO lemma in the cohort appeared earlier")
    }

    func testCohortLemmas_includeSiblingsAbsentFromThisWalk() {
        let walk = UUID()
        let recNow = UUID()
        let threads = [
            WalkThread(lemma: "move", displayTerm: "the move", appearances: [
                appearance(recording: recNow, walk: walk, date: base, mentions: 3, salience: 0.015)
            ]),
            WalkThread(lemma: "moving", displayTerm: "the move", appearances: [
                appearance(recording: UUID(), walk: UUID(),
                           date: base.addingTimeInterval(-10 * 86400), mentions: 2, salience: 0.01)
            ])
        ]
        let model = ThreadsCardModelBuilder.model(
            walkUUID: walk, threads: threads,
            recordings: [(uuid: recNow, transcript: "w", wordsPerMinute: nil)],
            contextsByRecording: [recNow: context(recNow)], backfillComplete: true
        )
        XCTAssertEqual(model?.themes.first?.lemmas, ["move", "moving"],
                       "release acts on every lemma sharing the display term — including a sibling with no appearance in this walk")
    }

    func testModel_noActiveThreads_returnsNil() {
        let rec = UUID()
        XCTAssertNil(ThreadsCardModelBuilder.model(
            walkUUID: UUID(), threads: [],
            recordings: [(uuid: rec, transcript: "w", wordsPerMinute: nil)],
            contextsByRecording: [rec: context(rec)], backfillComplete: true
        ), "no theme, no card — the summary stays pixel-identical")
    }

    func testTexture_slowPaceAndInsight() {
        XCTAssertEqual(
            ThreadsTexture.line(meanWordsPerMinute: 80, hasInsight: true),
            "Spoken slowly, with words of insight."
        )
        XCTAssertEqual(
            ThreadsTexture.line(meanWordsPerMinute: 180, hasInsight: false),
            "Spoken quickly."
        )
        XCTAssertEqual(
            ThreadsTexture.line(meanWordsPerMinute: nil, hasInsight: true),
            "With words of insight."
        )
    }

    func testTexture_weakSignalsOmitEverything() {
        XCTAssertNil(ThreadsTexture.line(meanWordsPerMinute: 120, hasInsight: false),
                     "a conversational pace and no insight words is not a texture — the line is omitted")
    }

    func testInsightWords_exactTraceableSurfacesDeduped() {
        let words = ThreadsTexture.insightWords(in: [
            "I realize now what I noticed before.",
            "I realize it again with new awareness."
        ])
        XCTAssertEqual(words, ["realize", "noticed", "awareness"],
                       "spoken order, deduplicated — the exact words the clause traces to")
    }

    func testModel_nonEnglishRecordings_noInsightClause() {
        let rec = UUID(), walk = UUID()
        let thread = WalkThread(lemma: "mudanza", displayTerm: "mudanza", appearances: [
            appearance(recording: rec, walk: walk, date: base, mentions: 3, salience: 0.015)
        ])
        let model = ThreadsCardModelBuilder.model(
            walkUUID: walk, threads: [thread],
            recordings: [(uuid: rec, transcript: "I realize I notice awareness", wordsPerMinute: nil)],
            contextsByRecording: [rec: context(rec, language: "es")], backfillComplete: true
        )
        XCTAssertTrue(model?.insightWords.isEmpty == true,
                      "the insight lexicon is English-validated — other languages degrade to themes-only")
    }

    func testCopy_neverEmitsDigits() {
        for walks in 1...40 {
            let note = ThreadsCardCopy.statusNote(for: .recurring(walksInWindow: walks)) ?? ""
            XCTAssertNil(note.rangeOfCharacter(from: .decimalDigits),
                         "principle 1: ordinal words, never metric digits (failed at \(walks))")
        }
    }
}
```

- [ ] **Step 2: Run to verify failure** (`-only-testing:UnitTests/ThreadsCardModelTests`). Expected: FAIL — types don't exist.

- [ ] **Step 3: Implement the texture**

`Pilgrim/Models/Threads/ThreadsTexture.swift`:

```swift
import Foundation

/// State-only texture: pace derived mechanically from words-per-minute,
/// insight from exact lexicon words the walker can be shown. No directional
/// language, no numbers — weak signals are omitted, and the whole line is
/// omitted when nothing clears threshold (spec: Stage 3 card).
enum ThreadsTexture {

    /// Mirrors ContextFormatter.speakingPaceLabel's outer buckets: only the
    /// extremes are remarkable enough to name.
    static let slowCeiling: Double = 100
    static let quickFloor: Double = 170
    static let insightFloor = 2

    /// Insight-word surfaces in spoken order, deduplicated — the exact words
    /// that earn "with words of insight", revealed on tap (traceability:
    /// if we can't show the words, we don't show the claim).
    static func insightWords(in transcripts: [String]) -> [String] {
        var seen: Set<String> = []
        return transcripts
            .flatMap { TranscriptNLP.wordTokens(in: $0) }
            .filter { MarkerLexicons.insight.contains($0) }
            .filter { seen.insert($0).inserted }
    }

    static func paceClause(meanWordsPerMinute: Double?) -> String? {
        guard let wpm = meanWordsPerMinute else { return nil }
        if wpm < slowCeiling { return "spoken slowly" }
        if wpm >= quickFloor { return "spoken quickly" }
        return nil
    }

    static func line(meanWordsPerMinute: Double?, hasInsight: Bool) -> String? {
        var clauses: [String] = []
        if let pace = paceClause(meanWordsPerMinute: meanWordsPerMinute) {
            clauses.append(pace)
        }
        if hasInsight {
            clauses.append("with words of insight")
        }
        guard let first = clauses.first else { return nil }
        let capitalized = first.prefix(1).capitalized + String(first.dropFirst())
        return ([capitalized] + clauses.dropFirst()).joined(separator: ", ") + "."
    }
}
```

- [ ] **Step 4: Implement the card model**

`Pilgrim/Models/Threads/ThreadsCardModel.swift`:

```swift
import Foundation

struct ThreadsCardTheme: Equatable, Identifiable {
    let displayTerm: String
    let lemmas: [String]
    let statusNote: String?

    var id: String { displayTerm }
}

struct ThreadsCardModel: Equatable {
    let themes: [ThreadsCardTheme]
    let textureLine: String?
    let insightWords: [String]
}

enum ThreadsCardCopy {

    private static let ordinalWords: [Int: String] = [
        2: "second", 3: "third", 4: "fourth", 5: "fifth", 6: "sixth",
        7: "seventh", 8: "eighth", 9: "ninth", 10: "tenth",
        11: "eleventh", 12: "twelfth"
    ]

    /// Ordinal words, never digits (spec principle 1). Beyond the table the
    /// copy stays soft instead of inventing "twenty-third"; a bare
    /// walksInWindow of 1 means the thread recurred outside the 30-day
    /// window — "returning", not a false ordinal.
    static func statusNote(for status: ThreadStatus?) -> String? {
        switch status {
        case .firstTime:
            return "first time"
        case .recurring(let walks):
            if walks <= 1 { return "returning" }
            guard let word = ordinalWords[walks] else { return "with you again" }
            return "\(word) walk now"
        case nil:
            return nil
        }
    }
}

enum ThreadsCardModelBuilder {

    static let maxThemes = 4

    /// Pure: threads in, card model out. Nil means no card — the summary
    /// must stay pixel-identical when nothing was found.
    static func model(
        walkUUID: UUID,
        threads: [WalkThread],
        recordings: [(uuid: UUID, transcript: String, wordsPerMinute: Double?)],
        contextsByRecording: [UUID: TranscriptContext],
        backfillComplete: Bool
    ) -> ThreadsCardModel? {
        // Two lemmas can share a display term (move/moving → "the move"):
        // one chip per term, and release later acts on the whole cohort. The
        // grouping runs over ALL threads first — a sibling lemma whose
        // appearances are all in earlier walks still joins its cohort, so
        // status history and release lemma sets stay cohort-complete — and
        // only cohorts present in this walk keep a chip. mentions/salience
        // below filter to walkUUID, so ranking is unaffected.
        let cohorts = Dictionary(grouping: threads, by: \.displayTerm)
            .filter { $0.value.contains { $0.appearances.contains { $0.walkUUID == walkUUID } } }
        guard !cohorts.isEmpty else { return nil }

        let totalWords = recordings
            .compactMap { contextsByRecording[$0.uuid]?.wordCount }
            .reduce(0, +)

        let ranked = cohorts
            .map { term, cohort -> (theme: ThreadsCardTheme, salience: Double, mentions: Int) in
                let merged = mergedThread(displayTerm: term, cohort: cohort)
                let mentions = merged.appearances
                    .filter { $0.walkUUID == walkUUID }
                    .reduce(0) { $0 + $1.mentionCount }
                let salience = totalWords > 0 ? Double(mentions) / Double(totalWords) : 0
                let status = ThreadStore.status(
                    of: merged, atWalk: walkUUID, backfillComplete: backfillComplete
                )
                return (
                    ThreadsCardTheme(
                        displayTerm: term,
                        lemmas: cohort.map(\.lemma).sorted(),
                        statusNote: ThreadsCardCopy.statusNote(for: status)
                    ),
                    salience,
                    mentions
                )
            }
            .sorted {
                ($0.salience, $0.mentions, $1.theme.displayTerm)
                    > ($1.salience, $1.mentions, $0.theme.displayTerm)
            }
            .prefix(maxThemes)
            .map(\.theme)

        let englishTranscripts = recordings
            .filter { contextsByRecording[$0.uuid]?.languageCode == "en" }
            .map(\.transcript)
        let insightWords = ThreadsTexture.insightWords(in: englishTranscripts)

        let wpms = recordings.compactMap(\.wordsPerMinute)
        let meanWPM = wpms.isEmpty ? nil : wpms.reduce(0, +) / Double(wpms.count)

        return ThreadsCardModel(
            themes: Array(ranked),
            textureLine: ThreadsTexture.line(
                meanWordsPerMinute: meanWPM,
                hasInsight: insightWords.count >= ThreadsTexture.insightFloor
            ),
            insightWords: insightWords
        )
    }

    /// One pseudo-thread per cohort so ThreadStore.status sees the cohort's
    /// full history — a first-time claim is only true if NO lemma in the
    /// cohort appeared earlier.
    static func mergedThread(displayTerm: String, cohort: [WalkThread]) -> WalkThread {
        WalkThread(
            lemma: cohort.map(\.lemma).sorted().first ?? displayTerm,
            displayTerm: displayTerm,
            appearances: cohort.flatMap(\.appearances)
                .sorted { ($0.date, $0.recordingUUID.uuidString) < ($1.date, $1.recordingUUID.uuidString) }
        )
    }
}
```

- [ ] **Step 5: Run the model tests — PASS** (`-only-testing:UnitTests/ThreadsCardModelTests`, expected 13 tests).

- [ ] **Step 6: Implement the card view and loader**

`Pilgrim/Scenes/WalkSummary/ThreadsCardSection.swift`:

```swift
import SwiftUI

/// Loads the card model off the summary's hot path: CoreStore reads on the
/// main actor, store I/O and thread aggregation detached, plain values
/// across the boundary (the ThreadsDossierBuilder discipline).
enum ThreadsCardLoader {

    @MainActor
    static func load(
        walk: WalkInterface,
        transcriptions: [UUID: String],
        store: TranscriptContextStore = .shared,
        releasedStore: ReleasedThreadsStore = .shared
    ) async -> ThreadsCardModel? {
        guard UserPreferences.threadsAfterWalks.value,
              let walkUUID = walk.uuid,
              !transcriptions.isEmpty else { return nil }

        let recordings = walk.voiceRecordings.compactMap { recording -> (uuid: UUID, transcript: String, wordsPerMinute: Double?)? in
            guard let uuid = recording.uuid, let text = transcriptions[uuid] else { return nil }
            return (uuid, text, recording.wordsPerMinute)
        }
        guard !recordings.isEmpty else { return nil }

        let walkIndex = DataManager.voiceRecordingWalkIndex()
        let released = releasedStore.releasedLemmas
        let backfillComplete = ThreadsBackfill.isComplete

        return await Task.detached(priority: .userInitiated) {
            let contexts = store.loadAll()
            let contextsByRecording = Dictionary(
                uniqueKeysWithValues: contexts.map { ($0.recordingUUID, $0) }
            )
            let threads = ThreadStore.build(contexts: contexts, walks: walkIndex, released: released)
            return ThreadsCardModelBuilder.model(
                walkUUID: walkUUID,
                threads: threads,
                recordings: recordings,
                contextsByRecording: contextsByRecording,
                backfillComplete: backfillComplete
            )
        }.value
    }
}

/// "What walked with you" — the quiet card naming the themes of this walk.
/// Rendered only when a model exists: at least one transcribed recording,
/// at least one surviving theme, toggle on.
struct ThreadsCardSection: View {

    let model: ThreadsCardModel

    @State private var showInsightWords = false

    var body: some View {
        VStack(spacing: Constants.UI.Padding.small) {
            Text("What walked with you")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
            FlowLayout(spacing: Constants.UI.Padding.small) {
                ForEach(model.themes) { theme in
                    chip(theme)
                }
            }
            if let texture = model.textureLine {
                textureLine(texture)
            }
        }
        .padding(Constants.UI.Padding.normal)
        .frame(maxWidth: .infinity)
        .background(Color.parchmentSecondary)
        .cornerRadius(Constants.UI.CornerRadius.normal)
    }

    private func chip(_ theme: ThreadsCardTheme) -> some View {
        VStack(spacing: 2) {
            Text(theme.displayTerm)
                .font(Constants.Typography.body)
                .foregroundColor(.ink)
            if let note = theme.statusNote {
                Text(note)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(Capsule().fill(Color.moss.opacity(0.1)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            theme.statusNote.map { "\(theme.displayTerm), \($0)" } ?? theme.displayTerm
        )
    }

    private func textureLine(_ texture: String) -> some View {
        Button {
            guard !model.insightWords.isEmpty else { return }
            showInsightWords.toggle()
        } label: {
            VStack(spacing: Constants.UI.Padding.xs) {
                Text(texture)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                    .multilineTextAlignment(.center)
                if showInsightWords, !model.insightWords.isEmpty {
                    Text(model.insightWords.map { "'\($0)'" }.joined(separator: ", "))
                        .font(Constants.Typography.caption)
                        .foregroundColor(.moss)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(
            model.insightWords.isEmpty ? "" : "Double tap to see the words of insight"
        )
    }
}
```

`Pilgrim/Scenes/WalkSummary/WalkSummaryView+Threads.swift`:

```swift
import SwiftUI

// MARK: - Thought Threads card glue
//
// Extracted from `WalkSummaryView.swift` like the +Map extension, to keep
// the main type body under SwiftLint's type_body_length limit. Stored
// state stays in the struct; everything else lives here.

extension WalkSummaryView {

    @ViewBuilder
    var threadsCardSlot: some View {
        if showsThreadsCard, let threadsCardModel {
            ThreadsCardSection(model: threadsCardModel)
        }
    }

    func loadThreadsCard() async {
        guard showsThreadsCard else { return }
        threadsCardModel = await ThreadsCardLoader.load(walk: walk, transcriptions: transcriptions)
    }
}
```

In `WalkSummaryView.swift`:
1. The `@State private var transcriptions` declaration (line 18) drops `private` (the extension file needs it — same pattern as the camera state, see the comment at lines 36-38): `@State var transcriptions: [UUID: String] = [:]`
2. The init gains a recursion-cut flag: `init(walk: WalkInterface, showsThreadsCard: Bool = true)`, storing `let showsThreadsCard: Bool` next to `let walk` and assigning it first in the init body. Every existing call site compiles unchanged via the default. Tap-through summaries presented from `ThreadHistoryView` pass `false` (Task 4): without it, summary → card chip → thread view → entry row → summary recurses unboundedly, and every stacked level is a full Mapbox-bearing `WalkSummaryView` with route caches — exactly the compounding-memory pattern the resource-safety doctrine forbids. The flag cuts the cycle at one level.
3. Add below the other `@State` declarations: `@State var threadsCardModel: ThreadsCardModel?`
4. In the body's `VStack`, directly below `intentionCard` (line 80): `threadsCardSlot`
5. On the `ScrollView` modifier chain, after the `.onReceive(CollectiveRouteCatalogService.shared.$catalog)` block:

```swift
            .task(id: transcriptions.count) {
                await loadThreadsCard()
            }
```

(`id: transcriptions.count` re-runs the load when auto-transcription lands while the summary is open — the card appears the moment analysis exists.)

- [ ] **Step 7: Build the app target, run the full UnitTests suite**

Run: `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests 2>&1 | tail -5`
Expected: PASS; `grep -c "Test Case '.*' started"` count = 1269 + 35 (Tasks 1-3 tests: 16 + 6 + 13).
Then: `swiftlint lint Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift` — zero errors; the struct sits ~669/750 against type_body_length, so this task's additions to the main struct stay limited to the init flag, `@State` declarations, and one-line slots (everything else lives in the extension file).

- [ ] **Step 8: Commit**

```bash
git add Pilgrim/Models/Threads/ThreadsTexture.swift Pilgrim/Models/Threads/ThreadsCardModel.swift Pilgrim/Scenes/WalkSummary/ThreadsCardSection.swift Pilgrim/Scenes/WalkSummary/WalkSummaryView+Threads.swift Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift UnitTests/ThreadsCardModelTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(threads): the card — what walked with you, in ordinal words and traceable texture"
```

---

### Task 4: The thread view — full history, excerpts, where it began

**Files:**
- Create: `Pilgrim/Models/Threads/ThreadHistoryModel.swift`
- Create: `Pilgrim/Scenes/WalkSummary/ThreadHistoryView.swift`
- Modify: `Pilgrim/Scenes/WalkSummary/ThreadsCardSection.swift` (chips become buttons)
- Modify: `Pilgrim/Scenes/WalkSummary/WalkSummaryView+Threads.swift` (pass the tap handler)
- Modify: `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift` (one `@State`, one `.sheet`)
- Test: `UnitTests/ThreadHistoryModelTests.swift`

**Interfaces:**
- Consumes: `ThreadStore.build(contexts:walks:released:)` (Task 2), `ThreadsBackfill.isComplete` (origin claims are suppressed pre-backfill, exactly like the card's first-time status), `ThemeMention` character offsets (Character/grapheme counts, produced via `text.distance` in `TranscriptNLP`), `TranscriptContextStore.hash(of:)`, `DataManager.transcribedRecordingsSnapshot()` / `.voiceRecordingWalkIndex()` (both `@MainActor`), `DataManager.dataStack.fetchOne(From<Walk>().where(\._uuid == uuid))` (the WalkSummaryView idiom, line 325), `WalkSummaryView.computeSegments(for:)`, `PilgrimMapView` (all-defaults init, `initialCamera: MapCameraSeed.Seed`), `PilgrimAnnotation.Kind.voiceRecording(label:)`, `WalkSummaryView(walk:showsThreadsCard:)` presented via `.sheet(item:)` (Walk is Identifiable — the RecordingsListView idiom, line 55; tap-through summaries pass `showsThreadsCard: false`, the Task 3 recursion cut).
- Produces (used by Tasks 5, 7):
  - `struct ThreadHistoryEntry: Equatable` — `{ recordingUUID: UUID, walkUUID: UUID, date: Date, excerpt: String?, isOrigin: Bool }`
  - `ThreadHistoryModelBuilder.entries(cohort:contextsByRecording:transcriptsByRecording:backfillComplete:) -> [ThreadHistoryEntry]` (newest first; oldest flagged origin ONLY when backfill is complete — no entry carries `isOrigin` pre-backfill, which hides both the footer and the origin-map action)
  - `ThreadHistoryModelBuilder.excerpt(for:context:transcript:)` / `.slice(_:around:radius:)` (grapheme-safe)
  - `ThreadOriginResolver.coordinate(recordingStart:samples:) -> CLLocationCoordinate2D?` (nearest route sample within `tolerance` = 120 s)
  - `ThreadHistoryView(displayTerm:cohortLemmas:)` (pushed inside a NavigationStack)
  - `ThreadsCardSection(model:onThemeTap:)`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import CoreLocation
@testable import Pilgrim

final class ThreadHistoryModelTests: XCTestCase {

    private let base = DateFactory.makeDate(2024, 6, 1, 9, 0, 0)

    private func appearance(recording: UUID, walk: UUID, date: Date, mentions: Int = 2) -> ThreadAppearance {
        ThreadAppearance(recordingUUID: recording, walkUUID: walk, date: date,
                         mentionCount: mentions, salience: 0.01)
    }

    func testEntries_newestFirstWithOriginOnOldest() {
        let recs = [UUID(), UUID(), UUID()]
        let thread = WalkThread(lemma: "move", displayTerm: "the move", appearances: recs.enumerated().map {
            appearance(recording: $1, walk: UUID(), date: base.addingTimeInterval(Double($0) * 86400))
        })
        let entries = ThreadHistoryModelBuilder.entries(
            cohort: [thread], contextsByRecording: [:], transcriptsByRecording: [:],
            backfillComplete: true
        )
        XCTAssertEqual(entries.map(\.recordingUUID), [recs[2], recs[1], recs[0]])
        XCTAssertEqual(entries.map(\.isOrigin), [false, false, true],
                       "the oldest entry carries 'where it began'")
    }

    func testEntries_backfillIncomplete_suppressesOrigin() {
        let recs = [UUID(), UUID()]
        let thread = WalkThread(lemma: "move", displayTerm: "the move", appearances: recs.enumerated().map {
            appearance(recording: $1, walk: UUID(), date: base.addingTimeInterval(Double($0) * 86400))
        })
        let entries = ThreadHistoryModelBuilder.entries(
            cohort: [thread], contextsByRecording: [:], transcriptsByRecording: [:],
            backfillComplete: false
        )
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { !$0.isOrigin },
                      "origin claims stay suppressed pre-backfill — no 'where it began' footer, no origin-map action")
    }

    func testEntries_onePerRecordingAcrossCohort() {
        let rec = UUID(), walk = UUID()
        let cohort = [
            WalkThread(lemma: "move", displayTerm: "the move",
                       appearances: [appearance(recording: rec, walk: walk, date: base, mentions: 3)]),
            WalkThread(lemma: "moving", displayTerm: "the move",
                       appearances: [appearance(recording: rec, walk: walk, date: base, mentions: 2)])
        ]
        let entries = ThreadHistoryModelBuilder.entries(
            cohort: cohort, contextsByRecording: [:], transcriptsByRecording: [:],
            backfillComplete: true
        )
        XCTAssertEqual(entries.count, 1, "two cohort lemmas in one recording is still one moment")
    }

    func testExcerpt_realOffsetsFromAnalyzer() {
        let transcript = "A long quiet morning on the water. The river kept speaking to me about " +
            "patience and the river answered its own question before I could. Nothing else needed saying today."
        let uuid = UUID()
        let context = TranscriptContextAnalyzer.analyze(recordingUUID: uuid, transcript: transcript)
        XCTAssertTrue(context.themes.contains { $0.lemma == "river" }, "fixture sanity")
        let excerpt = ThreadHistoryModelBuilder.excerpt(
            for: ["river"], context: context, transcript: transcript
        )
        XCTAssertNotNil(excerpt)
        XCTAssertTrue(excerpt!.contains("river"))
    }

    func testExcerpt_hashMismatchReturnsNil() {
        let transcript = "The river again today, and the river once more — twenty five words of it, " +
            "give or take, spoken slowly into the morning air."
        let context = TranscriptContextAnalyzer.analyze(recordingUUID: UUID(), transcript: transcript)
        XCTAssertNil(ThreadHistoryModelBuilder.excerpt(
            for: ["river"], context: context, transcript: transcript + " edited"
        ), "stored offsets are only trusted against the exact transcript they were computed from")
    }

    func testSlice_graphemeSafeAroundEmoji() {
        let transcript = "🚶‍♂️🌫️🌊 the river again"
        let mentionStart = transcript.distance(
            from: transcript.startIndex,
            to: transcript.range(of: "river")!.lowerBound
        )
        let excerpt = ThreadHistoryModelBuilder.slice(
            transcript, around: ThemeMention(start: mentionStart, length: 5), radius: 60
        )
        XCTAssertNotNil(excerpt)
        XCTAssertTrue(excerpt!.contains("river"),
                      "multi-scalar emoji before the mention must not shift the slice")
    }

    func testSlice_outOfBoundsMentionReturnsNil() {
        XCTAssertNil(ThreadHistoryModelBuilder.slice(
            "short", around: ThemeMention(start: 40, length: 5), radius: 60
        ))
        XCTAssertNil(ThreadHistoryModelBuilder.slice(
            "short", around: ThemeMention(start: 2, length: 40), radius: 60
        ))
    }

    func testSlice_ellipsesOnlyWhereTruncated() {
        let transcript = String(repeating: "before ", count: 30) + "river" + String(repeating: " after", count: 30)
        let mentionStart = transcript.distance(
            from: transcript.startIndex,
            to: transcript.range(of: "river")!.lowerBound
        )
        let middle = ThreadHistoryModelBuilder.slice(
            transcript, around: ThemeMention(start: mentionStart, length: 5), radius: 30
        )
        XCTAssertTrue(middle!.hasPrefix("…") && middle!.hasSuffix("…"))

        let atStart = ThreadHistoryModelBuilder.slice(
            "river first then much more text follows on and on and on and on and on and on and on",
            around: ThemeMention(start: 0, length: 5), radius: 30
        )
        XCTAssertFalse(atStart!.hasPrefix("…"), "no leading ellipsis when the slice reaches the start")
    }

    func testSlice_noWhitespaceWindow_degeneratesToBareEllipsis() {
        let transcript = String(repeating: "a", count: 200)
        let excerpt = ThreadHistoryModelBuilder.slice(
            transcript, around: ThemeMention(start: 100, length: 5), radius: 30
        )
        XCTAssertEqual(excerpt, "…",
                       "a truncated window with no whitespace trims to a bare ellipsis — pinned so any future formatting change is deliberate, not accidental")
    }

    func testOriginResolver_toleranceBoundary() {
        let start = base
        let sample: (Date) -> (timestamp: Date, latitude: Double, longitude: Double) = {
            ($0, 43.0, -8.5)
        }
        XCTAssertNotNil(ThreadOriginResolver.coordinate(
            recordingStart: start, samples: [sample(start.addingTimeInterval(120))]
        ), "a fix exactly at the tolerance edge still counts")
        XCTAssertNil(ThreadOriginResolver.coordinate(
            recordingStart: start, samples: [sample(start.addingTimeInterval(121))]
        ), "beyond tolerance the coordinate is a guess — the action hides instead")
        XCTAssertNil(ThreadOriginResolver.coordinate(recordingStart: start, samples: []))
    }

    func testOriginResolver_picksNearestSample() {
        let start = base
        let coordinate = ThreadOriginResolver.coordinate(
            recordingStart: start,
            samples: [
                (start.addingTimeInterval(-90), 1.0, 1.0),
                (start.addingTimeInterval(10), 2.0, 2.0),
                (start.addingTimeInterval(60), 3.0, 3.0)
            ]
        )
        XCTAssertEqual(coordinate?.latitude, 2.0)
    }
}
```

- [ ] **Step 2: Run to verify failure** (`-only-testing:UnitTests/ThreadHistoryModelTests`). Expected: FAIL — types don't exist.

- [ ] **Step 3: Implement the model**

`Pilgrim/Models/Threads/ThreadHistoryModel.swift`:

```swift
import Foundation
import CoreLocation

struct ThreadHistoryEntry: Equatable {
    let recordingUUID: UUID
    let walkUUID: UUID
    let date: Date
    let excerpt: String?
    let isOrigin: Bool
}

enum ThreadHistoryModelBuilder {

    static let excerptRadius = 60

    /// Newest first; the oldest entry carries the origin label — but only
    /// once the one-time backfill has completed. Until then "where it began"
    /// would be a claim about walks not yet analyzed, so origin flags are
    /// suppressed rather than risked (spec), hiding both the footer and the
    /// origin-map action. One entry per recording — when two cohort lemmas
    /// appear in the same recording, the strongest theme (mention count,
    /// then lemma) provides the excerpt.
    static func entries(
        cohort: [WalkThread],
        contextsByRecording: [UUID: TranscriptContext],
        transcriptsByRecording: [UUID: String],
        backfillComplete: Bool
    ) -> [ThreadHistoryEntry] {
        let lemmas = Set(cohort.map(\.lemma))
        let appearancesByRecording = Dictionary(
            grouping: cohort.flatMap(\.appearances), by: \.recordingUUID
        )

        let sorted: [ThreadHistoryEntry] = appearancesByRecording
            .map { recordingUUID, appearances in
                // Same recording ⇒ same walk and date; the excerpt picks the
                // strongest cohort theme itself, so any element serves.
                let appearance = appearances[0]
                return ThreadHistoryEntry(
                    recordingUUID: recordingUUID,
                    walkUUID: appearance.walkUUID,
                    date: appearance.date,
                    excerpt: excerpt(
                        for: lemmas,
                        context: contextsByRecording[recordingUUID],
                        transcript: transcriptsByRecording[recordingUUID]
                    ),
                    isOrigin: false
                )
            }
            .sorted { ($0.date, $0.recordingUUID.uuidString) > ($1.date, $1.recordingUUID.uuidString) }

        guard let oldest = sorted.last else { return [] }
        guard backfillComplete else { return sorted }
        return Array(sorted.dropLast()) + [ThreadHistoryEntry(
            recordingUUID: oldest.recordingUUID,
            walkUUID: oldest.walkUUID,
            date: oldest.date,
            excerpt: oldest.excerpt,
            isOrigin: true
        )]
    }

    static func excerpt(
        for lemmas: Set<String>,
        context: TranscriptContext?,
        transcript: String?
    ) -> String? {
        guard let context, let transcript,
              context.transcriptHash == TranscriptContextStore.hash(of: transcript),
              let theme = context.themes
                .filter({ lemmas.contains($0.lemma) })
                .sorted(by: { ($0.mentionCount, $1.lemma) > ($1.mentionCount, $0.lemma) })
                .first,
              let mention = theme.mentions.first else { return nil }
        return slice(transcript, around: mention, radius: excerptRadius)
    }

    /// Mention offsets are Character (grapheme) counts, produced by
    /// `text.distance` at analysis time — sliced back with `limitedBy:` so
    /// emoji and combining marks can never push an index past either end.
    static func slice(_ transcript: String, around mention: ThemeMention, radius: Int) -> String? {
        guard mention.start >= 0, mention.length > 0,
              let mentionStart = transcript.index(
                transcript.startIndex, offsetBy: mention.start, limitedBy: transcript.endIndex
              ),
              let mentionEnd = transcript.index(
                mentionStart, offsetBy: mention.length, limitedBy: transcript.endIndex
              ) else { return nil }

        let start = transcript.index(mentionStart, offsetBy: -radius, limitedBy: transcript.startIndex)
            ?? transcript.startIndex
        let end = transcript.index(mentionEnd, offsetBy: radius, limitedBy: transcript.endIndex)
            ?? transcript.endIndex

        var excerpt = String(transcript[start..<end])
        if start > transcript.startIndex {
            excerpt = "…" + String(excerpt.drop(while: { !$0.isWhitespace }))
                .trimmingCharacters(in: .whitespaces)
        }
        if end < transcript.endIndex {
            excerpt = String(String(excerpt.reversed()).drop(while: { !$0.isWhitespace }).reversed())
                .trimmingCharacters(in: .whitespaces) + "…"
        }
        return excerpt
    }
}

enum ThreadOriginResolver {

    static let tolerance: TimeInterval = 120

    /// The route sample nearest the recording's start, within tolerance —
    /// beyond it the fix is a guess, and the origin-map action hides
    /// instead of guessing (spec: Return to where it began).
    static func coordinate(
        recordingStart: Date,
        samples: [(timestamp: Date, latitude: Double, longitude: Double)]
    ) -> CLLocationCoordinate2D? {
        guard let nearest = samples.min(by: {
            abs($0.timestamp.timeIntervalSince(recordingStart))
                < abs($1.timestamp.timeIntervalSince(recordingStart))
        }), abs(nearest.timestamp.timeIntervalSince(recordingStart)) <= tolerance else { return nil }
        return CLLocationCoordinate2D(latitude: nearest.latitude, longitude: nearest.longitude)
    }
}
```

- [ ] **Step 4: Run the model tests — PASS** (`-only-testing:UnitTests/ThreadHistoryModelTests`, expected 11 tests).

- [ ] **Step 5: Implement the view**

`Pilgrim/Scenes/WalkSummary/ThreadHistoryView.swift`:

```swift
import SwiftUI
import CoreStore
import CoreLocation

/// Best-effort reverse geocoding of each walk's starting point — resolved
/// once per walk, capped per screen, and strictly serialized: CLGeocoder
/// fails a pending request when a new one is submitted, so concurrent
/// per-row requests would silently lose most place names. One FIFO Task
/// awaits each lookup before starting the next; a missing place simply
/// doesn't render. The Task handle is cancelled when the view disappears.
@MainActor
final class ThreadPlaceResolver: ObservableObject {

    @Published private(set) var places: [UUID: String] = [:]
    private let geocoder = CLGeocoder()
    private var resolveTask: Task<Void, Never>?
    private static let maxResolutions = 12

    /// Called exactly once, from load(), with the entries' distinct walk
    /// UUIDs in display order — never per row.
    func resolveAll(walkUUIDs: [UUID]) {
        guard resolveTask == nil else { return }
        let pending = walkUUIDs.prefix(Self.maxResolutions)
        resolveTask = Task {
            for walkUUID in pending {
                guard !Task.isCancelled else { return }
                guard let walk = try? DataManager.dataStack.fetchOne(
                    From<Walk>().where(\._uuid == walkUUID)
                ), let first = walk.routeData.first else { continue }
                let location = CLLocation(latitude: first.latitude, longitude: first.longitude)
                guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first,
                      let name = placemark.locality ?? placemark.name else { continue }
                places[walkUUID] = name
            }
        }
    }

    func cancel() {
        resolveTask?.cancel()
        resolveTask = nil
    }
}

/// A thread's full history, newest first — date, place, and the walker's
/// own words around each mention. The oldest entry is labeled "where it
/// began" and offers the origin walk's map when a route fix exists.
struct ThreadHistoryView: View {

    let displayTerm: String
    let cohortLemmas: [String]

    @State private var entries: [ThreadHistoryEntry] = []
    @State private var origin: OriginMapData?
    @State private var selectedWalk: Walk?
    @State private var presentedOriginMap: OriginMapData?
    @StateObject private var placeResolver = ThreadPlaceResolver()

    struct OriginMapData: Identifiable {
        let id = UUID()
        let walk: Walk
        let coordinate: CLLocationCoordinate2D
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Constants.UI.Padding.normal) {
                ForEach(entries, id: \.recordingUUID) { entry in
                    entryRow(entry)
                }
            }
            .padding(Constants.UI.Padding.normal)
        }
        .canvasBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(displayTerm)
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
            }
        }
        .sheet(item: $selectedWalk) { walk in
            // showsThreadsCard: false is the Task 3 recursion cut — a
            // tap-through summary must not offer another threads card, or
            // summary → thread → summary stacks Mapbox-bearing views
            // without bound.
            WalkSummaryView(walk: walk, showsThreadsCard: false)
        }
        .sheet(item: $presentedOriginMap) { data in
            ThreadOriginMapView(displayTerm: displayTerm, data: data)
        }
        .task { await load() }
        .onDisappear { placeResolver.cancel() }
    }

    private func entryRow(_ entry: ThreadHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.xs) {
            Button {
                selectedWalk = try? DataManager.dataStack.fetchOne(
                    From<Walk>().where(\._uuid == entry.walkUUID)
                )
            } label: {
                VStack(alignment: .leading, spacing: Constants.UI.Padding.xs) {
                    HStack(spacing: Constants.UI.Padding.xs) {
                        Text(Self.dateFormatter.string(from: entry.date))
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                        if let place = placeResolver.places[entry.walkUUID] {
                            Text("· \(place)")
                                .font(Constants.Typography.caption)
                                .foregroundColor(.fog)
                        }
                    }
                    if let excerpt = entry.excerpt {
                        Text(excerpt)
                            .font(Constants.Typography.body)
                            .foregroundColor(.ink)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Double tap to open this walk's summary")

            if entry.isOrigin {
                originFooter
            }
        }
        .padding(Constants.UI.Padding.normal)
        .background(Color.parchmentSecondary)
        .cornerRadius(Constants.UI.CornerRadius.normal)
    }

    private var originFooter: some View {
        HStack(spacing: Constants.UI.Padding.xs) {
            Image(systemName: "leaf")
                .font(.caption)
                .foregroundColor(.moss)
            Text("where it began")
                .font(Constants.Typography.caption)
                .foregroundColor(.moss)
            Spacer()
            if let origin {
                Button {
                    presentedOriginMap = origin
                } label: {
                    Text("open the map")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.stone)
                        .frame(minHeight: 44)
                }
            }
        }
    }

    @MainActor
    private func load() async {
        guard UserPreferences.threadsAfterWalks.value else { return }
        let walkIndex = DataManager.voiceRecordingWalkIndex()
        let transcripts = Dictionary(
            uniqueKeysWithValues: DataManager.transcribedRecordingsSnapshot()
                .map { ($0.uuid, $0.transcript) }
        )
        let released = ReleasedThreadsStore.shared.releasedLemmas
        let backfillComplete = ThreadsBackfill.isComplete
        let lemmas = Set(cohortLemmas)

        entries = await Task.detached(priority: .userInitiated) { () -> [ThreadHistoryEntry] in
            let contexts = TranscriptContextStore.shared.loadAll()
            let contextsByRecording = Dictionary(
                uniqueKeysWithValues: contexts.map { ($0.recordingUUID, $0) }
            )
            let threads = ThreadStore.build(contexts: contexts, walks: walkIndex, released: released)
            return ThreadHistoryModelBuilder.entries(
                cohort: threads.filter { lemmas.contains($0.lemma) },
                contextsByRecording: contextsByRecording,
                transcriptsByRecording: transcripts,
                backfillComplete: backfillComplete
            )
        }.value
        origin = resolveOrigin()
        var seenWalks: Set<UUID> = []
        placeResolver.resolveAll(
            walkUUIDs: entries.map(\.walkUUID).filter { seenWalks.insert($0).inserted }
        )
    }

    /// Resolution happens when the view opens — never persisted, so a
    /// deleted origin walk or a fix gap simply hides the action on the next
    /// open, and the record's earliest surviving appearance becomes "where
    /// it began" (spec: deletion is deliberate record-editing).
    @MainActor
    private func resolveOrigin() -> OriginMapData? {
        guard let oldest = entries.last, oldest.isOrigin,
              let walk = try? DataManager.dataStack.fetchOne(
                From<Walk>().where(\._uuid == oldest.walkUUID)
              ),
              let recording = walk.voiceRecordings.first(where: { $0.uuid == oldest.recordingUUID }),
              let coordinate = ThreadOriginResolver.coordinate(
                recordingStart: recording.startDate,
                samples: walk.routeData.map { ($0.timestamp, $0.latitude, $0.longitude) }
              ) else { return nil }
        return OriginMapData(walk: walk, coordinate: coordinate)
    }
}

/// The origin walk's map — the existing historical summary map, static and
/// read-only, no live-walk controls — centered on where the thread first
/// found words.
struct ThreadOriginMapView: View {

    let displayTerm: String
    let data: ThreadHistoryView.OriginMapData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PilgrimMapView(
                isInteractive: false,
                showsUserLocation: false,
                routeSegments: WalkSummaryView.computeSegments(for: data.walk),
                pinAnnotations: [PilgrimAnnotation(
                    coordinate: data.coordinate,
                    kind: .voiceRecording(label: "where it began")
                )],
                initialCamera: MapCameraSeed.Seed(center: data.coordinate, zoom: 15)
            )
            .ignoresSafeArea(edges: .bottom)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Where '\(displayTerm)' began")
                        .font(Constants.Typography.heading)
                        .foregroundColor(.ink)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.stone)
                }
            }
        }
    }
}
```

- [ ] **Step 6: Wire the card taps**

1. `ThreadsCardSection.swift` — add the handler property and replace `chip(_:)`:

```swift
    let model: ThreadsCardModel
    var onThemeTap: ((ThreadsCardTheme) -> Void)?
```

```swift
    private func chip(_ theme: ThreadsCardTheme) -> some View {
        Button {
            onThemeTap?(theme)
        } label: {
            VStack(spacing: 2) {
                Text(theme.displayTerm)
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink)
                if let note = theme.statusNote {
                    Text(note)
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(Capsule().fill(Color.moss.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .disabled(onThemeTap == nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            theme.statusNote.map { "\(theme.displayTerm), \($0)" } ?? theme.displayTerm
        )
        .accessibilityHint(onThemeTap == nil ? "" : "Double tap to view history")
    }
```

2. `WalkSummaryView.swift` — add `@State var selectedCardTheme: ThreadsCardTheme?` and, after the existing `.sheet(isPresented: $showPrompts)` block:

```swift
            .sheet(item: $selectedCardTheme) { theme in
                NavigationStack {
                    ThreadHistoryView(displayTerm: theme.displayTerm, cohortLemmas: theme.lemmas)
                }
            }
```

3. `WalkSummaryView+Threads.swift` — the slot passes the handler:

```swift
    @ViewBuilder
    var threadsCardSlot: some View {
        if showsThreadsCard, let threadsCardModel {
            ThreadsCardSection(
                model: threadsCardModel,
                onThemeTap: { selectedCardTheme = $0 }
            )
        }
    }
```

- [ ] **Step 7: Build + full UnitTests suite — PASS** (baseline 1269 + 46). Then `swiftlint lint Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift` — zero errors (the ~669/750 type_body_length headroom check, per Global Constraints). Commit.

```bash
git add Pilgrim/Models/Threads/ThreadHistoryModel.swift Pilgrim/Scenes/WalkSummary/ThreadHistoryView.swift Pilgrim/Scenes/WalkSummary/ThreadsCardSection.swift Pilgrim/Scenes/WalkSummary/WalkSummaryView+Threads.swift Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift UnitTests/ThreadHistoryModelTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(threads): thread view — the walker's own words, newest first, back to where it began"
```

---

### Task 5: Let this one go

**Files:**
- Create: `Pilgrim/Models/Threads/ReleasedThreadsCopy.swift`
- Create: `Pilgrim/Scenes/Settings/ReleasedThreadsListView.swift`
- Modify: `Pilgrim/Scenes/WalkSummary/ThreadsCardSection.swift` (long-press, VoiceOver action, confirm, caption)
- Modify: `Pilgrim/Scenes/WalkSummary/ThreadHistoryView.swift` (term header with long-press + confirm, pops on release)
- Modify: `Pilgrim/Scenes/WalkSummary/WalkSummaryView+Threads.swift` (release handler, card fade-out)
- Modify: `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift` (`.onChange(of: selectedCardTheme)` reload — Step 6's parenthetical)
- Modify: `Pilgrim/Models/Preferences/UserPreferences.swift` (caption-shown flag)
- Modify: `Pilgrim/Models/Threads/ThreadsCardModel.swift` (`removing(displayTerm:from:)`)
- Modify: `Pilgrim/Scenes/Settings/SettingsCards/VoiceCard.swift` (hidden-when-empty settings row)
- Test: `UnitTests/ReleasedThreadsInteractionTests.swift`

**Interfaces:**
- Consumes: `ReleasedThreadsStore` (Task 1), `ThreadsCardTheme.lemmas` cohort (Task 3), `settingNavRow(label:)` (SettingsCardStyle.swift:74).
- Produces:
  - `ReleasedThreadsCopy` — every confirm string, centralized so card and thread view can never drift, and so Task 9's gentleness pass edits one file
  - `ThreadsCardModelBuilder.removing(displayTerm:from:) -> ThreadsCardModel?` (nil when the last theme leaves — drives the card fade-out/reflow)
  - `UserPreferences.threadsReleaseCaptionShown` — `UserPreference.Required<Bool>(key: "threadsReleaseCaptionShown", defaultValue: false)`
  - `ThreadsCardSection(model:onThemeTap:onRelease:)` with per-chip long-press + "Let this go" VoiceOver custom action + one-time caption
  - `ReleasedThreadsListView` (welcome-back confirms), surfaced from VoiceCard only when non-empty and the toggle is on

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Pilgrim

final class ReleasedThreadsInteractionTests: XCTestCase {

    func testReleaseConfirmCopy_exactStrings() {
        XCTAssertEqual(ReleasedThreadsCopy.releaseTitle("my father"), "Let 'my father' go?")
        XCTAssertEqual(ReleasedThreadsCopy.releaseMessage, "You can welcome it back anytime.")
        XCTAssertEqual(ReleasedThreadsCopy.releaseConfirm, "Let it go")
        XCTAssertEqual(ReleasedThreadsCopy.releaseCancel, "Not now")
    }

    func testWelcomeBackConfirmCopy_exactStrings() {
        XCTAssertEqual(ReleasedThreadsCopy.welcomeBackTitle("my father"), "Welcome 'my father' back?")
        XCTAssertEqual(ReleasedThreadsCopy.welcomeBackMessage, "Threads will notice it again.")
        XCTAssertEqual(ReleasedThreadsCopy.welcomeBackConfirm, "Welcome it back")
        XCTAssertEqual(ReleasedThreadsCopy.welcomeBackCancel, "Not now")
    }

    func testCaptionCopy_exactString() {
        XCTAssertEqual(ReleasedThreadsCopy.caption, "long-press a theme to let it go")
    }

    func testVoiceOverActionName_exactString() {
        XCTAssertEqual(ReleasedThreadsCopy.voiceOverActionName, "Let this go")
    }

    private func model(terms: [String]) -> ThreadsCardModel {
        ThreadsCardModel(
            themes: terms.map { ThreadsCardTheme(displayTerm: $0, lemmas: [$0], statusNote: nil) },
            textureLine: nil,
            insightWords: []
        )
    }

    func testRemoving_dropsOnlyTheReleasedCohort() {
        let after = ThreadsCardModelBuilder.removing(displayTerm: "the move", from: model(terms: ["the move", "father"]))
        XCTAssertEqual(after?.themes.map(\.displayTerm), ["father"])
    }

    func testRemoving_lastThemeCollapsesTheCard() {
        XCTAssertNil(ThreadsCardModelBuilder.removing(displayTerm: "father", from: model(terms: ["father"])),
                     "an emptied card fades out and the summary reflows to its no-card state")
    }
}
```

- [ ] **Step 2: Run to verify failure** (`-only-testing:UnitTests/ReleasedThreadsInteractionTests`). Expected: FAIL — `ReleasedThreadsCopy` doesn't exist.

- [ ] **Step 3: Implement the copy and the model removal**

`Pilgrim/Models/Threads/ReleasedThreadsCopy.swift`:

```swift
import Foundation

/// Every release/welcome-back string in one place: the card and the thread
/// view can never drift apart, and the pre-release gentleness pass (Task 9)
/// edits one file. The confirm leads with reversibility by design.
enum ReleasedThreadsCopy {

    static func releaseTitle(_ term: String) -> String { "Let '\(term)' go?" }
    static let releaseMessage = "You can welcome it back anytime."
    static let releaseConfirm = "Let it go"
    static let releaseCancel = "Not now"

    static func welcomeBackTitle(_ term: String) -> String { "Welcome '\(term)' back?" }
    static let welcomeBackMessage = "Threads will notice it again."
    static let welcomeBackConfirm = "Welcome it back"
    static let welcomeBackCancel = "Not now"

    static let caption = "long-press a theme to let it go"
    static let voiceOverActionName = "Let this go"
}
```

Append to `ThreadsCardModelBuilder` in `ThreadsCardModel.swift`:

```swift
    /// Local, animatable card update after a release — the stores were
    /// already told; this keeps the on-screen card honest without a reload.
    static func removing(displayTerm: String, from model: ThreadsCardModel?) -> ThreadsCardModel? {
        guard let model else { return nil }
        let remaining = model.themes.filter { $0.displayTerm != displayTerm }
        guard !remaining.isEmpty else { return nil }
        return ThreadsCardModel(
            themes: remaining,
            textureLine: model.textureLine,
            insightWords: model.insightWords
        )
    }
```

In `UserPreferences.swift`, below `threadsAfterWalks` (line 95):

```swift
    static let threadsReleaseCaptionShown = UserPreference.Required<Bool>(key: "threadsReleaseCaptionShown", defaultValue: false)
```

- [ ] **Step 4: Run the tests — PASS** (`-only-testing:UnitTests/ReleasedThreadsInteractionTests`, expected 6 tests).

- [ ] **Step 5: Wire the card**

`ThreadsCardSection.swift` — add the release handler, confirm state, caption, and gesture/action parity. The struct's stored properties and body become:

```swift
struct ThreadsCardSection: View {

    let model: ThreadsCardModel
    var onThemeTap: ((ThreadsCardTheme) -> Void)?
    var onRelease: ((ThreadsCardTheme) -> Void)?

    @State private var showInsightWords = false
    @State private var themeToRelease: ThreadsCardTheme?
    @State private var captionDismissed = UserPreferences.threadsReleaseCaptionShown.value

    var body: some View {
        VStack(spacing: Constants.UI.Padding.small) {
            Text("What walked with you")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
            FlowLayout(spacing: Constants.UI.Padding.small) {
                ForEach(model.themes) { theme in
                    chip(theme)
                }
            }
            if let texture = model.textureLine {
                textureLine(texture)
            }
            if onRelease != nil, !captionDismissed {
                captionRow
            }
        }
        .padding(Constants.UI.Padding.normal)
        .frame(maxWidth: .infinity)
        .background(Color.parchmentSecondary)
        .cornerRadius(Constants.UI.CornerRadius.normal)
        .alert(
            themeToRelease.map { ReleasedThreadsCopy.releaseTitle($0.displayTerm) } ?? "",
            isPresented: Binding(
                get: { themeToRelease != nil },
                set: { if !$0 { themeToRelease = nil } }
            ),
            presenting: themeToRelease
        ) { theme in
            Button(ReleasedThreadsCopy.releaseConfirm) {
                onRelease?(theme)
                themeToRelease = nil
            }
            Button(ReleasedThreadsCopy.releaseCancel, role: .cancel) {
                themeToRelease = nil
            }
        } message: { _ in
            Text(ReleasedThreadsCopy.releaseMessage)
        }
    }

    private var captionRow: some View {
        HStack(spacing: Constants.UI.Padding.xs) {
            Text(ReleasedThreadsCopy.caption)
                .font(Constants.Typography.caption)
                .foregroundColor(.fog.opacity(0.7))
            Button {
                UserPreferences.threadsReleaseCaptionShown.value = true
                captionDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(.fog)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Dismiss hint")
        }
    }
```

and `chip(_:)` is replaced wholesale — the Task 4 `Button` wrapper goes away. A long-press gesture attached to a `Button` competes with the Button's own tap recognizer and one of the two stops firing reliably; no file in this repo combines them, and the house pattern for tap + long-press coexistence is `PhotoCarouselView.swift:122-128` — `.contentShape(Rectangle())` + `.onTapGesture` + `.onLongPressGesture(minimumDuration: 0.4)` on a plain view (`MeditationView.swift:62-69` is the other precedent). VoiceOver parity is unaffected: custom accessibility actions bypass gesture recognizers entirely, and `.isButton` restores the trait the `Button` used to convey:

```swift
    private func chip(_ theme: ThreadsCardTheme) -> some View {
        VStack(spacing: 2) {
            Text(theme.displayTerm)
                .font(Constants.Typography.body)
                .foregroundColor(.ink)
            if let note = theme.statusNote {
                Text(note)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(Capsule().fill(Color.moss.opacity(0.1)))
        .contentShape(Rectangle())
        .onTapGesture {
            onThemeTap?(theme)
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            guard onRelease != nil else { return }
            themeToRelease = theme
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(
            theme.statusNote.map { "\(theme.displayTerm), \($0)" } ?? theme.displayTerm
        )
        .accessibilityHint(onThemeTap == nil ? "" : "Double tap to view history")
        .accessibilityAction(named: ReleasedThreadsCopy.voiceOverActionName) {
            guard onRelease != nil else { return }
            themeToRelease = theme
        }
    }
```

`WalkSummaryView+Threads.swift` — the slot passes both handlers and the release fades/reflows:

```swift
    @ViewBuilder
    var threadsCardSlot: some View {
        if showsThreadsCard, let threadsCardModel {
            ThreadsCardSection(
                model: threadsCardModel,
                onThemeTap: { selectedCardTheme = $0 },
                onRelease: { releaseTheme($0) }
            )
            .transition(.opacity)
        }
    }

    func releaseTheme(_ theme: ThreadsCardTheme) {
        ReleasedThreadsStore.shared.release(displayTerm: theme.displayTerm, lemmas: theme.lemmas)
        withAnimation(.easeOut(duration: 0.4)) {
            threadsCardModel = ThreadsCardModelBuilder.removing(
                displayTerm: theme.displayTerm, from: threadsCardModel
            )
        }
    }
```

- [ ] **Step 6: Wire the thread view**

`ThreadHistoryView.swift` — add `@Environment(\.dismiss) private var dismiss` and `@State private var showReleaseConfirm = false` to the struct, insert a term header as the first child of the ScrollView's VStack, and pop on release (the spec's mid-view transition):

```swift
                termHeader
```

```swift
    private var termHeader: some View {
        Text(displayTerm)
            .font(Constants.Typography.displayMedium)
            .foregroundColor(.ink)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .onLongPressGesture { showReleaseConfirm = true }
            .accessibilityAction(named: ReleasedThreadsCopy.voiceOverActionName) {
                showReleaseConfirm = true
            }
    }
```

(The `.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())` pair matches every other interactive row in this plan — a transparent `Text` alone hit-tests only its glyph bounding box, so without it the long-press target would be narrower and shorter than the visual row and under the 44 pt minimum.)

and on the ScrollView's modifier chain, next to the existing sheets:

```swift
        .alert(
            ReleasedThreadsCopy.releaseTitle(displayTerm),
            isPresented: $showReleaseConfirm
        ) {
            Button(ReleasedThreadsCopy.releaseConfirm) {
                ReleasedThreadsStore.shared.release(displayTerm: displayTerm, lemmas: cohortLemmas)
                dismiss()
            }
            Button(ReleasedThreadsCopy.releaseCancel, role: .cancel) {}
        } message: {
            Text(ReleasedThreadsCopy.releaseMessage)
        }
```

(When the thread view was pushed from the summary card, the summary's card is stale after this pop — the `.task(id:)` reload doesn't refire on dismiss, so ALSO add `.onChange(of: selectedCardTheme) { _, newValue in if newValue == nil { Task { await loadThreadsCard() } } }` to the WalkSummaryView modifier chain, right after the Task 4 sheet. A release made inside the thread view is then reflected the moment the sheet closes. Task 7 extends this same pattern to the recap sheet path with `.onChange(of: recapSheet)`, and re-keys the recap view's own load on the released token — the release lifecycle stays consistent across all three surfaces.)

- [ ] **Step 7: The settings list**

`Pilgrim/Scenes/Settings/ReleasedThreadsListView.swift`:

```swift
import SwiftUI

/// Released threads, newest first — tapping an entry welcomes the cohort
/// back. The row that leads here is hidden when this list would be empty.
struct ReleasedThreadsListView: View {

    @State private var entries: [ReleasedThread] = ReleasedThreadsStore.shared.all
    @State private var entryToRestore: ReleasedThread?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    var body: some View {
        List {
            ForEach(entries, id: \.displayTerm) { entry in
                Button {
                    entryToRestore = entry
                } label: {
                    HStack {
                        Text(entry.displayTerm)
                            .font(Constants.Typography.body)
                            .foregroundColor(.ink)
                        Spacer()
                        Text(Self.dateFormatter.string(from: entry.releasedAt))
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint("Double tap to welcome this thread back")
                .listRowBackground(Color.parchmentSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .canvasBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Released threads")
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
            }
        }
        .alert(
            entryToRestore.map { ReleasedThreadsCopy.welcomeBackTitle($0.displayTerm) } ?? "",
            isPresented: Binding(
                get: { entryToRestore != nil },
                set: { if !$0 { entryToRestore = nil } }
            ),
            presenting: entryToRestore
        ) { entry in
            Button(ReleasedThreadsCopy.welcomeBackConfirm) {
                ReleasedThreadsStore.shared.welcomeBack(displayTerm: entry.displayTerm)
                entries = ReleasedThreadsStore.shared.all
                entryToRestore = nil
            }
            Button(ReleasedThreadsCopy.welcomeBackCancel, role: .cancel) {
                entryToRestore = nil
            }
        } message: { _ in
            Text(ReleasedThreadsCopy.welcomeBackMessage)
        }
    }
}
```

`VoiceCard.swift` — add `@State private var hasReleasedThreads = !ReleasedThreadsStore.shared.isEmpty` (line 9, with the other state), refresh it in `.onAppear` (`hasReleasedThreads = !ReleasedThreadsStore.shared.isEmpty`), and add the row directly below the Thought Threads `settingToggle` block:

```swift
            if threadsAfterWalks && hasReleasedThreads {
                NavigationLink {
                    ReleasedThreadsListView()
                } label: {
                    settingNavRow(label: "Released threads")
                }
            }
```

- [ ] **Step 8: Build + full UnitTests suite — PASS** (baseline 1269 + 52). Commit.

```bash
git add Pilgrim/Models/Threads/ReleasedThreadsCopy.swift Pilgrim/Models/Threads/ThreadsCardModel.swift Pilgrim/Models/Preferences/UserPreferences.swift Pilgrim/Scenes/WalkSummary/ThreadsCardSection.swift Pilgrim/Scenes/WalkSummary/ThreadHistoryView.swift Pilgrim/Scenes/WalkSummary/WalkSummaryView+Threads.swift Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift Pilgrim/Scenes/Settings/ReleasedThreadsListView.swift Pilgrim/Scenes/Settings/SettingsCards/VoiceCard.swift UnitTests/ReleasedThreadsInteractionTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(threads): let this one go — reversible releases with gesture parity and a welcome back"
```

---

### Task 6: Lunation machinery — moons, boundaries, eligibility

**Files:**
- Modify: `Pilgrim/Models/LunarPhase.swift` (two constants drop `private`)
- Create: `Pilgrim/Models/Threads/LunationCalendar.swift`
- Create: `Pilgrim/Models/Threads/LunationRecapState.swift`
- Modify: `Pilgrim/Scenes/WalkSummary/ThreadsCardSection.swift` (first-card-shown marker)
- Modify: `Pilgrim/Models/Data/DataManager.swift` (`deleteAll` also clears the recap state and the caption flag — beside Task 1's `releasedThreadsStore.clear()`)
- Test: `UnitTests/LunationCalendarTests.swift`, `UnitTests/LunationRecapStateTests.swift`, extend `UnitTests/DataManagerThreadsDeletionTests.swift`

**Interfaces:**
- Consumes: `LunarPhase.synodicMonth` / `LunarPhase.knownNewMoon` (internal after this task — the same reference the phase math uses, so phase and lunation arithmetic can never disagree), `UserPreferences.threadsAfterWalks`.
- Produces (used by Task 7):
  - `struct Lunation: Equatable, Identifiable` — `{ index: Int, start: Date, end: Date, fullMoon: Date }`, `id == index`
  - `LunationCalendar.lunation(at:)` / `.lunation(containing:)` / `.mostRecentClosed(asOf:)` / `.moonName(for:in:)` (timezone-pinned month-moon name table)
  - `final class LunationRecapState` — `static let shared`; `init(defaults:)`; `firstCardShownAt`; `markFirstCardShown(now:)` (set-once); `lastActedLunationIndex`; `markActedOn(_:)` (monotonic — opening an older moon from Past recaps never regresses the index); `invitation(forWalkDated:now:) -> Lunation?` (ignores acted indices beyond the current lunation — a forward-set clock cannot silence months of real invitations); `clear()` (Delete All hook — the first-card gate re-arms exactly as a reinstall would)

- [ ] **Step 1: Write the failing tests**

`UnitTests/LunationCalendarTests.swift`:

```swift
import XCTest
@testable import Pilgrim

final class LunationCalendarTests: XCTestCase {

    func testLunation_boundariesAreContiguous() {
        let lunation = LunationCalendar.lunation(at: 300)
        XCTAssertEqual(LunationCalendar.lunation(containing: lunation.start).index, 300)
        XCTAssertEqual(LunationCalendar.lunation(containing: lunation.end.addingTimeInterval(-1)).index, 300)
        XCTAssertEqual(LunationCalendar.lunation(containing: lunation.end).index, 301,
                       "the close instant belongs to the next lunation")
        XCTAssertEqual(lunation.end, LunationCalendar.lunation(at: 301).start)
    }

    func testMostRecentClosed_isThePreviousLunation() {
        let lunation = LunationCalendar.lunation(at: 300)
        let closed = LunationCalendar.mostRecentClosed(asOf: lunation.start.addingTimeInterval(86400))
        XCTAssertEqual(closed.index, 299)
    }

    func testFullMoon_isTheMidpoint() {
        let lunation = LunationCalendar.lunation(at: 300)
        XCTAssertEqual(
            lunation.fullMoon.timeIntervalSince(lunation.start),
            lunation.end.timeIntervalSince(lunation.fullMoon),
            accuracy: 1
        )
    }

    func testMoonName_derivesFromFullMoonMonthInTimezone() {
        let nearMonthEdge = Lunation(
            index: 0,
            start: DateFactory.makeDate(2024, 8, 17, 11, 0, 0),
            end: DateFactory.makeDate(2024, 9, 15, 23, 0, 0),
            fullMoon: DateFactory.makeDate(2024, 8, 31, 23, 0, 0)
        )
        XCTAssertEqual(
            LunationCalendar.moonName(for: nearMonthEdge, in: TimeZone(identifier: "UTC")!),
            "Sturgeon Moon"
        )
        XCTAssertEqual(
            LunationCalendar.moonName(for: nearMonthEdge, in: TimeZone(identifier: "Pacific/Auckland")!),
            "Corn Moon",
            "the same instant is already September in Auckland — the name follows the device's timezone"
        )
    }

    func testMoonName_allTwelveMonthsCovered() {
        for month in 1...12 {
            let lunation = Lunation(
                index: 0,
                start: DateFactory.makeDate(2024, month, 1),
                end: DateFactory.makeDate(2024, month, 29),
                fullMoon: DateFactory.makeDate(2024, month, 15, 12, 0, 0)
            )
            let name = LunationCalendar.moonName(for: lunation, in: TimeZone(identifier: "UTC")!)
            XCTAssertTrue(name.hasSuffix("Moon"))
        }
    }
}
```

`UnitTests/LunationRecapStateTests.swift`:

```swift
import XCTest
@testable import Pilgrim

final class LunationRecapStateTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var state: LunationRecapState!
    private var savedToggle = true

    /// A fixed lunation grid: `closed` = lunation 300, `now` one day after
    /// it closed, `walkAfter` a walk dated after the boundary.
    private let closed = LunationCalendar.lunation(at: 300)
    private var now: Date { closed.end.addingTimeInterval(86400) }
    private var walkAfter: Date { closed.end.addingTimeInterval(3600) }

    override func setUpWithError() throws {
        suiteName = "LunationRecapStateTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        state = LunationRecapState(defaults: defaults)
        savedToggle = UserPreferences.threadsAfterWalks.value
        UserPreferences.threadsAfterWalks.value = true
    }

    override func tearDownWithError() throws {
        UserPreferences.threadsAfterWalks.value = savedToggle
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func showFirstCard(before boundary: Date) {
        state.markFirstCardShown(now: boundary.addingTimeInterval(-10 * 86400))
    }

    func testInvitation_requiresFirstCardShown() {
        XCTAssertNil(state.invitation(forWalkDated: walkAfter, now: now),
                     "the recap must never be a walker's first contact with the feature")
        showFirstCard(before: closed.end)
        XCTAssertNotNil(state.invitation(forWalkDated: walkAfter, now: now))
    }

    func testInvitation_boundaryInsideBackfilledHistoryNeverInvites() {
        state.markFirstCardShown(now: closed.end.addingTimeInterval(3600))
        XCTAssertNil(state.invitation(forWalkDated: walkAfter, now: now),
                     "a lunation that closed before the first card belongs to backfilled history")
    }

    func testInvitation_walkDatedBeforeBoundary_neverInvites() {
        showFirstCard(before: closed.end)
        XCTAssertNil(state.invitation(
            forWalkDated: closed.end.addingTimeInterval(-3600), now: now
        ), "old summaries read the same whenever opened")
    }

    func testInvitation_reEvaluatesUntilActedOn() {
        showFirstCard(before: closed.end)
        XCTAssertNotNil(state.invitation(forWalkDated: walkAfter, now: now))
        XCTAssertNotNil(state.invitation(forWalkDated: walkAfter, now: now),
                        "the flag records acted-on, not first opportunity — pending transcriptions don't cost the month")
        state.markActedOn(closed)
        XCTAssertNil(state.invitation(forWalkDated: walkAfter, now: now))
    }

    func testInvitation_nextLunationSupersedes() {
        showFirstCard(before: closed.end)
        state.markActedOn(closed)
        let next = LunationCalendar.lunation(at: 301)
        let laterNow = next.end.addingTimeInterval(86400)
        let laterWalk = next.end.addingTimeInterval(3600)
        XCTAssertEqual(state.invitation(forWalkDated: laterWalk, now: laterNow)?.index, 301,
                       "acting on one moon never silences the next")
    }

    func testInvitation_onlyTheMostRecentClosedLunationInvites() {
        showFirstCard(before: closed.end)
        let next = LunationCalendar.lunation(at: 301)
        let laterNow = next.end.addingTimeInterval(86400)
        XCTAssertEqual(state.invitation(forWalkDated: walkAfter, now: laterNow), nil,
                       "once the next lunation closes, a walk dated inside the previous one no longer invites — Past recaps keeps it reachable")
    }

    func testMarkFirstCardShown_setOnce() {
        let first = DateFactory.makeDate(2026, 8, 1, 9, 0, 0)
        state.markFirstCardShown(now: first)
        state.markFirstCardShown(now: first.addingTimeInterval(86400))
        XCTAssertEqual(state.firstCardShownAt, first)
    }

    func testInvitation_toggleOffMeansOff() {
        showFirstCard(before: closed.end)
        UserPreferences.threadsAfterWalks.value = false
        XCTAssertNil(state.invitation(forWalkDated: walkAfter, now: now))
    }

    func testInvitation_futureActedIndexIsIgnored() {
        showFirstCard(before: closed.end)
        state.markActedOn(LunationCalendar.lunation(at: 305))
        XCTAssertEqual(state.invitation(forWalkDated: walkAfter, now: now)?.index, 300,
                       "an acted index from a forward-set clock is ignored — it cannot silence months of real invitations")
    }

    func testMarkActedOn_isMonotonic() {
        state.markActedOn(closed)
        state.markActedOn(LunationCalendar.lunation(at: 298))
        XCTAssertEqual(state.lastActedLunationIndex, 300,
                       "opening an older moon from Past recaps never regresses the acted index")
    }
}
```

Append to `UnitTests/DataManagerThreadsDeletionTests.swift` (beside Task 1's release-clearing test — Delete All must reset the recap bookkeeping exactly as a reinstall would; a surviving `firstCardShownAt` resurrects pre-wipe moons as ghost Past-recap rows and turns the first post-wipe walk into a junk "no recorded words" invitation):

```swift
    func testDeleteAll_clearsRecapStateAndCaptionFlag() {
        LunationRecapState.shared.clear()
        LunationRecapState.shared.markFirstCardShown()
        LunationRecapState.shared.markActedOn(LunationCalendar.lunation(at: 300))
        UserPreferences.threadsReleaseCaptionShown.value = true

        let deleted = expectation(description: "deleted all")
        DataManager.deleteAll { success, _ in
            XCTAssertTrue(success)
            deleted.fulfill()
        }
        wait(for: [deleted], timeout: 5)
        XCTAssertNil(LunationRecapState.shared.firstCardShownAt,
                     "the first-card gate re-arms — a wipe is a fresh start, like a reinstall")
        XCTAssertNil(LunationRecapState.shared.lastActedLunationIndex)
        XCTAssertFalse(UserPreferences.threadsReleaseCaptionShown.value)
    }
```

- [ ] **Step 2: Run to verify failure** (`-only-testing:UnitTests/LunationCalendarTests -only-testing:UnitTests/LunationRecapStateTests`). Expected: FAIL — types don't exist.

- [ ] **Step 3: Implement**

`LunarPhase.swift` — the two constants the calendar needs drop `private` (values unchanged):

```swift
    static let synodicMonth = 29.53058770576
    static let knownNewMoon = DateComponents(
        calendar: .init(identifier: .gregorian),
        timeZone: TimeZone(identifier: "UTC"),
        year: 2000, month: 1, day: 6, hour: 18, minute: 14
    ).date!
```

`Pilgrim/Models/Threads/LunationCalendar.swift`:

```swift
import Foundation

/// One synodic month: the stretch between two new-moon instants, indexed
/// from the same 2000-01-06 reference LunarPhase uses, so phase math and
/// lunation arithmetic can never disagree.
struct Lunation: Equatable, Identifiable {
    let index: Int
    let start: Date
    let end: Date
    let fullMoon: Date

    var id: Int { index }
}

enum LunationCalendar {

    private static let lunationLength = LunarPhase.synodicMonth * 86400

    /// Every boundary Date is minted by this one expression, so
    /// `lunation(at: n).end == lunation(at: n + 1).start` holds exactly —
    /// never `start + length`, which drifts by a ulp and splits boundaries.
    private static func newMoonDate(at index: Int) -> Date {
        LunarPhase.knownNewMoon.addingTimeInterval(Double(index) * lunationLength)
    }

    static func lunation(at index: Int) -> Lunation {
        Lunation(
            index: index,
            start: newMoonDate(at: index),
            end: newMoonDate(at: index + 1),
            fullMoon: newMoonDate(at: index).addingTimeInterval(lunationLength / 2)
        )
    }

    /// The floor division can land one off at exact boundary instants
    /// (Double round-off) — the two correction guards make the close
    /// instant belong to the next lunation, deterministically.
    static func lunation(containing date: Date) -> Lunation {
        var index = Int(floor(date.timeIntervalSince(LunarPhase.knownNewMoon) / lunationLength))
        if date >= newMoonDate(at: index + 1) { index += 1 }
        if date < newMoonDate(at: index) { index -= 1 }
        return lunation(at: index)
    }

    /// The lunation that most recently closed — the only moon that may
    /// invite. Once the next one closes, the previous moves to Past recaps.
    static func mostRecentClosed(asOf date: Date) -> Lunation {
        lunation(at: lunation(containing: date).index - 1)
    }

    /// Traditional full-moon month names, January through December.
    static let monthMoonNames = [
        "Wolf Moon", "Snow Moon", "Worm Moon", "Pink Moon",
        "Flower Moon", "Strawberry Moon", "Buck Moon", "Sturgeon Moon",
        "Corn Moon", "Hunter's Moon", "Beaver Moon", "Cold Moon"
    ]

    /// The moon's name derives from the calendar month of its full-moon
    /// instant in the given timezone (spec: timezone moon naming) — the
    /// same set moon can honestly carry different names in Lisbon and
    /// Auckland, because the walker's sky is the one that counts.
    static func moonName(for lunation: Lunation, in timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return monthMoonNames[calendar.component(.month, from: lunation.fullMoon) - 1]
    }
}
```

`Pilgrim/Models/Threads/LunationRecapState.swift`:

```swift
import Foundation

/// Persistence + eligibility for the lunation recap invitation. The acted
/// flag records "acted on", not "first opportunity" — pending
/// transcriptions don't cost the walker the month. Ephemeral by design:
/// loss on reinstall is accepted (unlike the released set, these are
/// bookkeeping, not walker decisions).
final class LunationRecapState {

    static let shared = LunationRecapState(defaults: .standard)

    static let firstCardShownKey = "threadsFirstCardShownAt"
    static let lastActedKey = "threadsRecapLastActedLunation"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var firstCardShownAt: Date? {
        guard let epoch = defaults.object(forKey: Self.firstCardShownKey) as? Double else { return nil }
        return Date(timeIntervalSince1970: epoch)
    }

    /// Set once, on the first per-walk card the walker ever sees — the card
    /// shows its work one walk at a time before any aggregate speaks.
    func markFirstCardShown(now: Date = Date()) {
        guard firstCardShownAt == nil else { return }
        defaults.set(now.timeIntervalSince1970, forKey: Self.firstCardShownKey)
    }

    var lastActedLunationIndex: Int? {
        defaults.object(forKey: Self.lastActedKey) as? Int
    }

    /// Monotonic: opening an older moon from Past recaps also marks it
    /// acted-on, and must never regress the index and resurrect an
    /// already-dismissed invitation.
    func markActedOn(_ lunation: Lunation) {
        defaults.set(max(lunation.index, lastActedLunationIndex ?? Int.min), forKey: Self.lastActedKey)
    }

    /// The lunation whose set moon may invite from this walk's summary, or
    /// nil. Re-evaluates on every qualifying post-boundary summary until the
    /// invitation is tapped or the next lunation closes.
    func invitation(forWalkDated walkDate: Date, now: Date = Date()) -> Lunation? {
        guard UserPreferences.threadsAfterWalks.value else { return nil }
        guard let firstShown = firstCardShownAt else { return nil }
        let closed = LunationCalendar.mostRecentClosed(asOf: now)
        guard closed.end > firstShown else { return nil }
        // An acted index beyond the current lunation can only come from a
        // forward-set clock (the manual smoke does exactly this) — ignore
        // it, so months of real invitations aren't silenced after the
        // clock returns.
        let currentIndex = LunationCalendar.lunation(containing: now).index
        let lastActed = lastActedLunationIndex.flatMap { $0 > currentIndex ? nil : $0 }
        guard closed.index > (lastActed ?? Int.min) else { return nil }
        guard walkDate >= closed.end else { return nil }
        return closed
    }

    /// Delete All Data hook — the first-card gate re-arms exactly as a
    /// reinstall would. Without this, a surviving firstCardShownAt
    /// resurrects pre-wipe moons as ghost Past-recap rows and turns the
    /// first post-wipe walk into a junk "no recorded words" invitation.
    func clear() {
        defaults.removeObject(forKey: Self.firstCardShownKey)
        defaults.removeObject(forKey: Self.lastActedKey)
    }
}
```

`DataManager.swift` — in `deleteAll`'s `.success` branch, directly after Task 1's `releasedThreadsStore.clear()` line (same transaction-success discipline — recap bookkeeping resets only once the database wipe committed):

```swift
                LunationRecapState.shared.clear()
                UserPreferences.threadsReleaseCaptionShown.value = false
```

`ThreadsCardSection.swift` — the card records the walker's first contact. On the outermost VStack's modifier chain (after `.cornerRadius`):

```swift
        .onAppear {
            LunationRecapState.shared.markFirstCardShown()
        }
```

- [ ] **Step 4: Run the three touched classes — PASS** (5 + 10 tests, plus the new deleteAll recap-clearing test)

Run: `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/LunationCalendarTests -only-testing:UnitTests/LunationRecapStateTests -only-testing:UnitTests/DataManagerThreadsDeletionTests 2>&1 | tail -20`

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/LunarPhase.swift Pilgrim/Models/Threads/LunationCalendar.swift Pilgrim/Models/Threads/LunationRecapState.swift Pilgrim/Scenes/WalkSummary/ThreadsCardSection.swift Pilgrim/Models/Data/DataManager.swift UnitTests/LunationCalendarTests.swift UnitTests/LunationRecapStateTests.swift UnitTests/DataManagerThreadsDeletionTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(threads): lunation machinery — timezone-named moons, first-card gate, acted-on invitations, wipe re-arms the gate"
```

---

### Task 7: The lunation recap — sheet, invitation row, past recaps

**Files:**
- Create: `Pilgrim/Models/Threads/LunationRecapModel.swift`
- Create: `Pilgrim/Scenes/WalkSummary/LunationRecapView.swift`
- Create: `Pilgrim/Scenes/Settings/PastRecapsListView.swift`
- Modify: `Pilgrim/Models/Data/DataManager+VoiceRecording.swift` (`voiceRecordingPaceIndex()` next to `voiceRecordingWalkIndex()` — that is the file the walk-index/snapshot helpers live in, NOT DataManager.swift)
- Modify: `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift` (two `@State`s, one onAppear line, one `.sheet`)
- Modify: `Pilgrim/Scenes/WalkSummary/WalkSummaryView+Threads.swift` (invitation row above the card)
- Modify: `Pilgrim/Scenes/Settings/SettingsCards/VoiceCard.swift` (Past recaps row)
- Test: `UnitTests/LunationRecapModelTests.swift`

**Interfaces:**
- Consumes: Tasks 2, 3 (`ThreadsTexture`), 6; `ThreadHistoryView` (Task 4) for theme tap-through; `DataManager.voiceRecordingWalkIndex()`.
- Produces:
  - `struct LunationRecapTheme: Equatable, Identifiable, Hashable` — `{ displayTerm, lemmas, walkCount, isNewThisMoon }`
  - `struct LunationRecapModel: Equatable` — `{ moonName, walkCount, themes, textureLine, quietLine }`
  - `LunationRecapCopy.themeLine(term:walkCount:totalWalks:)` ("in N of M walks" — structurally distinct from the card's ordinal copy by design), `.headline(walkCount:)` ("N walks with recorded words this moon" — the claim is scoped to analyzed-transcript walks so it never reads as the journal's walk total disagreeing), `.newThisMoon`, `.nothingHeld`, `.noWords`, `.invitation(moonName:)`
  - `LunationRecapModelBuilder.model(lunation:moonName:contexts:walkIndex:paceByRecording:released:backfillComplete:)` (pure, live-computed at sheet open)
  - `@MainActor DataManager.voiceRecordingPaceIndex() -> [UUID: Double]` — a two-column `queryAttributes` fetch mirroring its neighbors in `DataManager+VoiceRecording.swift` (verify the attribute name `_wordsPerMinute` against PilgrimV7.swift:241 — it is `Value.Optional<Double>("wordsPerMinute")`)
  - `LunationRecapView(lunation:)` sheet; `PastRecapsListView` + `PastRecapsListView.closedLunations(now:state:)`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Pilgrim

final class LunationRecapModelTests: XCTestCase {

    private let lunation = LunationCalendar.lunation(at: 300)

    private func context(_ uuid: UUID, lemma: String?, displayTerm: String? = nil, insight: Int = 0) -> TranscriptContext {
        TranscriptContext(
            schemaVersion: 1, recordingUUID: uuid, transcriptHash: "h",
            languageCode: "en", wordCount: 200,
            themes: lemma.map { [Theme(
                lemma: $0, displayTerm: displayTerm ?? $0, mentionCount: 3, salience: 0.015,
                mentions: [ThemeMention(start: 0, length: 4)]
            )] } ?? [],
            markers: MarkerPack(
                wordCount: 200, absolutistCount: 0, firstPersonCount: 0,
                insightCount: insight, causationCount: 0, discrepancyCount: 0,
                futureCount: 0, pastCount: 0, sentiment: nil
            )
        )
    }

    private func build(
        contexts: [TranscriptContext],
        walkIndex: [UUID: (walkUUID: UUID, date: Date)],
        paces: [UUID: Double] = [:],
        released: Set<String> = [],
        backfillComplete: Bool = true
    ) -> LunationRecapModel {
        LunationRecapModelBuilder.model(
            lunation: lunation, moonName: "Sturgeon Moon",
            contexts: contexts, walkIndex: walkIndex,
            paceByRecording: paces, released: released,
            backfillComplete: backfillComplete
        )
    }

    /// Three analyzed walks inside the moon; "move" spoken in two of them.
    private func fixture() -> (contexts: [TranscriptContext], walkIndex: [UUID: (walkUUID: UUID, date: Date)]) {
        let recs = [UUID(), UUID(), UUID()]
        let walks = [UUID(), UUID(), UUID()]
        let contexts = [
            context(recs[0], lemma: "move"),
            context(recs[1], lemma: "move"),
            context(recs[2], lemma: nil)
        ]
        var walkIndex: [UUID: (walkUUID: UUID, date: Date)] = [:]
        for (offset, rec) in recs.enumerated() {
            walkIndex[rec] = (walks[offset], lunation.start.addingTimeInterval(Double(offset + 1) * 86400))
        }
        return (contexts, walkIndex)
    }

    func testModel_countsWalksAndThemes() {
        let (contexts, walkIndex) = fixture()
        let model = build(contexts: contexts, walkIndex: walkIndex)
        XCTAssertEqual(model.walkCount, 3)
        XCTAssertEqual(model.themes.map(\.displayTerm), ["move"])
        XCTAssertEqual(model.themes.first?.walkCount, 2)
        XCTAssertNil(model.quietLine)
    }

    func testThemeLine_countCopyPinned() {
        XCTAssertEqual(
            LunationRecapCopy.themeLine(term: "the move", walkCount: 6, totalWalks: 9),
            "'the move' — walked with you in 6 of 9 walks"
        )
        XCTAssertEqual(
            LunationRecapCopy.themeLine(term: "father", walkCount: 1, totalWalks: 1),
            "'father' — walked with you in 1 of 1 walks",
            "a single-walk moon still uses count copy — spec sparse state"
        )
    }

    func testScopeDivergence_recapAndCardPhrasingsAreStructurallyDistinct() {
        let recap = LunationRecapCopy.themeLine(term: "move", walkCount: 3, totalWalks: 4)
        let card = ThreadsCardCopy.statusNote(for: .recurring(walksInWindow: 3))!
        XCTAssertTrue(recap.contains("walked with you in"))
        XCTAssertFalse(card.contains("walked with you in"))
        XCTAssertTrue(card.hasSuffix("walk now"),
                      "lunation counts vs trailing-window ordinals must never read as the same metric disagreeing")
    }

    func testNewThisMoon_gatedOnBackfill() {
        let (contexts, walkIndex) = fixture()
        XCTAssertEqual(build(contexts: contexts, walkIndex: walkIndex).themes.first?.isNewThisMoon, true)
        XCTAssertEqual(
            build(contexts: contexts, walkIndex: walkIndex, backfillComplete: false).themes.first?.isNewThisMoon,
            false,
            "firsts are full-history origin claims — suppressed until backfill completes"
        )
    }

    func testNewThisMoon_falseWhenThreadPredatesTheMoon() {
        var (contexts, walkIndex) = fixture()
        let earlierRec = UUID()
        contexts.append(context(earlierRec, lemma: "move"))
        walkIndex[earlierRec] = (UUID(), lunation.start.addingTimeInterval(-10 * 86400))
        XCTAssertEqual(build(contexts: contexts, walkIndex: walkIndex).themes.first?.isNewThisMoon, false)
    }

    func testNewThisMoon_falseWhenSiblingLemmaPredatesTheMoon() {
        var (contexts, walkIndex) = fixture()
        let earlierRec = UUID()
        contexts.append(context(earlierRec, lemma: "moving", displayTerm: "move"))
        walkIndex[earlierRec] = (UUID(), lunation.start.addingTimeInterval(-10 * 86400))
        XCTAssertEqual(build(contexts: contexts, walkIndex: walkIndex).themes.first?.isNewThisMoon, false,
                       "a sibling lemma of the same display term predating the moon makes the theme returning, not new — cohorts group over ALL threads")
    }

    func testReleasedFiltering_leavesTheQuietLine() {
        let (contexts, walkIndex) = fixture()
        let model = build(contexts: contexts, walkIndex: walkIndex, released: ["move"])
        XCTAssertTrue(model.themes.isEmpty)
        XCTAssertEqual(model.walkCount, 3, "the moon's walk count stands even when nothing is named")
        XCTAssertEqual(model.quietLine, "nothing held on to name this time")
    }

    func testRecapPathRelease_rebuildDropsThemeAndLeavesQuietLine() {
        let (contexts, walkIndex) = fixture()
        XCTAssertEqual(build(contexts: contexts, walkIndex: walkIndex).themes.map(\.displayTerm), ["move"],
                       "fixture sanity — the theme is present before the release")
        let after = build(contexts: contexts, walkIndex: walkIndex, released: ["move"])
        XCTAssertTrue(after.themes.isEmpty)
        XCTAssertEqual(after.quietLine, "nothing held on to name this time",
                       "the released-token re-key rebuilds the recap the moment the thread view pops — a released theme drops out instead of dead-ending")
    }

    func testZeroAnalyzedWalks_hasItsOwnQuietLine() {
        let model = build(contexts: [], walkIndex: [:])
        XCTAssertEqual(model.walkCount, 0)
        XCTAssertEqual(model.quietLine, "no recorded words walked this moon")
    }

    func testWalksOutsideTheLunation_doNotCount() {
        let rec = UUID()
        let walkIndex = [rec: (walkUUID: UUID(), date: lunation.end.addingTimeInterval(3600))]
        let model = build(contexts: [context(rec, lemma: "move")], walkIndex: walkIndex)
        XCTAssertEqual(model.walkCount, 0, "the window is [start, end) — the close belongs to the next moon")
    }

    func testWalkCount_ignoresWalksWithoutAnalyzedWords() {
        var (contexts, walkIndex) = fixture()
        walkIndex[UUID()] = (UUID(), lunation.start.addingTimeInterval(5 * 86400))
        let model = build(contexts: contexts, walkIndex: walkIndex)
        XCTAssertEqual(model.walkCount, 3,
                       "an untranscribed recording's walk doesn't count — the headline copy scopes the claim to walks with recorded words for exactly this reason")
    }

    func testHeadline_scopedToWalksWithRecordedWords() {
        XCTAssertEqual(LunationRecapCopy.headline(walkCount: 3), "3 walks with recorded words this moon")
        XCTAssertEqual(LunationRecapCopy.headline(walkCount: 1), "1 walk with recorded words this moon",
                       "the qualifier keeps the count honest against a journal showing more walks this moon")
    }

    func testTexture_paceAndInsightFromTheMoonsRecordings() {
        let (contexts, walkIndex) = fixture()
        let insightful = contexts.map { original in
            TranscriptContext(
                schemaVersion: 1, recordingUUID: original.recordingUUID, transcriptHash: "h",
                languageCode: "en", wordCount: 200, themes: original.themes,
                markers: MarkerPack(
                    wordCount: 200, absolutistCount: 0, firstPersonCount: 0,
                    insightCount: 2, causationCount: 0, discrepancyCount: 0,
                    futureCount: 0, pastCount: 0, sentiment: nil
                )
            )
        }
        let paces = Dictionary(uniqueKeysWithValues: walkIndex.keys.map { ($0, 80.0) })
        let model = build(contexts: insightful, walkIndex: walkIndex, paces: paces)
        XCTAssertEqual(model.textureLine, "Spoken slowly, with words of insight.")
    }

    func testInvitationCopy_pinned() {
        XCTAssertEqual(
            LunationRecapCopy.invitation(moonName: "Sturgeon Moon"),
            "The Sturgeon Moon has set — see what walked with you."
        )
    }

    func testClosedLunations_boundedByFirstCard() {
        let suiteName = "PastRecapsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = LunationRecapState(defaults: defaults)
        let now = LunationCalendar.lunation(at: 303).start.addingTimeInterval(86400)

        XCTAssertTrue(PastRecapsListView.closedLunations(now: now, state: state).isEmpty,
                      "no first card, no reachable moons")

        state.markFirstCardShown(now: LunationCalendar.lunation(at: 300).start.addingTimeInterval(86400))
        XCTAssertEqual(
            PastRecapsListView.closedLunations(now: now, state: state).map(\.index),
            [302, 301, 300],
            "every moon closed since first contact, newest first — a missed line never costs the month"
        )
    }

    func testClosedLunations_boundaryEndEqualsFirstShown_excluded() {
        let suiteName = "PastRecapsBoundary-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = LunationRecapState(defaults: defaults)
        state.markFirstCardShown(now: LunationCalendar.lunation(at: 300).end)
        let now = LunationCalendar.lunation(at: 302).start.addingTimeInterval(86400)
        XCTAssertEqual(
            PastRecapsListView.closedLunations(now: now, state: state).map(\.index),
            [301],
            "a moon closing at the exact first-shown instant belongs to backfilled history — the strict `>` is deliberate and pinned"
        )
    }
}
```

- [ ] **Step 2: Run to verify failure** (`-only-testing:UnitTests/LunationRecapModelTests`). Expected: FAIL — types don't exist.

- [ ] **Step 3: Implement the model and copy**

`Pilgrim/Models/Threads/LunationRecapModel.swift`:

```swift
import Foundation

struct LunationRecapTheme: Equatable, Identifiable, Hashable {
    let displayTerm: String
    let lemmas: [String]
    let walkCount: Int
    let isNewThisMoon: Bool

    var id: String { displayTerm }
}

struct LunationRecapModel: Equatable {
    let moonName: String
    let walkCount: Int
    let themes: [LunationRecapTheme]
    let textureLine: String?
    let quietLine: String?
}

enum LunationRecapCopy {

    /// Lunation-scoped counts — deliberately a different sentence shape
    /// from the card's trailing-window ordinals ("third walk now"), so the
    /// two scopes never read as the same metric disagreeing. Always
    /// "walks", even for one (spec sparse state: "in 1 of 1 walks").
    static func themeLine(term: String, walkCount: Int, totalWalks: Int) -> String {
        "'\(term)' — walked with you in \(walkCount) of \(totalWalks) walks"
    }

    /// The headline counts only walks with analyzed transcripts, so the
    /// copy scopes the claim: a walker with fifteen journal walks and three
    /// transcribed must never read "3 walks this moon" as the journal
    /// disagreeing with itself. The zero state ("no recorded words walked
    /// this moon") already carries the same frame.
    static func headline(walkCount: Int) -> String {
        walkCount == 1
            ? "1 walk with recorded words this moon"
            : "\(walkCount) walks with recorded words this moon"
    }

    static let newThisMoon = "new this moon"
    static let nothingHeld = "nothing held on to name this time"
    static let noWords = "no recorded words walked this moon"

    static func invitation(moonName: String) -> String {
        "The \(moonName) has set — see what walked with you."
    }
}

enum LunationRecapModelBuilder {

    static let maxThemes = 6
    static let insightFloor = 3

    /// Pure and live-computed at sheet open — its counts may exceed the
    /// invitation moment's, by design. Window is [start, end): the close
    /// instant belongs to the next moon.
    static func model(
        lunation: Lunation,
        moonName: String,
        contexts: [TranscriptContext],
        walkIndex: [UUID: (walkUUID: UUID, date: Date)],
        paceByRecording: [UUID: Double],
        released: Set<String>,
        backfillComplete: Bool
    ) -> LunationRecapModel {
        let inMoon: (Date) -> Bool = { $0 >= lunation.start && $0 < lunation.end }
        let analyzed = Set(contexts.map(\.recordingUUID))
        let moonRecordings = walkIndex.filter { analyzed.contains($0.key) && inMoon($0.value.date) }
        let totalWalks = Set(moonRecordings.values.map(\.walkUUID)).count

        guard totalWalks > 0 else {
            return LunationRecapModel(
                moonName: moonName, walkCount: 0, themes: [],
                textureLine: nil, quietLine: LunationRecapCopy.noWords
            )
        }

        let threads = ThreadStore.build(contexts: contexts, walks: walkIndex, released: released)
        // Cohorts group over ALL threads first — a sibling lemma whose
        // appearances all predate the moon still joins its cohort, so
        // isNewThisMoon judges the cohort's full history (mirroring the
        // card builder) — then only cohorts with at least one appearance
        // inside the moon are named.
        let cohorts = Dictionary(grouping: threads, by: \.displayTerm)
            .filter { $0.value.contains { $0.appearances.contains { inMoon($0.date) } } }

        let themes = cohorts
            .map { term, cohort -> LunationRecapTheme in
                let appearances = cohort.flatMap(\.appearances)
                let walkCount = Set(appearances.filter { inMoon($0.date) }.map(\.walkUUID)).count
                let earliest = appearances.map(\.date).min()
                return LunationRecapTheme(
                    displayTerm: term,
                    lemmas: cohort.map(\.lemma).sorted(),
                    walkCount: walkCount,
                    isNewThisMoon: backfillComplete && earliest.map(inMoon) == true
                )
            }
            .sorted { ($0.walkCount, $1.displayTerm) > ($1.walkCount, $0.displayTerm) }
            .prefix(maxThemes)

        let moonRecordingSet = Set(moonRecordings.keys)
        let insightTotal = contexts
            .filter { moonRecordingSet.contains($0.recordingUUID) }
            .compactMap(\.markers)
            .reduce(0) { $0 + $1.insightCount }
        let wpms = moonRecordingSet.compactMap { paceByRecording[$0] }
        let meanWPM = wpms.isEmpty ? nil : wpms.reduce(0, +) / Double(wpms.count)

        return LunationRecapModel(
            moonName: moonName,
            walkCount: totalWalks,
            themes: Array(themes),
            textureLine: ThreadsTexture.line(
                meanWordsPerMinute: meanWPM,
                hasInsight: insightTotal >= insightFloor
            ),
            quietLine: themes.isEmpty ? LunationRecapCopy.nothingHeld : nil
        )
    }
}
```

In `Pilgrim/Models/Data/DataManager+VoiceRecording.swift`, next to `voiceRecordingWalkIndex()` (line 159 — the walk-index/snapshot helpers live in this extension file, not DataManager.swift; the Task 7 `git add` stages this file). Mirror the neighbors' two-column `queryAttributes` pattern — their own doc comments explain that `fetchAll` faulted in every recording row, one SQL round-trip each, and this function runs on every recap sheet open:

```swift
    /// Recording UUID → words-per-minute, for the recap's pace texture. A
    /// two-column `queryAttributes` fetch mirroring the snapshot queries
    /// above. Main-actor only, like its neighbors.
    @MainActor
    public static func voiceRecordingPaceIndex() -> [UUID: Double] {
        guard let rows = try? dataStack.queryAttributes(
            From<VoiceRecording>().select(
                NSDictionary.self,
                .attribute(\._uuid),
                .attribute(\._wordsPerMinute)
            )
        ) else { return [:] }
        var index: [UUID: Double] = [:]
        for row in rows {
            guard let uuid = row["id"] as? UUID,
                  let wpm = row["wordsPerMinute"] as? Double else { continue }
            index[uuid] = wpm
        }
        return index
    }
```

- [ ] **Step 4: Implement the sheet and the settings list**

`Pilgrim/Scenes/WalkSummary/LunationRecapView.swift`:

```swift
import SwiftUI

/// The moon's quiet accounting — pulled, never pushed. Content is computed
/// live at open; themes tap through to their thread views. Deterministic
/// template copy; the only digits are the spec-sanctioned "in N of M walks".
struct LunationRecapView: View {

    let lunation: Lunation

    @Environment(\.dismiss) private var dismiss
    @State private var model: LunationRecapModel?
    @State private var selectedTheme: LunationRecapTheme?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let model {
                    content(model)
                        .padding(Constants.UI.Padding.normal)
                }
            }
            .canvasBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(model?.moonName ?? "")
                        .font(Constants.Typography.heading)
                        .foregroundColor(.ink)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.stone)
                }
            }
            .navigationDestination(item: $selectedTheme) { theme in
                ThreadHistoryView(displayTerm: theme.displayTerm, cohortLemmas: theme.lemmas)
            }
            // Re-keyed on the released token: a release made inside the
            // pushed thread view pops back here, the pop re-evaluates this
            // body, the id has changed, and load() reruns — the released
            // theme drops out (the quiet line appears when emptied) and a
            // re-tap can never open a dead-end empty history view.
            .task(id: ReleasedThreadsStore.shared.changeCount) { await load() }
        }
    }

    private func content(_ model: LunationRecapModel) -> some View {
        VStack(spacing: Constants.UI.Padding.normal) {
            Image(systemName: "moon")
                .font(.title2)
                .foregroundColor(.fog)
            Text(LunationRecapCopy.headline(walkCount: model.walkCount))
                .font(Constants.Typography.body)
                .foregroundColor(.ink)

            if let quiet = model.quietLine {
                Text(quiet)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                    .multilineTextAlignment(.center)
            }

            ForEach(model.themes) { theme in
                themeRow(theme, totalWalks: model.walkCount)
            }

            if let texture = model.textureLine {
                Text(texture)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func themeRow(_ theme: LunationRecapTheme, totalWalks: Int) -> some View {
        Button {
            selectedTheme = theme
        } label: {
            VStack(alignment: .leading, spacing: Constants.UI.Padding.xs) {
                Text(LunationRecapCopy.themeLine(
                    term: theme.displayTerm, walkCount: theme.walkCount, totalWalks: totalWalks
                ))
                .font(Constants.Typography.body)
                .foregroundColor(.ink)
                .multilineTextAlignment(.leading)
                if theme.isNewThisMoon {
                    Text(LunationRecapCopy.newThisMoon)
                        .font(Constants.Typography.caption)
                        .foregroundColor(.moss)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(Constants.UI.Padding.normal)
            .background(Color.parchmentSecondary)
            .cornerRadius(Constants.UI.CornerRadius.normal)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double tap to view this thread's history")
    }

    @MainActor
    private func load() async {
        // The local shadow must precede its first use — Swift resolves the
        // unqualified name to the local for the WHOLE scope, so referencing
        // it above its declaration is a compile error, not a property read.
        let lunation = self.lunation
        let walkIndex = DataManager.voiceRecordingWalkIndex()
        let paces = DataManager.voiceRecordingPaceIndex()
        let released = ReleasedThreadsStore.shared.releasedLemmas
        let backfillComplete = ThreadsBackfill.isComplete
        let moonName = LunationCalendar.moonName(for: lunation)

        model = await Task.detached(priority: .userInitiated) {
            LunationRecapModelBuilder.model(
                lunation: lunation, moonName: moonName,
                contexts: TranscriptContextStore.shared.loadAll(),
                walkIndex: walkIndex, paceByRecording: paces,
                released: released, backfillComplete: backfillComplete
            )
        }.value
    }
}
```

`Pilgrim/Scenes/Settings/PastRecapsListView.swift`:

```swift
import SwiftUI

/// Closed moons since the walker's first card, newest first — a missed
/// invitation line never costs the month. Each row opens the same
/// live-computed recap sheet.
struct PastRecapsListView: View {

    @State private var lunations: [Lunation] = PastRecapsListView.closedLunations()
    @State private var selected: Lunation?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    static func closedLunations(now: Date = Date(), state: LunationRecapState = .shared) -> [Lunation] {
        guard let firstShown = state.firstCardShownAt else { return [] }
        var result: [Lunation] = []
        var index = LunationCalendar.mostRecentClosed(asOf: now).index
        while index >= 0 {
            let lunation = LunationCalendar.lunation(at: index)
            guard lunation.end > firstShown else { break }
            result.append(lunation)
            index -= 1
        }
        return result
    }

    var body: some View {
        List {
            ForEach(lunations) { lunation in
                Button {
                    // Reading a recap here counts as acting on it — the
                    // summary's invitation row stops nagging about a moon
                    // the walker has already seen (spec-consistent: the
                    // invitation exists to surface the recap, not to be
                    // tapped for its own sake). markActedOn is monotonic,
                    // so opening an OLDER moon never regresses the index.
                    LunationRecapState.shared.markActedOn(lunation)
                    selected = lunation
                } label: {
                    HStack {
                        Text(LunationCalendar.moonName(for: lunation))
                            .font(Constants.Typography.body)
                            .foregroundColor(.ink)
                        Spacer()
                        Text(Self.dateFormatter.string(from: lunation.end))
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint("Double tap to open this moon's recap")
                .listRowBackground(Color.parchmentSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .canvasBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Past recaps")
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
            }
        }
        .sheet(item: $selected) { lunation in
            LunationRecapView(lunation: lunation)
        }
    }
}
```

- [ ] **Step 5: Wire the invitation row and settings**

1. `WalkSummaryView.swift` — add two `@State`s: `@State var recapInvitation: Lunation?` and `@State var recapSheet: Lunation?`. In `.onAppear` (after `loadReliquaryCandidates()`):

```swift
                recapInvitation = LunationRecapState.shared.invitation(forWalkDated: walk.startDate)
```

and after the Task 4 `.sheet(item: $selectedCardTheme)` block:

```swift
            .sheet(item: $recapSheet) { lunation in
                LunationRecapView(lunation: lunation)
            }
            .onChange(of: recapSheet) { _, newValue in
                if newValue == nil { Task { await loadThreadsCard() } }
            }
```

(The `.onChange(of: recapSheet)` is Task 5's `selectedCardTheme` pattern extended to the recap path: a release made inside the recap flow — recap → thread view → long-press release — reaches the summary card the moment the recap sheet closes, so the card can't keep offering to release an already-released cohort.)

2. `WalkSummaryView+Threads.swift` — the invitation renders as its own row below the intention card, above the per-walk card; when the triggering walk has no analyzed transcript, `threadsCardModel` is nil and the row renders alone in the card's slot — placement falls out of the slot order:

```swift
    @ViewBuilder
    var threadsCardSlot: some View {
        if showsThreadsCard {
            if let recapInvitation {
                lunationInvitationRow(recapInvitation)
            }
            if let threadsCardModel {
                ThreadsCardSection(
                    model: threadsCardModel,
                    onThemeTap: { selectedCardTheme = $0 },
                    onRelease: { releaseTheme($0) }
                )
                .transition(.opacity)
            }
        }
    }

    func lunationInvitationRow(_ lunation: Lunation) -> some View {
        Button {
            LunationRecapState.shared.markActedOn(lunation)
            recapInvitation = nil
            recapSheet = lunation
        } label: {
            HStack(spacing: Constants.UI.Padding.small) {
                Image(systemName: "moon")
                    .font(.caption)
                    .foregroundColor(.fog)
                Text(LunationRecapCopy.invitation(
                    moonName: LunationCalendar.moonName(for: lunation)
                ))
                .font(Constants.Typography.caption)
                .foregroundColor(.ink)
                .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(Constants.UI.Padding.normal)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.parchmentSecondary)
            .cornerRadius(Constants.UI.CornerRadius.normal)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double tap to open the moon's recap")
    }
```

3. `VoiceCard.swift` — add `@State private var hasPastRecaps = !PastRecapsListView.closedLunations().isEmpty`, refresh in `.onAppear`, and add below the Released threads row:

```swift
            if threadsAfterWalks && hasPastRecaps {
                NavigationLink {
                    PastRecapsListView()
                } label: {
                    settingNavRow(label: "Past recaps")
                }
            }
```

- [ ] **Step 6: Run `LunationRecapModelTests` (16 tests) then the full suite — PASS** (baseline 1269 + 84: Tasks 1-7 added 16 + 6 + 13 + 11 + 6 + 16 + 16). Then `swiftlint lint Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift` — zero errors (the ~669/750 type_body_length headroom check; this task added two `@State`s, one onAppear line, one sheet, and one onChange to the main struct).

- [ ] **Step 7: Commit**

```bash
git add Pilgrim/Models/Threads/LunationRecapModel.swift Pilgrim/Scenes/WalkSummary/LunationRecapView.swift Pilgrim/Scenes/Settings/PastRecapsListView.swift Pilgrim/Models/Data/DataManager+VoiceRecording.swift Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift Pilgrim/Scenes/WalkSummary/WalkSummaryView+Threads.swift Pilgrim/Scenes/Settings/SettingsCards/VoiceCard.swift UnitTests/LunationRecapModelTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(threads): the lunation recap — the moon sets, the month speaks in counts, pulled never pushed"
```

---

### Task 8: Chips live — the field gate opens

**Files:**
- Modify: `Pilgrim/Models/Threads/ThreadIntentionSuggestions.swift` (flip `pendingFieldGate`)
- Modify: `UnitTests/ThreadIntentionSuggestionsTests.swift` (replace the pinning test, add the `current()` release-wiring test — net +1)

**Interfaces:**
- Consumes: field gate outcome recorded in the spec addendum ("Chips: cleared to ship").
- Produces: `ThreadIntentionSuggestions.pendingFieldGate == false` — the chips section in `IntentionSettingView` renders for real. No other code changes: the section, the "Recurring" header (IntentionSettingView.swift:137), the `select` engine, and the toggle-off guard all shipped live-but-dark in Stage 2.

- [ ] **Step 1: Update the pinning test first** — in `ThreadIntentionSuggestionsTests.swift`, replace `testCurrent_pendingFieldGate_shipsDark` (lines 118-130) with:

```swift
    func testFieldGate_passed_chipsAreLive() {
        XCTAssertFalse(ThreadIntentionSuggestions.pendingFieldGate,
                       "field gate passed 2026-08-24 (spec addendum) — chips ship live in 1.12.0")
    }
```

and append the async wiring test the closed gate previously made impossible. Task 2's `testSuggestions_selectOverFilteredThreadsExcludesReleased` pins `select`'s ranking only — a bug in `current()`'s own wiring (omitting `released:` from its internal `ThreadStore.build` call, or a memo key that never sees the released token) would pass it. This test drives `current()` end to end through the Task 2 injection seams (mirroring `testDossierBuilder_releaseVisibleOnNextOpen`):

```swift
    @MainActor
    func testCurrent_releaseVisibleOnNextCall() async {
        let saved = UserPreferences.threadsAfterWalks.value
        defer { UserPreferences.threadsAfterWalks.value = saved }
        UserPreferences.threadsAfterWalks.value = true

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuggestionsWiring-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptContextStore(directory: directory)

        let suiteName = "SuggestionsWiring-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let releasedStore = ReleasedThreadsStore(defaults: defaults)

        let base = DateFactory.makeDate(2024, 6, 1, 9, 0, 0)
        let recA = UUID(), recB = UUID()
        let walkIndex: [UUID: (walkUUID: UUID, date: Date)] = [
            recA: (UUID(), base),
            recB: (UUID(), base.addingTimeInterval(5 * 86400))
        ]
        for rec in [recA, recB] {
            _ = store.save(TranscriptContext(
                schemaVersion: 1, recordingUUID: rec, transcriptHash: "h",
                languageCode: "en", wordCount: 200,
                themes: [Theme(lemma: "move", displayTerm: "the move", mentionCount: 3,
                               salience: 0.015, mentions: [ThemeMention(start: 0, length: 4)])],
                markers: nil
            ))
        }

        let asOf = base.addingTimeInterval(6 * 86400)
        let before = await ThreadIntentionSuggestions.current(
            asOf: asOf, store: store, releasedStore: releasedStore, walkIndex: walkIndex
        )
        XCTAssertEqual(before, ["walk with 'the move'"],
                       "fixture sanity — the suggestion is live before the release")

        releasedStore.release(displayTerm: "the move", lemmas: ["move"])
        let after = await ThreadIntentionSuggestions.current(
            asOf: asOf, store: store, releasedStore: releasedStore, walkIndex: walkIndex
        )
        XCTAssertTrue(after.isEmpty,
                      "current()'s own build path filters released lemmas and its memo re-keys on the released token — visible on the very next call")
    }
```

- [ ] **Step 2: Run to verify both fail** (`-only-testing:UnitTests/ThreadIntentionSuggestionsTests`). Expected: `testFieldGate_passed_chipsAreLive` FAILS against the still-true flag, and `testCurrent_releaseVisibleOnNextCall` FAILS at its `before` assertion (the closed gate returns `[]`); `testCurrent_toggleOff_returnsEmptyWithoutTouchingTheStore` still passes (toggle-off is a separate guard and must survive the flip).

- [ ] **Step 3: Flip the flag** — in `ThreadIntentionSuggestions.swift`, replace the `pendingFieldGate` declaration and its comment:

```swift
    /// The human field gate passed 2026-08-24 (spec addendum: "Chips:
    /// cleared to ship") — chips render in IntentionSettingView from 1.12.0.
    /// The header ships as "Recurring"; a softer-variant copy pass is a
    /// tracked fast-follow, judged against real chip words.
    static let pendingFieldGate = false
```

- [ ] **Step 4: Run the class — PASS.** Verify the header string is committed: `grep -n '"Recurring"' Pilgrim/Scenes/ActiveWalk/IntentionSettingView.swift` returns line 137. Manually verify toggle-off interaction on simulator: Settings → Voice → Thought Threads off → intention sheet shows no Recurring section; on → chips appear once a theme recurs across two walks (demo mode `--demo-mode` seeds enough history).

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Threads/ThreadIntentionSuggestions.swift UnitTests/ThreadIntentionSuggestionsTests.swift
git commit -m "feat(threads): chips live — the field gate opens, walk with what walks with you"
```

---

### Task 9: Verification + release checklist (no code)

**Files:** none — this task produces evidence and human checkpoints, not code.

- [ ] **Step 1: Full suite reconciliation**

Run: `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tee /tmp/threads-stage34-suite.log | tail -5`
Then: `grep -c "Test Case '.*' started" /tmp/threads-stage34-suite.log` (anchor on `started` — the unanchored `Test Case '` also matches the passed/failed lines and counts roughly double; reconcile with `xcrun xcresulttool` if in doubt).
Expected: PASS, and the count reconciles to **1269 + 85 = 1354** started cases (Tasks 1-7 added 16 + 6 + 13 + 11 + 6 + 16 + 16 = 84; Task 8 replaced one test and added the current() wiring test, net +1). Any shortfall means a test file never joined the UnitTests target — go back to the pbxproj 4-entries check for that file.

- [ ] **Step 2: Privacy grep gates**

```bash
grep -rn "TranscriptContext\|MarkerPack\|WalkThread" Pilgrim/Models/Share/ Pilgrim/Models/Data/PilgrimPackage/ | grep -v "TranscriptContextStore"
grep -rn "ReleasedThread\|releasedThreads\|WelcomedBack\|welcomedBack" Pilgrim/Models/Share/
grep -rln "ReleasedThread\|WelcomedBack" Pilgrim/Models/Data/PilgrimPackage/
```

Expected: line 1 and line 2 return **nothing** — derived analysis stays out of shares and exports, and neither the released set nor the welcome-back records ever enter `SharePayload` or the worker. (The `grep -v` allows the importer's pre-existing `TranscriptContextStore.shared.clearTombstones` call at PilgrimPackageImporter.swift:87 — store hygiene, not data egress; no other `TranscriptContext` reference may appear.) Line 3 returns **exactly three files** (`PilgrimPackageModels.swift`, `PilgrimPackageConverter.swift`, `PilgrimPackageImporter.swift`) — the sanctioned preferences-block carve-out and nothing else.

- [ ] **Step 3: UI language gates**

```bash
grep -rn '"rising"\|"fading"\|"steady"' Pilgrim/Scenes/
git diff main --stat -- '*Journal*'
```

Expected: both return nothing — no directional words anywhere in UI, and the journal is untouched (principle 4).

- [ ] **Step 4: Full-repo SwiftLint** — `swiftlint` from the repo root (the pre-commit hook only checks staged files; edited files like `WalkSummaryView.swift` and `AttentionDirectives.swift` may have crossed a length threshold mid-plan). Expected: zero errors. If `WalkSummaryView`'s type body approaches 750, move members to `WalkSummaryView+Threads.swift` — never raise the limit.

- [ ] **Step 5: Manual smoke on simulator (iPhone 17 Pro, demo mode)**

1. Launch with `--demo-mode`, open a Camino walk summary with transcripts: the card appears below the intention card, chips carry ordinal statuses, no digits anywhere on the card.
2. Tap a chip → thread view, newest first, "where it began" on the oldest, "open the map" opens the origin map centered on the pin; date rows resolve their place names one by one (serialized geocoding — no silently missing places on a long thread); tap an entry row → that walk's summary opens WITHOUT a threads card (the recursion cut — a tap-through summary never offers another chip to tap through).
3. Long-press a chip → confirm reads exactly "Let 'X' go? / You can welcome it back anytime." → release → card reflows (or fades out entirely when it was the last theme); a plain tap on a chip still navigates reliably (tap and long-press share the plain-view gesture pattern — verify both on the same chip); reopen the AI-prompts sheet → the released term is gone from the dossier on this very open.
4. Settings → Voice: "Released threads" row appeared; welcome the theme back; the row hides again once empty.
5. Toggle Thought Threads off → summary is pixel-identical to a card-less build; intention sheet shows no chips; both settings rows hidden.
6. VoiceOver pass: each chip is one element announcing "theme, status", hint "Double tap to view history", custom action "Let this go"; Dynamic Type at AX sizes wraps chips, never truncates; the thread view's term header long-press target spans the full row width.
7. Lunation: temporarily set the device clock forward past the next new moon (or seed `threadsFirstCardShownAt` back one lunation via the debugger) → a summary for a walk dated after the boundary shows the invitation row; an older walk's summary does not; tapping opens the recap (headline reads "N walks with recorded words this moon"); the row never returns after acting; Settings → Voice → Past recaps reaches the same sheet, and opening a moon there also stops the invitation nagging. (The acted-index clamp makes the clock-forward step safe to undo — restoring the clock cannot leave invitations silenced.)
8. Recap-path release: from a recap, tap a theme → thread view → long-press the term header → release → the pop returns to a REFRESHED recap (the theme is gone; the quiet line appears if it was the last); re-tapping cannot open an empty history view; close the recap sheet → the summary card no longer shows the released theme.

- [ ] **Step 6: RELEASE checklist — human checkpoints (STOP here; these gate distribution, not merge)**

1. **Internal TestFlight first.** Build 1.12.0 goes to the internal group only. No public TestFlight, no App Store submission yet.
2. **LLM-readback QA (release gate from the spec addendum, still PENDING):** the walker/product owner pastes representative REAL dossiers from the internal build — including elevated absolutist/self-focus profiles — into the major consumer LLMs and iterates `PromptAssembler.responseContract`'s handling note until no response contains clinical or diagnostic language. This is a human judgment task on real data; it cannot be pre-verified by this plan.
3. **Gentleness pass on the confirm strings:** the walker/product owner reads `ReleasedThreadsCopy` on-device (release, welcome-back, caption) and adjusts wording in that one file if anything reads clinical or abrupt; update `ReleasedThreadsInteractionTests` in the same commit if strings change.
4. Only after 2 and 3 pass: public TestFlight / App Store submission per `scripts/release.sh` and the `/release` skill. Remember: TestFlight dispatch requires the user's explicit go-ahead — never trigger `gh workflow run testflight.yml` from this plan.

---

## Verification (whole plan)

- [ ] Full suite green at 1354 cases (Task 9 Step 1 evidence attached to the PR).
- [ ] All grep gates clean (Task 9 Steps 2-3 output attached).
- [ ] SwiftLint clean, full repo.
- [ ] Manual smoke checklist completed on iPhone 17 Pro simulator.
- [ ] Release checkpoints acknowledged as OPEN items in the PR description — the branch merges; 1.12.0 does not ship externally until the LLM-readback QA and gentleness pass are recorded.

## Spec coverage map (addendum behavior → task)

| Spec addendum behavior | Task |
|---|---|
| Filtering call graph: ThreadStore.build drops released; recurringWord skip promotes next; intentionEcho exempt | T2 |
| Lemma-cohort release + atomic welcome-back | T1 (store) + T3 (cohort assembly) + T5 (UI) |
| Released set's own change token folded into dossier + suggestions memo keys; release visible on next open | T1 + T2 (+ T8 wiring test) |
| `.pilgrim` preferences-block carve-out (export, import merge, old-file tolerance) | T1 |
| Import merge is latest-decision-wins per cohort (welcome-backs recorded as decisions; a stale backup's release never silently overrides a later reversal — the reversibility promise survives backups) | T1 |
| Delete All Data clears releases, welcome-back records, recap state, and the caption flag (the first-card gate re-arms like a reinstall) | T1 + T6 |
| Confirm copy exact strings, leads with reversibility | T5 |
| Mid-view transitions: card fades/reflows; thread view pops | T5 |
| VoiceOver custom action "Let this go" (gesture parity, not gesture-only) | T5 |
| One-time dismissible caption on first card appearance | T5 |
| Settings "Released threads" hidden-when-empty, welcome-back confirm | T5 |
| Card below intention card; transcribed+themes only; otherwise pixel-identical | T3 |
| Top-4 salience themes, first-time/nth-walk ordinal statuses, backfill-gated origin claims | T3 |
| State-only texture line (pace mechanical from wpm; insight words traceable on tap) | T3 |
| Card accessibility: wrap, single VoiceOver element per chip, 44 pt targets | T3 (+T4 hint, +T5 action) |
| Thread view: full history newest-first, date/place/excerpt (serialized geocoding), tap-through to summary | T4 |
| Tap-through summaries suppress the threads card (`showsThreadsCard: false` — the summary → thread → summary recursion cut) | T3 (flag) + T4 (sheet) |
| Excerpt slicing from mention offsets, grapheme-safe, hash-guarded | T4 |
| "Where it began" label + origin map (route-sample-nearest-timestamp, 120 s tolerance, hide on failure, resolve at open) | T4 |
| Thread-view origin claims backfill-gated — no isOrigin entry, footer, or map action until the sweep completes (mirrors the card and recap) | T4 |
| Deleted origin walk → earliest surviving appearance becomes the origin | T4 (record-derived, nothing persisted) |
| Timezone moon naming (month of full-moon instant, device timezone) | T6 |
| Lunation boundary index pinned to LunarPhase's reference | T6 |
| First-card-shown marker; backfilled-history boundaries never invite | T6 |
| Acted-on (not first-opportunity) invitation state; re-evaluates until tapped or superseded | T6 |
| Walk-dated invitations — never on historical summaries | T6 (eligibility) + T7 (row) |
| Invitation row placement: own row below intention card, above per-walk card; renders alone when walk unanalyzed | T7 |
| Recap live-computed at open; counts may exceed invitation moment's | T7 |
| Recap content: moon name, walks-with-recorded-words headline, "in N of M walks" themes tappable to thread view, new-this-moon firsts, texture line | T7 |
| Recap headline scoped to walks with recorded words (analyzed-transcript denominator, pinned against an untranscribed-walk fixture) | T7 |
| No directional language in recap; released filtered; release inside the recap flow refreshes recap (released-token re-key) and summary card (recapSheet onChange) | T7 (via T2) + T9 grep + smoke 8 |
| Sparse states: "in 1 of 1 walks"; "nothing held on to name this time"; zero-walk moon | T7 |
| Scope-divergence phrasing (lunation counts vs trailing-window ordinals, structurally distinct) | T7 (pinned test) |
| Past recaps settings list, hidden-when-empty, missed line never costs the month; viewing a recap there also marks it acted-on (kills the invitation nag — spec-consistent, the invitation exists to surface the recap; markActedOn is monotonic so older moons never regress the index) | T7 |
| Clock-forward safety: acted indices beyond the current lunation are ignored | T6 |
| Accessibility extends to recap sheet + both settings lists | T7 (rows) + T5 (list) |
| Chips live: pendingFieldGate → false; header ships "Recurring"; softer variant is a fast-follow | T8 |
| Toggle off = off everywhere (card, thread nav, chips, invitation, settings rows) | T3/T4/T5/T6/T7 guards + T9 smoke |
| Rollout: internal TF first; LLM-readback QA + gentleness pass gate external release | T9 |
