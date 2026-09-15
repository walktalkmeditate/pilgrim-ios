// UnitTests/Honor/OfflineMapsViewModelTests.swift
import XCTest
@testable import Pilgrim

@MainActor
final class OfflineMapsViewModelTests: XCTestCase {

    func testTheRowSaysNoneSavedOrTheRouteAndItsBytes() {
        XCTAssertEqual(OfflineMapsModel.rowDetail(nil), "none saved")
        let saved = OfflineMapsModel.Saved(routeName: "Camino de Santiago (Frances)", bytes: 26_100_000, savedStages: 33, totalStages: 33)
        XCTAssertEqual(OfflineMapsModel.rowDetail(saved), "Camino de Santiago (Frances) · 26 MB")
    }

    func testTheCopyIsTheSpecs() {
        XCTAssertEqual(OfflineMapsModel.emptyCaption, "no maps saved")
        XCTAssertEqual(OfflineMapsModel.deleteTitle, "Delete maps?")
        XCTAssertEqual(OfflineMapsModel.deleteMessage, "Removes the saved basemap. The route's stages stay on your phone.")
    }

    private func stages(_ count: Int = 3) -> [Way] {
        (0..<count).map { index -> Way in
            let points = [WayPoint(lat: 42, lon: Double(index) * 0.05, alt: nil, t: 0), WayPoint(lat: 42, lon: Double(index) * 0.05 + 0.01, alt: nil, t: 60)]
            let stage = WayStage(routeId: "camino-frances", index: index, count: count, name: "s", theme: "t", narrative: "n", closing: "c",
                                 warnings: [], distanceKm: 1, gainMeters: 0, hours: WayStageHours(min: 1, max: 1), difficulty: "easy",
                                 start: WayStagePlace(name: "a", at: WayCoordinate(lat: 42, lon: 0)), end: WayStagePlace(name: "b", at: WayCoordinate(lat: 42, lon: 0.01)))
            return Way(id: WayStore.stageWayId(routeId: "camino-frances", stageIndex: index), source: .pilgrimage(routeId: "camino-frances", stageIndex: index),
                       title: "s", departedAt: Date(), tzIdentifier: nil, expires: nil, route: points, totalDistanceMeters: 1000,
                       theirActiveSeconds: 600, moments: [], weather: nil, spans: nil, marks: nil, stage: stage)
        }
    }

    private func manager(_ loader: FakeTileRegionLoader) -> PilgrimageTilesManager {
        PilgrimageTilesManager(loader: loader, defaults: UserDefaults(suiteName: "om-\(UUID().uuidString)")!)
    }

    /// A partial save still counts as "saved" for the settings row — there
    /// are bytes on the phone to delete — and the view says how many stages.
    func testLoadReadsTheInstalledRouteThroughTheTilesManager() {
        let loader = FakeTileRegionLoader()
        let tiles = manager(loader)
        let stages = stages()
        loader.seed(id: stages[0].id, corridorHash: PilgrimageTilesManager.corridorHash(for: stages[0]), bytes: 5_000_000)
        let saved = OfflineMapsModel.load(routeName: "Camino de Santiago (Frances)", routeId: "camino-frances", stages: stages, tiles: tiles)
        XCTAssertEqual(saved, OfflineMapsModel.Saved(routeName: "Camino de Santiago (Frances)", bytes: 5_000_000, savedStages: 1, totalStages: 3))
        XCTAssertEqual(loader.regionsReadCount, 1, "one store read for the whole route, not one per stage")
        XCTAssertNil(OfflineMapsModel.load(routeName: "x", routeId: "camino-frances", stages: [], tiles: tiles))
    }

    /// An Update redraws the way and every region's corridor hash goes
    /// stale at once. The bytes are still on the phone, so the row has to
    /// keep showing them — otherwise Delete is the one thing the walker
    /// cannot reach.
    func testStaleRegionsStillCountTowardBytesSoDeleteIsReachable() {
        let loader = FakeTileRegionLoader()
        let tiles = manager(loader)
        let stages = stages()
        loader.seed(id: stages[0].id, corridorHash: "stale", bytes: 5_000_000)
        XCTAssertEqual(OfflineMapsModel.load(routeName: "Camino de Santiago (Frances)", routeId: "camino-frances",
                                             stages: stages, tiles: tiles),
                       OfflineMapsModel.Saved(routeName: "Camino de Santiago (Frances)", bytes: 5_000_000,
                                              savedStages: 0, totalStages: 3))
    }
}
