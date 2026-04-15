import XCTest
@testable import Pilgrim

/// Unit coverage for `ExportConfirmationSheet`'s pure helpers. The sheet
/// itself is a SwiftUI view with no testable state machine — these tests
/// only cover the extracted static helpers that format text and resolve
/// the effective `includePhotos` value handed to the builder.
final class ExportConfirmationSheetTests: XCTestCase {

    // MARK: - walkCountText

    func testWalkCountText_singular() {
        XCTAssertEqual(ExportConfirmationSheet.walkCountText(for: 1), "1 walk")
    }

    func testWalkCountText_zero_plural() {
        // "0 walks" is grammatically correct English; also, the caller
        // should never present this sheet with zero walks, but if it did,
        // we'd rather render a sensible string than crash.
        XCTAssertEqual(ExportConfirmationSheet.walkCountText(for: 0), "0 walks")
    }

    func testWalkCountText_typical_plural() {
        XCTAssertEqual(ExportConfirmationSheet.walkCountText(for: 23), "23 walks")
    }

    func testWalkCountText_large_plural() {
        XCTAssertEqual(ExportConfirmationSheet.walkCountText(for: 1000), "1000 walks")
    }

    // MARK: - photoSizeText

    func testPhotoSizeText_singularPhoto() {
        let result = ExportConfirmationSheet.photoSizeText(photoCount: 1, bytes: 80_000)
        // "1 photo · ≈80 KB" — verify singular noun + decimal file-style KB.
        XCTAssertTrue(result.hasPrefix("1 photo · ≈"), "Expected singular 'photo' with middle dot + approx prefix, got: \(result)")
        XCTAssertTrue(result.contains("KB"), "Expected KB unit for 80 KB input, got: \(result)")
    }

    func testPhotoSizeText_pluralPhotos() {
        let result = ExportConfirmationSheet.photoSizeText(photoCount: 18, bytes: 1_440_000)
        XCTAssertTrue(result.hasPrefix("18 photos · ≈"), "Expected plural 'photos' prefix, got: \(result)")
        XCTAssertTrue(result.contains("MB"), "Expected MB unit for 1.44 MB input, got: \(result)")
    }

    func testPhotoSizeText_zeroPhotosAllowed() {
        // If the view is ever called with (0, 0) — e.g. the caller
        // forgot to hide the row — we still want a sensible string,
        // not a crash.
        let result = ExportConfirmationSheet.photoSizeText(photoCount: 0, bytes: 0)
        XCTAssertTrue(result.hasPrefix("0 photos · ≈"))
    }

    func testPhotoSizeText_middleDotSeparator() {
        // Regression guard: the separator must stay as " · " (space,
        // middle dot, space) to match the plan wording and the rest
        // of the app's typographic style.
        let result = ExportConfirmationSheet.photoSizeText(photoCount: 5, bytes: 400_000)
        XCTAssertTrue(result.contains(" · "), "Must use middle-dot separator, got: \(result)")
    }

    // MARK: - effectiveIncludePhotos

    func testEffectiveIncludePhotos_noPhotos_toggleOn_returnsFalse() {
        // Invariant: if there are no pinned photos, the toggle row is
        // hidden and the user has no way to opt in. We must never pass
        // true to the builder in that case, regardless of the internal
        // @State value.
        XCTAssertFalse(ExportConfirmationSheet.effectiveIncludePhotos(
            pinnedPhotoCount: 0,
            userToggle: true
        ))
    }

    func testEffectiveIncludePhotos_noPhotos_toggleOff_returnsFalse() {
        XCTAssertFalse(ExportConfirmationSheet.effectiveIncludePhotos(
            pinnedPhotoCount: 0,
            userToggle: false
        ))
    }

    func testEffectiveIncludePhotos_withPhotos_toggleOn_returnsTrue() {
        XCTAssertTrue(ExportConfirmationSheet.effectiveIncludePhotos(
            pinnedPhotoCount: 5,
            userToggle: true
        ))
    }

    func testEffectiveIncludePhotos_withPhotos_toggleOff_returnsFalse() {
        XCTAssertFalse(ExportConfirmationSheet.effectiveIncludePhotos(
            pinnedPhotoCount: 5,
            userToggle: false
        ))
    }
}
