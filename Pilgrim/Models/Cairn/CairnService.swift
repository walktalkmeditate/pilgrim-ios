import Foundation

enum CairnService {

    private static let baseURL = "https://walk.pilgrimapp.org/api/cairns"

    enum CairnError: LocalizedError {
        case networkError(String)
        case serverError(Int, String)

        var errorDescription: String? {
            switch self {
            case .networkError(let msg): return "Network error: \(msg)"
            case .serverError(let code, let msg): return "Server error (\(code)): \(msg)"
            }
        }
    }

    struct PlaceResult {
        let id: String
        let stoneCount: Int
    }

    static func placeStone(latitude: Double, longitude: Double) async throws -> PlaceResult {
        guard let url = URL(string: baseURL) else { throw CairnError.networkError("Invalid URL") }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ShareService.deviceTokenForFeedback(), forHTTPHeaderField: "X-Device-Token")
        request.timeoutInterval = 15

        let body: [String: Double] = ["latitude": latitude, "longitude": longitude]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CairnError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw CairnError.networkError("Invalid response")
        }

        guard (200...299).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "Unknown error"
            throw CairnError.serverError(http.statusCode, msg)
        }

        let result = try JSONDecoder().decode(PlaceResponse.self, from: data)
        return PlaceResult(id: result.id, stoneCount: result.stoneCount)
    }

    static func makeOfflinePayload() -> Data {
        Data("{}".utf8)
    }
}

private struct PlaceResponse: Decodable {
    let id: String
    let stoneCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case stoneCount = "stone_count"
    }
}

private struct ErrorBody: Decodable {
    let error: String
}
