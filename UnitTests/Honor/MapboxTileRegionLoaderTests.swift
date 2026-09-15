// UnitTests/Honor/MapboxTileRegionLoaderTests.swift
import XCTest
@testable import Pilgrim

final class MapboxTileRegionLoaderTests: XCTestCase {

    /// A Caches location is purgeable under storage pressure; a walker on
    /// day 20 could lose the maps for day 21. Application Support is not.
    func testTheStoreLivesUnderApplicationSupport() throws {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: false)
        XCTAssertTrue(MapboxTileRegionLoader.storeURL.path.hasPrefix(support.path))
        XCTAssertFalse(MapboxTileRegionLoader.storeURL.path.contains("/Caches/"))
        XCTAssertEqual(MapboxTileRegionLoader.storeURL.lastPathComponent, "pilgrimage-tiles")
    }

    /// The SDK excludes a `shared(for:)` path from iCloud backup on iOS;
    /// this pins that the loader uses that entry point and not `.default`.
    func testTheStoreIsCreatedAtAnExplicitPath() {
        XCTAssertTrue(MapboxTileRegionLoader.usesExplicitStorePath)
    }

    func testDescriptorsMatchTheSpec() {
        let ranges = MapboxTileRegionLoader.descriptorZoomRanges
        XCTAssertEqual(ranges.streets, PilgrimageTilesDescriptors.streetsZoom)
        XCTAssertEqual(ranges.terrain, PilgrimageTilesDescriptors.terrainZoom)
        XCTAssertEqual(MapboxTileRegionLoader.terrainTilesets, [PilgrimageTilesDescriptors.terrainTileset])
    }
}
