import Foundation
import UIKit
import os

enum ShareService {

    private static let baseURL = "https://walk.pilgrimapp.org"
    private static let deviceTokenKey = "pilgrim.share.device-token"

    enum ShareError: LocalizedError {
        case encodingFailed
        case networkError(String)
        case serverError(Int, String)
        case rateLimited

        var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "Failed to prepare walk data."
            case .networkError(let message):
                return "Network error: \(message)"
            case .serverError(let code, let message):
                return "Server error (\(code)): \(message)"
            case .rateLimited:
                return "You've shared too many walks today. Try again tomorrow."
            }
        }
    }

    struct ShareResult {
        let url: String
        let id: String
    }

    struct CachedShare {
        let url: String
        let id: String
        let expiry: Date
        let shareDate: Date?
        let expiryOption: String?
        var isExpired: Bool { expiry <= Date() }
    }

    static func share(payload: SharePayload) async throws -> ShareResult {
        let url = URL(string: "\(baseURL)/api/share")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceToken(), forHTTPHeaderField: "X-Device-Token")
        request.timeoutInterval = 30

        let encoder = JSONEncoder()
        guard let body = try? encoder.encode(payload) else {
            throw ShareError.encodingFailed
        }
        request.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ShareError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ShareError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 429 {
            throw ShareError.rateLimited
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error
                ?? "Unknown error"
            throw ShareError.serverError(httpResponse.statusCode, message)
        }

        let result = try JSONDecoder().decode(SuccessResponse.self, from: data)
        return ShareResult(url: result.url, id: result.id)
    }

    static func deviceTokenForFeedback() -> String {
        deviceToken()
    }

    private static func deviceToken() -> String {
        if let existing = UserDefaults.standard.string(forKey: deviceTokenKey) {
            return existing
        }
        let token = UUID().uuidString
        UserDefaults.standard.set(token, forKey: deviceTokenKey)
        return token
    }

    private static let isoFormatter = ISO8601DateFormatter()

    static func cachedShare(for walkID: UUID) -> CachedShare? {
        guard let dict = UserDefaults.standard.dictionary(forKey: "share:\(walkID.uuidString)"),
              let url = dict["url"] as? String,
              let id = dict["id"] as? String,
              let expiryStr = dict["expiry"] as? String,
              let expiry = isoFormatter.date(from: expiryStr) else {
            return nil
        }

        let shareDate = (dict["shareDate"] as? String).flatMap { isoFormatter.date(from: $0) }
        let expiryOption = dict["expiryOption"] as? String

        return CachedShare(
            url: url,
            id: id,
            expiry: expiry,
            shareDate: shareDate,
            expiryOption: expiryOption
        )
    }

    static func cacheShare(_ result: ShareResult, walkID: UUID, expiryDays: Int, expiryOption: String?) {
        let now = Date()
        let expiry = Calendar.current.date(byAdding: .day, value: expiryDays, to: now) ?? now
        var dict: [String: String] = [
            "url": result.url,
            "id": result.id,
            "expiry": isoFormatter.string(from: expiry),
            "shareDate": isoFormatter.string(from: now),
        ]
        if let expiryOption {
            dict["expiryOption"] = expiryOption
        }
        UserDefaults.standard.set(dict, forKey: "share:\(walkID.uuidString)")
    }
}

// MARK: - Interactive media uploads

extension ShareService {

    struct MediaProgress: Equatable {
        let completed: Int
        let total: Int
    }

    enum MediaKind: String { case audio, photos }

    static func mediaUploadRequest(shareID: String, kind: MediaKind, n: Int, contentLength: Int) -> URLRequest {
        let url = URL(string: "\(baseURL)/api/share/\(shareID)/\(kind.rawValue)/\(n)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(kind == .audio ? "audio/mp4" : "image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("\(contentLength)", forHTTPHeaderField: "Content-Length")
        request.setValue(deviceToken(), forHTTPHeaderField: "X-Device-Token")
        // Idle timeout — resets on bytes moving, so slow uploads survive;
        // stalls fail fast so the repair path picks them up instead of
        // burning background time on a connection that's already dead.
        request.timeoutInterval = 30
        return request
    }

    /// Sequential by contract: photos MUST land in index order (enrich
    /// HEADs only the last one), and one-at-a-time keeps memory flat for
    /// 15MB audio files. PHOTOS UPLOAD FIRST — they gate the keepsake
    /// render window; audio degrades gracefully to "voice unavailable".
    /// Each item gets one retry. Runs inside a background-task assertion
    /// so pocketing the phone doesn't kill the remaining PUTs. Returns
    /// the indices (1-based, per kind) that ultimately failed.
    static func uploadAllMedia(
        shareID: String,
        audioFiles: [URL],
        photos: [Data],
        onItemSuccess: ((MediaKind, Int) -> Void)? = nil,
        progress: @escaping (MediaProgress) -> Void
    ) async -> [(kind: MediaKind, n: Int)] {
        return await withBackgroundAssertion(named: "pilgrim.share.media") {
            var failures: [(kind: MediaKind, n: Int)] = []
            let total = audioFiles.count + photos.count
            var completed = 0

            func report() { progress(MediaProgress(completed: completed, total: total)) }
            report()

            // Photos first: enrich's keepsake render waits (bounded) on the
            // LAST photo; audio has a graceful fallback on the page.
            for (index, data) in photos.enumerated() {
                // Don't start a PUT the OS is about to kill mid-flight — the
                // repair record turns the untried tail into a Carry-the-
                // missing-files offer instead of a truncated upload.
                if await backgroundTimeExhausted() {
                    for remaining in index..<photos.count { failures.append((.photos, remaining + 1)) }
                    // Bounded to what THIS loop still owes, not the grand total — jumping straight to `total` would let `completed` overshoot if the app foregrounds before the audio loop below and that one finishes normally.
                    completed += photos.count - index
                    report()
                    break
                }
                let ok = await putWithRetry(shareID: shareID, kind: .photos, n: index + 1) { data }
                if ok {
                    onItemSuccess?(.photos, index + 1)
                } else {
                    failures.append((.photos, index + 1))
                }
                completed += 1
                report()
            }

            for (index, fileURL) in audioFiles.enumerated() {
                if await backgroundTimeExhausted() {
                    for remaining in index..<audioFiles.count { failures.append((.audio, remaining + 1)) }
                    // Same reasoning as the photos loop above.
                    completed += audioFiles.count - index
                    report()
                    break
                }
                let ok = await putWithRetry(shareID: shareID, kind: .audio, n: index + 1) {
                    try Data(contentsOf: fileURL)
                }
                if ok {
                    onItemSuccess?(.audio, index + 1)
                } else {
                    failures.append((.audio, index + 1))
                }
                completed += 1
                report()
            }
            return failures
        }
    }

    /// Targeted re-upload for a previous share's failed items ("Carry the
    /// missing files"). Same ordering rules; audio resolved from URLs,
    /// photos re-exported by the caller. This is the recovery path with
    /// the same per-file sizes as the original upload, so it shares the
    /// same background-task protection as uploadAllMedia.
    static func uploadSpecific(
        shareID: String,
        items: [(kind: MediaKind, n: Int, data: () throws -> Data)],
        onItemSuccess: ((MediaKind, Int) -> Void)? = nil,
        progress: @escaping (MediaProgress) -> Void
    ) async -> [(kind: MediaKind, n: Int)] {
        return await withBackgroundAssertion(named: "pilgrim.share.media") {
            var failures: [(kind: MediaKind, n: Int)] = []
            progress(MediaProgress(completed: 0, total: items.count))
            for (i, item) in items.enumerated() {
                if await backgroundTimeExhausted() {
                    for remaining in i..<items.count { failures.append((items[remaining].kind, items[remaining].n)) }
                    progress(MediaProgress(completed: items.count, total: items.count))
                    break
                }
                let ok = await putWithRetry(shareID: shareID, kind: item.kind, n: item.n, body: item.data)
                if ok {
                    onItemSuccess?(item.kind, item.n)
                } else {
                    failures.append((item.kind, item.n))
                }
                progress(MediaProgress(completed: i + 1, total: items.count))
            }
            return failures
        }
    }

    /// Injected rather than reading `UIApplication.shared` directly (mirrors
    /// `WalkShareViewModel.isPhotosGranted`'s precedent): the OS background
    /// state can't be driven from a unit test, so `backgroundTimeExhausted()`
    /// needs a seam a test can force deterministically. Tests restore the
    /// default in `tearDown`.
    nonisolated(unsafe) static var backgroundStateProvider: @MainActor () -> (isBackground: Bool, remaining: TimeInterval) = {
        (UIApplication.shared.applicationState == .background, UIApplication.shared.backgroundTimeRemaining)
    }

    /// True once the OS is about to suspend the app mid-background-task: a
    /// PUT started now could be killed with the connection half-open, which
    /// the worker would just see as a dropped upload — better to never start
    /// it and let the repair record ("Carry the missing files") offer it
    /// once Pilgrim is foreground again. iOS grants ~30s of background time
    /// total — a threshold at or above that grant is always-true the instant
    /// the app backgrounds, abandoning the usable ~25s before it. 10s lets
    /// small items still proceed and only stops near true exhaustion; the
    /// real fix is a background URLSession (scheduled fast-follow).
    private static func backgroundTimeExhausted() async -> Bool {
        await MainActor.run {
            let state = backgroundStateProvider()
            return state.isBackground && state.remaining < 10
        }
    }

    /// A failed upload's slot (`kind`/`n`, the PUT index the worker is still
    /// missing) plus the STABLE identity of the file it was meant to carry.
    /// `n` alone isn't safe to retry against later: the local candidate list
    /// an index was drawn from can shift (an export drop, an unpin) between
    /// the original share and a retry, so the caller resolving this cache
    /// must verify identity (recording `startTs`, or photo `localIdentifier`
    /// + captured `ts`) before uploading anything under `n` again — see
    /// `WalkShareViewModel.resolveRetryItems`. `kind` is a raw string, not
    /// `MediaKind`, so this format doesn't depend on that enum's cases.
    struct FailedMediaItem: Codable, Equatable {
        let kind: String
        let n: Int
        let audioStartTs: Int?
        let photoLocalID: String?
        let photoTs: Int?
    }

    /// Failed-media bookkeeping alongside the cached share, so a re-entry
    /// can offer repair for the share's whole life (the worker accepts
    /// PUTs until expiry). Stored as JSON — no shipped data exists in this
    /// format yet, so it's free to change without a migration.
    static func cacheFailedMedia(_ failures: [FailedMediaItem], walkID: UUID) {
        let key = "share-failed-media:\(walkID.uuidString)"
        if failures.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(failures) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func failedMedia(for walkID: UUID) -> [FailedMediaItem] {
        let key = "share-failed-media:\(walkID.uuidString)"
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([FailedMediaItem].self, from: data) else { return [] }
        return items
    }

    /// Begins a background-task assertion, runs `body`, then ends it — so
    /// backgrounding the app (pocketing, locking) doesn't suspend an
    /// in-flight PUT chain. `BackgroundAssertionState` is the one-shot
    /// guard: the expiration handler (fired by the OS if we overstay our
    /// background time) and the normal completion path both race to end
    /// the same assertion, and the lock ensures only the first of them
    /// actually calls endBackgroundTask — calling it twice is documented
    /// Apple misuse. Not `private`: `WalkShareViewModel+ShareOrchestration.swift`
    /// wraps `TourPhotoExporter.export` in the same assertion — Swift's
    /// `private` is file-scoped, so staying cross-file-callable means at
    /// most internal access (the default).
    static func withBackgroundAssertion<T: Sendable>(
        named name: String,
        _ body: () async -> T
    ) async -> T {
        let state = OSAllocatedUnfairLock(initialState: BackgroundAssertionState())

        func endOnce() -> UIBackgroundTaskIdentifier? {
            state.withLock { s in
                guard !s.ended, s.identifier != .invalid else { return nil }
                s.ended = true
                return s.identifier
            }
        }

        await MainActor.run {
            let identifier = UIApplication.shared.beginBackgroundTask(withName: name) {
                // Apple's documented contract: the expiration handler runs
                // on the main thread already, so assert isolation instead
                // of hopping through a Task — the app may already be
                // suspending by the time this fires.
                guard let idToEnd = endOnce() else { return }
                MainActor.assumeIsolated {
                    UIApplication.shared.endBackgroundTask(idToEnd)
                }
            }
            state.withLock { $0.identifier = identifier }
        }

        let result = await body()

        if let idToEnd = endOnce() {
            await MainActor.run {
                UIApplication.shared.endBackgroundTask(idToEnd)
            }
        }

        return result
    }

    private struct BackgroundAssertionState {
        var identifier: UIBackgroundTaskIdentifier = .invalid
        var ended = false
    }

    private static func putWithRetry(
        shareID: String,
        kind: MediaKind,
        n: Int,
        body: () throws -> Data
    ) async -> Bool {
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                let data = try body()
                let request = mediaUploadRequest(shareID: shareID, kind: kind, n: n, contentLength: data.count)
                let (_, response) = try await URLSession.shared.upload(for: request, from: data)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    return true
                }
            } catch {
                lastError = error
            }
            if attempt == 0 {
                // A single item's own attempt-plus-retry cycle can burn up to
                // ~60s of request timeouts on its own — re-check here, not
                // just once per item before this call, so a slow first
                // attempt can't blow through the remaining background grant
                // before the retry even starts.
                if await backgroundTimeExhausted() {
                    return false
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
        #if DEBUG
        print("[ShareService] media upload failed after retry: \(kind.rawValue)/\(n) — \(lastError?.localizedDescription ?? "non-2xx response")")
        #endif
        return false
    }
}

private struct SuccessResponse: Decodable {
    let url: String
    let id: String
}

private struct ErrorResponse: Decodable {
    let error: String
}
