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
