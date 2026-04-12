# Dynamic Whisper Catalog + Play Category

**Date**: 2026-04-11
**Status**: Draft, pending review

## Context

The whisper system today lives in a hardcoded Swift enum (`WhisperCatalog.all` in `Pilgrim/Models/Whisper/WhisperCatalog.swift`) with exactly 3 whispers per category × 7 categories = 21 total. Adding a new whisper requires an app update and App Store review cycle. This is friction the product should not have.

Audio files already live on a CDN at `cdn.pilgrimapp.org/audio/whisper/` and download on demand via `WhisperPlayer.play()`. The only reason new whispers can't be added without an app release is that the metadata (which whispers exist, their titles and durations) is baked into the binary.

At the same time, the creator wants to:

1. Add an 8th category, **Play**, voiced entirely by themselves as a "signature" on the app.
2. Let podcast guests on "Pilgrim on the Path" contribute whispers to the original 7 categories, joining a shared anonymous chorus. The creator records guests in person during podcast sessions; there is no public submission pipeline.

Both of these require the catalog to grow dynamically.

## Goals

- Move whisper metadata from hardcoded Swift to a remote, versioned manifest served from R2
- Add a new `.play` whisper category, populated only with creator recordings
- Preserve **silent growth**: users never see a "new whispers!" notification, count, or loading state; the catalog expands invisibly
- Preserve offline-first behavior: fresh installs work with no network (bundled bootstrap)
- Preserve anonymity: no attribution, no podcast cross-links, no naming anywhere in the UI
- Preserve the **sonic receipt** UX on placement — whisper plays back to the placer immediately after successful placement

## Non-Goals

- No UI showing how many whispers exist in a category, or which are new
- No attribution UI anywhere (no "voiced by", no episode links)
- No community submission pipeline — creator records guests in person, no external upload path
- No moderation dashboard or approval workflow — creator presence on the podcast is the QC
- No per-user novelty weighting — random pick stays pure random
- No orphan audio cleanup on the client (R2 is cheap; defer to later)
- No localization of whisper content — whispers are distributed as-recorded
- No change to the `walk.pilgrimapp.org/api/whispers` placement endpoint schema
- No change to the proximity-based encounter flow
- No foreground manifest re-sync — matches existing `AudioManifestService` pattern of cold-launch-only sync

## Current State

Code references (pre-change):

- `Pilgrim/Models/Whisper/WhisperCatalog.swift` — hardcoded static array, 21 entries
- `Pilgrim/Models/Whisper/WhisperDefinition.swift` — `Codable` struct, 7-case `WhisperCategory` enum with per-category border colors
- `Pilgrim/Models/Whisper/WhisperPlayer.swift` — singleton with `play()`, `preview()`, `downloadAll()`, cache in `Application Support/Whispers/`; downloads `.aac` files from `cdn.pilgrimapp.org/audio/whisper/` on demand
- `Pilgrim/Models/Whisper/WhisperService.swift` — POSTs placements to `walk.pilgrimapp.org/api/whispers`
- `Pilgrim/Scenes/ActiveWalk/WhisperPlacementSheet.swift` — picks random from `WhisperCatalog.whispers(for:)`, eagerly calls `whisperPlayer.downloadAll()` in `onAppear`
- `Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift:820` — after a successful server placement, calls `WhisperPlayer.shared.play(whisper)` to produce the sonic receipt
- `Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift:904` (`handleAnnotationTap`) — taps on map whisper pins look up `WhisperCatalog.whisper(byId:)` and play via `WhisperPlayer.play()`
- `Pilgrim/AppDelegate.swift:79-80` — existing manifest services are synced via `syncIfNeeded()` inside the `DataManager.setup` completion handler
- `Pilgrim/Models/Audio/AudioManifestService.swift` — the reference pattern to copy

Today's app **does not** bundle any whisper audio — every fresh install must download all 21 files the first time the placement sheet opens. This design upgrades that to a fully-bundled bootstrap.

## Design

### 1. Categories

Add one new case to `WhisperCategory`:

```swift
enum WhisperCategory: String, Codable, CaseIterable {
    case presence
    case lightness
    case wonder
    case gratitude
    case compassion
    case courage
    case stillness
    case play  // new
    ...
}
```

Border color for `.play`: warm rust, tentatively `UIColor(red: 0.75, green: 0.40, blue: 0.22, alpha: 1.0)`. Final hex finalized during implementation by eye against the wabi-sabi palette in `Constants.swift`.

**Semantic tiering** (enforced by the creator's workflow, not by code):

- `.play` is **creator-only**: the creator voices every whisper in this category. It is their signature — never voiced by guests.
- The other 7 categories are **mixed chorus**: creator recordings plus anonymous guest contributions recorded in person during "Pilgrim on the Path" podcast sessions. All voices are anonymous to the user.

The client does not encode this distinction — both tiers share the same manifest schema. The creator upholds the rule when editing the manifest.

### 2. Manifest Architecture

#### Server-side (R2)

**Location**: `https://cdn.pilgrimapp.org/audio/whisper/manifest.json`

**Schema**:

```json
{
  "version": 1,
  "whispers": [
    {
      "id": "presence-1",
      "category": "presence",
      "title": "What do you see right now?",
      "audioFileName": "whisper-presence-1",
      "durationSec": 6,
      "retiredAt": null
    }
  ]
}
```

Fields:

- `version` — monotonically increasing integer, bumped every time the manifest changes
- `whispers` — flat array; the client filters by category
- `retiredAt` — optional ISO8601 date string; `null` for active whispers. When set, the whisper is excluded from new placements but remains resolvable by ID so existing placements continue to play.

**Append-only rule**: whisper entries are never removed from the manifest, even after retirement. The file only grows. This guarantees existing placements with older IDs stay resolvable when users sync.

**Publishing workflow** (creator):

1. Record and master audio, upload `.aac` files to R2 under `cdn.pilgrimapp.org/audio/whisper/`
2. Edit `manifest.json`, add new entries (or flip `retiredAt` on an existing entry), bump `version`
3. Upload updated `manifest.json` to R2
4. Purge the Cloudflare cache for `manifest.json` (or set a short TTL on that object, e.g. 5 minutes)

#### Client-side: `WhisperManifestService`

New singleton modeled exactly on `AudioManifestService.swift`.

**Path**: `Pilgrim/Models/Whisper/WhisperManifestService.swift`

**Public API**:

```swift
final class WhisperManifestService: ObservableObject {
    static let shared = WhisperManifestService()

    @Published private(set) var manifest: WhisperManifest?

    // Returns ALL whispers for the category, including retired.
    // Used by WhisperPlayer to resolve existing placed whispers.
    func whispers(for category: WhisperCategory) -> [WhisperDefinition]

    // Returns non-retired whispers only.
    // Used by WhisperPlacementSheet for the random placement pick.
    func placeableWhispers(for category: WhisperCategory) -> [WhisperDefinition]

    // Returns a specific whisper by ID, including retired.
    // Used by map-tap and proximity-encounter resolution.
    func whisper(byId id: String) -> WhisperDefinition?

    func syncIfNeeded()
}
```

**Caching**: JSON persisted to `Application Support/Whispers/manifest.json`. Read synchronously in `init()` via `loadLocalManifest()` — by the time any view asks, a manifest is available (either cached or bootstrap fallback).

**Bootstrap fallback**: if no local manifest exists yet (first launch ever), load a JSON file bundled in the app at `Pilgrim/Support Files/whispers-bootstrap.json`. This file is a snapshot of the manifest at the moment the app version was built, generated as part of the release workflow.

#### `WhisperManifest` schema (Swift side)

New file: `Pilgrim/Models/Whisper/WhisperManifest.swift`

```swift
struct WhisperManifest: Codable {
    let version: Int
    let whispers: [WhisperDefinition]
}
```

`WhisperDefinition` gains one new field, `retiredAt`:

```swift
struct WhisperDefinition: Codable, Identifiable {
    let id: String
    let title: String
    let category: WhisperCategory
    let audioFileName: String
    let durationSec: Double
    let retiredAt: Date?   // nil for active
}
```

All existing call sites that construct `WhisperDefinition` (only `WhisperCatalog.all` today) need to pass `nil`. After the catalog is deleted, the only construction path will be via `JSONDecoder` reading the manifest.

### 3. Download Policy

Goal: silent growth with zero perceived latency, except in unavoidable edge cases.

| Moment | What downloads |
|---|---|
| App launch (cold) | Manifest JSON via `syncIfNeeded()`. No audio files. Matches existing `AudioManifestService` pattern. |
| Placement sheet opens | Nothing. The current `whisperPlayer.downloadAll()` call is removed. |
| User selects a category (taps row OR taps preview icon) | All uncached whispers in that category, downloaded in background, best-effort. New `WhisperPlayer.prefetchCategory(_:)` method. |
| User taps preview play icon | Picks random from manifest for that category; plays from cache if local, else single-file download-then-play via existing `WhisperPlayer.preview()` path. |
| User taps "Leave Whisper" | No explicit download. The category prefetch from selection is almost certainly complete. After successful server placement, `WhisperPlayer.play()` plays the whisper as a sonic receipt. Falls back to download-then-play if the picked whisper's audio happens not to be cached (slow-network edge case). |
| User taps a whisper on the map | Single-file download-then-play via existing `WhisperPlayer.play()` path. |
| Proximity encounter | Same as map tap, existing flow unchanged. |

#### Bundled bootstrap (offline-first upgrade)

Every whisper that exists in the manifest at the moment an app version is built ships as bundled audio in the app bundle:

- **Path**: `Pilgrim/Support Files/whisper-audio/<audioFileName>.aac`
- **Matching manifest**: `Pilgrim/Support Files/whispers-bootstrap.json`

On first launch with no cache, `WhisperPlayer` seeds its cache directory by copying the bundled audio files to `Application Support/Whispers/`. After the copy, the files live in the normal cache location and are indistinguishable from downloaded files.

**Generation**: the bootstrap bundle is regenerated as part of the release workflow. Pull latest `manifest.json` from R2, download all referenced audio files, update the Xcode project to include the new `whisper-audio/` contents and `whispers-bootstrap.json`, commit.

**App size impact**: ~70KB per whisper. At ~31 whispers (21 original + ~10 Play initial drop), ~2.2MB — negligible.

Only whispers added after a given app version's build date require network. Even then, the category-prefetch strategy usually hides the latency behind the user's selection-to-tap thinking time.

This is an upgrade over today's behavior, where a fresh install with no network has no whispers at all until `downloadAll()` can succeed.

#### Stale-while-revalidate manifest sync

Triggered on cold launch only, matching the existing `AudioManifestService` pattern wired in `AppDelegate.swift:79`:

1. `init()` reads the cached local manifest synchronously (or bootstrap if no cache yet) — app is ready immediately
2. `syncIfNeeded()` fires a background fetch to `https://cdn.pilgrimapp.org/audio/whisper/manifest.json`
3. If fetched `version` > local `version`, save the new manifest to disk
4. New manifest takes effect on next read (next placement sheet open, next map tap, next app launch)

No UI ever waits on this fetch. If it fails (offline, server down), the cached manifest continues to serve.

**Consequence**: a user who keeps Pilgrim suspended in memory for days will not pick up new whispers until they fully cold-launch. This is acceptable — iOS is aggressive about reclaiming suspended app memory, and whispers are not urgent content. Matching the existing pattern avoids touching scene-phase logic and keeps all manifest services behaving consistently.

### 4. Retirement and Takedown

Two distinct removal semantics:

**Retirement (soft)** — "I don't want new placements of this whisper, but existing ones can stay":

- Set `retiredAt: "2026-04-11"` on the manifest entry
- `placeableWhispers(for:)` filters it out — placement sheet can't pick it
- `whispers(for:)` and `whisper(byId:)` still return it — existing placements resolve and play
- R2 audio file stays forever
- Retired whispers fade from the world naturally as their existing placements expire

**Takedown (hard)** — "This whisper must stop playing now, including for existing placements":

- Handled server-side on the worker (`walk.pilgrimapp.org`), NOT client-side
- Worker maintains a `takedown_whisper_ids` set (D1 table or KV — implementer's choice)
- When the worker returns nearby placements, it filters out any whose `whisper_id` is in the takedown set
- Client never sees takedown'd placements → can't play them, regardless of app version or cache state
- Optionally delete the R2 audio file as well (extra certainty)
- Manifest entry can stay or be flagged `retiredAt`; behavior is the same either way

**Broken file** (unexpected): `WhisperPlayer.play()`'s existing `catch` branch silently logs and fails. No user-facing error. Tap or encounter produces no audio.

### 5. User-Facing Flow Examples

#### Fresh install, offline on first walk

1. User installs app, opens it with airplane mode on
2. `WhisperManifestService.init()` finds no cached manifest, loads `whispers-bootstrap.json` from bundle (~30 entries)
3. `WhisperPlayer` cache seeding copies bundled `whisper-audio/*.aac` into `Application Support/Whispers/`
4. User opens placement sheet → all 8 categories visible, zero loading states
5. User selects Gratitude → category prefetch is a no-op (all files already cached from the bootstrap copy)
6. User taps preview → plays instantly from local cache
7. User taps "Leave Whisper" → server call fails (offline) → existing error handling path kicks in

#### Established user, creator publishes new whispers

1. Tuesday: creator uploads 4 new Gratitude whispers to R2, bumps manifest from version 7 to version 8
2. Alice's app has been suspended in memory since Monday
3. Wednesday morning, Alice fully cold-launches Pilgrim (iOS had reclaimed the suspended process) → `WhisperManifestService.syncIfNeeded()` fires in background → detects version 8 > 7 → saves new manifest
4. Alice opens placement sheet → selects Gratitude → category prefetch sees 4 new uncached whispers → downloads them in background
5. Alice hits "Leave Whisper" after a few seconds
6. Random pick across 7 Gratitude whispers (3 original + 4 new) → server records → `WhisperPlayer.play()` plays sonic receipt instantly (prefetch done)
7. Alice has no visible signal that anything changed. She just hears a whisper she's never heard before, and smiles.

#### Placing then tapping your own whisper

1. Alice places a Play whisper → plays as sonic receipt → cached locally
2. Alice taps her Play whisper pin on the map
3. `handleAnnotationTap` → `WhisperManifestService.whisper(byId:)` resolves metadata → `WhisperPlayer.play()` → file is cached → plays instantly

### 6. File Changes

#### New files

- `Pilgrim/Models/Whisper/WhisperManifest.swift` — Codable schema (`WhisperManifest` struct)
- `Pilgrim/Models/Whisper/WhisperManifestService.swift` — singleton, copy of `AudioManifestService` shape, adapted for whispers
- `Pilgrim/Support Files/whispers-bootstrap.json` — bundled bootstrap manifest, regenerated on each release
- `Pilgrim/Support Files/whisper-audio/*.aac` — bundled audio files matching the bootstrap manifest

#### Modified files

- `Pilgrim/Models/Whisper/WhisperDefinition.swift` — add `.play` case to `WhisperCategory` with a rust border color; add `retiredAt: Date?` field to `WhisperDefinition`
- `Pilgrim/Models/Whisper/WhisperCatalog.swift` — **deleted**. All call sites route through `WhisperManifestService.shared`.
- `Pilgrim/Models/Whisper/WhisperPlayer.swift`:
  - Remove `downloadAll()` and `allDownloaded` (no more eager bulk download)
  - Add `prefetchCategory(_ category: WhisperCategory)` — downloads uncached whispers in that category in the background, best-effort
  - Add initial cache seeding logic: on init, if the cache directory has no files, copy bundled `whisper-audio/` resources into it
  - Keep `play()`, `preview()`, `stop()`, and the download-on-demand paths
- `Pilgrim/Scenes/ActiveWalk/WhisperPlacementSheet.swift`:
  - Replace `WhisperCatalog.whispers(for:)` with `WhisperManifestService.shared.placeableWhispers(for:)` for the random placement pick
  - Replace `WhisperCatalog.whispers(for:)` with `WhisperManifestService.shared.whispers(for:)` for the preview random pick (preview may play retired whispers — acceptable, and simpler than filtering)
  - Add `.onChange(of: selectedCategory)` that calls `whisperPlayer.prefetchCategory(newCategory)` when a category becomes selected
  - Remove the `whisperPlayer.downloadAll()` call in `onAppear`
- `Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift:911` — replace `WhisperCatalog.whisper(byId: cached.whisperId)` with `WhisperManifestService.shared.whisper(byId: cached.whisperId)`
- `Pilgrim/AppDelegate.swift:79-80` — add `WhisperManifestService.shared.syncIfNeeded()` alongside the existing `AudioManifestService` and `VoiceGuideManifestService` calls in `DataManager.setup` completion

#### Worker-side changes (separate repo: `../pilgrim-worker`)

- Add a takedown filter to the nearby-whispers endpoint (KV or D1 set of `whisper_id` strings — implementer's choice based on expected size)
- No schema changes required — the existing placement POST and lookup GET remain unchanged

#### Release workflow update

Add a step to `scripts/release.sh` (or document a manual pre-release task) that regenerates the bundled bootstrap:

1. Download `https://cdn.pilgrimapp.org/audio/whisper/manifest.json` to `Pilgrim/Support Files/whispers-bootstrap.json`
2. For each `audioFileName` in the manifest, download the corresponding `.aac` from R2 into `Pilgrim/Support Files/whisper-audio/`
3. Update the Xcode project so the files are in the target's Copy Bundle Resources phase
4. Commit and tag the release

### 7. Edge Cases and Failure Modes

| Situation | Behavior |
|---|---|
| Manifest fetch fails (offline or server down) | Use cached local manifest. Nothing blocks. |
| Manifest fetch succeeds but file is malformed | `JSONDecoder` throws, log, keep cached version |
| Cached manifest missing AND bundle bootstrap missing (shouldn't happen) | Log critical error, return empty arrays — placement sheet shows no categories. Dev-time assert to catch at build time. |
| Category prefetch races with placement on slow network | Random pick lands on uncached whisper → `WhisperPlayer.play()` downloads-then-plays with 200-800ms delay → sonic receipt still works, just delayed |
| Whisper ID in cached placement not in local manifest (user has stale manifest) | `WhisperPlayer.play()` can't resolve → silent failure. Next cold launch syncs. Window is small. |
| Retired whisper encountered on map | Plays normally. Retirement only affects new placements, not existing ones. |
| Takedown'd whisper | Worker never returns the placement → client never sees it. |
| Bundled audio file exists but local cache already has the file (e.g., after an update) | Skip the copy, cache version wins. |
| User places a whisper while on a slow network — prefetch incomplete, sonic receipt delayed | Existing UX degradation — already happens for any cold-cache play. Not a regression. |

### 8. Out of Scope (explicitly deferred)

- Attribution UI anywhere (no voiced-by text, no podcast cross-links)
- Public community submission pipeline
- Moderation dashboard or approval workflow
- Orphan audio cleanup sweep on client
- Whisper content localization
- User-facing indicators of new whispers (counts, badges, "new!" labels)
- Per-user novelty weighting
- Manual "refresh catalog" affordance in the UI
- Foreground manifest re-sync (matches existing pattern — can be added later across all manifest services as a separate improvement)
- Automated tests for the manifest service — manual verification is sufficient for initial ship

## Decisions

Resolved during spec review:

1. **Play initial drop count**: **10 whispers**. Creator records these in one session. Bootstrap bundle will include all 10.
2. **Play category border color**: warm rust, starting from `UIColor(red: 0.75, green: 0.40, blue: 0.22, alpha: 1.0)`. Final hex picked by eye against `Constants` during implementation.
3. **Bootstrap bundle regeneration**: **automated** as a dedicated step in `scripts/release.sh`. Pulls manifest + audio from R2, writes to `Pilgrim/Support Files/`, leaves a dirty working tree for the release commit to pick up.
4. **Hard takedown infrastructure**: **deferred**. The worker-side takedown filter will be built the first time a real takedown request exists. For now, retirement via `retiredAt` covers all planned use cases.
