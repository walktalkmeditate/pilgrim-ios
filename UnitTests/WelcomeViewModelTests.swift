import XCTest
@testable import Pilgrim

final class WelcomeViewModelTests: XCTestCase {

    func testQuotePool_isNotEmpty() {
        XCTAssertFalse(WelcomeViewModel.quotePool.isEmpty)
    }

    func testCurrentQuote_isFromPool() {
        let vm = WelcomeViewModel {}
        XCTAssertTrue(WelcomeViewModel.quotePool.contains(vm.currentQuote))
    }

    func testBeginAction_callsClosure() {
        var called = false
        let vm = WelcomeViewModel { called = true }
        vm.beginAction()
        XCTAssertTrue(called)
    }
}
