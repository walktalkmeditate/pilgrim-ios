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

    /// Maps objects read `MapboxMapsOptions` at construction, so the store
    /// has to be named at launch, before any map exists — otherwise every
    /// map reads the SDK's default store and no saved region is ever found.
    /// The test host's `AppDelegate` ran that line; no loader is built here.
    func testTheMapIsWiredToTheStoreTheRegionsAreSavedInto() {
        XCTAssertNotNil(MapboxMapsOptions.tileStore)
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
            XCTAssertEqual(streets.maxZoom, 14)
            XCTAssertNil(streets.tilesets)
        }

        XCTAssertEqual(options[2].minZoom, 0)
        XCTAssertEqual(options[2].maxZoom, 14)
        XCTAssertEqual(options[2].tilesets, ["mapbox://mapbox.mapbox-terrain-dem-v1"])
    }

    /// The descriptors test pins `rasterizesIdeographsLocally`; this pins
    /// that the loader reads it rather than restating the SDK's default.
    func testTheGlyphsModeComesFromThePinnedConstant() {
        XCTAssertEqual(MapboxTileRegionLoader.glyphsRasterizationMode, .ideographsRasterizedLocally)
    }

    /// The SDK names a full disk and its 750-pack ceiling as their own
    /// cases, which the shared URLError/Cocoa check cannot see. Pure
    /// function — no loader.
    func testMappedErrorsNameAFullDiskAPackCeilingAndACancel() {
        XCTAssertEqual(MapboxTileRegionLoader.mapped(TileRegionError.diskFull("x")), .diskFull)
        XCTAssertEqual(MapboxTileRegionLoader.mapped(StylePackError.diskFull("x")), .diskFull)
        XCTAssertEqual(MapboxTileRegionLoader.mapped(TileRegionError.tileCountExceeded("x")), .tileCountExceeded)
        XCTAssertEqual(MapboxTileRegionLoader.mapped(TileRegionError.canceled("x")), .cancelled)
        XCTAssertEqual(MapboxTileRegionLoader.mapped(URLError(.cannotWriteToFile)), .diskFull)
        XCTAssertEqual(MapboxTileRegionLoader.mapped(NSError(domain: "t", code: 1)), .failed)
    }

    /// A region mid-download reports new counts on every progress tick. A
    /// reader that reloads on `.regions` and reads `regions()` — which
    /// refreshes — would spin for the length of a save if those signalled.
    /// Pure function — no loader.
    func testTheSettledProjectionIgnoresCountsAndSizesButNotCompletionOrHash() {
        func region(completed: Int, size: Int, hash: String) -> TileRegionSummary {
            TileRegionSummary(id: "r", completedResourceCount: completed, requiredResourceCount: 10,
                              completedResourceSize: size, metadata: ["corridorHash": hash])
        }
        let downloading = region(completed: 3, size: 300, hash: "h")
        let further = region(completed: 7, size: 700, hash: "h")
        let done = region(completed: 10, size: 1_000, hash: "h")
        let redrawn = region(completed: 3, size: 300, hash: "h2")

        XCTAssertNotEqual(downloading, further, "the snapshots differ, so the cache is rewritten")
        XCTAssertEqual(MapboxTileRegionLoader.settled([downloading]), MapboxTileRegionLoader.settled([further]))
        XCTAssertNotEqual(MapboxTileRegionLoader.settled([downloading]), MapboxTileRegionLoader.settled([done]))
        XCTAssertNotEqual(MapboxTileRegionLoader.settled([downloading]), MapboxTileRegionLoader.settled([redrawn]))
        XCTAssertNotEqual(MapboxTileRegionLoader.settled([downloading]), MapboxTileRegionLoader.settled([]),
                          "a region appearing or vanishing is a settled change")
    }

    /// A pack interrupted mid-load must not read as present, or `refresh()`
    /// would skip it on every later save. Pure function — no loader, no
    /// `StylePack`, so this pins the rule `refresh()` actually filters by.
    func testIsCompleteMirrorsTileRegionSummarysIsComplete() {
        XCTAssertTrue(MapboxTileRegionLoader.isComplete(completed: 10, required: 10))
        XCTAssertFalse(MapboxTileRegionLoader.isComplete(completed: 4, required: 10))
        XCTAssertFalse(MapboxTileRegionLoader.isComplete(completed: 0, required: 0))

        for (completed, required) in [(10, 10), (4, 10), (0, 0), (0, 5), (5, 0)] {
            let summary = TileRegionSummary(id: "x", completedResourceCount: completed, requiredResourceCount: required,
                                            completedResourceSize: 0, metadata: [:])
            XCTAssertEqual(MapboxTileRegionLoader.isComplete(completed: completed, required: required), summary.isComplete)
        }
    }
}
