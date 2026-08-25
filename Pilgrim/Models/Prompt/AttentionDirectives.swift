import Foundation

/// Deterministic pattern detection over a walk's context. The assembler
/// hands the downstream model a dossier; these directives tell it what is
/// remarkable about *this* walk — the difference between handing someone
/// documents and handing them documents plus "compare page 3 to page 9".
enum AttentionDirectives {

    private static let movingThreshold = 0.3
    private static let maxDirectives = 4

    /// `detectedLanguageCode` defaults to nil ("detect here") so direct
    /// callers stay unchanged; PromptGenerator.resolvedDerivations passes
    /// its precomputed code so the echo skips its own detection pass.
    static func detect(
        context: ActivityContext,
        detectedLanguageCode: String? = nil
    ) -> [String] {
        // Lemmatizing the full transcript is the expensive step; do it once
        // here and share it between the two detectors that need it.
        let spokenMentions = context.hasSpeech
            ? TranscriptNLP.contentLemmaMentions(in: context.recordings.map(\.text).joined(separator: " "))
            : []
        let directives = [
            stillness(context),
            paceShift(context),
            intentionEcho(context, spokenMentions: spokenMentions, detectedLanguageCode: detectedLanguageCode),
            recurringWord(context, spokenMentions: spokenMentions),
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
    /// spoken words — by exact surface first (searched across ALL spoken
    /// mentions, so "worrying ... worry" still earns "again"), by shared
    /// lemma second, by embedding nearness third. "Again" is only honest
    /// when the walker repeated the exact surface; an inflection
    /// ("worrying" for "worry") quotes what was actually said.
    private static func intentionEcho(
        _ context: ActivityContext,
        spokenMentions spoken: [TranscriptNLP.LemmaMention],
        detectedLanguageCode: String?
    ) -> String? {
        guard let intention = context.intention, context.hasSpeech else { return nil }
        guard !spoken.isEmpty else { return nil }
        let spokenText = context.recordings.map(\.text).joined(separator: " ")
        let language = detectedLanguageCode ?? TranscriptNLP.detectLanguage(spokenText) ?? "en"

        for word in TranscriptNLP.contentLemmaMentions(in: intention) {
            if spoken.contains(where: { $0.lemma == word.lemma && $0.surface == word.surface }) {
                return "The walker's intention spoke of '\(word.surface)', and '\(word.surface)' surfaces again in their spoken words — trace how it traveled."
            }
            if let match = spoken.first(where: { $0.lemma == word.lemma }) {
                return "The walker's intention spoke of '\(word.surface)', and '\(match.surface)' surfaces in their spoken words — trace how it traveled."
            }
            if let match = spoken.first(where: { TranscriptNLP.related(word.lemma, $0.lemma, languageCode: language) }) {
                return "The walker's intention spoke of '\(word.surface)', and '\(match.surface)' surfaces in their spoken words — trace how it traveled."
            }
        }
        return nil
    }

    /// The most-repeated content lemma across all recordings, excluding any
    /// lemma the intention already claimed and any spoken-scaffolding lemma
    /// (`SpokenStoplist.scaffoldLemmas` — light verbs like "think" that
    /// dominate raw-frequency counts without carrying meaning) — the
    /// next-ranked candidate is promoted, so excluding a lemma never
    /// silences the directive, only redirects it. Shown as its most
    /// frequent surface form so the walker's own inflection is echoed back.
    private static func recurringWord(
        _ context: ActivityContext,
        spokenMentions mentions: [TranscriptNLP.LemmaMention]
    ) -> String? {
        guard context.hasSpeech else { return nil }
        let intentionLemmas = context.intention
            .map { Set(TranscriptNLP.contentLemmas(in: $0)) } ?? []

        var counts: [String: Int] = [:]
        var surfaces: [String: [String: Int]] = [:]
        for mention in mentions
        where !intentionLemmas.contains(mention.lemma)
            && !SpokenStoplist.scaffoldLemmas.contains(mention.lemma) {
            counts[mention.lemma, default: 0] += 1
            surfaces[mention.lemma, default: [:]][mention.surface, default: 0] += 1
        }

        guard let (lemma, count) = counts.filter({ $0.value >= 3 })
            .min(by: { ($0.value, $1.key) > ($1.value, $0.key) }) else { return nil }
        let display = surfaces[lemma]?
            .min(by: { ($0.value, $1.key) > ($1.value, $0.key) })?.key ?? lemma

        return "The word '\(display)' returns \(count) times across the recordings — it may be doing quiet work."
    }

    private static func firstVersusLast(_ context: ActivityContext) -> String? {
        guard context.recordings.count >= 2 else { return nil }
        return "Compare the first recording with the last — measure what changed in the walker between them."
    }
}
