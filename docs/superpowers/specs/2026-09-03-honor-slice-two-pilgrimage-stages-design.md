# Honor Slice Two: Pilgrimage Stages as Ways

**Date:** 2026-09-03
**Repos:** open-pilgrimages (packaging build, this spec's section 1), pilgrim-ios (everything else)
**Builds on:** `2026-09-01-honor-mode-design.md` (slice one, shipped in PR #81: the Way model, `HonorEngine`, place cards, the Way store) and `2026-03-23-pilgrimage-route-packages-design.md` (whose data-repo, CDN, one-route-at-a-time, and tile-budget decisions stand; its `RouteManifestService` / `RoutePackageManager` / `RouteProximityMonitor` design is superseded by the Way pipeline below)
**Plans:** two — one in open-pilgrimages for section 1 (build step, schema, fixtures), one in pilgrim-ios for sections 2–7; the iOS plan consumes a fixture package checked into its test bundle so it never waits on the dataset.
**Not in this slice:** offline tiles (slice three), stage stamps and the credencial keepsake, lineage to pilgrimag.es and per-route collective counts (slice four), Android parity

## Summary

A pilgrim downloads one route from the open-pilgrimages dataset and walks it stage by stage. Each stage is a Way — the same file the app already walks for a shared walk — built ahead of time by a script in the dataset repo and served from the CDN. On the walk, the stage's meaningful places rise as cards, its services sit on the map as quiet pins, water announces itself as you near it, and the stage's own words open and close the day. The route remembers which stages you have walked and offers the next one.

The engine does not change. What changes is where a Way comes from, what a card can carry, and what the walker sees before and after.

## Decisions (from the 2026-09-03 brainstorm)

1. **Packaging lives in open-pilgrimages.** A build step emits ready-to-walk Way files per stage and a catalog index. The app stays a thin client; the Way format is the only contract. (Alternatives rejected: converting on the phone, which ties the app to the dataset's schema; converting in the worker, which puts a server between the repo and the app.)
2. **No companion dot for a stage.** The clock is synthesized silently so the engine works unchanged; the companion dot, soft tap, and arrival delta stay off for the pilgrimage source. The stage's own voice walks with you. (Rejected: a "pilgrims before you" dot at typical pace — reads as a pacer; your own last walk as companion — most stages are walked once, and slice one already gives you that by re-walking your journal.)
3. **Meaningful places are cards; services are quiet pins.** Sacred sites, cultural sites, viewpoints, the stage's start and end towns, and credential-stamp spots become moments with the dataset's description. Water, food, beds, transport, supply, and medical points draw as small pins with no card and no tap.
4. **The stage's words ship in this slice.** Morning card at Begin, arrival reflection at the summary with "reply here". Stage stamps wait for the credencial slice.
5. **Water is a caption, not a stat.** One line on the map's caption surface with a soft haptic as you near a source. Nothing new in the stats sheet.
6. **Elevation is a warning, not a live readout.** Gain and difficulty appear in the stage list and the morning card. Nothing about the climb while you walk.
7. **Local names ride along.** The dataset's localized names appear as a quiet second line on cards, in the language of the place.
8. **The route remembers your place.** A per-route ledger: stages walked, kilometres covered, where a partial stage stopped. Begin offers the next stage; a partial stage resumes.
9. **Updates are manual, by tag.** The catalog reads the CDN's `@v1` alias; packages are fetched at the exact release tag the index names; a newer tag shows an "updated" badge with a one-tap Update, never mid-walk.

## Vocabulary

- **Route:** one pilgrimage in the dataset (`camino-frances`). Downloaded whole, one at a time.
- **Stage:** one day's section of a route, as the dataset divides it (`stages.json`). One stage is one Way.
- **Package:** everything the app downloads for a route: one Way file per stage plus the route's card data.
- **Mark:** a service point on the map (water, food, bed, transport, supply, medical). Drawn, never a moment.
- **Morning card:** the stage's interior theme, narrative, day facts, warnings, and weather, shown at Begin.
- **Arrival reflection:** the stage's closing line at the summary, followed by "reply here".
- **Ledger:** the per-route record of stages walked.

---

## 1. Packaging (open-pilgrimages)

### 1.1 The build step

`scripts/build-ways.mjs`, run by the existing `npm run pipeline` after validation, reads each route's `route.geojson`, `stages.json`, and `waypoints.geojson` and writes `routes/<route-id>/ways/stage-NN.json` (NN zero-padded from 00) plus `routes/<route-id>/ways/route.json` (the route's card data). It regenerates `index.json` with the fields in 1.5. Every output is validated against `schema/way.schema.json` before the step succeeds; a route that fails validation fails the pipeline.

### 1.2 One stage, one Way

For stage `k` with start coordinate `S` and end coordinate `E`:

- **Route slice.** The route line is cut at the points nearest `S` and `E` (nearest vertex by haversine; if the route is a `MultiLineString`, the parts are concatenated in order first). The slice is downsampled with Ramer–Douglas–Peucker at 8 m tolerance and then capped at 1,000 points by uniform stride, matching `OwnWalkWayBuilder`'s limits so `WayGeometry` behaves identically.
- **Clock.** `t` for point `i` is `hours × 3600 × (cumulativeMeters[i] / totalMeters)` where `hours` is the midpoint of the stage's `estimatedHours` range. The clock exists so `WayGeometry.elapsed(atFrac:)` and the preview's "along their way" line work; nothing on the walk shows it (decision 2). `theirActiveSeconds` is the same total.
- **Altitude.** Point altitude comes from the route line's third coordinate when present, else null.
- **Departed / weather / expires.** `departedAt` is the build's ISO timestamp; `tzIdentifier` is the route's `metadata.json` time zone when it has one, else null; `weather` is null; `expires` is null (a route never returns to the trail on its own).
- **Title.** The stage's English name (`"Saint-Jean-Pied-de-Port to Roncesvalles"`).
- **Id.** `pilgrimage:<route-id>:<stage-index>`.

### 1.3 Moments

Waypoints whose `stageIndex == k` and whose `type` is one of `sacred_site`, `cultural_site`, `viewpoint`, `town`, `credential_stamp` — plus the stage's start and end places if no town waypoint sits within 150 m of them — become moments, ordered by `frac` (the waypoint's projection onto the stage slice; a waypoint more than 300 m from the line is dropped with a build warning). Each is `kind: waypoint` with:

| Field | From |
|---|---|
| `label` | `properties.name` |
| `icon` | by type: `sacred_site` → `building.columns`, `cultural_site` → `book.closed`, `viewpoint` → `eye`, `town` → `house.lodge`, `credential_stamp` → `seal` (SF Symbol names; the app's header already falls back to `mappin` for any name the device lacks) |
| `text` | `properties.description` (capped at 600 characters; absent when blank) |
| `names` | `properties.nameLocalized` (map of language code to name; absent when empty) |
| `sitMinutes` | `5` for `sacred_site` and `viewpoint`; absent otherwise |
| `at` | the waypoint's own coordinate |
| `place` | absent (the label is the place) |

Moment ids are `wp-<waypoint id>` so a moment is stable across rebuilds.

### 1.4 Marks and the stage block

`marks` (new on the Way file) lists every other waypoint of the stage with `stageIndex == k`:

```json
{ "id": "wp-fuente-x", "kind": "water", "name": "Fuente de Roldán", "at": { "lat": 43.1, "lon": -1.3 }, "frac": 0.42 }
```

`kind` is one of `water`, `food`, `bed`, `transport`, `supply`, `medical` (from `water_source`, `food`, `accommodation`, `transport`, `supply`, `medical`). `frac` is the projection onto the stage slice; marks farther than 300 m from the line are dropped with a warning.

`stage` (new on the Way file):

```json
{
  "routeId": "camino-frances",
  "index": 0,
  "count": 33,
  "theme": "Initiation",
  "narrative": "The Pyrenees are …",
  "closing": "…",
  "warnings": ["The Napoleon Route closes …"],
  "distanceKm": 24.2,
  "gainMeters": 1419,
  "lossMeters": 557,
  "hours": { "min": 7, "max": 9 },
  "difficulty": "hard",
  "start": { "name": "Saint-Jean-Pied-de-Port", "at": { "lat": 43.163, "lon": -1.236 } },
  "end":   { "name": "Roncesvalles", "at": { "lat": 43.01, "lon": -1.319 } }
}
```

`theme`, `narrative`, `closing`, `warnings` are the English strings from `stages.json` `interior` and `warnings`; `closing` is the interior's `reflection` field when present, else the last sentence of the narrative. All strings are capped (theme 80, narrative 2,000, closing 400, each warning 300 characters).

### 1.5 The catalog

`routes/<route-id>/ways/route.json`:

```json
{ "id": "camino-frances", "name": "Camino de Santiago (Francés)", "names": { "es": "…", "gl": "…" }, "country": "ES", "region": "Europe", "distanceKm": 764, "stageCount": 33, "tradition": "christian", "summary": "<metadata.overview, capped 600>", "cover": "cover.jpg", "stages": [ { "index": 0, "name": "…", "distanceKm": 24.2, "gainMeters": 1419, "hours": { "min": 7, "max": 9 }, "difficulty": "hard" } ] }
```

`index.json` gains at the top level `"release": "v1.7.0"` (the git tag of the build) and, per route, `"ways": { "stageCount": 33, "bytes": 2140000 }`. Routes without a `ways/` directory (a route that failed to build) are listed without `ways`, and the app hides them.

### 1.6 CDN paths

- Catalog: `https://cdn.jsdelivr.net/gh/walktalkmeditate/open-pilgrimages@v1/index.json`
- Package files: `https://cdn.jsdelivr.net/gh/walktalkmeditate/open-pilgrimages@<release>/routes/<route-id>/ways/<file>` — pinned to the exact tag the index named, so a route's stages are always from one build.

### 1.7 Schema and tests

`schema/way.schema.json` describes the Way file as the app reads it (route, moments, marks, stage) and is the contract; a change to it is a change to the app. Fixture tests in the repo build one small synthetic route (three stages, a dozen waypoints across all types, one off-line waypoint, a `MultiLineString`) and assert: point cap and monotonic clock, moment selection and ordering, marks, the 300 m drop with a warning, the stage block, and index fields.

## 2. Catalog, download, and updates (pilgrim-ios)

### 2.1 The third door

`HonorWaysSheet`'s "Choose a way" gains "a pilgrimage" beside "one of my walks" and "from a shared walk". It opens `PilgrimageCatalogView`: the routes from the index, each a card with cover, name, country, distance, and stage count. A route with a package downloaded is marked "on your phone" with its progress line (section 5). An empty index, or no network with nothing downloaded, shows "the routes are out of reach right now" with a retry.

### 2.2 The route

`PilgrimageRouteView`: the cover, summary, and the stage list — index, name, distance, gain, hours, difficulty — with walked stages marked and the next unwalked one first in a "next" row at the top. "Download" (or "Update") sits under the summary. Tapping a stage of a downloaded route opens the existing `HonorOverviewView` for that stage's Way with Begin. Tapping a stage of a route not yet downloaded prompts to download.

### 2.3 One route at a time

`PilgrimagePackageManager` (new, in `Pilgrim/Models/Honor/`) owns download, replace, update, and removal:

- **Download** fetches `route.json` then every `stage-NN.json` at the index's release tag, through the existing `WayMediaDownloader` background session pattern, into `WayStore` as Ways with `source: .pilgrimage(routeId:stageIndex:)`, and writes `Ways/pilgrimage/<route-id>/route.json` and `release.txt`. Progress shows per stage; a failure mid-way leaves nothing (stages are written to a temporary directory and moved into place as a set).
- **Replace.** Choosing Download on a second route while one is present asks "Replace the Camino Francés? Its stages leave your phone; your ledger of walked stages leaves with it. Walks in your journal stay." Confirm removes the first route's Ways, marks, and ledger, then downloads.
- **Update.** When the catalog index's `release` is newer than `release.txt`, the route card and route view show "updated" and the button reads "Update". Update re-downloads the package at the new tag into the temporary directory, swaps it in, and keeps the ledger (matched by route id and stage index). An update is refused while a walk in Honor mode is active.
- **Remove** lives in the route view's overflow, with the same confirmation as Replace.

### 2.4 The catalog index

`PilgrimageCatalogService` (new) fetches `index.json` from the `@v1` alias when the catalog opens, at most once per 24 hours (cached in Application Support with its fetch date), with a 15 s request timeout as the importer uses. It parses `release`, and per route the fields of 1.5, rejecting any route whose numbers fall outside sane ranges (distance 0–10,000 km, stage count 1–200, bytes under 50 MB) the way `WayImporter.validate` does.

### 2.5 The Way file, extended

`Way` gains `marks: [WayMark]?` and `stage: WayStage?`, both optional and last so every existing `way.json` decodes. `WayMoment` gains `text: String?`, `names: [String: String]?`, and `sitMinutes: Int?`, optional and last like `place` and `transcript`. `WaySource` gains `.pilgrimage(routeId: String, stageIndex: Int)`. `WayImporter` grows a `PilgrimageWayImporter` sibling that decodes a stage file with the same range validation (fracs in 0…1, coordinates on Earth, counts under the existing caps) and the string caps above.

## 3. Walking a stage

### 3.1 The engine, unchanged

`HonorEngine` is constructed exactly as today. For `source == .pilgrimage`, the view model passes `softTapEnabled: false` and the overview and walk hide the companion dot; `HonorArrivalCard` for a stage reads "you walked the stage" with the stage name, places passed, and the distance walked, and carries no companion delta. Moments trigger by place as they do now.

### 3.2 Cards

A waypoint moment with `text` shows it in the card body instead of "A place they marked." A moment with `names` shows the local name — the first of `eu`, `gl`, `es`, `fr`, `ja`, `pt`, `it`, `de` present, in that order, skipping one equal to the label — as a quiet caption line under the kicker. A moment with `sitMinutes` shows the existing "Sit?" button in the card body, wired to the same `onSit(minutes)` as a sitting card. The header, distance line, direction tick, and fly-to work unchanged. `WayMomentPreview` shows the same text and local name.

### 3.3 Marks on the map

`PilgrimAnnotation.Kind.wayMark(id:kind:)` renders as an 18 pt disc in the light way-mark palette with a glyph per kind: `drop.fill`, `fork.knife`, `bed.double.fill`, `bus.fill`, `bag.fill`, `cross.case.fill`. Marks are drawn below moment pins, never tappable, and hidden below zoom 13 so a whole stage doesn't read as a rash. They render on the overview and the walk.

### 3.4 Water ahead

`HonorMomentTracker` gains a mark watcher: when the walker's frac passes within 300 m before a `water` mark's frac for the first time in this walk, the engine emits `.markAhead(mark, meters)`. The view model shows the caption "water in 280 m" on the existing caption surface (`softTapCaption`'s slot in `WalkStatsSheet`) for the same 6 s the soft-tap caption lives, and fires a new `HapticPattern.honorWaterAhead` (a single soft tap, the same intensity as `whisperProximity`). Each mark fires at most once per walk; walking away and back does not repeat it. Off-way walkers (beyond `HonorTuning.onWayMeters`) get nothing.

### 3.5 Starting, stopping, summary

Nothing new: the engine anchors on the first on-Way fix wherever the walker joins, so a stage started at its midpoint works; ending early records a normal walk. The summary's honor block reads the stage name and "14 of 24 km of the stage" from `progressFrac × stage.distanceKm`. The walk lands in the journal as today and is re-walkable through "one of my walks".

## 4. The stage's words

### 4.1 Morning card

At Begin on a stage, before the engine starts, `StageMorningCard` is presented as a sheet over the overview: theme as its title in the display face, the narrative as body, then one facts line — "24 km · 1,400 m up · 7 to 9 hours · hard" in the walker's distance unit — then each warning as its own short paragraph with a leading `exclamationmark.triangle`, then today's weather from the existing WeatherKit fetch as "clear, 9°" when available (nothing when not). One button, "walk", starts the walk. The card can be reopened from the walk's overflow menu as "the day". Copy is the dataset's, unedited.

### 4.2 Arrival reflection and reply

When the engine fires arrival on a stage, the summary's honor block shows the closing line in the display face with the stage name beneath, and a "reply here" button. Tapping it records through the existing `replyHere` path at the stage's end place, so the recording is what a reply is today: a voice note on the walk itself (in the journal, and in the walker's own Way of this stage) and this Way's reply at that place, offered back as "your reply" the next time the stage is walked from the package.

## 5. The route remembers your place

`PilgrimageLedger` (new, JSON at `Ways/pilgrimage/<route-id>/ledger.json`):

```json
{ "routeId": "camino-frances", "stages": { "0": { "walkedAt": "2026-09-10T15:02:00Z", "kmWalked": 24.2, "completed": true }, "1": { "walkedAt": "…", "kmWalked": 14.1, "completed": false, "stoppedAtFrac": 0.58 } } }
```

The coordinator writes it when a walk in Honor mode on a `.pilgrimage` Way is saved: `completed` when the engine reached arrival, else `stoppedAtFrac` from the last on-Way progress. The catalog card reads "stage 5 of 33 · 112 km walked" (sum of `kmWalked`, completed stages counted). The route view's "next" row offers the first stage without `completed`; for a stage with `stoppedAtFrac`, the row reads "continue from where you stopped" and the overview opens with the camera on that frac. The ledger survives Update and leaves with Replace or Remove.

## 6. Error handling

- A stage file that fails validation is refused as a package: the download reports "this route isn't walkable yet" and leaves nothing behind.
- A missing `ways` entry in the index hides the route.
- Index fetch failure with a route already downloaded degrades silently: the catalog shows what is on the phone, no "updated" badge.
- Disk full mid-download surfaces the existing `WayError.diskFull` copy.
- Update while a walk is active is refused with "finish your walk first".
- All number fields pass the same range validation as the share importer before any `Int` conversion.

## 7. Testing

- **open-pilgrimages:** fixture route tests for the build step (section 1.7); schema validation in the pipeline.
- **pilgrim-ios unit tests:** `PilgrimageWayImporterTests` (decode a fixture stage file; marks, stage block, moment `text`/`names`/`sitMinutes`; range and cap rejection; old `way.json` still decodes); `PilgrimageCatalogServiceTests` (index parse, 24 h cache, range rejection, hidden routes); `PilgrimagePackageManagerTests` (download into a temporary set then move; replace removes the old route and ledger; update keeps the ledger; refused mid-walk); `HonorMomentTrackerTests` (water mark fires once within 300 m before, never after, never off-way); `ActiveWalkHonorTests` (pilgrimage source suppresses soft tap and companion; arrival card without delta; caption and haptic on `.markAhead`); `PilgrimageLedgerTests` (next stage, resume frac, km sum, survives update); `WayPlaceCard` and header tests for `text`, local name selection, and the sit button.
- **Device pass:** one real stage on the SE3 with location simulation from the stage's GPX (`WayGPXExporter`), checking pins at zoom, a water caption, a sit card at a sacred site, the morning card, the arrival reflection, and the ledger line afterward.

## 8. Out of scope

Offline tiles, stage stamps and the credencial, sharing lineage to pilgrimag.es and per-route collective counts, route variants (the dataset's `variants/` are ignored), reverse-direction stages, background index refresh, service pins that open anything, elevation profiles, any companion dot for stages, Android.

## 9. Open questions

1. **Cover images.** `route.json` names `cover.jpg`; the dataset has none yet. The build step falls back to a Mapbox Static image of the route bounds rendered at build time, committed alongside. Confirm with the dataset's licence that a Mapbox static render may be committed under ODbL data, or keep covers in the app bundle for the launch routes.
2. **Which routes at launch.** The March spec's target list stands unless the dataset's validation drops one.
3. **Interior `reflection` field.** Not every stage's `interior` carries a closing line; the last sentence of the narrative is the fallback. Worth adding the field to the dataset schema so contributors write one.
