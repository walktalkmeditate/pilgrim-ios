// UnitTests/Honor/PilgrimageTilesDescriptorsTests.swift
import XCTest
import CoreLocation
@testable import Pilgrim

final class PilgrimageTilesDescriptorsTests: XCTestCase {

    /// The SDK loads tile packs in fixed zoom bands — 0–5, 6–10, 11–14,
    /// 15–16 — and caps a store at 750 unique packs. Streets ends at 14:
    /// the 15–16 band adds building footprints only and would put the
    /// Francés alone at ~1,800 packs. The DEM tileset has no z15 at all;
    /// 14 is both its ceiling and a band edge.
    func testTheCeilingsAreBandEdges() {
        XCTAssertEqual(PilgrimageTilesDescriptors.streetsZoom, 0...14)
        XCTAssertEqual(PilgrimageTilesDescriptors.terrainZoom, 0...14)
    }

    /// The estimate sweeps the corridor once and counts it for both
    /// tilesets; that shortcut holds only while the two ceilings agree.
    func testStreetsAndTerrainShareACeilingSoTheEstimateSweepsOnce() {
        XCTAssertEqual(PilgrimageTilesDescriptors.streetsZoom.upperBound, PilgrimageTilesDescriptors.terrainZoom.upperBound)
    }

    /// The DEM is added by `PilgrimMapStyle.applyWabiSabiStyle` at runtime,
    /// not by the base style, so it has to be named or the hillshade is
    /// blank offline.
    func testTheTerrainTilesetIsTheOneTheStyleAdds() {
        XCTAssertEqual(PilgrimageTilesDescriptors.terrainTileset, "mapbox://mapbox.mapbox-terrain-dem-v1")
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
