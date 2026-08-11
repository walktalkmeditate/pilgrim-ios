import Foundation
import UIKit

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
        request.timeoutInterval = 120
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
        progress: @escaping (MediaProgress) -> Void
    ) async -> [(kind: MediaKind, n: Int)] {
        var failures: [(kind: MediaKind, n: Int)] = []
        let total = audioFiles.count + photos.count
        var completed = 0

        func report() { progress(MediaProgress(completed: completed, total: total)) }
        report()

        // Keep the PUT chain alive through pocketing/locking: request
        // background execution for the whole sequence.
        let bgTask = await MainActor.run {
            UIApplication.shared.beginBackgroundTask(withName: "pilgrim.share.media")
        }
        defer {
            if bgTask != .invalid {
                Task { @MainActor in UIApplication.shared.endBackgroundTask(bgTask) }
            }
        }

        // Photos first: enrich's keepsake render waits (bounded) on the
        // LAST photo; audio has a graceful fallback on the page.
        for (index, data) in photos.enumerated() {
            let ok = await putWithRetry(shareID: shareID, kind: .photos, n: index + 1) { data }
            if !ok { failures.append((.photos, index + 1)) }
            completed += 1
            report()
        }

        for (index, fileURL) in audioFiles.enumerated() {
            let ok = await putWithRetry(shareID: shareID, kind: .audio, n: index + 1) {
                try Data(contentsOf: fileURL)
            }
            if !ok { failures.append((.audio, index + 1)) }
            completed += 1
            report()
        }
        return failures
    }

    /// Targeted re-upload for a previous share's failed items ("Carry the
    /// missing files"). Same ordering rules; audio resolved from URLs,
    /// photos re-exported by the caller.
    static func uploadSpecific(
        shareID: String,
        items: [(kind: MediaKind, n: Int, data: () throws -> Data)],
        progress: @escaping (MediaProgress) -> Void
    ) async -> [(kind: MediaKind, n: Int)] {
        var failures: [(kind: MediaKind, n: Int)] = []
        for (i, item) in items.enumerated() {
            let ok = await putWithRetry(shareID: shareID, kind: item.kind, n: item.n, body: item.data)
            if !ok { failures.append((item.kind, item.n)) }
            progress(MediaProgress(completed: i + 1, total: items.count))
        }
        return failures
    }

    /// Failed-media bookkeeping alongside the cached share, so a re-entry
    /// can offer repair for the share's whole life (the worker accepts
    /// PUTs until expiry).
    static func cacheFailedMedia(_ failures: [(kind: MediaKind, n: Int)], walkID: UUID) {
        let key = "share-failed-media:\(walkID.uuidString)"
        if failures.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(failures.map { "\($0.kind.rawValue):\($0.n)" }, forKey: key)
        }
    }

    static func failedMedia(for walkID: UUID) -> [(kind: MediaKind, n: Int)] {
        let key = "share-failed-media:\(walkID.uuidString)"
        guard let raw = UserDefaults.standard.stringArray(forKey: key) else { return [] }
        return raw.compactMap { entry in
            let parts = entry.split(separator: ":")
            guard parts.count == 2, let kind = MediaKind(rawValue: String(parts[0])), let n = Int(parts[1]) else { return nil }
            return (kind, n)
        }
    }

    private static func putWithRetry(
        shareID: String,
        kind: MediaKind,
        n: Int,
        body: () throws -> Data
    ) async -> Bool {
        for attempt in 0..<2 {
            do {
                let data = try body()
                let request = mediaUploadRequest(shareID: shareID, kind: kind, n: n, contentLength: data.count)
                let (_, response) = try await URLSession.shared.upload(for: request, from: data)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    return true
                }
            } catch {
                // fall through to retry
            }
            if attempt == 0 {
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
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
