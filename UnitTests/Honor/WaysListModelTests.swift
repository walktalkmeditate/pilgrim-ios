// UnitTests/Honor/WaysListModelTests.swift
import XCTest
@testable import Pilgrim

final class WaysListModelTests: XCTestCase {

    private func way(id: String, source: WaySource) -> Way {
        Way(id: id, source: source, title: "t", departedAt: Date(timeIntervalSince1970: 0), tzIdentifier: nil, expires: nil,
            route: [], totalDistanceMeters: 0, theirActiveSeconds: 0, moments: [], weather: nil, spans: nil, marks: nil, stage: nil)
    }

    /// The Data card's row and the list read one predicate. On a phone with
    /// one shared walk and a four-stage route the row said "5 ways" above a
    /// list of one, because the row counted the store and the list did not.
    func testListableDropsPackageOwnedWaysAndNothingElse() {
        let shared = way(id: "share:9mYhRL7GWx", source: .share(id: "9mYhRL7GWx", pageURL: URL(string: "https://walk.pilgrimapp.org/9mYhRL7GWx")!))
        let own = way(id: "walk:00000000-0000-0000-0000-000000000000", source: .ownWalk(UUID()))
        let stages = (0..<4).map {
            way(id: WayStore.stageWayId(routeId: "kumano-kodo-nakahechi", stageIndex: $0),
                source: .pilgrimage(routeId: "kumano-kodo-nakahechi", stageIndex: $0))
        }
        XCTAssertEqual(WaysListModel.listable([shared] + stages + [own]).map(\.id), [shared.id, own.id])
    }

    func testTheRowCountsAndSizesTheWaysItIsGiven() {
        XCTAssertEqual(WaysListModel.rowDetail(count: 1, bytes: 2_340_000), "1 way · 2.3 MB")
        XCTAssertEqual(WaysListModel.rowDetail(count: 3, bytes: 12_000_000), "3 ways · 12.0 MB")
        XCTAssertEqual(WaysListModel.rowDetail(count: 0, bytes: 0), "0 ways · 0.0 MB")
    }

    /// The footer says where the hidden stages went, in the caption voice,
    /// and only when there is something hidden and a route to name it by.
    func testTheFooterNamesTheRouteAndItsStagesOnlyWhenThereAreAny() {
        XCTAssertEqual(WaysListModel.packageFooter(routeName: "Nakahechi (Central Route)", stageCount: 4),
                       "the Nakahechi (Central Route) keeps its 4 stages on its route page")
        XCTAssertEqual(WaysListModel.packageFooter(routeName: "Kohechi", stageCount: 1),
                       "the Kohechi keeps its 1 stage on its route page")
        XCTAssertNil(WaysListModel.packageFooter(routeName: "Nakahechi (Central Route)", stageCount: 0))
        XCTAssertNil(WaysListModel.packageFooter(routeName: nil, stageCount: 4),
                     "stages with no installed route to name — a Replace cut short — say nothing")
    }
}
