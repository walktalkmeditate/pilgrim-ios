# Honor Slice Three: Offline Maps for a Pilgrimage

**Date:** 2026-09-14
**Repo:** pilgrim-ios only. The dataset does not change.
**Builds on:** `2026-09-03-honor-slice-two-pilgrimage-stages-design.md` (shipped in PR #84: the pilgrimage package, one route at a time, the per-route ledger, the morning card) and PR #85 (sections grouped under their pilgrimage). Uses MapboxMaps 11.23.1 via SPM.
**Plan:** one, in pilgrim-ios. The Mapbox tile store sits behind a protocol so every task's tests run against a fake.
**Not in this slice:** a rolling "next few stages" window, wifi-only mode, automatic refresh of expired tiles, offline whispers or cairns, Android parity.

## Summary

A downloaded pilgrimage already carries everything it needs to be walked with no signal — the stage line, its places, its words — and draws all of it on a blank map, because the basemap under it is streamed. This slice saves the basemap too. One deliberate tap on the route page, sized before it is tapped, fetches Mapbox tile regions for every stage of the installed route; the walk screen, the overview and the morning card then render in a valley with no bars exactly as they do at home.

The package does not change. The download does not change. A second, optional step is added beside it, and the three lifecycle moments the package manager already has — Remove, Replace, Update — take the maps with them so nothing is ever orphaned.

## Decisions (from the 2026-09-14 brainstorm)

1. **Maps are a separate, opt-in tap, not part of Download.** The package is ~1.3 MB and instant; the maps are up to ~26 MB. A walker browsing routes should not pay for tiles, and a walker at home on wifi should be able to fetch them deliberately with the size in front of them. (Rejected: bundling tiles into Download, which makes one button mean two very different things; per-stage tiles fetched when a stage is begun, which puts a network step and a nightly chore in front of the walk.)
2. **Per stage in storage, whole way in one action.** One Mapbox tile region per stage, keyed like the stage's Way. The walker taps once for the whole route; the loop runs stage by stage so progress reads "stage 12 of 33", cancel keeps what is done, and a second tap resumes at the first gap. (Rejected: one region for the whole route — no partial progress, no resume; a rolling window of the next few stages — needs a ledger watcher and background fetching to save ~20 MB, and is a policy on top of per-stage regions if ever wanted.)
3. **Zoom ceiling: Streets to z15, terrain DEM to z14.** Measured on three Francés stages: z14 tiles already carry footpaths, tracks, hamlets and lodging POIs; z15 adds building footprints and nothing else; the DEM tileset has no z15. Whole-way sizes at these ceilings: Camino Francés ~26 MB, Nakahechi ~2 MB.
4. **Cellular is allowed; the size is the guardrail.** No wifi-only mode. The button carries the estimate; the walker decides. (Rejected: `NetworkRestriction.disallowCellular` with an override — one more state to draw for a 26 MB ceiling.)
5. **Two doors, one state.** The route page owns save / saved / progress. Settings → Data gets a "Maps" row beside "Ways" that shows what is saved and can delete it. Both read the same manager.
6. **Proof is a feature.** A `#if DEBUG` switch flips `OfflineSwitch.shared.isMapboxStackConnected` so a saved stage can be verified to render in a living room. Without it the feature ships on faith.
7. **The `.readOnly` tile store mode already set in `AppDelegate` is correct and stays.** It means: check the tile store first; if a tile pack covers the tile, use it; otherwise fetch the tile. That is exactly the behaviour a saved region needs. The earlier note that this would need switching to a "shared" mode was wrong.

## Vocabulary

- **Tile region** — Mapbox's unit of saved map data: a geometry plus tileset descriptors, loaded into the tile store under an id. Ours are per stage.
- **Style pack** — the style's own resources (style JSON, sprites, glyphs), saved once per style URI. We keep two, `.light` and `.dark`.
- **Tile pack** — Mapbox's internal bundle of a parent tile and its descendants, per tileset. Regions share packs; the account limit is on *unique* packs.
- **Corridor** — the polygon a stage's region is loaded for: the stage line buffered 500 m to each side.
- **Saved** — every stage of the installed route has a complete region, and both style packs are present.

## 1. Where the code lives

### 1.1 `PilgrimageTilesManager`

A new `@MainActor final class PilgrimageTilesManager: ObservableObject` in `Pilgrim/Models/Honor/`, a sibling of `PilgrimagePackageManager` with the same shape:

```swift
enum Phase: Equatable {
    case idle
    /// `total` counts the two style packs plus one region per stage.
    case saving(done: Int, total: Int)
    case failed(PilgrimageError)
}
@Published private(set) var phase: Phase = .idle

/// Set by `MainCoordinatorView`, like the package manager's.
var isWalkActive: () -> Bool = { false }

func status(for routeId: String, stageCount: Int) -> Status   // .none, .partial(saved:of:), .saved(bytes:)
func estimateBytes(for stages: [Way]) -> Int                  // corridor tile count × bytesPerTile
func save(routeId: String, stages: [Way]) async throws
func cancel()
func remove(routeId: String)                                   // every region with the route's prefix
```

The Mapbox objects are reached only through one protocol, injected at init:

```swift
protocol TileRegionLoading {
    func loadStylePack(styleURI: StyleURI, options: StylePackLoadOptions,
                       progress: @escaping (Int, Int) -> Void) -> AnyCancelable
    func loadRegion(id: String, options: TileRegionLoadOptions,
                    progress: @escaping (Int, Int) -> Void,
                    completion: @escaping (Result<TileRegionSummary, Error>) -> Void) -> AnyCancelable
    func regions() -> [TileRegionSummary]                      // our own value type: id, completedResourceCount, requiredResourceCount, bytes — not the SDK's TileRegion, so the fake needs no Mapbox type
    func removeRegion(id: String)
    func hasStylePack(styleURI: StyleURI) -> Bool
}
```

`MapboxTileRegionLoader` is the one production conformer, wrapping `OfflineManager` and `TileStore.default`. Tests inject a fake that records calls, fails on demand, and drives progress by hand.

### 1.2 Keys

A stage's region id is `WayStore.stageWayId(routeId:stageIndex:)` — `pilgrimage:<routeId>:<index>` — so a region and the Way it serves share one string. `remove(routeId:)` deletes every region whose id has the prefix `pilgrimage:<routeId>:`.

Style pack ids are the style URIs themselves; the SDK keys them that way.

### 1.3 Descriptors

Two `TilesetDescriptor`s, built once and reused for every region:

- Streets: `TilesetDescriptorOptions(styleURI: .light, zoomRange: 0...15, tilesets: nil)` and the same for `.dark`. The light and dark styles read the same Streets source, so the tile store holds each tile once.
- Terrain: `TilesetDescriptorOptions(styleURI: .light, zoomRange: 0...14, tilesets: ["mapbox://mapbox.mapbox-terrain-dem-v1"])`. The DEM is not in either base style — `PilgrimMapStyle.applyWabiSabiStyle` adds it at runtime — so it must be named here or the hillshade is blank offline. Its ceiling is 14 because the tileset has no z15; a test pins the number.

The zoom range starts at 0 on purpose: the route page and the overview fit a whole stage at around z11, and the region has to cover that as well as the walk screen's z16.

Style packs load with `StylePackLoadOptions(glyphsRasterizationMode: .ideographsRasterizedLocally)`, explicitly. Shikoku and Kumano labels are CJK; rasterizing ideographs on the device keeps the pack from carrying every glyph range. This is the SDK default, and it is written down so nobody "fixes" it.

## 2. Geometry

### 2.1 The corridor

`WayGeometry` gains one pure function:

```swift
static func corridor(around points: [CLLocationCoordinate2D], halfWidthMeters: Double) -> Polygon
```

It simplifies the line (Douglas–Peucker, 25 m tolerance — a 500 m buffer does not care about a 10 m wiggle), offsets each vertex ±`halfWidthMeters` along the perpendicular of its adjoining segments, and closes the ring: left side forward, right side back. Metres to degrees use the point's own latitude for longitude.

Half width is 500 m. A stage that runs 20 km diagonally is 400 km² as a bounding box and 20 km² as a corridor; at z15 that is the difference between thousands of tiles and hundreds.

The corridor is the region's `Geometry` in `TileRegionLoadOptions(geometry:descriptors:acceptExpired:)`.

### 2.2 The estimate

`estimateBytes(for:)` counts the distinct XYZ tiles the corridor touches at z10–15 (Streets) and z10–14 (DEM) and multiplies by `bytesPerTile`. The descriptors start at z0, but a corridor touches only a handful of tiles below z10 — a rounding error the estimate leaves out. That constant starts at the measured value from the design session — 10 KB, from three Francés tiles at z14/z15 — and **calibrates itself**: when a save completes, the tile store's real `completedResourceSize` divided by the region's tile count is written to `UserDefaults` under `pilgrimage.tiles.bytesPerTile`, and the next estimate uses it. After the first save the number stops being a guess.

The UI always writes the estimate as "~13 MB". Once saved it shows the real byte count with no tilde.

## 3. The save

### 3.1 The loop

```
guard !isWalkActive()            → throw .walkInProgress
guard phase == .idle             → return (one save at a time)
phase = .saving(done: 0, total: 2 + stages.count)
for style in [.light, .dark]:
    if !hasStylePack(style): loadStylePack(...)   // awaits completion
    done += 1
for stage in stages (by index):
    if regions()[stage.id] is complete: done += 1; continue
    loadRegion(id: stage.id, options: TileRegionLoadOptions(geometry: corridor, descriptors: [streets, terrain], acceptExpired: true))
    done += 1
phase = .idle
```

`acceptExpired: true` lets a resumed save on a flaky connection complete with cached-but-expired tiles instead of failing on them.

### 3.2 Cancel keeps what is done

`cancel()` cancels the in-flight `AnyCancelable` and sets `phase = .idle`. Regions already complete stay. Tapping save again runs the same loop, which skips every complete region and picks up at the first gap. There is no partial-download state to draw: the route page reads `status(for:)`, which is `.partial(saved: 12, of: 33)`, and offers the same button.

### 3.3 Resource safety

- The current `AnyCancelable` is stored on the manager and cancelled in `cancel()`, in `remove(routeId:)`, and in `deinit`.
- Every progress and completion closure captures `[weak self]`.
- One save in flight; a second call while `.saving` returns without doing anything, mirroring the package manager's guard.
- The SDK downloads in-process. There is no background `URLSession`; backgrounding the app mid-save pauses it, and resume covers the rest. At ~26 MB worst case a save is seconds on wifi.

### 3.4 Errors

`PilgrimageError` gains no new cases. A failed region load maps to `.incomplete` ("the download didn't finish"); a disk-full error from the store maps to `.diskFull`; `.walkInProgress` and `.catalogUnreachable` are reused as they are. The route page shows `PilgrimageCopy.line(for:)` under the button exactly as it does for a failed package download.

## 4. Lifecycle — nothing orphaned

`PilgrimagePackageManager` already has the three moments; each now calls the tiles manager, which it holds by reference:

- **`remove(routeId:)`** → `tiles.remove(routeId:)` after the stages are gone. Packs no other region references are freed by the store.
- **`replace(with:release:)`** → `tiles.remove(routeId: previous)` for the outgoing route. The incoming route starts with no maps; saving them is the same separate tap.
- **`update(entry:release:)`** → after the new stages land, if `tiles.status(for:)` was `.saved` or `.partial` before the update, `tiles.save(...)` runs again. Loading a region under an existing id replaces it in place, so a redrawn stage gets a corridor that matches its new line. A route that had no maps gets none.

Expired regions stay usable offline — the SDK serves them rather than dropping them — so a 33-day walk needs no refresh policy. Re-tapping save refreshes; nothing refreshes on its own.

## 5. What the walker sees

### 5.1 The route page

Under the existing download button, one row driven by `status(for:)` while idle and by `phase` while saving:

| status | row |
|---|---|
| package not installed | nothing — maps need stages |
| `.none` | button: **Save maps for the way · ~13 MB** |
| `.partial(12, of: 33)` | button: **Save maps for the way · 12 of 33 saved** |
| `.saved(bytes)` | check glyph, caption: **maps saved · 26 MB**, tappable to save again |
| `.saving(done, total)` | caption: **maps · stage 12 of 33**, and a **cancel** |

The check glyph is the same `checkmark.circle.fill` in `.moss` the catalog list uses for the installed route, so "on your phone" and "maps saved" read as one family. Copy is `Constants.Typography.caption` for captions and `.button` for the button, like the page around it.

### 5.2 The morning card

`StageMorningCard` gains one optional caption line, passed in as a `String?` by its caller, which computes it from `status(for:)` and the stage index:

- region complete → **maps saved for today**
- not complete → **no offline maps for today — save on wifi**

It sits with the weather line, before the button. Nothing is added to the walk screen; the minimalism rule holds there.

### 5.3 The catalog list

Unchanged. The install badge is the only glyph a row carries; map state lives on the route page.

### 5.4 Settings → Data

A **Maps** row on `DataCard`, a sibling of **Ways**, using `settingNavRow(label:detail:)`:

- detail **none saved** when nothing is saved
- detail **Camino Francés · 26 MB** otherwise (the route's display name from the installed package, bytes from the store)

It opens `OfflineMapsView`: the one saved pilgrimage, its byte count, the stage count saved, and **Delete maps**, which calls `tiles.remove(routeId:)` and leaves the stages alone. The footer says so: *"Removes the saved basemap. The route's stages stay on your phone."* One pilgrimage at a time keeps this a single entry rather than a list; the view is written for one and the row reads "none saved" when there is none.

### 5.5 The debug switch

`#if DEBUG`, on the same Data card: a toggle **simulate no signal for maps** bound to `OfflineSwitch.shared.isMapboxStackConnected` (inverted). It forces the Mapbox stack offline without airplane mode, so a saved stage can be opened on the walk screen and seen to render — or not — at home. It is the acceptance test for this slice on a real device and the hook a screenshot test can use.

## 6. Storage facts to verify

Two properties of `TileStore.default` are load-bearing and are verified by the plan, each with a test:

1. **Its directory is under Application Support, not Caches.** A Caches location is purgeable under storage pressure, and a walker on day 20 could lose the maps for day 21. If the SDK's default is not Application Support, the store is created at an explicit path under it.
2. **It is excluded from iCloud backup.** ~26 MB of re-downloadable tiles should not sync. If the SDK does not set `isExcludedFromBackup`, the app does, after the store is created.

Neither the package's `maxPackageBytes` (a JSON ceiling) nor a tile store `DiskQuota` applies to the save. With one pilgrimage at a time and a ~26 MB ceiling across the whole catalog, there is nothing to quota. The ambient cache keeps the SDK's defaults.

## 7. Testing

Everything below runs against the `TileRegionLoading` fake; no test touches Mapbox.

- **Order and skipping:** a save loads style packs first, then regions in stage order; a region already complete is skipped; a style pack already present is skipped.
- **Cancel keeps done, resume starts at the gap:** cancel after stage 12 of 33 leaves 12 complete regions; the next save's first load is stage 13.
- **Remove clears exactly the prefix:** regions for `pilgrimage:camino-frances:` go; a region for another route id stays; both style packs stay.
- **Update re-saves only if maps were saved:** `.saved` and `.partial` trigger a save after update; `.none` does not.
- **Refused while walking:** `isWalkActive` true → `.walkInProgress`, no load calls.
- **One at a time:** a second `save` during `.saving` makes no calls.
- **Corridor polygon:** a straight line yields a rectangle of the right width; a right-angle bend yields a ring that contains the bend's outer corner; the Francés stage 0 line yields a ring whose area is within 20 % of length × 1 km.
- **Estimate:** the tile count for the Nakahechi corridor at z10–15 is 129 (the design session's figure) and the estimate scales with `bytesPerTile`; a completed save updates `bytesPerTile` from the real byte count.
- **Ceilings:** the terrain descriptor's zoom range ends at 14 and the Streets descriptor's at 15; the terrain descriptor names `mapbox://mapbox.mapbox-terrain-dem-v1`; both start at 0.
- **Glyphs:** style packs are requested with `.ideographsRasterizedLocally`.
- **Errors:** a failing region load surfaces `.incomplete` and leaves earlier regions in place; a disk-full error surfaces `.diskFull`.
- **Status and copy:** `status(for:)` across none / partial / saved; the row label and the morning-card line for each.
- **Store location and backup exclusion**, per section 6.

## 8. Out of scope

- A rolling window of the next N stages, auto-advanced from the ledger.
- A wifi-only mode.
- Automatic refresh of expired regions.
- Offline whispers, cairns, companion — none of it is tiles, and all of it degrades offline exactly as today.
- The saved corridor drawn on the route page map. Considered and declined: it is noise on a page that already says "maps saved".
- Saving maps automatically on download or on wifi. Declined: decision 1 was made to keep this a deliberate act.
- Android.

## 9. Open questions

None that block the plan. Two facts are verified during it rather than assumed (section 6). The Mapbox account's offline billing is recorded in the 2026-09-01 decisions as MAU-included; the design session could not find a documentation sentence that says so in as many words, and the pack limit — *"the cumulative number of unique tile packs cannot exceed 750"* — is an order of magnitude above the whole catalog installed at once.
