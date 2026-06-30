import XCTest
@testable import Pilgrim

/// AF12: battery/thermal notifications post on background threads, and tier
/// recalculation reschedules the checkpoint Timer — a Timer installed on a
/// runloop-less GCD worker never fires, silently ending crash-recovery
/// checkpointing for the rest of the walk. These tests prove the sinks hop
/// to the main thread before recalculating.
final class WalkSessionGuardDispatchTests: XCTestCase {

    private var sessionGuard: WalkSessionGuard!

    override func setUp() {
        super.setUp()
        sessionGuard = WalkSessionGuard()
        sessionGuard.start()
    }

    override func tearDown() {
        sessionGuard.stop()
        sessionGuard = nil
        super.tearDown()
    }

    private func assertRecalculatesOnMain(
        whenPosting name: Notification.Name,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var observedMainThread: Bool?
        let recalculated = expectation(description: "tier recalculated for \(name.rawValue)")
        recalculated.assertForOverFulfill = false

        sessionGuard._test_onRecalculateTier = {
            if observedMainThread == nil {
                observedMainThread = Thread.isMainThread
            }
            recalculated.fulfill()
        }

        DispatchQueue.global(qos: .userInitiated).async {
            NotificationCenter.default.post(name: name, object: nil)
        }

        wait(for: [recalculated], timeout: 2.0)
        XCTAssertEqual(
            observedMainThread, true,
            "\(name.rawValue) must recalculate the tier on the main thread, where the checkpoint Timer lives",
            file: file, line: line
        )
    }

    func testThermalNotificationFromBackgroundThread_recalculatesTierOnMain() {
        assertRecalculatesOnMain(whenPosting: ProcessInfo.thermalStateDidChangeNotification)
    }

    func testBatteryNotificationFromBackgroundThread_recalculatesTierOnMain() {
        assertRecalculatesOnMain(whenPosting: UIDevice.batteryLevelDidChangeNotification)
    }

    // MARK: - Checkpoint I/O (AF13)

    /// The encode + write of the full walk (multi-MB on long walks) must run
    /// off the main thread — it used to stall the UI every 10–30 s, getting
    /// worse exactly when the device was low on battery or hot.
    func testCheckpointNow_persistsOffMainThread() throws {
        defer { try? FileManager.default.removeItem(at: WalkSessionGuard.checkpointFileURL()) }

        let builder = WalkBuilder()
        builder._test_setStartDate(Date(timeIntervalSinceNow: -60))
        let guard_ = WalkSessionGuard()
        guard_.builder = builder

        var persistedOnMain: Bool?
        let persisted = expectation(description: "checkpoint persisted")
        guard_._test_onCheckpointPersisted = { isMainThread in
            persistedOnMain = isMainThread
            persisted.fulfill()
        }

        guard_.checkpointNow()
        wait(for: [persisted], timeout: 5.0)

        XCTAssertEqual(persistedOnMain, false, "checkpoint encode+write must run on the utility queue")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: WalkSessionGuard.checkpointFileURL().path),
            "checkpoint file must exist after the async write lands"
        )
    }

    /// `deleteCheckpointFile` is serialized behind in-flight writes: a write
    /// dispatched just before walk end must not land after the post-save
    /// cleanup and resurrect a checkpoint for an already-saved walk.
    func testDeleteCheckpointFile_ordersAfterInFlightWrite() throws {
        defer { try? FileManager.default.removeItem(at: WalkSessionGuard.checkpointFileURL()) }

        let builder = WalkBuilder()
        builder._test_setStartDate(Date(timeIntervalSinceNow: -60))
        let guard_ = WalkSessionGuard()
        guard_.builder = builder

        guard_.checkpointNow()
        WalkSessionGuard.deleteCheckpointFile()

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: WalkSessionGuard.checkpointFileURL().path),
            "deletion must be ordered after the pending checkpoint write"
        )
    }
}
