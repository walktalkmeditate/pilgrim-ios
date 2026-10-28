import XCTest
@testable import Pilgrim

final class StageLinkResolverTests: XCTestCase {

    private let frances = PilgrimageCatalogEntry(id: "camino-frances", name: "Camino Francés", names: [:],
                                                 country: "ES", region: "Europe", distanceKm: 780,
                                                 tradition: "christian", stageCount: 33, bytes: 1_000)

    private var catalog: PilgrimageCatalog { PilgrimageCatalog(release: "v1.12.0", routes: [frances]) }

    private func resolve(routeId: String = "camino-frances", index: Int = 13, installed: String? = nil,
                         wayExists: Bool = false, catalog: PilgrimageCatalog?) -> StageLinkOutcome {
        StageLinkResolver.resolve(routeId: routeId, index: index, installedRouteId: installed,
                                  stageWayExists: wayExists, catalog: catalog)
    }

    private func sheet(focus: Int?) -> StageLinkOutcome {
        .routeSheet(HonorRouteLink(entry: frances, release: "v1.12.0", focus: focus))
    }

    func testInstalledWithTheStageOpensTheOverview() {
        XCTAssertEqual(resolve(installed: "camino-frances", wayExists: true, catalog: catalog),
                       .overview(wayId: "pilgrimage:camino-frances:13"))
    }

    func testInstalledWithTheStageNeedsNoCatalog() {
        XCTAssertEqual(resolve(installed: "camino-frances", wayExists: true, catalog: nil),
                       .overview(wayId: "pilgrimage:camino-frances:13"))
    }

    func testInstalledButTheStageMissingOpensTheRouteFocused() {
        XCTAssertEqual(resolve(installed: "camino-frances", wayExists: false, catalog: catalog), sheet(focus: 13))
    }

    func testNotInstalledOpensTheRouteFocused() {
        XCTAssertEqual(resolve(catalog: catalog), sheet(focus: 13))
    }

    func testAnotherRouteInstalledOpensTheRouteFocused() {
        XCTAssertEqual(resolve(installed: "camino-norte", catalog: catalog), sheet(focus: 13),
                       "Replace is the route screen's question to ask, not the link's")
    }

    func testTheLastStageOpensTheRouteFocusedOnIt() {
        XCTAssertEqual(resolve(index: 32, catalog: catalog), sheet(focus: 32))
    }

    func testAStagePastTheEndOpensTheRouteUnfocused() {
        XCTAssertEqual(resolve(index: 33, catalog: catalog), sheet(focus: nil))
    }

    func testARouteAbsentFromTheCatalogSaysSo() {
        XCTAssertEqual(resolve(routeId: "camino-imaginario", catalog: catalog), .notInCatalog)
    }

    func testNoCatalogInHandAsksForOne() {
        XCTAssertEqual(resolve(catalog: nil), .needsCatalog)
    }

    func testFocusIsPartOfTheSheetIdentity() {
        let fourteen = HonorRouteLink(entry: frances, release: "v1.12.0", focus: 13)
        let twenty = HonorRouteLink(entry: frances, release: "v1.12.0", focus: 19)
        XCTAssertNotEqual(fourteen.id, twenty.id)
        XCTAssertNotEqual(HonorRouteLink(entry: frances, release: "v1.12.0", focus: nil).id, fourteen.id)
    }
}
