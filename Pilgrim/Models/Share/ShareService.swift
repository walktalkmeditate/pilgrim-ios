import Foundation
import Security

enum ShareService {

    private static let baseURL = "https://walk.pilgrimapp.org"
    private static let keychainKey = "pilgrim.share.device-token"

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
        if let existing = readKeychainToken() {
            return existing
        }
        let token = UUID().uuidString
        saveKeychainToken(token)
        return token
    }

    private static func readKeychainToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func saveKeychainToken(_ token: String) {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private static let isoFormatter = ISO8601DateFormatter()

    static func cachedShare(for walkID: UUID) -> ShareResult? {
        guard let dict = UserDefaults.standard.dictionary(forKey: "share:\(walkID.uuidString)"),
              let url = dict["url"] as? String,
              let id = dict["id"] as? String,
              let expiryStr = dict["expiry"] as? String,
              let expiry = isoFormatter.date(from: expiryStr),
              expiry > Date() else {
            return nil
        }
        return ShareResult(url: url, id: id)
    }

    static func cacheShare(_ result: ShareResult, walkID: UUID, expiryDays: Int) {
        let expiry = Calendar.current.date(byAdding: .day, value: expiryDays, to: Date()) ?? Date()
        let dict: [String: String] = [
            "url": result.url,
            "id": result.id,
            "expiry": isoFormatter.string(from: expiry)
        ]
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
