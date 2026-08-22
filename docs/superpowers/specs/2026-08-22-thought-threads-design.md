# Threads — Semantic Analysis of Walk Transcripts

**Date:** 2026-08-22
**Status:** Design approved, pending implementation planning
**Repos:** pilgrim-ios only (nothing leaves the device; worker/viewer untouched)

## Vision

Wearables track the outputs of a life — steps, heart rate, sleep. Pilgrim
already captures the inputs: the thoughts a walker speaks aloud while moving,
transcribed on-device, anchored to place, pace, weather, and intention. This
feature listens to those transcripts the way a good walking companion would —
noticing what keeps coming up, what has just appeared, what is quietly fading —
and gives that noticing back in two forms: a far richer dossier for the
walker's own AI reflection prompts, and a quiet card after the walk that names
the themes that walked with them.

Themes, not scores. The app describes; it never evaluates. Every surfaced
theme traces back to the walker's own spoken words, one tap away. Nothing —
not a transcript, not a derived category — ever leaves the device.

The feature is named by what it finds: **Threads**.

## Design principles

1. **Descriptive, never evaluative.** No metric numbers, gauges,
   trends-with-arrows, or wellbeing language anywhere in the UI (dates and
   ordinal words like "third walk" are fine; densities and scores are not). "'the move' — third walk now" is
   allowed; "your negativity rose 12%" is not, in any form, ever. Research on
   mood-tracking apps is unambiguous: identical data framed evaluatively turns
   a reflective tool into a judgment machine.
2. **Every insight is traceable.** The single most-cited user complaint about
   AI journaling apps is opaque inference. Any theme Pilgrim names must open
   into the exact transcript excerpts that formed it. If we can't show the
   words, we don't show the theme.
3. **Rich for the AI, spare for the walker.** The prompt dossier gets maximal
   detail — raw densities with baselines, per-recording profiles, thread
   trajectories — because a capable LLM interprets nuance responsibly and the
   walker chose that conversation. The card gets two to four theme words and
   one texture sentence. Same analysis, two very different renderings.
4. **The journal is untouched.** The journal stays contemplative. The card
   lives in the post-walk summary; the cross-walk thread view is pulled by a
   tap, never pushed. No persistent analysis surface exists anywhere.
5. **On-device, invisible to the network, invisible to the schema.** Analysis
   runs in the NaturalLanguage framework on-device. Derived data is a
   recomputable cache — no CoreStore migration, nothing in `SharePayload`,
   nothing in any export. `TourBuilder`'s `transcription: nil` promise extends
   to every derived signal.
6. **Multilingual by degradation, not by pretense.** The prompt pipeline is
   multilingual by design. Theme extraction works wherever Apple ships
   lemmatization/embeddings for the detected language; the English-validated
   marker lexicons switch off silently for other languages rather than
   producing garbage.

## What we analyze

### Themes (all languages with NL support)

Recurring content-word clusters across a walk's recordings and across recent
walks. Built from `NLTagger` lemmatization (grief/grieving/grieved unify) +
part-of-speech filtering (nouns, verbs, adjectives — replaces the current
hardcoded English stopword list), clustered with `NLEmbedding` word similarity
so near-synonyms join a thread. Deterministic: same transcripts, same themes,
with tie-breaks matching the existing `recurringWord` convention.

### The marker pack (English-only v1, gated on `NLLanguageRecognizer`)

Small embedded lexicons and counts — no dependencies, no network:

| Marker | Source | Notes |
|---|---|---|
| Absolutist-word density | 19-word dictionary from Al-Mosaiwi & Johnstone 2018 (open-access; copy Table 1 verbatim at implementation) | Best-replicated linguistic marker in the literature; ~1% baseline prevalence |
| First-person-singular density | Simple pronoun count | Classic self-focus marker |
| Cognitive-process words | Hand-built mini-lexicons (~15–25 words each): insight ("realize", "understand"), causation ("because", "hence"), discrepancy ("should", "could have") | Tracks meaning-making — the most hopeful signal for a reflective app |
| Temporal orientation | Tense/modal patterns via `NLTagger` | Past / present / future lean |
| Sentiment | `NLTagger.sentimentScore` | Coarse; prompt-side only, never user-facing |
| Speaking pace | Existing `wordsPerMinute` + `speakingPaceLabel` buckets | Already shipped |

**Licensing boundaries (hard):** LIWC dictionaries are proprietary — we use
published findings, never their word lists. NRC lexicons require a commercial
license — excluded. Empath is MIT — a handful of its topic lexicons may seed
theme clusters. The absolutist dictionary is published in an open-access paper.

## Architecture — three stages

### Stage 1 — Semantic prompt upgrade (`AttentionDirectives` v2)

Upgrade the existing pure function in place; no new UI, no storage.

- `contentWords`: `NLTagger` lemmatization + POS filtering replaces the
  38-word English stoplist. Works in any language NL supports.
- `recurringWord`: counts lemmas, not surface forms.
- `intentionEcho`: lemma match OR `NLEmbedding` word-similarity above a fixed
  threshold — "grief" now echoes "grieving", "the move" echoes "moving house".
- `NLLanguageRecognizer` gates language-specific behavior.
- The 4-directive cap and deterministic tie-breaks stay.
- `UnitTests/AttentionDirectivesTests.swift` extends to cover lemmatization,
  paraphrase echo, and non-English gating.

### Stage 2 — `TranscriptContextAnalyzer` + thread aggregation + rich dossier

A new analyzer mirroring `PhotoContextAnalyzer`'s blessed shape
(on-device framework → `Codable` struct → cache → prompt section).

**`TranscriptContext`** (per recording): detected language, word count,
themes (lemma, display term, salience), full marker pack, and the character
ranges of each theme's mentions (for excerpt display later).

**Trigger:** immediately after `persistTranscription` succeeds in
`TranscriptionService` — text already in memory, off the main actor, before
the WhisperKit model-unload boundary. Lazy backfill when a walk summary opens
with transcribed-but-unanalyzed recordings.

**Storage:** cache keyed by `VoiceRecording.uuid` + a hash of the transcript
text (transcripts are inline-editable in two places — hash mismatch triggers
recompute). Follows the `PhotoContextAnalyzer` UserDefaults-cache pattern.
Deliberately **not** a `PilgrimV8` schema attribute: derived data is
recomputable, and this avoids a forward-only migration entirely. Recordings
shorter than 25 words are skipped (below theme reliability; the existing
`TourBuilder` ambient threshold is 8).

**`ThreadStore`** (compute-on-demand aggregator): scans cached contexts for
recent walks and builds threads — theme → chronological appearances (walk,
date, place, excerpt range). Card status is computed over a trailing 30-day
window: *first time* (no prior appearance), *nth walk* (recurring), *fading*
(present but salience declining vs. prior walks). The thread detail view uses
full history. Aggregation is cheap and cached in memory only.

**Prompt dossier — the maximal rendering.** New sections in `PromptAssembler`:

- Per-recording marker profiles with baselines the AI can calibrate against
  (e.g. "absolutist words 3.1% — typical conversational baseline ~1%"),
  temporal lean, insight/causation/discrepancy counts, sentiment, pace.
- Thread trajectories: each active thread with dates, places, and salience
  direction ("'the move' — first spoken Aug 9 river loop, rising since").
- Cross-signal correlations the app can compute but should never editorialize
  on-screen: themes vs. pace ("spoke slowest when 'my father' arose"), themes
  vs. place, intention-echo strength.
- Attention directives gain thread awareness ("'the move' has recurred across
  three walks — attend to how it has changed").
- A handling note in the response contract: markers are descriptive signals,
  not diagnoses; interpret gently and never produce clinical language.

### Stage 3 — "What walked with you" card + thread view

**Card** in `WalkSummaryView`, directly below the intention card, same
parchment visual language, `Constants.Typography.*` throughout. Appears only
when at least one recording is transcribed and at least one theme was found;
otherwise the summary is pixel-identical to today.

- Two to four theme words, each with one soft status note
  (*first time* / *third walk now* / *fading*).
- One texture line composed from the safe markers only — pace, temporal lean,
  insight words: "Spoken slowly, leaning future, insight rising." Maximum
  three clauses; weak signals are omitted; whole line omitted if nothing
  clears threshold. Absolutist and pronoun densities never appear here — they
  live in the prompt dossier only.
- Deterministic template copy — no generation, no numbers.

**Thread view**, pushed on theme tap: the theme's full history, newest first —
date, place name, and a short transcript excerpt centered on the mention, each
excerpt tapping through to that walk's summary. The oldest entry is labeled
"where it began."

**Settings:** one toggle, "Threads after walks" (default on), hiding the card
and thread navigation. Analysis itself rides the existing transcription
consent — transcription is user-initiated (`autoTranscribe` defaults off), and
analysis is a property of a transcript the walker already chose to create.

## Data flow

```
voice recording (.m4a on disk)
  → WhisperKit transcription (existing)
  → CoreStore VoiceRecording.transcription (existing)
  → TranscriptContextAnalyzer (NLTagger / NLEmbedding + lexicons)
  → cache [uuid + transcript-hash → TranscriptContext]
      ├→ PromptAssembler dossier sections (Stage 2)
      ├→ AttentionDirectives thread awareness (Stages 1–2)
      └→ ThreadStore aggregation
           ├→ "What walked with you" card (Stage 3)
           └→ Thread view (Stage 3)
```

Nothing in this graph touches the network, `SharePayload`, `.pilgrim` export,
or the schema.

## Error handling

- Analyzer failure is silent: no card, prompts render exactly as today.
  The feature can only add; it can never block a summary or a prompt.
- Unsupported language: themes degrade to lemma-frequency (or off, if no
  lemmatizer); markers and texture line switch off; prompts note the detected
  language as they already do.
- Edited transcript: hash mismatch → recompute on next access.
- Deleted recordings/walks: cache entries orphaned by deletion are pruned
  opportunistically on analyzer runs (mirrors photo-context cache hygiene).

## Testing

- Fixture-text unit tests per lexicon (known densities in, exact counts out).
- Lemmatization unification (grief/grieving), paraphrase intention echo,
  non-English gating, sub-25-word skip.
- ThreadStore: status transitions (first time → recurring → fading) across a
  synthetic walk sequence; determinism (same walks in, same threads out).
- Hash invalidation on transcript edit.
- Prompt snapshot tests: dossier sections render with baselines; card copy
  template never emits metric digits (dates in the thread view excepted).
- Existing `AttentionDirectivesTests` extended, not replaced.

## Out of scope (parked deliberately)

- Moon-cycle / lunation recap (natural Stage 4; designed later, informed by
  what threads actually look like in the field).
- Any journal-page rendering of threads.
- Foundation Models on-device generation (the clipboard-prompt flow already
  delegates generation to the walker's chosen AI; revisit only if that flow
  changes).
- Any wellbeing score, alerting, streaks, or notifications tied to analysis.
- Threads in shares, exports, or the worker payload — permanently, not v1.

## Privacy & regulatory posture

Derived psychological categories are exactly the data the FTC's Health Breach
Notification Rule now reaches when they touch third parties. Pilgrim's answer
is structural: no analytics SDKs exist in the app, derived data never leaves
the device, and this design adds no new `PrivacyInfo.xcprivacy` collected-data
types because nothing is collected. The card's descriptive-only copy keeps the
product outside mood-inference framing; the marker pack's clinical edge lives
only in the dossier the walker hand-carries to their own AI.
