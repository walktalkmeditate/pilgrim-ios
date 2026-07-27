import XCTest
@testable import Pilgrim

/// The glyph pipeline's name contract: every whisper/cairn/clearing surface
/// loads these assets by string, so a missing or renamed imageset must fail
/// here rather than silently rendering nothing on the map.
final class GlyphAssetTests: XCTestCase {

    /// Glyphs that take their colour from a tint at render time. These need
    /// `template-rendering-intent` in the imageset — without it
    /// `withTintColor` is a silent no-op and they render near-black.
    static let tintedGlyphNames = [
        MapGlyphImageBuilder.whisperAssetName,
        MapGlyphImageBuilder.seekClearingAssetName
    ]

    static let allGlyphNames = tintedGlyphNames
        + CairnTier.allCases.map(\.glyphAssetName)

    func testAllGlyphAssetsResolve() {
        for name in Self.allGlyphNames {
            XCTAssertNotNil(UIImage(named: name), "asset catalog is missing glyph '\(name)'")
        }
    }

    func testTintedGlyphsAreTemplateAssets() {
        for name in Self.tintedGlyphNames {
            XCTAssertEqual(
                UIImage(named: name)?.renderingMode,
                .alwaysTemplate,
                "glyph '\(name)' must set template-rendering-intent or its tint is dropped"
            )
        }
    }

    /// The clearing's imageset wraps its path in a `<g transform>` to centre
    /// the art in a square box. Xcode's SVG support is a subset of the spec,
    /// and a dropped transform would rasterise the tree at raw generator
    /// coordinates — off-canvas or microscopic — while every name-and-mode
    /// assertion above still passed. So measure the pixels.
    ///
    /// Reference geometry comes from rendering the same master with rsvg:
    /// ink spans 75.7% of the box in width, 57.9% in height, centred.
    func testClearingGlyphGeometrySurvivesTheAssetPipeline() throws {
        let points: CGFloat = 150
        let image = try XCTUnwrap(MapGlyphImageBuilder.rendered(
            assetNamed: MapGlyphImageBuilder.seekClearingAssetName,
            tint: .black,
            size: points
        ))
        let side = points * image.scale
        let ink = try XCTUnwrap(Self.inkBounds(of: image))

        XCTAssertEqual(ink.width / side, 0.757, accuracy: 0.04, "clearing ink width drifted")
        XCTAssertEqual(ink.height / side, 0.579, accuracy: 0.04, "clearing ink height drifted")
        XCTAssertEqual(ink.midX / side, 0.5, accuracy: 0.04, "clearing is not horizontally centred")
        XCTAssertEqual(ink.midY / side, 0.5, accuracy: 0.04, "clearing is not vertically centred")
    }

    /// Bounding box of everything more than faintly opaque, in pixels.
    private static func inkBounds(of image: UIImage) -> CGRect? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        var alpha = [UInt8](repeating: 0, count: width * height)
        guard let ctx = CGContext(
            data: &alpha, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where alpha[y * width + x] > 8 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Every hour of the sky needs its own cached raster — a collision here
    /// would serve a dusk-amber tree for a clearing found after dark.
    func testEveryDaypartProducesADistinctClearingKey() {
        var keys = Set<String>()
        for starlight in [false, true] {
            for daypart in [SeekSkyLight.Daypart.golden, .midday, .night] {
                let tint = UIColor(hex: SeekSkyLight.hex(daypart: daypart, starlight: starlight))
                keys.insert(MapGlyphImageBuilder.cacheKey(for: .seekClearing(tint: tint)))
            }
        }
        XCTAssertEqual(keys.count, 6, "each daypart/starlight pairing must cache separately")
    }

    /// The clearing's key must stay distinct from the wisp's even when both
    /// are handed the same colour — they are different art on the same map.
    func testTintedGlyphCacheKeysDoNotCollide() {
        let light = UIColor(red: 0.77, green: 0.58, blue: 0.42, alpha: 1)
        XCTAssertNotEqual(
            MapGlyphImageBuilder.cacheKey(for: .whisper(tint: light)),
            MapGlyphImageBuilder.cacheKey(for: .seekClearing(tint: light))
        )
    }

    func testTierAssetNameMapping() {
        XCTAssertEqual(CairnTier.faint.glyphAssetName, "cairn-faint")
        XCTAssertEqual(CairnTier.small.glyphAssetName, "cairn-small")
        XCTAssertEqual(CairnTier.medium.glyphAssetName, "cairn-medium")
        XCTAssertEqual(CairnTier.large.glyphAssetName, "cairn-large")
        XCTAssertEqual(CairnTier.great.glyphAssetName, "cairn-great")
        XCTAssertEqual(CairnTier.sacred.glyphAssetName, "cairn-sacred")
        XCTAssertEqual(CairnTier.eternal.glyphAssetName, "cairn-eternal")
    }
}
