# Thought Threads — Stages 1–2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On-device semantic analysis of walk transcripts — NaturalLanguage-powered attention directives, a marker pack + theme extractor cached per recording, cross-walk thread aggregation, and a rich AI-prompt dossier — ending at the field gate that decides whether the Stage 3 card ships.

**Architecture:** A new `Pilgrim/Models/Threads/` module mirrors the `PhotoContextAnalyzer` shape: NaturalLanguage framework → `Codable` structs → file-per-recording JSON store → prompt sections. `AttentionDirectives` is upgraded in place. Nothing touches the CoreStore schema, `SharePayload`, or the network. Spec: `docs/superpowers/specs/2026-08-22-thought-threads-design.md`.

**Tech Stack:** Swift, SwiftUI, NaturalLanguage (NLTagger / NLEmbedding / NLLanguageRecognizer), CryptoKit (SHA-256), XCTest.

## Global Constraints

- iOS 18 minimum; no new dependencies; no CoreStore schema changes (`PilgrimV7` stays current — derived data is a recomputable file cache, never a schema attribute).
- Transcripts and derived data never leave the device: nothing added to `SharePayload`, `.pilgrim` export, or any network path.
- Markers are English-only, gated on detected language; themes degrade gracefully (spec "Multilingual by degradation").
- All analysis output is deterministic: same transcripts in, same results out; ties broken by the existing `recurringWord` convention (highest count, then alphabetical).
- Absolutist lexicon: copy the 19-word dictionary verbatim from Al-Mosaiwi & Johnstone 2018 Table 1 (open access, https://pmc.ncbi.nlm.nih.gov/articles/PMC6376956/); LIWC word lists must never be copied; NRC lexicons excluded (commercial license); Empath out of v1.
- The `threadsAfterWalks` preference (default `true`) gates the dossier sections AND all future UI — off means prompts render exactly as today.
- Context files live in `Application Support/TranscriptContexts/<recordingUUID>.json`, excluded from backups via `isExcludedFromBackup`.
- New Swift files must be added to the `Pilgrim` app target (tests to the `UnitTests` target) in `Pilgrim.xcodeproj/project.pbxproj` — follow the pbxproj entry pattern of a sibling file in the same group.
- Comment policy: self-documenting code; comments only for constraints code can't show. SwiftLint `type_body_length` errors at 750 lines — keep files small.
- Test command (per class): `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/<ClassName> 2>&1 | tail -20`
- `NLEmbedding` availability is per-language and absent on some simulators: any test depending on it must `try XCTSkipIf(NLEmbedding.wordEmbedding(for: .english) == nil, "word embeddings unavailable in this environment")` rather than fail.

---

### Task 1: TranscriptNLP — language, lemmas, relatedness

**Files:**
- Create: `Pilgrim/Models/Threads/TranscriptNLP.swift`
- Test: `UnitTests/TranscriptNLPTests.swift`

**Interfaces:**
- Consumes: NaturalLanguage framework only.
- Produces (used by Tasks 2, 4, 5, 7):
  - `TranscriptNLP.detectLanguage(_ text: String) -> String?` (ISO code, e.g. `"en"`, nil when confidence < 0.5)
  - `TranscriptNLP.LemmaMention` — `{ lemma: String, surface: String, start: Int, length: Int }` (character offsets into the input string)
  - `TranscriptNLP.contentLemmaMentions(in text: String) -> [LemmaMention]` (nouns/verbs/adjectives only, lowercased, length > 2)
  - `TranscriptNLP.contentLemmas(in text: String) -> [String]`
  - `TranscriptNLP.related(_ a: String, _ b: String, languageCode: String) -> Bool` (embedding cosine distance ≤ 0.95, or exact match; false when no embedding for the language; the loaded `NLEmbedding` is memoized per language)
  - `TranscriptNLP.wordTokens(in text: String) -> [String]` / `TranscriptNLP.wordCount(in text: String) -> Int` — the ONE tokenizer every word count and density in this feature uses (MarkerAnalyzer, ThemeExtractor, TranscriptContextAnalyzer all call it; never re-implement the chain)

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import NaturalLanguage
@testable import Pilgrim

final class TranscriptNLPTests: XCTestCase {

    func testDetectLanguage_english() {
        XCTAssertEqual(TranscriptNLP.detectLanguage("I keep thinking about the move and whether we should go"), "en")
    }

    func testDetectLanguage_spanish() {
        XCTAssertEqual(TranscriptNLP.detectLanguage("Sigo pensando en la mudanza y en si deberíamos irnos de aquí"), "es")
    }

    func testContentLemmas_unifiesInflections() {
        let lemmas = TranscriptNLP.contentLemmas(in: "Grieving again today. I grieved all spring.")
        XCTAssertEqual(lemmas.filter { $0 == "grieve" }.count, 2)
    }

    func testContentLemmas_dropsFunctionWords() {
        let lemmas = TranscriptNLP.contentLemmas(in: "the river and the fog were with me")
        XCTAssertFalse(lemmas.contains("the"))
        XCTAssertFalse(lemmas.contains("and"))
        XCTAssertTrue(lemmas.contains("river"))
        XCTAssertTrue(lemmas.contains("fog"))
    }

    func testMentions_carryCharacterOffsets() {
        let text = "fog on the river"
        let mention = TranscriptNLP.contentLemmaMentions(in: text).first { $0.lemma == "river" }
        XCTAssertNotNil(mention)
        let start = text.index(text.startIndex, offsetBy: mention!.start)
        let end = text.index(start, offsetBy: mention!.length)
        XCTAssertEqual(String(text[start..<end]), "river")
    }

    func testRelated_synonymPair() throws {
        try XCTSkipIf(NLEmbedding.wordEmbedding(for: .english) == nil, "word embeddings unavailable in this environment")
        XCTAssertTrue(TranscriptNLP.related("river", "water", languageCode: "en"))
        XCTAssertFalse(TranscriptNLP.related("river", "deadline", languageCode: "en"))
    }

    func testRelated_exactMatchNeedsNoEmbedding() {
        XCTAssertTrue(TranscriptNLP.related("move", "move", languageCode: "zz"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/TranscriptNLPTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'TranscriptNLP' in scope` (build error counts as red).

- [ ] **Step 3: Implement**

```swift
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

    static func contentLemmaMentions(in text: String) -> [LemmaMention] {
        let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
        tagger.string = text
        let contentClasses: Set<NLTag> = [.noun, .verb, .adjective]
        var mentions: [LemmaMention] = []
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitPunctuation, .omitWhitespace, .omitOther]
        ) { tag, range in
            guard let tag, contentClasses.contains(tag) else { return true }
            let surface = String(text[range]).lowercased()
            guard surface.count > 2 else { return true }
            let lemma = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma)
                .0?.rawValue.lowercased() ?? surface
            mentions.append(LemmaMention(
                lemma: lemma,
                surface: surface,
                start: text.distance(from: text.startIndex, to: range.lowerBound),
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
```

Add both files to the project (app target / UnitTests target) in `project.pbxproj`.

- [ ] **Step 4: Run tests to verify they pass**

Same command. Expected: PASS (embedding test may skip on simulator — skip is acceptable, not failure).

The 0.95 ceiling is calibrated against measured Apple embedding distances (river↔water 0.892, grief↔grieve 0.917 — real synonym pairs sit ABOVE 0.85, which would have shipped both embedding features inert; nearest unrelated pair mean↔move measured 1.051, so 0.95 keeps a margin). Values were measured on the macOS host framework: re-verify these anchor pairs on the iOS 18 simulator before committing, and keep `river↔deadline` asserted false as the drift canary.

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Threads/TranscriptNLP.swift UnitTests/TranscriptNLPTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(threads): TranscriptNLP — language detection, content lemmas, embedding relatedness"
```

---

### Task 2: AttentionDirectives v2 — lemmas and semantic echo

**Files:**
- Modify: `Pilgrim/Models/Threads/../Prompt/AttentionDirectives.swift` (full path `Pilgrim/Models/Prompt/AttentionDirectives.swift`, lines 69–116)
- Test: `UnitTests/AttentionDirectivesTests.swift` (extend, don't replace)

**Interfaces:**
- Consumes: `TranscriptNLP.contentLemmaMentions/contentLemmas/detectLanguage/related` (Task 1).
- Produces: unchanged public surface — `AttentionDirectives.detect(context:) -> [String]`. The 4-directive cap and message formats stay.

- [ ] **Step 1: Write the failing tests** (append to `AttentionDirectivesTests`)

```swift
    // MARK: - Semantic upgrade (Thought Threads Stage 1)

    func testIntentionEcho_lemmaVariantFires() throws {
        try XCTSkipIf(NLEmbedding.wordEmbedding(for: .english) == nil,
                      "word embeddings unavailable in this environment")
        let context = ActivityContext.make(
            recordings: [recording("I have been grieving all morning on this path")],
            startDate: start,
            intention: "sit with grief"
        )
        XCTAssertTrue(joined(context).contains("intention spoke of"))
    }

    func testIntentionEcho_sharedLemmaFires() {
        let context = ActivityContext.make(
            recordings: [recording("walking my worry out under the pines")],
            startDate: start,
            intention: "worry less"
        )
        XCTAssertTrue(joined(context).contains("intention spoke of"))
    }

    func testRecurringWord_countsAcrossInflections() {
        let context = ActivityContext.make(
            recordings: [recording("Moving is hard. We moved before. This move feels different.")],
            startDate: start
        )
        XCTAssertTrue(joined(context).contains("returns 3 times"))
    }

    func testRecurringWord_ignoresFunctionWordsWithoutStoplist() {
        let context = ActivityContext.make(
            recordings: [recording("because because because because the the the the")],
            startDate: start
        )
        XCTAssertFalse(joined(context).contains("returns"))
    }
```

The "grieving"/"grief" pair lemmatizes to different lemmas ("grieve" vs "grief"), so the first test exercises the embedding path and carries the skip guard; the second shares lemma "worry" exactly and never skips. The test file needs `import NaturalLanguage`.

- [ ] **Step 2: Run to verify the new tests fail**

Run the AttentionDirectivesTests class command. Expected: new tests FAIL (exact-string matching can't unify "moving"/"moved"/"move"); all pre-existing tests still PASS.

- [ ] **Step 3: Implement** — replace `intentionEcho`, `recurringWord`, and the `// MARK: - Words` section (delete `stopwords` and the old `contentWords`):

```swift
    /// A word from the stated intention resurfacing in the walker's own
    /// spoken words — by shared lemma first, by embedding nearness second.
    private static func intentionEcho(_ context: ActivityContext) -> String? {
        guard let intention = context.intention, context.hasSpeech else { return nil }
        let spokenText = context.recordings.map(\.text).joined(separator: " ")
        let spoken = TranscriptNLP.contentLemmaMentions(in: spokenText)
        guard !spoken.isEmpty else { return nil }
        let language = TranscriptNLP.detectLanguage(spokenText) ?? "en"
        let spokenLemmas = Set(spoken.map(\.lemma))

        for word in TranscriptNLP.contentLemmaMentions(in: intention) {
            if spokenLemmas.contains(word.lemma) {
                return "The walker's intention spoke of '\(word.surface)', and '\(word.surface)' surfaces again in their spoken words — trace how it traveled."
            }
            if let match = spoken.first(where: { TranscriptNLP.related(word.lemma, $0.lemma, languageCode: language) }) {
                return "The walker's intention spoke of '\(word.surface)', and '\(match.surface)' surfaces in their spoken words — trace how it traveled."
            }
        }
        return nil
    }

    /// The most-repeated content lemma across all recordings, excluding any
    /// lemma the intention already claimed. Shown as its most frequent
    /// surface form so the walker's own inflection is echoed back.
    private static func recurringWord(_ context: ActivityContext) -> String? {
        guard context.hasSpeech else { return nil }
        let intentionLemmas = context.intention
            .map { Set(TranscriptNLP.contentLemmas(in: $0)) } ?? []

        var counts: [String: Int] = [:]
        var surfaces: [String: [String: Int]] = [:]
        let mentions = TranscriptNLP.contentLemmaMentions(
            in: context.recordings.map(\.text).joined(separator: " ")
        )
        for mention in mentions where !intentionLemmas.contains(mention.lemma) {
            counts[mention.lemma, default: 0] += 1
            surfaces[mention.lemma, default: [:]][mention.surface, default: 0] += 1
        }

        guard let (lemma, count) = counts.filter({ $0.value >= 3 })
            .min(by: { ($0.value, $1.key) > ($1.value, $0.key) }) else { return nil }
        let display = surfaces[lemma]?
            .min(by: { ($0.value, $1.key) > ($1.value, $0.key) })?.key ?? lemma

        return "The word '\(display)' returns \(count) times across the recordings — it may be doing quiet work."
    }
```

- [ ] **Step 4: Run the full AttentionDirectivesTests class** — all old and new tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Prompt/AttentionDirectives.swift UnitTests/AttentionDirectivesTests.swift
git commit -m "feat(threads): AttentionDirectives speak in lemmas — inflections unify, intention echo hears paraphrase"
```

---

### Task 3: Detected-language note in the prompt

**Files:**
- Modify: `Pilgrim/Models/Prompt/PromptAssembler.swift:83-106` (`walkRecord`)
- Test: `UnitTests/PromptAssemblerLanguageTests.swift` (create)

**Interfaces:**
- Consumes: `TranscriptNLP.detectLanguage` (Task 1); `PromptAssembler.assemble(context:voice:)` (existing).
- Produces: prompts containing `**Detected language:** <name>` when speech exists and detection succeeds.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Pilgrim

final class PromptAssemblerLanguageTests: XCTestCase {

    private let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)

    private func assembled(_ text: String) -> String {
        let context = ActivityContext.make(
            recordings: [RecordingContext(
                text: text, timestamp: start,
                startCoordinate: nil, endCoordinate: nil, wordsPerMinute: nil
            )],
            startDate: start
        )
        return PromptAssembler.assemble(context: context, voice: PromptStyle.allCases[0].voice)
    }

    func testSpanishTranscript_notesDetectedLanguage() {
        let prompt = assembled("Sigo pensando en la mudanza y en si deberíamos irnos de aquí este otoño")
        XCTAssertTrue(prompt.contains("**Detected language:**"))
        XCTAssertTrue(prompt.contains("Spanish"))
    }

    func testNoSpeech_noLanguageNote() {
        let context = ActivityContext.make(startDate: start)
        let prompt = PromptAssembler.assemble(context: context, voice: PromptStyle.allCases[0].voice)
        XCTAssertFalse(prompt.contains("**Detected language:**"))
    }
}
```

Check how existing prompt tests obtain a `PromptVoice` (search `UnitTests/` for `PromptAssembler.assemble`) and reuse that idiom in place of `PromptStyle.allCases[0].voice` if it differs.

- [ ] **Step 2: Run to verify it fails** (`-only-testing:UnitTests/PromptAssemblerLanguageTests`). Expected: FAIL — no language note emitted.

- [ ] **Step 3: Implement** — in `walkRecord`, directly after the `**Walking Transcription:**` block:

```swift
        if !transcription.isEmpty,
           let code = TranscriptNLP.detectLanguage(context.recordings.map(\.text).joined(separator: " ")),
           let name = Locale(identifier: "en").localizedString(forLanguageCode: code) {
            sections += "\n\n**Detected language:** \(name)"
        }
```

(`Locale(identifier: "en")` keeps the note deterministic regardless of device locale — the prompt is written in English.)

- [ ] **Step 4: Run tests — PASS.**

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Prompt/PromptAssembler.swift UnitTests/PromptAssemblerLanguageTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(threads): prompts name the detected transcript language"
```

---

### Task 4: Marker lexicons and MarkerAnalyzer

**Files:**
- Create: `Pilgrim/Models/Threads/MarkerLexicons.swift`
- Create: `Pilgrim/Models/Threads/MarkerAnalyzer.swift`
- Test: `UnitTests/MarkerAnalyzerTests.swift`

**Interfaces:**
- Consumes: NaturalLanguage sentiment; plain tokenization.
- Produces (used by Tasks 7, 10):
  - `struct MarkerPack: Codable, Equatable` — `{ wordCount: Int, absolutistCount: Int, firstPersonCount: Int, insightCount: Int, causationCount: Int, discrepancyCount: Int, futureCount: Int, pastCount: Int, sentiment: Double? }` plus computed `var temporalLean: String` (`"past"` / `"future"` / `"balanced"`).
  - `MarkerAnalyzer.compute(text: String, languageCode: String?) -> MarkerPack?` (nil unless `languageCode == "en"`).

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Pilgrim

final class MarkerAnalyzerTests: XCTestCase {

    func testAbsolutistCount_exact() {
        let pack = MarkerAnalyzer.compute(
            text: "I always ruin everything. It never works. Never.",
            languageCode: "en"
        )
        XCTAssertEqual(pack?.absolutistCount, 4)  // always, everything, never, never
    }

    func testFirstPersonCount_exact() {
        let pack = MarkerAnalyzer.compute(text: "I told myself my worry is mine to carry", languageCode: "en")
        XCTAssertEqual(pack?.firstPersonCount, 4)  // i, myself, my, mine
    }

    func testInsightAndCausation() {
        let pack = MarkerAnalyzer.compute(
            text: "I realize now it happened because I never rested",
            languageCode: "en"
        )
        XCTAssertEqual(pack?.insightCount, 1)
        XCTAssertEqual(pack?.causationCount, 1)
    }

    func testTemporalLean_future() {
        let pack = MarkerAnalyzer.compute(
            text: "Tomorrow I will call her. I will plan the trip. Soon we will know. It will be fine.",
            languageCode: "en"
        )
        XCTAssertEqual(pack?.temporalLean, "future")
    }

    func testNonEnglish_returnsNil() {
        XCTAssertNil(MarkerAnalyzer.compute(text: "Sigo pensando en la mudanza", languageCode: "es"))
        XCTAssertNil(MarkerAnalyzer.compute(text: "anything", languageCode: nil))
    }

    func testWordCount_lettersOnlyTokens() {
        let pack = MarkerAnalyzer.compute(text: "one two three, four — five!", languageCode: "en")
        XCTAssertEqual(pack?.wordCount, 5)
    }
}
```

- [ ] **Step 2: Run to verify failure** (`-only-testing:UnitTests/MarkerAnalyzerTests`).

- [ ] **Step 3: Implement**

`MarkerLexicons.swift`:

```swift
import Foundation

/// Small embedded lexicons for on-device linguistic markers. The absolutist
/// set is the 19-word dictionary from Al-Mosaiwi & Johnstone 2018 (Table 1,
/// open access) — verify verbatim against the paper before shipping. LIWC's
/// proprietary word lists must never be copied here.
enum MarkerLexicons {

    static let absolutist: Set<String> = [
        "absolutely", "all", "always", "complete", "completely", "constant",
        "constantly", "definitely", "entire", "ever", "every", "everyone",
        "everything", "full", "must", "never", "nothing", "totally", "whole"
    ]

    static let firstPersonSingular: Set<String> = ["i", "me", "my", "mine", "myself"]

    static let insight: Set<String> = [
        "realize", "realized", "realizing", "understand", "understood",
        "understanding", "notice", "noticed", "noticing", "aware", "awareness",
        "clarity", "insight", "learn", "learned", "learning", "recognize",
        "recognized", "sense", "sensed"
    ]

    static let causation: Set<String> = [
        "because", "cause", "caused", "causes", "effect", "hence", "since",
        "therefore", "thus", "reason", "reasons", "why", "consequently", "led"
    ]

    static let discrepancy: Set<String> = [
        "should", "would", "could", "ought", "need", "needed", "want",
        "wanted", "wish", "wished", "hope", "hoped", "rather", "instead"
    ]

    static let futureMarkers: Set<String> = [
        "will", "shall", "gonna", "tomorrow", "soon", "later", "ahead",
        "upcoming", "future", "plan", "plans", "planning"
    ]

    static let pastMarkers: Set<String> = [
        "was", "were", "did", "had", "ago", "yesterday", "remember",
        "remembered", "used", "back", "once", "before"
    ]
}
```

`MarkerAnalyzer.swift`:

```swift
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
```

- [ ] **Step 4: Run tests — PASS.** If `testAbsolutistCount_exact` disagrees with the verified Table 1 word list, fix the lexicon, not the test intent (recount expected values against the final list).

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Threads/MarkerLexicons.swift Pilgrim/Models/Threads/MarkerAnalyzer.swift UnitTests/MarkerAnalyzerTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(threads): marker pack — absolutist, self-focus, cognitive-process, temporal, sentiment"
```

---

### Task 5: ThemeExtractor

**Files:**
- Create: `Pilgrim/Models/Threads/ThemeExtractor.swift`
- Test: `UnitTests/ThemeExtractorTests.swift`

**Interfaces:**
- Consumes: `TranscriptNLP` (Task 1).
- Produces (used by Tasks 7, 9, 10):
  - `struct ThemeMention: Codable, Equatable` — `{ start: Int, length: Int }`
  - `struct Theme: Codable, Equatable` — `{ lemma: String, displayTerm: String, mentionCount: Int, salience: Double, mentions: [ThemeMention] }`
  - `ThemeExtractor.themes(in text: String, languageCode: String?) -> [Theme]` — empty below 25 words; max 6, salience-descending, deterministic ties.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Pilgrim

final class ThemeExtractorTests: XCTestCase {

    private let moveText = """
        Still circling the move today. If the move happens in fall we lose the garden, \
        and moving means telling her father. The move keeps returning whenever the \
        morning is quiet enough for it to speak. Thirty words of worry now.
        """

    func testRepeatedLemma_becomesTheme() {
        let themes = ThemeExtractor.themes(in: moveText, languageCode: "en")
        let move = themes.first { $0.lemma == "move" }
        XCTAssertNotNil(move)
        XCTAssertGreaterThanOrEqual(move!.mentionCount, 3)
        XCTAssertEqual(move!.mentions.count, move!.mentionCount)
    }

    func testShortText_returnsNoThemes() {
        XCTAssertTrue(ThemeExtractor.themes(in: "only a few words here", languageCode: "en").isEmpty)
    }

    func testWalkingDomain_suppressed() {
        let text = String(repeating: "walking the path uphill on the trail ", count: 10)
        let themes = ThemeExtractor.themes(in: text, languageCode: "en")
        XCTAssertFalse(themes.contains { ThemeExtractor.walkingDomain.contains($0.lemma) })
    }

    func testDeterminism() {
        let a = ThemeExtractor.themes(in: moveText, languageCode: "en")
        let b = ThemeExtractor.themes(in: moveText, languageCode: "en")
        XCTAssertEqual(a, b)
    }
}
```

- [ ] **Step 2: Run to verify failure** (`-only-testing:UnitTests/ThemeExtractorTests`).

- [ ] **Step 3: Implement**

```swift
import Foundation

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

    private static func mentions(in text: String) -> [TranscriptNLP.LemmaMention] {
        TranscriptNLP.contentLemmaMentions(in: text)
            .filter { !walkingDomain.contains($0.lemma) }
    }
}
```

- [ ] **Step 4: Run tests — PASS.**
- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Threads/ThemeExtractor.swift UnitTests/ThemeExtractorTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(threads): theme extraction — lemma clusters with mention offsets, walking-domain suppressed"
```

---

### Task 6: TranscriptContext and the file store

**Files:**
- Create: `Pilgrim/Models/Threads/TranscriptContext.swift`
- Create: `Pilgrim/Models/Threads/TranscriptContextStore.swift`
- Test: `UnitTests/TranscriptContextStoreTests.swift`

**Interfaces:**
- Consumes: `Theme` (Task 5), `MarkerPack` (Task 4), CryptoKit.
- Produces (used by Tasks 7, 8, 9, 10):
  - `struct TranscriptContext: Codable, Equatable` — `{ schemaVersion: Int, recordingUUID: UUID, transcriptHash: String, languageCode: String?, wordCount: Int, themes: [Theme], markers: MarkerPack? }` with `static let currentSchemaVersion = 1`
  - `final class TranscriptContextStore` — `static let shared`; `init(directory: URL)` for tests; `static func hash(of transcript: String) -> String`; `func save(_:)`; `func context(for recordingUUID: UUID, matching transcriptHash: String) -> TranscriptContext?`; `func hasContext(for recordingUUID: UUID) -> Bool`; `func loadAll() -> [TranscriptContext]`; `func delete(recordingUUIDs: [UUID])`; `func deleteAll()`; `func pruneOrphans(keeping valid: Set<UUID>)`; `private(set) var changeCount: Int` (bumps on every mutation — the dossier builder's memo key). All file mutations run on a private serial queue, and deleted UUIDs are tombstoned in memory so a queued analysis finishing after a deletion cannot resurrect derived data (tombstones clear on relaunch — safe, because re-imported recordings re-analyze via the backfill reset in Task 7).

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Pilgrim

final class TranscriptContextStoreTests: XCTestCase {

    private var store: TranscriptContextStore!
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptContextsTests-\(UUID().uuidString)")
        store = TranscriptContextStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeContext(uuid: UUID = UUID(), transcript: String = "hello world") -> TranscriptContext {
        TranscriptContext(
            schemaVersion: TranscriptContext.currentSchemaVersion,
            recordingUUID: uuid,
            transcriptHash: TranscriptContextStore.hash(of: transcript),
            languageCode: "en",
            wordCount: 2,
            themes: [],
            markers: nil
        )
    }

    func testSaveAndLoadRoundTrip() {
        let context = makeContext(transcript: "the river again")
        store.save(context)
        let loaded = store.context(
            for: context.recordingUUID,
            matching: TranscriptContextStore.hash(of: "the river again")
        )
        XCTAssertEqual(loaded, context)
    }

    func testHashMismatch_returnsNil() {
        let context = makeContext(transcript: "original words")
        store.save(context)
        XCTAssertNil(store.context(
            for: context.recordingUUID,
            matching: TranscriptContextStore.hash(of: "edited words")
        ))
    }

    func testDeleteByUUIDs() {
        let a = makeContext(), b = makeContext()
        store.save(a); store.save(b)
        store.delete(recordingUUIDs: [a.recordingUUID])
        XCTAssertEqual(store.loadAll().map(\.recordingUUID), [b.recordingUUID])
    }

    func testDeleteAll() {
        store.save(makeContext()); store.save(makeContext())
        store.deleteAll()
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testSaveAfterDelete_doesNotResurrect() {
        let context = makeContext()
        store.save(context)
        store.delete(recordingUUIDs: [context.recordingUUID])
        store.save(context)
        XCTAssertTrue(store.loadAll().isEmpty,
                      "a queued analysis landing after deletion must not resurrect derived data")
    }

    func testPruneOrphans() {
        let keep = makeContext(), orphan = makeContext()
        store.save(keep); store.save(orphan)
        store.pruneOrphans(keeping: [keep.recordingUUID])
        XCTAssertEqual(store.loadAll().map(\.recordingUUID), [keep.recordingUUID])
    }

    func testDirectoryExcludedFromBackup() throws {
        store.save(makeContext())
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }
}
```

- [ ] **Step 2: Run to verify failure** (`-only-testing:UnitTests/TranscriptContextStoreTests`).

- [ ] **Step 3: Implement**

`TranscriptContext.swift`:

```swift
import Foundation

/// Derived, recomputable linguistic context for one voice recording.
/// Never persisted in CoreStore, never exported, never transmitted.
struct TranscriptContext: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let recordingUUID: UUID
    let transcriptHash: String
    let languageCode: String?
    let wordCount: Int
    let themes: [Theme]
    let markers: MarkerPack?
}
```

`TranscriptContextStore.swift`:

```swift
import Foundation
import CryptoKit

/// File-per-recording JSON store under Application Support, excluded from
/// backups — derived psychological data is recomputable and must not ride
/// along in iCloud/iTunes backups (spec: Storage).
final class TranscriptContextStore {

    static let shared = TranscriptContextStore(
        directory: FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TranscriptContexts", isDirectory: true)
    )

    private let directory: URL
    private let writeQueue = DispatchQueue(label: "org.walktalkmeditate.pilgrim.transcript-contexts")
    private var tombstones: Set<UUID> = []
    private(set) var changeCount = 0

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        excludeFromBackup()
    }

    static func hash(of transcript: String) -> String {
        SHA256.hash(data: Data(transcript.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Deleted UUIDs are tombstoned so a queued analysis finishing after a
    /// deletion cannot resurrect derived data. Stale writes self-heal: any
    /// consumer that finds a hash mismatch re-analyzes and persists.
    func save(_ context: TranscriptContext) {
        writeQueue.sync {
            guard !tombstones.contains(context.recordingUUID),
                  let data = try? JSONEncoder().encode(context) else { return }
            try? data.write(to: fileURL(for: context.recordingUUID), options: .atomic)
            changeCount += 1
        }
    }

    func context(for recordingUUID: UUID, matching transcriptHash: String) -> TranscriptContext? {
        guard let loaded = load(recordingUUID: recordingUUID),
              loaded.transcriptHash == transcriptHash,
              loaded.schemaVersion == TranscriptContext.currentSchemaVersion else { return nil }
        return loaded
    }

    func hasContext(for recordingUUID: UUID) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: recordingUUID).path)
    }

    func loadAll() -> [TranscriptContext] {
        contextFileURLs()
            .compactMap { try? JSONDecoder().decode(TranscriptContext.self, from: Data(contentsOf: $0)) }
            .sorted { $0.recordingUUID.uuidString < $1.recordingUUID.uuidString }
    }

    func delete(recordingUUIDs: [UUID]) {
        writeQueue.sync {
            for uuid in recordingUUIDs {
                tombstones.insert(uuid)
                try? FileManager.default.removeItem(at: fileURL(for: uuid))
            }
            changeCount += 1
        }
    }

    func deleteAll() {
        writeQueue.sync {
            for url in contextFileURLs() {
                UUID(uuidString: url.deletingPathExtension().lastPathComponent)
                    .map { tombstones.insert($0) }
            }
            do {
                try FileManager.default.removeItem(at: directory)
            } catch {
                print("[TranscriptContextStore] Failed to remove context directory: \(error)")
            }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            changeCount += 1
        }
        excludeFromBackup()
    }

    func pruneOrphans(keeping valid: Set<UUID>) {
        let orphans = loadAll().map(\.recordingUUID).filter { !valid.contains($0) }
        guard !orphans.isEmpty else { return }
        delete(recordingUUIDs: orphans)
    }

    private func contextFileURLs() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? [])
            .filter { $0.pathExtension == "json" }
    }

    private func load(recordingUUID: UUID) -> TranscriptContext? {
        guard let data = try? Data(contentsOf: fileURL(for: recordingUUID)) else { return nil }
        return try? JSONDecoder().decode(TranscriptContext.self, from: data)
    }

    private func fileURL(for uuid: UUID) -> URL {
        directory.appendingPathComponent("\(uuid.uuidString).json")
    }

    private func excludeFromBackup() {
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
```

- [ ] **Step 4: Run tests — PASS.**
- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Threads/TranscriptContext.swift Pilgrim/Models/Threads/TranscriptContextStore.swift UnitTests/TranscriptContextStoreTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(threads): transcript context file store — hash-validated, backup-excluded, prunable"
```

---

### Task 7: Analyzer, transcription trigger, ASR quality gate, backfill

**Files:**
- Create: `Pilgrim/Models/Threads/TranscriptContextAnalyzer.swift`
- Create: `Pilgrim/Models/Threads/ThreadsBackfill.swift`
- Modify: `Pilgrim/Models/TranscriptionService.swift` (`TranscriptionOutput` at :7, the WhisperKit adapter at :20, and the persist success paths at ~:288 and in `transcribeSingle`)
- Modify: `Pilgrim/Models/Data/DataManager.swift` (add `transcribedRecordingsSnapshot()` helper near `updateVoiceRecordingTranscription` at :569)
- Modify: `Pilgrim/Scenes/Root/MainCoordinatorView.swift` (call `ThreadsBackfill.runIfNeeded()` where launch work already happens)
- Test: `UnitTests/TranscriptContextAnalyzerTests.swift`

**Interfaces:**
- Consumes: Tasks 1, 4, 5, 6.
- Produces (used by Tasks 9, 10):
  - `TranscriptContextAnalyzer.analyze(recordingUUID: UUID, transcript: String, flaggedFragments: [String]) -> TranscriptContext`
  - `TranscriptContextAnalyzer.analyzeAndStore(recordingUUID: UUID, transcript: String, flaggedFragments: [String], store: TranscriptContextStore) -> TranscriptContext` (`store` defaults to `.shared`, `flaggedFragments` to `[]`)
  - `TranscriptionOutput` gains `let flaggedFragments: [String]` — texts of segments with `compressionRatio > 2.4` or `noSpeechProb > 0.6`, each normalized through the same shared cleaning helper as the transcript (Step 5; raw segment text never matches the cleaned persisted transcript). Vendored WhisperKit 0.16 hardcodes `noSpeechProb` to 0 (upstream TODO, TextDecoder.swift:993), so compressionRatio is the effective signal today — keep the branch for a future WhisperKit.
  - `ThreadsBackfill.runIfNeeded()` (`@MainActor`, single-flight, battery-gated) / `isComplete: Bool` / `reset()` (UserDefaults key `"threadsBackfillCompleted"`)
  - `@MainActor DataManager.transcribedRecordingsSnapshot() -> [(uuid: UUID, transcript: String)]` (CoreStore fetches assert main-thread)

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Pilgrim

final class TranscriptContextAnalyzerTests: XCTestCase {

    private let transcript = """
        Still circling the move today. If the move happens in fall we lose the \
        garden. The move keeps returning whenever the morning is quiet, and I \
        always feel it will never settle until we decide something real.
        """

    func testAnalyze_producesThemesMarkersAndHash() {
        let uuid = UUID()
        let context = TranscriptContextAnalyzer.analyze(
            recordingUUID: uuid, transcript: transcript, flaggedFragments: []
        )
        XCTAssertEqual(context.recordingUUID, uuid)
        XCTAssertEqual(context.transcriptHash, TranscriptContextStore.hash(of: transcript))
        XCTAssertEqual(context.languageCode, "en")
        XCTAssertTrue(context.themes.contains { $0.lemma == "move" })
        XCTAssertNotNil(context.markers)
        XCTAssertGreaterThanOrEqual(context.markers!.absolutistCount, 2)  // always, never
    }

    func testFlaggedFragments_cannotFoundATheme() {
        let hallucination = "thanks for watching thanks for watching thanks for watching"
        let text = "A quiet morning with nothing much to say beyond the weather being kind today, honestly just glad the rain held off and the streets stayed empty enough to hear my own breathing for once. " + hallucination
        let context = TranscriptContextAnalyzer.analyze(
            recordingUUID: UUID(), transcript: text, flaggedFragments: [hallucination]
        )
        XCTAssertFalse(context.themes.contains { ["watch", "thank", "thanks"].contains($0.lemma) })
    }

    func testRepeatedFlaggedFragment_everyOccurrenceExcluded() {
        let fragment = "thanks for watching"
        let base = "A long quiet reflection about the garden and the fall and whether the move makes sense for both of us this year, spoken slowly. "
        let text = base + fragment + ". " + fragment + ". " + fragment + "."
        let context = TranscriptContextAnalyzer.analyze(
            recordingUUID: UUID(), transcript: text, flaggedFragments: [fragment]
        )
        XCTAssertFalse(context.themes.contains { ["watch", "thank", "thanks"].contains($0.lemma) })
    }

    func testPartiallyFlaggedTheme_survives() {
        let flagged = "the move the move the move"
        let text = "Still circling the move today and what the move would cost us, more than twenty-five honest words about the whole question spoken here. " + flagged
        let context = TranscriptContextAnalyzer.analyze(
            recordingUUID: UUID(), transcript: text, flaggedFragments: [flagged]
        )
        XCTAssertTrue(context.themes.contains { $0.lemma == "move" },
                      "a theme with at least one unflagged mention survives")
    }

    func testAnalyzeAndStore_persists() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalyzerTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptContextStore(directory: directory)
        let uuid = UUID()
        TranscriptContextAnalyzer.analyzeAndStore(
            recordingUUID: uuid, transcript: transcript, flaggedFragments: [], store: store
        )
        XCTAssertNotNil(store.context(for: uuid, matching: TranscriptContextStore.hash(of: transcript)))
    }
}
```

- [ ] **Step 2: Run to verify failure** (`-only-testing:UnitTests/TranscriptContextAnalyzerTests`).

- [ ] **Step 3: Implement the analyzer**

```swift
import Foundation

enum TranscriptContextAnalyzer {

    /// Themes are extracted from the full transcript so mention offsets stay
    /// valid for excerpt display, then any theme whose every mention falls
    /// inside an ASR-flagged fragment is dropped — a hallucinated fragment
    /// can echo a real theme but never found one (spec: Error handling).
    static func analyze(
        recordingUUID: UUID,
        transcript: String,
        flaggedFragments: [String] = []
    ) -> TranscriptContext {
        let language = TranscriptNLP.detectLanguage(transcript)
        let flaggedRanges = characterRanges(of: flaggedFragments, in: transcript)

        let themes = ThemeExtractor.themes(in: transcript, languageCode: language)
            .filter { theme in
                flaggedRanges.isEmpty || theme.mentions.contains { mention in
                    !flaggedRanges.contains { $0.contains(mention.start) }
                }
            }

        let analysisText = flaggedFragments.reduce(transcript) {
            $0.replacingOccurrences(of: $1, with: " ")
        }

        return TranscriptContext(
            schemaVersion: TranscriptContext.currentSchemaVersion,
            recordingUUID: recordingUUID,
            transcriptHash: TranscriptContextStore.hash(of: transcript),
            languageCode: language,
            wordCount: TranscriptNLP.wordCount(in: transcript),
            themes: themes,
            markers: MarkerAnalyzer.compute(text: analysisText, languageCode: language)
        )
    }

    @discardableResult
    static func analyzeAndStore(
        recordingUUID: UUID,
        transcript: String,
        flaggedFragments: [String] = [],
        store: TranscriptContextStore = .shared
    ) -> TranscriptContext {
        let context = analyze(
            recordingUUID: recordingUUID,
            transcript: transcript,
            flaggedFragments: flaggedFragments
        )
        store.save(context)
        return context
    }

    /// Every occurrence, not just the first — repeated hallucination is the
    /// canonical Whisper failure shape.
    private static func characterRanges(of fragments: [String], in text: String) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        for fragment in fragments where !fragment.isEmpty {
            var searchStart = text.startIndex
            while let range = text.range(of: fragment, range: searchStart..<text.endIndex) {
                let start = text.distance(from: text.startIndex, to: range.lowerBound)
                ranges.append(start..<(start + text.distance(from: range.lowerBound, to: range.upperBound)))
                searchStart = range.upperBound
            }
        }
        return ranges
    }
}
```

- [ ] **Step 4: Run analyzer tests — PASS. Commit.**

```bash
git add Pilgrim/Models/Threads/TranscriptContextAnalyzer.swift UnitTests/TranscriptContextAnalyzerTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(threads): analyzer — themes plus markers per recording, hallucinations cannot found threads"
```

- [ ] **Step 5: Wire the ASR quality signals and the trigger**

In `TranscriptionService.swift`:
1. Extend `TranscriptionOutput` (line 7) with `let flaggedFragments: [String]`.
2. In the `WhisperKit: TranscriptionEngine` adapter (line ~20), collect segment texts where `compressionRatio > 2.4 || noSpeechProb > 0.6` into `flaggedFragments` (match WhisperKit 0.16's `TranscriptionSegment` field names). **Normalize each fragment through the same cleaning as the transcript**: extract `cleanTranscription` (:427-437) into a shared static helper applied to both, so fragment text can actually be found inside the cleaned persisted transcript — raw segment text with leading spaces and artifacts never matches, which would silently no-op the entire gate. WhisperKit 0.16 hardcodes `noSpeechProb` to 0 (upstream TODO), so compressionRatio is the effective signal today; keep the branch. Every other construction site of `TranscriptionOutput` (including test doubles) passes `flaggedFragments: []`.
3. Make `DataManager.updateVoiceRecordingTranscription` (DataManager.swift:569) the single analysis choke point — it is the one write path shared by batch transcription, single retranscribe, AND the manual transcript-edit UIs (`VoiceRecordingRow`, `RecordingsListView`), which is exactly what the spec's "recompute on edit" requires. Add a defaulted parameter and trigger analysis on success:

```swift
    public static func updateVoiceRecordingTranscription(
        uuid: UUID,
        transcription: String,
        flaggedFragments: [String] = [],
        transcriptContextStore: TranscriptContextStore = .shared,
        // ...existing dataStack/completion parameters unchanged...
    )
```

The success signal lives inside the shared `updateVoiceRecording` helper
(DataManager.swift:602-628), whose `.success` case includes `found == false`
(row deleted or replaced mid-batch — firing then would store psychological
data for a recording the user just deleted). Wrap the completion this
function already hands to the shared helper, matching that helper's actual
closure shape:

```swift
        updateVoiceRecording(uuid: uuid, dataStack: dataStack, mutate: {
            $0._transcription.value = transcription
        }) { success, found, error in
            if success, found {
                Task.detached(priority: .utility) {
                    TranscriptContextAnalyzer.analyzeAndStore(
                        recordingUUID: uuid,
                        transcript: transcription,
                        flaggedFragments: flaggedFragments,
                        store: transcriptContextStore
                    )
                }
            }
            completion(success, found, error)
        }
```

The trigger stays local to this function — the shared helper also serves
WPM/isEnhanced updates, which must never analyze. `TranscriptionService.persistTranscription`
passes `output.flaggedFragments` through; the edit UIs compile unchanged via
the defaults. The detached utility task keeps analysis off the transcription
loop so `unloadModel()` at :317 is never delayed, and an in-place edit
replaces the stale context file when it saves. Extend
`UnitTests/VoiceRecordingPersistenceTests.swift` with an injected temp store
asserting analysis persists on `found == true` and does not on `found == false`.

- [ ] **Step 6: Implement the backfill**

`ThreadsBackfill.swift`:

```swift
import Foundation
import UIKit

/// One-time pass over already-transcribed recordings when the feature first
/// activates — origin claims ("first time", "where it began") are only true
/// once history is fully analyzed (spec: ThreadStore).
enum ThreadsBackfill {

    static let completedKey = "threadsBackfillCompleted"
    private static var isRunning = false

    static var isComplete: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    /// Called from PilgrimPackageImporter's success path: imports bypass the
    /// transcription choke point, so the flag resets and the next launch
    /// sweeps the imported recordings (origin labels re-suppress meanwhile).
    static func reset() {
        UserDefaults.standard.set(false, forKey: completedKey)
    }

    /// Main-actor only: the CoreStore snapshot must be taken before
    /// detaching — `dataStack.fetchAll` asserts main-thread. Single-flight,
    /// and battery-gated like MainCoordinator.triggerAutoTranscription.
    /// Fills MISSING contexts only: a hash-mismatched (edited) recording is
    /// owned by the edit trigger, and overwriting it here would race a
    /// newer analysis with this launch's stale snapshot.
    @MainActor
    static func runIfNeeded(store: TranscriptContextStore = .shared) {
        guard !isComplete, !isRunning else { return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        guard UIDevice.current.batteryLevel > 0.2
            || UIDevice.current.batteryState == .charging
            || UIDevice.current.batteryState == .full else { return }
        isRunning = true

        let items = DataManager.transcribedRecordingsSnapshot()
        Task.detached(priority: .utility) {
            for item in items where !store.hasContext(for: item.uuid) {
                TranscriptContextAnalyzer.analyzeAndStore(
                    recordingUUID: item.uuid,
                    transcript: item.transcript,
                    store: store
                )
            }
            await MainActor.run {
                UserDefaults.standard.set(true, forKey: completedKey)
                isRunning = false
            }
        }
    }
}
```

In `DataManager.swift`, next to `updateVoiceRecordingTranscription` (:569):

```swift
    /// Snapshot of every transcribed recording for the Threads backfill —
    /// UUIDs and text only, fetched once, no live objects escape the stack.
    /// Main-actor only: `dataStack.fetchAll` asserts Thread.isMainThread.
    @MainActor
    public static func transcribedRecordingsSnapshot() -> [(uuid: UUID, transcript: String)] {
        let recordings = (try? dataStack.fetchAll(From<VoiceRecording>())) ?? []
        return recordings.compactMap { recording in
            guard let uuid = recording._uuid.value,
                  let transcript = recording._transcription.value,
                  !transcript.isEmpty else { return nil }
            return (uuid, transcript)
        }
    }
```

(Verify the exact attribute property names against `PilgrimV7.swift:233-241` — `_uuid` and `_transcription` per the entity definition.)

In `MainCoordinatorView.swift`, call `ThreadsBackfill.runIfNeeded()` from `MainCoordinator.init()` (MainCoordinatorView.swift:21-26, alongside `WalkSessionGuard.recoverIfNeeded` — the file has no `onAppear` launch task), guaranteeing main-actor invocation.

One more wiring: `.pilgrim` import bypasses the choke point — `PilgrimPackageImporter` writes transcriptions via `persistVoiceRecordings` (DataManager.swift:378, reached from PilgrimPackageImporter.swift:252). Call `ThreadsBackfill.reset()` in the importer's success completion so the next launch's idempotent backfill sweeps the imported recordings; until it completes, origin labels correctly re-suppress.

- [ ] **Step 7: Build the app target and run the full UnitTests suite.**

Run: `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests 2>&1 | tail -20`
Expected: PASS (compile errors here usually mean a `TranscriptionOutput` construction site missed `flaggedFragments`).

- [ ] **Step 8: Commit**

```bash
git add Pilgrim/Models/Threads/ThreadsBackfill.swift Pilgrim/Models/TranscriptionService.swift Pilgrim/Models/Data/DataManager.swift Pilgrim/Scenes/Root/MainCoordinatorView.swift
git commit -m "feat(threads): analysis rides transcription — quality-gated fragments, one-time backfill"
```

---

### Task 8: Deletion hygiene in DataManager

**Files:**
- Modify: `Pilgrim/Models/Data/DataManager.swift:902-966` (`deleteObject`, `deleteAll`)
- Test: `UnitTests/DataManagerThreadsDeletionTests.swift` (create)

**Interfaces:**
- Consumes: `TranscriptContextStore.delete(recordingUUIDs:)` / `.deleteAll()` (Task 6).
- Produces: deletion-triggered context-file removal via `DataManager.transcriptContextStore` (a `static var` seam defaulting to `.shared`, swapped by tests); the spec's "deletion is the trigger, not luck" requirement.

- [ ] **Step 1: Write the failing test**

Mirror the CoreStore seeding pattern used in `UnitTests/VoiceRecordingPersistenceTests.swift` (walk + voice-recording rows against the test stack — reuse its seeding helper idiom):

```swift
import XCTest
@testable import Pilgrim

final class DataManagerThreadsDeletionTests: XCTestCase {

    private var store: TranscriptContextStore!
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThreadsDeletionTests-\(UUID().uuidString)")
        store = TranscriptContextStore(directory: directory)
        DataManager.transcriptContextStore = store
    }

    override func tearDownWithError() throws {
        DataManager.transcriptContextStore = .shared
        try? FileManager.default.removeItem(at: directory)
    }

    private func context(for uuid: UUID) -> TranscriptContext {
        TranscriptContext(
            schemaVersion: TranscriptContext.currentSchemaVersion,
            recordingUUID: uuid, transcriptHash: "h", languageCode: "en",
            wordCount: 2, themes: [], markers: nil
        )
    }

    func testDeleteWalk_removesItsRecordingContexts() throws {
        let (walk, recordingUUID) = try seedWalkWithTranscribedRecording()
        store.save(context(for: recordingUUID))

        let deleted = expectation(description: "deleted")
        DataManager.deleteObject(object: walk) { success, _ in
            XCTAssertTrue(success)
            deleted.fulfill()
        }
        wait(for: [deleted], timeout: 5)
        XCTAssertFalse(store.hasContext(for: recordingUUID))
    }

    func testDeleteAll_removesEveryContextFile() throws {
        let (_, recordingUUID) = try seedWalkWithTranscribedRecording()
        store.save(context(for: recordingUUID))
        store.save(context(for: UUID()))

        let deleted = expectation(description: "deleted all")
        DataManager.deleteAll { success, _ in
            XCTAssertTrue(success)
            deleted.fulfill()
        }
        wait(for: [deleted], timeout: 5)
        XCTAssertTrue(store.loadAll().isEmpty)
    }
}
```

(`seedWalkWithTranscribedRecording()` mirrors the walk+recording seeding already used in `VoiceRecordingPersistenceTests.swift` — copy that file's helper shape.)

- [ ] **Step 2: Run to verify failure** (`-only-testing:UnitTests/DataManagerThreadsDeletionTests`). Expected: FAIL — context files survive deletion.

- [ ] **Step 3: Implement** — add the seam near the top of `DataManager`:

```swift
    /// Injection seam for tests; production always uses the shared store.
    static var transcriptContextStore: TranscriptContextStore = .shared
```

Then modify `deleteObject` — the transaction already collects `filePaths` from `editable._voiceRecordings.value` (line 911); collect UUIDs the same way and return both:

```swift
        dataStack.perform(asynchronous: { (transaction) -> ([String], [UUID]) in

            var filePaths: [String] = []
            var recordingUUIDs: [UUID] = []
            if let walk = object as? Walk,
               let editable = transaction.edit(walk) {
                filePaths = editable._voiceRecordings.value.compactMap { $0._fileRelativePath.value }
                recordingUUIDs = editable._voiceRecordings.value.compactMap { $0._uuid.value }
            }
            transaction.delete(object)
            return (filePaths, recordingUUIDs)

        }) { (result) in
            switch result {
            case .success(let (filePaths, recordingUUIDs)):
                cleanupRecordingFiles(relativePaths: filePaths)
                transcriptContextStore.delete(recordingUUIDs: recordingUUIDs)
                if let uuid = walkUUID {
                    UserPreferences.unmarkWalkArchived(uuid: uuid)
                }
                completion(true, nil)
            case .failure(let error):
                completion(false, .databaseError(error: error))
            }
        }
```

And `deleteAll` — in the `.success` branch (line 956), after `cleanupRecordingFiles`:

```swift
                transcriptContextStore.deleteAll()
```

Both calls sit in the transaction-success completion, preserving the Data Safety rule (never remove derived artifacts unless the database transaction committed — the same discipline as `cleanupRecordingFiles`).

- [ ] **Step 4: Run the test — PASS** (then the full UnitTests suite, same command as Task 7 Step 7).

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Data/DataManager.swift UnitTests/DataManagerThreadsDeletionTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(threads): deletion removes transcript contexts — single delete and Delete All Data"
```

---

### Task 9: ThreadStore — cross-walk aggregation

**Files:**
- Create: `Pilgrim/Models/Threads/ThreadStore.swift`
- Modify: `Pilgrim/Models/Data/DataManager.swift` (add `voiceRecordingWalkIndex()` helper next to `transcribedRecordingsSnapshot()`)
- Test: `UnitTests/ThreadStoreTests.swift`

**Interfaces:**
- Consumes: `TranscriptContext` (Task 6), `Theme` (Task 5), `ThreadsBackfill.isComplete` (Task 7).
- Produces (used by Task 10 and the future Stage 3 plan):
  - `struct ThreadAppearance: Equatable` — `{ recordingUUID: UUID, walkUUID: UUID, date: Date, mentionCount: Int, salience: Double }`
  - `struct WalkThread: Equatable` — `{ lemma: String, displayTerm: String, appearances: [ThreadAppearance] }` (appearances date-ascending)
  - `enum ThreadStatus: Equatable` — `.firstTime`, `.recurring(walksInWindow: Int)`
  - `enum SalienceDirection: String` — `rising`, `steady`, `fading` (dossier-only, never UI)
  - `ThreadStore.build(contexts: [TranscriptContext], walks: [UUID: (walkUUID: UUID, date: Date)]) -> [WalkThread]`
  - `ThreadStore.status(of: WalkThread, atWalk: UUID, backfillComplete: Bool) -> ThreadStatus?` (nil when the thread isn't in that walk, or when an origin claim would be made pre-backfill)
  - `ThreadStore.salienceDirection(of: WalkThread) -> SalienceDirection?` (nil below 3 appearances)
  - `@MainActor DataManager.voiceRecordingWalkIndex() -> [UUID: (walkUUID: UUID, date: Date)]` (recording UUID → owning walk; CoreStore fetches assert main-thread — callers fetch on the main actor and pass the index into off-main work)

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Pilgrim

final class ThreadStoreTests: XCTestCase {

    private let base = DateFactory.makeDate(2024, 6, 1, 9, 0, 0)

    private func context(_ uuid: UUID, lemma: String, mentions: Int, words: Int = 200) -> TranscriptContext {
        TranscriptContext(
            schemaVersion: 1, recordingUUID: uuid, transcriptHash: "h",
            languageCode: "en", wordCount: words,
            themes: [Theme(
                lemma: lemma, displayTerm: lemma, mentionCount: mentions,
                salience: Double(mentions) / Double(words),
                mentions: Array(repeating: ThemeMention(start: 0, length: 4), count: mentions)
            )],
            markers: nil
        )
    }

    /// Three walks, ten days apart, all speaking of "move".
    private func fixture() -> (threads: [WalkThread], walkUUIDs: [UUID]) {
        let recordings = [UUID(), UUID(), UUID()]
        let walkUUIDs = [UUID(), UUID(), UUID()]
        let contexts = [
            context(recordings[0], lemma: "move", mentions: 3),
            context(recordings[1], lemma: "move", mentions: 4),
            context(recordings[2], lemma: "move", mentions: 2)
        ]
        var walks: [UUID: (walkUUID: UUID, date: Date)] = [:]
        for (i, rec) in recordings.enumerated() {
            walks[rec] = (walkUUIDs[i], base.addingTimeInterval(Double(i) * 10 * 86400))
        }
        return (ThreadStore.build(contexts: contexts, walks: walks), walkUUIDs)
    }

    func testBuild_groupsByLemmaSortedByDate() {
        let (threads, _) = fixture()
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].appearances.count, 3)
        XCTAssertEqual(threads[0].appearances.map(\.date), threads[0].appearances.map(\.date).sorted())
    }

    func testStatus_firstTimeOnlyWithFullHistoryAndBackfill() {
        let (threads, walkUUIDs) = fixture()
        XCTAssertEqual(ThreadStore.status(of: threads[0], atWalk: walkUUIDs[0], backfillComplete: true), .firstTime)
        XCTAssertNil(ThreadStore.status(of: threads[0], atWalk: walkUUIDs[0], backfillComplete: false),
                     "origin claims are suppressed until backfill completes")
    }

    func testStatus_windowAnchorsToViewedWalkNotToday() {
        let (threads, walkUUIDs) = fixture()
        XCTAssertEqual(
            ThreadStore.status(of: threads[0], atWalk: walkUUIDs[2], backfillComplete: true),
            .recurring(walksInWindow: 3),
            "all three walks fall within 30 days of walk 3's own date, regardless of when this test runs"
        )
    }

    func testStatus_gapBeyondHistoryIsStillNotFirstTime() {
        let recordings = [UUID(), UUID()]
        let walkUUIDs = [UUID(), UUID()]
        let contexts = [
            context(recordings[0], lemma: "father", mentions: 3),
            context(recordings[1], lemma: "father", mentions: 3)
        ]
        let walks: [UUID: (walkUUID: UUID, date: Date)] = [
            recordings[0]: (walkUUIDs[0], base),
            recordings[1]: (walkUUIDs[1], base.addingTimeInterval(45 * 86400))
        ]
        let threads = ThreadStore.build(contexts: contexts, walks: walks)
        XCTAssertEqual(
            ThreadStore.status(of: threads[0], atWalk: walkUUIDs[1], backfillComplete: true),
            .recurring(walksInWindow: 1),
            "a 45-day-old prior appearance means never 'first time', even though it is outside the window"
        )
    }

    func testSalienceDirection_fadingAndFloor() {
        let (threads, _) = fixture()
        XCTAssertEqual(ThreadStore.salienceDirection(of: threads[0]), .fading)
        let (two, _) = { () -> ([WalkThread], [UUID]) in
            let r = [UUID(), UUID()]; let w = [UUID(), UUID()]
            let c = [self.context(r[0], lemma: "x", mentions: 3), self.context(r[1], lemma: "x", mentions: 3)]
            let map: [UUID: (walkUUID: UUID, date: Date)] = [
                r[0]: (w[0], self.base), r[1]: (w[1], self.base.addingTimeInterval(86400))
            ]
            return (ThreadStore.build(contexts: c, walks: map), w)
        }()
        XCTAssertNil(ThreadStore.salienceDirection(of: two[0]), "trend inference needs at least 3 points")
    }
}
```

- [ ] **Step 2: Run to verify failure** (`-only-testing:UnitTests/ThreadStoreTests`).

- [ ] **Step 3: Implement**

```swift
import Foundation

struct ThreadAppearance: Equatable {
    let recordingUUID: UUID
    let walkUUID: UUID
    let date: Date
    let mentionCount: Int
    let salience: Double
}

struct WalkThread: Equatable {
    let lemma: String
    let displayTerm: String
    let appearances: [ThreadAppearance]
}

enum ThreadStatus: Equatable {
    case firstTime
    case recurring(walksInWindow: Int)
}

/// Dossier-only: a trend fitted to few noisy points never reaches UI
/// (spec principle 1).
enum SalienceDirection: String {
    case rising, steady, fading
}

enum ThreadStore {

    static let recurrenceWindow: TimeInterval = 30 * 86400
    static let directionFloor = 3
    static let directionThreshold = 0.25

    static func build(
        contexts: [TranscriptContext],
        walks: [UUID: (walkUUID: UUID, date: Date)]
    ) -> [WalkThread] {
        var appearancesByLemma: [String: [ThreadAppearance]] = [:]
        var displayCounts: [String: [String: Int]] = [:]

        for context in contexts {
            guard let walk = walks[context.recordingUUID] else { continue }
            for theme in context.themes {
                appearancesByLemma[theme.lemma, default: []].append(ThreadAppearance(
                    recordingUUID: context.recordingUUID,
                    walkUUID: walk.walkUUID,
                    date: walk.date,
                    mentionCount: theme.mentionCount,
                    salience: theme.salience
                ))
                displayCounts[theme.lemma, default: [:]][theme.displayTerm, default: 0] += theme.mentionCount
            }
        }

        return appearancesByLemma
            .map { lemma, appearances in
                WalkThread(
                    lemma: lemma,
                    displayTerm: displayCounts[lemma]?
                        .min { ($0.value, $1.key) > ($1.value, $0.key) }?.key ?? lemma,
                    appearances: appearances.sorted { ($0.date, $0.recordingUUID.uuidString) < ($1.date, $1.recordingUUID.uuidString) }
                )
            }
            .sorted { $0.lemma < $1.lemma }
    }

    static func status(
        of thread: WalkThread,
        atWalk walkUUID: UUID,
        backfillComplete: Bool
    ) -> ThreadStatus? {
        guard let current = thread.appearances.first(where: { $0.walkUUID == walkUUID }) else { return nil }
        let earlier = thread.appearances.filter { $0.date < current.date && $0.walkUUID != walkUUID }
        if earlier.isEmpty {
            return backfillComplete ? .firstTime : nil
        }
        let windowStart = current.date.addingTimeInterval(-recurrenceWindow)
        let walksInWindow = Set(
            thread.appearances
                .filter { $0.date >= windowStart && $0.date <= current.date }
                .map(\.walkUUID)
        ).count
        return .recurring(walksInWindow: walksInWindow)
    }

    static func salienceDirection(of thread: WalkThread) -> SalienceDirection? {
        let saliences = thread.appearances.map(\.salience)
        guard saliences.count >= directionFloor else { return nil }
        let third = max(1, saliences.count / 3)
        let early = saliences.prefix(third).reduce(0, +) / Double(third)
        let late = saliences.suffix(third).reduce(0, +) / Double(third)
        guard early > 0 else { return .steady }
        let change = (late - early) / early
        if change >= directionThreshold { return .rising }
        if change <= -directionThreshold { return .fading }
        return .steady
    }
}
```

In `DataManager.swift`, next to `transcribedRecordingsSnapshot()`:

```swift
    /// Recording UUID → owning walk, for thread aggregation. The walk
    /// relationship on PilgrimV7.VoiceRecording is `_workout` — a frozen
    /// SQL identifier ("workout", PilgrimV7.swift:244) from the OutRun era;
    /// never rename the entity property to "fix" the name. Main-actor only:
    /// `dataStack.fetchAll` asserts Thread.isMainThread.
    @MainActor
    public static func voiceRecordingWalkIndex() -> [UUID: (walkUUID: UUID, date: Date)] {
        let recordings = (try? dataStack.fetchAll(From<VoiceRecording>())) ?? []
        var index: [UUID: (walkUUID: UUID, date: Date)] = [:]
        for recording in recordings {
            guard let uuid = recording._uuid.value,
                  let walk = recording._workout.value,
                  let walkUUID = walk._uuid.value,
                  let date = walk._startDate.value else { continue }
            index[uuid] = (walkUUID, date)
        }
        return index
    }
```

- [ ] **Step 4: Run tests — PASS.**
- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Threads/ThreadStore.swift Pilgrim/Models/Data/DataManager.swift UnitTests/ThreadStoreTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(threads): ThreadStore — full-history first-time, walk-anchored window, dossier-only direction"
```

---

### Task 10: The dossier, the preference, the toggle

**Files:**
- Create: `Pilgrim/Models/Threads/ThreadsDossierFormatter.swift`
- Create: `Pilgrim/Models/Threads/ThreadsDossierBuilder.swift`
- Modify: `Pilgrim/Models/Preferences/UserPreferences.swift:94` (add preference next to `autoTranscribe`)
- Modify: `Pilgrim/Models/Prompt/ActivityContext.swift` (add `threadsDossier: String?` field + `make` default)
- Modify: `Pilgrim/Models/Prompt/PromptAssembler.swift` (append dossier section; handling note in `responseContract`)
- Modify: `Pilgrim/Scenes/Prompts/PromptListView.swift:117-182` (`buildActivityContext` passes the built dossier)
- Modify: `Pilgrim/Scenes/Settings/SettingsCards/VoiceCard.swift` (toggle row)
- Test: `UnitTests/ThreadsDossierTests.swift`

**Interfaces:**
- Consumes: Tasks 4, 6, 7, 9.
- Produces:
  - `UserPreferences.threadsAfterWalks` — `UserPreference.Required<Bool>(key: "threadsAfterWalks", defaultValue: true)`
  - `ThreadsDossierFormatter.dossier(currentRecordingContexts:allContexts:threads:currentWalkUUID:backfillComplete:) -> String?`
  - `ThreadsDossierFormatter.personalBaseline(from: [TranscriptContext]) -> (absolutist: Double, firstPerson: Double)?` (nil below 5 recordings of ≥100 words)
  - `ThreadsDossierBuilder.build(walkUUID: UUID, recordings: [RecordingContext], walkIndex: [UUID: (walkUUID: UUID, date: Date)], store: TranscriptContextStore = .shared) -> String?` (nil when toggle off or no recordings; callable off-main — the caller fetches the walk index on the main actor; results memoized per `store.changeCount`)
  - `RecordingContext` gains `var recordingUUID: UUID? = nil` (defaulted last property — every existing construction site compiles unchanged)
  - `ActivityContext.threadsDossier: String?` (default nil — existing call sites unaffected)

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Pilgrim

final class ThreadsDossierTests: XCTestCase {

    private func markers(words: Int, absolutist: Int) -> MarkerPack {
        MarkerPack(
            wordCount: words, absolutistCount: absolutist, firstPersonCount: 5,
            insightCount: 2, causationCount: 1, discrepancyCount: 1,
            futureCount: 4, pastCount: 1, sentiment: -0.2
        )
    }

    private func context(words: Int, absolutist: Int) -> TranscriptContext {
        TranscriptContext(
            schemaVersion: 1, recordingUUID: UUID(), transcriptHash: "h",
            languageCode: "en", wordCount: words, themes: [],
            markers: markers(words: words, absolutist: absolutist)
        )
    }

    func testDensitiesOnlyAtFloor_smallSampleGetsRawCounts() {
        let small = context(words: 40, absolutist: 2)
        let line = ThreadsDossierFormatter.markerLine(for: small, baseline: nil)
        XCTAssertTrue(line.contains("40 words"))
        XCTAssertTrue(line.contains("small sample"))
        XCTAssertFalse(line.contains("%"))

        let large = context(words: 400, absolutist: 8)
        let largeLine = ThreadsDossierFormatter.markerLine(for: large, baseline: nil)
        XCTAssertTrue(largeLine.contains("%"))
        XCTAssertTrue(largeLine.contains("400 words"))
    }

    func testPersonalBaseline_needsFiveQualifyingRecordings() {
        let four = (0..<4).map { _ in context(words: 200, absolutist: 2) }
        XCTAssertNil(ThreadsDossierFormatter.personalBaseline(from: four))
        let five = four + [context(words: 200, absolutist: 2)]
        XCTAssertNotNil(ThreadsDossierFormatter.personalBaseline(from: five))
    }

    func testBaselineComparison_usesWalkersOwnHistory() {
        let history = (0..<5).map { _ in context(words: 200, absolutist: 2) }  // 1% baseline
        let baseline = ThreadsDossierFormatter.personalBaseline(from: history)!
        let today = context(words: 200, absolutist: 6)  // 3%
        let line = ThreadsDossierFormatter.markerLine(for: today, baseline: baseline)
        XCTAssertTrue(line.contains("your usual"))
    }

    func testBuilder_toggleOffReturnsNil() {
        let saved = UserPreferences.threadsAfterWalks.value
        defer { UserPreferences.threadsAfterWalks.value = saved }
        UserPreferences.threadsAfterWalks.value = false

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DossierBuilderTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = RecordingContext(
            text: String(repeating: "the move keeps returning to me today ", count: 6),
            timestamp: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            startCoordinate: nil, endCoordinate: nil, wordsPerMinute: nil,
            recordingUUID: UUID()
        )
        XCTAssertNil(ThreadsDossierBuilder.build(
            walkUUID: UUID(), recordings: [recording], walkIndex: [:],
            store: TranscriptContextStore(directory: directory)
        ), "off means off everywhere — no dossier, no analysis surfaced")
    }

    func testBuilder_toggleOnBuildsAndPersistsFallback() {
        let saved = UserPreferences.threadsAfterWalks.value
        defer { UserPreferences.threadsAfterWalks.value = saved }
        UserPreferences.threadsAfterWalks.value = true

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DossierBuilderTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptContextStore(directory: directory)
        let uuid = UUID()
        let recording = RecordingContext(
            text: String(repeating: "the move keeps returning to me today ", count: 6),
            timestamp: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            startCoordinate: nil, endCoordinate: nil, wordsPerMinute: nil,
            recordingUUID: uuid
        )
        let dossier = ThreadsDossierBuilder.build(
            walkUUID: UUID(), recordings: [recording], walkIndex: [:], store: store
        )
        XCTAssertNotNil(dossier, "an empty store still yields marker profiles — the spec's degradation")
        XCTAssertTrue(dossier!.contains("Thought threads"))
        XCTAssertTrue(store.hasContext(for: uuid), "fallback analysis persists under the real UUID and self-heals")
    }

    func testDossierFormatter_originGatedOnBackfill() {
        let current = context(words: 200, absolutist: 2)
        let walkA = UUID(), walkB = UUID()
        let thread = WalkThread(
            lemma: "move", displayTerm: "move",
            appearances: [
                ThreadAppearance(recordingUUID: UUID(), walkUUID: walkA,
                                 date: DateFactory.makeDate(2024, 6, 1, 9, 0, 0),
                                 mentionCount: 3, salience: 0.02),
                ThreadAppearance(recordingUUID: current.recordingUUID, walkUUID: walkB,
                                 date: DateFactory.makeDate(2024, 6, 10, 9, 0, 0),
                                 mentionCount: 3, salience: 0.02)
            ]
        )
        let gated = ThreadsDossierFormatter.dossier(
            currentRecordingContexts: [current], allContexts: [current],
            threads: [thread], currentWalkUUID: walkB, backfillComplete: false
        )
        XCTAssertFalse(gated!.contains("first spoken"), "origin claims suppressed pre-backfill")
        let open = ThreadsDossierFormatter.dossier(
            currentRecordingContexts: [current], allContexts: [current],
            threads: [thread], currentWalkUUID: walkB, backfillComplete: true
        )
        XCTAssertTrue(open!.contains("first spoken"))
    }

    func testAssembler_omitsDossierWhenNil() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let prompt = PromptAssembler.assemble(
            context: ActivityContext.make(startDate: start),
            voice: PromptStyle.allCases[0].voice
        )
        XCTAssertFalse(prompt.contains("Thought threads"))
    }

    func testAssembler_includesDossierAndHandlingNote() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let context = ActivityContext.make(startDate: start, threadsDossier: "**Thought threads (on-device analysis):**\ntest")
        let prompt = PromptAssembler.assemble(context: context, voice: PromptStyle.allCases[0].voice)
        XCTAssertTrue(prompt.contains("Thought threads"))
        XCTAssertTrue(prompt.contains("not assessments"))
    }
}
```

(Adjust the `PromptVoice` acquisition idiom to match Task 3's finding. `ActivityContext.make` gains `threadsDossier: String? = nil` as its last parameter.)

- [ ] **Step 2: Run to verify failure** (`-only-testing:UnitTests/ThreadsDossierTests`).

- [ ] **Step 3: Implement the formatter**

```swift
import Foundation

enum ThreadsDossierFormatter {

    static let densityFloorWords = 100
    static let baselineFloorRecordings = 5

    static func markerLine(for context: TranscriptContext, baseline: (absolutist: Double, firstPerson: Double)?) -> String {
        guard let markers = context.markers else {
            return "Markers unavailable (non-English recording)."
        }
        var parts: [String] = []
        if markers.wordCount >= densityFloorWords {
            let absolutist = Double(markers.absolutistCount) / Double(markers.wordCount) * 100
            var absolutistPart = String(format: "absolutist words %.1f%% over %d words", absolutist, markers.wordCount)
            if let baseline {
                absolutistPart += String(format: " (your usual walking baseline ~%.1f%%)", baseline.absolutist * 100)
            }
            parts.append(absolutistPart)
            let firstPerson = Double(markers.firstPersonCount) / Double(markers.wordCount) * 100
            parts.append(String(format: "self-focus %.1f%%", firstPerson))
        } else {
            parts.append("\(markers.wordCount) words — small sample, raw counts only: \(markers.absolutistCount) absolutist, \(markers.firstPersonCount) self-focus")
        }
        parts.append("insight \(markers.insightCount), causation \(markers.causationCount), discrepancy \(markers.discrepancyCount)")
        parts.append("temporal lean: \(markers.temporalLean) (coarse heuristic)")
        if let sentiment = markers.sentiment {
            parts.append(String(format: "sentiment %.2f", sentiment))
        }
        return parts.joined(separator: "; ")
    }

    static func personalBaseline(from contexts: [TranscriptContext]) -> (absolutist: Double, firstPerson: Double)? {
        let qualifying = contexts.compactMap { context -> MarkerPack? in
            guard let markers = context.markers, markers.wordCount >= densityFloorWords else { return nil }
            return markers
        }
        guard qualifying.count >= baselineFloorRecordings else { return nil }
        let totalWords = qualifying.reduce(0) { $0 + $1.wordCount }
        guard totalWords > 0 else { return nil }
        return (
            absolutist: Double(qualifying.reduce(0) { $0 + $1.absolutistCount }) / Double(totalWords),
            firstPerson: Double(qualifying.reduce(0) { $0 + $1.firstPersonCount }) / Double(totalWords)
        )
    }

    static func dossier(
        currentRecordingContexts: [TranscriptContext],
        allContexts: [TranscriptContext],
        threads: [WalkThread],
        currentWalkUUID: UUID,
        backfillComplete: Bool
    ) -> String? {
        guard !currentRecordingContexts.isEmpty else { return nil }
        let baseline = personalBaseline(from: allContexts)

        var section = "**Thought threads (on-device linguistic analysis):**"
        for (index, context) in currentRecordingContexts.enumerated() {
            section += "\nRecording \(index + 1): \(markerLine(for: context, baseline: baseline))"
        }

        let activeThreads = threads.filter { thread in
            thread.appearances.contains { $0.walkUUID == currentWalkUUID }
        }
        if !activeThreads.isEmpty {
            section += "\n\n**Threads across recent walks:**"
            for thread in activeThreads {
                var line = "\n'\(thread.displayTerm)'"
                switch ThreadStore.status(of: thread, atWalk: currentWalkUUID, backfillComplete: backfillComplete) {
                case .firstTime:
                    line += " — first appearance in the record"
                case .recurring(let walks):
                    line += " — \(walks) walk\(walks == 1 ? "" : "s") in the last 30 days"
                case nil:
                    break
                }
                if let direction = ThreadStore.salienceDirection(of: thread) {
                    line += ", \(direction.rawValue) across appearances"
                }
                if let origin = thread.appearances.first, backfillComplete {
                    line += " (first spoken \(ContextFormatter.shortDateFormatter.string(from: origin.date)))"
                }
                section += line
            }
        }
        return section
    }
}
```

- [ ] **Step 4: Implement the builder**

```swift
import Foundation

/// Single insertion point for PromptListView. Callable off the main actor:
/// the CoreStore walk index is fetched by the caller on the main actor and
/// passed in; everything else is file I/O and pure computation. Results are
/// memoized against the store's changeCount so reopening the prompt screen
/// doesn't re-read the whole context directory.
enum ThreadsDossierBuilder {

    private static var memo: (changeCount: Int, walkUUID: UUID, dossier: String?)?

    static func build(
        walkUUID: UUID,
        recordings: [RecordingContext],
        walkIndex: [UUID: (walkUUID: UUID, date: Date)],
        store: TranscriptContextStore = .shared
    ) -> String? {
        guard UserPreferences.threadsAfterWalks.value, !recordings.isEmpty else { return nil }
        if let memo, memo.changeCount == store.changeCount, memo.walkUUID == walkUUID {
            return memo.dossier
        }

        store.pruneOrphans(keeping: Set(walkIndex.keys))

        let current = recordings.compactMap { recording -> TranscriptContext? in
            guard let uuid = recording.recordingUUID else { return nil }
            let hash = TranscriptContextStore.hash(of: recording.text)
            if let stored = store.context(for: uuid, matching: hash) { return stored }
            // Lazy-backfill fallback, persisted under the real UUID so the
            // store self-heals instead of re-analyzing on every open. Also
            // covers edited transcripts whose stored hash no longer matches.
            return TranscriptContextAnalyzer.analyzeAndStore(
                recordingUUID: uuid, transcript: recording.text, store: store
            )
        }
        guard !current.isEmpty else { return nil }

        let all = store.loadAll()
        let threads = ThreadStore.build(contexts: all, walks: walkIndex)
        let dossier = ThreadsDossierFormatter.dossier(
            currentRecordingContexts: current,
            allContexts: all,
            threads: threads,
            currentWalkUUID: walkUUID,
            backfillComplete: ThreadsBackfill.isComplete
        )
        memo = (store.changeCount, walkUUID, dossier)
        return dossier
    }
}
```

- [ ] **Step 5: Wire preference, context, assembler, view, toggle**

1. `UserPreferences.swift` line 94, below `autoTranscribe`:
   ```swift
   static let threadsAfterWalks = UserPreference.Required<Bool>(key: "threadsAfterWalks", defaultValue: true)
   ```
2. `ActivityContext`: add `let threadsDossier: String?` to the struct and `threadsDossier: String? = nil` to `make`, passing it through.
3. `PromptAssembler.walkRecord`: after the recent-walks section, before directives:
   ```swift
           if let dossier = context.threadsDossier {
               sections += "\n\n\(dossier)"
           }
   ```
   `PromptAssembler.responseContract` needs to know a dossier exists — change its signature to `responseContract(voice:hasSpeech:hasThreadsDossier:)` (update the one `assemble` call site and any test callers) and append when true:
   ```swift
           if hasThreadsDossier {
               lines.append("The thought-thread marker profiles are descriptive on-device linguistic signals, not assessments — interpret them gently, never produce clinical or diagnostic language, and never treat a single walk's numbers as meaningful on their own.")
           }
   ```
4. `RecordingContext` (Pilgrim/Models/Prompt/PromptContextTypes.swift): append `var recordingUUID: UUID? = nil` as the last property — defaulted, so every existing construction site (including test helpers) compiles unchanged. In `PromptListView.buildActivityContext` (:117-182) populate it from the recording's uuid already unwrapped there (PromptListView.swift:122 — the UUID is in hand; never match by content hash). Then, inside generatePrompts' existing background Task, fetch the walk index on the main actor and build off it:

```swift
        let walkIndex = await MainActor.run { DataManager.voiceRecordingWalkIndex() }
        let threadsDossier = walk.uuid.flatMap {
            ThreadsDossierBuilder.build(walkUUID: $0, recordings: recordings, walkIndex: walkIndex)
        }
```

and pass `threadsDossier` into the `ActivityContext` construction.
5. `VoiceCard.swift`: add `@State private var threadsAfterWalks = UserPreferences.threadsAfterWalks.value` (line 8) and, below the Auto-transcribe toggle (line 48):
   ```swift
               settingToggle(
                   label: "Thought Threads",
                   description: "Weave recurring themes from your recordings into AI prompts",
                   isOn: $threadsAfterWalks
               ) { newValue in
                   UserPreferences.threadsAfterWalks.value = newValue
               }
   ```

- [ ] **Step 6: Run the full UnitTests suite — PASS** (existing prompt tests must be untouched by the nil-default dossier; if `responseContract` has direct test callers, update their signatures).

- [ ] **Step 7: Commit**

```bash
git add Pilgrim/Models/Threads/ThreadsDossierFormatter.swift Pilgrim/Models/Threads/ThreadsDossierBuilder.swift Pilgrim/Models/Preferences/UserPreferences.swift Pilgrim/Models/Prompt/ActivityContext.swift Pilgrim/Models/Prompt/PromptAssembler.swift Pilgrim/Scenes/Prompts/PromptListView.swift Pilgrim/Scenes/Settings/SettingsCards/VoiceCard.swift UnitTests/ThreadsDossierTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(threads): the dossier — marker profiles with personal baselines, thread trajectories, one honest toggle"
```

---

### Task 11: Field-gate harness and checkpoint

**Files:**
- Create: `UnitTests/FieldGateReportTests.swift`

**Interfaces:**
- Consumes: Tasks 5, 7, 9, 10.
- Produces: a printable report for the human field gate; no production code.

- [ ] **Step 1: Write the harness** (this test always passes — its product is the printed report):

```swift
import XCTest
@testable import Pilgrim

/// Not a correctness test — a harness for the spec's field gate between
/// Stages 2 and 3. Prints the analyzer's real output over representative
/// walk monologues so a human can judge theme quality before any card UI
/// is planned. Extend `fixtures` with real dogfood transcripts (pasted
/// locally, never committed) when running the gate for real.
final class FieldGateReportTests: XCTestCase {

    private let fixtures: [String] = [
        "Still circling the move today. If the move happens in fall we lose the garden, and moving means telling her father before the holidays. I keep rehearsing that conversation on every hill.",
        "Dad called last night. He sounded smaller. I noticed I talk about him in the past tense already and I hate that. The river was loud today and I let it be louder than the thought.",
        "Work again. The deadline moved twice and I said yes twice. I should have said something real. Next walk I want to figure out what saying something real would even sound like.",
        "Nothing much today. Cold hands. A dog followed me half a kilometer. I named him Bruno in my head and felt better than I have all week.",
        "I realized on the bridge that the move and dad are the same worry wearing two coats. If we go, who sits with him on Sundays? That is the whole question under everything."
    ]

    func testPrintFieldGateReport() {
        var report = "\n===== THOUGHT THREADS FIELD GATE REPORT =====\n"
        var contexts: [TranscriptContext] = []
        var walks: [UUID: (walkUUID: UUID, date: Date)] = [:]
        let base = DateFactory.makeDate(2024, 6, 1, 9, 0, 0)

        for (index, transcript) in fixtures.enumerated() {
            let context = TranscriptContextAnalyzer.analyze(
                recordingUUID: UUID(), transcript: transcript, flaggedFragments: []
            )
            contexts.append(context)
            walks[context.recordingUUID] = (UUID(), base.addingTimeInterval(Double(index) * 3 * 86400))
            report += "\nWalk \(index + 1) themes: "
            report += context.themes.map { "\($0.displayTerm) (\($0.mentionCount)×)" }.joined(separator: ", ")
            report += "\n  markers: \(ThreadsDossierFormatter.markerLine(for: context, baseline: nil))\n"
        }

        let threads = ThreadStore.build(contexts: contexts, walks: walks)
        report += "\nThreads across the corpus:\n"
        for thread in threads where thread.appearances.count >= 2 {
            report += "  '\(thread.displayTerm)' — \(thread.appearances.count) appearances\n"
        }
        report += "=============================================\n"
        print(report)
        XCTAssertFalse(contexts.isEmpty)
    }
}
```

- [ ] **Step 2: Run it and read the output** (`-only-testing:UnitTests/FieldGateReportTests`, drop the `| tail -20` so the report is visible). Expected: PASS, with a legible report.

- [ ] **Step 3: Commit**

```bash
git add UnitTests/FieldGateReportTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(threads): field-gate harness — the analyzer must earn the card"
```

- [ ] **Step 4: CHECKPOINT — the human field gate (do not proceed to any Stage 3 work).** Per the spec, the gate requires, with the feature's creator:
  1. Replace/extend the harness fixtures locally with real walk transcripts (the creator's own device data; never commit them) plus the demo-mode Camino transcripts, and re-run the report.
  2. Human-rate the surfaced themes: at least 3 of 4 judged recognizable and meaningful by the walker who spoke them. Tune `ThemeExtractor.walkingDomain` and thresholds here if not.
  3. Generate real prompts with the dossier on-device, paste representative ones (including elevated absolutist/self-focus profiles) into ChatGPT and Claude, and iterate the handling note until no response contains clinical or diagnostic language.
  4. Record the outcomes in the spec's Deferred/Open Questions section (including the categorical-marker value question parked there).
  Only after this gate passes: write the Stage 3 plan (card + thread view) with the copy and thresholds the gate produced.

---

## Verification (whole plan)

- [ ] Full suite: `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5` — PASS.
- [ ] Full-repo SwiftLint before pushing (pre-commit only checks staged files).
- [ ] Grep gate: `grep -rn "TranscriptContext\|MarkerPack\|WalkThread" Pilgrim/Models/Share/ Pilgrim/Models/Data/PilgrimPackage/` returns nothing — derived data stays out of shares and exports.
- [ ] Manual smoke on simulator: record → transcribe → open AI Prompts with the toggle on (dossier present) and off (prompt byte-identical to pre-feature output).
