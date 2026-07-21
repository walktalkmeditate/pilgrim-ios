import XCTest
@testable import Pilgrim

/// The glyph pipeline's name contract: every whisper/cairn surface loads
/// these assets by string, so a missing or renamed imageset must fail here
/// rather than silently rendering nothing on the map.
final class GlyphAssetTests: XCTestCase {

    static let allGlyphNames = [
        "whisperWisp",
        "cairn-faint", "cairn-small", "cairn-medium", "cairn-large",
        "cairn-great", "cairn-sacred", "cairn-eternal"
    ]

    func testAllGlyphAssetsResolve() {
        for name in Self.allGlyphNames {
            XCTAssertNotNil(UIImage(named: name), "asset catalog is missing glyph '\(name)'")
        }
    }

    func testEveryCairnTierHasAnAsset() {
        for tier in CairnTier.allCases {
            XCTAssertNotNil(UIImage(named: tier.glyphAssetName), "no glyph asset for tier \(tier)")
        }
    }
}
