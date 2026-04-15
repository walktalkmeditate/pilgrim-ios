import Foundation
import Photos
import UIKit

/// Fetches pinned reliquary photos from PhotoKit, resizes them to a small
/// bounding box, encodes as JPEG, and writes them into a `photos/`
/// subdirectory so `PilgrimPackageBuilder` can ZIP them into a `.pilgrim`
/// archive. Returns a map of `localIdentifier → filename` for every photo
/// whose bytes successfully landed, plus a count of photos that were
/// skipped (PHAsset missing, iCloud unreachable, resize/encode failure,
/// or bytes over the hard ceiling).
///
/// Resizes target is ≤600×600 aspect-fit, JPEG quality 0.7 — per the plan,
/// average target ~80 KB per photo, hard ceiling 150 KB. Anything over the
/// ceiling is rejected rather than silently bloating the archive.
enum PilgrimPhotoEmbedder {

    struct EmbedResult {
        let filenameMap: [String: String]
        let skippedCount: Int
    }

    /// Maximum bounding-box dimension for the resized JPEG.
    private static let maxDimension: CGFloat = 600

    /// JPEG quality factor applied to every photo.
    private static let jpegQuality: CGFloat = 0.7

    /// Hard ceiling on encoded size (150 KB). Photos that exceed this after
    /// resize+encode are rejected — should never happen for ≤600px images
    /// at q 0.7, but this catches pathological cases rather than letting
    /// a bloated file silently enter the archive.
    private static let maxEncodedBytes = 150_000

    /// Embed every pinned photo from the given walks into `tempDir/photos/`.
    /// Must be called from a background queue: this method issues
    /// synchronous `PHImageManager.requestImage` calls, which block the
    /// caller for the duration of each fetch (potentially several seconds
    /// per photo if the asset must be downloaded from iCloud).
    static func embedPhotos(
        from walks: [PilgrimWalk],
        into tempDir: URL
    ) -> EmbedResult {
        let photosDir = tempDir.appendingPathComponent("photos")
        var filenameMap: [String: String] = [:]
        var skippedCount = 0
        var photosDirectoryEnsured = false

        for walk in walks {
            guard let photos = walk.photos else { continue }
            for photo in photos {
                autoreleasepool {
                    guard let jpegData = encodePhoto(localIdentifier: photo.localIdentifier) else {
                        skippedCount += 1
                        return
                    }

                    if !photosDirectoryEnsured {
                        do {
                            try FileManager.default.createDirectory(
                                at: photosDir,
                                withIntermediateDirectories: true
                            )
                            photosDirectoryEnsured = true
                        } catch {
                            print("[PilgrimPhotoEmbedder] Failed to create photos directory: \(error)")
                            skippedCount += 1
                            return
                        }
                    }

                    let filename = sanitizedFilename(for: photo.localIdentifier)
                    let destination = photosDir.appendingPathComponent(filename)
                    do {
                        try jpegData.write(to: destination)
                        filenameMap[photo.localIdentifier] = filename
                    } catch {
                        print("[PilgrimPhotoEmbedder] Failed to write \(filename): \(error)")
                        skippedCount += 1
                    }
                }
            }
        }

        return EmbedResult(filenameMap: filenameMap, skippedCount: skippedCount)
    }

    /// Sanitizes a `PHAsset.localIdentifier` for use as a filename. PhotoKit
    /// identifiers use `/` as a segment separator (e.g. `ABC-123/L0/001`),
    /// which would create unintended subdirectories when used as a path
    /// component. Replace with `_` to flatten.
    static func sanitizedFilename(for localIdentifier: String) -> String {
        let cleaned = localIdentifier.replacingOccurrences(of: "/", with: "_")
        return "\(cleaned).jpg"
    }

    /// Resizes a UIImage to fit within `maxDimension × maxDimension`
    /// preserving aspect ratio, then encodes as JPEG at `jpegQuality`.
    /// Returns nil only if UIImage's JPEG encoder refuses the image
    /// (malformed CGImage, unsupported color space, etc.).
    static func resizeAndEncode(_ image: UIImage) -> Data? {
        let originalSize = image.size
        let scale = min(
            maxDimension / originalSize.width,
            maxDimension / originalSize.height,
            1.0
        )

        if scale >= 1.0 {
            // Already within bounds. Encode directly without re-rendering.
            return image.jpegData(compressionQuality: jpegQuality)
        }

        let newSize = CGSize(
            width: (originalSize.width * scale).rounded(),
            height: (originalSize.height * scale).rounded()
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return resized.jpegData(compressionQuality: jpegQuality)
    }

    // MARK: - Private helpers

    /// Resolve a PHAsset by local identifier, fetch its image via
    /// PhotoKit (synchronously — we're on a background queue), resize,
    /// and encode. Returns nil if any step fails; caller handles the
    /// skipped count and logging.
    private static func encodePhoto(localIdentifier: String) -> Data? {
        let fetch = PHAsset.fetchAssets(
            withLocalIdentifiers: [localIdentifier],
            options: nil
        )
        guard let asset = fetch.firstObject else {
            print("[PilgrimPhotoEmbedder] PHAsset not found for \(localIdentifier)")
            return nil
        }

        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.version = .current
        options.resizeMode = .fast

        // Request an image that's big enough to resize down to
        // maxDimension without upscaling. 1200x1200 gives ~2x headroom,
        // letting Core Image pick a reasonable mipmap level.
        let targetSize = CGSize(width: maxDimension * 2, height: maxDimension * 2)

        var resultImage: UIImage?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            resultImage = image
            if let info = info, let error = info[PHImageErrorKey] as? Error {
                print("[PilgrimPhotoEmbedder] PHImageManager error for \(localIdentifier): \(error)")
            }
        }

        guard let image = resultImage else {
            print("[PilgrimPhotoEmbedder] PHImageManager returned no image for \(localIdentifier)")
            return nil
        }

        guard let jpegData = resizeAndEncode(image) else {
            print("[PilgrimPhotoEmbedder] Resize/encode failed for \(localIdentifier)")
            return nil
        }

        guard jpegData.count <= maxEncodedBytes else {
            print("[PilgrimPhotoEmbedder] Photo \(localIdentifier) exceeded \(maxEncodedBytes) bytes (\(jpegData.count)), skipping")
            return nil
        }

        return jpegData
    }
}
