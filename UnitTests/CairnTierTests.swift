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

    // The add-a-stone sheet previews CachedCairn.becomingTier — the tier
    // the cairn becomes with the walker's stone.

    private func cairn(stones: Int) -> CachedCairn {
        CachedCairn(id: "test", latitude: 0, longitude: 0, stoneCount: stones, lastPlacedAt: "")
    }

    func testBecoming_sixStones_crossesIntoMedium() {
        XCTAssertEqual(cairn(stones: 6).becomingTier, .medium, "AE1: the walker sees what their stone makes")
    }

    func testBecoming_eightStones_staysMedium() {
        XCTAssertEqual(cairn(stones: 8).becomingTier, .medium, "AE2: most stones deepen a tier, not change it")
    }

    func testBecoming_newCairn_isFaint() {
        XCTAssertEqual(CairnTier.from(stoneCount: 1), .faint, "AE3: a first stone begins a faint cairn")
    }

    func testBecoming_thresholdCrossings() {
        XCTAssertEqual(cairn(stones: 2).becomingTier, .small)
        XCTAssertEqual(cairn(stones: 11).becomingTier, .large)
        XCTAssertEqual(cairn(stones: 41).becomingTier, .great)
        XCTAssertEqual(cairn(stones: 76).becomingTier, .sacred)
        XCTAssertEqual(cairn(stones: 107).becomingTier, .eternal)
    }
}
