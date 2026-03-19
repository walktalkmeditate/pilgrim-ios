import XCTest
@testable import Pilgrim

final class UnitSystemTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        UserPreferences.distanceMeasurementType.delete()
        UserPreferences.altitudeMeasurementType.delete()
        UserPreferences.speedMeasurementType.delete()
        UserPreferences.weightMeasurementType.delete()
        UserPreferences.energyMeasurementType.delete()
    }

    func testApplyUnitSystem_metric_setsKilometers() {
        UserPreferences.applyUnitSystem(metric: true)
        XCTAssertEqual(UserPreferences.distanceMeasurementType.value, .kilometers)
    }

    func testApplyUnitSystem_metric_setsMeters() {
        UserPreferences.applyUnitSystem(metric: true)
        XCTAssertEqual(UserPreferences.altitudeMeasurementType.value, .meters)
    }

    func testApplyUnitSystem_metric_setsKilojoules() {
        UserPreferences.applyUnitSystem(metric: true)
        XCTAssertEqual(UserPreferences.energyMeasurementType.value, .kilojoules)
    }

    func testApplyUnitSystem_metric_setsMinutesPerKilometer() {
        UserPreferences.applyUnitSystem(metric: true)
        XCTAssertEqual(UserPreferences.speedMeasurementType.value, .minutesPerLengthUnit(from: .kilometers))
    }

    func testApplyUnitSystem_metric_setsKilograms() {
        UserPreferences.applyUnitSystem(metric: true)
        XCTAssertEqual(UserPreferences.weightMeasurementType.value, .kilograms)
    }

    func testApplyUnitSystem_imperial_setsMiles() {
        UserPreferences.applyUnitSystem(metric: false)
        XCTAssertEqual(UserPreferences.distanceMeasurementType.value, .miles)
    }

    func testApplyUnitSystem_imperial_setsFeet() {
        UserPreferences.applyUnitSystem(metric: false)
        XCTAssertEqual(UserPreferences.altitudeMeasurementType.value, .feet)
    }

    func testApplyUnitSystem_imperial_setsKilocalories() {
        UserPreferences.applyUnitSystem(metric: false)
        XCTAssertEqual(UserPreferences.energyMeasurementType.value, .kilocalories)
    }

    func testApplyUnitSystem_imperial_setsMinutesPerMile() {
        UserPreferences.applyUnitSystem(metric: false)
        XCTAssertEqual(UserPreferences.speedMeasurementType.value, .minutesPerLengthUnit(from: .miles))
    }

    func testApplyUnitSystem_imperial_setsPounds() {
        UserPreferences.applyUnitSystem(metric: false)
        XCTAssertEqual(UserPreferences.weightMeasurementType.value, .pounds)
    }
}
