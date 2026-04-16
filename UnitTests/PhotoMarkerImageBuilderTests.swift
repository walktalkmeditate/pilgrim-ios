import XCTest
import UIKit
@testable import Pilgrim

/// Covers `PhotoMarkerImageBuilder` — the Core Graphics helper that
/// turns a reliquary photo into a circular Mapbox marker icon. These
/// tests don't introspect pixel colors (too brittle across
/// render-hint differences); instead they verify the contract: the
/// output is a UIImage of the requested size at the main-screen
/// scale, and it doesn't crash on degenerate inputs.
final class PhotoMarkerImageBuilderTests: XCTestCase {

    // MARK: - build(from:)

    func testBuild_returnsImageAtRequestedDiameter() {
        let source = solidColorImage(size: CGSize(width: 200, height: 200), color: .red)

        let marker = PhotoMarkerImageBuilder.build(from: source, diameter: 44)

        XCTAssertEqual(marker.size, CGSize(width: 44, height: 44))
    }

    func testBuild_honorsCustomDiameter() {
        let source = solidColorImage(size: CGSize(width: 200, height: 200), color: .red)

        let marker = PhotoMarkerImageBuilder.build(from: source, diameter: 88)

        XCTAssertEqual(marker.size, CGSize(width: 88, height: 88))
    }

    func testBuild_rendersAtMainScreenScale() {
        let source = solidColorImage(size: CGSize(width: 200, height: 200), color: .red)

        let marker = PhotoMarkerImageBuilder.build(from: source)

        XCTAssertEqual(marker.scale, UIScreen.main.scale)
    }

    func testBuild_handlesNonSquareSource() {
        // 400x200 landscape — the builder aspect-fills so the
        // shorter dimension (height) matches the marker and the
        // longer dimension (width) is cropped by the circular clip.
        let source = solidColorImage(size: CGSize(width: 400, height: 200), color: .blue)

        let marker = PhotoMarkerImageBuilder.build(from: source, diameter: 44)

        XCTAssertEqual(marker.size, CGSize(width: 44, height: 44))
    }

    func testBuild_handlesPortraitSource() {
        let source = solidColorImage(size: CGSize(width: 200, height: 400), color: .green)

        let marker = PhotoMarkerImageBuilder.build(from: source, diameter: 44)

        XCTAssertEqual(marker.size, CGSize(width: 44, height: 44))
    }

    func testBuild_degenerateZeroSizeSource_doesNotCrash() {
        // An empty 0x0 image shouldn't crash the builder — it
        // short-circuits the image draw and produces a pin that's
        // just the border/fill, so there's still something visible
        // on the map instead of a transparent hole.
        let source = UIImage()

        let marker = PhotoMarkerImageBuilder.build(from: source, diameter: 44)

        XCTAssertEqual(marker.size, CGSize(width: 44, height: 44))
    }

    // MARK: - placeholder()

    func testPlaceholder_returnsImageAtRequestedDiameter() {
        let placeholder = PhotoMarkerImageBuilder.placeholder(diameter: 44)

        XCTAssertEqual(placeholder.size, CGSize(width: 44, height: 44))
    }

    func testPlaceholder_rendersAtMainScreenScale() {
        let placeholder = PhotoMarkerImageBuilder.placeholder()

        XCTAssertEqual(placeholder.scale, UIScreen.main.scale)
    }

    // MARK: - Helpers

    /// Builds a solid-color UIImage at `size`. Used as a synthetic
    /// source photo for the builder under test.
    private func solidColorImage(size: CGSize, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
