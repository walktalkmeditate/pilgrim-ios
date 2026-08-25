import Foundation

/// Derived, recomputable linguistic context for one voice recording.
/// Never persisted in CoreStore, never exported, never transmitted.
struct TranscriptContext: Codable, Equatable {
    /// Bump whenever a change to HOW context is derived (extractor filters,
    /// marker rules, etc.) makes existing stored files semantically stale —
    /// not just when the Codable shape changes. `loadAll` hides anything
    /// off this version, and `TranscriptContextStore.hasCurrentContext`
    /// answers false for it, so every reader (threads/dossier/suggestions)
    /// and the backfill sweep treat a stale-derivation file as absent
    /// (see docs/solutions/derived-cache-semantics-are-schema.md).
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let recordingUUID: UUID
    let transcriptHash: String
    let languageCode: String?
    let wordCount: Int
    let themes: [Theme]
    let markers: MarkerPack?
}
