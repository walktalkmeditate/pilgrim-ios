import XCTest
@testable import Pilgrim

/// Covers the pure helpers behind the ink-scroll layout cache (AF51):
/// the cache key that decides when the expensive layout (lunar day-scan,
/// milestone scan, per-segment astro colors) recomputes, and the lunar
/// event scan itself.
final class InkScrollLayoutTests: XCTestCase {

    // MARK: - Fixtures

    private let referenceDate = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)

    private func makeSnapshot(
        id: UUID = UUID(),
        daysAgo: Int,
        distance: Double = 1_000
    ) -> WalkSnapshot {
        WalkSnapshot(
            id: id,
            startDate: Calendar.current.date(byAdding: .day, value: -daysAgo, to: referenceDate)!,
            distance: distance,
            duration: 1_800,
            averagePace: 600,
            cumulativeDistance: distance,
            talkDuration: 0,
            meditateDuration: 0,
            favicon: nil,
            isShared: false,
            weatherCondition: nil,
            isSeek: false
        )
    }

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "UTC")
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return components.date!
    }

    // MARK: - Layout cache key

    func testCacheKey_sameInputs_returnsSameKey() {
        let snapshots = [makeSnapshot(daysAgo: 1), makeSnapshot(daysAgo: 10)]
        let first = InkScrollView.layoutCacheKey(snapshots: snapshots, width: 390)
        let second = InkScrollView.layoutCacheKey(snapshots: snapshots, width: 390)
        XCTAssertEqual(first, second)
    }

    func testCacheKey_walkAdded_changesKey() {
        let snapshots = [makeSnapshot(daysAgo: 1), makeSnapshot(daysAgo: 10)]
        let grown = snapshots + [makeSnapshot(daysAgo: 20)]
        XCTAssertNotEqual(
            InkScrollView.layoutCacheKey(snapshots: snapshots, width: 390),
            InkScrollView.layoutCacheKey(snapshots: grown, width: 390)
        )
    }

    func testCacheKey_widthChange_changesKey() {
        let snapshots = [makeSnapshot(daysAgo: 1), makeSnapshot(daysAgo: 10)]
        XCTAssertNotEqual(
            InkScrollView.layoutCacheKey(snapshots: snapshots, width: 390),
            InkScrollView.layoutCacheKey(snapshots: snapshots, width: 430)
        )
    }

    func testCacheKey_dateChange_changesKey() {
        let id = UUID()
        XCTAssertNotEqual(
            InkScrollView.layoutCacheKey(snapshots: [makeSnapshot(id: id, daysAgo: 1)], width: 390),
            InkScrollView.layoutCacheKey(snapshots: [makeSnapshot(id: id, daysAgo: 2)], width: 390)
        )
    }

    func testCacheKey_distanceChange_changesKey() {
        let id = UUID()
        XCTAssertNotEqual(
            InkScrollView.layoutCacheKey(snapshots: [makeSnapshot(id: id, daysAgo: 1, distance: 1_000)], width: 390),
            InkScrollView.layoutCacheKey(snapshots: [makeSnapshot(id: id, daysAgo: 1, distance: 2_000)], width: 390)
        )
    }

    // MARK: - Lunar event scan

    func testFindLunarEvents_knownNewMoon_detectedAsDarkPeak() {
        // 2024-01-11 was a new moon (see LunarPhaseTests).
        let events = InkScrollView.findLunarEvents(
            from: utcDate(2024, 1, 5),
            to: utcDate(2024, 1, 15)
        )
        XCTAssertEqual(events.count, 1)
        XCTAssertLessThan(events[0].illumination, 0.1)
    }

    func testFindLunarEvents_knownFullMoon_detectedAsBrightPeak() {
        // 2024-01-25 was a full moon.
        let events = InkScrollView.findLunarEvents(
            from: utcDate(2024, 1, 20),
            to: utcDate(2024, 1, 30)
        )
        XCTAssertEqual(events.count, 1)
        XCTAssertGreaterThan(events[0].illumination, 0.9)
    }

    func testFindLunarEvents_quarterMoonWindow_returnsEmpty() {
        // Waxing crescent through first quarter — no new/full peaks.
        let events = InkScrollView.findLunarEvents(
            from: utcDate(2024, 1, 15),
            to: utcDate(2024, 1, 18)
        )
        XCTAssertTrue(events.isEmpty)
    }

    func testFindLunarEvents_twoMonthSpan_alternatesExtremePhases() {
        let events = InkScrollView.findLunarEvents(
            from: utcDate(2024, 1, 1),
            to: utcDate(2024, 3, 1)
        )
        XCTAssertGreaterThanOrEqual(events.count, 3)
        for event in events {
            XCTAssertTrue(
                event.illumination < 0.1 || event.illumination > 0.9,
                "Event at \(event.date) has mid-range illumination \(event.illumination)"
            )
        }
    }
}
