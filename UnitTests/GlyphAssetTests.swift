import XCTest
@testable import Pilgrim

/// The glyph pipeline's name contract: every whisper/cairn surface loads
/// these assets by string, so a missing or renamed imageset must fail here
/// rather than silently rendering nothing on the map.
final class GlyphAssetTests: XCTestCase {

    static let allGlyphNames = [MapGlyphImageBuilder.whisperAssetName]
        + CairnTier.allCases.map(\.glyphAssetName)

    func testAllGlyphAssetsResolve() {
        for name in Self.allGlyphNames {
            XCTAssertNotNil(UIImage(named: name), "asset catalog is missing glyph '\(name)'")
        }
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
