import XCTest
@testable import Pilgrim

final class WalkSharingTrackerTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "WalkSharingTrackerTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testHasNotSharedInitially() {
        let tracker = WalkSharingTracker(defaults: defaults)
        XCTAssertFalse(tracker.hasShared(walkUUID: "abc"))
    }

    func testMarkSharedStoresUUID() {
        let tracker = WalkSharingTracker(defaults: defaults)
        tracker.markShared(walkUUID: "abc")
        XCTAssertTrue(tracker.hasShared(walkUUID: "abc"))
    }

    func testMarkMultipleWalksAccumulates() {
        let tracker = WalkSharingTracker(defaults: defaults)
        tracker.markShared(walkUUID: "walk-1")
        tracker.markShared(walkUUID: "walk-2")
        tracker.markShared(walkUUID: "walk-3")
        XCTAssertTrue(tracker.hasShared(walkUUID: "walk-1"))
        XCTAssertTrue(tracker.hasShared(walkUUID: "walk-2"))
        XCTAssertTrue(tracker.hasShared(walkUUID: "walk-3"))
    }

    func testMarkSharedUsesSingleKey() {
        let tracker = WalkSharingTracker(defaults: defaults)
        tracker.markShared(walkUUID: "walk-1")
        tracker.markShared(walkUUID: "walk-2")
        let sharedKeys = defaults.dictionaryRepresentation().keys.filter { key in
            key.lowercased().contains("shared") && key.lowercased().contains("walk")
        }
        XCTAssertEqual(sharedKeys.count, 1, "Should use exactly one UserDefaults key")
    }

    func testMarkSharedIsIdempotent() {
        let tracker = WalkSharingTracker(defaults: defaults)
        tracker.markShared(walkUUID: "walk-1")
        tracker.markShared(walkUUID: "walk-1")
        tracker.markShared(walkUUID: "walk-1")
        // Should still just be one entry, not three
        let stored = defaults.array(forKey: "sharedWalkUUIDs") as? [String]
        XCTAssertEqual(stored?.count, 1)
    }

    func testPersistsAcrossInstances() {
        // Two different tracker instances pointing at the same defaults
        // should see the same state.
        let tracker1 = WalkSharingTracker(defaults: defaults)
        tracker1.markShared(walkUUID: "walk-x")
        let tracker2 = WalkSharingTracker(defaults: defaults)
        XCTAssertTrue(tracker2.hasShared(walkUUID: "walk-x"))
    }
}
