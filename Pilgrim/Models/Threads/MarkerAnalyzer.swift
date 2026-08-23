import Foundation
import NaturalLanguage

struct MarkerPack: Codable, Equatable {
    let wordCount: Int
    let absolutistCount: Int
    let firstPersonCount: Int
    let insightCount: Int
    let causationCount: Int
    let discrepancyCount: Int
    let futureCount: Int
    let pastCount: Int
    let sentiment: Double?

    /// Coarse heuristic, not a tagged linguistic feature — the dossier
    /// carries this caveat wherever the lean is reported.
    var temporalLean: String {
        if futureCount >= 3, futureCount >= pastCount * 2 { return "future" }
        if pastCount >= 3, pastCount >= futureCount * 2 { return "past" }
        return "balanced"
    }
}

enum MarkerAnalyzer {

    /// English-only: every lexicon is validated for English. Other languages
    /// return nil and the pipeline degrades to themes-only (spec principle 6).
    static func compute(text: String, languageCode: String?) -> MarkerPack? {
        guard languageCode == "en" else { return nil }
        let words = TranscriptNLP.wordTokens(in: text)

        func count(in lexicon: Set<String>) -> Int {
            words.reduce(0) { $0 + (lexicon.contains($1) ? 1 : 0) }
        }

        return MarkerPack(
            wordCount: words.count,
            absolutistCount: count(in: MarkerLexicons.absolutist),
            firstPersonCount: count(in: MarkerLexicons.firstPersonSingular),
            insightCount: count(in: MarkerLexicons.insight),
            causationCount: count(in: MarkerLexicons.causation),
            discrepancyCount: count(in: MarkerLexicons.discrepancy),
            futureCount: count(in: MarkerLexicons.futureMarkers),
            pastCount: count(in: MarkerLexicons.pastMarkers),
            sentiment: sentimentScore(text)
        )
    }

    static func sentimentScore(_ text: String) -> Double? {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        return tag.flatMap { Double($0.rawValue) }
    }
}
