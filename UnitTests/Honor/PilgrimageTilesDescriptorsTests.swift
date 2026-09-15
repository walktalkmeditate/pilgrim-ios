// UnitTests/Honor/PilgrimageTilesDescriptorsTests.swift
import XCTest
import CoreLocation
@testable import Pilgrim

final class PilgrimageTilesDescriptorsTests: XCTestCase {

    /// The SDK downloads whole packs in fixed zoom bands — 0–5, 6–10,
    /// 11–14, 15–16 — not the tiles a corridor touches. A range from 0
    /// pulls the planet-wide 0–5 pack of every tileset in the style, 206 MB
    /// before a route tile, which is how a ~2 MB Nakahechi estimate landed
    /// as 596 MB on the phone. Streets ends at 14: the 15–16 band adds
    /// building footprints only and would put the Francés alone at ~1,800
    /// packs against the store's 750.
    func testTheRangeIsTheOneBandWhosePacksFollowTheCorridor() {
        XCTAssertEqual(PilgrimageTilesDescriptors.streetsZoom, 11...14)
    }

    /// The estimate counts z11 cells because that is what the store
    /// downloads; the range has to start on that band's root or the count
    /// speaks for packs the region never pulls.
    func testThePackRootIsTheRangesFloor() {
        XCTAssertEqual(PilgrimageTilesDescriptors.packRootZoom, 11)
        XCTAssertEqual(PilgrimageTilesDescriptors.streetsZoom.lowerBound, PilgrimageTilesDescriptors.packRootZoom)
    }

    /// Version 1 saved regions from z0 with the DEM named, and phones have
    /// them. The version is hashed into every corridor so those read as
    /// unsaved; a descriptor change that forgets to move it leaves 596 MB
    /// of the wrong packs reading as maps saved.
    func testTheRegionVersionMovedPastTheDescriptorsThatShippedFirst() {
        XCTAssertEqual(PilgrimageTilesDescriptors.regionVersion, 2)
    }

    func testGlyphsRasterizeIdeographsLocally() {
        XCTAssertTrue(PilgrimageTilesDescriptors.rasterizesIdeographsLocally)
    }

    /// The design session's figure for the Nakahechi corridor at z10–15 was
    /// 129 tiles from 504 points; this corridor is the same shape of thing.
    func testTileCountGrowsFourfoldPerZoomOnALongCorridor() {
        let line = (0...300).map { i in CLLocationCoordinate2D(latitude: 33.8, longitude: 135.5 + Double(i) * 0.001) }
        let rings = WayGeometry.corridor(around: line, halfWidthMeters: 500)
        let z13 = PilgrimageTilesDescriptors.tileCount(rings: rings, zooms: 13...13)
        let z15 = PilgrimageTilesDescriptors.tileCount(rings: rings, zooms: 15...15)
        XCTAssertGreaterThan(z13, 5)
        XCTAssertEqual(Double(z15) / Double(z13), 4, accuracy: 1.5)
    }
}
