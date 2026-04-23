import XCTest
import SwiftUI
@testable import Pilgrim

final class SeasonalMarkerTurningTests: XCTestCase {

    // MARK: - kanji

    func testKanji_springEquinox() {
        XCTAssertEqual(SeasonalMarker.springEquinox.kanji, "春分")
    }

    func testKanji_summerSolstice() {
        XCTAssertEqual(SeasonalMarker.summerSolstice.kanji, "夏至")
    }

    func testKanji_autumnEquinox() {
        XCTAssertEqual(SeasonalMarker.autumnEquinox.kanji, "秋分")
    }

    func testKanji_winterSolstice() {
        XCTAssertEqual(SeasonalMarker.winterSolstice.kanji, "冬至")
    }

    func testKanji_crossQuarter_returnsNil() {
        XCTAssertNil(SeasonalMarker.imbolc.kanji)
        XCTAssertNil(SeasonalMarker.beltane.kanji)
        XCTAssertNil(SeasonalMarker.lughnasadh.kanji)
        XCTAssertNil(SeasonalMarker.samhain.kanji)
    }

    // MARK: - bannerText

    func testBannerText_solstices_saySunStandsStill() {
        XCTAssertEqual(SeasonalMarker.summerSolstice.bannerText, "Today the sun stands still")
        XCTAssertEqual(SeasonalMarker.winterSolstice.bannerText, "Today the sun stands still")
    }

    func testBannerText_equinoxes_sayDayEqualsNight() {
        XCTAssertEqual(SeasonalMarker.springEquinox.bannerText, "Today, day equals night")
        XCTAssertEqual(SeasonalMarker.autumnEquinox.bannerText, "Today, day equals night")
    }

    func testBannerText_crossQuarter_returnsNil() {
        XCTAssertNil(SeasonalMarker.imbolc.bannerText)
    }

    // MARK: - colorAssetName

    func testColorAssetName_forEachTurning() {
        XCTAssertEqual(SeasonalMarker.springEquinox.colorAssetName, "turningJade")
        XCTAssertEqual(SeasonalMarker.summerSolstice.colorAssetName, "turningGold")
        XCTAssertEqual(SeasonalMarker.autumnEquinox.colorAssetName, "turningClaret")
        XCTAssertEqual(SeasonalMarker.winterSolstice.colorAssetName, "turningIndigo")
    }

    func testColorAssetName_crossQuarter_returnsNil() {
        XCTAssertNil(SeasonalMarker.imbolc.colorAssetName)
    }

    // MARK: - isTurning

    func testIsTurning_trueForFourMainMarkers() {
        XCTAssertTrue(SeasonalMarker.springEquinox.isTurning)
        XCTAssertTrue(SeasonalMarker.summerSolstice.isTurning)
        XCTAssertTrue(SeasonalMarker.autumnEquinox.isTurning)
        XCTAssertTrue(SeasonalMarker.winterSolstice.isTurning)
    }

    func testIsTurning_falseForCrossQuarter() {
        XCTAssertFalse(SeasonalMarker.imbolc.isTurning)
        XCTAssertFalse(SeasonalMarker.beltane.isTurning)
        XCTAssertFalse(SeasonalMarker.lughnasadh.isTurning)
        XCTAssertFalse(SeasonalMarker.samhain.isTurning)
    }
}
