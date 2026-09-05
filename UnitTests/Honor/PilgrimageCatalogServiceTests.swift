import XCTest
@testable import Pilgrim

@MainActor
final class PilgrimageCatalogServiceTests: XCTestCase {

    private var dir: URL!
    private var clock = Date(timeIntervalSince1970: 3_000_000)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        clock = Date(timeIntervalSince1970: 3_000_000)
        StubURLProtocol.reset()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func makeService() -> PilgrimageCatalogService {
        PilgrimageCatalogService(session: StubURLProtocol.session(),
                                 directory: dir,
                                 now: { [unowned self] in self.clock })
    }

    private func stubIndex(_ data: Data, status: Int = 200, headers: [String: String]? = nil) {
        StubURLProtocol.stub(url: PilgrimageCatalogService.indexURL, status: status, body: data, headers: headers)
    }

    /// Never a tag: jsDelivr caches a tag URL forever, so the moving `v1`
    /// tag still serves a March index with three routes.
    func testTheIndexIsReadFromTheBranchNotAMovingTag() {
        XCTAssertEqual(PilgrimageCatalogService.indexURL.absoluteString,
                       "https://cdn.jsdelivr.net/gh/walktalkmeditate/open-pilgrimages@main/index.json")
        XCTAssertFalse(PilgrimageCatalogService.indexURL.absoluteString.contains("@v1"))
    }

    func testPackageURLsArePinnedToTheExactRelease() {
        XCTAssertEqual(
            PilgrimageCatalogService.packageURL(release: "v1.7.0", routeId: "camino-frances", file: "stage-00.json")?.absoluteString,
            "https://cdn.jsdelivr.net/gh/walktalkmeditate/open-pilgrimages@v1.7.0/routes/camino-frances/ways/stage-00.json")
        XCTAssertNil(PilgrimageCatalogService.packageURL(release: "v1.7.0", routeId: "../etc", file: "route.json"))
        XCTAssertNil(PilgrimageCatalogService.packageURL(release: "main", routeId: "camino-frances", file: "route.json"))
        XCTAssertNil(PilgrimageCatalogService.packageURL(release: "v1.7.0", routeId: "camino-frances", file: "../../secret"))
    }

    func testParsesOnlyRoutesThatCarryAWaysEntryAndALegalSlug() throws {
        let catalog = try PilgrimageCatalogService.parse(PilgrimageFixtures.data("index.json"))
        XCTAssertEqual(catalog.release, "v1.7.0")
        XCTAssertEqual(catalog.routes.map(\.id), ["camino-frances"],
                       "camino-norte has no ways entry; the third id is not a slug")
        let route = try XCTUnwrap(catalog.routes.first)
        XCTAssertEqual(route.name, "Camino de Santiago (Frances)")
        XCTAssertEqual(route.names["es"], "Camino de Santiago (Francés)")
        XCTAssertEqual(route.country, "ES")
        XCTAssertEqual(route.stageCount, 2)
        XCTAssertEqual(route.bytes, 214_000)
    }

    func testTheSparseFlagAndItsDensityCarryThrough() throws {
        let catalog = try PilgrimageCatalogService.parse(PilgrimageFixtures.data("index.json"))
        let route = try XCTUnwrap(catalog.routes.first)
        XCTAssertTrue(route.sparse, "the Camino Francés carries a curated place on fewer than half its stages")
        XCTAssertEqual(route.placesPerStage, 0.4, accuracy: 0.0001)

        // An index written before the flag existed still parses, as dense.
        let base = String(data: try PilgrimageFixtures.data("index.json"), encoding: .utf8)!
        let older = base.replacingOccurrences(
            of: "\"stageCount\": 2, \"bytes\": 214000, \"placesPerStage\": 0.4, \"sparse\": true",
            with: "\"stageCount\": 2, \"bytes\": 214000")
        XCTAssertNotEqual(older, base)
        let olderRoute = try XCTUnwrap(PilgrimageCatalogService.parse(Data(older.utf8)).routes.first)
        XCTAssertFalse(olderRoute.sparse)
        XCTAssertEqual(olderRoute.placesPerStage, 0)
    }

    func testAnAbsurdPlaceDensityDropsTheRoute() throws {
        let base = String(data: try PilgrimageFixtures.data("index.json"), encoding: .utf8)!
        for bad in ["\"placesPerStage\": 51", "\"placesPerStage\": -1", "\"placesPerStage\": 1e300"] {
            let json = base.replacingOccurrences(of: "\"placesPerStage\": 0.4", with: bad)
            XCTAssertNotEqual(json, base, bad)
            XCTAssertTrue(try PilgrimageCatalogService.parse(Data(json.utf8)).routes.isEmpty, bad)
        }
    }

    /// `Dictionary(uniqueKeysWithValues:)` downstream (the catalog view's
    /// ledger map, `List`'s own `Identifiable` diffing) traps on a repeated
    /// id; the parse itself is the one place to make that impossible.
    func testADuplicateRouteIdInTheIndexKeepsOnlyTheFirst() throws {
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: try PilgrimageFixtures.data("index.json")) as? [String: Any])
        var routes = try XCTUnwrap(obj["routes"] as? [[String: Any]])
        routes[1]["id"] = "camino-frances"
        routes[1]["ways"] = ["stageCount": 5, "bytes": 100_000]
        obj["routes"] = routes
        let data = try JSONSerialization.data(withJSONObject: obj)
        let catalog = try PilgrimageCatalogService.parse(data)
        XCTAssertEqual(catalog.routes.map(\.id), ["camino-frances"], "the second row's id repeats the first; first wins")
    }

    func testARepairedReleaseTagIsRefused() throws {
        let base = String(data: try PilgrimageFixtures.data("index.json"), encoding: .utf8)!
        for bad in ["\"release\": \"main\"", "\"release\": \"v1.7\"", "\"release\": \"1.7.0\""] {
            let json = base.replacingOccurrences(of: "\"release\": \"v1.7.0\"", with: bad)
            XCTAssertThrowsError(try PilgrimageCatalogService.parse(Data(json.utf8)), bad) {
                XCTAssertEqual($0 as? PilgrimageError, .catalogUnreachable, bad)
            }
        }
    }

    func testOutOfRangeRouteNumbersDropTheRoute() throws {
        let base = String(data: try PilgrimageFixtures.data("index.json"), encoding: .utf8)!
        for (from, to) in [("\"distanceKm\": 46.1", "\"distanceKm\": 20000"),
                           ("\"stageCount\": 2, \"bytes\": 214000", "\"stageCount\": 900, \"bytes\": 214000"),
                           ("\"stageCount\": 2, \"bytes\": 214000", "\"stageCount\": 2, \"bytes\": 99000000")] {
            let json = base.replacingOccurrences(of: from, with: to)
            XCTAssertNotEqual(json, base, to)
            let catalog = try PilgrimageCatalogService.parse(Data(json.utf8))
            XCTAssertTrue(catalog.routes.isEmpty, to)
        }
    }

    func testFetchesOnceAndThenServesTheCacheForTwentyFourHours() async throws {
        stubIndex(try PilgrimageFixtures.data("index.json"))
        let service = makeService()
        _ = try await service.load()
        XCTAssertEqual(StubURLProtocol.requestedURLs.count, 1)

        clock = clock.addingTimeInterval(23 * 3600)
        let second = makeService()
        let cached = try await second.load()
        XCTAssertEqual(cached.routes.map(\.id), ["camino-frances"])
        XCTAssertEqual(StubURLProtocol.requestedURLs.count, 1, "still inside the 24 h window")

        clock = clock.addingTimeInterval(2 * 3600)
        let third = makeService()
        _ = try await third.load()
        XCTAssertEqual(StubURLProtocol.requestedURLs.count, 2, "past 24 h, it asks again")
    }

    func testAnIndexBiggerThanTheCapIsNeverBuffered() async throws {
        let huge = Data(repeating: 0x7B, count: PilgrimageCatalogService.maxIndexBytes + 1)
        stubIndex(huge)
        let service = makeService()
        do {
            _ = try await service.load()
            XCTFail("expected catalogUnreachable")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .catalogUnreachable)
        }
    }

    /// With no `Content-Length` the guard before the drain reads -1 and lets
    /// the body through, so only the cap counted while streaming can refuse it.
    func testAnIndexThatNeverDeclaresItsLengthIsRefusedByTheCapCountedWhileStreaming() async throws {
        let huge = Data(repeating: 0x7B, count: PilgrimageCatalogService.maxIndexBytes + 1)
        stubIndex(huge, headers: ["Content-Type": "application/json"])
        let service = makeService()
        do {
            _ = try await service.load()
            XCTFail("expected catalogUnreachable")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .catalogUnreachable)
        }
        XCTAssertNil(service.catalog)
    }

    /// A perfectly good index body behind a 404: only the status check refuses
    /// it, and the catalog is out of reach rather than silently empty.
    func testAnIndexServedAsNotFoundIsOutOfReach() async throws {
        stubIndex(try PilgrimageFixtures.data("index.json"), status: 404)
        let service = makeService()
        do {
            _ = try await service.load()
            XCTFail("expected catalogUnreachable")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .catalogUnreachable)
        }
        XCTAssertNil(service.catalog)
    }

    func testAFailedFetchWithACachedIndexDegradesSilently() async throws {
        stubIndex(try PilgrimageFixtures.data("index.json"))
        _ = try await makeService().load()
        StubURLProtocol.reset()
        clock = clock.addingTimeInterval(48 * 3600)
        let offline = makeService()
        let catalog = try await offline.load()
        XCTAssertEqual(catalog.routes.map(\.id), ["camino-frances"],
                       "a stale cache still answers when the network does not")
    }

    func testAFailedFetchWithNoCacheIsOutOfReach() async {
        let service = makeService()
        do {
            _ = try await service.load()
            XCTFail("expected catalogUnreachable")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .catalogUnreachable)
        }
        XCTAssertNil(service.catalog)
    }
}

extension PilgrimageCatalogServiceTests {

    /// Spec 2.2 wants a stage list before anything is downloaded, so tapping
    /// a stage of an undownloaded route has a row to tap.
    func testTheRoutePreviewArrivesBeforeAnythingIsDownloaded() async throws {
        let entry = PilgrimageCatalogEntry(
            id: "camino-frances", name: "Camino", names: [:], country: "ES", region: "Europe",
            distanceKm: 46.1, tradition: "christian", stageCount: 2, bytes: 214_000)
        let url = try XCTUnwrap(PilgrimageCatalogService.packageURL(
            release: "v1.7.0", routeId: "camino-frances", file: "route.json"))
        StubURLProtocol.stub(url: url, body: try PilgrimageFixtures.data("route.json"))

        let service = makeService()
        let route = try await service.routePreview(entry: entry, release: "v1.7.0")
        XCTAssertEqual(route.stages.map(\.index), [0, 1])
        XCTAssertEqual(route.stages[0].name, "Saint-Jean-Pied-de-Port to Roncesvalles")
        XCTAssertEqual(StubURLProtocol.requestedURLs.count, 1)

        // Cached beside the index: a second view of the same route is free.
        _ = try await makeService().routePreview(entry: entry, release: "v1.7.0")
        XCTAssertEqual(StubURLProtocol.requestedURLs.count, 1)
    }

    func testAPreviewThatDoesNotMatchTheEntryIsNotWalkable() async throws {
        let entry = PilgrimageCatalogEntry(
            id: "camino-frances", name: "Camino", names: [:], country: "ES", region: "Europe",
            distanceKm: 46.1, tradition: "christian", stageCount: 5, bytes: 214_000)
        let url = try XCTUnwrap(PilgrimageCatalogService.packageURL(
            release: "v1.7.0", routeId: "camino-frances", file: "route.json"))
        StubURLProtocol.stub(url: url, body: try PilgrimageFixtures.data("route.json"))
        do {
            _ = try await makeService().routePreview(entry: entry, release: "v1.7.0")
            XCTFail("expected notWalkable")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .notWalkable)
        }
    }

    func testAPreviewWithNoNetworkIsOutOfReach() async {
        let entry = PilgrimageCatalogEntry(
            id: "camino-frances", name: "Camino", names: [:], country: "ES", region: "Europe",
            distanceKm: 46.1, tradition: "christian", stageCount: 2, bytes: 214_000)
        do {
            _ = try await makeService().routePreview(entry: entry, release: "v1.7.0")
            XCTFail("expected catalogUnreachable")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .catalogUnreachable)
        }
    }
}

final class PilgrimageCatalogModelTests: XCTestCase {

    private let entry = PilgrimageCatalogEntry(
        id: "camino-frances", name: "Camino de Santiago (Francés)", names: [:], country: "ES",
        region: "Europe", distanceKm: 764, tradition: "christian", stageCount: 33, bytes: 2_140_000)

    private var sparseEntry: PilgrimageCatalogEntry {
        PilgrimageCatalogEntry(
            id: "camino-frances", name: "Camino de Santiago (Francés)", names: [:], country: "ES",
            region: "Europe", distanceKm: 764, tradition: "christian", stageCount: 33,
            bytes: 2_140_000, placesPerStage: 0.4, sparse: true)
    }

    private func stage(_ index: Int) -> PilgrimageRouteStage {
        PilgrimageRouteStage(index: index, name: "Saint-Jean-Pied-de-Port to Roncesvalles",
                             distanceKm: 24.2, gainMeters: 1419,
                             hours: WayStageHours(min: 7, max: 9), difficulty: "hard")
    }

    func testACardWithoutAPackageJustCountsTheStages() {
        XCTAssertEqual(PilgrimageCatalogModel.card(entry: entry, ledger: nil, isInstalled: false, hasUpdate: false),
                       "ES · \(StatsHelper.string(for: 764_000, unit: UnitLength.meters, type: .distance)) · 33 stages")
    }

    func testACardWithAPackageSaysSoAndCarriesItsProgress() {
        var led = PilgrimageLedger(routeId: "camino-frances")
        led.record(stageIndex: 0, name: "a", distanceKm: 24.2,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: Date())
        let line = PilgrimageCatalogModel.card(entry: entry, ledger: led, isInstalled: true, hasUpdate: false)
        XCTAssertTrue(line.contains("on your phone"), line)
        XCTAssertTrue(line.contains("stage 2 of 33"), line)
        XCTAssertFalse(line.contains("updated"), line)
    }

    /// Spec: when the catalog's release is newer than the installed
    /// `release.txt`, the card reads "on your phone · updated · <progress>".
    func testACardWithAnUpdateSaysSoBetweenPhoneAndProgress() {
        var led = PilgrimageLedger(routeId: "camino-frances")
        led.record(stageIndex: 0, name: "a", distanceKm: 24.2,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: Date())
        let line = PilgrimageCatalogModel.card(entry: entry, ledger: led, isInstalled: true, hasUpdate: true)
        XCTAssertTrue(line.contains("on your phone · updated · stage 2 of 33"), line)
    }

    func testASparseRouteSaysSoWithoutHidingItself() {
        XCTAssertEqual(PilgrimageCatalogModel.sparseNote(for: sparseEntry), "few places marked yet")
        XCTAssertNil(PilgrimageCatalogModel.sparseNote(for: entry))
        // The note is its own quiet line, never folded into the meta line.
        XCTAssertFalse(PilgrimageCatalogModel.card(entry: sparseEntry, ledger: nil, isInstalled: false, hasUpdate: false)
            .contains("few places marked yet"))
    }

    func testStageLineReadsDistanceClimbHoursAndDifficulty() {
        let line = PilgrimageRouteModel.stageLine(stage(0))
        XCTAssertTrue(line.hasPrefix(StatsHelper.string(for: 24_200, unit: UnitLength.meters, type: .distance)), line)
        XCTAssertTrue(line.contains(StatsHelper.string(for: 1419, unit: UnitLength.meters, type: .altitude)), line)
        XCTAssertTrue(line.contains("7 to 9 hours"), line)
        XCTAssertTrue(line.hasSuffix("hard"), line)
    }

    func testAStageWithOneHourFigureDoesNotSayItTwice() {
        let single = PilgrimageRouteStage(index: 0, name: "n", distanceKm: 10, gainMeters: 40,
                                          hours: WayStageHours(min: 4, max: 4), difficulty: "easy")
        XCTAssertTrue(PilgrimageRouteModel.stageLine(single).contains("4 hours"))
        XCTAssertFalse(PilgrimageRouteModel.stageLine(single).contains("4 to 4"))
    }

    /// One formatter, two callers: the stage list and the morning card must
    /// not drift apart, and a non-finite figure must never reach `Int(_:)`.
    func testTheStageFactsFormatterIsTheOneBothCallersUse() {
        let facts = WayStageFacts.line(distanceKm: 24.2, gainMeters: 1419,
                                       hours: WayStageHours(min: 7, max: 9), difficulty: "hard")
        XCTAssertEqual(PilgrimageRouteModel.stageLine(stage(0)), facts)
        XCTAssertEqual(WayStageFacts.line(distanceKm: 10, gainMeters: 0,
                                          hours: WayStageHours(min: 4, max: 4), difficulty: ""),
                       "\(StatsHelper.string(for: 10_000, unit: UnitLength.meters, type: .distance)) · " +
                       "\(StatsHelper.string(for: 0, unit: UnitLength.meters, type: .altitude)) up · 4 hours",
                       "an empty difficulty adds no trailing separator")
        XCTAssertTrue(WayStageFacts.line(distanceKm: 10, gainMeters: 40,
                                         hours: WayStageHours(min: .nan, max: .infinity), difficulty: "easy")
            .contains("0 to 100 hours"), "clamped, never trapped")
    }

    func testTheNextRowOffersResumesAndFinallyCongratulates() {
        var led = PilgrimageLedger(routeId: "camino-frances")
        XCTAssertEqual(PilgrimageRouteModel.nextRow(ledger: nil, stageCount: 33), "start with stage 1")
        led.record(stageIndex: 0, name: "a", distanceKm: 24.2,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: Date())
        XCTAssertEqual(PilgrimageRouteModel.nextRow(ledger: led, stageCount: 33), "next: stage 2")
        led.record(stageIndex: 1, name: "b", distanceKm: 21.9,
                   outcome: HonorStageOutcome(progressFrac: 0.58, arrived: false), at: Date())
        XCTAssertEqual(PilgrimageRouteModel.nextRow(ledger: led, stageCount: 33), "continue from where you stopped")
        for index in 1..<33 {
            led.record(stageIndex: index, name: "s", distanceKm: 20,
                       outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: Date())
        }
        XCTAssertEqual(PilgrimageRouteModel.nextRow(ledger: led, stageCount: 33), "you have walked the whole way")
    }

    func testTheButtonSaysWhatItWillDo() {
        XCTAssertEqual(PilgrimageRouteModel.buttonLabel(isInstalled: false, hasUpdate: false), "Download")
        XCTAssertEqual(PilgrimageRouteModel.buttonLabel(isInstalled: true, hasUpdate: true), "Update")
        XCTAssertEqual(PilgrimageRouteModel.buttonLabel(isInstalled: true, hasUpdate: false), "On your phone")
    }

    func testTheRedrawNoticeIsTheSpecsWords() {
        XCTAssertEqual(PilgrimageRouteModel.redrawNotice,
                       "the route's stages were redrawn; your kilometres are kept.")
    }
}
