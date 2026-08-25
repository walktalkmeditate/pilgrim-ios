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
    ///
    /// v3: `MarkerPack.modalCounts` (per-surface-word modal-verb counts,
    /// feeding the dossier's modal-lean clause). A v2 file still decodes —
    /// `MarkerPack` decodes `modalCounts` leniently (missing → empty) so the
    /// stale-orphan sweep can still see it — but it carries no modal data,
    /// which would silently starve the modal-lean baseline of history; the
    /// bump forces those recordings to re-analyze.
    ///
    /// v4 (ship gate, 2026-08-25): `SpokenStoplist.lightNouns` gained `day`,
    /// `days`, `area` — a v3 file's stored themes may still carry one of
    /// those as a generic noun rather than topical content, so the bump
    /// forces re-analysis under `ThemeExtractor`'s tightened stoplist.
    static let currentSchemaVersion = 4

    let schemaVersion: Int
    let recordingUUID: UUID
    let transcriptHash: String
    let languageCode: String?
    let wordCount: Int
    let themes: [Theme]
    let markers: MarkerPack?
}
