import Photos
import UIKit
import os

struct TourPhoto {
    let meta: SharePayload.Photo
    let jpegData: Data
}

enum TourPhotoExporter {

    static let maxBytes = 2 * 1024 * 1024
    static let targetPixels: CGFloat = 1600
    static let perPhotoTimeout: TimeInterval = 20

    /// Interactive pages show photography full-bleed: export at 1600px
    /// (vs the classic page's 600px inline thumbnails), walking quality
    /// down until the file fits the worker's 2MB per-photo cap.
    static func jpegDataUnder(cap: Int, image: UIImage) -> Data? {
        for quality in [0.8, 0.65, 0.5, 0.35, 0.2] {
            if let data = image.jpegData(compressionQuality: quality), data.count <= cap {
                return data
            }
        }
        return nil
    }

    static func export(_ candidates: [PhotoCandidate], progress: @escaping (Int, Int) -> Void) async -> [TourPhoto] {
        var out: [TourPhoto] = []
        for (i, candidate) in candidates.enumerated() {
            if let photo = await loadOne(candidate) { out.append(photo) }
            progress(i + 1, candidates.count)
        }
        return out
    }

    // Guarantee: perPhotoTimeout cancels the underlying PHImageManager request
    // itself (via cancelImageRequest), not just the value this function is
    // waiting on. PhotoKit's documented contract is to invoke the result
    // handler with a nil image once a request is cancelled, so a stalled
    // iCloud fetch is interrupted at the source and cannot block the share
    // beyond perPhotoTimeout — wall-clock time is genuinely bounded.
    private static func loadOne(_ candidate: PhotoCandidate) async -> TourPhoto? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [candidate.localIdentifier], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.resizeMode = .exact

        return await withCheckedContinuation { continuation in
            let hasResumed = OSAllocatedUnfairLock(initialState: false)

            let requestID = PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: targetPixels, height: targetPixels),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                let shouldResume = hasResumed.withLock { alreadyResumed -> Bool in
                    guard !alreadyResumed else { return false }
                    alreadyResumed = true
                    return true
                }
                guard shouldResume else { return }
                guard let image, let data = jpegDataUnder(cap: maxBytes, image: image) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: TourPhoto(
                    meta: SharePayload.Photo(
                        lat: candidate.capturedLat,
                        lon: candidate.capturedLng,
                        ts: Int(candidate.capturedAt.timeIntervalSince1970),
                        data: nil
                    ),
                    jpegData: data
                ))
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + perPhotoTimeout) {
                PHImageManager.default().cancelImageRequest(requestID)
            }
        }
    }
}
