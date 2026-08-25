import XCTest
@testable import Pilgrim

/// The backfill's promise is accounting: `threadsBackfillCompleted` may only
/// turn true when every snapshot item is accounted for by a sweep whose
/// generation is still current and whose gate stayed open. These tests drive
/// `runIfNeeded` through its injection seams (snapshot, gate, finish) —
/// production callers use the defaults, so the seams change nothing shipped.
@MainActor
final class ThreadsBackfillTests: XCTestCase {

    /// The pre-rename keys (see ThreadsBackfill.legacyCompletedKeys, which is
    /// private) — hardcoded here deliberately, the same way the production
    /// hygiene removal hardcodes them: these strings are frozen, not symbols
    /// that can drift with a rename.
    private static let legacyCompletedKeyV1 = "threadsBackfillCompleted"
    private static let legacyCompletedKeyV2 = "threadsBackfillCompletedV2"
    private static let legacyCompletedKeyV3 = "threadsBackfillCompletedV3"
    private static let legacyCompletedKeyV4 = "threadsBackfillCompletedV4"
    private static let legacyCompletedKeyV5 = "threadsBackfillCompletedV5"

    private var store: TranscriptContextStore!
    private var directory: URL!
    private var savedCompleted: Any?
    private var savedLegacyCompletedV1: Any?
    private var savedLegacyCompletedV2: Any?
    private var savedLegacyCompletedV3: Any?
    private var savedLegacyCompletedV4: Any?
    private var savedLegacyCompletedV5: Any?
    private var savedMoonState: Any?
    private var savedToggle = true

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedCompleted = UserDefaults.standard.object(forKey: ThreadsBackfill.completedKey)
        savedLegacyCompletedV1 = UserDefaults.standard.object(forKey: Self.legacyCompletedKeyV1)
        savedLegacyCompletedV2 = UserDefaults.standard.object(forKey: Self.legacyCompletedKeyV2)
        savedLegacyCompletedV3 = UserDefaults.standard.object(forKey: Self.legacyCompletedKeyV3)
        savedLegacyCompletedV4 = UserDefaults.standard.object(forKey: Self.legacyCompletedKeyV4)
        savedLegacyCompletedV5 = UserDefaults.standard.object(forKey: Self.legacyCompletedKeyV5)
        savedMoonState = UserDefaults.standard.object(forKey: ThreadsDossierBuilder.moonLineDefaultsKey)
        savedToggle = UserPreferences.threadsAfterWalks.value
        UserDefaults.standard.set(false, forKey: ThreadsBackfill.completedKey)
        UserDefaults.standard.removeObject(forKey: Self.legacyCompletedKeyV1)
        UserDefaults.standard.removeObject(forKey: Self.legacyCompletedKeyV2)
        UserDefaults.standard.removeObject(forKey: Self.legacyCompletedKeyV3)
        UserDefaults.standard.removeObject(forKey: Self.legacyCompletedKeyV4)
        UserDefaults.standard.removeObject(forKey: Self.legacyCompletedKeyV5)
        UserPreferences.threadsAfterWalks.value = true
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThreadsBackfillTests-\(UUID().uuidString)")
        store = TranscriptContextStore(directory: directory)
    }

    override func tearDownWithError() throws {
        if let savedCompleted {
            UserDefaults.standard.set(savedCompleted, forKey: ThreadsBackfill.completedKey)
        } else {
            UserDefaults.standard.removeObject(forKey: ThreadsBackfill.completedKey)
        }
        if let savedLegacyCompletedV1 {
            UserDefaults.standard.set(savedLegacyCompletedV1, forKey: Self.legacyCompletedKeyV1)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.legacyCompletedKeyV1)
        }
        if let savedLegacyCompletedV2 {
            UserDefaults.standard.set(savedLegacyCompletedV2, forKey: Self.legacyCompletedKeyV2)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.legacyCompletedKeyV2)
        }
        if let savedLegacyCompletedV3 {
            UserDefaults.standard.set(savedLegacyCompletedV3, forKey: Self.legacyCompletedKeyV3)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.legacyCompletedKeyV3)
        }
        if let savedLegacyCompletedV4 {
            UserDefaults.standard.set(savedLegacyCompletedV4, forKey: Self.legacyCompletedKeyV4)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.legacyCompletedKeyV4)
        }
        if let savedLegacyCompletedV5 {
            UserDefaults.standard.set(savedLegacyCompletedV5, forKey: Self.legacyCompletedKeyV5)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.legacyCompletedKeyV5)
        }
        if let savedMoonState {
            UserDefaults.standard.set(savedMoonState, forKey: ThreadsDossierBuilder.moonLineDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: ThreadsDossierBuilder.moonLineDefaultsKey)
        }
        UserPreferences.threadsAfterWalks.value = savedToggle
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func makeItems(_ count: Int) -> [(uuid: UUID, transcript: String)] {
        (0..<count).map { _ in (uuid: UUID(), transcript: "walking with the river again this morning") }
    }

    /// v1.11.0 TestFlight devices swept zero recordings under a snapshot bug
    /// (fixed in 9529fff) yet still set the old flag true — `runIfNeeded`'s
    /// `!isComplete` guard then never re-evaluates them. `completedKey` was
    /// renamed to re-arm those devices: the new key is absent regardless of
    /// what the old key holds, so `isComplete` must read false.
    func testIsComplete_legacyKeyTrue_reArmsUnderNewKey() {
        UserDefaults.standard.set(true, forKey: Self.legacyCompletedKeyV1)

        XCTAssertFalse(ThreadsBackfill.isComplete,
                       "a device that swept nothing under the old key must re-evaluate under the new key")
    }

    /// Build 106 devices completed a real V2 sweep, but ThemeExtractor's raw
    /// NLTagger verb filter let spoken scaffolding ("was", "have", "can",
    /// "think") win every theme ranking — those stored themes are junk, not
    /// stale. The V3 rename re-arms them the same way the V1 rename did:
    /// the new key is absent, so `isComplete` reads false regardless of what
    /// the V2 key holds, and the next sweep recomputes with the noun-only
    /// extractor.
    func testIsComplete_legacyV2KeyTrue_reArmsUnderNewKey() {
        UserDefaults.standard.set(true, forKey: Self.legacyCompletedKeyV2)

        XCTAssertFalse(ThreadsBackfill.isComplete,
                       "a device that completed the junk-theme V2 sweep must re-evaluate under the new key")
    }

    /// V3 devices completed a real sweep, but the noun-only extractor still
    /// left verb/adjective scaffolding ("was", "can", "cool") and stoplisted
    /// nouns ("thing", "way") in stored themes because nothing checked
    /// `TranscriptContext.schemaVersion` — a bare `hasContext` skip treated
    /// existence as freshness. The V4 rename (schema v2) re-arms them the
    /// same way V1→V2 and V2→V3 did: the new key is absent regardless of
    /// what the V3 key holds.
    func testIsComplete_legacyV3KeyTrue_reArmsUnderNewKey() {
        UserDefaults.standard.set(true, forKey: Self.legacyCompletedKeyV3)

        XCTAssertFalse(ThreadsBackfill.isComplete,
                       "a device that completed the stale-schema V3 sweep must re-evaluate under the new key")
    }

    /// V4 devices completed a real sweep under schema v2, but that schema
    /// carries no modal-lean word counts (`MarkerPack.modalCounts` didn't
    /// exist yet) — schema v3 adds them. The V5 rename (completedKey) re-arms
    /// them the same way every prior rename did: the new key is absent
    /// regardless of what the V4 key holds. Unlike V3→V4, this rename
    /// touches no theme-extraction logic, so no moon-line re-arm accompanies
    /// it (see `performLegacyHygiene`).
    func testIsComplete_legacyV4KeyTrue_reArmsUnderNewKey() {
        UserDefaults.standard.set(true, forKey: Self.legacyCompletedKeyV4)

        XCTAssertFalse(ThreadsBackfill.isComplete,
                       "a device that completed the pre-modal-lean V4 sweep must re-evaluate under the new key")
    }

    /// V5 devices completed a real sweep under schema v3, but `day`/`days`/
    /// `area` were still admitted as theme nouns — the same generic-noun
    /// class as the already-stoplisted `thing`/`way`. The V6 rename (schema
    /// v4) re-arms them the same way every prior rename did: the new key is
    /// absent regardless of what the V5 key holds.
    func testIsComplete_legacyV5KeyTrue_reArmsUnderNewKey() {
        UserDefaults.standard.set(true, forKey: Self.legacyCompletedKeyV5)

        XCTAssertFalse(ThreadsBackfill.isComplete,
                       "a device that completed the pre-lightNouns-gate V5 sweep must re-evaluate under the new key")
    }

    /// The where-clause skip (`!store.hasContext`) must become version-aware
    /// (`!store.hasCurrentContext`) so a stale-schema file blocks nothing —
    /// the item is re-analyzed and lands on disk with the current schema.
    func testRunIfNeeded_staleSchemaContext_reAnalyzedToCurrentSchema() async {
        let items = makeItems(1)
        let item = items[0]
        let stale = TranscriptContext(
            schemaVersion: 1, recordingUUID: item.uuid, transcriptHash: "stale-hash",
            languageCode: "en", wordCount: 1, themes: [], markers: nil
        )
        store.save(stale)

        let done = expectation(description: "sweep finished")
        ThreadsBackfill.runIfNeeded(
            store: store, snapshotProvider: { items }, gate: { true },
            onFinish: { done.fulfill() }
        )
        await fulfillment(of: [done], timeout: 60)

        XCTAssertTrue(store.hasCurrentContext(for: item.uuid),
                      "a stale-schema context must be re-analyzed into the current schema, not skipped")
        XCTAssertTrue(ThreadsBackfill.isComplete)
    }

    /// A stale-version file whose recording no longer exists in the sweep's
    /// snapshot must be deleted outright — `loadAll`/`ThreadsDossierBuilder`
    /// only ever prune orphans among CURRENT-schema contexts, so a stale
    /// orphan would otherwise linger on disk forever, invisible to every
    /// reader yet never cleaned up.
    func testRunIfNeeded_staleOrphan_deletedFromDisk() async {
        let items = makeItems(1)
        let orphanUUID = UUID()
        let staleOrphan = TranscriptContext(
            schemaVersion: 1, recordingUUID: orphanUUID, transcriptHash: "gone",
            languageCode: "en", wordCount: 1, themes: [], markers: nil
        )
        store.save(staleOrphan)

        let done = expectation(description: "sweep finished")
        ThreadsBackfill.runIfNeeded(
            store: store, snapshotProvider: { items }, gate: { true },
            onFinish: { done.fulfill() }
        )
        await fulfillment(of: [done], timeout: 60)

        XCTAssertFalse(store.hasContext(for: orphanUUID),
                       "a stale-version context with no matching recording must be deleted, not merely hidden")
    }

    /// `transcribedRecordingsSnapshot()`'s `try? queryAttributes` silently
    /// returns `[]` on any CoreStore failure — indistinguishable here from a
    /// genuinely empty history. Treating an empty snapshot as proof every
    /// stale-schema context is orphaned would store-wide delete and
    /// tombstone a still-live recording's context on a single bad read. The
    /// dossier builder's sibling guard (`walkIndex.isEmpty && !all.isEmpty`,
    /// see `testBuilder_emptyWalkIndexWithStoredContexts_doesNotMassPrune`)
    /// defends the same hazard on its own read path.
    func testRunIfNeeded_emptySnapshotWithStoredStaleContext_doesNotMassPrune() async {
        let staleUUID = UUID()
        let stillLive = TranscriptContext(
            schemaVersion: 1, recordingUUID: staleUUID, transcriptHash: "still-live",
            languageCode: "en", wordCount: 1, themes: [], markers: nil
        )
        store.save(stillLive)
        let changeCountBeforeSweep = store.changeCount

        let done = expectation(description: "sweep finished")
        ThreadsBackfill.runIfNeeded(
            store: store, snapshotProvider: { [] }, gate: { true },
            onFinish: { done.fulfill() }
        )
        await fulfillment(of: [done], timeout: 60)

        XCTAssertTrue(store.hasContext(for: staleUUID),
                      "an empty/failed snapshot read must not be treated as proof every stale context is orphaned")
        XCTAssertEqual(store.changeCount, changeCountBeforeSweep,
                       "no delete/tombstone write must reach the store on an empty snapshot")
    }

    /// The V3→V4 transition is the one moment the burned Buck Moon budget
    /// can be forgiven: the stale-theme era's re-analysis will change what
    /// the moon line has to say, so its last-reported lunation must clear
    /// exactly once, gated on the V3 key's presence (not a separate marker).
    func testRunIfNeeded_v3KeyPresent_removesMoonLineKeyOnce() async {
        UserDefaults.standard.set(true, forKey: Self.legacyCompletedKeyV3)
        UserDefaults.standard.set(7, forKey: ThreadsDossierBuilder.moonLineDefaultsKey)

        let done = expectation(description: "sweep finished")
        ThreadsBackfill.runIfNeeded(
            store: store, snapshotProvider: { [] }, gate: { true },
            onFinish: { done.fulfill() }
        )
        await fulfillment(of: [done], timeout: 10)

        XCTAssertNil(UserDefaults.standard.object(forKey: ThreadsDossierBuilder.moonLineDefaultsKey),
                     "the V3→V4 transition burns the stale-theme era's moon budget so it can re-report honestly")
    }

    /// No V3 key means either a fresh install or an already-migrated device
    /// — the moon key must be left alone in both cases.
    func testRunIfNeeded_noV3Key_moonLineUntouched() async {
        UserDefaults.standard.set(true, forKey: ThreadsBackfill.completedKey)
        UserDefaults.standard.set(3, forKey: ThreadsDossierBuilder.moonLineDefaultsKey)

        let done = expectation(description: "sweep finished")
        ThreadsBackfill.runIfNeeded(
            store: store, snapshotProvider: { [] }, gate: { true },
            onFinish: { done.fulfill() }
        )
        await fulfillment(of: [done], timeout: 10)

        XCTAssertEqual(UserDefaults.standard.object(forKey: ThreadsDossierBuilder.moonLineDefaultsKey) as? Int, 3,
                       "no V3 key present — a fresh install or already-migrated device must not lose its moon budget")
    }

    func testRunIfNeeded_processesEveryItemAcrossBatches() async {
        let items = makeItems(ThreadsBackfill.batchSize + 1)
        let done = expectation(description: "sweep finished")
        ThreadsBackfill.runIfNeeded(
            store: store,
            snapshotProvider: { items },
            gate: { true },
            onFinish: { done.fulfill() }
        )
        await fulfillment(of: [done], timeout: 60)

        XCTAssertTrue(items.allSatisfy { store.hasContext(for: $0.uuid) },
                      "an item past the first batch boundary must still be analyzed")
        XCTAssertTrue(ThreadsBackfill.isComplete)
    }

    func testRunIfNeeded_gateClosesMidSweep_retriesOnlyMissingOnRerun() async {
        let items = makeItems(ThreadsBackfill.batchSize + 5)
        var gateCalls = 0
        let firstPass = expectation(description: "gated sweep finished")
        ThreadsBackfill.runIfNeeded(
            store: store,
            snapshotProvider: { items },
            gate: {
                gateCalls += 1
                return gateCalls <= 2
            },
            onFinish: { firstPass.fulfill() }
        )
        await fulfillment(of: [firstPass], timeout: 60)

        XCTAssertFalse(ThreadsBackfill.isComplete,
                       "a gate closing mid-sweep leaves items unaccounted — the flag stays false")
        XCTAssertEqual(store.changeCount, ThreadsBackfill.batchSize,
                       "exactly one batch reached the store before the gate closed")

        let secondPass = expectation(description: "rerun finished")
        ThreadsBackfill.runIfNeeded(
            store: store,
            snapshotProvider: { items },
            gate: { true },
            onFinish: { secondPass.fulfill() }
        )
        await fulfillment(of: [secondPass], timeout: 60)

        XCTAssertTrue(ThreadsBackfill.isComplete)
        XCTAssertEqual(store.changeCount, items.count,
                       "the rerun analyzes only the missing items — already-stored contexts are skipped")
    }

    func testRunIfNeeded_saveFailure_leavesCompletedFalse() async throws {
        let readOnly = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadOnlyBackfill-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: readOnly, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnly.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnly.path)
            try? FileManager.default.removeItem(at: readOnly)
        }
        let failingStore = TranscriptContextStore(directory: readOnly)

        let done = expectation(description: "sweep finished")
        ThreadsBackfill.runIfNeeded(
            store: failingStore,
            snapshotProvider: { self.makeItems(1) },
            gate: { true },
            onFinish: { done.fulfill() }
        )
        await fulfillment(of: [done], timeout: 60)

        XCTAssertFalse(ThreadsBackfill.isComplete,
                       "a context that never reached disk is unaccounted — the next launch must retry")
    }

    func testRunIfNeeded_resetMidFlight_staleSweepNeverCompletes_followUpDoes() async {
        let items = makeItems(1)
        var gateCalls = 0
        var completedAfterFirstPass: Bool?
        var passes = 0
        let bothPasses = expectation(description: "stale sweep and follow-up finished")
        bothPasses.expectedFulfillmentCount = 2
        ThreadsBackfill.runIfNeeded(
            store: store,
            snapshotProvider: { items },
            gate: {
                gateCalls += 1
                if gateCalls == 2 {
                    ThreadsBackfill.reset()
                }
                return true
            },
            onFinish: {
                passes += 1
                if passes == 1 {
                    completedAfterFirstPass = ThreadsBackfill.isComplete
                }
                bothPasses.fulfill()
            }
        )
        await fulfillment(of: [bothPasses], timeout: 60)

        XCTAssertEqual(completedAfterFirstPass, false,
                       "a sweep whose generation went stale must never set the completed flag")
        XCTAssertTrue(ThreadsBackfill.isComplete,
                      "the follow-up pass re-sweeps (hasContext-only) and completes the accounting")
        XCTAssertTrue(store.hasContext(for: items[0].uuid))
    }

    func testRunIfNeeded_toggleOff_neverTakesSnapshot() async {
        UserPreferences.threadsAfterWalks.value = false
        var snapshotCalls = 0
        let done = expectation(description: "early return")
        ThreadsBackfill.runIfNeeded(
            store: store,
            snapshotProvider: {
                snapshotCalls += 1
                return []
            },
            gate: { true },
            onFinish: { done.fulfill() }
        )
        await fulfillment(of: [done], timeout: 10)

        XCTAssertEqual(snapshotCalls, 0, "off means off — the CoreStore snapshot is never taken")
        XCTAssertFalse(ThreadsBackfill.isComplete)
    }
}
