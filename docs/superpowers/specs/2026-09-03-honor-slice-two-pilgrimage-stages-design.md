# Honor Slice Two: Pilgrimage Stages as Ways

**Date:** 2026-09-03 (reviewed 2026-09-04)
**Repos:** open-pilgrimages (packaging build, this spec's section 1), pilgrim-ios (everything else)
**Builds on:** `2026-09-01-honor-mode-design.md` (slice one, shipped in PR #81: the Way model, `HonorEngine`, place cards, the Way store) and `2026-03-23-pilgrimage-route-packages-design.md` (whose data-repo, CDN, one-route-at-a-time, and tile-budget decisions stand; its `RouteManifestService` / `RoutePackageManager` / `RouteProximityMonitor` design is superseded by the Way pipeline below)
**Plans:** two — one in open-pilgrimages for section 1 (build step, schema, fixtures, the walked line), one in pilgrim-ios for sections 2–7; the iOS plan consumes a fixture package checked into its test bundle so it never waits on the dataset.
**Not in this slice:** offline tiles (slice three), stage stamps and the credencial keepsake, lineage to pilgrimag.es and per-route collective counts (slice four), Android parity

## Summary

A pilgrim downloads one route from the open-pilgrimages dataset and walks it stage by stage. Each stage is a Way — the same file the app already walks for a shared walk — built ahead of time by a script in the dataset repo and served from the CDN. On the walk, the stage's meaningful places rise as cards, its services sit on the map as quiet pins, water announces itself as you near it, and the stage's own words open and close the day. The route remembers which stages you have walked and offers the next one.

The engine does not change. What changes is where a Way comes from, what a card can carry, and what the walker sees before and after.

## Decisions (from the 2026-09-03 brainstorm; 2026-09-04 review in italics)

1. **Packaging lives in open-pilgrimages.** A build step emits ready-to-walk Way files per stage and a catalog index. The app stays a thin client; the Way format is the only contract. (Alternatives rejected: converting on the phone, which ties the app to the dataset's schema; converting in the worker, which puts a server between the repo and the app.)
2. **No companion dot for a stage.** The clock is synthesized silently so the engine works unchanged; the companion dot, soft tap, and arrival delta stay off for the pilgrimage source. The stage's own voice walks with you. (Rejected: a "pilgrims before you" dot at typical pace — reads as a pacer; your own last walk as companion — most stages are walked once, and slice one already gives you that by re-walking your journal.)
3. **Meaningful places are cards; services are quiet pins.** Sacred sites, cultural sites, viewpoints, the stage's start and end towns, and credential-stamp spots become moments with the dataset's description. Water, food, beds, transport, supply, and medical points draw as small pins with no card and no tap. *A route enters the catalog only when the build's coverage report shows it has enough curated places to make that promise (1.5).*
4. **The stage's words ship in this slice.** Morning card at Begin, arrival reflection at the summary with "reply here". Stage stamps wait for the credencial slice.
5. **Water is a caption, not a stat.** One line on the map's caption surface with a soft haptic as you near a source. Nothing new in the stats sheet. *Bounded: on-way sources only, at most one caption per hour of walking (3.4).*
6. **Elevation is a warning, not a live readout.** Gain and difficulty appear in the stage list and the morning card. Nothing about the climb while you walk.
7. **Local names ride along.** The dataset's localized names appear as a quiet second line on cards, in the language of the place.
8. **The route remembers your place.** A per-route ledger: stages walked, kilometres covered, where a partial stage stopped. Begin offers the next stage; a partial stage resumes. *The ledger outlives the package: Replace and Remove delete the stages, not the record of having walked them.*
9. **Updates are manual, by tag.** The catalog reads the CDN's `@v1` alias; packages are fetched at the exact release tag the index names; a newer tag shows an "updated" badge with a one-tap Update, never mid-walk.
10. *Routes are downloaded, not bundled.* A whole route is a few megabytes, so bundling the launch routes in the app was weighed. Downloading wins because route data then updates on the dataset's cadence instead of riding App Store review, the app binary stays small as routes multiply, and the same path serves a route added next month. The cost is the download and update machinery in section 2.

## Vocabulary

- **Route:** one pilgrimage in the dataset (`camino-frances`). Downloaded whole, one at a time.
- **Stage:** one day's section of a route, as the dataset divides it (`stages.json`). One stage is one Way.
- **Walked line:** the route's main line with optional variants and detours removed — the geometry a stage is cut from.
- **Package:** everything the app downloads for a route: one Way file per stage plus the route's card data.
- **Mark:** a service point on the map (water, food, bed, transport, supply, medical). Drawn, never a moment.
- **Morning card:** the stage's interior theme, narrative, day facts, warnings, and weather, shown at Begin.
- **Arrival reflection:** the stage's closing line at the summary, followed by "reply here".
- **Ledger:** the per-route record of stages walked.

---

## 1. Packaging (open-pilgrimages)

### 1.1 The build step

`scripts/build-ways.mjs`, run by the existing `npm run pipeline` after validation, reads each route's walked line, `stages.json`, and `waypoints.geojson` and writes `routes/<route-id>/ways/stage-NN.json` (NN zero-padded from 00), `routes/<route-id>/ways/route.json` (the route's card data), and `routes/<route-id>/ways/report.json` (the coverage report, 1.5). It regenerates `index.json` with the fields in 1.5. Every output is validated against `schema/way.schema.json` before the step succeeds; a route that fails validation fails the pipeline.

**The walked line.** `route.geojson` for the Camino Francés measures 989 km while its 33 stages sum to 764 km, because the line includes optional variants and detours. Cutting stages from it hands a 27 km day a 63 km geometry. The build therefore cuts from a walked line: `route.main.geojson` when the route provides one, else `route.geojson` only if it passes the length gate below. Producing a main line for routes that lack one is dataset work tracked in the open-pilgrimages plan, and a route without a passing walked line emits no `ways/` directory.

**Length gate.** After slicing, every stage's measured length must lie within 10% of that stage's `distanceKm`. One failing stage fails the route's build with a message naming the stage and both figures.

**Release tag.** The release step moves a `v1` git tag onto each release commit after tagging `vX.Y.Z`, because the catalog URL in 1.6 reads through `@v1`. As of this review the `v1` tag is stale: it points at a March 2026 build with three routes while `v1.6.0` has seven.

### 1.2 One stage, one Way

For stage `k` with start coordinate `S` and end coordinate `E`:

- **Route slice.** The walked line is cut at the vertices nearest `S` and `E` (nearest vertex by haversine; if the line is a `MultiLineString`, the parts are concatenated in order first). The slice is downsampled with Ramer–Douglas–Peucker at 8 m tolerance and then capped at 1,000 points by uniform stride. The cap is the build's own choice: it keeps `WayGeometry.lowestFrac`'s linear scan cheap on a 25 km day while leaving roughly 25 m between vertices against a 60 m on-way threshold. (`OwnWalkWayBuilder`'s cap is 4,000 with stride sampling and no RDP; a stage stays well inside the geometry the engine already exercises.)
- **Clock.** `t` for point `i` is `hours × 3600 × (cumulativeMeters[i] / totalMeters)` where `hours` is the midpoint of the stage's `estimatedHours` range. The clock exists so `WayGeometry.elapsed(atFrac:)` works; nothing on the walk or in the preview shows it (decision 2, 3.1). `theirActiveSeconds` is the same total.
- **Altitude.** Point altitude comes from the walked line's third coordinate when present, else null.
- **Departed / weather / expires.** `departedAt` is the build's ISO timestamp and is never shown for a stage (3.1); `tzIdentifier` is the route's `metadata.json` time zone when it has one, else null; `weather` is null; `expires` is null (a route never returns to the trail on its own).
- **Title.** The stage's English name (`"Saint-Jean-Pied-de-Port to Roncesvalles"`).
- **Id.** `pilgrimage:<route-id>:<stage-index>`, where `<route-id>` matches `[a-z0-9-]{1,64}` and `<stage-index>` is a non-negative integer.

### 1.3 Moments

Waypoints whose `stageIndex == k` and whose `type` is one of `sacred_site`, `cultural_site`, `viewpoint`, `town`, `credential_stamp` — plus the stage's start and end places if no town waypoint sits within 150 m of them — become moments, ordered by `frac` (the waypoint's projection onto the stage slice; a waypoint more than 300 m from the line is dropped with a build warning). Each is `kind: waypoint` with:

| Field | From |
|---|---|
| `label` | `properties.name` |
| `icon` | by type: `sacred_site` → `building.columns`, `cultural_site` → `book.closed`, `viewpoint` → `eye`, `town` → `house.lodge`, `credential_stamp` → `seal`; any waypoint with `properties.credentialStamp == true` wears `seal` whatever its type (SF Symbol names; the app's header already falls back to `mappin` for any name the device lacks) |
| `text` | `properties.description` (capped at 600 characters); when absent, a line composed from the structured fields the dataset carries — for a temple, "Temple 12 · Shingon · stamp available (¥300)" from `templeNumber`, `tradition`/`denomination`, `credentialStamp`/`stampFee` — and absent only when none of those exist either |
| `names` | `properties.nameLocalized` (map of language code to name; absent when empty) |
| `sitMinutes` | `5` for `sacred_site` and `viewpoint`; absent otherwise |
| `at` | the waypoint's projection onto the stage slice (the line's coordinate at its `frac`), so the engine's 60 m trigger fires as the walker passes on the trail |
| `pin` | the waypoint's own coordinate, for the map pin |
| `place` | absent (the label is the place) |

Moment ids are `wp-<waypoint id>` so a moment is stable across rebuilds. The split between `at` and `pin` matters: on the real dataset only 17 of the Camino Francés's 52 eligible waypoints lie within 60 m of the line, and none of stage 0's do.

### 1.4 Marks and the stage block

`marks` (new on the Way file) lists every other waypoint of the stage with `stageIndex == k`:

```json
{ "id": "wp-fuente-x", "kind": "water", "name": "Fuente de Roldán", "at": { "lat": 43.1, "lon": -1.3 }, "frac": 0.42, "offLineMeters": 40 }
```

`kind` is one of `water`, `food`, `bed`, `transport`, `supply`, `medical` (from `water_source`, `food`, `accommodation`, `transport`, `supply`, `medical`). `frac` is the projection onto the stage slice and `offLineMeters` the distance from the line; marks farther than 300 m are dropped with a warning. `name` is capped at 80 characters.

`stage` (new on the Way file):

```json
{
  "routeId": "camino-frances",
  "index": 0,
  "count": 33,
  "name": "Saint-Jean-Pied-de-Port to Roncesvalles",
  "theme": "Initiation",
  "narrative": "The Pyrenees are …",
  "closing": "…",
  "warnings": ["The Napoleon Route closes …"],
  "distanceKm": 24.2,
  "gainMeters": 1419,
  "hours": { "min": 7, "max": 9 },
  "difficulty": "hard",
  "start": { "name": "Saint-Jean-Pied-de-Port", "at": { "lat": 43.163, "lon": -1.236 } },
  "end":   { "name": "Roncesvalles", "at": { "lat": 43.01, "lon": -1.319 } }
}
```

`theme`, `narrative`, `closing`, `warnings` are the English strings from `stages.json` `interior` and `warnings`; `closing` is the interior's `reflection` field, which every stage in the current dataset carries; the last sentence of the narrative is the fallback for future contributions. All strings are capped (theme 80, narrative 2,000, closing 400, each warning 300, name 120 characters). Elevation loss is not packaged: nothing in this slice reads it.

### 1.5 The catalog, the report, and the floor

`routes/<route-id>/ways/route.json`:

```json
{ "id": "camino-frances", "name": "Camino de Santiago (Francés)", "names": { "es": "…", "gl": "…" }, "country": "ES", "region": "Europe", "distanceKm": 764, "stageCount": 33, "tradition": "christian", "summary": "<metadata.overview.description, capped 600>", "cover": "cover.jpg", "stages": [ { "index": 0, "name": "…", "distanceKm": 24.2, "gainMeters": 1419, "hours": { "min": 7, "max": 9 }, "difficulty": "hard" } ] }
```

`distanceKm` is the sum of the stages' `distanceKm`, not the geometry's length.

`routes/<route-id>/ways/report.json` records, per stage, the slice length against `distanceKm`, the moment count beyond the start and end towns, how many moments carry `text`, and the mark count; and per route, whether it passed the floor and why not. The report is the honest picture of what the dataset can promise and drives the launch list (open question 2).

**The floor.** A route is listed in `index.json` with a `ways` entry only when every stage passed the length gate and at least half of its stages carry at least one moment beyond the start and end towns. As of this review only the Camino Francés and Shikoku 88 can approach that floor; the Norte, Portugués, Primitivo, and Inglés carry service waypoints only and would ship as empty stages. Routes below the floor stay in the index without `ways`, and the app hides them.

`index.json` gains at the top level `"release": "v1.7.0"` (the git tag of the build) and, per route, `"ways": { "stageCount": 33, "bytes": 2140000 }`.

### 1.6 CDN paths

- Catalog: `https://cdn.jsdelivr.net/gh/walktalkmeditate/open-pilgrimages@v1/index.json` — this depends on the moving `v1` tag from 1.1.
- Package files: `https://cdn.jsdelivr.net/gh/walktalkmeditate/open-pilgrimages@<release>/routes/<route-id>/ways/<file>` — pinned to the exact tag the index named, so a route's stages are always from one build.

### 1.7 Schema and tests

`schema/way.schema.json` describes the Way file as the app reads it (route, moments with `at` and `pin`, marks, stage) and is the contract; a change to it is a change to the app. Fixture tests in the repo build one small synthetic route (three stages, a dozen waypoints across all types including a temple with structured fields and no description, one off-line waypoint, a `MultiLineString`, and one stage whose slice is deliberately 20% long) and assert: point cap and monotonic clock, the length gate failing the long stage, moment selection and ordering with `at` on the line and `pin` off it, composed temple text, marks with `offLineMeters`, the 300 m drop with a warning, the stage block, the report, the floor decision, and index fields.

## 2. Catalog, download, and updates (pilgrim-ios)

### 2.1 The third door

`HonorWaysSheet`'s "Choose a way" gains "a pilgrimage" beside "one of my walks" and "from a shared walk". It opens `PilgrimageCatalogView`: the routes from the index that carry a `ways` entry, each a card with cover, name, country, distance, and stage count. While the index fetch is in flight and nothing is cached, a centred progress indicator stands where the cards will be. A route with a package downloaded is marked "on your phone" with its progress line (section 5). An empty index, or no network with nothing downloaded, shows "the routes are out of reach right now" with a retry.

### 2.2 The route

`PilgrimageRouteView`: the cover, summary, and the stage list — index, name, distance, gain, hours, difficulty — with walked stages marked and the next unwalked one first in a "next" row at the top. "Download" (or "Update") sits under the summary. Tapping a stage of a downloaded route opens the existing `HonorOverviewView` for that stage's Way with Begin. Tapping a stage of a route not yet downloaded prompts to download. A stage begun far from its line simply walks as an ordinary walk: no cards, no captions, no arrival, and no ledger entry (section 5).

### 2.3 One route at a time

`PilgrimagePackageManager` (new, in `Pilgrim/Models/Honor/`) owns download, replace, update, and removal:

- **Download** fetches `route.json` then every `stage-NN.json` at the index's release tag into a temporary directory, enforcing a streamed byte ceiling per file (`expectedContentLength` checked first, then a running cap of 2 MB per stage file and 512 KB for `route.json`, the way `WayImporter.importShare` caps a manifest), validating each file (2.5), and only then moving the set into place: Ways in `WayStore` with `source: .pilgrimage(routeId:stageIndex:)`, plus `Ways/pilgrimage/<route-id>/route.json` and `release.txt`. Progress shows per stage. A failure mid-way leaves nothing. The background-session and disk-space handling follow `WayMediaDownloader`'s pattern, but the URL and path construction are the manager's own: the route id must already have passed the slug check in 2.4 before it is used in any path or URL.
- **Replace.** Choosing Download on a second route while one is present asks "Replace the Camino Francés? Its stages leave your phone; what you've walked of it is remembered if it comes back. Walks in your journal stay." Confirm downloads the new route into the temporary directory first, and only once the new set is complete and validated removes the first route's Ways, marks, and package files, then swaps the new one in. The ledger stays (section 5). A failed download leaves the first route untouched.
- **Update.** When the catalog index's `release` is newer than `release.txt`, the route card and route view show "updated" and the button reads "Update". Update downloads the package at the new tag into the temporary directory, swaps it in, and reconciles the ledger by stage identity (section 5).
- **Remove** lives in the route view's overflow, with the same wording as Replace. It removes the stages and package files and keeps the ledger.
- **Guard.** Download of a second route, Replace, Update, and Remove are all refused while a walk in Honor mode is active, with "finish your walk first".

### 2.4 The catalog index

`PilgrimageCatalogService` (new) fetches `index.json` from the `@v1` alias when the catalog opens, at most once per 24 hours (cached in Application Support with its fetch date), with a 15 s request timeout and a 256 KB streamed cap as the importer uses. It parses `release` (which must match `v[0-9]+\.[0-9]+\.[0-9]+`), and per route the fields of 1.5. A route is rejected when its `id` fails `[a-z0-9-]{1,64}` — the same validate-before-use rule `WayImporter.isShareId` applies to a share id — or when its numbers fall outside sane ranges (distance 0–10,000 km, stage count 1–200, bytes under 50 MB), the way `WayImporter.validate` does.

### 2.5 The Way file, extended

`Way` gains `marks: [WayMark]?` and `stage: WayStage?`, both optional and last so every existing `way.json` decodes. `WayMoment` gains `text: String?`, `names: [String: String]?`, `sitMinutes: Int?`, and `pin: WayCoordinate?`, optional and last like `place` and `transcript`. `WaySource` gains `.pilgrimage(routeId: String, stageIndex: Int)`. `WayStore.isValidId`'s allow-list gains a third alternative, `pilgrimage:[a-z0-9-]{1,64}:[0-9]{1,3}`, beside `share:` and `walk:`; without it `save`, `load`, `directory(for:)`, and `replies(for:)` trap on the first stage. `WayImporter` grows a `PilgrimageWayImporter` sibling that decodes a stage file and `route.json` with the same range validation (fracs in 0…1, coordinates on Earth, counts under the existing caps, the numeric ranges of 2.4) and the string caps of 1.3–1.5, before anything reaches a view.

## 3. Walking a stage

### 3.1 The engine, unchanged

`HonorEngine` is constructed exactly as today. For `source == .pilgrimage`, the view model passes `softTapEnabled: false`; the overview and walk hide the companion dot; `HonorArrivalCard` for a stage reads "you walked the stage" with the stage name, places passed, and the distance walked, and carries no companion delta. The date is hidden too: `HonorOverviewView`, `HonorWaysSheet`, and the Ways list replace the `departedAt` row with the stage line ("stage 1 of 33 · 24 km · hard"), and `WayMomentPreview` drops the clock time from "along their way", keeping the distance. Moments trigger by place as they do now, on `at`; pins draw at `pin` when present.

### 3.2 Cards

A waypoint moment with `text` shows it in the card body. A moment with `names` shows the local name — the first of `eu`, `gl`, `es`, `fr`, `ja`, `pt`, `it`, `de` present, in that order, skipping one equal to the label — as a quiet caption line under the kicker. A moment with `sitMinutes` shows the existing "Sit?" button in the card body, wired to the same `onSit(minutes)` as a sitting card. The header, distance line, direction tick, and fly-to work unchanged. `WayMomentPreview` shows the same text and local name.

### 3.3 Marks on the map

`PilgrimAnnotation.Kind.wayMark(id:kind:)` renders as an 18 pt disc in the light way-mark palette with a glyph per kind: `drop.fill`, `fork.knife`, `bed.double.fill`, `bus.fill`, `bag.fill`, `cross.case.fill`. Marks are drawn below moment pins, never tappable, and hidden below zoom 13 so a whole stage doesn't read as a rash; inside a town at zoom 13 a stage can still carry over a hundred, so the plan includes a per-screen cap of 40, nearest to the walker first. They render on the overview and the walk.

### 3.4 Water ahead

`HonorMomentTracker` gains a mark watcher over the stage's `water` marks whose `offLineMeters` is within `HonorTuning.onWayMeters` — a fountain 250 m off the trail is a detour, not a drink. When the walker's frac passes within 300 m before such a mark's frac, and at least one hour of the walk's active time has passed since the last water caption (the first one is free), the engine emits `.markAhead(mark, meters)`; the marks skipped inside the quiet hour stay silent pins. The Camino Francés carries a median of eight on-way sources per stage and 23 on its wettest day, so without the hour the caption would be the day's loudest voice. The view model shows "water in 280 m" on the existing caption surface (`softTapCaption`'s slot in `WalkStatsSheet`) for the existing `softTapCaptionSeconds` (20 s) and fires a new `HapticPattern.honorWaterAhead`, a single soft tap at `whisperProximity`'s intensity. A mark fires at most once per walk. Off-way walkers (beyond `HonorTuning.onWayMeters`) get nothing.

### 3.5 Starting, stopping, summary

The engine anchors on the first on-Way fix wherever the walker joins, so a stage started at its midpoint works; ending early records a normal walk. The summary's honor block for a stage always reads the stage name and "14 of 24 km of the stage" from `progressFrac × stage.distanceKm`; when arrival fired, the closing line and the reply button (4.2) are appended beneath that line, not in its place. The walk lands in the journal as today and is re-walkable through "one of my walks".

### 3.6 Honor's language for a stage

Honor's copy assumes another walker. For `.pilgrimage` it must not: `WalkMode`'s subtitle "walk in their steps" gains a stage form ("walk the stage"); `PromptAssembler.practiceLexicon`'s `.honor` branch gains a pilgrimage form that names the route and stage instead of another walker's voices, with `HonorStoryContext` carrying route and stage for the journal; the "A place they marked." fallback in `WayPlaceCard` and `WayMomentPreview` reads "A place on the way." for a stage moment without `text`. Any other string that says "their" or "they" on a stage surface is a bug the device pass looks for.

## 4. The stage's words

### 4.1 Morning card

At Begin on a stage, before the engine starts, `StageMorningCard` is presented as a sheet over the overview: theme as its title in the display face, the narrative as body, then one facts line — "24 km · 1,400 m up · 7 to 9 hours · hard" in the walker's distance unit — then each warning as its own short paragraph with a leading `exclamationmark.triangle`, then today's weather from the existing WeatherKit fetch as "clear, 9°" when available (nothing when not). One button, "walk", starts the walk. The card can be reopened from the walk's overflow menu as "the day"; reopened mid-walk its button reads "close" and only dismisses. Copy is the dataset's, unedited.

### 4.2 Arrival reflection and reply

When the engine fires arrival on a stage, the summary's honor block appends the closing line in the display face and a "reply here" button. Tapping it records through the existing `replyHere` path at the stage's end place, so the recording is what a reply is today: a voice note on the walk itself (in the journal, and in the walker's own Way of this stage) and this Way's reply at that place, offered back as "your reply" the next time the stage is walked from the package. The reply path keys replies by a `voice-n` origin, which a stage does not have; the arrival reflection is stored under the reserved origin `-1`, and `originIndex(of:)` and `existingReplyURL(for:)` gain that branch so the reply round-trips.

## 5. The route remembers your place

`PilgrimageLedger` (new, JSON at `Ways/pilgrimage/<route-id>/ledger.json`):

```json
{ "routeId": "camino-frances", "stages": { "0": { "name": "Saint-Jean-Pied-de-Port to Roncesvalles", "distanceKm": 24.2, "walkedAt": "2026-09-10T15:02:00Z", "kmWalked": 24.2, "completed": true }, "1": { "name": "…", "distanceKm": 21.9, "walkedAt": "…", "kmWalked": 14.1, "completed": false, "stoppedAtFrac": 0.58 } } }
```

The coordinator writes it when a walk in Honor mode on a `.pilgrimage` Way is saved and the engine actually anchored on the Way (not its frac-0 fallback): `completed` when the engine reached arrival, else `stoppedAtFrac` from the last on-Way progress. Each entry carries the stage's name and `distanceKm` as its identity. The catalog card reads "stage 5 of 33 · 112 km walked" (sum of `kmWalked`, completed stages counted). The route view's "next" row offers the first stage without `completed`; for a stage with `stoppedAtFrac`, the row reads "continue from where you stopped" and the overview opens with the camera on that frac. When every stage is completed the row reads "you have walked the whole way" and offers the first stage again; anything more ceremonial belongs to the credencial slice.

**Across updates.** After an Update, each entry is kept only if the new package's stage at that index has the same name and a `distanceKm` within 5%; entries that no longer match are dropped, the kilometres-walked total is preserved as a separate field, and the route view says once that "the route's stages were redrawn; your kilometres are kept." **Across Replace and Remove** the ledger file stays where it is, so a route that comes back finds its record.

## 6. Error handling

- A stage file or `route.json` that fails validation is refused as a package: the download reports "this route isn't walkable yet" and leaves nothing behind.
- A network failure mid-download reports "the download didn't finish" with a retry; the temporary set is discarded and whatever was on the phone before is untouched.
- A missing `ways` entry in the index hides the route.
- Index fetch failure with a route already downloaded degrades silently: the catalog shows what is on the phone, no "updated" badge.
- Disk full mid-download surfaces the existing `WayError.diskFull` copy.
- Download of a second route, Replace, Update, and Remove while a walk is active are refused with "finish your walk first".
- Offline on the trail (no tiles until slice three): the map shows the ghost line, moment pins, marks, and captions over the basemap's empty grey, and the overview says once "map tiles need a connection; the way itself is on your phone." Cards, water, the morning card, arrival, and the ledger all work without a network.
- All number fields pass the same range validation as the share importer before any `Int` conversion; every string field is capped at parse time.

## 7. Testing

- **open-pilgrimages:** fixture route tests for the build step (section 1.7); schema validation in the pipeline.
- **pilgrim-ios unit tests:** `PilgrimageWayImporterTests` (decode a fixture stage file and `route.json`; marks, stage block, moment `text`/`names`/`sitMinutes`/`pin`; range and cap rejection; the id allow-list; old `way.json` still decodes); `PilgrimageCatalogServiceTests` (index parse, slug and release-tag rejection, 24 h cache, byte cap, range rejection, hidden routes); `PilgrimagePackageManagerTests` (download into a temporary set then move; Replace downloads first and leaves the old route intact on failure; Update reconciles the ledger by identity; ledger survives Remove; all four refused mid-walk); `HonorMomentTrackerTests` (water mark fires once within 300 m before, never after, never off-way, not within the quiet hour, first one free); `ActiveWalkHonorTests` (pilgrimage source suppresses soft tap and companion; arrival card without delta; caption and haptic on `.markAhead`; arrival reply stored under origin −1 and offered back); `PilgrimageLedgerTests` (next stage, resume frac, km sum, no entry without an anchor, identity check across update, all-complete row); `WayPlaceCard` and header tests for `text`, local name selection, the sit button, and the stage fallback copy.
- **Device pass:** one real stage on the test device with location simulation from the stage's GPX (`WayGPXExporter`), checking pins at zoom and the per-screen cap in a town, a water caption and its quiet hour, a sit card at a sacred site, the morning card, the arrival reflection and reply, the ledger line afterward, and one leg in airplane mode.

## 8. Out of scope

Offline tiles, stage stamps and the credencial, sharing lineage to pilgrimag.es and per-route collective counts, route variants as walkable choices (the walked line is the main line only), reverse-direction stages, background index refresh, service pins that open anything, elevation profiles, any companion dot for stages, Android.

## 9. Open questions

1. **Cover images.** `route.json` names `cover.jpg`; the dataset has none yet. The build step falls back to a Mapbox Static image of the route bounds rendered at build time, committed alongside. Confirm with the dataset's licence that a Mapbox static render may be committed under ODbL data, or keep covers in the app bundle for the launch routes.
2. **Which routes at launch.** Decided by the report and the floor (1.5), not by the March list: that list names the Portugués, which has no curated waypoints, and routes the dataset does not carry. Expect the Camino Francés and Shikoku 88 first, once each has a walked line that passes the length gate; every other route needs curated places before it can be listed.
3. **The walked line.** Which routes can provide a `route.main.geojson` today, and how the dataset marks variants, is the first task of the open-pilgrimages plan; until a route has one it emits no package.
4. **`reflection` in the dataset schema.** Every current stage carries `interior.reflection`; making it required in `schema/` turns the narrative-last-sentence fallback into a guard that never fires.
