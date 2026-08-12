import Photos
import UIKit
import os

struct TourPhoto {
    let meta: SharePayload.Photo
    let jpegData: Data
    /// The PHAsset identifier this export came from — stable identity for
    /// matching a failed upload back to its source photo later, even if the
    /// candidate list's ORDER or LENGTH has since changed (see
    /// `WalkShareViewModel.resolveRetryItems`). Never sent to the server;
    /// `meta`/`jpegData` are the payload.
    let sourceLocalIdentifier: String
}

enum TourPhotoExporter {

    static let maxBytes = 2 * 1024 * 1024
    static let targetPixels: CGFloat = 1600
    static let perPhotoTimeout: TimeInterval = 20
    static let backstopGrace: TimeInterval = 2

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

    /// `progress` fires after every photo, off the main thread — `export` is a
    /// nonisolated async function and reports from whatever executor happens to
    /// be running when the current photo finishes, never the main actor. This
    /// differs from the sibling `WalkPhotoMatcher.findCandidates`, whose
    /// `completion` closure is always delivered on the main thread. Callers that
    /// update UI from `progress` must hop to the MainActor themselves.
    static func export(_ candidates: [PhotoCandidate], progress: @escaping (Int, Int) -> Void) async -> [TourPhoto] {
        var out: [TourPhoto] = []
        for (i, candidate) in candidates.enumerated() {
            // A cancelled share() must stop within ~one photo, not run the
            // whole remaining list — loadOne itself isn't cancellation-aware
            // (its own timeout/backstop bound it independently), so this is
            // the only place that can act on it.
            if Task.isCancelled { break }
            if let photo = await loadOne(candidate) { out.append(photo) }
            progress(i + 1, candidates.count)
        }
        return out
    }

    // Guarantee: wall-clock time is bounded by timeout + grace, not unbounded.
    // perPhotoTimeout cancels the underlying PHImageManager request itself
    // (PhotoKit's documented contract is to invoke the result handler with a
    // nil image once a request is cancelled), and an independent backstop at
    // perPhotoTimeout + backstopGrace force-resumes with nil even if that
    // callback never fires at all — wedged iCloud requests are a credible
    // failure mode, so the bound cannot depend entirely on PhotoKit calling
    // back. Either path resumes through the same one-shot lock, and whichever
    // fires first cancels the other's pending DispatchWorkItem.
    private static func loadOne(_ candidate: PhotoCandidate) async -> TourPhoto? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [candidate.localIdentifier], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.resizeMode = .exact

        return await withCheckedContinuation { continuation in
            let state = OSAllocatedUnfairLock(initialState: LoadState())

            let requestID = PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: targetPixels, height: targetPixels),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                let shouldResume = state.withLock { box -> Bool in
                    guard !box.resumed else { return false }
                    box.resumed = true
                    box.cancelItem?.cancel()
                    box.backstopItem?.cancel()
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
                    jpegData: data,
                    sourceLocalIdentifier: candidate.localIdentifier
                ))
            }

            // Deadline 1: nudge PhotoKit to give up on the fetch itself.
            let cancelItem = DispatchWorkItem {
                PHImageManager.default().cancelImageRequest(requestID)
            }

            // Deadline 2 (backstop): force the continuation to resume even if
            // PhotoKit never calls the result handler at all — independent of
            // whether cancelImageRequest actually interrupted anything.
            let backstopItem = DispatchWorkItem {
                let shouldResume = state.withLock { box -> Bool in
                    guard !box.resumed else { return false }
                    box.resumed = true
                    return true
                }
                guard shouldResume else { return }
                continuation.resume(returning: nil)
            }

            state.withLock {
                $0.cancelItem = cancelItem
                $0.backstopItem = backstopItem
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + perPhotoTimeout, execute: cancelItem)
            DispatchQueue.global().asyncAfter(deadline: .now() + perPhotoTimeout + backstopGrace, execute: backstopItem)
        }
    }

    private struct LoadState {
        var resumed = false
        var cancelItem: DispatchWorkItem?
        var backstopItem: DispatchWorkItem?
    }
}
