# Dossier Senses II — Design

**Date:** 2026-08-24 · **Status:** implemented on feat/dossier-senses-2, pending ship gate
**Origin:** the Stage 3 field verdict (see `2026-08-22-thought-threads-design.md`, "Stage 3 field verdict"). The card died; the dossier is the feature's home. These are the four approved upgrade tracks that deepen what the AI prompts can see — all on-device, all descriptive, no new UI.

## Binding principles (inherited, non-negotiable)

1. **Descriptive-never-evaluative** in every emitted line: state what happened, never a trajectory or judgment. (The dossier may carry cross-walk *facts*; the handling note tells the LLM how to hold them.)
2. **Nothing derived leaves the device** except inside the user-carried clipboard prompt. Raw coordinates never appear in prompt text — only relational phrases ("near the same stretch of ground").
3. **Traceable**: every line derives from enumerable, deterministic inputs — no line the walker couldn't verify against their own recordings. Template counts and ordinals are always substituted from computed values, never hardcoded prose.
4. **Pulled-never-pushed**: senses render only inside the AI-prompt dossier the walker opens. No notifications, no journal changes, no summary-screen changes.
5. **Toggle sovereignty**: `threadsAfterWalks` off = none of this computes.
6. **No schema migration.** All new state is UserDefaults or derived-at-build-time from existing CoreStore fields + `TranscriptContext` files. (Question density deliberately counts from stored transcripts at build time rather than adding a context field — see Track 4 — because the backfill cannot retrofit context-schema changes.)
7. **Prompt economy**: the dossier must not bloat. Each sense emits **at most one line**, and the whole Senses II block is capped at **3 lines per prompt** — roughly a quarter of a typical dossier's existing line budget, enough to add texture without competing with the theme section itself. A sense with nothing true to say emits nothing — silence is the default.
8. **Module purity (binding)**: `DossierSenses.lines(...)` performs no DataManager, CoreStore, or singleton access itself. Every input is fetched by the caller (`ThreadsDossierBuilder`) and passed as an argument. A future sense that needs new data must widen the call signature — never reach out sideways. This is the enforcement mechanism for principle 3.
9. **One theme, one line**: within a single build, once a sense has named a theme, lower-priority senses skip that theme (naming the same word twice in three lines reads as fixation, not noticing).

## Priority order (provisional — field-tunable at the ship gate)

1. **Place-theme resonance** — with the specificity guard below it fires only when geography genuinely singles a theme out; rare + the most personally anchored claim in the set.
2. **The moon line** — time-boxed to once per lunation, so it almost never competes; when it fires it frames the whole block.
3. **Theme-marker coloring** — the founder-idea signal; rare by its 2× + floor gates.
4. **Intention lineage** — the most reflective fact in the set (a carried intention echoing across walks); ranked above the body/coincidence senses deliberately.
5. **Climb anchoring** — embodied, current-walk, but only meaningful on hilly walks.
6. **Weather weave** — evocative but weather is shared context, not personal signal.
7. **Photo adjacency** — place-tied (below), but still a coincidence-class observation.
8. **Question density** — interesting when true, generic in phrasing.
9. **Speech shape** — the most generic; cheap to compute, first to yield.

## Data sources (all existing)

| Input | Where it lives | Fetched when |
|---|---|---|
| Themes + mention offsets, markers, word counts | `TranscriptContext` file cache (per recording) | already loaded by dossier build |
| Recording timestamps (per-recording `_startDate`) | CoreStore `VoiceRecording` | at build — NOTE: per-recording times, not the owning walk's `startDate`; Track 1 needs a recording-timestamp index distinct from the existing walk-level `walkIndex` |
| Transcripts (for question counts) | CoreStore `VoiceRecording` transcription field | at build, in-window walks only (bounded fetch) |
| Recording coordinates | walk `routeData` sample nearest recording timestamp | at build, per needed recording only, via a bounded timestamp-predicate query (`fetchLimit`, `rowUUID` discipline — UUID columns are stored as strings), never full-array materialization |
| Elevation series, speeds | walk `routeData` | at build, current walk only |
| Weather (condition, temperature) | `Walk._weatherCondition` / `_weatherTemperature` (PilgrimV7, existing) | at build |
| Reliquary photo timestamps + coordinates | walk photo entities (PilgrimV7, existing) | at build, current walk only |
| Intentions | `Walk.comment` + `Walk.startDate` (per-walk; `IntentionHistoryStore` is an MRU-5 without walk association and CANNOT serve this) | at build |
| Lunation boundaries | `LunationCalendar` (kept from the refit for exactly this) | at build |

## Coordinate hygiene (applies wherever a recording is located)

A recording participates in location claims only when its nearest `routeData` sample is within **90 seconds** of the recording's start AND the codebase's existing accuracy discipline holds (`horizontalAccuracy < 100 m`, matching `LocationManagement`). A recording that fails either check simply doesn't participate — same fallback as walks without route data. GPS-paused stretches, indoor starts, and cold-fix garbage never anchor a claim.

> **Implementation note (added at plan review):** the accuracy floor (`horizontalAccuracy < 100 m`) reuses `LocationManagement`'s existing discipline verbatim. The 90-second recording↔sample gap is a **new threshold**, not previously precedented in the codebase — treat it as provisional, field-tunable at the ship gate like the priority order.

## The senses

### Track 1 — Place-theme resonance (cross-walk)

When a theme has mentions on ≥2 distinct walks whose recording coordinates fall within a **150 m** great-circle radius of each other, AND the cluster is genuinely specific to that theme (below), emit:

> `'music' has surfaced on N walks — K times near the same stretch of ground.`

(K = the cluster's actual mention count, substituted; "twice" only when K is literally 2.)

- **Specificity guard (binding)**: for a walker whose recordings all cluster (a daily neighborhood loop), every theme trivially satisfies a 150 m radius and the claim means nothing. The sense emits only when the theme's cluster radius is **at most half** the walker's baseline in-window recording spread (median pairwise distance across ALL in-window mention recordings). Routine geography suppresses the sense; genuine place-theme affinity survives. **Implementation note (added at plan review):** implemented as strict `spread < baseline / 2`, so the degenerate case where every in-window recording shares one spot (baseline 0) suppresses outright rather than dividing by zero — an accepted refinement of "at most half."
- Clustering: pairwise distance between mention-recording coordinates; a cluster is ≥2 mentions from ≥2 distinct walks within the radius. No geocoding, no place names in v1 (offline-safe, nothing to leak); "the same stretch of ground" is the whole location claim.
- Coordinate resolution: per the Coordinate hygiene section — per-recording timestamps, bounded fetch, accuracy + time-gap gated.
- Gates: `backfillComplete` (origin-class claim), ≥2 distinct walks in the standard 30-day window.
- Cost bound: only themes already in the dossier's thread section are checked (≤4), only their mention recordings' coordinates are resolved. **Implementation note (added at plan review):** the shipped thread section is uncapped in code — there's no existing ≤4 limit to "check." The plan introduces an explicit `placeCandidateThemeCap = 4`, checking only the first 4 active threads in the section's own (lemma-sorted) order. Adjudicated sound at plan review: it matches this bullet's cost-bound intent.

### Track 2 — The moon line (once per lunation)

On the first dossier build after a lunation closes (and only if `threadsMoonLineLastLunationIndex` says this closed lunation hasn't been reported), emit:

> `The Sturgeon Moon has set: 5 walks, 3 with recorded words; 'music' walked in 2 of them.`

- `LunationCalendar.mostRecentClosed` supplies boundary + name (timezone-pinned, as shipped).
- State: one UserDefaults int (`threadsMoonLineLastLunationIndex`), set when the line is emitted; Delete All Data clears it; the key follows the same backup/export policy as the other threads UserDefaults state (device-backup only, never in `.pilgrim` exports).
- Gates: the closed lunation contains ≥1 walk with words; **the current walk itself has ≥1 recorded word** (the line must never be a non-sequitur stapled to a silent walk); `threadsAfterWalks` on.
- **Accepted behavior**: only the single most-recently-closed lunation is ever eligible. A walker returning from a months-long gap gets no retroactive moon lines for the missed lunations — those moons passed in silence, which is the honest telling.
- Counts only; at most one theme named (the one appearing in the most walks that moon; ties broken alphabetically).

### Track 3 — Body & sky (current walk + cross-walk)

**Climb anchoring** (current walk): classify each theme-mention recording against the walk's elevation series — a mention is "on the climb" when its recording overlaps the walk's steepest sustained ascent (top decile of smoothed gradient, minimum 20 m gain — the smoothing exists because raw GPS elevation is noisy at the per-sample level and unsmoothed gradients would false-positive on jitter). Emit at most:

> `'the move' was spoken on the day's steepest climb.`

Skip entirely when total ascent < 50 m (flat walks make the claim meaningless).

**Weather weave** (cross-walk): when a theme's walks (≥2 in-window) all share a stored weather condition category, emit:

> `All N walks where 'music' surfaced were under rain.` (N substituted; "Both" only when N is literally 2.)

- **Climate guard (binding)**: skip when the shared category is also the walker's in-window *majority* condition (>50% of in-window walks with stored weather). In a place where it mostly rains, "both walks were under rain" is a tautology of geography, not a fact about the theme.
- Condition categories collapse WeatherKit strings to: rain, snow, clear, cloud, wind, fog, plus a named `unknown` bucket; a unit test asserts every WeatherKit condition string the app can store maps to some bucket (drift guard — WeatherKit's vocabulary has shifted before). Walks with unknown/missing conditions are excluded from the claim, and a theme with any excluded walk emits nothing — the claim must be total.

### Track 4 — Small signatures (current walk unless noted)

*(Scope note: the approved track named photo adjacency + theme-marker coloring; question density, speech shape, and intention lineage were added during design elaboration and approved in the same session.)*

**Theme-marker coloring**: absolutist-marker density inside ±15-word windows around a theme's mentions vs the transcript's overall absolutist density. Emit only when window density ≥ 2× overall AND ≥3 absolutist tokens in windows:

> `Absolutist words cluster around 'the move' — twice the density of the rest of the walk's speech.`

- **Placement + gate (binding, resolves the wiring question)**: this line renders inside the `Noticed:` block like every other sense and counts against the 3-line cap. It emits ONLY when the full threads dossier is present in the prompt — the dossier's presence is what triggers the marker handling note in `PromptAssembler.responseContract` (`hasThreadsDossier`), so the note is guaranteed co-present. No second integration point, no new plumbing.
- **Ship-gate extension (binding)**: the LLM-readback QA pass must include theme-linked marker lines specifically — the existing field validation covered generic elevated profiles, not topic-correlated ones, and this is the most sensitive line in the set.

**Photo adjacency** (place-tied): a reliquary photo whose coordinates fall within **75 m** of a theme mention's recording location, taken within **10 minutes** of that mention:

> `A photo was taken near where 'music' was spoken.`

- The tie is *place first, time second* — a bare timestamp join reads as surveillance ("we noticed when you took photos"); a place tie reads as attention ("the camera and the words went to the same spot"). Photos or recordings failing Coordinate hygiene don't participate. Nearest qualifying pair only; one line max.

**Question density** (cross-walk): sentences ending `?` in this walk's transcripts vs the walker's median across in-window walks (≥3 walks of history required). Question counts are computed at build time directly from stored transcripts (bounded in-window fetch) — no `TranscriptContext` schema change. Emit only when today ≥ 2× median, ≥3 questions, AND today's count exceeds every other in-window walk's count:

> `Four of today's sentences were questions — more than any walk in the last 30 days.`

- **Known dependency**: Whisper's `?` placement is an ASR artifact, not prosody. The ship gate (below) measures real-transcript question-mark behavior before this sense ships; if punctuation proves unreliable, this sense is cut at the gate, not patched.

**Speech shape**: when all recordings fall in the first third of the walk's duration and the wordless remainder exceeds 30 minutes:

> `All the words came in the first third; the last 40 minutes were wordless.`

**Intention lineage** (cross-walk): when ≥3 in-window walks carry intentions sharing a **non-scaffold** lemma, and today's walk has an intention in that family:

> `Fifth walk in the last 30 days carrying some form of 'release'.` (Ordinal = the actual in-window count, substituted — never hardcoded.)

- **Scaffold filter (binding)**: lemma matching applies `SpokenStoplist.scaffoldLemmas` — intentions are dense with "want/feel/be", and without the filter, unrelated intentions cluster on scaffold verbs (the exact bug class that killed the card). Required fixture: two topically-unrelated intentions sharing only "want" must NOT cluster.
- Source: `Walk.comment` + `Walk.startDate` (per-walk); lemma extraction via the existing `TranscriptNLP.contentLemmas` path.

## Architecture

- One new pure module: `Pilgrim/Models/Threads/DossierSenses.swift` — `DossierSenses.lines(...) -> [String]` returning the capped, priority-ordered, theme-deduped block. Each sense is a private pure function with its own tests; the module owns the cap, ordering, and one-theme-one-line rule. Per binding principle 8, the module fetches nothing.
- `ThreadsDossierBuilder` gathers all inputs (per its existing off-main, memoized build), calls `DossierSenses.lines`, and appends the block under a new dossier subheading (`Noticed:`), memoized with the existing (changeCount, walkUUID, backfillComplete) key — plus the moon-line state read at build.
- Per-walk fetches (route samples by timestamp predicate, photos, weather, in-window transcripts/intentions) are small `DataManager` extensions mirroring existing query patterns, with the `rowUUID` discipline for any `queryAttributes` work.
- Performance: target <50 ms added for a typical history. The route-sample fetches are the risk — hence the bounded timestamp-predicate queries with `fetchLimit` (never `walk.routeData` full-array traversal for cross-walk resolution).

## Build staging

The implementation plan stages along the pure/cross-walk boundary: current-walk senses (climb anchoring, theme-marker coloring, photo adjacency, speech shape) land first as pure functions over single-walk data; cross-walk senses (place resonance, weather weave, intention lineage, question density) and the moon line land second, behind their backfill/window machinery. Each stage ends suite-green.

## Testing

- Pure fixtures per sense (RED first): geometry fixtures for clustering incl. the specificity guard's baseline comparison (tight cluster + tight baseline → suppressed; tight cluster + wide baseline → fires); coordinate-hygiene fixtures (stale sample, poor accuracy → non-participation); elevation series fixtures; weather category fixtures incl. climate guard, unknown bucket, map-every-string drift test, and the any-excluded-walk-emits-nothing rule; marker-window fixtures incl. the dossier-present gate; photo place-tie fixtures (near+soon fires, near+late and far+soon don't); question/speech-shape fixtures; intention-lineage scaffold fixtures (the "want"-only pair must not cluster); moon-line state machine (emit once, not twice; current-walk-words gate; Delete All re-arms).
- Cap + priority + dedup tests: 5 senses firing → exactly 3 lines in priority order; a theme named at rank 1 never reappears at rank 5.
- String-pinning tests for every template with substituted counts; descriptive-only sweep is part of review.
- No UI tests (no UI).

## Ship gate (binding — this is the release precondition, not an aspiration)

The predecessor surface died because synthetic fixtures validated the author's assumptions instead of real speech. Before ANY Senses II line ships externally:

1. **Real-history firing pass**: run `DossierSenses` against the team's own accumulated device history (walks, transcripts, coordinates, weather, photos) and record each sense's firing rate and output text. A sense that fires on nearly every walk (degeneration) or nearly never (dead feature) gets re-thresholded or cut here. This is also where "same stretch of ground" is judged too thin or not, and where Whisper's `?` reliability is measured — the observability channel principle 4 otherwise removes.
2. **LLM-readback QA**: paste real dossiers containing Senses II blocks — explicitly including theme-linked marker lines — into consumer LLMs; iterate the handling note until no response contains clinical or diagnostic language. (Extends the standing gate from Stages 1–2.)

Both are human judgment on real data; neither can be pre-verified by fixtures.

## Out of scope

- Any new user-facing surface, setting, or notification.
- Geocoded place names (revisit only if the ship gate's real-history pass judges "same stretch of ground" too thin).
- Heart rate, cadence (no HealthKit; pedometer data not persisted per-recording).
- Close-the-loop / future-commitment detection (previously rejected).
- Embedding-based theme clustering (unchanged: exact-lemma v1).
- Retroactive moon lines for lunations missed during usage gaps (accepted behavior, per Track 2).
