import XCTest
import SwiftUI
@testable import Pilgrim

final class WaveformScrubberStepTests: XCTestCase {

    func testIncrement_movesUpByTenPercent() {
        let result = WaveformBarView.steppedProgress(from: 0.5, direction: .increment)
        XCTAssertEqual(result, 0.6, accuracy: 0.0001)
    }

    func testDecrement_movesDownByTenPercent() {
        let result = WaveformBarView.steppedProgress(from: 0.5, direction: .decrement)
        XCTAssertEqual(result, 0.4, accuracy: 0.0001)
    }

    func testIncrement_clampsAtOne() {
        let result = WaveformBarView.steppedProgress(from: 0.95, direction: .increment)
        XCTAssertEqual(result, 1.0, accuracy: 0.0001)
    }

    func testDecrement_clampsAtZero() {
        let result = WaveformBarView.steppedProgress(from: 0.05, direction: .decrement)
        XCTAssertEqual(result, 0.0, accuracy: 0.0001)
    }

    func testIncrement_fromExactlyOne_staysAtOne() {
        let result = WaveformBarView.steppedProgress(from: 1.0, direction: .increment)
        XCTAssertEqual(result, 1.0, accuracy: 0.0001)
    }

    func testDecrement_fromExactlyZero_staysAtZero() {
        let result = WaveformBarView.steppedProgress(from: 0.0, direction: .decrement)
        XCTAssertEqual(result, 0.0, accuracy: 0.0001)
    }

    func testCustomStep_isHonored() {
        let result = WaveformBarView.steppedProgress(from: 0.5, direction: .increment, step: 0.25)
        XCTAssertEqual(result, 0.75, accuracy: 0.0001)
    }
}
