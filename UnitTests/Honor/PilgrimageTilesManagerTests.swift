// UnitTests/Honor/PilgrimageTilesManagerTests.swift
import XCTest
import CoreLocation
@testable import Pilgrim

@MainActor
final class PilgrimageTilesManagerTests: XCTestCase {

    var loader: FakeTileRegionLoader!
    var defaults: UserDefaults!
    var manager: PilgrimageTilesManager!

    override func setUp() {
        super.setUp()
        loader = FakeTileRegionLoader()
        defaults = UserDefaults(suiteName: "tiles-tests-\(UUID().uuidString)")
        manager = PilgrimageTilesManager(loader: loader, defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.description)
        super.tearDown()
    }

    /// A 3 km straight stage east along latitude 42, 31 points 100 m apart.
    func stage(_ index: Int, count: Int = 3, routeId: String = "camino-frances", lonOffset: Double = 0) -> Way {
        let points = (0...30).map { i in
            WayPoint(lat: 42, lon: lonOffset + Double(i) * 0.001209, alt: nil, t: Double(i) * 60)
        }
        let stage = WayStage(routeId: routeId, index: index, count: count, name: "stage \(index)", theme: "t",
                             narrative: "n", closing: "c", warnings: [], distanceKm: 3, gainMeters: 50,
                             hours: WayStageHours(min: 1, max: 2), difficulty: "easy",
                             start: WayStagePlace(name: "a", at: WayCoordinate(lat: 42, lon: lonOffset)),
                             end: WayStagePlace(name: "b", at: WayCoordinate(lat: 42, lon: lonOffset + 0.03627)))
        return Way(id: WayStore.stageWayId(routeId: routeId, stageIndex: index),
                   source: .pilgrimage(routeId: routeId, stageIndex: index),
                   title: "stage \(index)", departedAt: Date(timeIntervalSince1970: 0), tzIdentifier: nil,
                   expires: nil, route: points, totalDistanceMeters: 3000, theirActiveSeconds: 1800,
                   moments: [], weather: nil, spans: nil, marks: nil, stage: stage)
    }

    func stages(_ count: Int, routeId: String = "camino-frances") -> [Way] {
        (0..<count).map { stage($0, count: count, routeId: routeId, lonOffset: Double($0) * 0.04) }
    }

    func testAFreshManagerReportsNothingSaved() {
        XCTAssertEqual(manager.status(for: "camino-frances", stages: stages(3)), .none)
    }

    // MARK: - Estimate

    func testTheEstimateUsesTheRoutesOwnBytesPerTileAndTheSeedByDefault() {
        let three = stages(3)
        let tiles = three.reduce(0) { total, way in
            let ring = WayGeometry.corridor(around: way.route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) },
                                            halfWidthMeters: 500)
            return total + PilgrimageTilesDescriptors.tileCount(ring: ring, zooms: 10...16)
                + PilgrimageTilesDescriptors.tileCount(ring: ring, zooms: 10...14)
        }
        XCTAssertEqual(manager.estimateBytes(for: "camino-frances", stages: three),
                       tiles * PilgrimageTilesManager.seedBytesPerTile)
        defaults.set(25_000, forKey: "pilgrimage.tiles.bytesPerTile.camino-frances")
        XCTAssertEqual(manager.estimateBytes(for: "camino-frances", stages: three), tiles * 25_000)
        XCTAssertEqual(manager.estimateBytes(for: "kumano-kodo-nakahechi", stages: stages(3, routeId: "kumano-kodo-nakahechi")),
                       tiles * PilgrimageTilesManager.seedBytesPerTile,
                       "another route's calibration never leaks")
    }

    // MARK: - Status

    func testStatusCountsOnlyCompleteRegionsWhoseCorridorStillMatches() {
        let three = stages(3)
        loader.seedStylePacks()
        loader.seed(id: three[0].id, corridorHash: PilgrimageTilesManager.corridorHash(for: three[0]))
        loader.seed(id: three[1].id, corridorHash: "stale")
        loader.seed(id: three[2].id, corridorHash: PilgrimageTilesManager.corridorHash(for: three[2]), complete: false)
        XCTAssertEqual(manager.status(for: "camino-frances", stages: three), .partial(saved: 1, of: 3))
        XCTAssertTrue(manager.isStageSaved(three[0]))
        XCTAssertFalse(manager.isStageSaved(three[1]))
        XCTAssertFalse(manager.isStageSaved(three[2]))
    }

    func testStatusIsSavedOnlyWhenEveryStageAndBothPacksArePresent() {
        let two = stages(2)
        for way in two { loader.seed(id: way.id, corridorHash: PilgrimageTilesManager.corridorHash(for: way), bytes: 50_000) }
        XCTAssertEqual(manager.status(for: "camino-frances", stages: two), .partial(saved: 2, of: 2),
                       "no style packs yet")
        loader.seedStylePacks()
        XCTAssertEqual(manager.status(for: "camino-frances", stages: two), .saved(bytes: 100_000))
    }
}
