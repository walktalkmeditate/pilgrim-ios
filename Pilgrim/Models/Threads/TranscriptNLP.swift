import Foundation
import NaturalLanguage

/// On-device linguistic primitives shared by attention directives and the
/// transcript analyzer. Deterministic per OS release; nothing leaves the
/// device.
enum TranscriptNLP {

    static let relatedDistanceCeiling = 0.95

    struct LemmaMention: Equatable {
        let lemma: String
        let surface: String
        let start: Int
        let length: Int
    }

    static func detectLanguage(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage,
              let confidence = recognizer.languageHypotheses(withMaximum: 1)[language],
              confidence >= 0.5 else { return nil }
        return language.rawValue
    }

    /// `classes` defaults to the full content set so intention echo and
    /// insight words — which need verbs like "worrying" and "grieving" to
    /// stay untouched — see no behavior change. ThemeExtractor passes
    /// `[.noun]` alone: raw-frequency ranking over verbs let spoken
    /// scaffolding ("was", "have", "can", "think") win every theme.
    static func contentLemmaMentions(
        in text: String,
        classes: Set<NLTag> = [.noun, .verb, .adjective]
    ) -> [LemmaMention] {
        let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
        tagger.string = text
        var mentions: [LemmaMention] = []
        // Running cursor: enumerateTags visits ranges in order, so advancing
        // the character offset from the previous mention keeps this linear
        // instead of re-measuring from startIndex per mention (quadratic on
        // long transcripts).
        var lastIndex = text.startIndex
        var lastOffset = 0
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitPunctuation, .omitWhitespace, .omitOther]
        ) { tag, range in
            guard let tag, classes.contains(tag) else { return true }
            let surface = String(text[range]).lowercased()
            guard surface.count > 2 else { return true }
            let lemma = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma)
                .0?.rawValue.lowercased() ?? surface
            lastOffset += text.distance(from: lastIndex, to: range.lowerBound)
            lastIndex = range.lowerBound
            mentions.append(LemmaMention(
                lemma: lemma,
                surface: surface,
                start: lastOffset,
                length: text.distance(from: range.lowerBound, to: range.upperBound)
            ))
            return true
        }
        return mentions
    }

    static func contentLemmas(in text: String) -> [String] {
        contentLemmaMentions(in: text).map(\.lemma)
    }

    /// The single tokenizer for every word count and density in the feature
    /// — a second implementation means diverging denominators.
    static func wordTokens(in text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
    }

    static func wordCount(in text: String) -> Int {
        wordTokens(in: text).count
    }

    struct WordToken: Equatable {
        let token: String
        let start: Int
    }

    /// Offsets for `wordTokens`' own output — not a second tokenizer. A
    /// separate letters-only scan (even a careful one) can still diverge from
    /// `components(separatedBy:)` on a grapheme that mixes scalar classes
    /// (a base letter plus a combining mark): the two would draw the split
    /// in different places. Sourcing the token list directly from
    /// `wordTokens` and locating each one by forward search makes the token
    /// TEXT identical by construction — there is exactly one tokenizer, and
    /// this just remembers where its output came from (the offsets
    /// `contentLemmaMentions` also measures in: `String.distance`, Character
    /// count).
    static func wordTokenOffsets(in text: String) -> [WordToken] {
        let lowered = text.lowercased()
        var tokens: [WordToken] = []
        var cursor = lowered.startIndex
        for token in wordTokens(in: text) {
            guard let range = lowered.range(of: token, range: cursor..<lowered.endIndex) else { continue }
            tokens.append(WordToken(
                token: token,
                start: lowered.distance(from: lowered.startIndex, to: range.lowerBound)
            ))
            cursor = range.upperBound
        }
        return tokens
    }

    static func related(_ a: String, _ b: String, languageCode: String) -> Bool {
        if a == b { return true }
        guard let embedding = embedding(for: languageCode),
              embedding.contains(a), embedding.contains(b) else { return false }
        return embedding.distance(between: a, and: b, distanceType: .cosine) <= relatedDistanceCeiling
    }

    /// NLEmbedding loads are expensive and related() runs inside loops.
    private static var embeddingCache: [String: NLEmbedding] = [:]
    private static let embeddingLock = NSLock()

    private static func embedding(for languageCode: String) -> NLEmbedding? {
        embeddingLock.lock()
        defer { embeddingLock.unlock() }
        if let cached = embeddingCache[languageCode] { return cached }
        let loaded = NLEmbedding.wordEmbedding(for: NLLanguage(rawValue: languageCode))
        if let loaded { embeddingCache[languageCode] = loaded }
        return loaded
    }
}

/// Spoken-English scaffolding NLTagger tags as content words even though a
/// speaker reaches for them out of habit, not meaning — a field-confirmed
/// bug ("was / have / can / think" as real-device themes) traced to exactly
/// this gap between lexical class and topical content.
enum SpokenStoplist {

    /// Filler nouns filtered out of THEME extraction (nouns only). `day`,
    /// `days`, and `area` joined at the ship gate (2026-08-25): real-device
    /// history showed place resonance threading 'day' (17 mentions near the
    /// same ground) and photo adjacency threading 'area' — the same
    /// generic-noun class as `thing`/`way`, not topical content.
    static let lightNouns: Set<String> = [
        "thing", "things", "stuff", "kind", "sort", "lot", "bit", "way", "ways",
        "one", "ones", "something", "anything", "everything", "nothing",
        "day", "days", "area"
    ]

    /// Light/auxiliary/modal verbs plus the filler nouns above, filtered out
    /// of the recurring-word attention directive — which still scans verbs,
    /// so it needs its own stoplist rather than the noun restriction above.
    ///
    /// Modal verbs (`can`, `could`, `should`, `would`, `must`, `might`,
    /// `may`, `will`, `ought`, `wish` — `need`/`want` were already here) are
    /// stoplisted by design: they're a STATE signal that belongs in the
    /// markers channel with word identity (`MarkerLexicons.modalFamilies`),
    /// never named as a recurring-word TOPIC — a flat walk's "can ×57" is
    /// noise there, not a theme.
    static let scaffoldLemmas: Set<String> = [
        "be", "have", "do", "get", "go", "come", "make", "take", "know",
        "think", "say", "see", "want", "mean", "feel", "need", "let", "put",
        "keep", "kind", "thing", "stuff", "way", "lot", "bit",
        "can", "could", "should", "would", "must", "might", "may", "will", "ought", "wish"
    ]
}
