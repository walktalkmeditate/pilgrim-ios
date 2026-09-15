// UnitTests/Honor/PilgrimageTilesManagerTests.swift
import Combine
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

    /// One `Task.yield()` is one scheduling hop, not "let the save reach its
    /// next load" — when an earlier test leaves main-actor work queued, a
    /// single hop is not enough and the drive below runs against nothing
    /// pending. Yield until the fake actually has a load to complete,
    /// bounded so a genuine hang fails here, loudly.
    func untilPending(file: StaticString = #filePath, line: UInt = #line) async {
        await until("the save to reach a load", file: file, line: line) { self.loader.hasPendingWork }
    }

    /// The same bounded wait for a state `hasPendingWork` cannot speak for:
    /// a resumed save has its predecessor's cancelled load pending already,
    /// so `untilPending` returns before the new request is recorded.
    func until(_ what: String, file: StaticString = #filePath, line: UInt = #line,
               _ condition: () -> Bool) async {
        for _ in 0..<2_000 where !condition() {
            await Task.yield()
        }
        if !condition() {
            XCTFail("timed out waiting for \(what)", file: file, line: line)
        }
    }

    func testAFreshManagerReportsNothingSaved() {
        XCTAssertEqual(manager.status(for: "camino-frances", stages: stages(3)), .none)
    }

    // MARK: - Estimate

    func testTheEstimateUsesTheRoutesOwnBytesPerTileAndTheSeedByDefault() {
        let three = stages(3)
        let tiles = three.reduce(0) { total, way in
            let rings = WayGeometry.corridor(around: way.route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) },
                                             halfWidthMeters: 500)
            return total + PilgrimageTilesDescriptors.tileCount(rings: rings, zooms: 10...16)
                + PilgrimageTilesDescriptors.tileCount(rings: rings, zooms: 10...14)
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

    // MARK: - Save

    func testASaveLoadsPacksThenRegionsInOrderAndSkipsWhatIsThere() async throws {
        let three = stages(3)
        loader.stylePacks = [.light]
        loader.seed(id: three[1].id, corridorHash: PilgrimageTilesManager.corridorHash(for: three[1]))
        let task = Task { try await manager.save(routeId: "camino-frances", stages: three) }
        await untilPending()
        XCTAssertEqual(loader.packRequests, [.dark], "the light pack was already there")
        loader.completeNextPack()
        await untilPending()
        XCTAssertEqual(loader.regionRequests.map(\.id), [three[0].id])
        loader.completeNextRegion()
        await untilPending()
        XCTAssertEqual(loader.regionRequests.map(\.id), [three[0].id, three[2].id], "stage 1 was complete and current")
        loader.completeNextRegion()
        try await task.value
        XCTAssertEqual(manager.phase, .idle)
        XCTAssertEqual(manager.status(for: "camino-frances", stages: three), .saved(bytes: 300_000))
    }

    func testProgressCountsPacksAndStages() async throws {
        let two = stages(2)
        let task = Task { try await manager.save(routeId: "camino-frances", stages: two) }
        await untilPending()
        XCTAssertEqual(manager.phase, .saving(done: 0, total: 4))
        loader.completeNextPack(); await untilPending()
        loader.completeNextPack(); await untilPending()
        XCTAssertEqual(manager.phase, .saving(done: 2, total: 4))
        loader.completeNextRegion(); await untilPending()
        XCTAssertEqual(manager.phase, .saving(done: 3, total: 4))
        loader.completeNextRegion()
        try await task.value
    }

    func testCancelKeepsWhatIsDoneAndResumeStartsAtTheGap() async throws {
        let four = stages(4)
        loader.seedStylePacks()
        let first = Task { try await manager.save(routeId: "camino-frances", stages: four) }
        await untilPending()
        loader.completeNextRegion(); await untilPending()
        loader.completeNextRegion(); await untilPending()
        manager.cancel()
        _ = try? await first.value
        XCTAssertEqual(manager.phase, .idle)
        XCTAssertEqual(manager.status(for: "camino-frances", stages: four), .partial(saved: 2, of: 4))
        XCTAssertTrue(loader.pendingRegions.isEmpty || loader.pendingRegions.first!.handle.isCancelled)

        loader.regionRequests.removeAll()
        let second = Task { try await manager.save(routeId: "camino-frances", stages: four) }
        // Not `untilPending`: the first save's cancelled load is still queued,
        // so the fake has work before the resumed save has asked for anything.
        await until("the resumed save to request a region") { !self.loader.regionRequests.isEmpty }
        XCTAssertEqual(loader.regionRequests.first?.id, four[2].id, "resume picks up at the first gap")
        // The cancelled load is still queued in the fake; its late completion
        // reaches the manager, which must ignore it, so it takes three
        // completions to finish the two remaining stages.
        await untilPending()
        loader.completeNextRegion(); await untilPending()
        loader.completeNextRegion(); await untilPending()
        loader.completeNextRegion()
        try await second.value
    }

    func testARedrawnStageIsReloadedAndAnUnchangedOneIsNot() async throws {
        var three = stages(3)
        loader.seedStylePacks()
        for way in three { loader.seed(id: way.id, corridorHash: PilgrimageTilesManager.corridorHash(for: way)) }
        // Redraw stage 1: shift its line.
        three[1] = stage(1, count: 3, lonOffset: 0.04 + 0.01)
        let task = Task { try await manager.save(routeId: "camino-frances", stages: three) }
        await untilPending()
        XCTAssertEqual(loader.regionRequests.map(\.id), [three[1].id])
        XCTAssertEqual(loader.regionRequests.first?.corridorHash, PilgrimageTilesManager.corridorHash(for: three[1]))
        XCTAssertEqual(loader.regionRequests.first?.acceptExpired, true)
        await untilPending()
        loader.completeNextRegion()
        try await task.value
    }

    func testAWalkStartingMidSaveStopsItAndKeepsWhatIsDone() async throws {
        let seven = stages(7)
        loader.seedStylePacks()
        var walking = false
        manager.isWalkActive = { walking }
        let task = Task { try await manager.save(routeId: "camino-frances", stages: seven) }
        for _ in 0..<5 { await untilPending(); loader.completeNextRegion() }
        await untilPending()
        walking = true
        loader.completeNextRegion()
        await Task.yield()
        do {
            try await task.value
            XCTFail("expected walkInProgress")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .walkInProgress)
        }
        XCTAssertEqual(loader.regionRequests.count, 6, "no seventh load was requested")
        XCTAssertEqual(manager.status(for: "camino-frances", stages: seven), .partial(saved: 6, of: 7))
    }

    func testRefusedWhileWalkingBeforeAnythingIsRequested() async {
        manager.isWalkActive = { true }
        do {
            try await manager.save(routeId: "camino-frances", stages: stages(2))
            XCTFail("expected walkInProgress")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .walkInProgress)
        }
        XCTAssertTrue(loader.packRequests.isEmpty)
        XCTAssertTrue(loader.regionRequests.isEmpty)
        XCTAssertEqual(manager.phase, .failed(.walkInProgress))
    }

    func testASecondSaveWhileSavingMakesNoCalls() async throws {
        let two = stages(2)
        let first = Task { try await manager.save(routeId: "camino-frances", stages: two) }
        await untilPending()
        try await manager.save(routeId: "camino-frances", stages: two)
        XCTAssertEqual(loader.packRequests.count, 1)
        loader.completeNextPack(); await untilPending()
        loader.completeNextPack(); await untilPending()
        loader.completeNextRegion(); await untilPending()
        loader.completeNextRegion()
        try await first.value
    }

    func testAFailedLoadLandsInFailedKeepsEarlierRegionsAndClears() async throws {
        let three = stages(3)
        loader.seedStylePacks()
        let task = Task { try await manager.save(routeId: "camino-frances", stages: three) }
        await untilPending()
        loader.completeNextRegion(); await untilPending()
        loader.nextRegionFailure = .failed
        loader.completeNextRegion()
        do {
            try await task.value
            XCTFail("expected incomplete")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .incomplete)
        }
        XCTAssertEqual(manager.phase, .failed(.incomplete))
        XCTAssertEqual(manager.status(for: "camino-frances", stages: three), .partial(saved: 1, of: 3))
        manager.cancel()
        XCTAssertEqual(manager.phase, .idle)
    }

    func testAFailedPhaseClearsOnTheNextSave() async throws {
        let one = stages(1)
        loader.seedStylePacks()
        let failing = Task { try await manager.save(routeId: "camino-frances", stages: one) }
        await untilPending()
        loader.nextRegionFailure = .failed
        loader.completeNextRegion()
        do {
            try await failing.value
            XCTFail("expected incomplete")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .incomplete)
        }
        XCTAssertEqual(manager.phase, .failed(.incomplete))

        let second = Task { try await manager.save(routeId: "camino-frances", stages: one) }
        await untilPending()
        XCTAssertEqual(manager.phase, .saving(done: 2, total: 3), "both packs were there; the region is loading again")
        loader.completeNextRegion()
        try await second.value
    }

    func testDiskFullSurfacesAsDiskFull() async {
        loader.seedStylePacks()
        let task = Task { try await manager.save(routeId: "camino-frances", stages: stages(1)) }
        await untilPending()
        loader.nextRegionFailure = .diskFull
        loader.completeNextRegion()
        do {
            try await task.value
            XCTFail("expected diskFull")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .diskFull)
        }
    }

    func testACompletedSaveCalibratesThisRouteOnly() async throws {
        let two = stages(2)
        loader.seedStylePacks()
        loader.bytesPerRegion = 400_000
        let task = Task { try await manager.save(routeId: "camino-frances", stages: two) }
        await untilPending()
        loader.completeNextRegion(); await untilPending()
        loader.completeNextRegion()
        try await task.value
        let expected = 800_000 / manager.tileCount(for: two)
        XCTAssertEqual(defaults.integer(forKey: "pilgrimage.tiles.bytesPerTile.camino-frances"), expected)
        XCTAssertEqual(defaults.integer(forKey: "pilgrimage.tiles.bytesPerTile.kumano-kodo-nakahechi"), 0)
    }

    /// A store read per stage would be thirty-five of them on the Francés,
    /// each one refreshing the loader's cache off the real store.
    func testASaveReadsTheStoreOnceBeforeTheLoopAndOnceToCalibrate() async throws {
        loader.seedStylePacks()
        let task = Task { try await manager.save(routeId: "camino-frances", stages: stages(3)) }
        await untilPending()
        loader.completeNextRegion(); await untilPending()
        loader.completeNextRegion(); await untilPending()
        loader.completeNextRegion()
        try await task.value
        XCTAssertEqual(loader.regionsReadCount, 2, "one snapshot for the loop, one for calibrate")
    }

    /// A view that read `status` before the store answered needs this to
    /// learn the answer arrived.
    func testTheManagerPublishesWhenTheLoaderAnnouncesAChange() async throws {
        var published = false
        let sink = manager.objectWillChange.sink { _ in published = true }
        loader.seedStylePacks()
        let task = Task { try await manager.save(routeId: "camino-frances", stages: stages(1)) }
        await untilPending()

        // `phase` publishes through `@Published` too, so reset here and read
        // back before yielding: the only thing that can have fired in
        // between is the loader's own signal.
        published = false
        loader.completeNextRegion()
        XCTAssertTrue(published)

        try await task.value
        withExtendedLifetime(sink) {}
    }
}
