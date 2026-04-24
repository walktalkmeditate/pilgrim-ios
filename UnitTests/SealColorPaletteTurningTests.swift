import XCTest
import UIKit
@testable import Pilgrim

final class SealColorPaletteTurningTests: XCTestCase {

    private func sealInput(year: Int, month: Int, day: Int, lat: Double, lon: Double, favicon: String? = "leaf") -> SealInput {
        let date = DateFactory.makeDate(year, month, day, 12, 0, 0)
        let route = WalkDataFactory.makeRouteDataSample(latitude: lat, longitude: lon)
        let walk = WalkDataFactory.makeWalk(startDate: date, routeData: [route], favicon: favicon)
        return SealInput(walk: walk)
    }

    // MARK: - Turning day override

    func testTurningDayInput_northernJuneSolstice_returnsGoldSealColor() {
        let input = sealInput(year: 2024, month: 6, day: 20, lat: 40.7, lon: -74.0)
        let color = SealColorPalette.uiColor(for: input)
        XCTAssertEqual(color, UIColor(named: "turningGold"))
    }

    func testTurningDayInput_southernJuneSolstice_returnsIndigoSealColor() {
        let input = sealInput(year: 2024, month: 6, day: 20, lat: -33.9, lon: 151.2)
        let color = SealColorPalette.uiColor(for: input)
        XCTAssertEqual(color, UIColor(named: "turningIndigo"))
    }

    func testTurningDayInput_northernMarchEquinox_returnsJadeSealColor() {
        let input = sealInput(year: 2024, month: 3, day: 20, lat: 40.7, lon: -74.0)
        let color = SealColorPalette.uiColor(for: input)
        XCTAssertEqual(color, UIColor(named: "turningJade"))
    }

    func testTurningDayInput_northernSeptemberEquinox_returnsClaretSealColor() {
        let input = sealInput(year: 2024, month: 9, day: 22, lat: 40.7, lon: -74.0)
        let color = SealColorPalette.uiColor(for: input)
        XCTAssertEqual(color, UIColor(named: "turningClaret"))
    }

    // MARK: - Turning override ignores favicon

    func testTurningDayInput_ignoresFaviconHashSelection() {
        let input = sealInput(year: 2024, month: 6, day: 20, lat: 40.7, lon: -74.0, favicon: "flame")
        let color = SealColorPalette.uiColor(for: input)
        XCTAssertEqual(color, UIColor(named: "turningGold"))
        XCTAssertNotEqual(color, SealColorPalette.rust.light)
    }

    // MARK: - Non-turning walks unchanged

    func testNonTurningInput_isNotATurningColor() {
        let input = sealInput(year: 2024, month: 5, day: 15, lat: 40.7, lon: -74.0, favicon: "leaf")
        let color = SealColorPalette.uiColor(for: input)
        let turningColors: [UIColor] = [
            UIColor(named: "turningJade")!,
            UIColor(named: "turningGold")!,
            UIColor(named: "turningClaret")!,
            UIColor(named: "turningIndigo")!
        ]
        XCTAssertFalse(turningColors.contains(color), "Non-turning walk must not get a turning color")
    }

    // MARK: - SeasonalMarker.sealColor

    func testSealColor_forEachTurning() {
        XCTAssertEqual(SeasonalMarker.springEquinox.sealColor?.light, UIColor(named: "turningJade"))
        XCTAssertEqual(SeasonalMarker.summerSolstice.sealColor?.light, UIColor(named: "turningGold"))
        XCTAssertEqual(SeasonalMarker.autumnEquinox.sealColor?.light, UIColor(named: "turningClaret"))
        XCTAssertEqual(SeasonalMarker.winterSolstice.sealColor?.light, UIColor(named: "turningIndigo"))
    }

    func testSealColor_crossQuarter_returnsNil() {
        XCTAssertNil(SeasonalMarker.imbolc.sealColor)
    }
}
