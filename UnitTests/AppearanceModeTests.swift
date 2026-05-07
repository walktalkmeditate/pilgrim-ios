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

    func testInit_constellation_fromRawString() {
        XCTAssertEqual(AppearanceMode(rawValue: "constellation"), .constellation)
    }

    func testResolvedScheme_constellation_returnsDark() {
        XCTAssertEqual(AppearanceMode.constellation.resolvedScheme, .dark)
    }

    func testIsConstellation_constellation_returnsTrue() {
        XCTAssertTrue(AppearanceMode.constellation.isConstellation)
    }

    func testIsConstellation_dark_returnsFalse() {
        XCTAssertFalse(AppearanceMode.dark.isConstellation)
    }

    func testIsConstellation_light_returnsFalse() {
        XCTAssertFalse(AppearanceMode.light.isConstellation)
    }

    func testIsConstellation_system_returnsFalse() {
        XCTAssertFalse(AppearanceMode.system.isConstellation)
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

    func testResolvedScheme_updatesWhenPreferenceChanges() {
        UserPreferences.appearanceMode.value = "system"
        let manager = AppearanceManager()
        XCTAssertNil(manager.resolvedScheme)

        let exp = expectation(description: "scheme updates")
        let cancellable = manager.$resolvedScheme
            .dropFirst()
            .sink { _ in exp.fulfill() }

        UserPreferences.appearanceMode.value = "dark"
        waitForExpectations(timeout: 1.0)
        cancellable.cancel()

        XCTAssertEqual(manager.resolvedScheme, .dark)
    }

    func testResolvedScheme_invalidValue_fallsBackToNil() {
        UserPreferences.appearanceMode.value = "bogus"
        let manager = AppearanceManager()
        XCTAssertNil(manager.resolvedScheme)
    }

    func testIsConstellation_default_isFalse() {
        UserPreferences.appearanceMode.value = "system"
        let manager = AppearanceManager()
        XCTAssertFalse(manager.isConstellation)
    }

    func testIsConstellation_constellation_isTrueAndSchemeIsDark() {
        UserPreferences.appearanceMode.value = "constellation"
        let manager = AppearanceManager()
        XCTAssertTrue(manager.isConstellation)
        XCTAssertEqual(manager.resolvedScheme, .dark)
    }

    func testIsConstellation_updatesWhenPreferenceChanges() {
        UserPreferences.appearanceMode.value = "system"
        let manager = AppearanceManager()
        XCTAssertFalse(manager.isConstellation)

        let exp = expectation(description: "isConstellation flips")
        let cancellable = manager.$isConstellation
            .dropFirst()
            .sink { _ in exp.fulfill() }

        UserPreferences.appearanceMode.value = "constellation"
        waitForExpectations(timeout: 1.0)
        cancellable.cancel()

        XCTAssertTrue(manager.isConstellation)
        XCTAssertEqual(manager.resolvedScheme, .dark)
    }

    func testIsConstellation_darkToConstellation_flipsWithoutSchemeChange() {
        UserPreferences.appearanceMode.value = "dark"
        let manager = AppearanceManager()
        XCTAssertFalse(manager.isConstellation)
        XCTAssertEqual(manager.resolvedScheme, .dark)

        let exp = expectation(description: "isConstellation flips to true")
        let cancellable = manager.$isConstellation
            .dropFirst()
            .sink { _ in exp.fulfill() }

        UserPreferences.appearanceMode.value = "constellation"
        waitForExpectations(timeout: 1.0)
        cancellable.cancel()

        XCTAssertTrue(manager.isConstellation)
        XCTAssertEqual(manager.resolvedScheme, .dark)
    }

    func testIsConstellation_constellationToDark_flipsWithoutSchemeChange() {
        UserPreferences.appearanceMode.value = "constellation"
        let manager = AppearanceManager()
        XCTAssertTrue(manager.isConstellation)

        let exp = expectation(description: "isConstellation flips to false")
        let cancellable = manager.$isConstellation
            .dropFirst()
            .sink { _ in exp.fulfill() }

        UserPreferences.appearanceMode.value = "dark"
        waitForExpectations(timeout: 1.0)
        cancellable.cancel()

        XCTAssertFalse(manager.isConstellation)
        XCTAssertEqual(manager.resolvedScheme, .dark)
    }
}
