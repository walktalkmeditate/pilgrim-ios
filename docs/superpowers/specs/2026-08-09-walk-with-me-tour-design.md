# Walk with Me — Interactive Walk Tour

**Date:** 2026-08-09
**Status:** Design approved, pending implementation planning
**Repos:** pilgrim-ios (share flow), pilgrim-worker (tour engine, serving, expiry)

## Vision

Today a shared walk is a beautiful postcard: a static page with the route, stats,
and pinned photos. This feature turns it into the walk itself — a viewer scrolls
through the walk step by step, the ink stroke drawing forward beneath them, and
where the walker recorded, the place becomes audible: their voice at the talks,
the ambient sound of the street where they recorded without speaking. Photos
bloom where they were taken. Waypoint marks pass by. The reference feeling is
walkkumano.com/koyabound — interactive storytelling art — but generated from a
walk instead of authored by hand. Every walker becomes a tour guide simply by
walking, recording, and sharing.

The feature is named by its button: **"Walk with me"**.

## Design principles

1. **One artifact, one URL.** The tour is a progressive enhancement of the
   existing share page at `walk.pilgrimapp.org/{id}`. The static Journey layout
   remains what unfurls in iMessage, serves no-JS readers, and is the page the
   tour returns to. There is never a second share type to choose.
2. **Encounters, not a film.** Scroll is walking; stations are moments. Movement
   between encounters is position-based (scroll), each encounter is time-based
   (audio plays, a photo holds). This is how audio and scroll coexist.
3. **The ink world, no tile map.** No Mapbox GL, no tiles. The tour renders the
   route as a sumi-e stroke drawing itself, with the elevation ribbon as the
   scrubber and geocoded place names as drifting labels. Distinctive,
   featherweight, and gentler on privacy than a satellite flythrough. Photos
   carry visual reality; the map only carries shape.
4. **Honest sound.** The recorder already captures ambience — a recording with
   no words is an ambient one, not a broken talk. Sound plays only where it was
   recorded. Between recordings the page is quiet. No loops, no fabricated
   soundscape.
5. **Voice is the most intimate data in the app.** Every recording is opt-in,
   per recording, default off.

## What exists today (verified 2026-08-09)

- **Recordings** are AAC `.m4a`, 44.1 kHz mono, `AVAudioQuality.high`, stored at
  `Documents/Recordings/<walkUUID>/<uuid>.m4a`
  (`VoiceRecordingManagement.swift`). `VoiceRecordingInterface` carries
  `startDate`, `endDate`, `duration`, `fileRelativePath`, `transcription?`,
  `wordsPerMinute?`, `isEnhanced`. Optional on-device enhancement
  (`VoiceEnhancer`) rewrites the file in place — uploads need no transcode.
- **Share payload** (`SharePayload.swift`) already sends: stats, route points
  **with timestamps** (`{lat, lon, alt, ts}`, RDP-downsampled to ≤200 points),
  activity intervals (meditation + talk time ranges), journal (≤140 chars),
  expiry, units, place names, mark, waypoints (`{lat, lon, label, icon, ts}`),
  photos (600×600 JPEG q0.5 base64, `{lat, lon, ts, data}`).
- **Transport** (`ShareService.swift`): `POST https://walk.pilgrimapp.org/api/share`,
  JSON body, `X-Device-Token` header (random UUID persisted in UserDefaults).
  Response `{url, id}`. Result cached per walk in UserDefaults.
- **Worker** (`pilgrim-worker`): payload cap **2 MB**; HTML pre-rendered at
  upload into R2 `walks/{id}/index.html`; photos at `walks/{id}/photos/{n}.jpg`;
  full payload minus photos at `walks/{id}/card.json`; meta with
  `device_token_hash` at `walks/{id}/meta.json`. Serving adds CSP
  (`script-src 'unsafe-inline' https://static.cloudflareinsights.com`) at
  request time. Daily 03:00 UTC cron deletes expired walks by an **enumerated
  key list** plus the `photos/` prefix (duplicated in `expiry.ts` and
  `serve.ts`). Rate limit 10 shares/day/device.
- **No per-recording UI exists** in the share flow; talk intervals are sent as
  anonymous time ranges only. No audio and no transcriptions leave the device
  via share today. (The separate podcast flow uploads raw `.m4a`, so raw audio
  upload has precedent.)
- **Waypoint vocabulary** is "Waypoints" (preset chips Peaceful `leaf`,
  Beautiful `eye`, Grateful `heart`, Resting `figure.seated.side`, Inspired
  `sparkles`, Arrived `flag.fill`, custom note ≤50 chars → `mappin`). Stones and
  cairns are a different, collective feature — the tour must not borrow that
  vocabulary.

## Experience design

### Entry

The pre-rendered page gains a hero button under the map section — **"Walk with
me →"** — present only when the share includes **at least one recording**.
Voice is the point of the tour; photos-only shares keep today's static page
unchanged (a photos-only tour is a trivial later enablement if wanted). Tapping
the button is the audio-unlock
gesture (iOS Safari requires one): the engine fetches `/{id}/tour.json`, opens a
full-screen overlay, and resumes the AudioContext inside the tap handler. The
static page below is untouched; closing the tour returns to it.

### The tour

A vertical scroll drives progress along the route. The scroll track length is
proportional to route distance, with fixed-height dwell blocks inserted at
encounters so each moment has scroll room to breathe.

While walking (between encounters):

- The route stroke draws forward (`stroke-dashoffset` linked to scroll
  progress); the camera — a translate/scale of one SVG group using the same
  Web-Mercator projection the worker already uses (`camera.ts`) — keeps the
  active point centered.
- The elevation ribbon sits fixed at the bottom as the scrubber: progress dot,
  tick marks for upcoming encounters.
- Meditation intervals render as glow segments along the stroke (colors match
  the static page's activity palette).
- Place names (start/end from the payload) drift in at their ends of the walk.

### Encounter types

Compiled server-side at share time (see tour.json), ordered by timestamp:

| Type | Source | Behavior |
|---|---|---|
| Departure | `start_date`, `place_start`, weather, journal | Title card: date, place, weather line; journal text as epigraph if present |
| Spoken encounter | recording with `kind: "spoken"` | Scroll settles into a station; audio plays with ~300 ms gain fade-in; transcription revealed as flowing text (full text, slow reveal — no word-sync in v1); scrolling past a threshold fades audio out (never force-listen) |
| Ambient passage | recording with `kind: "ambient"` | A span from position(start_ts) to position(end_ts); audio fades in while the viewer is inside the span (~1.5 s ramps), no transcript, scroll never stops |
| Photo | photo `{lat, lon, ts}` | Photo card blooms at its ts-position (600×600 relic card in the ink world, not full-bleed — matches the reliquary aesthetic and today's pipeline) |
| Waypoint mark | waypoint | Small card: icon + label, drifts past |
| Rest | pause interval ≥3 min (new `pauses` payload field) | Quiet beat: "stillness here · 12 min" — the stroke pauses drawing for a breath |
| Arrival | `place_end`, toggled stats | Closing card: place, duration, the stats the walker chose to share; then the overlay closes onto the static page at the seal section — the walk literally returns to the artifact |

At most one spoken audio plays at a time; an ambient passage ducks (gain to
~0.3) under a spoken encounter if spans overlap, and both share one Web Audio
graph (iOS Safari ignores the `volume` property on media elements, so all
level control is GainNodes on MediaElementAudioSourceNodes).

### Ambient vs spoken (the wpm gate)

Computed on iOS at payload build, sent as `kind` so the worker stays dumb and a
future per-recording override slot exists:

```
ambient  if transcription is nil/whitespace
      or wordCount < 8
      or wordsPerMinute < 30
spoken   otherwise
```

Initial constants; tunable. Rationale: Whisper hallucinates short repeated
phrases on wind and street noise, so low-wpm/low-count transcripts are treated
as noise and never displayed. All inputs already exist on
`VoiceRecordingInterface`.

### Degraded modes (all first-class)

- **Muted / no audio:** everything works as a text-and-image walk; spoken
  encounters show transcripts, ambient passages are skipped visually.
- **Missing audio file** (upload failed, or expired asset): spoken encounter
  renders transcript-only; ambient passage is dropped.
- **`prefers-reduced-motion`:** no camera glide, no stroke animation — stepped
  transitions between encounters, tap/arrow to advance.
- **No JS / crawlers / iMessage preview:** the static page, unchanged.

## Architecture

### iOS changes (share flow only — no schema change, no migration)

1. **"Voices on the trail" section** in `WalkShareView`, shown when the walk has
   recordings whose files still exist. One row per recording, styled after
   `VoiceRecordingRow` (index title, duration, start time, one-line transcript
   preview), each with a toggle **default off**. Recordings whose file was
   deleted (transcript kept) appear grayed: "audio removed". When ≥1 recording
   is on, show the warning (mirroring the photos warning): "Voices will be
   audible to anyone with the link."
2. **"Soften start & end" toggle** — trims route points within ~150 m
   path-distance of each end **before** payload build, so the static map, og
   image, and tour all inherit it. Default **on when ≥1 recording is included**,
   off otherwise (preserves current behavior for existing share types). Tour
   anchor positions falling inside a trimmed zone clamp to the trimmed ends.
3. **Payload additions** (`SharePayload`):
   ```json
   "tour": {
     "recordings": [
       {"n": 1, "start_ts": 0, "end_ts": 0, "duration": 0.0,
        "kind": "spoken|ambient", "transcription": "…", "wpm": 0.0,
        "size_bytes": 0}
     ],
     "trim_m": 150
   },
   "pauses": [{"start_ts": 0, "end_ts": 0}]
   ```
   `transcription`/`wpm` are included **only** for selected recordings — no
   transcript leaves the device for a recording the walker didn't choose. The
   `tour` object is sent only when ≥1 recording is selected.
4. **Audio upload** in `ShareService`: after `POST /api/share` returns `{id}`,
   PUT each selected file sequentially —
   `PUT /api/share/{id}/audio/{n}` with `X-Device-Token`, raw `.m4a` body
   (no transcode; files are already AAC mono) — with a progress UI
   ("Uploading voice 2 of 5"). Per-file failure offers Retry / Skip; a skipped
   file degrades to transcript-only on the page. No finalize handshake needed.
5. **Caps enforced client-side** (mirrored server-side): ≤12 recordings,
   ≤15 MB per file, ≤60 MB and ≤45 min total. If a selection exceeds a cap, the
   share button disables with gentle copy until the selection fits.

### Worker changes

1. **`POST /api/share`** accepts the optional `tour` and `pauses` fields,
   validates recording metadata (count/duration/size caps, ts ordering, kind
   enum, transcription length ≤ 10k chars each), and when `tour` is present
   (≥1 recording):
   - compiles **`walks/{id}/tour.json`** — the finished encounter script:
     `{v: 1, theme, place_start, place_end, weather, route (trimmed, ts),
     elevation profile, encounters[], meditation_segments[], expires}`.
     Compilation (ts→route-position interpolation, clamping anchors that fall
     inside trimmed zones to the trimmed ends, encounter ordering, dwell hints)
     happens here so the page engine is a pure renderer and the logic is
     vitest-testable;
   - renders the page with the "Walk with me" button and a
     `<script defer src="/assets/tour-v1.js">` tag.
2. **`PUT /api/share/{id}/audio/{n}`** — auth: SHA-256 of `X-Device-Token` must
   equal `meta.device_token_hash`; walk must be unexpired; `n` must be within
   the declared recording count; `Content-Length` ≤ 15 MB; body streamed to R2
   `walks/{id}/audio/{n}.m4a`. No separate daily quota: PUTs are bounded by
   the declared recording count of an already rate-limited share.
3. **`GET /{id}/audio/{n}.m4a`** — new `ASSET_ROUTES` entry, `audio/mp4`,
   max-age 86400, **with HTTP Range support** (R2 range get → 206): iOS Safari
   issues byte-range requests for media and misbehaves without it.
4. **`GET /{id}/tour.json`** — new asset route, `application/json`, max-age
   3600.
5. **Engine bundle** — `/assets/tour-v{N}.js` served from the worker bundle
   (text modules), explicitly versioned, long max-age. Pages reference the
   version current at their share time; superseded versions stay in the worker
   for ≥365 days (the maximum walk lifetime), so pre-rendered pages never break
   on deploy and iterating the engine affects new shares only. CSP
   `script-src` gains `'self'`.
6. **Expiry fix (required, also fixes latent bugs):** replace the enumerated
   key lists duplicated in `expiry.ts` and `serve.ts:cleanupExpiredWalk` with
   one shared, cursor-paginated **prefix delete of `walks/{id}/`**. Without
   this, audio and tour.json would leak forever; it also fixes the existing
   unpaginated `photos/` list (>1000 objects partially missed) and removes the
   duplication.

### Page engine (vanilla JS, budget ≈25 KB minified)

No framework, no external deps. Scroll handler + `requestAnimationFrame` drive:
stroke dashoffset, SVG group transform (projection math ported from
`camera.ts` — it is already TypeScript), encounter card opacity, elevation
scrubber. One `AudioContext` (created in the entry tap), one
`MediaElementAudioSourceNode` + GainNode per active audio, prefetch policy of
"next encounter only" (`preload="none"` otherwise). All text from tour.json is
inserted via `textContent`, never `innerHTML`.

## Privacy

- Per-recording opt-in, default off; transcript and wpm ride only with selected
  recordings. Photos warning pattern reused for voices.
- Trim defaults on for voice shares; applies to every downstream artifact
  because it happens before payload build.
- Same threat model as photos today: unlisted 10-char nanoid, `noindex`,
  ephemeral by expiry (moon/season/cycle), served over the same domain. Audio
  inherits all of it, including cron cleanup via the prefix-delete fix.
- No new third parties: audio stays in R2, served by the existing worker; no
  analytics added to the tour.

## Limits and costs

- Storage: ≤60 MB/walk worst case, ephemeral. R2 egress to Cloudflare-served
  requests is free; no new vendor dependencies; Mapbox usage unchanged.
- The 2 MB JSON payload cap stays: audio never rides in JSON (a single 3-min
  recording exceeds the whole cap as base64 — this is why audio is per-file
  PUTs), and transcription text at ≤10k × 12 fits comfortably.
- Rate limits: existing 10 shares/day/device; audio PUTs bounded by declared
  count per walk.

## Testing

- **Worker (vitest):** tour payload validation (caps, ordering, kinds);
  encounter compilation against a golden walk fixture (recordings + photos +
  waypoints + pauses → expected encounter script); PUT auth (wrong token, wrong
  n, oversize, expired walk); Range responses (206/416); prefix-delete expiry
  including >1000 objects and audio keys.
- **iOS (XCTest):** wpm gate cases (nil/hallucinated/slow-poem/normal);
  trim function (path-distance, anchor clamping, degenerate short walks);
  payload build with mixed selections (deleted files excluded, transcripts
  scoped to selected).
- **Manual matrix:** iOS Safari (audio unlock, Range, background/lock
  behavior), macOS Safari, Chrome desktop, Android Chrome; VoiceOver pass over
  the tour overlay; `prefers-reduced-motion`; muted walkthrough; expired-walk
  tombstone from inside a tour.

## Phasing

- **v1 (this spec):** everything above.
- **Phase 2:** "walk it for me" auto-advance at the walker's compressed real
  pace; daypart sky gradient following the walk's actual clock; full-bleed
  photo option via per-file PUTs; transcript sync highlighting.
- **Phase 3:** "leave a stone" — one anonymous tap at the arrival, surfaced to
  the walker as "N people walked with you" (collective-counter language, no
  comments, no accounts); pilgrim-cards QR → tour of a trail.

## Rejected alternatives

- **Mapbox GL / tile map in the tour** — heavy, aesthetically generic, worse
  privacy (satellite flythrough of a neighborhood), and the ink world is
  already the brand.
- **A dedicated "ambience capture" feature** — the record button already
  captures ambience; a recording with no words *is* the ambient capture. No new
  schema entity, no migration.
- **A second share type / separate tour URL** — one artifact, one link; the
  tour enhances the page that already exists.
- **Base64 audio in the JSON payload** — breaks the 2 MB cap immediately.
- **On-device transcode before upload** — files are already AAC mono; recompression
  adds code and loses quality for ~2× size savings that caps make unnecessary.
- **Auto-walk in v1** — one input driver (scroll) ships first; the clock driver
  reuses the same engine in Phase 2.
