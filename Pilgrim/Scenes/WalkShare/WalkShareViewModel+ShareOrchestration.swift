import Foundation

/// The POST → media-PUT orchestration `share()` drives, plus the "Carry the
/// missing files" retry path. Lives in its own file to keep
/// `WalkShareViewModel` under the type-body-length ceiling (mirrors
/// `ActiveWalkViewModel+Seek.swift`).
extension WalkShareViewModel {

    func share() async {
        guard canShare else { return }
        shareState = .uploading

        let tourPhotos: [TourPhoto]
        if interactiveEnabled, includePhotos, hasPinnedPhotos {
            tourPhotos = await TourPhotoExporter.export(interactivePhotoExportList()) { [weak self] done, total in
                Task { @MainActor in self?.shareState = .preparingPhotos(completed: done, total: total) }
            }
        } else {
            tourPhotos = []
        }

        let placeNames = await geocodeEndpoints()
        let payload = buildPayload(
            placeStart: placeNames.start,
            placeEnd: placeNames.end,
            tourPhotoMeta: tourPhotos.map(\.meta)
        )

        do {
            let result = try await ShareService.share(payload: payload)
            if let uuid = walk.uuid {
                ShareService.cacheShare(result, walkID: uuid, expiryDays: selectedExpiry.rawValue, expiryOption: selectedExpiry.cacheKey)
            }

            if interactiveEnabled {
                let audioFiles = TourBuilder.tourItems(candidates: tourCandidates, trimM: 0).files
                // Prime the phase synchronously (no unstructured-Task hop to
                // race) so the FIRST progress tick already finds shareState
                // in .uploadingMedia — see applyMediaProgress.
                shareState = .uploadingMedia(completed: 0, total: audioFiles.count + tourPhotos.count)
                let failures = await ShareService.uploadAllMedia(
                    shareID: result.id,
                    audioFiles: audioFiles,
                    photos: tourPhotos.map(\.jpegData)
                ) { [weak self] progress in
                    Task { @MainActor in self?.applyMediaProgress(progress) }
                }
                if let uuid = walk.uuid { ShareService.cacheFailedMedia(failures, walkID: uuid) }
                shareState = failures.isEmpty
                    ? .success(url: result.url)
                    : .partial(url: result.url, failedCount: failures.count)
            } else {
                shareState = .success(url: result.url)
            }
        } catch {
            shareState = .error(message: error.localizedDescription)
        }
    }

    /// Rebuilds data sources for a previous share's failed `(kind, n)` list
    /// and re-attempts just those uploads ("Carry the missing files").
    /// Assumes the walker's recording/photo selection hasn't changed since
    /// the original share — true in the common case (retrying moments after
    /// a failed PUT, same session). Across a re-entry `tourCandidates` may
    /// be empty, so it's recomputed fresh from the walk; if a failed index
    /// still doesn't resolve (selection genuinely changed), that item is
    /// left out of the retry and stays counted as failed rather than
    /// uploaded to the wrong slot.
    func retryFailedMedia() async {
        guard let uuid = walk.uuid, let cached = ShareService.cachedShare(for: uuid) else { return }
        let failed = ShareService.failedMedia(for: uuid)
        guard !failed.isEmpty else { return }

        // Leave .partial synchronously, before the possibly-multi-second photo
        // re-export below — otherwise "Carry the missing files" stays on
        // screen and tappable during that gap, and a second tap would start
        // an overlapping retry of the same items.
        shareState = .uploadingMedia(completed: 0, total: failed.count)

        let candidates = tourCandidates.isEmpty ? TourBuilder.candidates(for: walk) : tourCandidates
        let audioFiles = TourBuilder.tourItems(candidates: candidates, trimM: 0).files

        let photoData: [Data]
        if failed.contains(where: { $0.kind == .photos }) {
            let reExported = await TourPhotoExporter.export(interactivePhotoExportList()) { _, _ in }
            photoData = reExported.map(\.jpegData)
        } else {
            photoData = []
        }

        var items: [(kind: ShareService.MediaKind, n: Int, data: () throws -> Data)] = []
        var unresolved: [(kind: ShareService.MediaKind, n: Int)] = []
        for failure in failed {
            let index = failure.n - 1
            switch failure.kind {
            case .audio:
                guard audioFiles.indices.contains(index) else { unresolved.append(failure); continue }
                let fileURL = audioFiles[index]
                items.append((kind: .audio, n: failure.n, data: { try Data(contentsOf: fileURL) }))
            case .photos:
                guard photoData.indices.contains(index) else { unresolved.append(failure); continue }
                let data = photoData[index]
                items.append((kind: .photos, n: failure.n, data: { data }))
            }
        }
        guard !items.isEmpty else {
            // Nothing could be rebuilt (e.g. the pinned set changed) — undo
            // the state above rather than leave the UI stuck mid-progress.
            shareState = .partial(url: cached.url, failedCount: failed.count)
            return
        }

        shareState = .uploadingMedia(completed: 0, total: items.count)
        let stillFailed = await ShareService.uploadSpecific(shareID: cached.id, items: items) { [weak self] progress in
            Task { @MainActor in self?.applyMediaProgress(progress) }
        }

        let remaining = stillFailed + unresolved
        ShareService.cacheFailedMedia(remaining, walkID: uuid)
        shareState = remaining.isEmpty
            ? .success(url: cached.url)
            : .partial(url: cached.url, failedCount: remaining.count)
    }

    /// Applies a media-upload progress tick only while `shareState` is still
    /// `.uploadingMedia`. Progress hops from `uploadAllMedia`/`uploadSpecific`
    /// run as unstructured `Task`s off their (nonisolated) progress closure,
    /// so a hop can still be queued on the MainActor after `share()` or
    /// `retryFailedMedia()` has already set a terminal state and run after
    /// it. Gating on the phase makes a late hop a no-op instead of
    /// clobbering `.success`/`.partial`/`.error`.
    private func applyMediaProgress(_ progress: ShareService.MediaProgress) {
        guard case .uploadingMedia = shareState else { return }
        shareState = .uploadingMedia(completed: progress.completed, total: progress.total)
    }

    /// The candidate list `share()` exports hi-res photos from — reused by
    /// `retryFailedMedia()` so a retry re-derives the same trimmed window
    /// and 20-photo cap the original share used (assuming `interactiveEnabled`
    /// and `trimEnabled` haven't changed since; see `retryFailedMedia`).
    private func interactivePhotoExportList() -> [PhotoCandidate] {
        guard hasPinnedPhotos else { return [] }
        let window = interactiveKeptWindow()
        return Array(
            pinnedPhotos
                .filter { window?.contains(Int($0.capturedAt.timeIntervalSince1970)) ?? true }
                .prefix(20)
        )
    }
}
