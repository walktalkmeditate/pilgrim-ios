import UIKit
import Photos

/// Loads and caches circular photo-marker images for
/// `PilgrimMapView`'s photo pin annotations. Owned by the map view's
/// Coordinator — pulled out as a standalone class so the Coordinator
/// doesn't exceed SwiftLint's type body length and so the async
/// image-loading logic is easier to reason about on its own.
///
/// The loader keeps a dictionary cache keyed by PHAsset
/// `localIdentifier`. `buildPoints` reads the cache synchronously;
/// cache misses kick off a PhotoKit request that, on success, stores
/// the built marker and invokes `onImageLoaded` so the caller can
/// trigger a redraw. Duplicate in-flight requests for the same
/// identifier are collapsed.
final class PhotoMarkerImageLoader {

    /// Circular-cropped marker images keyed by `PHAsset.localIdentifier`.
    private var images: [String: UIImage] = [:]

    /// LocalIdentifiers currently being fetched from PhotoKit.
    /// Prevents duplicate in-flight requests when multiple render
    /// passes happen while a photo is still loading.
    private var inFlightRequests: Set<String> = []

    /// Called on main when a new marker image lands in the cache.
    /// The map view's Coordinator installs this callback in
    /// `applyAnnotations` to trigger a redraw when each image
    /// arrives; captured weakly so a torn-down walk summary doesn't
    /// trigger a dangling redraw.
    var onImageLoaded: (() -> Void)?

    /// Returns the cached marker image for `localIdentifier`, or
    /// `nil` if nothing has been built for that identifier yet.
    /// Synchronous — safe to call from a render pass.
    func image(for localIdentifier: String) -> UIImage? {
        images[localIdentifier]
    }

    /// Synchronous image load for the fast path (local photos on
    /// this device). Uses `isSynchronous = true` with network
    /// access disabled so it never blocks on iCloud downloads.
    /// Returns nil if the photo is iCloud-only or no longer exists.
    /// ~10-50ms per local photo — acceptable for the 1-5 pinned
    /// photos typical in a walk's reliquary.
    func loadImageSync(localIdentifier: String) -> UIImage? {
        if let cached = images[localIdentifier] { return cached }

        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: [localIdentifier],
            options: nil
        )
        guard let asset = fetchResult.firstObject else { return nil }

        let scale = UIScreen.main.scale
        let targetSize = CGSize(
            width: PhotoMarkerImageBuilder.defaultDiameter * 2 * scale,
            height: PhotoMarkerImageBuilder.defaultDiameter * 2 * scale
        )

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = false
        options.isSynchronous = true
        options.resizeMode = .exact

        var result: UIImage?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            result = image
        }

        guard let image = result else { return nil }
        let marker = PhotoMarkerImageBuilder.build(from: image)
        images[localIdentifier] = marker
        return marker
    }

    /// Async fallback for iCloud-only photos where the sync path
    /// returned nil. Kicks off a network-enabled PhotoKit fetch,
    /// caches the result, and invokes `onImageLoaded` so the map
    /// can swap out the placeholder on a later render pass.
    func loadImage(localIdentifier: String) {
        guard images[localIdentifier] == nil else { return }
        guard !inFlightRequests.contains(localIdentifier) else { return }
        inFlightRequests.insert(localIdentifier)

        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: [localIdentifier],
            options: nil
        )
        guard let asset = fetchResult.firstObject else {
            inFlightRequests.remove(localIdentifier)
            return
        }

        // Target ~2x the marker diameter in points so the marker
        // image is sharp at Retina scale. PHImageManager honours
        // this as a hint, not an exact contract, so the actual
        // returned image may differ slightly.
        let scale = UIScreen.main.scale
        let targetSize = CGSize(
            width: PhotoMarkerImageBuilder.defaultDiameter * 2 * scale,
            height: PhotoMarkerImageBuilder.defaultDiameter * 2 * scale
        )

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.resizeMode = .exact

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, info in
            // .highQualityFormat should be a single call, but guard
            // against intermediate degraded callbacks just in case
            // the delivery mode changes in a future refactor — we
            // only want the final sharp image for the marker.
            if let degraded = info?[PHImageResultIsDegradedKey] as? Bool, degraded {
                return
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.inFlightRequests.remove(localIdentifier)
                guard let image = image else { return }
                let marker = PhotoMarkerImageBuilder.build(from: image)
                self.images[localIdentifier] = marker
                self.onImageLoaded?()
            }
        }
    }
}
