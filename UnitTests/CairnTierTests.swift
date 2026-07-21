import XCTest
@testable import Pilgrim

/// Pins CairnTier.from(stoneCount:) — the threshold table the map pins, the
/// sheets, and the add-a-stone "becoming" preview (AE1–AE3) all rely on.
/// First direct coverage of this function.
final class CairnTierTests: XCTestCase {

    func testTierThresholdTable() {
        XCTAssertEqual(CairnTier.from(stoneCount: 0), .faint)
        XCTAssertEqual(CairnTier.from(stoneCount: 2), .faint)
        XCTAssertEqual(CairnTier.from(stoneCount: 3), .small)
        XCTAssertEqual(CairnTier.from(stoneCount: 6), .small)
        XCTAssertEqual(CairnTier.from(stoneCount: 7), .medium)
        XCTAssertEqual(CairnTier.from(stoneCount: 11), .medium)
        XCTAssertEqual(CairnTier.from(stoneCount: 12), .large)
        XCTAssertEqual(CairnTier.from(stoneCount: 41), .large)
        XCTAssertEqual(CairnTier.from(stoneCount: 42), .great)
        XCTAssertEqual(CairnTier.from(stoneCount: 76), .great)
        XCTAssertEqual(CairnTier.from(stoneCount: 77), .sacred)
        XCTAssertEqual(CairnTier.from(stoneCount: 107), .sacred)
        XCTAssertEqual(CairnTier.from(stoneCount: 108), .eternal)
    }

    // The add-a-stone sheet previews the tier the cairn becomes with the
    // walker's stone: from(stoneCount: current + 1).

    func testBecoming_sixStones_crossesIntoMedium() {
        XCTAssertEqual(CairnTier.from(stoneCount: 6 + 1), .medium, "AE1: the walker sees what their stone makes")
    }

    func testBecoming_eightStones_staysMedium() {
        XCTAssertEqual(CairnTier.from(stoneCount: 8 + 1), .medium, "AE2: most stones deepen a tier, not change it")
    }

    func testBecoming_newCairn_isFaint() {
        XCTAssertEqual(CairnTier.from(stoneCount: 0 + 1), .faint, "AE3: a first stone begins a faint cairn")
    }

    func testBecoming_thresholdCrossings() {
        XCTAssertEqual(CairnTier.from(stoneCount: 2 + 1), .small)
        XCTAssertEqual(CairnTier.from(stoneCount: 11 + 1), .large)
        XCTAssertEqual(CairnTier.from(stoneCount: 41 + 1), .great)
        XCTAssertEqual(CairnTier.from(stoneCount: 76 + 1), .sacred)
        XCTAssertEqual(CairnTier.from(stoneCount: 107 + 1), .eternal)
    }
}
