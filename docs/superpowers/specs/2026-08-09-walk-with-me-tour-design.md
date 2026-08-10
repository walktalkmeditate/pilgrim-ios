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

1. **One artifact, one URL — and the page IS the story.** *(Revised 2026-08-10
   after live preview: the first build made the tour a button-gated overlay on
   the classic page; seeing it real showed the vision is Koya Bound — you land
   in the story.)* An interactive share renders the story directly at
   `walk.pilgrimapp.org/{id}`: full-viewport chapters, with the classic
   Journey layout (map, stats, seal, keepsake) as the final arrival chapter.
   Chapters are server-rendered HTML — a no-JS reader gets the whole story.
   Non-interactive shares keep today's page exactly. Never a second URL.
2. **Chapters, not a film.** *(Revised 2026-08-10.)* The story reads as a
   document — Koya Bound's grammar: full-viewport chapters scrolled naturally,
   the route drawing as a connecting thread between them, photos full-bleed,
   transcripts as large serif prose. Audio is chapter-anchored; scroll is
   never hijacked.
3. **The map is the canvas.** *(Revised again 2026-08-10 — the user's
   original instinct, restored: "follow the walk step by step.")* A fixed
   full-viewport Mapbox GL backdrop traverses the real route as the reader
   scrolls; the route line draws itself on real streets; chapters float over
   the map as parchment cards anchored where they happened; a warm daypart
   scrim keeps it Pilgrim rather than navigation-app. Requires a public
   Mapbox token (`MAPBOX_PUBLIC_TOKEN` worker var) and CSP allowances for
   api.mapbox.com + blob workers; when the token is absent the story
   degrades gracefully to chapters on paper. Start/end trim remains the
   privacy control.
4. **Honest sound.** The recorder already captures ambience — a recording with
   no words is an ambient one, not a broken talk. Sound plays only where it was
   recorded. Between recordings the page is quiet. No loops, no fabricated
   soundscape.
5. **Voice is the most intimate data in the app.** The tour is opt-in at the
   share level: one explicit **"Interactive"** toggle, default off. With it on,
   every recording remains individually excludable. With it off, no audio
   leaves the device and the share is exactly today's.

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

### Landing *(revised 2026-08-10 — replaces the button-gated overlay)*

Opening an interactive share lands directly on the **departure chapter**: a
full-viewport daypart sky (the walk's actual time of day — a dawn walk opens
in dawn light), date, place, weather, and the journal as epigraph. No cover,
no button. A tour needs no audio to stand: the Koya Bound reference itself is
silent — photos, waypoint marks, rests, and the route thread carry a
voiceless walk, and voices elevate it when present. Non-interactive shares
keep today's static page unchanged.

**Sound is an invitation, not an ambush.** When the tour has recordings, the
departure chapter carries a quiet **"walk with sound"** pill. Tapping it is
the iOS audio-unlock gesture: the engine unlocks the AudioContext, primes the
audio elements, and from then on voice chapters play as they enter view.
Without the tap the story is fully readable — transcripts are server-rendered
prose. This also bounds bandwidth: no audio downloads until sound is
requested, which resolves the prime-all open question by construction.

### The story

Chapters flow as a normal document — no scroll hijacking, no camera lock:

- Between chapters, the reader glides: transparent leg spacers give the
  map room, the camera interpolating along the real route from one
  chapter's coordinates to the next while the walked portion of the route
  line draws itself (line-trim) on the streets below.
- A hairline **progress line** (route fraction walked) sits fixed at the
  viewport edge; the elevation profile renders once inside the arrival
  chapter rather than as a persistent ribbon.
- Meditation stretches tint their thread segments with the activity palette.
- The daypart sky shifts subtly from chapter to chapter as the walk's clock
  advances from start time to end time.

### Chapter types *(revised 2026-08-10)*

Compiled server-side at share time (same tour.json encounter script; the page
generator renders encounters as server-side HTML chapters, ordered by
timestamp):

| Chapter | Source | Treatment |
|---|---|---|
| Departure | `start_date`, `place_start`, weather, journal | Full-viewport daypart sky; date, place, weather line; journal as epigraph; "walk with sound" pill when recordings exist |
| Voice | recording with `kind: "spoken"` | Full-viewport chapter: the transcription as large Cormorant prose, server-rendered; with sound on, audio plays (~300 ms gain fade-in) as the chapter enters view and fades if the reader moves on — never force-listen |
| Ambience | recording with `kind: "ambient"` | No chapter of its own: with sound on, the clip fades in (~1.5 s ramps) while the reader is within the chapters spanning its route range; ducks to ~0.3 under a voice |
| Photo | photo `{lat, lon, ts}` | Full-bleed photo chapter (interactive shares upload photos at high resolution — see iOS changes) |
| Waypoint | waypoint | Short interstitial: glyph + label between chapters |
| Rest | pause interval ≥3 min (`pauses` payload field) | Quiet beat chapter: "stillness here · 12 min", extra whitespace, thread pauses |
| Arrival | the classic page | The existing Journey layout in full — map, stats, timeline, elevation, reliquary, seal, keepsake, verify, colophon — as the story's final chapter; the walk's shape is revealed at the end |

At most one voice plays at a time; ambience ducks under voice; all level
control is Web Audio GainNodes on MediaElementAudioSourceNodes (iOS Safari
ignores the `volume` property on media elements).

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

*(Revised 2026-08-10 — long continuous talks.)* Talks recorded continuously
while walking (10–50 min) are **spans, not stations**: a voice covers its
real route stretch (`frac..end_frac`), playback is **position-synced** — the
reader hears the part spoken where they are; slow scrolling never interrupts
(re-seek only past ~45 s of drift), leaving fades, returning resumes in
place. Long transcripts chunk into ~110-word passages distributed along the
span (proportional placement; when iOS ships Whisper **segment timings** via
an optional per-recording `segments: [{start, end, text}]` payload field,
anchoring becomes exact). `MAX_TRANSCRIPTION_LEN` is 60,000 chars (a
50-minute talk). **Untranscribed recordings default to spoken**, not ambient
— the gate above applies only when a transcription exists; without one the
page renders "a voice, unwritten" with duration, position-synced at full
volume. The iOS share sheet may offer a per-recording spoken/ambient
override.

### Degraded modes (all first-class) *(revised 2026-08-10)*

- **Sound never requested / muted:** the story is complete as served —
  chapters are real HTML; transcripts read as prose. Nothing downloads.
- **Missing audio file** (upload failed, or expired asset): the voice chapter
  simply stays text; a quiet "voice unavailable" note appears only after a
  requested play fails.
- **`prefers-reduced-motion`:** thread-drawing and sky-shift animations are
  disabled; the document scrolls normally — chapters need no special
  navigation because they are ordinary flow content.
- **No JS / crawlers / iMessage previews:** the full story renders — chapters
  are server-side HTML; only the thread animation, progress line, and audio
  require JS. (This is a resilience upgrade over the overlay model.)

## Architecture

### iOS changes (share flow only — no schema change, no migration)

1. **"Interactive" toggle** — a new section in `WalkShareView`, available on
   every walk. One switch, default **off**, with explanatory subtitle:
   "Interactive" / "Viewers walk your route step by step — your voices and
   photos play where they happened." Turning it on:
   - reveals the recordings disclosure when the walk has recordings: one row
     per recording (index title, duration, start time, one-line transcript
     preview), each individually excludable but **included by default** —
     consent happened at the master switch; exclusion handles the one
     recording that was private. Deleted-file recordings (transcript kept)
     appear grayed: "audio removed";
   - auto-enables the existing "Reliquary Photos" toggle when pinned photos
     exist (still independently controllable — a voice-only tour is valid, and
     so is a voiceless one);
   - shows the warning when ≥1 recording is included, mirroring the photos
     one: "Voices will be audible to anyone with the link."
   Excluding every recording simply makes a silent tour. Interactive off =
   today's share exactly; no audio is uploaded.
2. **"Soften start & end" toggle** — trims route points within ~150 m
   path-distance of each end **before** payload build, so the static map, og
   image, and tour all inherit it. Default **on when Interactive is on**, off
   otherwise (preserves current behavior for existing share types).
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
   `tour` object is sent whenever Interactive is on; its `recordings` array
   may be empty (a silent tour).
4. **Media upload** in `ShareService`: after `POST /api/share` returns `{id}`,
   PUT each included file sequentially with `X-Device-Token` and a progress UI
   ("Uploading voice 2 of 5", "Uploading photo 3 of 8"):
   - `PUT /api/share/{id}/audio/{n}` — raw `.m4a` body (no transcode; files
     are already AAC mono). Per-file failure offers Retry / Skip; a skipped
     file degrades to transcript-only on the page.
   - `PUT /api/share/{id}/photos/{n}` — raw JPEG. **Interactive shares upload
     photos at high resolution** — 1600 px long edge, q0.7, EXIF-free by
     re-encode — instead of the base64 route: `SharePayload.Photo.data` is
     omitted and files land at the same R2 keys the static page already
     references, so the reliquary section and its lightboxes get the sharper
     photos for free. Non-interactive shares keep today's 600×600 base64 path
     unchanged.
   The share link is revealed when uploads complete. No finalize handshake:
   the page tolerates missing files.
5. **Caps enforced client-side** (mirrored server-side): ≤12 recordings,
   ≤15 MB per audio file, ≤60 MB and ≤45 min of audio total; ≤20 photos
   (existing cap), ≤2 MB per photo file. If a selection exceeds a cap, the
   share button disables with gentle copy until the selection fits.

### Worker changes

1. **`POST /api/share`** accepts the optional `tour` and `pauses` fields,
   validates recording metadata (count/duration/size caps, ts ordering, kind
   enum, transcription length ≤ 10k chars each), accepts `photos[].data`
   omitted when `tour` is present (files arrive via PUT; base64 required
   otherwise), and when `tour` is present:
   - compiles **`walks/{id}/tour.json`** — the finished encounter script:
     `{v: 1, theme, place_start, place_end, weather, route (trimmed, ts),
     elevation profile, encounters[], meditation_segments[], expires}`.
     Compilation (ts→route-position interpolation, clamping anchors that fall
     inside trimmed zones to the trimmed ends, encounter ordering, dwell hints)
     happens here so the page engine is a pure renderer and the logic is
     vitest-testable;
   - renders the **story page** *(revised 2026-08-10)*: server-side HTML
     chapters (departure sky → voices/photos/waypoints/rests → the classic
     Journey layout as the arrival chapter) with per-chapter route-thread SVGs,
     plus a `<script defer src="/assets/tour-v1.js">` tag for the enhancement
     layer (thread animation, progress line, audio).
2. **`PUT /api/share/{id}/audio/{n}` and `PUT /api/share/{id}/photos/{n}`** —
   auth: SHA-256 of `X-Device-Token` must equal `meta.device_token_hash`; walk
   must be unexpired; `n` must be within the declared count (recordings /
   photos); `Content-Length` ≤ 15 MB for audio, ≤ 2 MB for photos; bodies
   streamed to R2 `walks/{id}/audio/{n}.m4a` / `walks/{id}/photos/{n}.jpg`
   (the photo key today's serving already uses). No separate daily quota:
   PUTs are bounded by the declared counts of an already rate-limited share.
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

### Page engine (vanilla JS, enhancement layer) *(revised 2026-08-10)*

No framework, no external deps — and now a much lighter job, because chapters
are server-rendered: the engine only animates thread-drawing
(`stroke-dashoffset` per chapter-connector SVG, driven by
IntersectionObserver/scroll progress), maintains the fixed progress line, and
runs audio. One `AudioContext` (created in the "walk with sound" tap), one
`MediaElementAudioSourceNode` + GainNode per active audio; audio elements are
created and primed only after the sound opt-in. All dynamic text originates
server-side; the engine never uses `innerHTML`.

## Privacy

- The tour is gated by the explicit Interactive toggle, default off; with it
  on, every recording is individually excludable, and transcript/wpm ride only
  with included recordings. Photos warning pattern reused for voices.
  Interactive off = nothing new leaves the device.
- Trim defaults on for Interactive shares; applies to every downstream artifact
  because it happens before payload build.
- Same threat model as photos today: unlisted 10-char nanoid, `noindex`,
  ephemeral by expiry (moon/season/cycle), served over the same domain. Audio
  inherits all of it, including cron cleanup via the prefix-delete fix.
- No new third parties: audio stays in R2, served by the existing worker; no
  analytics added to the tour.

## Limits and costs

- Storage: ≤100 MB/walk worst case (60 MB audio + 40 MB photos), ephemeral.
  R2 egress to Cloudflare-served requests is free; no new vendor dependencies;
  Mapbox usage unchanged.
- The media caps are policy, not platform limits (a Worker request body allows
  ~100 MB per request; R2 objects far more). They bound worst-case storage per
  walk on an endpoint whose device tokens are self-issued — anyone can mint
  one, so per-walk caps are the blast-radius control, not the daily rate
  limit. Server-side constants, tunable anytime; the client mirrors them only
  for friendly early failure.
- The 2 MB JSON payload cap stays: audio never rides in JSON (a single 3-min
  recording exceeds the whole cap as base64 — this is why audio is per-file
  PUTs), and transcription text at ≤10k × 12 fits comfortably.
- Rate limits: existing 10 shares/day/device; audio PUTs bounded by declared
  count per walk.

## Testing

- **Worker (vitest):** tour payload validation (caps, ordering, kinds);
  encounter compilation against a golden walk fixture (recordings + photos +
  waypoints + pauses → expected encounter script) and a voiceless fixture; PUT auth (wrong token, wrong
  n, oversize, expired walk); Range responses (206/416); prefix-delete expiry
  including >1000 objects and audio keys.
- **iOS (XCTest):** wpm gate cases (nil/hallucinated/slow-poem/normal);
  trim function (path-distance, anchor clamping, degenerate short walks);
  payload build with mixed selections (deleted files excluded, transcripts
  scoped to selected).
- **Manual matrix:** iOS Safari (sound opt-in unlock, Range, background/lock
  behavior), macOS Safari, Chrome desktop, Android Chrome; VoiceOver pass over
  the story page; `prefers-reduced-motion`; no-sound read-through; expired-walk
  tombstone.

## Phasing

- **v1 (this spec):** everything above — including the daypart sky, pulled
  forward from Phase 2 by the 2026-08-10 story-page revision (it is the
  departure chapter's canvas, not a nice-to-have).
- **Phase 2:** "walk it for me" auto-advance at the walker's compressed real
  pace; transcript sync highlighting.
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
- **A second share type / separate tour URL** — one artifact, one link; for
  interactive shares that one page is the story.
- **Button-gated overlay on the classic page** *(the 2026-08-09 first build)*
  — implemented, previewed live, and replaced: landing on a stats page with a
  "Walk with me" button made the story subordinate to the artifact. The Koya
  Bound feel requires landing in the story; the classic layout survives as the
  arrival chapter. The API layer (validation, compilation, PUTs, Range
  serving, expiry) carried over unchanged.
- **Granular-first selection** (per-recording checkboxes as the primary consent
  surface — this spec's first draft) — replaced by the single Interactive
  toggle: consent lives at the mode level where it's legible; granular
  exclusion remains as a disclosure beneath it.
- **Base64 audio in the JSON payload** — breaks the 2 MB cap immediately.
- **On-device transcode before upload** — files are already AAC mono; recompression
  adds code and loses quality for ~2× size savings that caps make unnecessary.
- **Auto-walk in v1** — one input driver (scroll) ships first; the clock driver
  reuses the same engine in Phase 2.
