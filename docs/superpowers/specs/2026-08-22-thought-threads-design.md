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
theme traces back to the walker's own spoken words, one tap away. The app
itself never transmits a transcript or a derived signal anywhere; the only
egress that exists is the walker deliberately copying a prompt and pasting
it into an AI they chose.

The feature is named by what it finds: **Thought Threads** ("Threads" as
internal shorthand only — the two-word user-facing name avoids reading as a
Meta social integration in Settings or release notes).

## Design principles

1. **Descriptive, never evaluative.** No metric numbers, gauges,
   trend-or-direction claims, or wellbeing language anywhere in the UI (dates
   and ordinal words like "third walk" are fine; densities, scores, and
   directional words like "rising" or "fading" are not — trajectory language
   lives exclusively in the AI prompt dossier). "'the move' — third walk now" is
   allowed; "your negativity rose 12%" is not, in any form, ever. Research on
   mood-tracking apps is unambiguous: identical data framed evaluatively turns
   a reflective tool into a judgment machine.
2. **Every insight is traceable.** The single most-cited user complaint about
   AI journaling apps is opaque inference. Any theme Pilgrim names — and any
   texture clause the card shows — must open into the exact transcript words
   that formed it, or derive mechanically from a measurement the walker can
   already see. If we can't show the words, we don't show the claim.
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
with tie-breaks matching the existing `recurringWord` convention. A
walking-domain suppression list (path, trail, hill, uphill, and similar
narration vocabulary) keeps the activity's own words from dominating every
thread; the list is tuned at the field gate below.

### The marker pack (English-only v1, gated on `NLLanguageRecognizer`)

Small embedded lexicons and counts — no dependencies, no network:

| Marker | Source | Notes |
|---|---|---|
| Absolutist-word density | 19-word dictionary from Al-Mosaiwi & Johnstone 2018 (open-access; copy Table 1 verbatim at implementation) | Well-replicated in written text; the published ~1% baseline is written-forum-derived — see marker reporting rules |
| First-person-singular density | Simple pronoun count | Classic self-focus marker |
| Cognitive-process words | Hand-built mini-lexicons (~15–25 words each): insight ("realize", "understand"), causation ("because", "hence"), discrepancy ("should", "could have") | Tracks meaning-making — the most hopeful signal for a reflective app |
| Temporal orientation | Hand-built heuristic: modal/auxiliary word lists ("will", "going to" vs. "was", "did") plus lemma-vs-surface inflection comparison — `NLTagger` exposes no tense scheme | Past / present / future lean; the dossier labels it a coarse heuristic |
| Sentiment | `NLTagger.sentimentScore` | Coarse; prompt-side only, never user-facing |
| Speaking pace | Existing `wordsPerMinute` + `speakingPaceLabel` buckets | Already shipped |

**Marker reporting rules.** Densities are only meaningful over enough words:
densities with baseline comparisons are reported only for recordings (or
walk-level aggregates) of at least ~100 words; below that the dossier emits
raw counts with an explicit small-sample note, and every density always
carries the word count it was computed over. Baselines are personal, not
literature-derived: once enough history exists, each density compares
against the walker's own rolling spoken-transcript baseline; the published
written-forum figures appear only as secondary context, labeled by register,
so the interpreting AI never reads a spoken-register number against a
written-text norm.

**Licensing boundaries (hard):** LIWC dictionaries are proprietary — we use
published findings, never their word lists. NRC lexicons require a commercial
license — excluded. Empath is MIT-licensed but out of v1 scope — themes are
fully specified via NLTagger + NLEmbedding; revisit Empath seeds only if the
field gate shows clustering needs help. The absolutist dictionary is
published in an open-access paper.

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
the WhisperKit model-unload boundary. Segments WhisperKit flags as low
quality (high no-speech probability, anomalous compression ratio — signals
it already exposes) are excluded before analysis, and a theme's thread
membership requires at least one mention in a non-flagged segment, so
wind-and-silence hallucinations cannot found a thread. When the feature
first activates, a one-time background backfill analyzes all existing
transcribed recordings; lazy backfill on summary-open remains as a fallback
for anything missed.

**Storage:** one JSON file per recording under
`Application Support/TranscriptContexts/`, named by `VoiceRecording.uuid`,
holding the `TranscriptContext` plus a hash of the transcript text it was
computed from (transcripts are inline-editable in two places — a hash
mismatch replaces the file on next access, so edits never strand stale
entries). Files are excluded from device backups (`isExcludedFromBackup`):
this is derived psychological data, not user content, and it is fully
recomputable. Deliberately **not** a `PilgrimV8` schema attribute and not
UserDefaults — no forward-only migration, and no unbounded blob growing
inside a plist that loads wholesale at launch once full thread history
accumulates for years. Recordings shorter than 25 words are skipped (below
theme reliability; the existing `TourBuilder` ambient threshold is 8).

**`ThreadStore`** (compute-on-demand aggregator): scans cached contexts and
builds threads — theme → chronological appearances (walk, date, place,
excerpt range). Card statuses make only claims the data can back: *first
time* is computed against the full analyzed history (has this theme ever
appeared, at all), and *nth walk* recurrence is counted over a trailing
30-day window anchored to the viewed walk's own date — never today's — so
an old walk's card reads the same whenever it is opened. Until the one-time
backfill completes, origin-claiming labels (*first time*, "where it began")
are suppressed rather than risked. Salience direction (rising, fading) is
computed but dossier-only — it is a trend inference over few noisy data
points and never appears in UI. The thread detail view uses full history.
Aggregation is cheap and cached in memory only.

**Prompt dossier — the maximal rendering.** New sections in `PromptAssembler`:

- Per-recording marker profiles with word counts and baselines the AI can
  calibrate against (e.g. "absolutist words 3.1% over 640 words — above your
  usual walking baseline of ~1.2%"), temporal lean (with its coarse-heuristic
  caveat), insight/causation/discrepancy counts, sentiment, pace.
- Thread trajectories: each active thread with dates, places, and salience
  direction ("'the move' — first spoken Aug 9 river loop, rising since").
- Cross-signal correlations the app can compute but should never editorialize
  on-screen: themes vs. pace ("spoke slowest when 'my father' arose"), themes
  vs. place, intention-echo strength.
- Attention directives gain thread awareness ("'the move' has recurred across
  three walks — attend to how it has changed").
- A handling note in the response contract: markers are descriptive signals,
  not diagnoses; interpret gently and never produce clinical language.

### The field gate between Stages 2 and 3

The card ships only after the analysis proves itself on real walks — the
same "informed by the field" standard already applied to Stage 4. Run the
analyzer over a dogfood corpus (the creator's real walk transcripts plus the
demo-mode Camino walks), human-rate surfaced themes against a stated bar (at
least 3 of 4 themes judged recognizable and meaningful by the walker who
spoke them), and tune the walking-domain suppression list there. In the same
gate, paste representative dossiers — including elevated absolutist and
self-focus profiles — into the major consumer LLMs and iterate the handling
note until none respond with clinical or diagnostic language. Card
thresholds and copy are finalized only after this gate passes.

### Stage 3 — "What walked with you" card + thread view

**Card** in `WalkSummaryView`, directly below the intention card, same
parchment visual language, `Constants.Typography.*` throughout. Appears only
when at least one recording is transcribed and at least one theme was found;
otherwise the summary is pixel-identical to today.

- Two to four theme words — the top themes ranked by salience descending,
  ties broken by the existing `recurringWord` convention — each with one
  soft status note (*first time* / *third walk now*). No directional
  statuses: rising/fading talk is dossier-only.
- One texture line of at most two clauses, state-only and traceable: pace
  ("spoken slowly" — derived mechanically from words-per-minute) and insight
  words ("with words of insight" — tapping reveals the exact words that
  earned the clause). Temporal lean is too diffuse to trace to specific
  words, so it never appears on the card. Weak signals are omitted; the
  whole line is omitted if nothing clears threshold. Absolutist and pronoun
  densities never appear here — they live in the prompt dossier only.
- Deterministic template copy — no generation, no numbers.
- Accessibility is specified, not assumed: theme chips wrap rather than
  truncate at large Dynamic Type sizes; each chip is a single VoiceOver
  element announcing the theme, its status, and "double tap to view
  history"; every chip meets the 44-point minimum touch target.

**Thread view**, pushed on theme tap: the theme's full history, newest first —
date, place name, and a short transcript excerpt centered on the mention, each
excerpt tapping through to that walk's summary. The oldest entry is labeled
"where it began."

**Settings:** one toggle, "Thought threads after walks" (default on). Off
means off everywhere: it hides the card and thread navigation AND suppresses
the marker-profile and thread-trajectory sections of the prompt dossier, so
prompts render exactly as today. The toggle's scope matches its label — a
walker who declines thought threads declines the psychological analysis, not
just its display. Baseline analysis still rides the existing transcription
consent (transcription is user-initiated; `autoTranscribe` defaults off),
but nothing derived from it surfaces anywhere while the toggle is off.

## Data flow

```
voice recording (.m4a on disk)
  → WhisperKit transcription (existing)
  → CoreStore VoiceRecording.transcription (existing)
  → TranscriptContextAnalyzer (NLTagger / NLEmbedding + lexicons)
  → file store [Application Support/TranscriptContexts/<uuid>.json]
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
- Low-quality transcription: segments WhisperKit flags (no-speech
  probability, compression ratio) are excluded from analysis; a thread never
  rests solely on flagged segments.
- Unsupported language: themes degrade to lemma-frequency (or off, if no
  lemmatizer); markers and texture line switch off; prompts gain a note of
  the detected language (new behavior via Stage 1's `NLLanguageRecognizer` —
  today the prompt only instructs the AI to respond in the walker's spoken
  language).
- Edited transcript: stored hash mismatch → recompute replaces the file in
  place; edits never accumulate stale entries.
- Deleted recordings/walks: deletion is the trigger, not luck — the
  `DataManager` deletion paths (single delete and Delete All Data) remove
  the corresponding context files directly, and `ThreadStore` aggregation
  passes additionally prune any orphan whose UUID no longer resolves. This
  is new hygiene, not mirrored: the photo-context cache has no pruning today
  (worth extending there too), and opportunistic pruning alone could never
  fire after Delete All Data removes every future analyzer run.

## Testing

- Fixture-text unit tests per lexicon (known densities in, exact counts out).
- Lemmatization unification (grief/grieving), paraphrase intention echo,
  non-English gating, sub-25-word skip.
- ThreadStore: *first time* computed against full history (a theme absent
  31+ days is never re-labeled first time); recurrence window anchored to the
  viewed walk's date, not today's; origin labels suppressed until backfill
  completes; salience direction present in dossier output but never in card
  copy; determinism (same walks in, same threads out).
- Marker floors: densities with baselines only at ≥100 words, raw counts
  plus small-sample note below; ASR-flagged segments excluded from themes.
- Hash invalidation on transcript edit; deletion removes context files,
  including the Delete All Data path.
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
is structural, and stated precisely: the app never transmits transcripts or
derived data — no analytics SDKs exist, nothing enters `SharePayload` or any
export, and this design adds no new `PrivacyInfo.xcprivacy` collected-data
types because nothing is collected. The one egress that exists is
user-initiated disclosure: the walker explicitly copies a prompt and pastes
it into an AI of their choosing, an act the app neither performs nor
automates. Marketing and App Store copy must use this precise form, never an
absolute "nothing ever leaves the device" claim. The card's descriptive-only
copy keeps the product outside mood-inference framing; the marker pack's
clinical edge lives only in that hand-carried dossier.

## Deferred / Open Questions

### From 2026-08-22 review

- Adoption reach: the card is visible only to walkers who record AND
  transcribe (`autoTranscribe` defaults off). Decide whether a summary with
  untranscribed recordings shows a quiet one-line invitation to transcribe.
- Categorical markers (insight/causation/discrepancy, temporal lean) may
  duplicate what a capable LLM infers from the raw transcript already in the
  dossier; the quantified densities are the clearer value-add. Revisit the
  pack's composition at the field gate if dossier quality shows no lift.
- Should the 30-day recurrence window adapt to walking cadence (a weekly
  walker's "recurring" is a daily walker's "fading")?
- Per-theme forget control: should a walker be able to exclude a specific
  thread (e.g. a person's name) from analysis, card, and dossier?
