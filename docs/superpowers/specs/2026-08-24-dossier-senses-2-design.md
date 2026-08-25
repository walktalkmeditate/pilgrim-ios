# Dossier Senses II — Design

**Date:** 2026-08-24 · **Status:** draft for review
**Origin:** the Stage 3 field verdict (see `2026-08-22-thought-threads-design.md`, "Stage 3 field verdict"). The card died; the dossier is the feature's home. These are the four approved upgrade tracks that deepen what the AI prompts can see — all on-device, all descriptive, no new UI.

## Binding principles (inherited, non-negotiable)

1. **Descriptive-never-evaluative** in every emitted line: state what happened, never a trajectory or judgment. (The dossier may carry cross-walk *facts*; the handling note tells the LLM how to hold them.)
2. **Nothing derived leaves the device** except inside the user-carried clipboard prompt. Raw coordinates never appear in prompt text — only relational phrases ("near the same stretch of ground").
3. **Traceable**: every line derives from enumerable, deterministic inputs — no line the walker couldn't verify against their own recordings.
4. **Pulled-never-pushed**: senses render only inside the AI-prompt dossier the walker opens. No notifications, no journal changes, no summary-screen changes.
5. **Toggle sovereignty**: `threadsAfterWalks` off = none of this computes.
6. **No schema migration.** All new state is UserDefaults or derived-at-build-time from existing CoreStore fields + `TranscriptContext` files.
7. **Prompt economy**: the dossier must not bloat. Each sense emits **at most one line**, and the whole Senses II block is capped at **3 lines per prompt**, chosen by the priority order below. A sense with nothing true to say emits nothing — silence is the default.

## Priority order (when more than 3 senses fire)

1. Place-theme resonance · 2. The moon line · 3. Theme-marker coloring · 4. Climb anchoring · 5. Weather weave · 6. Photo adjacency · 7. Question density · 8. Speech shape · 9. Intention lineage

Rationale: rarer + more personally anchored beats generic; the moon line is time-boxed (one prompt per lunation) so it rarely competes.

## Data sources (all existing)

| Input | Where it lives | Fetched when |
|---|---|---|
| Themes + mention offsets, markers, word counts | `TranscriptContext` file cache (per recording) | already loaded by dossier build |
| Recording timestamps, wpm | CoreStore `VoiceRecording` | already in dossier build |
| Recording coordinates | walk `routeData` sample nearest recording timestamp | at build, per needed recording only |
| Elevation series, speeds | walk `routeData` | at build, current walk only |
| Weather (condition, temperature) | `Walk._weatherCondition` / `_weatherTemperature` (PilgrimV7, existing) | at build |
| Reliquary photo timestamps | walk photo entities (PilgrimV7, existing) | at build, current walk only |
| Intentions | walk intention field / `IntentionHistoryStore` | at build |
| Lunation boundaries | `LunationCalendar` (kept from the refit for exactly this) | at build |

## The senses

### Track 1 — Place-theme resonance (cross-walk)

When a theme has mentions on ≥2 distinct walks whose recording coordinates fall within a **150 m** great-circle radius of each other, emit:

> `'music' has surfaced on N walks — twice near the same stretch of ground.`

- Clustering: pairwise distance between mention-recording coordinates; a cluster is ≥2 mentions from ≥2 distinct walks within the radius. No geocoding, no place names in v1 (offline-safe, nothing to leak); "the same stretch of ground" is the whole location claim.
- Coordinate resolution: recording → owning walk → `routeData` sample nearest the recording's timestamp; recordings on walks without route data simply don't participate.
- Gates: `backfillComplete` (origin-class claim), theme not scaffolding (nouns-only is upstream now), ≥2 distinct walks in the standard 30-day window.
- Cost bound: only themes already in the dossier's thread section are checked (≤4), only their mention recordings' coordinates are resolved.

### Track 2 — The moon line (once per lunation)

On the first dossier build after a lunation closes (and only if `firstDossierMoonIndex` state says this closed lunation hasn't been reported), emit:

> `The Sturgeon Moon has set: 5 walks, 3 with recorded words; 'music' walked in 2 of them.`

- `LunationCalendar.mostRecentClosed` supplies boundary + name (timezone-pinned, as shipped).
- State: one UserDefaults int (`threadsMoonLineLastLunationIndex`), set when the line is emitted; Delete All Data clears it.
- Gates: the closed lunation contains ≥1 walk with words; `threadsAfterWalks` on. No first-card gate anymore — the dossier is the surface, and the walker opened it.
- Counts only; at most one theme named (the one appearing in the most walks that moon; ties broken alphabetically).

### Track 3 — Body & sky (current walk + cross-walk)

**Climb anchoring** (current walk): classify each theme-mention recording against the walk's elevation series — a mention is "on the climb" when its recording overlaps the walk's steepest sustained ascent (top decile of smoothed gradient, minimum 20 m gain). Emit at most:

> `'the move' was spoken on the day's steepest climb.`

Skip entirely when total ascent < 50 m (flat walks make the claim meaningless).

**Weather weave** (cross-walk): when a theme's walks (≥2 in-window) all share a stored weather condition category, emit:

> `Both walks where 'music' surfaced were under rain.`

Condition categories collapse WeatherKit strings to: rain, snow, clear, cloud, wind, fog (mapping table in code; unknown/missing conditions exclude the walk from the claim, and a theme with any excluded walk emits nothing — the claim must be total).

### Track 4 — Small signatures (current walk unless noted)

**Theme-marker coloring**: absolutist-marker density inside ±15-word windows around a theme's mentions vs the transcript's overall absolutist density. Emit only when window density ≥ 2× overall AND ≥3 absolutist tokens in windows:

> `Absolutist words cluster around 'the move' — twice the density of the rest of the walk's speech.`

(The dossier's existing handling note already governs how the LLM may use marker facts; this line joins that section, not the theme section.)

**Photo adjacency**: a reliquary photo taken within **3 minutes** after a theme mention's recording:

> `A photo was taken two minutes after 'music' was spoken.`

Nearest pair only; one line max; minutes rounded to nearest whole word-number.

**Question density**: sentences ending `?` in this walk's transcripts vs the walker's median across in-window walks (≥3 walks of history required). Emit only when today ≥ 2× median and ≥3 questions:

> `Four of today's sentences were questions — more than any walk this month.`
(The comparison clause must stay literally true: compute max, not just median, before claiming "more than any".)

**Speech shape**: when all recordings fall in the first third of the walk's duration and the wordless remainder exceeds 30 minutes:

> `All the words came in the first third; the last 40 minutes were wordless.`

**Intention lineage** (cross-walk): when ≥3 in-window walks carry intentions sharing a lemma (existing intention-echo lemma machinery), and today's walk has an intention in that family:

> `Third walk this month carrying some form of 'release'.`

## Architecture

- One new pure module: `Pilgrim/Models/Threads/DossierSenses.swift` — `DossierSenses.lines(context:threads:walkData:...) -> [String]` returning the capped, priority-ordered block. Each sense is a private pure function with its own tests; the module owns the cap and ordering.
- `ThreadsDossierBuilder` calls it and appends the block under a new dossier subheading (`Noticed:`), memoized with the existing (changeCount, walkUUID, backfillComplete) key — plus the moon-line state read at build.
- Per-walk fetches (route samples, photos, weather) go through small `DataManager` extensions mirroring existing query patterns (**`rowUUID` discipline for any queryAttributes work — UUID columns are stored as strings**).
- Everything computes on the existing dossier-build path (already off-main, already memoized). Target: <50 ms added for a typical history on device; place resonance is the only cross-walk coordinate work and is bounded by ≤4 themes × their mentions.

## Testing

- Pure fixtures per sense (RED first): geometry fixtures for clustering (two walks, coords 100 m apart vs 500 m apart), elevation series fixtures, weather category fixtures incl. the any-excluded-walk-emits-nothing rule, marker-window fixtures, question/speech-shape fixtures, intention-lineage lemma fixtures, moon-line state machine (emit once, not twice; Delete All re-arms).
- Cap + priority tests: 5 senses firing → exactly 3 lines in priority order.
- String-pinning tests for every template; descriptive-only sweep is part of review.
- No UI tests (no UI).

## Out of scope

- Any new user-facing surface, setting, or notification.
- Geocoded place names (revisit only if "same stretch of ground" proves too thin in the field).
- Heart rate, cadence (no HealthKit; pedometer data not persisted per-recording).
- Close-the-loop / future-commitment detection (previously rejected).
- Embedding-based theme clustering (unchanged: exact-lemma v1).
