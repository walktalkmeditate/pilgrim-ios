import Foundation
import Photos

/// Ephemeral candidate produced by `WalkPhotoMatcher`. Not persisted until the user pins it
/// (at which point a `WalkPhoto` entity is created from the candidate's fields).
public struct PhotoCandidate: Equatable {
    public let localIdentifier: String
    public let capturedAt: Date
    public let capturedLat: Double
    public let capturedLng: Double
    public let isPinned: Bool
}

/// Input for the pure filter function. Strips `PHAsset` off the photo library side so the
/// filter logic can be tested without instantiating Apple's photo framework types.
public struct PhotoCandidateSource {
    public let localIdentifier: String
    public let creationDate: Date?
    public let latitude: Double?
    public let longitude: Double?
    public let isScreenshot: Bool
}

public enum WalkPhotoMatcher {

    /// Pure filter function. Given a list of photo sources and a walk's time window, returns
    /// the candidates that should appear in the reliquary carousel, chronologically ordered.
    /// Drops photos outside the time window, without location, or marked as screenshots.
    /// Each candidate carries an `isPinned` flag based on whether the user has already
    /// committed a `WalkPhoto` entity with the same local identifier.
    public static func filterCandidates(
        sources: [PhotoCandidateSource],
        walkStartDate: Date,
        walkEndDate: Date,
        pinnedIdentifiers: Set<String>
    ) -> [PhotoCandidate] {
        sources.compactMap { source -> PhotoCandidate? in
            guard let creationDate = source.creationDate else { return nil }
            guard creationDate >= walkStartDate && creationDate <= walkEndDate else { return nil }
            guard let latitude = source.latitude, let longitude = source.longitude else { return nil }
            guard !source.isScreenshot else { return nil }
            return PhotoCandidate(
                localIdentifier: source.localIdentifier,
                capturedAt: creationDate,
                capturedLat: latitude,
                capturedLng: longitude,
                isPinned: pinnedIdentifiers.contains(source.localIdentifier)
            )
        }
        .sorted { $0.capturedAt < $1.capturedAt }
    }

    /// PhotoKit adapter. Fetches all photo assets in the walk's time window, converts each
    /// to a `PhotoCandidateSource`, then delegates to `filterCandidates`. Requires Photos
    /// library read permission; caller must check `PermissionManager.standard.isPhotosGranted`
    /// before invoking.
    public static func findCandidates(
        for walk: WalkInterface,
        completion: @escaping ([PhotoCandidate]) -> Void
    ) {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@",
            walk.startDate as NSDate,
            walk.endDate as NSDate
        )

        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        var sources: [PhotoCandidateSource] = []
        sources.reserveCapacity(fetchResult.count)

        fetchResult.enumerateObjects { asset, _, _ in
            sources.append(PhotoCandidateSource(
                localIdentifier: asset.localIdentifier,
                creationDate: asset.creationDate,
                latitude: asset.location?.coordinate.latitude,
                longitude: asset.location?.coordinate.longitude,
                isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot)
            ))
        }

        let pinnedIdentifiers = Set(walk.walkPhotos.map { $0.localIdentifier })

        let candidates = filterCandidates(
            sources: sources,
            walkStartDate: walk.startDate,
            walkEndDate: walk.endDate,
            pinnedIdentifiers: pinnedIdentifiers
        )

        completion(candidates)
    }
}
