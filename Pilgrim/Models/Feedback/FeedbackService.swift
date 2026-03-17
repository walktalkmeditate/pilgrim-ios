import Foundation
import UIKit

enum FeedbackService {

    private static let baseURL = "https://walk.pilgrimapp.org"

    enum FeedbackError: LocalizedError {
        case networkError(String)
        case rateLimited
        case serverError(Int)

        var errorDescription: String? {
            switch self {
            case .networkError(let msg): return msg
            case .rateLimited: return "Too many submissions today."
            case .serverError(let code): return "Server error (\(code))"
            }
        }
    }

    static func submit(
        category: String,
        message: String,
        includeDeviceInfo: Bool
    ) async throws {
        let url = URL(string: "\(baseURL)/api/feedback")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ShareService.deviceTokenForFeedback(), forHTTPHeaderField: "X-Device-Token")
        request.timeoutInterval = 15

        var body: [String: String] = [
            "category": category,
            "message": message
        ]
        if includeDeviceInfo {
            body["deviceInfo"] = deviceInfoString()
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw FeedbackError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw FeedbackError.networkError("Invalid response")
        }

        if http.statusCode == 429 {
            throw FeedbackError.rateLimited
        }

        guard (200...299).contains(http.statusCode) else {
            throw FeedbackError.serverError(http.statusCode)
        }
    }

    private static func deviceInfoString() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "iOS \(UIDevice.current.systemVersion) · \(UIDevice.current.model) · v\(version)"
    }
}
