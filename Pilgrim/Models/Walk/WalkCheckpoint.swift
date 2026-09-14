import Foundation

struct WalkCheckpoint: Codable {
    /// Shape of the on-disk checkpoint JSON. Bumped whenever `TempWalk` gains or
    /// loses fields in a way that older builds can't round-trip; `WalkSessionGuard`
    /// recovers any version from `minimumRecoverableSchemaVersion` through this one.
    static let currentSchemaVersion = 2

    /// Version 1 carried no Way identity. Everything it did carry decodes
    /// unchanged into this shape — the honor fields simply arrive nil — so a
    /// walk crashed under the previous build still recovers, as a plain walk.
    static let minimumRecoverableSchemaVersion = 1

    let schemaVersion: Int
    let walkUUID: UUID
    let checkpointDate: Date
    let walk: TempWalk
    /// The Way this walk is honoring, so a crash-recovered walk can be bound
    /// back to it. Nil for every walk that isn't an honor walk.
    let wayId: String?
    /// The engine's last word before the crash. The engine dies with the
    /// process, so a recovered stage walk has no other source for its ledger
    /// entry.
    let honorProgressFrac: Double?
    let honorArrived: Bool?

    /// Both halves are written together from the same engine read, so either
    /// one missing means no stage was joined and no ledger entry was earned.
    var honorOutcome: HonorStageOutcome? {
        guard let honorProgressFrac, let honorArrived else { return nil }
        return HonorStageOutcome(progressFrac: honorProgressFrac, arrived: honorArrived)
    }

    init(
        walkUUID: UUID,
        walk: TempWalk,
        wayId: String? = nil,
        honorProgressFrac: Double? = nil,
        honorArrived: Bool? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.walkUUID = walkUUID
        self.checkpointDate = Date()
        self.walk = walk
        self.wayId = wayId
        self.honorProgressFrac = honorProgressFrac
        self.honorArrived = honorArrived
    }
}
