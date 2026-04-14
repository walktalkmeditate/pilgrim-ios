import Foundation

/// Bidirectional conversion between the app's `WalkPhoto` relics and their
/// `.pilgrim` export shape `PilgrimPhoto`. Kept separate from
/// `PilgrimPackageConverter` so the main converter stays under SwiftLint's
/// type-body-length budget.
enum PilgrimPackagePhotoConverter {

    /// `includePhotos: false` returns nil so the JSON encoder omits the
    /// `photos` key entirely and exports stay byte-identical to the
    /// pre-reliquary format. The `embeddedPhotoFilename` on each entry is
    /// left nil here — the builder sets it later when it actually writes
    /// photo bytes into the ZIP.
    static func exportPhotos(
        from walkPhotos: [WalkPhotoInterface],
        includePhotos: Bool
    ) -> [PilgrimPhoto]? {
        guard includePhotos else { return nil }
        return walkPhotos.map { photo in
            PilgrimPhoto(
                localIdentifier: photo.localIdentifier,
                capturedAt: photo.capturedAt,
                capturedLat: photo.capturedLat,
                capturedLng: photo.capturedLng,
                keptAt: photo.keptAt,
                embeddedPhotoFilename: nil
            )
        }
    }

    /// Reverse conversion for imports. nil photos (older `.pilgrim` files or
    /// an opted-out export) yield an empty array.
    static func importPhotos(from exportedPhotos: [PilgrimPhoto]?) -> [TempWalkPhoto] {
        (exportedPhotos ?? []).map { photo in
            TempWalkPhoto(
                uuid: UUID(),
                localIdentifier: photo.localIdentifier,
                capturedAt: photo.capturedAt,
                capturedLat: photo.capturedLat,
                capturedLng: photo.capturedLng,
                keptAt: photo.keptAt
            )
        }
    }
}
