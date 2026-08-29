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
            let token = String(text[range])
            let core = letterCore(token)
            guard core.count > 2 else { return true }
            let surface = core.lowercased()
            let taggedLemma = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma)
                .0.map { letterCore($0.rawValue).lowercased() } ?? ""
            lastOffset += text.distance(from: lastIndex, to: range.lowerBound)
            lastIndex = range.lowerBound
            mentions.append(LemmaMention(
                lemma: taggedLemma.isEmpty ? surface : taggedLemma,
                surface: surface,
                start: lastOffset + token.prefix { !$0.isLetter }.count,
                length: core.count
            ))
            return true
        }
        return mentions
    }

    /// The leading run of letters, skipping any non-letters before it.
    ///
    /// NLTagger's `.word` unit does not always end a token at the word: when
    /// a sentence-final period is followed by a lowercase word — the shape
    /// Whisper writes — the token range swallows the period ("yeah.",
    /// "garden.", "mary.") and the token is classed as a content word, so
    /// `.omitPunctuation` never sees it. Left alone, the tagger then has no
    /// lemma for that glued form and the `?? surface` fallback stores the
    /// punctuation as thread identity: 'yeah' and 'yeah.' become two lemmas
    /// for one spoken word, and a real noun's mentions split across two
    /// threads. Field-confirmed on device (2026-08-28) as a fabricated
    /// "never apart" invariant and as a Recurring chip printing "yeah.".
    ///
    /// Reducing to the leading letter run also repairs the no-space case
    /// ("garden.the" → "garden"), where the token glues two words together.
    private static func letterCore(_ token: String) -> String {
        String(token.drop { !$0.isLetter }.prefix { $0.isLetter })
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
    ///
    /// `time`/`times`, `person`/`people`, `app`/`apps` joined on 2026-08-28,
    /// all three observed as live themes on real-device history. `app` is the
    /// walker narrating Pilgrim itself — meta-noise, never a life theme.
    /// The filter reads LEMMAS, and NLTagger folds `people` → `person` and
    /// `times` → `time`, so the singular forms are the ones that do the work;
    /// the plurals are listed for the reader, and cost nothing.
    static let lightNouns: Set<String> = [
        "thing", "things", "stuff", "kind", "sort", "lot", "bit", "way", "ways",
        "one", "ones", "something", "anything", "everything", "nothing",
        "day", "days", "area",
        "time", "times", "person", "people", "app", "apps"
    ]

    /// Conversational filler filtered out of THEME extraction. The noun-only
    /// restriction does not stop these: in Whisper's lowercase sentence runs
    /// NLTagger classes 'yeah' as a NOUN, and the field report of 2026-08-28
    /// found it threading three real walks.
    ///
    /// `ok` sits beside `okay` because NLTagger lemmatizes the surface
    /// "okay" to "OK" in some positions and "okay" in others — the same fold
    /// that makes `people` arrive as `person`. The two-letter spellings
    /// (`um`, `uh`, `er`, `mm`) are absent because `contentLemmaMentions`
    /// already drops any surface shorter than three characters; the doubled
    /// spellings Whisper actually writes are what needs listing.
    ///
    /// Deliberately NOT here, because every word added blinds the feature to
    /// that word forever: `right` (a direction on a walk — and already
    /// covered by `ThemeExtractor.walkingDomain`), `sure`, `yes`, `no`,
    /// `well`, `like`, `just`, `anyway`. Each can carry real weight in a
    /// walker's speech; none has been seen misfiring.
    static let filler: Set<String> = [
        "yeah", "yep", "yup", "nah", "okay", "ok",
        "uhh", "umm", "erm", "hmm", "mhm", "mmm", "huh",
        "gonna", "gotta", "wanna"
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
