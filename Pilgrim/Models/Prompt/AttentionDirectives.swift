import Foundation

/// Deterministic pattern detection over a walk's context. The assembler
/// hands the downstream model a dossier; these directives tell it what is
/// remarkable about *this* walk — the difference between handing someone
/// documents and handing them documents plus "compare page 3 to page 9".
enum AttentionDirectives {

    private static let movingThreshold = 0.3
    private static let maxDirectives = 4

    static func detect(context: ActivityContext) -> [String] {
        let directives = [
            stillness(context),
            paceShift(context),
            intentionEcho(context),
            recurringWord(context),
            firstVersusLast(context)
        ].compactMap { $0 }
        return Array(directives.prefix(maxDirectives))
    }

    // MARK: - Detectors

    /// A sustained still stretch that neither a logged meditation nor a
    /// recorded pause accounts for — otherwise the directive would re-brand
    /// the walk's own Pauses line as mystery. Sample spacing is unknown
    /// here, so minutes are estimated from the run's share of all samples —
    /// imprecise, honest enough to point at. Negative speeds are invalid
    /// GPS fixes, not stillness.
    private static func stillness(_ context: ActivityContext) -> String? {
        let speeds = context.routeSpeeds
        guard speeds.count >= 30, context.duration > 0 else { return nil }

        var longestRun = 0
        var currentRun = 0
        for speed in speeds {
            currentRun = (0..<movingThreshold).contains(speed) ? currentRun + 1 : 0
            longestRun = max(longestRun, currentRun)
        }

        let estimatedMinutes = context.duration * (Double(longestRun) / Double(speeds.count)) / 60
        let explainedMinutes = (context.meditations.reduce(0) { $0 + $1.duration }
            + context.pauses.reduce(0) { $0 + $1.duration }) / 60
        guard estimatedMinutes >= 3, estimatedMinutes > explainedMinutes else { return nil }

        return "The route shows about \(Int(estimatedMinutes.rounded())) minutes of stillness in one place — ask what held the walker there."
    }

    /// Average moving speed of the final third against the first third.
    private static func paceShift(_ context: ActivityContext) -> String? {
        let moving = context.routeSpeeds.filter { $0 >= movingThreshold }
        guard moving.count >= 30 else { return nil }

        let third = moving.count / 3
        let first = moving.prefix(third).reduce(0, +) / Double(third)
        let last = moving.suffix(third).reduce(0, +) / Double(third)
        guard first > 0 else { return nil }

        let change = (last - first) / first
        guard abs(change) >= 0.2 else { return nil }

        let percent = Int((abs(change) * 100).rounded())
        return change < 0
            ? "The walker's pace slowed by \(percent)% in the final third — something slowed them; notice what."
            : "The walker's pace quickened by \(percent)% in the final third — something carried them; notice what."
    }

    /// A word from the stated intention resurfacing in the walker's own
    /// spoken words.
    private static func intentionEcho(_ context: ActivityContext) -> String? {
        guard let intention = context.intention, context.hasSpeech else { return nil }
        let spoken = contentWords(in: context.recordings.map(\.text).joined(separator: " "))
        guard let echoed = contentWords(in: intention).first(where: { spoken.contains($0) }) else {
            return nil
        }
        return "The walker's intention spoke of '\(echoed)', and '\(echoed)' surfaces again in their spoken words — trace how it traveled."
    }

    /// The most-repeated content word across all recordings, excluding any
    /// word the intention-echo directive already claimed.
    private static func recurringWord(_ context: ActivityContext) -> String? {
        guard context.hasSpeech else { return nil }
        let intentionWords = context.intention.map { Set(contentWords(in: $0)) } ?? []

        var counts: [String: Int] = [:]
        for word in contentWords(in: context.recordings.map(\.text).joined(separator: " ")) where !intentionWords.contains(word) {
            counts[word, default: 0] += 1
        }

        guard let (word, count) = counts.filter({ $0.value >= 3 })
            .min(by: { ($0.value, $1.key) > ($1.value, $0.key) }) else { return nil }

        return "The word '\(word)' returns \(count) times across the recordings — it may be doing quiet work."
    }

    private static func firstVersusLast(_ context: ActivityContext) -> String? {
        guard context.recordings.count >= 2 else { return nil }
        return "Compare the first recording with the last — measure what changed in the walker between them."
    }

    // MARK: - Words

    private static let stopwords: Set<String> = [
        "the", "and", "that", "this", "with", "from", "have", "what", "your",
        "them", "they", "been", "were", "will", "would", "could", "should",
        "about", "into", "just", "like", "know", "then", "there", "when",
        "where", "which", "while", "because", "again", "back", "keep",
        "still", "very", "really", "today", "cannot", "something"
    ]

    private static func contentWords(in text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count > 3 && !stopwords.contains($0) }
    }
}
