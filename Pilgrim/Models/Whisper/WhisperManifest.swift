// Pilgrim/Models/Whisper/WhisperManifest.swift
import Foundation

struct WhisperManifest: Codable {

    let version: Int
    let whispers: [WhisperDefinition]

    static let empty = WhisperManifest(version: 0, whispers: [])

    // MARK: - Init

    init(version: Int, whispers: [WhisperDefinition]) {
        self.version = version
        self.whispers = whispers
    }

    /// Lossy decoding: individual whisper entries that fail to decode are
    /// silently dropped instead of failing the whole manifest. This lets
    /// the server evolve the schema additively (new categories, new fields)
    /// without bricking older clients — they simply don't see entries they
    /// can't understand, and keep receiving the ones they can.
    ///
    /// Without this, a single typo in any entry or the introduction of a
    /// new `WhisperCategory` on the server would cause every old client's
    /// sync to fail permanently.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        let lossy = try container.decode([LossyDecodable<WhisperDefinition>].self, forKey: .whispers)
        whispers = lossy.compactMap(\.value)
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case whispers
    }

    // MARK: - Filter predicates
    //
    // These live on the manifest (not the service) so tests exercise the
    // exact same predicate logic the service uses. WhisperManifestService
    // delegates to these; do not duplicate the filters there.

    /// All whispers in a category, including retired. Use when resolving
    /// an existing placed whisper by category.
    func whispers(in category: WhisperCategory) -> [WhisperDefinition] {
        whispers.filter { $0.category == category }
    }

    /// Non-retired whispers in a category. Use for new placement picks.
    func placeableWhispers(in category: WhisperCategory) -> [WhisperDefinition] {
        whispers.filter { $0.category == category && $0.retiredAt == nil }
    }

    /// Full lookup by ID, including retired. Used when resolving an
    /// existing placed whisper's audio from its stored whisper_id.
    func whisper(withId id: String) -> WhisperDefinition? {
        whispers.first { $0.id == id }
    }

    /// Categories with at least one placeable whisper. Used to hide
    /// empty categories from the placement sheet.
    var placeableCategories: [WhisperCategory] {
        WhisperCategory.allCases.filter { category in
            whispers.contains { $0.category == category && $0.retiredAt == nil }
        }
    }
}

// MARK: - LossyDecodable

/// Wraps a `Decodable` so that a failed decode stores `nil` instead of
/// throwing. Used with `[LossyDecodable<T>]` to survive bad elements in
/// a JSON array without dropping the whole payload.
private struct LossyDecodable<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        self.value = try? T(from: decoder)
    }
}
