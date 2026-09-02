import XCTest
@testable import Pilgrim

final class WalkModeTests: XCTestCase {

    func testHonorIsTheThirdMode() {
        XCTAssertEqual(WalkMode.allCases, [.wander, .honor, .seek])
        XCTAssertTrue(WalkMode.honor.isAvailable)
        XCTAssertEqual(WalkMode.honor.subtitle, "walk in their steps")
        XCTAssertEqual(WalkMode.honor.buttonLabel, "Choose a way")
    }

    func testHonorQuotesAreLocalized() {
        XCTAssertEqual(WalkMode.honor.quotes.count, 3)
        XCTAssertFalse(WalkMode.honor.quotes.contains(""))
        XCTAssertFalse(WalkMode.honor.quotes.contains { $0.hasPrefix("Honor.Quote") })
    }
}
