import Photos
import UIKit

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
            let photo = await withTimeoutOrNil(seconds: perPhotoTimeout) {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        continuation.resume(returning: loadOne(candidate))
                    }
                }
            }
            if let photo { out.append(photo) }
            progress(i + 1, candidates.count)
        }
        return out
    }

    private static func withTimeoutOrNil<T: Sendable>(seconds: TimeInterval, _ work: @escaping () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            guard let first = await group.next() else { return nil }
            group.cancelAll()
            return first
        }
    }

    private static func loadOne(_ candidate: PhotoCandidate) -> TourPhoto? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [candidate.localIdentifier], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = true
        options.resizeMode = .exact

        var result: TourPhoto?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: targetPixels, height: targetPixels),
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            guard let image, let data = jpegDataUnder(cap: maxBytes, image: image) else { return }
            result = TourPhoto(
                meta: SharePayload.Photo(
                    lat: candidate.capturedLat,
                    lon: candidate.capturedLng,
                    ts: Int(candidate.capturedAt.timeIntervalSince1970),
                    data: nil
                ),
                jpegData: data
            )
        }
        return result
    }
}
