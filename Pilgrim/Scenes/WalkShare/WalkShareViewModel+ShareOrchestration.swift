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
            let exportList = interactivePhotoExportList()
            // Prime synchronously, same reason as .uploadingMedia below — the
            // first progress tick only fires after the first photo finishes
            // loading, so without this the phase would never actually become
            // .preparingPhotos and applyPreparingPhotosProgress's guard would
            // reject every tick.
            shareState = .preparingPhotos(completed: 0, total: exportList.count)
            tourPhotos = await TourPhotoExporter.export(exportList) { [weak self] done, total in
                Task { @MainActor in self?.applyPreparingPhotosProgress(completed: done, total: total) }
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
                let tourItems = TourBuilder.tourItems(candidates: tourCandidates, trimM: 0)
                let audioFiles = tourItems.files
                let audioRecordings = tourItems.tour.recordings
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
                if let uuid = walk.uuid {
                    let failureItems = failures.map {
                        Self.failedMediaItem(for: $0, audioRecordings: audioRecordings, tourPhotos: tourPhotos)
                    }
                    ShareService.cacheFailedMedia(failureItems, walkID: uuid)
                }
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

    /// Builds the stable-identity cache record for one failed upload slot,
    /// reading from the SAME arrays `share()` just uploaded from — `failure.n`
    /// indexes directly into them, since that's the order `uploadAllMedia`
    /// PUT things in. This identity (not `n` alone) is what lets a later
    /// retry verify it's about to send the right bytes — see
    /// `resolveRetryItems`.
    private static func failedMediaItem(
        for failure: (kind: ShareService.MediaKind, n: Int),
        audioRecordings: [SharePayload.TourRecording],
        tourPhotos: [TourPhoto]
    ) -> ShareService.FailedMediaItem {
        switch failure.kind {
        case .audio:
            let startTs = audioRecordings.indices.contains(failure.n - 1) ? audioRecordings[failure.n - 1].startTs : nil
            return ShareService.FailedMediaItem(kind: failure.kind.rawValue, n: failure.n, audioStartTs: startTs, photoLocalID: nil, photoTs: nil)
        case .photos:
            let photo = tourPhotos.indices.contains(failure.n - 1) ? tourPhotos[failure.n - 1] : nil
            return ShareService.FailedMediaItem(kind: failure.kind.rawValue, n: failure.n, audioStartTs: nil, photoLocalID: photo?.sourceLocalIdentifier, photoTs: photo?.meta.ts)
        }
    }

    /// Rebuilds data sources for a previous share's failed items and
    /// re-attempts just those ("Carry the missing files"). Never trusts `n`
    /// alone to still point at the right file — `resolveRetryItems` verifies
    /// stable identity (recording `startTs`; photo `localIdentifier` + `ts`)
    /// against the CURRENT candidate set before anything is queued for
    /// upload, so a shifted or missing candidate is skipped (stays counted
    /// as failed) rather than risking the wrong bytes landing on a live page.
    func retryFailedMedia() async {
        guard let uuid = walk.uuid, let cached = ShareService.cachedShare(for: uuid) else { return }
        let failed = ShareService.failedMedia(for: uuid)
        guard !failed.isEmpty else { return }

        // Leave .partial synchronously, before the possibly-multi-second photo
        // re-export below — otherwise "Carry the missing files" stays on
        // screen and tappable during that gap, and a second tap would start
        // an overlapping retry of the same items.
        shareState = .uploadingMedia(completed: 0, total: failed.count)

        let currentRecordings: [SharePayload.TourRecording]
        let currentAudioFiles: [URL]
        if failed.contains(where: { $0.kind == ShareService.MediaKind.audio.rawValue }) {
            let candidates = tourCandidates.isEmpty ? TourBuilder.candidates(for: walk) : tourCandidates
            let tourItems = TourBuilder.tourItems(candidates: candidates, trimM: 0)
            currentRecordings = tourItems.tour.recordings
            currentAudioFiles = tourItems.files
        } else {
            currentRecordings = []
            currentAudioFiles = []
        }

        // Re-export only the specific photos that failed, by identity — not
        // the whole (up to 20-photo) export list again.
        let failedPhotoIDs = Set(failed.compactMap { $0.kind == ShareService.MediaKind.photos.rawValue ? $0.photoLocalID : nil })
        let photoCandidatesToReExport = pinnedPhotos.filter { failedPhotoIDs.contains($0.localIdentifier) }
        let currentPhotos: [TourPhoto] = photoCandidatesToReExport.isEmpty
            ? []
            : await TourPhotoExporter.export(photoCandidatesToReExport) { _, _ in }

        let (uploadable, remainingAfterResolve) = Self.resolveRetryItems(
            cached: failed,
            currentRecordings: currentRecordings,
            currentAudioFiles: currentAudioFiles,
            currentPhotos: currentPhotos
        )

        guard !uploadable.isEmpty else {
            ShareService.cacheFailedMedia(remainingAfterResolve, walkID: uuid)
            shareState = .partial(url: cached.url, failedCount: remainingAfterResolve.count)
            return
        }

        shareState = .uploadingMedia(completed: 0, total: uploadable.count)
        let stillFailedRaw = await ShareService.uploadSpecific(shareID: cached.id, items: uploadable) { [weak self] progress in
            Task { @MainActor in self?.applyMediaProgress(progress) }
        }
        // Recover each still-failed item's full identity from the cache we
        // resolved it from, so a THIRD attempt can still verify it too.
        let stillFailed = stillFailedRaw.compactMap { raw in
            failed.first { $0.kind == raw.kind.rawValue && $0.n == raw.n }
        }

        let remaining = stillFailed + remainingAfterResolve
        ShareService.cacheFailedMedia(remaining, walkID: uuid)
        shareState = remaining.isEmpty
            ? .success(url: cached.url)
            : .partial(url: cached.url, failedCount: remaining.count)
    }

    /// Pure identity resolution — no MainActor/instance state — so it's
    /// directly unit-testable. Matches each cached failure to CURRENT data by
    /// stable identity, never by `n` alone: an index that's still "in bounds"
    /// after the underlying candidate set shifted (an export drop, an unpin)
    /// can silently point at a DIFFERENT file than the one that failed.
    /// Audio is index-checked THEN identity-verified at that same index
    /// (recordings keep their relative order); photos are found by identity
    /// search across the whole current set (their position isn't assumed to
    /// be stable at all) and uploaded under the CACHED `n`, never their own
    /// current position. Anything that doesn't verify is returned in
    /// `remaining`, untouched, rather than uploaded to a guessed slot.
    nonisolated static func resolveRetryItems(
        cached: [ShareService.FailedMediaItem],
        currentRecordings: [SharePayload.TourRecording],
        currentAudioFiles: [URL],
        currentPhotos: [TourPhoto]
    ) -> (uploadable: [(kind: ShareService.MediaKind, n: Int, data: () throws -> Data)], remaining: [ShareService.FailedMediaItem]) {
        var uploadable: [(kind: ShareService.MediaKind, n: Int, data: () throws -> Data)] = []
        var remaining: [ShareService.FailedMediaItem] = []

        for item in cached {
            guard let kind = ShareService.MediaKind(rawValue: item.kind) else {
                remaining.append(item)
                continue
            }
            switch kind {
            case .audio:
                let index = item.n - 1
                guard currentRecordings.indices.contains(index),
                      currentAudioFiles.indices.contains(index),
                      currentRecordings[index].startTs == item.audioStartTs else {
                    remaining.append(item)
                    continue
                }
                let fileURL = currentAudioFiles[index]
                uploadable.append((kind: .audio, n: item.n, data: { try Data(contentsOf: fileURL) }))
            case .photos:
                guard let match = currentPhotos.first(where: {
                    $0.sourceLocalIdentifier == item.photoLocalID && $0.meta.ts == item.photoTs
                }) else {
                    remaining.append(item)
                    continue
                }
                let data = match.jpegData
                uploadable.append((kind: .photos, n: item.n, data: { data }))
            }
        }

        return (uploadable, remaining)
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

    /// Same late-arrival guard as `applyMediaProgress`, for the photo-export
    /// phase: a stale tick landing after a terminal state must not clobber
    /// `.success`/`.partial`/`.error`, and must not re-lock dismissal by
    /// flipping `shareState` back into an `isShareInFlight` case.
    private func applyPreparingPhotosProgress(completed: Int, total: Int) {
        guard case .preparingPhotos = shareState else { return }
        shareState = .preparingPhotos(completed: completed, total: total)
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
