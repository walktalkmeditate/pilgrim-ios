import XCTest
@testable import Pilgrim

final class ScrollHapticEngineTests: XCTestCase {

    /// viewCenter = -offset + viewportHeight/2, so offset = H/2 - center.
    private func scroll(_ state: ScrollHapticState, toCenter center: CGFloat) {
        state.handleScrollOffset(400 - center, viewportHeight: 800)
    }

    private func makeState() -> ScrollHapticState {
        let state = ScrollHapticState()
        state.dotPositions = [100, 200, 300, 500]
        state.dotSizes = [10, 20, 10, 20]
        state.dotKinds = [.plain, .gate, .cairn, .plain]
        return state
    }

    func testGateCrossing_firesTheGateEvent() {
        let state = makeState()
        scroll(state, toCenter: 200)
        XCTAssertEqual(state.currentEvent, .gateDot(1), "a torii speaks the milestone thump regardless of size")
    }

    func testCairnCrossing_firesTheCairnEvent() {
        let state = makeState()
        scroll(state, toCenter: 300)
        XCTAssertEqual(state.currentEvent, .cairnDot(2))
    }

    func testPlainDots_keepTheSizeVocabulary() {
        let state = makeState()
        scroll(state, toCenter: 100)
        XCTAssertEqual(state.currentEvent, .lightDot(0))
        scroll(state, toCenter: 500)
        XCTAssertEqual(state.currentEvent, .heavyDot(3))
    }

    func testSameDot_doesNotRetrigger() {
        let state = makeState()
        scroll(state, toCenter: 200)
        let first = state.currentEvent
        scroll(state, toCenter: 205)
        XCTAssertEqual(state.currentEvent, first, "re-crossing the same dot must not fire twice")
    }

    func testMissingKinds_fallBackToSize() {
        let state = ScrollHapticState()
        state.dotPositions = [100]
        state.dotSizes = [20]
        scroll(state, toCenter: 100)
        XCTAssertEqual(state.currentEvent, .heavyDot(0), "no kinds configured = the old vocabulary")
    }
}
