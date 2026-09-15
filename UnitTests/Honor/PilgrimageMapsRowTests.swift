// UnitTests/Honor/PilgrimageMapsRowTests.swift
import XCTest
@testable import Pilgrim

final class PilgrimageMapsRowTests: XCTestCase {

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
}
