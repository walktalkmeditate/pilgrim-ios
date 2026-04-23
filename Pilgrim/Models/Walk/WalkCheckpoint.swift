import Foundation

struct WalkCheckpoint: Codable {
    /// Shape of the on-disk checkpoint JSON. Bumped whenever `TempWalk` gains or
    /// loses fields in a way that older builds can't round-trip; `WalkSessionGuard`
    /// rejects any checkpoint whose `schemaVersion` doesn't match this constant.
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let walkUUID: UUID
    let checkpointDate: Date
    let walk: TempWalk

    init(walkUUID: UUID, walk: TempWalk) {
        self.schemaVersion = Self.currentSchemaVersion
        self.walkUUID = walkUUID
        self.checkpointDate = Date()
        self.walk = walk
    }
}
