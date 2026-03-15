import Foundation

struct WalkCheckpoint: Codable {
    let schemaVersion: Int
    let walkUUID: UUID
    let checkpointDate: Date
    let walk: TempWalk

    init(walkUUID: UUID, walk: TempWalk) {
        self.schemaVersion = 1
        self.walkUUID = walkUUID
        self.checkpointDate = Date()
        self.walk = walk
    }
}
