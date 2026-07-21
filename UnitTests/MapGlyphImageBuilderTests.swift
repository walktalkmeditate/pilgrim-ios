import XCTest
@testable import Pilgrim

/// The builder turns glyph requests into correctly sized, cached UIImages
/// for Mapbox. A silent regression here blurs or mistints every pin on the
/// map, so the pixel and cache contracts are pinned directly (R11).
final class MapGlyphImageBuilderTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MapGlyphImageBuilder._test_clearCache()
    }

    func testWhisperRendersForEveryMoodColor() {
        for category in WhisperCategory.allCases {
            let image = MapGlyphImageBuilder.image(for: .whisper(tint: category.borderColor), size: 14)
            XCTAssertNotNil(image, "no wisp rendered for mood \(category.rawValue)")
        }
    }

    func testCairnRendersForEveryTier() {
        for tier in CairnTier.allCases {
            let size = 12 + CGFloat(tier.rawValue)
            XCTAssertNotNil(MapGlyphImageBuilder.image(for: .cairn(tier: tier), size: size),
                            "no cairn rendered for tier \(tier)")
        }
    }

    func testPixelDimensionsMatchRequestedSize() {
        guard let image = MapGlyphImageBuilder.image(for: .cairn(tier: .faint), size: 12) else {
            return XCTFail("no image")
        }
        XCTAssertEqual(image.size.width, 12)
        XCTAssertEqual(image.size.height, 12)
        XCTAssertEqual(image.scale, UIScreen.main.scale,
                       "raster must be display-scale so pins stay crisp")
    }

    func testRepeatedRequestReturnsCachedInstance() {
        let first = MapGlyphImageBuilder.image(for: .cairn(tier: .great), size: 16)
        let second = MapGlyphImageBuilder.image(for: .cairn(tier: .great), size: 16)
        XCTAssertTrue(first === second, "same glyph and size must not re-render")
    }

    func testCacheKeysMatchExistingAnnotationNameFormats() {
        XCTAssertEqual(MapGlyphImageBuilder.cacheKey(for: .cairn(tier: .medium)), "cairn-2")
        let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        XCTAssertEqual(MapGlyphImageBuilder.cacheKey(for: .whisper(tint: red)), "whisper-FF0000")
    }

    func testDistinctTintsAndTiersProduceDistinctKeys() {
        var keys = Set<String>()
        for category in WhisperCategory.allCases {
            keys.insert(MapGlyphImageBuilder.cacheKey(for: .whisper(tint: category.borderColor)))
        }
        for tier in CairnTier.allCases {
            keys.insert(MapGlyphImageBuilder.cacheKey(for: .cairn(tier: tier)))
        }
        XCTAssertEqual(keys.count, WhisperCategory.allCases.count + CairnTier.allCases.count,
                       "every mood and tier must have its own cache identity")
    }

    func testMissingAssetDegradesToNil() {
        XCTAssertNil(MapGlyphImageBuilder.rendered(assetNamed: "no-such-glyph", tint: nil, size: 14),
                     "a broken asset-name contract must degrade, not crash")
    }
}
