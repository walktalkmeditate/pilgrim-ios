// UnitTests/Honor/MapboxTileRegionLoaderTests.swift
import MapboxMaps
import XCTest
@testable import Pilgrim

final class MapboxTileRegionLoaderTests: XCTestCase {

    /// A Caches location is purgeable under storage pressure; a walker on
    /// day 20 could lose the maps for day 21. Application Support is not.
    /// `TileStore.shared(for:)` — the only entry point the loader uses, and
    /// the one that keeps the path out of iCloud backup — traps on anything
    /// but a file URL, so the path being one is part of the contract.
    func testTheStoreLivesUnderApplicationSupport() throws {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: false)
        XCTAssertTrue(MapboxTileRegionLoader.storeURL.path.hasPrefix(support.path))
        XCTAssertFalse(MapboxTileRegionLoader.storeURL.path.contains("/Caches/"))
        XCTAssertEqual(MapboxTileRegionLoader.storeURL.lastPathComponent, "pilgrimage-tiles")
        XCTAssertTrue(MapboxTileRegionLoader.storeURL.isFileURL)
    }

    /// Reads the options the SDK is actually handed. They are value types,
    /// so this opens no `TileStore`.
    func testDescriptorOptionsCarryTheSpecsRangesAndTheTerrainTileset() {
        let options = MapboxTileRegionLoader.descriptorOptions()
        XCTAssertEqual(options.count, 3)

        XCTAssertEqual(options[0].styleURI, StyleURI.light.rawValue)
        XCTAssertEqual(options[1].styleURI, StyleURI.dark.rawValue)
        XCTAssertEqual(options[2].styleURI, StyleURI.light.rawValue)

        for streets in [options[0], options[1]] {
            XCTAssertEqual(streets.minZoom, 0)
            XCTAssertEqual(streets.maxZoom, 16)
            XCTAssertNil(streets.tilesets)
        }

        XCTAssertEqual(options[2].minZoom, 0)
        XCTAssertEqual(options[2].maxZoom, 14)
        XCTAssertEqual(options[2].tilesets, ["mapbox://mapbox.mapbox-terrain-dem-v1"])
    }
}
