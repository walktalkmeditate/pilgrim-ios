import XCTest
import SwiftUI
@testable import Pilgrim

final class AppearanceModeTests: XCTestCase {

    func testInit_system_fromRawString() {
        XCTAssertEqual(AppearanceMode(rawValue: "system"), .system)
    }

    func testInit_light_fromRawString() {
        XCTAssertEqual(AppearanceMode(rawValue: "light"), .light)
    }

    func testInit_dark_fromRawString() {
        XCTAssertEqual(AppearanceMode(rawValue: "dark"), .dark)
    }

    func testInit_invalidString_returnsNil() {
        XCTAssertNil(AppearanceMode(rawValue: "invalid"))
    }

    func testResolvedScheme_system_returnsNil() {
        XCTAssertNil(AppearanceMode.system.resolvedScheme)
    }

    func testResolvedScheme_light_returnsLight() {
        XCTAssertEqual(AppearanceMode.light.resolvedScheme, .light)
    }

    func testResolvedScheme_dark_returnsDark() {
        XCTAssertEqual(AppearanceMode.dark.resolvedScheme, .dark)
    }
}

final class AppearanceManagerTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        UserPreferences.appearanceMode.value = "system"
    }

    func testPreferenceDefault_isSystem() {
        UserPreferences.appearanceMode.delete()
        XCTAssertEqual(UserPreferences.appearanceMode.value, "system")
    }

    func testResolvedScheme_defaultIsNil() {
        UserPreferences.appearanceMode.value = "system"
        let manager = AppearanceManager()
        XCTAssertNil(manager.resolvedScheme)
    }

    func testResolvedScheme_light_returnsLight() {
        UserPreferences.appearanceMode.value = "light"
        let manager = AppearanceManager()
        XCTAssertEqual(manager.resolvedScheme, .light)
    }

    func testResolvedScheme_dark_returnsDark() {
        UserPreferences.appearanceMode.value = "dark"
        let manager = AppearanceManager()
        XCTAssertEqual(manager.resolvedScheme, .dark)
    }

    func testResolvedScheme_invalidValue_fallsBackToNil() {
        UserPreferences.appearanceMode.value = "bogus"
        let manager = AppearanceManager()
        XCTAssertNil(manager.resolvedScheme)
    }
}
