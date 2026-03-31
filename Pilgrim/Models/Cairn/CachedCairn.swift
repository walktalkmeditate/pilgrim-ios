import Foundation

struct CachedCairn: Codable, Identifiable {

    let id: String
    let latitude: Double
    let longitude: Double
    let stoneCount: Int
    let lastPlacedAt: String

    var tier: CairnTier {
        CairnTier.from(stoneCount: stoneCount)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case latitude
        case longitude
        case stoneCount = "stone_count"
        case lastPlacedAt = "last_placed_at"
    }
}
