import Foundation

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

private struct SuccessResponse: Decodable {
    let url: String
    let id: String
}

private struct ErrorResponse: Decodable {
    let error: String
}
