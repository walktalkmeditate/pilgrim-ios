import Foundation

struct PendingPlacement: Codable {

    let type: PlacementType
    let latitude: Double
    let longitude: Double
    let payload: Data
    let timestamp: Date

    enum PlacementType: String, Codable {
        case whisper
        case stone
    }
}
