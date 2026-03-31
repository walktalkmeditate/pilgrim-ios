import Foundation

struct CachedWhisper: Codable, Identifiable {

    let id: String
    let latitude: Double
    let longitude: Double
    let whisperId: String
    let category: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case latitude
        case longitude
        case whisperId = "whisper_id"
        case category
        case expiresAt = "expires_at"
    }
}
