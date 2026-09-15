import XCTest
import CoreLocation
@testable import Pilgrim

final class FakeTileRegionLoaderTests: XCTestCase {

    private let rings = [[
        CLLocationCoordinate2D(latitude: 42, longitude: 0), CLLocationCoordinate2D(latitude: 42, longitude: 0.01),
        CLLocationCoordinate2D(latitude: 42.01, longitude: 0.01), CLLocationCoordinate2D(latitude: 42.01, longitude: 0),
        CLLocationCoordinate2D(latitude: 42, longitude: 0)
    ]]

    func testALoadIsRecordedAndCompletesIntoTheStore() {
        let fake = FakeTileRegionLoader()
        let request = TileRegionRequest(id: "pilgrimage:camino-frances:0", rings: rings, corridorHash: "h", acceptExpired: true)
        var result: Result<TileRegionSummary, TileRegionLoadingError>?
        _ = fake.loadRegion(request, progress: { _, _ in }) { result = $0 }
        XCTAssertEqual(fake.regionRequests, [request])
        XCTAssertTrue(fake.regions().isEmpty, "nothing is stored until the load completes")
        fake.completeNextRegion()
        XCTAssertEqual(try result?.get().id, request.id)
        XCTAssertEqual(fake.regions().first?.corridorHash, "h")
        XCTAssertTrue(fake.regions().first?.isComplete ?? false)
    }

    func testAFailureIsDeliveredOnceAndStoresNothing() {
        let fake = FakeTileRegionLoader()
        let request = TileRegionRequest(id: "pilgrimage:camino-frances:0", rings: rings, corridorHash: "h", acceptExpired: true)
        var result: Result<TileRegionSummary, TileRegionLoadingError>?
        _ = fake.loadRegion(request, progress: { _, _ in }) { result = $0 }
        fake.nextRegionFailure = .diskFull
        fake.completeNextRegion()
        if case .failure(let error)? = result { XCTAssertEqual(error, .diskFull) } else { XCTFail("expected failure") }
        XCTAssertTrue(fake.regions().isEmpty)
        XCTAssertNil(fake.nextRegionFailure, "one failure, not a sticky one")
    }

    /// Production always answers `refreshRegions` asynchronously; a fake
    /// that answered inline would let a test prove a launch sweep ran
    /// before the store had spoken.
    func testRefreshRegionsAnswersOnlyWhenReleasedAndOnce() {
        let fake = FakeTileRegionLoader()
        var answered = 0
        fake.refreshRegions { answered += 1 }
        XCTAssertEqual(answered, 0, "nothing answers until the store speaks")
        fake.releaseRegions()
        XCTAssertEqual(answered, 1)
        fake.releaseRegions()
        XCTAssertEqual(answered, 1, "a completion is delivered once")
    }

    func testSeedAndRemoveAndPacks() {
        let fake = FakeTileRegionLoader()
        fake.seed(id: "pilgrimage:camino-frances:1", corridorHash: "h", complete: false)
        XCTAssertFalse(fake.regions().first?.isComplete ?? true)
        fake.removeRegion(id: "pilgrimage:camino-frances:1")
        XCTAssertTrue(fake.regions().isEmpty)
        XCTAssertEqual(fake.removedIds, ["pilgrimage:camino-frances:1"])
        XCTAssertFalse(fake.hasStylePack(.light))
        var packResult: Result<Void, TileRegionLoadingError>?
        _ = fake.loadStylePack(.light) { packResult = $0 }
        fake.completeNextPack()
        XCTAssertNotNil(try packResult?.get())
        XCTAssertTrue(fake.hasStylePack(.light))
    }
}
