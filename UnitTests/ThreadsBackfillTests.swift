import XCTest
@testable import Pilgrim

/// The backfill's promise is accounting: `threadsBackfillCompleted` may only
/// turn true when every snapshot item is accounted for by a sweep whose
/// generation is still current and whose gate stayed open. These tests drive
/// `runIfNeeded` through its injection seams (snapshot, gate, finish) —
/// production callers use the defaults, so the seams change nothing shipped.
@MainActor
final class ThreadsBackfillTests: XCTestCase {

    private var store: TranscriptContextStore!
    private var directory: URL!
    private var savedCompleted: Any?
    private var savedToggle = true

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedCompleted = UserDefaults.standard.object(forKey: ThreadsBackfill.completedKey)
        savedToggle = UserPreferences.threadsAfterWalks.value
        UserDefaults.standard.set(false, forKey: ThreadsBackfill.completedKey)
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
        UserPreferences.threadsAfterWalks.value = savedToggle
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func makeItems(_ count: Int) -> [(uuid: UUID, transcript: String)] {
        (0..<count).map { _ in (uuid: UUID(), transcript: "walking with the river again this morning") }
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
