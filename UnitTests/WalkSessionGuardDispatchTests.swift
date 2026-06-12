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
}
