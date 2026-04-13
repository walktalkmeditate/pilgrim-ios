import XCTest
@testable import Pilgrim

final class LightReadingGeneratorTests: XCTestCase {

    // MARK: - Priority ladder tests

    func testLunarEclipseFiresForKnownEclipseDate() {
        // 2026-03-03 is a known total lunar eclipse
        let walk = syntheticWalk(
            startDate: iso("2026-03-03T11:30:00Z"),
            latitude: 48.8566, longitude: 2.3522
        )
        let reading = LightReadingGenerator.generate(for: walk)
        XCTAssertEqual(reading.tier, .lunarEclipse)
        XCTAssertFalse(reading.sentence.contains("{"), "Placeholder leaked: \(reading.sentence)")
    }

    func testBaselineAlwaysFires() {
        let walk = syntheticWalk(
            startDate: iso("2026-04-15T14:00:00Z"),
            latitude: 48.8566, longitude: 2.3522
        )
        let reading = LightReadingGenerator.generate(for: walk)
        XCTAssertFalse(reading.sentence.isEmpty)
        XCTAssertFalse(reading.sentence.contains("{"), "Placeholder leaked: \(reading.sentence)")
    }

    func testSameWalkDeterministic() {
        let walk = syntheticWalk(
            startDate: iso("2026-06-21T12:00:00Z"),
            latitude: 48.8566, longitude: 2.3522
        )
        let reading1 = LightReadingGenerator.generate(for: walk)
        let reading2 = LightReadingGenerator.generate(for: walk)
        XCTAssertEqual(reading1, reading2, "Same walk must produce same reading every time")
        XCTAssertFalse(reading1.sentence.contains("{"), "Placeholder leaked: \(reading1.sentence)")
    }

    func testFullMoonTierFiresForKnownFullMoon() {
        // 2026-04-02: full moon, no eclipse, no supermoon (nearest is Dec 24 2026),
        // not a seasonal marker, 20 days before Lyrids peak (Apr 22) — clean date.
        // Use 22:00Z (midnight Paris local) so the sun is below the horizon and
        // the moon-tier night gate does not block.
        let walk = syntheticWalk(
            startDate: iso("2026-04-02T22:00:00Z"),
            latitude: 48.8566, longitude: 2.3522
        )
        let reading = LightReadingGenerator.generate(for: walk)
        XCTAssertEqual(reading.tier, .fullMoon, "Expected fullMoon tier, got \(reading.tier)")
        XCTAssertFalse(reading.sentence.contains("{"), "Placeholder leaked: \(reading.sentence)")
    }

    func testFullMoonDoesNotFireInDaylight() {
        // Same full-moon date but at noon (sun well above horizon). The moon tier
        // must skip and the daylight baseline must fire.
        let walk = syntheticWalk(
            startDate: iso("2026-04-02T12:00:00Z"),
            latitude: 48.8566, longitude: 2.3522
        )
        let reading = LightReadingGenerator.generate(for: walk)
        XCTAssertNotEqual(reading.tier, .fullMoon, "fullMoon must not fire during daytime")
        XCTAssertNotEqual(reading.tier, .moonPhase, "moonPhase must not fire during daytime")
        XCTAssertEqual(reading.tier, .daylight, "Expected daylight tier for noon full-moon walk, got \(reading.tier)")
        XCTAssertFalse(reading.sentence.contains("{"), "Placeholder leaked: \(reading.sentence)")
    }

    func testDaylightBaselineFiresForOrdinaryDaytimeWalk() {
        // Ordinary April afternoon in Paris — no rare events, sun is up.
        let walk = syntheticWalk(
            startDate: iso("2026-04-15T14:00:00Z"),
            latitude: 48.8566, longitude: 2.3522
        )
        let reading = LightReadingGenerator.generate(for: walk)
        XCTAssertEqual(reading.tier, .daylight, "Expected daylight tier, got \(reading.tier)")
        XCTAssertFalse(reading.sentence.isEmpty)
        XCTAssertFalse(reading.sentence.contains("{"), "Placeholder leaked: \(reading.sentence)")
    }

    func testSeasonalMarkerFiresForAllEightMarkers() {
        // Known equinox/solstice dates where the sun is squarely within the ±1.5°
        // window that CelestialCalculator.seasonalMarker requires.
        // 2026-12-21 is within ±3 days of the Dec 24 supermoon, so supermoon wins.
        // Use 2027-12-22 for winter solstice instead (no supermoon nearby in 2027).
        let cases: [(String, String)] = [
            ("2026-03-20T12:00:00Z", "spring equinox"),
            ("2026-06-21T12:00:00Z", "summer solstice"),
            ("2026-09-23T12:00:00Z", "autumn equinox"),
            ("2027-12-22T12:00:00Z", "winter solstice"),
            ("2027-02-04T12:00:00Z", "imbolc"),
            ("2027-05-05T12:00:00Z", "beltane"),
            ("2027-08-07T12:00:00Z", "lughnasadh"),
            ("2027-11-07T12:00:00Z", "samhain"),
        ]
        for (dateStr, expectedKeyword) in cases {
            let walk = syntheticWalk(
                startDate: iso(dateStr),
                latitude: 48.8566, longitude: 2.3522
            )
            let reading = LightReadingGenerator.generate(for: walk)
            XCTAssertEqual(reading.tier, .seasonalMarker,
                "Walk on \(dateStr) should fire seasonalMarker tier, got \(reading.tier)")
            XCTAssertTrue(reading.sentence.lowercased().contains(expectedKeyword),
                "Reading for \(dateStr) should contain '\(expectedKeyword)', got '\(reading.sentence)'")
            XCTAssertFalse(reading.sentence.contains("{"), "Placeholder leaked: \(reading.sentence)")
        }
    }

    func testSunriseTierFiresForWalkAtSunrise() {
        // Paris sunrise on 2024-06-22 is ~03:48 UTC (not a seasonal marker day).
        // A walk starting at 03:46 UTC (2 min before sunrise) should fire a
        // sun-related tier. The seasonal marker tier is also acceptable because
        // it outranks the sun tiers in the priority ladder.
        let walk = syntheticWalk(
            startDate: iso("2024-06-22T03:46:00Z"),
            latitude: 48.8566, longitude: 2.3522
        )
        let reading = LightReadingGenerator.generate(for: walk)
        XCTAssertTrue(
            [.sunriseSunset, .twilight, .goldenHour, .seasonalMarker].contains(reading.tier),
            "Walk at sunrise should fire a sun-related tier, got \(reading.tier)"
        )
        XCTAssertFalse(reading.sentence.contains("{"), "Placeholder leaked: \(reading.sentence)")
    }

    func testOutputSentenceIsNonEmptyForAllTiers() {
        // Verify no placeholder leaks through as a raw {key} in the sentence.
        let scenarios: [(String, Double, Double)] = [
            ("2026-03-03T11:30:00Z", 48.8566, 2.3522),  // eclipse
            ("2026-04-02T12:00:00Z", 48.8566, 2.3522),  // full moon
            ("2026-04-15T03:00:00Z", 48.8566, 2.3522),  // nighttime
            ("2024-06-21T03:45:00Z", 48.8566, 2.3522),  // sunrise
        ]
        for (dateStr, lat, lon) in scenarios {
            let walk = syntheticWalk(startDate: iso(dateStr), latitude: lat, longitude: lon)
            let reading = LightReadingGenerator.generate(for: walk)
            XCTAssertFalse(reading.sentence.isEmpty, "Sentence empty for \(dateStr)")
            XCTAssertFalse(reading.sentence.contains("{"), "Placeholder leaked: \(reading.sentence)")
        }
    }

    func testWalkWithNoRouteDataFallsBackToMoonPhase() {
        let walk = WalkDataFactory.makeWalk(
            uuid: UUID(),
            startDate: iso("2026-04-15T14:00:00Z"),
            routeData: []
        )
        let reading = LightReadingGenerator.generate(for: walk)
        // Without coordinates, sun-related tiers can't fire; falls back to
        // the moon-phase or new/full moon tiers.
        XCTAssertFalse(reading.sentence.isEmpty)
        XCTAssertFalse(reading.sentence.contains("{"), "Placeholder leaked: \(reading.sentence)")
    }

    func testWalkWithoutCoordinatesFallsThroughToLocationIndependentTier() {
        // A walk with no routeData has no coordinates, so the SolarHorizon-
        // based tiers (deepNight, sunriseSunset, twilight, goldenHour) cannot
        // fire. With no altitude available, the moon-tier night gate treats
        // altitude as nil and falls through to moon tiers (preserves the V1
        // nil-coordinate path). The daylight tier only fires when we have
        // confirmed coordinates with the sun above the horizon.
        //
        // We use an ordinary afternoon in April that isn't any rare event,
        // so the expected outcome is the moonPhase baseline.
        let walkNoRoute = WalkDataFactory.makeWalk(
            uuid: Self.fixedWalkUUID,
            startDate: iso("2026-04-15T14:00:00Z"),
            routeData: []
        )
        let reading = LightReadingGenerator.generate(for: walkNoRoute)

        let locationIndependent: Set<LightReading.Tier> = [
            .lunarEclipse, .supermoon, .seasonalMarker, .meteorShowerPeak,
            .fullMoon, .newMoon, .moonPhase
        ]
        XCTAssertTrue(locationIndependent.contains(reading.tier),
            "Walk with no coordinates should fire a location-independent tier, got \(reading.tier)")
        XCTAssertNotEqual(reading.tier, .daylight,
            "daylight must not fire for no-coordinate walks (no altitude to confirm sun is up)")
        XCTAssertFalse(reading.sentence.isEmpty)
        XCTAssertFalse(reading.sentence.contains("{"), "Placeholder leaked: \(reading.sentence)")
    }

    // MARK: - Helpers

    private func iso(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    private static let fixedWalkUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private func syntheticWalk(startDate: Date, latitude: Double, longitude: Double, uuid: UUID = fixedWalkUUID) -> WalkInterface {
        let routeSample = WalkDataFactory.makeRouteDataSample(
            timestamp: startDate,
            latitude: latitude,
            longitude: longitude
        )
        return WalkDataFactory.makeWalk(
            uuid: uuid,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(1800),
            routeData: [routeSample]
        )
    }
}
