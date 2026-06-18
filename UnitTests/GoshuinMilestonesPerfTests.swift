import XCTest
@testable import Pilgrim

/// Confirms the goshuin pagination lag root cause: GoshuinMilestones.detect()
/// is O(allWalks) and is called once per seal cell (6 per page) on the main
/// thread every time a page builds during a TabView swipe. Measures the
/// per-page main-thread cost as the walk count grows.
final class GoshuinMilestonesPerfTests: XCTestCase {

    private func makeWalks(_ count: Int) -> [TempWalk] {
        (0..<count).map { i in
            // Spread across years + seasons + latitudes so isFirstOfSeason does real work.
            let year = 2022 + (i % 4)
            let month = 1 + (i % 12)
            let lat = Double((i % 160) - 80)
            return WalkDataFactory.makeWalk(
                uuid: UUID(),
                distance: Double(500 + (i * 37) % 20000),
                startDate: DateFactory.makeDate(year, month, 1 + (i % 27), 9, 0, 0),
                meditateDuration: Double((i % 5) * 300),
                routeData: [WalkDataFactory.makeRouteDataSample(latitude: lat, longitude: Double(i))]
            )
        }
    }

    /// One page = 6 seal cells, each calling detect(allWalks). Measure that.
    private func timeOnePageRender(walks: [TempWalk]) -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        for cell in 0..<6 {
            _ = GoshuinMilestones.detect(
                walkCount: walks.count,
                walkIndex: cell,
                walk: walks[cell % walks.count],
                allWalks: walks
            )
        }
        return (CFAbsoluteTimeGetCurrent() - start) * 1000  // ms
    }

    /// Guards that GoshuinMilestones.detect() stays cheap. It is NOT the source
    /// of the goshuin pagination lag (measured ~1.4ms for one page even at 400
    /// walks) — that's the seal-thumbnail load path. This test exists so a
    /// future change that makes detect() O(n)-expensive per cell is caught,
    /// rather than re-investigated as a "new" lag.
    func test_detect_perPageCost_staysCheap() {
        for n in [20, 50, 100, 200, 400] {
            let walks = makeWalks(n)
            _ = timeOnePageRender(walks: walks)  // warm
            let runs = (0..<5).map { _ in timeOnePageRender(walks: walks) }
            let avg = runs.reduce(0, +) / Double(runs.count)
            print(String(format: "[GOSHUIN-PERF] N=%d walks → one page (6 detect calls) = %.2f ms", n, avg))
        }
        // Generous ceiling (observed ~1.4ms at N=400); a real regression would
        // be 10x+ this. Final size is the worst case.
        let avg400 = (0..<5).map { _ in timeOnePageRender(walks: makeWalks(400)) }.reduce(0, +) / 5
        XCTAssertLessThan(avg400, 10.0, "detect() per page regressed badly — it should stay well under a frame budget")
    }
}
