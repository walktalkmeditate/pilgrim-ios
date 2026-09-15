// UnitTests/Honor/PilgrimageMapsRowTests.swift
import XCTest
@testable import Pilgrim

@MainActor
final class PilgrimageMapsRowTests: XCTestCase {

    /// The row is redrawn on every published change of the route page; a
    /// body that hashed every stage's corridor and read the store would do
    /// so on each of them. The status arrives already computed.
    func testTheRowsBodyReadsNoStore() {
        let loader = FakeTileRegionLoader()
        let tiles = PilgrimageTilesManager(loader: loader, defaults: UserDefaults(suiteName: "row-\(UUID().uuidString)")!)
        let statuses: [PilgrimageTilesManager.Status] = [.none, .partial(saved: 1, of: 3), .saved(bytes: 100)]
        for status in statuses {
            let row = PilgrimageMapsRow(routeId: "camino-frances", stages: [], estimateBytes: 0, status: status, tiles: tiles)
            _ = row.body
        }
        XCTAssertEqual(loader.regionsReadCount, 0)
    }

    func testTheEstimateIsRoundedAndTilded() {
        XCTAssertEqual(PilgrimageMapsRowModel.label(status: .none, estimateBytes: 26_400_000), "Save maps for the way · ~26 MB")
        XCTAssertEqual(PilgrimageMapsRowModel.label(status: .none, estimateBytes: 1_900_000), "Save maps for the way · ~2 MB")
        XCTAssertEqual(PilgrimageMapsRowModel.label(status: .none, estimateBytes: 400_000), "Save maps for the way · ~1 MB")
    }

    func testAPartialSaveSaysHowFarItGot() {
        XCTAssertEqual(PilgrimageMapsRowModel.label(status: .partial(saved: 12, of: 33), estimateBytes: 0),
                       "Save maps for the way · 12 of 33 saved")
    }

    func testSavedShowsRealBytesWithNoTilde() {
        XCTAssertEqual(PilgrimageMapsRowModel.savedLine(bytes: 26_100_000), "maps saved · 26 MB")
    }

    /// `total` counts the two style packs; the walker counts stages.
    func testSavingCountsStagesNotPacks() {
        XCTAssertEqual(PilgrimageMapsRowModel.savingLine(done: 14, total: 35), "maps · stage 12 of 33")
        XCTAssertEqual(PilgrimageMapsRowModel.savingLine(done: 0, total: 35), "maps · stage 0 of 33")
    }

    func testTheMorningCardSaysWhetherTodayIsSaved() {
        XCTAssertEqual(StageMorningCardModel.mapsLine(saved: true), "maps saved for today")
        XCTAssertEqual(StageMorningCardModel.mapsLine(saved: false), "no offline maps for today — save on wifi")
    }
}
