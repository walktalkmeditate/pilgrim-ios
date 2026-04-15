import XCTest
import UIKit
@testable import Pilgrim

/// Unit coverage for `PilgrimPhotoEmbedder`'s pure helpers. The full
/// orchestration (`embedPhotos`) depends on PhotoKit and can't be exercised
/// without a seeded simulator Photos library — that's integration-level
/// QA for Stage 6. Here we only cover the pieces that don't touch PHAsset.
final class PilgrimPhotoEmbedderTests: XCTestCase {

    // MARK: - sanitizedFilename

    func testSanitizedFilename_replacesForwardSlash() {
        let result = PilgrimPhotoEmbedder.sanitizedFilename(for: "ABC-123/L0/001")
        XCTAssertEqual(result, "ABC-123_L0_001.jpg")
    }

    func testSanitizedFilename_noSlashes_passesThrough() {
        let result = PilgrimPhotoEmbedder.sanitizedFilename(for: "abc123")
        XCTAssertEqual(result, "abc123.jpg")
    }

    func testSanitizedFilename_multipleSlashes_allReplaced() {
        let result = PilgrimPhotoEmbedder.sanitizedFilename(for: "a/b/c/d")
        XCTAssertEqual(result, "a_b_c_d.jpg")
    }

    func testSanitizedFilename_uuidLikeIdentifier() {
        // PHAsset localIdentifiers often look like this in practice
        let id = "99D53167-5A8A-4933-A4A3-EE40BFDF05E3/L0/001"
        let result = PilgrimPhotoEmbedder.sanitizedFilename(for: id)
        XCTAssertEqual(result, "99D53167-5A8A-4933-A4A3-EE40BFDF05E3_L0_001.jpg")
    }

    func testSanitizedFilename_alwaysEndsInJpgExtension() {
        XCTAssertTrue(PilgrimPhotoEmbedder.sanitizedFilename(for: "anything").hasSuffix(".jpg"))
        XCTAssertTrue(PilgrimPhotoEmbedder.sanitizedFilename(for: "with/slash").hasSuffix(".jpg"))
    }

    // MARK: - resizeAndEncode

    func testResizeAndEncode_largeImage_resizedBelowMaxDimension() throws {
        // 2000x1000 test image → should resize to 600x300 (aspect-fit in 600x600 box)
        let image = makeTestImage(width: 2000, height: 1000, color: .red)
        let data = try XCTUnwrap(PilgrimPhotoEmbedder.resizeAndEncode(image))

        // Verify it's valid JPEG by decoding it
        let decoded = try XCTUnwrap(UIImage(data: data))
        // Allow ±1 pixel rounding slop
        XCTAssertEqual(decoded.size.width, 600, accuracy: 1.5)
        XCTAssertEqual(decoded.size.height, 300, accuracy: 1.5)
    }

    func testResizeAndEncode_smallImage_notUpscaled() throws {
        // 100x50 test image → already under 600×600, should NOT be scaled up
        let image = makeTestImage(width: 100, height: 50, color: .blue)
        let data = try XCTUnwrap(PilgrimPhotoEmbedder.resizeAndEncode(image))

        let decoded = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(decoded.size.width, 100, accuracy: 1.5)
        XCTAssertEqual(decoded.size.height, 50, accuracy: 1.5)
    }

    func testResizeAndEncode_squareImage_resizedToMaxDimension() throws {
        // 1000x1000 → 600x600
        let image = makeTestImage(width: 1000, height: 1000, color: .green)
        let data = try XCTUnwrap(PilgrimPhotoEmbedder.resizeAndEncode(image))

        let decoded = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(decoded.size.width, 600, accuracy: 1.5)
        XCTAssertEqual(decoded.size.height, 600, accuracy: 1.5)
    }

    func testResizeAndEncode_tallImage_resizedToHeightDimension() throws {
        // 300x1200 → 150x600 (height is the limiting dimension)
        let image = makeTestImage(width: 300, height: 1200, color: .purple)
        let data = try XCTUnwrap(PilgrimPhotoEmbedder.resizeAndEncode(image))

        let decoded = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(decoded.size.width, 150, accuracy: 1.5)
        XCTAssertEqual(decoded.size.height, 600, accuracy: 1.5)
    }

    func testResizeAndEncode_outputIsJPEG_notPNG() throws {
        let image = makeTestImage(width: 800, height: 800, color: .orange)
        let data = try XCTUnwrap(PilgrimPhotoEmbedder.resizeAndEncode(image))

        // JPEG files start with 0xFF 0xD8 0xFF (SOI marker)
        XCTAssertGreaterThanOrEqual(data.count, 3)
        XCTAssertEqual(data[0], 0xFF)
        XCTAssertEqual(data[1], 0xD8)
        XCTAssertEqual(data[2], 0xFF)
    }

    func testResizeAndEncode_sizeUnderCeiling() throws {
        // A 600×600 solid color encodes to well under 150KB at q0.7.
        // This test guards against accidental quality/size regressions.
        let image = makeTestImage(width: 1200, height: 1200, color: .gray)
        let data = try XCTUnwrap(PilgrimPhotoEmbedder.resizeAndEncode(image))
        XCTAssertLessThan(
            data.count,
            150_000,
            "Resized photo should be comfortably under the 150KB embed ceiling"
        )
    }

    // MARK: - applyEmbeddedFilenames (builder drop-and-stamp logic)

    func testApplyEmbeddedFilenames_nilPhotos_passesThrough() {
        let walk = makeWalk(photos: nil)
        let updated = PilgrimPackageBuilder.applyEmbeddedFilenames(
            to: walk,
            using: ["anything": "file.jpg"]
        )
        XCTAssertNil(updated.photos)
    }

    func testApplyEmbeddedFilenames_emptyPhotos_staysEmpty() {
        let walk = makeWalk(photos: [])
        let updated = PilgrimPackageBuilder.applyEmbeddedFilenames(
            to: walk,
            using: [:]
        )
        XCTAssertEqual(updated.photos?.count, 0)
    }

    func testApplyEmbeddedFilenames_stampsFilenameOnKeptPhotos() throws {
        let photo = makePhoto(localIdentifier: "A")
        let walk = makeWalk(photos: [photo])
        let updated = PilgrimPackageBuilder.applyEmbeddedFilenames(
            to: walk,
            using: ["A": "A.jpg"]
        )
        let kept = try XCTUnwrap(updated.photos?.first)
        XCTAssertEqual(kept.embeddedPhotoFilename, "A.jpg")
        XCTAssertEqual(kept.localIdentifier, "A", "Other fields must survive the stamp")
    }

    func testApplyEmbeddedFilenames_dropsPhotosMissingFromMap() {
        let a = makePhoto(localIdentifier: "A")
        let b = makePhoto(localIdentifier: "B")
        let c = makePhoto(localIdentifier: "C")
        let walk = makeWalk(photos: [a, b, c])
        let updated = PilgrimPackageBuilder.applyEmbeddedFilenames(
            to: walk,
            using: ["A": "A.jpg", "C": "C.jpg"]
        )
        XCTAssertEqual(
            updated.photos?.map { $0.localIdentifier },
            ["A", "C"],
            "Photos without filenames must be dropped; the viewer has no bytes to render them"
        )
        XCTAssertEqual(updated.photos?.map { $0.embeddedPhotoFilename }, ["A.jpg", "C.jpg"])
    }

    func testApplyEmbeddedFilenames_allPhotosDroppedWhenMapEmpty() {
        let a = makePhoto(localIdentifier: "A")
        let b = makePhoto(localIdentifier: "B")
        let walk = makeWalk(photos: [a, b])
        let updated = PilgrimPackageBuilder.applyEmbeddedFilenames(
            to: walk,
            using: [:]
        )
        // Empty array (not nil): the user opted in, embedding just
        // happened to fail for every photo. skippedPhotoCount on the
        // builder result carries the failure signal.
        XCTAssertEqual(updated.photos?.count, 0)
        XCTAssertNotNil(updated.photos, "Must stay non-nil — user opted in, failure ≠ opt-out")
    }

    func testApplyEmbeddedFilenames_preservesNonPhotoFields() throws {
        let photo = makePhoto(localIdentifier: "A")
        let walk = makeWalk(photos: [photo])
        let updated = PilgrimPackageBuilder.applyEmbeddedFilenames(
            to: walk,
            using: ["A": "A.jpg"]
        )
        // The other 19 PilgrimWalk fields shouldn't have shifted.
        XCTAssertEqual(updated.id, walk.id)
        XCTAssertEqual(updated.type, walk.type)
        XCTAssertEqual(updated.startDate, walk.startDate)
        XCTAssertEqual(updated.endDate, walk.endDate)
        XCTAssertEqual(updated.stats.distance, walk.stats.distance)
        XCTAssertEqual(updated.intention, walk.intention)
        XCTAssertEqual(updated.isUserModified, walk.isUserModified)
    }

    // MARK: - Helpers

    private func makePhoto(localIdentifier: String) -> PilgrimPhoto {
        PilgrimPhoto(
            localIdentifier: localIdentifier,
            capturedAt: Date(timeIntervalSince1970: 1710001000),
            capturedLat: 10,
            capturedLng: 20,
            keptAt: Date(timeIntervalSince1970: 1710002000),
            embeddedPhotoFilename: nil
        )
    }

    private func makeWalk(photos: [PilgrimPhoto]?) -> PilgrimWalk {
        PilgrimWalk(
            schemaVersion: "1.0",
            id: UUID(),
            type: "walking",
            startDate: Date(timeIntervalSince1970: 1000),
            endDate: Date(timeIntervalSince1970: 2000),
            stats: PilgrimStats(
                distance: 100, steps: nil,
                activeDuration: 60, pauseDuration: 0,
                ascent: 0, descent: 0,
                burnedEnergy: nil,
                talkDuration: 0, meditateDuration: 0
            ),
            weather: nil,
            route: GeoJSONFeatureCollection(features: []),
            pauses: [],
            activities: [],
            voiceRecordings: [],
            intention: nil,
            reflection: nil,
            heartRates: [],
            workoutEvents: [],
            favicon: nil,
            isRace: false,
            isUserModified: false,
            finishedRecording: true,
            photos: photos
        )
    }

    /// Render a solid-color UIImage at the given size. Used as a stand-in
    /// for real photos; the resize pipeline doesn't care about content.
    private func makeTestImage(width: CGFloat, height: CGFloat, color: UIColor) -> UIImage {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
