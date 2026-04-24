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

    // MARK: - evocativePhrase

    func testEvocativePhrase_winterSolstice() {
        XCTAssertEqual(SeasonalMarker.winterSolstice.evocativePhrase, "The longest night. From here, light returns.")
    }

    func testEvocativePhrase_summerSolstice() {
        XCTAssertEqual(SeasonalMarker.summerSolstice.evocativePhrase, "The longest day. The wheel begins to turn back toward stillness.")
    }

    func testEvocativePhrase_springEquinox() {
        XCTAssertEqual(SeasonalMarker.springEquinox.evocativePhrase, "Light is rising. The thaw.")
    }

    func testEvocativePhrase_autumnEquinox() {
        XCTAssertEqual(SeasonalMarker.autumnEquinox.evocativePhrase, "Light is fading. The harvest.")
    }

    func testEvocativePhrase_crossQuarter_returnsNil() {
        XCTAssertNil(SeasonalMarker.imbolc.evocativePhrase)
        XCTAssertNil(SeasonalMarker.beltane.evocativePhrase)
        XCTAssertNil(SeasonalMarker.lughnasadh.evocativePhrase)
        XCTAssertNil(SeasonalMarker.samhain.evocativePhrase)
    }

    // MARK: - sealColor

    func testSealColor_forEachTurning() {
        XCTAssertNotNil(SeasonalMarker.springEquinox.sealColor)
        XCTAssertNotNil(SeasonalMarker.summerSolstice.sealColor)
        XCTAssertNotNil(SeasonalMarker.autumnEquinox.sealColor)
        XCTAssertNotNil(SeasonalMarker.winterSolstice.sealColor)
    }

    func testSealColor_crossQuarter_returnsNil() {
        XCTAssertNil(SeasonalMarker.imbolc.sealColor)
        XCTAssertNil(SeasonalMarker.beltane.sealColor)
        XCTAssertNil(SeasonalMarker.lughnasadh.sealColor)
        XCTAssertNil(SeasonalMarker.samhain.sealColor)
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
