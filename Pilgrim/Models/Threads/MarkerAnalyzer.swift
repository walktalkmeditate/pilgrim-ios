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
    /// Per-surface-word modal occurrence counts (only words that occurred at
    /// least once — absent, not zero). Word identity, not just family
    /// totals, is what the dossier's modal-lean clause needs to name a
    /// specific dominant word (e.g. "'should' ×31").
    let modalCounts: [String: Int]

    init(
        wordCount: Int, absolutistCount: Int, firstPersonCount: Int, insightCount: Int,
        causationCount: Int, discrepancyCount: Int, futureCount: Int, pastCount: Int,
        sentiment: Double?, modalCounts: [String: Int]
    ) {
        self.wordCount = wordCount
        self.absolutistCount = absolutistCount
        self.firstPersonCount = firstPersonCount
        self.insightCount = insightCount
        self.causationCount = causationCount
        self.discrepancyCount = discrepancyCount
        self.futureCount = futureCount
        self.pastCount = pastCount
        self.sentiment = sentiment
        self.modalCounts = modalCounts
    }

    /// `modalCounts` decodes leniently (missing key → empty) so a
    /// schema-v2 file on disk, written before this field existed, still
    /// decodes successfully. A hard decode failure would make it invisible
    /// to `TranscriptContextStore.loadAllIncludingStaleVersions` — the
    /// backfill's stale-orphan sweep would never see it to clean it up
    /// (see docs/solutions/derived-cache-semantics-are-schema.md). The
    /// schema-version filter, not a decode error, is what marks it stale.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        wordCount = try container.decode(Int.self, forKey: .wordCount)
        absolutistCount = try container.decode(Int.self, forKey: .absolutistCount)
        firstPersonCount = try container.decode(Int.self, forKey: .firstPersonCount)
        insightCount = try container.decode(Int.self, forKey: .insightCount)
        causationCount = try container.decode(Int.self, forKey: .causationCount)
        discrepancyCount = try container.decode(Int.self, forKey: .discrepancyCount)
        futureCount = try container.decode(Int.self, forKey: .futureCount)
        pastCount = try container.decode(Int.self, forKey: .pastCount)
        sentiment = try container.decodeIfPresent(Double.self, forKey: .sentiment)
        modalCounts = try container.decodeIfPresent([String: Int].self, forKey: .modalCounts) ?? [:]
    }

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

        var modalCounts: [String: Int] = [:]
        for word in words where MarkerLexicons.modalWords.contains(word) {
            modalCounts[word, default: 0] += 1
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
            sentiment: sentimentScore(text),
            modalCounts: modalCounts
        )
    }

    /// `NLTagger`'s sentiment model degrades to a near-constant score once
    /// the tagged string passes roughly 150 words — confirmed by direct
    /// measurement (happy/sad/neutral transcripts all converge on the same
    /// value past that length), and reproduced in the field: three
    /// wildly-different recordings all reported `-0.60`. Whole-transcript
    /// `.paragraph` tagging doesn't dodge this either — spoken transcripts
    /// rarely carry paragraph breaks, so `.paragraph` covers the same long
    /// run as the raw string. Scoring each SENTENCE in isolation (a fresh
    /// `.string` assignment per sentence, short enough to stay under the
    /// degradation threshold) and averaging keeps the score genuinely
    /// content-sensitive at any transcript length.
    static func sentimentScore(_ text: String) -> Double? {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var scores: [Double] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range])
            guard !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
            tagger.string = sentence
            if let tag = tagger.tag(at: sentence.startIndex, unit: .paragraph, scheme: .sentimentScore).0,
               let value = Double(tag.rawValue) {
                scores.append(value)
            }
            return true
        }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }
}
