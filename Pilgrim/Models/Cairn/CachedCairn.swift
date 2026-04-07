import Foundation

struct CachedCairn: Codable, Identifiable {

    let id: String
    let latitude: Double
    let longitude: Double
    let stoneCount: Int
    let lastPlacedAt: String
    let createdAt: String

    var tier: CairnTier {
        CairnTier.from(stoneCount: stoneCount)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case latitude
        case longitude
        case stoneCount = "stone_count"
        case lastPlacedAt = "last_placed_at"
        case createdAt = "created_at"
    }

    init(id: String, latitude: Double, longitude: Double, stoneCount: Int, lastPlacedAt: String, createdAt: String? = nil) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.stoneCount = stoneCount
        self.lastPlacedAt = lastPlacedAt
        self.createdAt = createdAt ?? lastPlacedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        stoneCount = try container.decode(Int.self, forKey: .stoneCount)
        lastPlacedAt = try container.decode(String.self, forKey: .lastPlacedAt)
        createdAt = (try? container.decode(String.self, forKey: .createdAt)) ?? lastPlacedAt
    }
}
