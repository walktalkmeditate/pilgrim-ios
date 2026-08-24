import Foundation

/// State-only texture: pace derived mechanically from words-per-minute,
/// insight from exact lexicon words the walker can be shown. No directional
/// language, no numbers — weak signals are omitted, and the whole line is
/// omitted when nothing clears threshold (spec: Stage 3 card).
enum ThreadsTexture {

    /// Mirrors ContextFormatter.speakingPaceLabel's outer buckets: only the
    /// extremes are remarkable enough to name.
    static let slowCeiling: Double = 100
    static let quickFloor: Double = 170
    static let insightFloor = 2

    /// Insight-word surfaces in spoken order, deduplicated — the exact words
    /// that earn "with words of insight", revealed on tap (traceability:
    /// if we can't show the words, we don't show the claim).
    static func insightWords(in transcripts: [String]) -> [String] {
        var seen: Set<String> = []
        return transcripts
            .flatMap { TranscriptNLP.wordTokens(in: $0) }
            .filter { MarkerLexicons.insight.contains($0) }
            .filter { seen.insert($0).inserted }
    }

    static func paceClause(meanWordsPerMinute: Double?) -> String? {
        guard let wpm = meanWordsPerMinute else { return nil }
        if wpm < slowCeiling { return "spoken slowly" }
        if wpm >= quickFloor { return "spoken quickly" }
        return nil
    }

    static func line(meanWordsPerMinute: Double?, hasInsight: Bool) -> String? {
        var clauses: [String] = []
        if let pace = paceClause(meanWordsPerMinute: meanWordsPerMinute) {
            clauses.append(pace)
        }
        if hasInsight {
            clauses.append("with words of insight")
        }
        guard let first = clauses.first else { return nil }
        let capitalized = first.prefix(1).capitalized + String(first.dropFirst())
        return ([capitalized] + clauses.dropFirst()).joined(separator: ", ") + "."
    }
}
