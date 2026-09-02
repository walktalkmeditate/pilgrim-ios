# Honor — walk in another's steps

**Date:** 2026-09-01
**Status:** Design approved in conversation, pending user review of this document
**Repos:** pilgrim-ios (this spec), pilgrim-worker (handoff surface, small contract below), open-pilgrimages (slice two, separate spec)
**Supersedes in part:** `2026-03-23-pilgrimage-route-packages-design.md` (packages become Honor slice two; its data-repo, tile-budget, and one-route-at-a-time decisions stand)

## Vision

Wander is a walk without an aim. Seek is a walk with a goal. Honor is a walk
with someone: you follow a line another person already walked, and where they
spoke, you hear them; where they sat, you are offered to sit; where they took
a photo, you see what they saw. On Shikoku the pilgrim's staff is carved with
dōgyō ninin, "two traveling together," because the staff is Kūkai walking
beside you. That is Honor's glyph and its meaning. You never walk alone.

The line you follow is a **Way**. A Way comes from three places, and this spec
builds the first two:

1. **Your own past walk.** Any walk in your journal with a route can be walked
   again, with your own voices from that day playing where you spoke them.
2. **A shared walk.** Any interactive Walk-with-me page carries a "walk it
   there" button. Tapping it on a phone with Pilgrim opens the app with that
   walk's route, voices, and photos as a Way.
3. **A pilgrimage stage** from a downloaded route package. Slice two, with
   offline tiles in slice three. Not in this document.

The ghost line is literal. Their trace renders as a faint pencil underdrawing;
your moss ink lays down over it as you walk. At the summary you see both.

## Vocabulary

- **Way**: the object Honor follows. A polyline with timing, plus moments
  positioned along it, plus provenance.
- **Moment**: something that happened at a place on the Way: a voice, a photo,
  a rest, a sitting, a waypoint.
- **Companion**: the faint second dot that walks the Way at the original
  walker's real pace from the moment you begin.
- **walk it there**: the button on a shared page.
- **walk this again**: the button on your own walk summary.
- **reply here**: record your own voice at the spot where theirs played.
- **returned to the trail**: the app's existing phrase for an expired share,
  reused for a Way whose voices have expired.

## Design principles

1. **Voices are place-triggered, never time-triggered.** A voice plays when
   your feet reach the spot where it was spoken, at natural pace, in full. The
   companion dot may be far ahead or behind; it does not gate sound.
2. **Photos are pins, not interruptions.** Nothing goes full screen on its own.
   A photo surfaces as a small plate in the sheet when you arrive, and opens
   only on tap.
3. **Download at acceptance, always.** Shares expire and trails have no signal.
   A Way is self-contained the moment it is accepted. There is no streaming
   and no download toggle.
4. **Media obeys the sharer's promise.** The sharer chose an expiry. Their
   voices and photos are swept from the honoring phone when that date passes.
   The geometry stays with the honoring walker's own walk record forever.
5. **Companion, not navigator.** No turn-by-turn. The only deviation signal is
   an opt-in single soft tap after sustained drift.
6. **Zero schema migration.** Mode, arrival, and linkage are recorded exactly
   the way Seek records them: a `WalkEvent`, a reserved-icon waypoint, and
   files on disk keyed by walk UUID.
7. **Camera to the Way, never to the puck.** The overview frames the whole
   Way. Follow-puck begins only at Begin. Begin is never blocked by distance,
   so the feature is testable from a desk.

## What exists today (verified 2026-09-01)

- **Modes** are a runtime-only enum, `Pilgrim/Models/Walk/WalkMode.swift`:
  `wander, together, seek`, with `together` stubbed (`isAvailable == false`).
  Four exhaustive switches must gain the new case: `WalkStartView`
  `footprintForMode`, `modeAtmosphere`, `trailUnderline`, and `WalkMode`'s
  own `subtitle`/`buttonLabel`/`quotes`; plus `PracticeMode` in
  `Models/Prompt/ActivityContext.swift` and its lexicon in `PromptAssembler`.
- **Seek persists nothing new in the schema.** `.seekMode` and `.seekArrival`
  are `WalkEvent.EventType` cases (rawValues 3 and 4); arrivals are waypoints
  with the reserved icon `"sun.haze"` (`Models/Walk/Seek/SeekPersistence.swift`).
  Journal, summary, seal milestones, scenery, Live Activity, `.pilgrim`
  export/import, and the demo seeder all key off those.
- **Seek's arrival debounce** lives in `SeekEngine.updateArrivalDebounce`:
  three consecutive fixes inside the radius with horizontal accuracy ≤ 50 m
  (`SeekEngineTuning.arrivalFixCount`, `arrivalAccuracyMeters`).
- **The map** (`Views/PilgrimMapView.swift`, MapboxMaps 11.20.0 via SPM) has
  one route source `pilgrim-route` and two line layers, `pilgrim-route-casing`
  and `pilgrim-route-layer`. Fog installs `.below("pilgrim-route-casing")`,
  annotations `.above("pilgrim-route-layer")`. Layers are destroyed on style
  reload and stripped on lock/unlock; `SeekFogRenderer` reinstalls on
  `onStyleLoaded` and on foreground (`reinstallSeekFog`, `flushDeferredSeekFog`)
  and self-heals with a layer probe. Camera modes: follow-puck at zoom 16 with
  `bottomInset`, or fit-to-`cameraBounds`.
- **Annotations** are one enum, `PilgrimAnnotation.Kind`, with tap hit-testing
  at 25 m for `.whisper/.cairn/.photo` only.
- **Proximity** already auto-plays whisper audio at 42 m
  (`Models/Proximity/ProximityDetectionService.swift`, `whisperRadius`), with
  5 s throttle and 1.2× exit hysteresis, surfaced through
  `ActiveWalkView.handleProximityEvent`.
- **Audio arbitration** is `AudioSessionCoordinator` with named consumers;
  `WhisperPlayer` activates `.playbackOnly` for `"whisper-preview"` and
  deactivates in every completion and error path.
- **Voice recording** starts and stops through
  `ActiveWalkViewModel.toggleVoiceRecording()`; meditation through
  `startMeditation()` (which stops a running recording first).
- **Downloads** follow `VoiceGuideDownloadManager` + `VoiceGuideFileStore`
  (per-pack folders under Application Support, progress dictionary, one
  retry, atomic move). Storage rows follow `SoundSettingsView.storageSection`
  and `VoiceCard`'s recordings row.
- **Share payload** (`Models/Share/SharePayload.swift`) is `Encodable` only;
  nothing in the app reads a share back. Routes are downsampled to ≤ 200
  points (`Models/Share/RouteDownsampler.swift`) before POST.
- **The worker** serves `GET /{id}/tour.json` publicly with no auth
  (`pilgrim-worker/src/index.ts`, 1 h cache). Its `route` is the POSTed
  array verbatim: `{lat, lon, alt, ts}`. Encounters carry `frac` (cumulative
  distance fraction), `n` (1-based media index), `duration`, `dwell`,
  `place`. Media is at `/{id}/audio/{n}.m4a` (Range-capable) and
  `/{id}/photos/{n}.jpg`. `meditation[]` carries `start_frac`/`end_frac`
  only. `expires` is in tour.json. After expiry sweep the asset route answers
  a plain 404. Nothing on the page links to the app: no AASA, no smart
  banner, no scheme.
- **Deep links** do not exist in the app: no associated-domains entitlement,
  no `CFBundleURLTypes`, no `onOpenURL`.
- **No GPX import exists.** `ExportManager.createGPXFiles` is dead code.
  CoreGPX is linked.

## Slices

| Slice | Content | Spec |
|---|---|---|
| **1 (this spec)** | Honor mode, the Way model, own-walk and shared-walk sources, universal link + paste, media download and expiry, ghost line, moments at places, companion dot, soft tap, place cards, reply here, summary/journal/seal/scenery, share lineage field, debug simulation export, worker handoff surface | this file |
| 2 | Pilgrimage packages online: open-pilgrimages packaging build, manifest, catalog inside Honor, one-route-at-a-time with Replace, stages as Ways, curated POIs, stage interior text, morning card, arrival reflection, stage stamps | next spec |
| 3 | Offline tiles: `tileStoreUsageMode = .shared`, corridor tile region per route, estimator, style pack, storage row, purge on Remove | next spec |
| 4 | Practices at places, credencial keepsake, Collective honor counter, page lineage rendering, voices of the Way | later |

## The Way

```swift
struct Way: Codable, Equatable {
    let id: String                    // "walk:{walkUUID}" or "share:{shareId}"
    let source: WaySource
    let title: String                 // "Rúa do Franco → Praza do Obradoiro", else the date
    let departedAt: Date
    let tzIdentifier: String?
    let expires: Date?                // shares only
    let route: [WayPoint]             // ordered; t is seconds since departure
    let totalDistanceMeters: Double
    let theirActiveSeconds: Double    // from stats when present, else route.last.t
    let moments: [WayMoment]          // sorted by frac
    let weather: WayWeather?          // condition string + °C
}

struct WayPoint: Codable, Equatable { let lat, lon: Double; let alt: Double?; let t: Double }

enum WaySource: Codable, Equatable {
    case ownWalk(UUID)
    case share(id: String, pageURL: URL)
}

enum WayMoment: Codable, Equatable {
    case voice(frac: Double, endFrac: Double, duration: Double, kind: VoiceKind, media: WayMedia)
    case photo(frac: Double, media: WayMedia)
    case waypoint(frac: Double, label: String, icon: String)
    case rest(frac: Double, minutes: Int)
    case meditation(frac: Double, minutes: Int, isEstimate: Bool)
}

enum VoiceKind: String, Codable { case spoken, ambient }

enum WayMedia: Codable, Equatable {
    case file(String)                       // relative to Ways/{id}/media/
    case recording(relativePath: String)    // own walk: Documents/Recordings/...
    case photoAsset(localIdentifier: String) // own walk: PhotoKit
}
```

`WayGeometry` wraps a Way's route with cumulative distances and is the only
place that does geometry:

- `coordinate(atFrac:)`, `frac(atElapsed:)`, `elapsed(atFrac:)` (linear
  within a segment).
- `nearest(to: CLLocationCoordinate2D) -> (frac: Double, meters: Double)`,
  the closest point on the polyline. Pure Swift haversine, ported from
  `SeekChainGenerator.distance(from:to:)`; no Turf dependency added.
- Route caps: an own-walk Way keeps up to 4,000 points through
  `RouteDownsampler` (Ramer-Douglas-Peucker, already in the app); a share Way
  is at most 200 points by construction.

## Sources

### Your own walk

Built on demand from the walk record; nothing is copied.

- Route: `routeData` samples with their timestamps → `t`.
- Voices: `voiceRecordings` placed by `startDate`; `kind` from
  `TourBuilder.classify(transcription:)`; media `.recording(relativePath:)`.
- Photos: `walkPhotos` placed by timestamp; media `.photoAsset`.
- Waypoints: all except reserved icons (`"sun.haze"` and Honor's own, below).
- Rests: `pauses` of 180 s or more, matching the worker's `MIN_REST_SECONDS`.
- Sittings: meditation `activityIntervals`, exact minutes, `isEstimate: false`.
- Weather: the walk's stored condition and temperature.

Entry point: a **"walk this again"** button on `WalkSummaryView` for any walk
with two or more route samples. It calls
`MainCoordinatorView.startHonor(way:)`, which opens the Honor overview.

### A shared walk

`WayImporter.import(shareId:) async throws -> Way`:

1. `GET https://walk.pilgrimapp.org/{id}/tour.json`. 404 → `WayError.returnedToTrail`.
   Any other non-200 or a decode failure → `WayError.unavailable`.
2. If `expires` is already past → `returnedToTrail`.
3. Build the Way: route from `route[]` (`t = ts - route[0].ts`), title from
   `place_start`/`place_end`, moments from `encounters[]`:
   `voice`/`ambience` → `.voice` with media `.file("audio/{n}.m4a")`;
   `photo` → `.photo(.file("photos/{n}.jpg"))`; `waypoint` and `rest` map
   directly. `meditation[]` entries become `.meditation` moments at
   `start_frac`, minutes from the worker's `duration` field when present,
   otherwise estimated as the time gap between the route points bracketing
   that frac, flagged `isEstimate: true` and rendered as "about".
4. Persist `way.json` to `Ways/share:{id}/` and start the media download.

Tour manifests deliberately carry no transcripts, and Honor does not want
them. Nothing is decoded that is not needed.

## Handoff from the web page

**Universal link, with paste as the fallback and the test path.**

- Entitlement: `com.apple.developer.associated-domains` =
  `applinks:walk.pilgrimapp.org`. The Associated Domains capability is
  already enabled on the developer account.
- The page's button links to `https://walk.pilgrimapp.org/{id}/honor`. Only
  the `/honor` path is claimed by the app, so ordinary share links keep
  opening in Safari for everyone, including app owners.
- `PilgrimApp` gains `.onOpenURL` and `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)`.
  Both feed `HonorLink.parse(_ url: URL) -> String?`, which accepts
  `/{id}`, `/{id}/honor`, trailing slashes, query strings, and fragments, and
  validates the ten-character id pattern.
- Routing: `RootCoordinatorView` forwards a parsed id to
  `MainCoordinatorView.openWay(shareId:)`. If setup is not complete the link
  is dropped silently. If a walk is active, a toast reads "finish this walk
  first" and the link is dropped; the user re-taps later. Otherwise the tab
  switches to Path with Honor selected and the overview opens, fetching.
- The Honor screen's **"from a shared walk"** row holds a paste field that
  accepts any form of the URL or a bare id, and runs the same importer. This
  covers the case where the link arrives inside a chat app that does not
  fire universal links, and it is how the feature is tested without a
  device-side link.

## Media download and storage

**Layout** under Application Support:

```
Ways/
  index.json                 { "walkUUID": "wayId", ... }
  share:{id}/
    way.json
    replies.json             { "originN": "Recordings/<walk>/<uuid>.m4a", ... }
    media/
      audio/{n}.m4a
      photos/{n}.jpg
  walk:{uuid}/
    way.json                 written when an honor walk of it begins
    replies.json
```

`WayStore` mirrors `AudioFileStore`: `list()`, `load(id:)`, `save(_:)`,
`diskUsage(id:)`, `totalDiskUsage()`, `delete(id:)`, `deleteMedia(id:)`,
`sweepExpired(now:)`, `link(walkUUID:to wayId:)`, `way(forWalk:)`.

`WayMediaDownloader` mirrors `VoiceGuideDownloadManager` but runs on a
background `URLSession` configuration so a locked phone finishes the job:
one task per file, temp file then atomic move, one retry per file,
`@Published progress: [wayId: Double]` and `failures: [wayId: [String]]`.
Sizes are bounded by the worker: at most 12 recordings, 15 MB each, 60 MB
total; at most 20 photos, 2 MB each.

**Overview states**: "gathering their voices · 3 of 9", then ready. Begin is
disabled while gathering. On failure after retry, the card offers "try again"
and "walk without the missing voices"; a missing moment renders its pin
greyed and its card says "this voice didn't arrive."

**Expiry sweep**, on launch and whenever the Honor list appears:

| Way | Expired | Walked (in index) | Action |
|---|---|---|---|
| share | yes | no | delete the whole folder |
| share | yes | yes | delete `media/` only; keep `way.json` and `replies.json` |
| walk | never | any | nothing |

A swept Way lists as "voices returned to the trail" and its summary place
cards say the same. The ghost line survives because geometry is the honoring
walker's own record.

**Settings → Data card** gains a **Ways** row: "3 ways · 48 MB" → `WaysListView`
with per-row swipe delete and a confirmed "Delete all Ways." Explicit delete
removes the folder entirely; a summary whose Way is gone shows no ghost and a
one-line "this way has been removed."

## The Honor engine

`HonorEngine: ObservableObject`, sibling of `SeekEngine`, owned by
`ActiveWalkViewModel` when `mode == .honor`. It is a pure consumer of the
existing publishers and persists nothing.

**Inputs**: the walk's location stream, active-duration clock, `isPaused`,
`isMeditating`, `isRecordingVoice`, builder status, power tier.

**Published state**:

- `progressFrac`, `distanceRemainingMeters`
- `offWayMeters`, `isOnWay` (nearest distance ≤ 60 m)
- `companionFrac`
- `phase: .walking | .arrived`
- `activeVoice: WayMoment?` and `pendingCards: [WayCard]`

**Position**: each fix runs `WayGeometry.nearest(to:)`. `progressFrac` only
advances (monotonic with a 0.02 backward tolerance) so a loop walk crossing
its own line does not jump.

**Companion**: `companionFrac = geometry.frac(atElapsed: activeDuration)`.
Because the clock is the walker's active duration, pausing pauses the
companion, and the original walker's own rests are already baked into the
Way's timing, so the dot rests where they rested. Arrival difference is
`theirActiveSeconds` versus your active duration at arrival.

**Moments** trigger once each, when the walker is within a radius of the
moment's coordinate and `progressFrac ≥ moment.frac − 0.05`:

| Moment | Radius | Behavior |
|---|---|---|
| voice (spoken) | 42 m | plays in full via `WayVoicePlayer`; queued if another voice is playing |
| voice (ambient) | 42 m | plays at low volume while the walker is inside its frac span, fades on exit |
| photo | 60 m | pin becomes active; a plate rises in the sheet: "what they saw here" |
| rest | 60 m | card: "they rested here 12 minutes" |
| meditation | 60 m | card: "they sat here for 12 minutes. Sit?" → `startMeditation()` with a timer preset to those minutes |
| waypoint | none | always visible as a faded pin with label |

Gates, matching the voice guide's: no voice plays while the walker is
recording, meditating, or paused, or while a whisper or guide prompt is
playing. A gated voice waits; a waiting voice is dropped once the walker is
more than 300 m past its spot. The `walk with their voice` toggle on the
overview (default on, remembered as `UserPreferences.honorVoicesEnabled`)
silences voices without affecting cards or pins.

`WayVoicePlayer` follows `WhisperPlayer` exactly: one `AVAudioPlayer` at a
time, `coordinator.activate(for: .playbackOnly, consumer: "honor-voice")`,
deactivate in completion and every error path, soundscape ducked through
the existing duck level while playing. The stats sheet shows a listening
chip with elapsed time and a pause/skip control while a voice plays.

**Soft tap** (opt-in, `UserPreferences.honorSoftTapEnabled`, default off):
when `offWayMeters > 200` continuously for 120 s, fire
`HapticPattern.honorOffWay` once and show "off the way · 240 m" in the mini
bar; re-arm when back within 60 m. Nothing else ever comments on deviation.

**Arrival**: within 30 m of the last route point, using the same debounce as
Seek. That logic is extracted from `SeekEngine.updateArrivalDebounce` into a
pure `ArrivalDebounce` value type shared by both engines, with its existing
behavior pinned by tests before the extraction. On arrival the engine emits
`.arrived`; the view model writes the `.honorArrival` event and the reserved
waypoint, fires `HapticPattern.honorArrival`, and shows the arrival card:
"you walked their way" plus "they arrived 18 minutes after you" or "before
you." The walk continues until the walker ends it, as with Seek's complete
state.

## Map rendering

`HonorWayRenderer`, an extension of `PilgrimMapView` modeled on
`SeekFogRenderer`:

- **Ghost line**: source `honor-way-source`, one `LineLayer` `honor-way-line`
  inserted `.below("pilgrim-route-casing")`: stone tint, opacity 0.35, width
  4, round joins, no dash. Same in light and dark.
- **Companion**: source `honor-companion-source`, `CircleLayer`
  `honor-companion` inserted `.above("pilgrim-route-layer")`: radius 6, stone
  at 0.6 opacity, 1.5 pt white stroke. Updated at most every 2 s while the
  walk is recording; frozen while paused, in background, or meditating (same
  render-state gate the display link uses).
- Both reinstall on `onStyleLoaded` and on foreground, and both are covered
  by the existing self-healing layer probe.
- **Moment pins** are new `PilgrimAnnotation.Kind` cases rendered as faded
  versions of their walker counterparts: `.wayVoice(n:, heard:)`,
  `.wayPhoto(media:)`, `.wayRest(minutes:)`, `.wayMeditation(minutes:)`,
  `.wayWaypoint(label:, icon:)`. The tap hit-test grows to include them.
- **Place card**: tapping a pin, or a moment triggering, lifts `WayPlaceCard`
  in the existing bottom sheet. One component, four bodies: photo (small
  parchment-matted image, tap to enlarge), voice (duration, play/pause,
  "spoken here", and **reply here**), rest, meditation (with the Sit
  button).

## The walk, start to finish

1. **Path screen.** Honor replaces Together in `WalkMode`. Subtitle "walk in
   their steps", button "Honor", footprint art a staff, quotes
   `Honor.Quote.1…3` (copy to be chosen by the user; public-domain lines
   about walking with another). With Honor selected, the area under the
   selector is `HonorWaysList`: accepted share Ways (title, date, "9 voices ·
   4 photos", expiry aging, or "voices returned to the trail"), a "walk one
   of yours again" row opening `OwnWalkPicker` (walks with routes, newest
   first), and "from a shared walk" with the paste field. Begin reads
   "Choose a way" until a Way is selected. The pilgrimage-routes door
   arrives in slice two.
2. **Overview.** `HonorOverviewView`: the map fit to the Way's bounds with
   ghost line and pins, camera not following the puck; a card with title,
   date, distance, their duration, "they walked this in rain at 9°. Today is
   clear." when weather is known, "9 voices · 4 photos", the
   `walk with their voice` toggle, "2.3 km from the start" or "you're on the
   way", download progress when gathering, and Begin.
3. **Begin** → `ActiveWalkViewModel(mode: .honor, way:)`, follow-puck at
   zoom 16 as today, ghost beneath, companion moving, moments firing.
4. **Reply here.** From the voice card or the listening chip. Starts
   `toggleVoiceRecording()`; when that recording stops, its `relativePath` is
   written to `replies.json` under the origin voice's `n`. The reply pins
   beside theirs on the live map and in the summary.
5. **Arrival** as above. **End** as any walk.

**Live Activity**: `HonorGlanceState { distanceRemainingMeters, isOnWay }`
rendered like `SeekGlanceState`.

## Persistence

- `WalkEvent.EventType` gains `.honorMode = 5` and `.honorArrival = 6`.
  `.honorMode` is written at the first recording start, exactly where Seek
  writes `.seekMode`.
- `HonorPersistence.arrivalWaypointIcon = "signpost.right.fill"`, reserved and
  disjoint from `WaypointMarkingSheet.presets`, `"mappin"`, and `"sun.haze"`;
  `isArrivalWaypoint(_:)`, `arrivalWaypointLabel(wayTitle:)`.
- When an honor walk begins, `WayStore.link(walkUUID:to:)` records the pair
  in `index.json`; for an own-walk Way this is also when `way.json` is first
  written.
- `PilgrimPackageConverter` maps `"honorMode"` and `"honorArrival"` so
  `.pilgrim` round-trips keep the mode. The Way itself is not exported; an
  imported honor walk shows its section without a ghost.
- `WalkSnapshot.isHonor` comes from the same bulk event fetch as `isSeek`.

## Summary, journal, seal, scenery

- **Summary**: the ghost line under the walked line on the summary map;
  `HonorSummarySection` with the Way title, "they arrived N minutes
  after/before you," voices heard, replies made, and the moment pins with
  place cards. **"walk this again"** appears on every summary with a route.
- **Journal**: `WalkModeFootprints` gains the staff; `SceneryType.staffs`, two
  staffs leaning together, stone-tinted, placed for any walk with a
  `.honorArrival`, at the same priority as Seek's cairn.
- **Seal**: `GoshuinMilestones.Milestone` gains `.firstHonor` and
  `.honorsWalked(Int)` at thresholds `[10, 25, 50, 100]`, counted from
  `.honorArrival` waypoints with the same before/after ordering Seek uses.
  `SealInput` gains `honorArrivalCount`. The seal's faint route watermark
  draws both lines for an honor walk.
- **Prompts**: `PracticeMode.honor` with a lexicon so journal prose knows the
  walk followed another's steps.

## Share payload addition

`SharePayload.honor?`:

```json
"honor": {
  "origin_share_id": "Qoi4YmPHLN",
  "origin_title": "Rúa do Franco → Praza do Obradoiro",
  "replies": [ { "n": 2, "origin_n": 3 } ]
}
```

Sent only when the honor walk's Way is a share. `n` is the honoring walker's
own recording index in its tour, `origin_n` the origin voice it answers.
Rendering call-and-response and "walked by" on the pages is worker slice
four; slice one only stores it.

## Debug: location-simulation export

`#if DEBUG` only. `WayGPXExporter.gpx(for: Way) -> Data` writes one track
with a `<trkpt>` per route point carrying `<ele>` when known and `<time>` =
`departedAt + t`, plus a `<wpt>` per moment named by its kind for reference.
A debug menu on the overview card offers "Export simulation GPX" through the
share sheet. Xcode's Core Location simulation paces a timestamped track at
its recorded speed, so the simulator walks the Way with voices, pins, and the
companion live. `docs/` gains a short how-to. `ScreenshotDataSeeder` seeds one
honor walk with a matching Way folder so the summary ghost appears in demo
mode.

## Error handling

- `returnedToTrail` → overview shows the tombstone line and a back action.
- Network failure on import → "couldn't reach the walk" with retry.
- Media failure → per-file retry, then the two-choice card above.
- Location denied or reduced accuracy → same behavior as every other mode.
- Disk full during download → the download fails cleanly, partial files
  removed, message names the problem.
- Deleting a Way mid-walk is impossible: the Ways list is not reachable
  during an active walk.
- Every timer, player, and subscription in the engine has a cancellation
  path in `stop()`, per the resource-safety rules in CLAUDE.md.

## Privacy

- No new permissions and no new Info.plist strings. The privacy manifest is
  unchanged.
- The only network calls are GETs to walk.pilgrimapp.org for a Way the user
  explicitly accepted. Nothing about the honoring walk leaves the device
  unless the walker shares it through the existing flow, where the `honor`
  field names an origin share that is already public.
- Replies are ordinary recordings and stay local until shared.

## Testing

Unit, in `UnitTests/Honor/`:

- `WayGeometry`: frac/coordinate/elapsed round trips, nearest-point on
  straight and looping routes, monotonic progress tolerance.
- `WayImporter`: builds a Way from the worker's `sample-share.json` fixture;
  expired and 404 paths; meditation minutes from `duration` versus estimate.
- Own-walk Way builder: recordings, photos, rests, sittings placed at the
  right fracs; reserved icons excluded.
- `HonorEngine`: moment fires once, frac gate, voice queue and 300 m drop,
  gating by meditation/recording/pause, companion frac under pause, soft tap
  arm/re-arm timing, arrival debounce via the extracted `ArrivalDebounce`.
- `ArrivalDebounce`: Seek's current behavior pinned before extraction.
- `WayStore.sweepExpired`: the three-row table above.
- `HonorLink.parse`: every accepted URL form and the rejections.
- `WayGPXExporter`: point count, timestamp monotonicity, waypoint names.
- `PilgrimPackageConverter`: honor events round-trip.
- `GoshuinMilestones`: first honor and threshold crossing with the ordering
  tie-break.

UI: the demo seed drives a screenshot of the Honor path screen and an honor
summary. The real-device pass uses the GPX export on a simulator first, then
the user's own live shares on a phone.

## Worker contract (pilgrim-worker, deploys before the iOS build ships)

1. `GET /.well-known/apple-app-site-association`: JSON, `application/json`,
   `applinks.details[0].appIDs = ["YCF2TGZAX8.org.walktalkmeditate.pilgrim"]`,
   `components = [{ "/": "/*/honor" }]`.
2. `GET /{id}/honor`: for phones without the app, a small page with
   "Open in Pilgrim" (App Store link), the `apple-itunes-app` smart-banner
   meta with `app-argument` set to the same URL, and "back to the walk."
3. Template: a `walk it there` pill on interactive pages, class `sound-pill`
   so it is a pointer-events island, hidden in embed mode, linking to
   `/{id}/honor`. Live shares regenerated with `scripts/regenerate-share.ts`.
   No engine change, so no `tour-v8`.
4. `tour.json`: `meditation[]` entries gain `duration` in seconds. Additive;
   old engines ignore it.
5. `POST /api/share` accepts and stores `honor` (id pattern, title ≤ 100
   chars, ≤ 12 replies, indices positive integers).
6. Share sheet copy in iOS: "Anyone with the link can walk it there."

## Out of scope for slice one

Pilgrimage packages and the catalog, offline tiles, the morning card and
arrival reflection, practices at places, the credencial, the Collective
honor counter, page rendering of lineage and "walked by," voices of the Way,
Android parity.
