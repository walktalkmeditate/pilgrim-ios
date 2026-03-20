import XCTest
@testable import Pilgrim

final class SealColorPaletteTests: XCTestCase {

    func testUnmarked_selectsFromThreeColors() {
        for byte in UInt8(0)...UInt8(2) {
            let color = SealColorPalette.color(for: nil, hashByte: byte)
            XCTAssertTrue(SealColorPalette.neutralColors.contains(color))
        }
    }

    func testUnmarked_wrapsAtThree() {
        let color0 = SealColorPalette.color(for: nil, hashByte: 0)
        let color3 = SealColorPalette.color(for: nil, hashByte: 3)
        XCTAssertEqual(color0, color3)
    }

    func testFlame_selectsFromWarmPalette() {
        for byte in UInt8(0)...UInt8(3) {
            let color = SealColorPalette.color(for: .flame, hashByte: byte)
            XCTAssertTrue(SealColorPalette.warmColors.contains(color))
        }
    }

    func testLeaf_selectsFromCoolPalette() {
        let color = SealColorPalette.color(for: .leaf, hashByte: 0)
        XCTAssertTrue(SealColorPalette.coolColors.contains(color))
    }

    func testStar_selectsFromAccentPalette() {
        let color = SealColorPalette.color(for: .star, hashByte: 0)
        XCTAssertTrue(SealColorPalette.accentColors.contains(color))
    }

    func testAllFifteenColors_areUnique() {
        let all = SealColorPalette.warmColors + SealColorPalette.coolColors +
                  SealColorPalette.accentColors + SealColorPalette.neutralColors
        XCTAssertEqual(all.count, 15)
        XCTAssertEqual(Set(all).count, 15)
    }
}
