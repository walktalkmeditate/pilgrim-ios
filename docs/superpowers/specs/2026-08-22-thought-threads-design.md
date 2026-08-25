# Threads — Semantic Analysis of Walk Transcripts

**Date:** 2026-08-22 (Stage 3+4 addendum 2026-08-24)
**Status:** Stages 1–2 shipped in v1.11.0 (PR #65). Field gate part 1 passed. Stage 3+4 design below, pending implementation planning.
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
hardcoded English stopword list). Thread identity is exact-lemma in v1 —
per-transcript `NLEmbedding` synonym clustering would split cross-walk
identity (a lemma merged away in one walk reads "first time" in the next),
so embedding-based merging is re-evaluated at the field gate with a
cross-walk-consistent design. Deterministic: same transcripts, same themes,
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
spoke them) — and, alongside them, intention-suggestion quality: do the
`ThreadIntentionSuggestions` chips read as intentions the walker would
actually choose to carry into a walk — and tune the walking-domain
suppression list there. In the same gate, paste representative dossiers —
including elevated absolutist and self-focus profiles — into the major
consumer LLMs and iterate the handling note until none respond with
clinical or diagnostic language. Card thresholds and copy are finalized
only after this gate passes.

### Intention suggestions from threads (any walk)

Independent of the Stage 3 card, `ThreadIntentionSuggestions` offers, never
claims, a small set of intention chips in `IntentionSettingView`, built from
the same `ThreadStore` aggregation the dossier uses. A thread only qualifies
once it has recurred across at least 2 distinct walks within the trailing 30
days (the same guardrail `ThreadStore` uses for "recurring" status), ranked
by distinct-walk count then alphabetically, and capped at 2 suggestions so
the walker is offered a nudge, not a list. Gated on `threadsAfterWalks`: off
means no chips, matching the toggle's "off means off everywhere" scope
already established for the dossier and backfill.

The surface works for any walk — a plain wander or a Seek alike. Seek seeds
its ritual from the walker's chosen intention, so a thread carried into a
Seek steers which clearings it can find: walk with what walks with you.
The engine ships live but the surface ships dark, behind the same field
gate as the card: `ThreadIntentionSuggestions.pendingFieldGate` (true as
shipped) is checked first in `current()`, so the chips section renders
nothing in production. The sensitivity call is that chips would be the
feature's first surface to render derived words unprompted — that, plus
their quality (do they read as intentions worth carrying, not just words
that recurred), is judged at the field gate above alongside the card's
themes, and the selection window and copy are tuned there like everything
else that gate touches. Enabling the surface after the gate passes means
flipping `pendingFieldGate` to false.

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
means off everywhere: it hides the card and thread navigation, suppresses
the marker-profile and thread-trajectory sections of the prompt dossier, AND
stops new analysis — the backfill sweep and the per-transcription trigger
both check the toggle before writing a context, so prompts render exactly as
today. The toggle's scope matches its label — a walker who declines thought
threads declines the psychological analysis, not just its display. Contexts
written before the toggle was turned off remain on disk, but nothing reads
or extends them while it's off; re-enabling resets the backfill so history
missed during the gap gets swept.

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

- ~~Moon-cycle / lunation recap~~ — promoted into the Stage 3+4 addendum
  below (2026-08-24), descriptive-only.
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
- ~~Per-theme forget control~~ — resolved 2026-08-24: committed into Stage 3
  as "Let this one go" (see addendum).

## Stage 3+4 addendum (2026-08-24) — post-field-gate

*Superseded in part by the Stage 3 field verdict below (2026-08-24): the card, thread view, recap, and release surfaces described here were removed after real-device contact.*

### Field gate outcomes

- **Theme quality: PASSED** on real dogfood walks (v1.11.0 TestFlight) — the
  walker judged surfaced themes recognizable and meaningful. Engine
  thresholds stand as shipped (`minimumMentions = 2`, exact-lemma identity,
  current suppression list).
- **Chips: cleared to ship.** `ThreadIntentionSuggestions.pendingFieldGate`
  flips to `false` in the Stage 3 release. Judge the section header copy
  ("Recurring" vs. a softer variant) against real chip words during
  implementation review.
- **LLM-readback QA: PENDING — a RELEASE gate, not a build gate.** Before
  the Stage 3 release (1.12.0) is submitted anywhere beyond internal
  TestFlight: paste representative real dossiers (including elevated marker
  profiles) into the major consumer LLMs and iterate the handling note until
  no response contains clinical or diagnostic language.

### Let this one go (committed — ships with the card)

A walker can release a thread. Long-press a theme (on the card or in the
thread view) → a gentle confirm that leads with reversibility — "Let 'my
father' go? You can welcome it back anytime." → the theme joins a persisted
released set. Release acts on the display term's full lemma cohort (every
lemma currently sharing that display term — two lemmas can share one, e.g.
move/moving → "the move"), and welcome-back restores the cohort atomically.

**Where filtering actually lives** (verified against the call graph):
`ThreadStore.build` drops released lemmas — covering the card, thread view,
dossier trajectories, quiet-this-walk lines, intention chips, and the recap
— **plus** a released-lemma skip inside `AttentionDirectives.recurringWord`
(the next-ranked candidate is promoted), which is the one surfacing path
that bypasses ThreadStore. `intentionEcho` is deliberately exempt: it only
quotes words from the walker's own stated intention — walker-authored, not
app-noticed. The released set carries its own change token, folded into the
dossier-builder and suggestions memo keys so a release is visible on the
very next prompt or sheet open.

Lifecycle: releases are walker decisions, not derived analysis — they ride
in the `.pilgrim` preferences block (a scoped carve-out from the
no-derived-data-in-exports rule, alongside `zodiacSystem` precedent; the
lemmas already appear verbatim in exported transcripts) and Delete All Data
clears the set with everything else. Analysis and stored contexts are
untouched by release, so it is fully reversible.

Interaction states: if a release empties the card while the summary is on
screen, the card fades out and the summary reflows to its no-card state;
the thread view pops to the previous screen if its own theme is released
mid-view. Long-press gains a one-time dismissible caption on first card
appearance ("long-press a theme to let it go") and each theme chip exposes
a "Let this go" VoiceOver custom action — gesture parity, not
gesture-only. The Settings "Released threads" row is hidden when empty;
tapping an entry confirms "Welcome 'my father' back? Threads will notice
it again." Releasing is wabi-sabi, not deletion — the words remain in
their transcripts; the app simply stops noticing.

### Return to where it began (committed — ships with the thread view)

The thread view's oldest entry gains one quiet action: open the origin
walk's map — the existing historical summary map, static and read-only, no
live-walk controls — centered on where the thread first found words. The
walk and coordinate resolve at tap time (the route sample nearest the
recording's start within a stated tolerance); on any failure — deleted
walk, no route fix near that moment — the action simply doesn't render.
Origin claims are claims about the record: if a walker deletes the origin
walk, the record's earliest surviving appearance becomes "where it began,"
because deletion is deliberate record-editing, consistent with how origin
labels already work against analyzed history.

### The lunation recap (Stage 4, pulled forward — descriptive-only)

When a lunation closes (`LunarPhase` boundaries; the moon's name derives
from the calendar month of its full-moon instant in the device's current
timezone — implementation adds the month-moon name table `LunarPhase`
lacks), summaries of walks **dated after the boundary** may carry one quiet
invitation line — "The Sturgeon Moon has set — see what walked with you."
— which opens the recap sheet. Pulled, never pushed; never on historical
walk summaries (old summaries read the same whenever opened); the journal
stays untouched.

**First-exposure gate:** recap eligibility begins only after the walker's
first per-walk card has been shown (persisted marker). Lunation boundaries
that closed inside backfilled history never invite — the recap must never
be a walker's first contact with the feature; the card shows its work one
walk at a time before any aggregate speaks.

**Invitation semantics:** eligibility re-evaluates on every qualifying
post-boundary summary until the invitation is tapped or the next lunation
closes — the persisted flag records "acted on," not "first opportunity," so
pending transcriptions don't cost the walker the month. The sheet computes
live at open (its counts may exceed the invitation moment's). The
last-acted lunation index lives in UserDefaults; loss on reinstall is
accepted (ephemeral, unlike the released set). A "Past recaps" list under
the Thought Threads settings area (mirroring "Released threads") keeps
closed moons reachable, so a missed line never costs the month.

**Content:** the moon's name and walk count; themes as plain counts
("'the move' — walked with you in 6 of 9 walks"), each tappable to its
thread view; *new this moon* firsts (full-history, backfill-gated, like
all origin claims); one state-only texture line from the safe markers.
**No directional language** — the original rising/steady/faded sketch is
superseded by design principle 1; trajectory remains dossier-only.
Released lemmas are filtered. Recap counts are lunation-scoped by design
and will diverge from the card's trailing-30-day statuses — the phrasings
stay structurally distinct ("in N of M walks" vs. ordinal "nth walk now")
so they never read as the same metric disagreeing. Sparse states: a
single-walk moon still uses count copy ("in 1 of 1 walks"); when release-
filtering leaves no themes, the sheet shows moon name + walk count + a
quiet line ("nothing held on to name this time"). Invitation placement:
its own row below the intention card, above the per-walk card; when the
triggering walk has no analyzed transcript it renders alone in the card's
slot. Deterministic template copy; no generation.

### Stage 3+4 release shape (v1.12.0)

Card + thread view (as specified in Stage 3 above, unchanged) + Let this
one go + Return to where it began + chips live (header ships as
"Recurring"; a softer-variant copy pass is a tracked fast-follow) + the
lunation recap. Walker-facing exposure staggers by construction: the card
appears with the first post-update analyzed walk; chips require a theme
recurring across two walks; the recap requires a lunation to close after
the first card — the bundle ships together but arrives gently, by design.
Accessibility requirements from Stage 3 (Dynamic Type wrapping, VoiceOver
elements incl. the release custom action, 44-point targets) extend to the
recap sheet and both settings lists. Rollout: internal TestFlight first;
the walker/product owner runs the LLM-readback QA pass (and a gentleness
read of the release/welcome-back confirm strings) on that build, gating
public TestFlight or App Store submission.

## Stage 3 field verdict (2026-08-24)

### What broke

Build 106 real-device contact — the first walk transcripts a human actually
spoke into the shipped Stage 1–2 engine, rather than the dogfood corpus the
field gate above was judged against — surfaced a blind spot the gate never
tested: everyday spoken scaffolding ("was", "have", "can", "think") threaded
as themes. The `[noun, verb, adjective]` part-of-speech filter admitted
these lemmas as verbs, and raw-frequency ranking then let them win against
sparser, more meaningful nouns — "was" appears more often in any recording
than "grief" ever will. The dogfood corpus validated theme quality on
curated transcripts; it never stress-tested the extractor against
unscripted, filler-heavy speech, which is most of what a walker actually
says aloud on a walk.

### The verdict

Themes move to nouns-only, filtered through a new `SpokenStoplist` — light
nouns ("thing", "way", "stuff", and similar) for theme extraction, and a
separate scaffold-lemma set ("be", "have", "think", and similar) for the
`AttentionDirectives` recurring-word directive, which shares the same
spoken-filler exposure outside theme extraction entirely. That fix stands
on its own, regardless of the surface question below.

The surface question did not survive contact. Once themes were correctly
nouns-only and re-run against a real transcript, the walker's verdict was to
remove the card, the cross-walk thread history view, the lunation recap, and
the release ("let this one go") gesture — not gate them further, remove
them. The reasoning: the AI prompt dossier already carries every theme the
card would show, with a capable LLM to contextualize them in the walker's
own words — the card was redundant at best against that dossier, and at
worst the surface where the junk-theme bug was most visible and most
damaging to trust. The engine underneath — `ThemeExtractor`, `ThreadStore`,
`ThreadsDossierBuilder` — is untouched; only the surfaces built to display
threads directly to the walker are gone.

`ThreadIntentionSuggestions` chips are the one walker-facing surface that
survives, unchanged in kind: they stay under the "Recurring" header in
`IntentionSettingView`, now drawing from noun-only themes. A chip offers a
word to carry into an intention; it asserts nothing about the walker's inner
life, which is a materially smaller claim than the card made — the
distinction the walker's verdict turned on.

`LunationCalendar` is deliberately retained even though the lunation recap
that consumed it is gone: it has no walker-facing surface left to serve
today, but the moon line below is a committed consumer, not a hope.

### Dossier-first direction (approved, unscheduled)

Four upgrade tracks were approved for the AI-prompt dossier — the feature's
one surviving surface — as follow-up work, none scheduled or designed in
detail yet:

- **Place-theme resonance** — correlating themes with where they were
  spoken, the way the dossier already correlates them with pace.
- **The moon line** — a dossier-only descendant of the lunation recap,
  consuming `LunationCalendar` to give the AI the current lunar context
  without any walker-facing recap surface.
- **Body & sky** — climb anchoring (grade/elevation context) woven with
  weather, giving the dossier physical and atmospheric texture alongside
  the psychological markers it already carries.
- **Small signatures** — photo adjacency (themes correlated with where
  photos were taken) and theme-marker coloring, small touches that let the
  dossier's supporting material feel richer without asserting new claims.
