import Foundation
import NaturalLanguage

struct ThemeMention: Codable, Equatable {
    let start: Int
    let length: Int
}

struct Theme: Codable, Equatable {
    let lemma: String
    let displayTerm: String
    let mentionCount: Int
    let salience: Double
    let mentions: [ThemeMention]
}

enum ThemeExtractor {

    static let minimumWords = 25
    static let maxThemes = 6
    static let minimumMentions = 2

    /// The activity's own narration vocabulary — without suppression every
    /// walk's dominant thread would be the walk itself.
    static let walkingDomain: Set<String> = [
        "walk", "walking", "path", "trail", "hill", "uphill", "downhill",
        "road", "street", "step", "steps", "route", "mile", "kilometer",
        "minute", "left", "right"
    ]

    static func themes(in text: String, languageCode: String?) -> [Theme] {
        let wordCount = TranscriptNLP.wordCount(in: text)
        guard wordCount >= minimumWords else { return [] }

        // Thread identity is exact-lemma in v1. Per-transcript synonym
        // merging split cross-walk identity — a lemma folded into a
        // neighbor in one walk read "first time" in the next, a false
        // origin claim. Embedding clustering is re-evaluated at the field
        // gate with a cross-walk-consistent design; languageCode is
        // reserved for that. (`related()` still serves intention echo.)
        let groups = Dictionary(grouping: mentions(in: text), by: \.lemma)

        return groups
            .filter { $0.value.count >= minimumMentions }
            .map { lemma, group -> Theme in
                let surfaceCounts = Dictionary(grouping: group, by: \.surface)
                    .mapValues(\.count)
                let display = surfaceCounts
                    .min { ($0.value, $1.key) > ($1.value, $0.key) }!.key
                return Theme(
                    lemma: lemma,
                    displayTerm: display,
                    mentionCount: group.count,
                    salience: Double(group.count) / Double(wordCount),
                    mentions: group.map { ThemeMention(start: $0.start, length: $0.length) }
                )
            }
            .sorted { ($0.salience, $1.lemma) > ($1.salience, $0.lemma) }
            .prefix(maxThemes)
            .map { $0 }
    }

    /// Nouns only — verbs and adjectives dominated raw-frequency ranking
    /// with spoken scaffolding ("was", "have", "can", "think") on real
    /// devices, never the topical content underneath it. The noun class is
    /// necessary but not sufficient: NLTagger also calls 'yeah' a noun, so
    /// `SpokenStoplist.filler` carries what lexical class cannot.
    ///
    /// Deliberately not `SpokenStoplist.nonContentLemmas`, which the live
    /// prompt-time consumers share: that union also carries
    /// `scaffoldLemmas`, whose light verbs ("will", "feel", "need") NLTagger
    /// does sometimes call nouns — adding it would change which lemmas this
    /// extractor discards. Themes are persisted and pinned to
    /// `TranscriptContext.currentSchemaVersion`, so that is a schema change
    /// requiring a version bump and a re-analysis sweep on every device
    /// (`docs/solutions/derived-cache-semantics-are-schema.md`).
    private static func mentions(in text: String) -> [TranscriptNLP.LemmaMention] {
        TranscriptNLP.contentLemmaMentions(in: text, classes: [.noun])
            .filter {
                !walkingDomain.contains($0.lemma)
                    && !SpokenStoplist.lightNouns.contains($0.lemma)
                    && !SpokenStoplist.filler.contains($0.lemma)
            }
    }
}
