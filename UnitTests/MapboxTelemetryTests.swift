import XCTest
@testable import Pilgrim

final class MapboxTelemetryTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "MapboxTelemetryTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// The SDK registers `true` as the default for this key and reads it
    /// through KVO, so the key name is the whole contract with it.
    func testKey_isTheOneTheMapboxSDKObserves() {
        XCTAssertEqual(MapboxTelemetry.metricsEnabledKey, "MGLMapboxMetricsEnabled")
    }

    func testOptOut_overridesTheSDKsRegisteredDefault() {
        defaults.register(defaults: [MapboxTelemetry.metricsEnabledKey: true])

        MapboxTelemetry.optOut(defaults)

        XCTAssertFalse(defaults.bool(forKey: MapboxTelemetry.metricsEnabledKey))
    }

    /// The test host launches through `AppDelegate`, so this is the launch
    /// path's own write, not the helper's.
    func testAppLaunch_hasAlreadyOptedOut() {
        XCTAssertNotNil(UserDefaults.standard.object(forKey: MapboxTelemetry.metricsEnabledKey))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: MapboxTelemetry.metricsEnabledKey))
    }

    func testOptOut_turnsOffAnEarlierOptIn() {
        defaults.set(true, forKey: MapboxTelemetry.metricsEnabledKey)

        MapboxTelemetry.optOut(defaults)

        XCTAssertFalse(defaults.bool(forKey: MapboxTelemetry.metricsEnabledKey))
    }
}
