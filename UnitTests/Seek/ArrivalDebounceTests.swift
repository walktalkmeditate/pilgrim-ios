import XCTest
@testable import Pilgrim

final class ArrivalDebounceTests: XCTestCase {

    func testThreeConsecutiveInsideFixesArrive() {
        var d = ArrivalDebounce(requiredFixes: 3, accuracyMeters: 50)
        XCTAssertFalse(d.register(distance: 10, radius: 30, accuracy: 5))
        XCTAssertFalse(d.register(distance: 10, radius: 30, accuracy: 5))
        XCTAssertTrue(d.register(distance: 10, radius: 30, accuracy: 5))
    }

    func testAnOutsideFixResetsTheCount() {
        var d = ArrivalDebounce(requiredFixes: 3, accuracyMeters: 50)
        _ = d.register(distance: 10, radius: 30, accuracy: 5)
        _ = d.register(distance: 10, radius: 30, accuracy: 5)
        XCTAssertFalse(d.register(distance: 40, radius: 30, accuracy: 5))
        XCTAssertFalse(d.register(distance: 10, radius: 30, accuracy: 5))
        XCTAssertFalse(d.register(distance: 10, radius: 30, accuracy: 5))
        XCTAssertTrue(d.register(distance: 10, radius: 30, accuracy: 5))
    }

    func testPoorAccuracyNeitherAdvancesNorResets() {
        var d = ArrivalDebounce(requiredFixes: 3, accuracyMeters: 50)
        _ = d.register(distance: 10, radius: 30, accuracy: 5)
        _ = d.register(distance: 10, radius: 30, accuracy: 5)
        XCTAssertFalse(d.register(distance: 10, radius: 30, accuracy: 120))
        XCTAssertFalse(d.register(distance: 10, radius: 30, accuracy: -1))
        XCTAssertTrue(d.register(distance: 10, radius: 30, accuracy: 5))
    }
}
