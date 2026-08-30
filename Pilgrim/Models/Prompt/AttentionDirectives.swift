import Foundation
import NaturalLanguage

/// Deterministic pattern detection over a walk's context. The assembler
/// hands the downstream model a dossier; these directives tell it what is
/// remarkable about *this* walk — the difference between handing someone
/// documents and handing them documents plus "compare page 3 to page 9".
enum AttentionDirectives {

    private static let movingThreshold = 0.3
    private static let maxDirectives = 4
    private static let paceShiftThreshold = 0.15
    /// `wordsPerMinute` over a handful of words is noise, not a speaking
    /// rate: a five-word note clears a 15% relative delta on the rounding of
    /// its own start and end timestamps. At any plausible speaking rate this
    /// floor means at least ten seconds of continuous speech on each side —
    /// the pace branch's answer to the subject branch's lemma floor.
    private static let minimumWordsToJudgePace = 25
    private static let subjectOverlapCeiling = 0.20
    /// Content lemmas, after `SpokenStoplist.scaffoldLemmas` is removed. The
    /// original floor of 5 sat far below where a lexical-overlap judgment
    /// carries any information: a sign-off ("heading back down the hill,
    /// tired but glad") clears 5 comfortably and shares nothing with a long
    /// opening, so the overlap coefficient reads zero and the directive fires
    /// on a walk that never changed subject. A genuinely divergent long pair
    /// measures around 0.06, so there is ample headroom above this floor.
    private static let minimumLemmasToJudgeSubject = 12
    /// Two recordings are only comparable as subjects when both carry
    /// comparable amounts of it. Past this ratio the smaller recording is a
    /// thin sample of the walk rather than its second half, and its overlap
    /// against a much longer transcript says more about its length than about
    /// what the walker was talking about.
    private static let subjectLengthRatioCeiling = 3.0

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
    /// lemma the intention already claimed and any lemma that carries no
    /// content (`SpokenStoplist.nonContentLemmas` — light verbs like "think"
    /// that dominate raw-frequency counts without carrying meaning, plus the
    /// filler and light nouns the theme layer discards; 'okay' is exactly
    /// the word a speaker repeats most, and NLTagger calls it a noun in
    /// Whisper's lowercase sentence runs) — the next-ranked candidate is
    /// promoted, so excluding a lemma never silences the directive, only
    /// redirects it. Shown as its most frequent surface form so the walker's
    /// own inflection is echoed back.
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
            && !SpokenStoplist.nonContentLemmas.contains(mention.lemma) {
            counts[mention.lemma, default: 0] += 1
            surfaces[mention.lemma, default: [:]][mention.surface, default: 0] += 1
        }

        guard let (lemma, count) = counts.filter({ $0.value >= 3 })
            .min(by: { ($0.value, $1.key) > ($1.value, $0.key) }) else { return nil }
        let display = surfaces[lemma]?
            .min(by: { ($0.value, $1.key) > ($1.value, $0.key) })?.key ?? lemma

        return "The word '\(display)' returns \(count) times across the recordings — it may be doing quiet work."
    }

    /// Fires only when something measurably moved between the first
    /// recording and the last. The previous version fired on every walk
    /// with two recordings and presupposed its own conclusion — told to
    /// measure what changed, the model finds change, including on walks
    /// where nothing did (the `questionDensity` failure mode, quieter).
    ///
    /// Marker and sentiment deltas are deliberately NOT used: they are
    /// unreachable from `ActivityContext`, and computing them here would
    /// mean a fresh analyzer pass per recording. Pace is free
    /// (`wordsPerMinute` is already populated); subject costs exactly two
    /// lemma passes, never N.
    ///
    /// Both branches fail closed. Each carries a floor sized so the signal
    /// it reads is measurable at all — words for a speaking rate, content
    /// lemmas for a subject — and the subject branch additionally refuses
    /// languages this OS cannot lemmatize. Silence hands the `maxDirectives`
    /// budget to a detector with something to say.
    private static func firstVersusLast(_ context: ActivityContext) -> String? {
        guard let first = context.recordings.first,
              let last = context.recordings.last,
              context.recordings.count >= 2 else { return nil }

        if let paceLine = speakingRateShift(first: first, last: last) { return paceLine }
        return subjectShift(first: first, last: last)
    }

    /// Speaking rate, not ground speed — `paceShift` above reads GPS.
    private static func speakingRateShift(first: RecordingContext, last: RecordingContext) -> String? {
        guard let firstPace = first.wordsPerMinute, let lastPace = last.wordsPerMinute, firstPace > 0,
              TranscriptNLP.wordCount(in: first.text) >= minimumWordsToJudgePace,
              TranscriptNLP.wordCount(in: last.text) >= minimumWordsToJudgePace else { return nil }

        let change = (lastPace - firstPace) / firstPace
        if change >= paceShiftThreshold {
            return "The walker spoke faster by the last recording than the first — attend to what moved between them."
        }
        if change <= -paceShiftThreshold {
            return "The walker spoke more slowly by the last recording than the first — attend to what moved between them."
        }
        return nil
    }

    /// Whether the walker's vocabulary moved between the two recordings.
    ///
    /// Both sides must be lemmatized by the SAME language model. Without a
    /// lemma model `TranscriptNLP.contentLemmas` falls back to the lowercased
    /// surface form, so an inflected language yields a distinct "lemma" per
    /// inflection and depresses overlap systematically — every Camino walk in
    /// Spanish, French, German, Italian, or Portuguese would read as total
    /// divergence. A walker who switches languages mid-walk has not changed
    /// subject either; the two sets are simply not comparable.
    private static func subjectShift(first: RecordingContext, last: RecordingContext) -> String? {
        guard let firstLanguage = lemmatizableLanguage(of: first.text),
              let lastLanguage = lemmatizableLanguage(of: last.text),
              firstLanguage == lastLanguage else { return nil }

        let firstLemmas = subjectLemmas(in: first.text)
        let lastLemmas = subjectLemmas(in: last.text)
        let smallerCount = min(firstLemmas.count, lastLemmas.count)
        let largerCount = max(firstLemmas.count, lastLemmas.count)
        guard smallerCount >= minimumLemmasToJudgeSubject,
              Double(largerCount) / Double(smallerCount) <= subjectLengthRatioCeiling else { return nil }

        // Overlap coefficient (intersection / smaller set), not Jaccard
        // (intersection / union). Jaccard collapses to |smaller| / |larger|
        // whenever one lemma set is a subset of the other — a long opening
        // reflection (~30+ unique lemmas) followed by a short closing note
        // on the SAME subject (all repeats) can then cross the ceiling on
        // length alone, firing "shares little vocabulary" on a walk that
        // never left its subject. The overlap coefficient is 1.0 for that
        // same subset case (correctly silent) and still near 0 for genuinely
        // divergent subjects, because it measures how much of the SMALLER
        // recording is accounted for by the larger one rather than
        // penalizing a short recording for being short.
        let overlap = Double(firstLemmas.intersection(lastLemmas).count) / Double(smallerCount)
        guard overlap <= subjectOverlapCeiling else { return nil }

        return "The walker's last recording shares little vocabulary with the first — attend to what moved between them."
    }

    /// The same `SpokenStoplist.nonContentLemmas` filter `recurringWord`
    /// applies: NLTagger tags "think", "know", "want", "keep" as content, but
    /// a speaker reaches for them out of habit — and so are 'okay', 'yeah',
    /// 'people', 'area' and 'app'. Left in, a closing recording made entirely
    /// of scaffolding and filler clears the lemma floor on words that carry
    /// no subject at all, and pads the overlap coefficient's denominator with
    /// them.
    ///
    /// This raises the bar `minimumLemmasToJudgeSubject` represents: twelve
    /// REAL content lemmas, not twelve tokens NLTagger happened to call
    /// content. The floor is deliberately not lowered to compensate — the
    /// branch failing closed on a thin closing note is the behaviour the
    /// floor was introduced for.
    private static func subjectLemmas(in text: String) -> Set<String> {
        Set(TranscriptNLP.contentLemmas(in: text)).subtracting(SpokenStoplist.nonContentLemmas)
    }

    /// The transcript's language when this OS actually ships a lemma model
    /// for it, nil otherwise — including when no language clears the
    /// recognizer's confidence bar. Asked of the OS rather than hardcoded, so
    /// the subject branch widens on its own as Apple adds lemma models.
    static func lemmatizableLanguage(of text: String) -> String? {
        guard let code = TranscriptNLP.detectLanguage(text) else { return nil }
        return NLTagger.availableTagSchemes(for: .word, language: NLLanguage(rawValue: code))
            .contains(.lemma) ? code : nil
    }
}
