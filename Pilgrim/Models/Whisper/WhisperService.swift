import Foundation

enum WhisperService {

    private static let baseURL = "https://walk.pilgrimapp.org/api/whispers"

    enum WhisperError: LocalizedError {
        case encodingFailed
        case networkError(String)
        case serverError(Int, String)
        case rateLimited

        var errorDescription: String? {
            switch self {
            case .encodingFailed: return "Failed to prepare whisper data."
            case .networkError(let msg): return "Network error: \(msg)"
            case .serverError(let code, let msg): return "Server error (\(code)): \(msg)"
            case .rateLimited: return "Too many whispers placed today."
            }
        }
    }

    struct PlaceResult {
        let id: String
    }

    static func placeWhisper(
        latitude: Double,
        longitude: Double,
        whisperId: String,
        category: String,
        expiryOption: String
    ) async throws -> PlaceResult {
        guard let url = URL(string: baseURL) else { throw WhisperError.encodingFailed }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ShareService.deviceTokenForFeedback(), forHTTPHeaderField: "X-Device-Token")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "latitude": latitude,
            "longitude": longitude,
            "whisper_id": whisperId,
            "category": category,
            "expiry_option": expiryOption,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw WhisperError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw WhisperError.networkError("Invalid response")
        }

        if http.statusCode == 429 { throw WhisperError.rateLimited }

        guard (200...299).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "Unknown error"
            throw WhisperError.serverError(http.statusCode, msg)
        }

        let result = try JSONDecoder().decode(IDResponse.self, from: data)
        return PlaceResult(id: result.id)
    }

}

private struct IDResponse: Decodable {
    let id: String
}

private struct ErrorBody: Decodable {
    let error: String
}
