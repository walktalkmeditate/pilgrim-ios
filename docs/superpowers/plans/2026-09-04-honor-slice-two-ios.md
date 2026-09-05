# Honor Slice Two — Pilgrimage Stages as Ways (iOS) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A pilgrim downloads one route from the open-pilgrimages dataset and walks it stage by stage — each stage a Way the existing Honor engine walks unchanged, with the stage's places as cards, its services as quiet map pins, water as a caption, and the stage's own words at Begin and at arrival.

**Architecture:** Nothing about `HonorEngine` changes except one new event. What changes is *where a Way comes from* (a new `PilgrimageWayImporter` beside `WayImporter`, fed by a `PilgrimageCatalogService` and a `PilgrimagePackageManager`), *what a card can carry* (`text`, `names`, `sitMinutes`, `pin` on `WayMoment`; `marks` and `stage` on `Way`), and *what the walker sees before and after* (a morning card, an arrival reflection, and a per-route `PilgrimageLedger`). The Way file format is the only contract with the dataset repo; this plan consumes a fixture package checked into the test tree (Task 1) so it never waits on the dataset build.

**Tech Stack:** Swift 5.10 / SwiftUI / Combine / CoreStore / MapboxMaps 11.20 (SPM) / XCTest. Spec: `docs/superpowers/specs/2026-09-03-honor-slice-two-pilgrimage-stages-design.md` (sections 2–7). Slice one: `docs/superpowers/specs/2026-09-01-honor-mode-design.md`, `docs/superpowers/plans/2026-09-01-honor-mode-slice-one.md`.

## Global Constraints

- Typography: always `Constants.Typography.*` (`displayLarge`/`displayMedium`/`heading`/`body`/`timer`/`statValue`/`statLabel`/`button`/`caption`). Never `.system()`, never a SwiftUI default font.
- Colors from the palette (`.stone`, `.ink`, `.fog`, `.parchment`, `.parchmentSecondary`, `.moss`, `.rust`, `.dawn`). Map layers take fixed hexes, never adaptive colors.
- Comments explain **why**, never **what**. No commented-out code, no restating the line below.
- Every `DispatchQueue.main.asyncAfter` and every `Timer` in honor code is generation-guarded (`honorGeneration`) and has a cancellation path in `teardownHonor()`. Every Combine sink uses `[weak self]` and is stored in `honorCancellables`. Every OS callback closure uses `[weak self]`.
- New Swift files are NOT auto-registered: `Pilgrim/` and `UnitTests/` are plain `PBXGroup`s. Every task that creates a `.swift` file runs `ruby scripts/xcode-add.rb <Pilgrim|UnitTests> <repo-relative-path>` in the step that creates it, and commits `Pilgrim.xcodeproj/project.pbxproj`.
- Build: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build`
- Test one suite: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/<ClassName>`
- SwiftLint runs on commit. `type_body_length` **errors** at 750 — extract subviews before a struct nears 700 lines. `implicit_optional_initialization` forbids `= nil` on an optional declaration. Run `swiftlint` over the repo before pushing.
- Every task's tests must pass before its commit. Every commit compiles.
- Branch `feat/honor-slice-two`. **Never commit to `main`.** Every commit message ends with:
  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  ```
- **CDN URLs, verbatim:**
  - Catalog: `https://cdn.jsdelivr.net/gh/walktalkmeditate/open-pilgrimages@main/index.json`
  - Package file: `https://cdn.jsdelivr.net/gh/walktalkmeditate/open-pilgrimages@<release>/routes/<route-id>/ways/<file>`
  - **Never the `@v1` alias.** jsDelivr caches a tag URL permanently, so a moving `v1` tag serves whatever bytes it first saw — verified: `@v1/index.json` returns a March index with three routes while `@v1.6.0` has seven. A branch ref refreshes on jsDelivr's own 12 h cycle, and our 24 h cache sits on top of it. Packages stay pinned at the exact `release` tag the index names, because those tags never move.
- **Regexes, verbatim (spec 2.4, 2.5):**
  - route id: `[a-z0-9-]{1,64}`
  - release tag: `v[0-9]+\.[0-9]+\.[0-9]+`
  - Way id allow-list gains: `pilgrimage:[a-z0-9-]{1,64}:[0-9]{1,3}`
- **Ranges (spec 2.4):** distance 0–10,000 km; stage count 1–200; bytes under 50 MB. All number fields pass range validation **before** any `Int(_:)` conversion. Every string field is capped at parse time.
- **String caps (spec 1.3–1.5):** theme 80, narrative 2,000, closing 400, each warning 300, stage name 120, mark name 80, moment `text` 600, route summary 600. Reuse `WayImporter.maxLabelCharacters` (80) and `maxIconCharacters` (64).
- **Byte ceilings:** `index.json` 256 KB; `route.json` 512 KB; each `stage-NN.json` 2 MB. `expectedContentLength` is checked before draining, then a running cap while streaming — the shape `WayImporter.importShare` uses.
- **Copy strings, verbatim — never paraphrase:**
  - `"the routes are out of reach right now"`
  - `"finish your walk first"`
  - `"this route isn't walkable yet"`
  - `"the download didn't finish"`
  - `"Replace the Camino Francés? Its stages leave your phone; what you've walked of it is remembered if it comes back. Walks in your journal stay."` (the route name is interpolated)
  - `"you have walked the whole way"`
  - `"the route's stages were redrawn; your kilometres are kept."`
  - `"map tiles need a connection; the way itself is on your phone."`
  - `"A place on the way."`
- **User's stated preference:** nothing new in the bottom stats sheet. The water notice borrows the *existing* caption slot (`viewModel.softTapCaption`, rendered by `WalkStatsSheet.thirdStat`) — no new stat, no new row.
- **Resource safety (`.claude/CLAUDE.md`):** one player per role; no accumulating timers; `[weak self]` in `CMAltimeter`/`CMPedometer`/`NWPathMonitor` callbacks; if unsure whether something leaks, take the simpler shape.
- **The device pass is gated on the dataset, and the dataset is not there yet.** Nothing on the CDN serves a ways build today: `index.json` on `main` carries no top-level `release` and no per-route `ways` entry, and no `vX.Y.Z` tag carries `routes/<route-id>/ways/route.json` or `stage-NN.json`. Until the open-pilgrimages ways build lands on `main` **and** a release tag carries the package files, the catalog correctly shows "the routes are out of reach right now" and no stage can be downloaded on a device. Every task here is proven by the fixture-driven unit tests; **Task 16's device pass cannot be run, and the slice is not shippable, until that build exists.** Do not treat an empty catalog on a device as a bug in this code.

## File map

**New — models (`Pilgrim/Models/Honor/`):**
- `PilgrimageWayImporter.swift` — the stage-file and `route.json` wire formats, validation, and the `Way` they build.
- `PilgrimageCatalogService.swift` — `index.json` fetch, 24 h cache, slug/release validation, hidden routes.
- `PilgrimageLedger.swift` — the per-route record, its store, and the pure writer.
- `PilgrimagePackageManager.swift` — download / replace / update / remove, the mid-walk guard, `PilgrimageError` and its copy.
- `WayMarkPins.swift` — the pure zoom-and-cap selector for service pins.

**New — scenes (`Pilgrim/Scenes/Honor/`):**
- `PilgrimageCatalogView.swift` — the third door's list of routes.
- `PilgrimageRouteView.swift` — cover plate, summary, next row, stage list, Download/Update, overflow Remove.
- `StageMorningCard.swift` — the stage's words at Begin, reopenable as "the day".

**New — tests (`UnitTests/`):**
- `Fixtures/PilgrimageFixtures.swift` + `Fixtures/Pilgrimage/{index.json,route.json,stage-00.json,stage-01.json}`
- `Helpers/StubURLProtocol.swift`
- `Honor/PilgrimageWayImporterTests.swift`, `PilgrimageCatalogServiceTests.swift`, `PilgrimageLedgerTests.swift`, `PilgrimagePackageManagerTests.swift`, `PilgrimageStageSurfacesTests.swift`, `WayMarkPinsTests.swift`

**Modified:** `Pilgrim/Models/Honor/Way.swift`, `WayStore.swift`, `HonorTuning.swift`, `HonorMomentTracker.swift`, `HonorEngine.swift`, `WayMediaDownloader.swift`; `Pilgrim/Models/Haptics/HapticManager.swift`; `Pilgrim/Models/Walk/WalkMode.swift`; `Pilgrim/Models/Walk/MapManagement/PilgrimAnnotation.swift`; `Pilgrim/Models/Prompt/ActivityContext.swift`; `Pilgrim/Models/Prompt/PromptAssembler.swift`; `Pilgrim/Views/PilgrimMapView.swift`, `PilgrimMapView+HonorWay.swift`; `Pilgrim/Scenes/Honor/HonorWaysSheet.swift`, `HonorOverviewView.swift`, `WayMomentHeader.swift`, `WayMomentPreview.swift`; `Pilgrim/Scenes/ActiveWalk/ActiveWalkViewModel.swift`, `ActiveWalkViewModel+Honor.swift`, `ActiveWalkView.swift`, `ActiveWalkView+Map.swift`, `ActiveWalkView+Honor.swift`, `WayPlaceCard.swift`; `Pilgrim/Scenes/Settings/WaysListView.swift`; `Pilgrim/Scenes/Root/MainCoordinatorView.swift`, `MainTabView.swift`; `Pilgrim/Scenes/WalkSummary/HonorSummarySection.swift`, `WalkSummaryView.swift`.

**New — docs:** `docs/honor-slice-two-device-pass.md`.

## Resolved spec ambiguities

1. **The arrival reply's surface (spec 3.5 / 4.2).** 4.2 routes the reply through `ActiveWalkViewModel.replyHere`, which needs a live recorder; the summary has none. Resolution: the **arrival card on the walk** carries the closing line and the "reply here" button (that is where `replyHere` works); the **summary's honor block** carries the stage line, the closing line, and — when a reply exists — a "your reply" play button. Both use the reserved origin `-1`. *(The spec has since been revised to say the same — decision 4 and the Vocabulary entry now read "on the arrival card … echoed on the summary" — so no deviation remains.)*
2. **Cover images (open question 1).** The dataset has none and `index.json` carries no `cover` field. Resolution: no cover downloads in this slice. A parchment plate with the route's initial stands where the cover will go; `route.json`'s `cover` field is parsed and ignored. The open question stays open.
3. **`index.json`'s real shape.** The live file is `{schemaVersion, generatedAt, routes: [{id, name: {locale: String}, region, country, distanceKm, topology, tradition, path, variants?}]}`. `name` is a **map**, not a string (spec 1.5's string `name` belongs to `route.json`). The catalog entry therefore picks `name["en"]` and keeps the map as `names`.
4. **The stage file is a wire format, not a Swift-encoded `Way`.** Spec 1.3's flat field table (`label`, `icon`, `text`, `names`, `sitMinutes`, `at`, `pin`) is not what `JSONEncoder` emits for `WayMomentKind`. `PilgrimageWayImporter` decodes the flat wire format and builds a `Way`, exactly as `WayImporter` decodes `TourManifest`.
5. **Foreground session for package downloads.** Spec 2.3 says "the background-session … handling follow[s] `WayMediaDownloader`'s pattern", but an all-or-nothing temp set that "leaves nothing" on failure cannot survive app suspension anyway. Resolution: a foreground `URLSession.bytes` per file with the streamed cap (the `WayImporter.importShare` shape); only the **disk-full detection** is reused from `WayMediaDownloader`.
6. **Fixtures are loaded by `#filePath`, not bundled.** `scripts/xcode-add.rb` writes to the *sources* build phase; JSON would need the resources phase. Loading the four fixture files from the source tree via `#filePath` avoids touching the resource plumbing at all.
7. **The catalog reads `@main`, not the `@v1` alias.** jsDelivr caches a tag URL permanently, so a tag the release step moves keeps serving the bytes it first saw — verified: `@v1/index.json` returns a March index with three routes while `@v1.6.0` has seven. The catalog therefore reads the default branch, which jsDelivr refreshes on a 12 h cycle, with the 24 h cache on top. **Package files are unchanged** — they stay pinned at the exact `release` tag the index names, which is exactly the case tag caching handles correctly. *(Spec 1.6 has since been revised to `@main` with the same reasoning; the plan and the spec agree.)*
8. **`sparse` is a caption, not a filter.** The index's per-route `ways` entry gains `placesPerStage` and `sparse` (true when fewer than half a route's stages carry a curated place beyond the start and end towns — the Camino Francés today, at 7 of 33). A sparse route is still listed and still walkable; it simply says "few places marked yet" on its catalog card and under its summary. Both fields are optional on the wire so an index written before them still parses, as a dense route with no figure. *(Spec 1.5 has since been revised from a hard coverage floor to this flag; the plan and the spec agree.)*

---

## Task 1: The fixture package and the model the stages decode into

**Files:**
- Create: `UnitTests/Fixtures/PilgrimageFixtures.swift`
- Create: `UnitTests/Fixtures/Pilgrimage/index.json`
- Create: `UnitTests/Fixtures/Pilgrimage/route.json`
- Create: `UnitTests/Fixtures/Pilgrimage/stage-00.json`
- Create: `UnitTests/Fixtures/Pilgrimage/stage-01.json`
- Modify: `Pilgrim/Models/Honor/Way.swift`
- Modify: `Pilgrim/Models/Honor/WayStore.swift:55-57`
- Test: `UnitTests/Honor/PilgrimageWayImporterTests.swift` (created here, grown in Task 2)

**Interfaces:**
- Produces: `WayMarkKind` (`.water .food .bed .transport .supply .medical`, `String` raw values); `WayMark(id:kind:name:at:frac:offLineMeters:)`; `WayStageHours(min:max:)`; `WayStagePlace(name:at:)`; `WayStage(routeId:index:count:name:theme:narrative:closing:warnings:distanceKm:gainMeters:hours:difficulty:start:end:)`.
- Produces on `WayMoment`: `var text: String?`, `var names: [String: String]?`, `var sitMinutes: Int?`, `var pin: WayCoordinate?` — optional and last, so every existing `WayMoment(id:frac:at:kind:)` call site keeps compiling and every existing `way.json` still decodes.
- Produces on `Way`: `var marks: [WayMark]?`, `var stage: WayStage?` — optional and last, after `spans`.
- Produces `WaySource.pilgrimage(routeId: String, stageIndex: Int)`.
- Produces `WayStore.isValidRouteId(_:) -> Bool`, `WayStore.stageWayId(routeId:stageIndex:) -> String`, `WayStore.pilgrimageDirectory(for routeId: String) -> URL?`, and a widened `WayStore.isValidId`.
- Produces `PilgrimageFixtures.data(_ name: String) throws -> Data` and `PilgrimageFixtures.directory`.

- [ ] **Step 1: Write the fixture package**

`UnitTests/Fixtures/Pilgrimage/stage-00.json` — a 1 km stage running east along the equator, so every distance in the tests is arithmetic. Two card moments (one with `text` and `names` and `sitMinutes`, one with neither), one water mark on the line, one water mark 250 m off it, one food mark:

```json
{
  "id": "pilgrimage:camino-frances:0",
  "title": "Saint-Jean-Pied-de-Port to Roncesvalles",
  "departedAt": "2026-08-19T15:31:51Z",
  "tzIdentifier": "Europe/Madrid",
  "route": [
    { "lat": 0, "lon": 0.0, "alt": 170, "t": 0 },
    { "lat": 0, "lon": 0.000898, "alt": 260, "t": 2880 },
    { "lat": 0, "lon": 0.001796, "alt": 420, "t": 5760 },
    { "lat": 0, "lon": 0.002694, "alt": 700, "t": 8640 },
    { "lat": 0, "lon": 0.003592, "alt": 980, "t": 11520 },
    { "lat": 0, "lon": 0.004490, "alt": 1180, "t": 14400 },
    { "lat": 0, "lon": 0.005388, "alt": 1300, "t": 17280 },
    { "lat": 0, "lon": 0.006286, "alt": 1400, "t": 20160 },
    { "lat": 0, "lon": 0.007184, "alt": 1420, "t": 23040 },
    { "lat": 0, "lon": 0.008082, "alt": 1300, "t": 25920 },
    { "lat": 0, "lon": 0.008980, "alt": 950, "t": 28800 }
  ],
  "totalDistanceMeters": 1000,
  "theirActiveSeconds": 28800,
  "moments": [
    {
      "id": "wp-saint-jean",
      "frac": 0.0,
      "kind": "waypoint",
      "label": "Saint-Jean-Pied-de-Port",
      "icon": "house.lodge",
      "at": { "lat": 0, "lon": 0.0 },
      "pin": { "lat": 0, "lon": 0.0 }
    },
    {
      "id": "wp-orisson",
      "frac": 0.3,
      "kind": "waypoint",
      "label": "Vierge d'Orisson",
      "icon": "building.columns",
      "text": "A shepherd carried this Madonna up from Lourdes.",
      "names": { "eu": "Orissongo Ama Birjina", "fr": "Vierge d'Orisson" },
      "sitMinutes": 5,
      "at": { "lat": 0, "lon": 0.002694 },
      "pin": { "lat": 0, "lon": 0.002700 }
    },
    {
      "id": "wp-roncesvalles",
      "frac": 1.0,
      "kind": "waypoint",
      "label": "Roncesvalles",
      "icon": "house.lodge",
      "at": { "lat": 0, "lon": 0.008980 },
      "pin": { "lat": 0, "lon": 0.008980 }
    }
  ],
  "marks": [
    { "id": "wp-fuente-roldan", "kind": "water", "name": "Fuente de Roldán", "at": { "lat": 0, "lon": 0.004490 }, "frac": 0.5, "offLineMeters": 12 },
    { "id": "wp-fuente-lejos", "kind": "water", "name": "Fuente lejana", "at": { "lat": 0.00224, "lon": 0.006286 }, "frac": 0.7, "offLineMeters": 250 },
    { "id": "wp-bar-orisson", "kind": "food", "name": "Refuge Orisson", "at": { "lat": 0, "lon": 0.002694 }, "frac": 0.3, "offLineMeters": 20 }
  ],
  "stage": {
    "routeId": "camino-frances",
    "index": 0,
    "count": 2,
    "name": "Saint-Jean-Pied-de-Port to Roncesvalles",
    "theme": "Initiation",
    "narrative": "The Pyrenees are the first question the way asks.",
    "closing": "You crossed a border on foot. Few things are still done this way.",
    "warnings": ["The Napoleon Route closes in winter."],
    "distanceKm": 24.2,
    "gainMeters": 1419,
    "hours": { "min": 7, "max": 9 },
    "difficulty": "hard",
    "start": { "name": "Saint-Jean-Pied-de-Port", "at": { "lat": 0, "lon": 0.0 } },
    "end": { "name": "Roncesvalles", "at": { "lat": 0, "lon": 0.008980 } }
  }
}
```

`UnitTests/Fixtures/Pilgrimage/stage-01.json` — a second stage, no marks, no `text` on its one moment (the fallback-copy fixture):

```json
{
  "id": "pilgrimage:camino-frances:1",
  "title": "Roncesvalles to Zubiri",
  "departedAt": "2026-08-19T15:31:51Z",
  "tzIdentifier": "Europe/Madrid",
  "route": [
    { "lat": 0, "lon": 0.008980, "alt": 950, "t": 0 },
    { "lat": 0, "lon": 0.013470, "alt": 900, "t": 7200 },
    { "lat": 0, "lon": 0.017960, "alt": 520, "t": 14400 }
  ],
  "totalDistanceMeters": 1000,
  "theirActiveSeconds": 14400,
  "moments": [
    {
      "id": "wp-zubiri",
      "frac": 1.0,
      "kind": "waypoint",
      "label": "Zubiri",
      "icon": "house.lodge",
      "at": { "lat": 0, "lon": 0.017960 },
      "pin": { "lat": 0, "lon": 0.017960 }
    }
  ],
  "marks": [],
  "stage": {
    "routeId": "camino-frances",
    "index": 1,
    "count": 2,
    "name": "Roncesvalles to Zubiri",
    "theme": "Descent",
    "narrative": "Down through beech woods.",
    "closing": "The mountain is behind you now.",
    "warnings": [],
    "distanceKm": 21.9,
    "gainMeters": 217,
    "hours": { "min": 5, "max": 7 },
    "difficulty": "moderate",
    "start": { "name": "Roncesvalles", "at": { "lat": 0, "lon": 0.008980 } },
    "end": { "name": "Zubiri", "at": { "lat": 0, "lon": 0.017960 } }
  }
}
```

`UnitTests/Fixtures/Pilgrimage/route.json`:

```json
{
  "id": "camino-frances",
  "name": "Camino de Santiago (Francés)",
  "names": { "es": "Camino de Santiago (Francés)", "gl": "Camiño de Santiago (Francés)" },
  "country": "ES",
  "region": "Europe",
  "distanceKm": 46.1,
  "stageCount": 2,
  "tradition": "christian",
  "summary": "The most walked of the caminos.",
  "cover": "cover.jpg",
  "stages": [
    { "index": 0, "name": "Saint-Jean-Pied-de-Port to Roncesvalles", "distanceKm": 24.2, "gainMeters": 1419, "hours": { "min": 7, "max": 9 }, "difficulty": "hard" },
    { "index": 1, "name": "Roncesvalles to Zubiri", "distanceKm": 21.9, "gainMeters": 217, "hours": { "min": 5, "max": 7 }, "difficulty": "moderate" }
  ]
}
```

`UnitTests/Fixtures/Pilgrimage/index.json` — the live shape, with one listed route that the build marked sparse (as the Camino Francés is today), one route that failed the length gate and so carries no `ways` entry, and one route whose slug is illegal. The third route also omits `placesPerStage` and `sparse`, so the parse is exercised against an index written before those fields existed:

```json
{
  "schemaVersion": "1.0.0",
  "generatedAt": "2026-08-19T15:31:51.448Z",
  "release": "v1.7.0",
  "routes": [
    {
      "id": "camino-frances",
      "name": { "en": "Camino de Santiago (Frances)", "es": "Camino de Santiago (Francés)" },
      "region": "Europe",
      "country": "ES",
      "distanceKm": 46.1,
      "topology": "linear",
      "tradition": "christian",
      "path": "routes/camino-frances",
      "ways": { "stageCount": 2, "bytes": 214000, "placesPerStage": 0.4, "sparse": true }
    },
    {
      "id": "camino-norte",
      "name": { "en": "Camino del Norte (Northern Way)" },
      "region": "Europe",
      "country": "ES",
      "distanceKm": 784,
      "topology": "linear",
      "tradition": "christian",
      "path": "routes/camino-norte"
    },
    {
      "id": "../etc/passwd",
      "name": { "en": "Not a route" },
      "region": "Europe",
      "country": "ES",
      "distanceKm": 10,
      "topology": "linear",
      "tradition": "christian",
      "path": "routes/x",
      "ways": { "stageCount": 1, "bytes": 100 }
    }
  ]
}
```

- [ ] **Step 2: Write the fixture loader**

`UnitTests/Fixtures/PilgrimageFixtures.swift`:

```swift
import Foundation

/// The fixture package the iOS plan walks against, so section 2–7 work never
/// waits on the open-pilgrimages build. Read from the source tree through
/// `#filePath` rather than the test bundle: `scripts/xcode-add.rb` registers
/// sources, and adding a resources build phase for four JSON files would be
/// more plumbing than the fixtures are worth.
enum PilgrimageFixtures {

    static var directory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Pilgrimage", isDirectory: true)
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(name))
    }
}
```

- [ ] **Step 3: Write the failing test**

`UnitTests/Honor/PilgrimageWayImporterTests.swift`:

```swift
import XCTest
@testable import Pilgrim

final class PilgrimageWayImporterTests: XCTestCase {

    func testFixturePackageIsReadable() throws {
        XCTAssertFalse(try PilgrimageFixtures.data("stage-00.json").isEmpty)
        XCTAssertFalse(try PilgrimageFixtures.data("stage-01.json").isEmpty)
        XCTAssertFalse(try PilgrimageFixtures.data("route.json").isEmpty)
        XCTAssertFalse(try PilgrimageFixtures.data("index.json").isEmpty)
    }

    /// The build marks a route sparse when fewer than half its stages carry a
    /// curated place beyond the start and end towns — true of the Camino
    /// Francés today. The fixture must carry both fields, and one route must
    /// omit them, so the parse is exercised against an older index too.
    func testTheFixtureIndexCarriesTheSparseFlag() throws {
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try PilgrimageFixtures.data("index.json")) as? [String: Any])
        let routes = try XCTUnwrap(json["routes"] as? [[String: Any]])
        let ways = try XCTUnwrap(routes.first?["ways"] as? [String: Any])
        XCTAssertEqual(ways["placesPerStage"] as? Double, 0.4)
        XCTAssertEqual(ways["sparse"] as? Bool, true)
        let older = try XCTUnwrap(routes.last?["ways"] as? [String: Any])
        XCTAssertNil(older["sparse"], "an index written before the flag existed")
        XCTAssertNil(older["placesPerStage"])
    }

    func testAStageWayCarriesMarksAndAStageBlock() throws {
        let stage = WayStage(
            routeId: "camino-frances", index: 0, count: 33,
            name: "Saint-Jean-Pied-de-Port to Roncesvalles", theme: "Initiation",
            narrative: "The Pyrenees are …", closing: "You crossed a border on foot.",
            warnings: ["The Napoleon Route closes in winter."],
            distanceKm: 24.2, gainMeters: 1419,
            hours: WayStageHours(min: 7, max: 9), difficulty: "hard",
            start: WayStagePlace(name: "Saint-Jean-Pied-de-Port", at: WayCoordinate(lat: 43.163, lon: -1.236)),
            end: WayStagePlace(name: "Roncesvalles", at: WayCoordinate(lat: 43.01, lon: -1.319)))
        let mark = WayMark(id: "wp-fuente-roldan", kind: .water, name: "Fuente de Roldán",
                           at: WayCoordinate(lat: 43.1, lon: -1.3), frac: 0.42, offLineMeters: 40)
        var moment = WayMoment(id: "wp-orisson", frac: 0.3, at: WayCoordinate(lat: 0, lon: 0.0027),
                               kind: .waypoint(label: "Vierge d'Orisson", icon: "building.columns"))
        moment.text = "A shepherd carried this Madonna up from Lourdes."
        moment.names = ["fr": "Vierge d'Orisson"]
        moment.sitMinutes = 5
        moment.pin = WayCoordinate(lat: 0, lon: 0.0028)
        var way = Way(id: "pilgrimage:camino-frances:0",
                      source: .pilgrimage(routeId: "camino-frances", stageIndex: 0),
                      title: stage.name, departedAt: Date(timeIntervalSince1970: 1_700_000_000),
                      tzIdentifier: "Europe/Madrid", expires: nil,
                      route: [WayPoint(lat: 0, lon: 0, alt: nil, t: 0),
                              WayPoint(lat: 0, lon: 0.00898, alt: nil, t: 28_800)],
                      totalDistanceMeters: 1000, theirActiveSeconds: 28_800,
                      moments: [moment], weather: nil)
        way.marks = [mark]
        way.stage = stage

        let data = try JSONEncoder().encode(way)
        let round = try JSONDecoder().decode(Way.self, from: data)
        XCTAssertEqual(round, way)
        XCTAssertEqual(round.stage?.hours.max, 9)
        XCTAssertEqual(round.marks?.first?.kind, .water)
        XCTAssertEqual(round.moments.first?.sitMinutes, 5)
        XCTAssertEqual(round.moments.first?.pin, WayCoordinate(lat: 0, lon: 0.0028))
    }

    /// A `way.json` written before this slice must still decode, as an
    /// unmarked, unstaged Way.
    func testAWayWrittenBeforeStagesStillDecodes() throws {
        let json = """
        {"id":"share:Qoi4YmPHLN",
         "source":{"share":{"id":"Qoi4YmPHLN","pageURL":"https://walk.pilgrimapp.org/Qoi4YmPHLN"}},
         "title":"Rúa do Franco → Obradoiro","departedAt":"2026-08-01T07:00:00Z",
         "expires":"2099-01-01T00:00:00Z",
         "route":[{"lat":42.88,"lon":-8.545,"t":0},{"lat":42.88,"lon":-8.540,"t":400}],
         "totalDistanceMeters":420,"theirActiveSeconds":400,
         "moments":[{"id":"waypoint-1","frac":0.5,"kind":{"waypoint":{"label":"Oak","icon":"leaf"}}}]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let way = try decoder.decode(Way.self, from: Data(json.utf8))
        XCTAssertNil(way.marks)
        XCTAssertNil(way.stage)
        XCTAssertNil(way.moments[0].text)
        XCTAssertNil(way.moments[0].pin)
    }

    func testTheStoreAcceptsStageIdsAndRefusesEverythingElse() throws {
        XCTAssertTrue(WayStore.isValidId("pilgrimage:camino-frances:0"))
        XCTAssertTrue(WayStore.isValidId("pilgrimage:camino-frances:199"))
        XCTAssertFalse(WayStore.isValidId("pilgrimage"))
        XCTAssertFalse(WayStore.isValidId("pilgrimage:../etc:0"))
        XCTAssertFalse(WayStore.isValidId("pilgrimage:Camino:0"), "slugs are lowercase")
        XCTAssertFalse(WayStore.isValidId("pilgrimage:camino-frances:1000"))
        XCTAssertTrue(WayStore.isValidRouteId("camino-frances"))
        XCTAssertFalse(WayStore.isValidRouteId("../etc/passwd"))
        XCTAssertEqual(WayStore.stageWayId(routeId: "camino-frances", stageIndex: 7),
                       "pilgrimage:camino-frances:7")
    }

    func testAStageWayRoundTripsThroughTheStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let store = WayStore(baseDirectory: dir)
        var way = Way(id: "pilgrimage:camino-frances:0",
                      source: .pilgrimage(routeId: "camino-frances", stageIndex: 0),
                      title: "s", departedAt: Date(), tzIdentifier: nil, expires: nil,
                      route: [WayPoint(lat: 0, lon: 0, alt: nil, t: 0),
                              WayPoint(lat: 0, lon: 0.001, alt: nil, t: 60)],
                      totalDistanceMeters: 111, theirActiveSeconds: 60, moments: [], weather: nil)
        way.marks = []
        try store.save(way)
        XCTAssertEqual(store.load(id: "pilgrimage:camino-frances:0")?.id, way.id)
        let packageDir = try XCTUnwrap(store.pilgrimageDirectory(for: "camino-frances"))
        XCTAssertTrue(packageDir.path.hasSuffix("pilgrimage/camino-frances"))
        XCTAssertNil(store.pilgrimageDirectory(for: "../etc"))
        XCTAssertTrue(store.list().contains { $0.id == way.id },
                      "the package folder is not a way id, so list() steps over it")
    }
}
```

- [ ] **Step 4: Register the new files and run the test to verify it fails**

```bash
mkdir -p UnitTests/Fixtures/Pilgrimage
ruby scripts/xcode-add.rb UnitTests UnitTests/Fixtures/PilgrimageFixtures.swift
ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/PilgrimageWayImporterTests.swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/PilgrimageWayImporterTests 2>&1 | grep -E "error:|Executed"
```
Expected: compile errors — `cannot find 'WayStage' in scope`, `type 'WaySource' has no member 'pilgrimage'`, `value of type 'WayStore' has no member 'pilgrimageDirectory'`.

- [ ] **Step 5: Extend `Way.swift`**

Add above `enum WaySource` in `Pilgrim/Models/Honor/Way.swift`:

```swift
/// A service point on the stage: drawn on the map, never a moment, never
/// tappable. The six kinds the dataset carries.
enum WayMarkKind: String, Codable, Equatable {
    case water, food, bed, transport, supply, medical
}

struct WayMark: Codable, Equatable, Identifiable {
    let id: String
    let kind: WayMarkKind
    let name: String
    let at: WayCoordinate
    /// Projection onto the stage slice: what the water watcher compares the
    /// walker's progress against.
    let frac: Double
    /// Distance from the line. A fountain 250 m off the trail is a detour,
    /// not a drink, so the watcher ignores it.
    let offLineMeters: Double
}

struct WayStageHours: Codable, Equatable {
    let min: Double
    let max: Double
}

struct WayStagePlace: Codable, Equatable {
    let name: String
    let at: WayCoordinate
}

/// The stage block a pilgrimage Way carries: what the morning card reads at
/// Begin, what the arrival reflection closes with, and the identity the
/// ledger checks a stage against after an update.
struct WayStage: Codable, Equatable {
    let routeId: String
    /// Zero-based, as the dataset numbers stages.
    let index: Int
    let count: Int
    let name: String
    let theme: String
    let narrative: String
    let closing: String
    let warnings: [String]
    let distanceKm: Double
    let gainMeters: Double
    let hours: WayStageHours
    let difficulty: String
    let start: WayStagePlace
    let end: WayStagePlace
}
```

Extend `WaySource`:

```swift
enum WaySource: Codable, Equatable {
    case ownWalk(UUID)
    case share(id: String, pageURL: URL)
    /// One stage of a downloaded pilgrimage route. No page, no expiry: a
    /// route never returns to the trail on its own.
    case pilgrimage(routeId: String, stageIndex: Int)
}
```

Add to `WayMoment`, after `transcript`:

```swift
    /// The dataset's description of this place, or a line composed from its
    /// structured fields. Optional and last, like `place`.
    var text: String?
    /// Localized names by language code; the card shows one, in the language
    /// of the place.
    var names: [String: String]?
    /// When the place invites sitting, how long the dataset suggests.
    var sitMinutes: Int?
    /// The waypoint's own coordinate, for the map pin. `at` is its projection
    /// onto the line, so the 60 m trigger fires as the walker passes on the
    /// trail even when the place itself stands well off it.
    var pin: WayCoordinate?
```

Add to `Way`, after `spans`:

```swift
    /// Service points, drawn and never triggered. Optional and last, like
    /// `spans`, so a `way.json` written before stages still decodes.
    var marks: [WayMark]?
    /// Present only for a pilgrimage stage.
    var stage: WayStage?
```

- [ ] **Step 6: Widen the store's allow-list and give the package a home**

In `Pilgrim/Models/Honor/WayStore.swift`, replace `isValidId` and add three members beneath it:

```swift
    /// Ids are built by code (`share:` + a validated share id, `walk:` + a
    /// UUID, `pilgrimage:` + a validated route slug and stage index). The
    /// store still refuses anything else so a stray folder name or a future
    /// caller can never turn an id into a path outside `Ways/`.
    static func isValidId(_ id: String) -> Bool {
        id.range(of: "\\A(share:[A-Za-z0-9_-]{10}|walk:[0-9A-Fa-f-]{36}|pilgrimage:[a-z0-9-]{1,64}:[0-9]{1,3})\\z",
                 options: .regularExpression) != nil
    }

    /// The dataset's slug rule (spec 2.4). Checked before a route id is used
    /// in any path or URL, the way `WayImporter.isShareId` guards a share id.
    static func isValidRouteId(_ id: String) -> Bool {
        id.range(of: "\\A[a-z0-9-]{1,64}\\z", options: .regularExpression) != nil
    }

    static func stageWayId(routeId: String, stageIndex: Int) -> String {
        "pilgrimage:\(routeId):\(stageIndex)"
    }

    /// Where a downloaded route's `route.json`, `release.txt`, and ledger
    /// live — beside the stage Ways, never inside one, so Replace and Remove
    /// can take the stages and leave the record of having walked them.
    /// "pilgrimage" is not a valid Way id, so `list()` steps over this folder.
    func pilgrimageDirectory(for routeId: String) -> URL? {
        guard Self.isValidRouteId(routeId) else { return nil }
        return base.appendingPathComponent("pilgrimage", isDirectory: true)
            .appendingPathComponent(routeId, isDirectory: true)
    }
```

- [ ] **Step 7: Run the test to verify it passes**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/PilgrimageWayImporterTests 2>&1 | grep -E "error:|Executed"
```
Expected: `Executed 6 tests, with 0 failures`.

- [ ] **Step 8: Verify the whole app still builds**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD"
```
Expected: `** BUILD SUCCEEDED **`. No existing `switch` is exhaustive over `WaySource` (every call site uses `if case`/`guard case`), so the new case breaks nothing.

- [ ] **Step 9: Commit**

```bash
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(honor): a Way can carry marks and a stage

Optional and last on every type, so a way.json written before this slice
still decodes. Adds the fixture package the iOS side tests against.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `PilgrimageWayImporter`

**Files:**
- Create: `Pilgrim/Models/Honor/PilgrimageWayImporter.swift`
- Test: `UnitTests/Honor/PilgrimageWayImporterTests.swift` (extend)

**Interfaces:**
- Consumes: `Way`, `WayMark`, `WayStage`, `WaySource.pilgrimage`, `WayStore.isValidRouteId`, `WayStore.stageWayId`, `WayImporter.maxRoutePoints` (2000), `.maxEncounters` (200), `.maxLabelCharacters` (80), `.maxIconCharacters` (64), `.maxRestMinutes` (1440), `.isoDate(_:)`, `WayMoment.maxTranscriptCharacters` (600), `OwnWalkWayBuilder.minLengthMeters`, `PilgrimageFixtures`.
- Produces:
  - `enum PilgrimageError: Error, Equatable { case notWalkable, incomplete, diskFull, walkInProgress, catalogUnreachable }`
  - `enum PilgrimageCopy { static func line(for error: PilgrimageError) -> String }`
  - `struct PilgrimageRouteStage: Equatable { let index: Int; let name: String; let distanceKm: Double; let gainMeters: Double; let hours: WayStageHours; let difficulty: String }`
  - `struct PilgrimageRoute: Equatable { let id: String; let name: String; let names: [String: String]; let country: String?; let region: String?; let distanceKm: Double; let stageCount: Int; let tradition: String?; let summary: String?; let stages: [PilgrimageRouteStage] }`
  - `enum PilgrimageWayImporter { static let maxStageBytes = 2 * 1024 * 1024; static let maxRouteBytes = 512 * 1024; static let maxMarks = 400; static func way(from data: Data, routeId: String, stageIndex: Int) throws -> Way; static func route(from data: Data) throws -> PilgrimageRoute }`

- [ ] **Step 1: Write the failing tests**

Append these methods to `UnitTests/Honor/PilgrimageWayImporterTests.swift`:

```swift
extension PilgrimageWayImporterTests {

    private func stage00() throws -> Way {
        try PilgrimageWayImporter.way(from: PilgrimageFixtures.data("stage-00.json"),
                                      routeId: "camino-frances", stageIndex: 0)
    }

    func testDecodesTheFixtureStage() throws {
        let way = try stage00()
        XCTAssertEqual(way.id, "pilgrimage:camino-frances:0")
        XCTAssertEqual(way.source, .pilgrimage(routeId: "camino-frances", stageIndex: 0))
        XCTAssertEqual(way.title, "Saint-Jean-Pied-de-Port to Roncesvalles")
        XCTAssertNil(way.expires, "a route never returns to the trail on its own")
        XCTAssertNil(way.weather)
        XCTAssertEqual(way.route.count, 11)
        XCTAssertEqual(way.totalDistanceMeters, 1000, accuracy: 5)
        XCTAssertEqual(way.theirActiveSeconds, 28_800)
        XCTAssertEqual(way.tzIdentifier, "Europe/Madrid")
    }

    func testMomentsCarryTextLocalNamesSitMinutesAndAPin() throws {
        let way = try stage00()
        XCTAssertEqual(way.moments.map(\.id), ["wp-saint-jean", "wp-orisson", "wp-roncesvalles"])
        let orisson = try XCTUnwrap(way.moments.first { $0.id == "wp-orisson" })
        guard case .waypoint(let label, let icon) = orisson.kind else { return XCTFail("kind") }
        XCTAssertEqual(label, "Vierge d'Orisson")
        XCTAssertEqual(icon, "building.columns")
        XCTAssertEqual(orisson.text, "A shepherd carried this Madonna up from Lourdes.")
        XCTAssertEqual(orisson.names?["eu"], "Orissongo Ama Birjina")
        XCTAssertEqual(orisson.sitMinutes, 5)
        XCTAssertEqual(orisson.at, WayCoordinate(lat: 0, lon: 0.002694), "triggers fire on the line")
        XCTAssertEqual(orisson.pin, WayCoordinate(lat: 0, lon: 0.0027), "the pin draws off it")
        XCTAssertNil(way.moments.first { $0.id == "wp-saint-jean" }?.text)
    }

    func testMarksAndTheStageBlockSurvive() throws {
        let way = try stage00()
        let marks = try XCTUnwrap(way.marks)
        XCTAssertEqual(marks.map(\.id), ["wp-fuente-roldan", "wp-fuente-lejos", "wp-bar-orisson"])
        XCTAssertEqual(marks[0].kind, .water)
        XCTAssertEqual(marks[0].name, "Fuente de Roldán")
        XCTAssertEqual(marks[0].offLineMeters, 12)
        XCTAssertEqual(marks[2].kind, .food)
        let stage = try XCTUnwrap(way.stage)
        XCTAssertEqual(stage.routeId, "camino-frances")
        XCTAssertEqual(stage.index, 0)
        XCTAssertEqual(stage.count, 2)
        XCTAssertEqual(stage.theme, "Initiation")
        XCTAssertEqual(stage.closing, "You crossed a border on foot. Few things are still done this way.")
        XCTAssertEqual(stage.warnings, ["The Napoleon Route closes in winter."])
        XCTAssertEqual(stage.distanceKm, 24.2)
        XCTAssertEqual(stage.gainMeters, 1419)
        XCTAssertEqual(stage.hours, WayStageHours(min: 7, max: 9))
        XCTAssertEqual(stage.difficulty, "hard")
        XCTAssertEqual(stage.end.name, "Roncesvalles")
    }

    func testTheStageMustMatchTheRouteAndIndexItWasFetchedFor() throws {
        let data = try PilgrimageFixtures.data("stage-00.json")
        XCTAssertThrowsError(try PilgrimageWayImporter.way(from: data, routeId: "camino-frances", stageIndex: 4)) {
            XCTAssertEqual($0 as? PilgrimageError, .notWalkable)
        }
        XCTAssertThrowsError(try PilgrimageWayImporter.way(from: data, routeId: "camino-norte", stageIndex: 0)) {
            XCTAssertEqual($0 as? PilgrimageError, .notWalkable)
        }
        XCTAssertThrowsError(try PilgrimageWayImporter.way(from: data, routeId: "../etc", stageIndex: 0)) {
            XCTAssertEqual($0 as? PilgrimageError, .notWalkable)
        }
    }

    /// One field out of range at a time; each must be refused before any
    /// `Int(_:)` conversion, the way `WayImporter.validate` does.
    func testOutOfRangeStageFieldsAreNotWalkable() throws {
        let base = String(data: try PilgrimageFixtures.data("stage-00.json"), encoding: .utf8)!
        let cases: [(name: String, from: String, to: String)] = [
            ("frac above 1", "\"frac\": 0.3,", "\"frac\": 1.4,"),
            ("latitude off Earth", "\"lat\": 0, \"lon\": 0.002694", "\"lat\": 991, \"lon\": 0.002694"),
            ("sitMinutes absurd", "\"sitMinutes\": 5", "\"sitMinutes\": 999999999"),
            ("distanceKm absurd", "\"distanceKm\": 24.2,", "\"distanceKm\": 1e300,"),
            ("stage count over 200", "\"count\": 2,", "\"count\": 900,"),
            ("mark frac negative", "\"frac\": 0.5, \"offLineMeters\": 12", "\"frac\": -0.5, \"offLineMeters\": 12"),
            ("hours not finite", "\"hours\": { \"min\": 7, \"max\": 9 },", "\"hours\": { \"min\": 7, \"max\": 1e400 },")
        ]
        for testCase in cases {
            let json = base.replacingOccurrences(of: testCase.from, with: testCase.to)
            XCTAssertNotEqual(json, base, "\(testCase.name): the fixture no longer contains that text")
            XCTAssertThrowsError(try PilgrimageWayImporter.way(from: Data(json.utf8),
                                                              routeId: "camino-frances", stageIndex: 0),
                                 testCase.name) {
                XCTAssertEqual($0 as? PilgrimageError, .notWalkable, testCase.name)
            }
        }
    }

    func testFreeTextIsCappedAtParseTime() throws {
        let base = String(data: try PilgrimageFixtures.data("stage-00.json"), encoding: .utf8)!
        let long = String(repeating: "a", count: 5000)
        let json = base
            .replacingOccurrences(of: "\"theme\": \"Initiation\"", with: "\"theme\": \"\(long)\"")
            .replacingOccurrences(of: "\"A shepherd carried this Madonna up from Lourdes.\"", with: "\"\(long)\"")
        let way = try PilgrimageWayImporter.way(from: Data(json.utf8), routeId: "camino-frances", stageIndex: 0)
        XCTAssertEqual(way.stage?.theme.count, 80)
        XCTAssertEqual(way.moments.first { $0.id == "wp-orisson" }?.text?.count, 600)
    }

    func testTooManyMomentsOrMarksIsNotWalkable() throws {
        let base = String(data: try PilgrimageFixtures.data("stage-00.json"), encoding: .utf8)!
        let extraMark = ",{ \"id\": \"x\", \"kind\": \"water\", \"name\": \"x\", \"at\": { \"lat\": 0, \"lon\": 0 }, \"frac\": 0.1, \"offLineMeters\": 5 }"
        let many = String(repeating: extraMark, count: PilgrimageWayImporter.maxMarks)
        let json = base.replacingOccurrences(of: "\"offLineMeters\": 20 }\n  ],", with: "\"offLineMeters\": 20 }\(many)\n  ],")
        XCTAssertThrowsError(try PilgrimageWayImporter.way(from: Data(json.utf8),
                                                          routeId: "camino-frances", stageIndex: 0)) {
            XCTAssertEqual($0 as? PilgrimageError, .notWalkable)
        }
    }

    func testUnknownMarkKindsAndMomentKindsAreSkippedNotFatal() throws {
        let base = String(data: try PilgrimageFixtures.data("stage-00.json"), encoding: .utf8)!
        let json = base.replacingOccurrences(of: "\"kind\": \"food\"", with: "\"kind\": \"helipad\"")
        let way = try PilgrimageWayImporter.way(from: Data(json.utf8), routeId: "camino-frances", stageIndex: 0)
        XCTAssertEqual(way.marks?.map(\.id), ["wp-fuente-roldan", "wp-fuente-lejos"])
    }

    func testDecodesTheRouteFile() throws {
        let route = try PilgrimageWayImporter.route(from: PilgrimageFixtures.data("route.json"))
        XCTAssertEqual(route.id, "camino-frances")
        XCTAssertEqual(route.name, "Camino de Santiago (Francés)")
        XCTAssertEqual(route.names["gl"], "Camiño de Santiago (Francés)")
        XCTAssertEqual(route.country, "ES")
        XCTAssertEqual(route.stageCount, 2)
        XCTAssertEqual(route.distanceKm, 46.1)
        XCTAssertEqual(route.summary, "The most walked of the caminos.")
        XCTAssertEqual(route.stages.map(\.index), [0, 1])
        XCTAssertEqual(route.stages[0].difficulty, "hard")
        XCTAssertEqual(route.stages[1].hours, WayStageHours(min: 5, max: 7))
    }

    func testARouteFileWhoseNumbersAreOutOfRangeIsNotWalkable() throws {
        let base = String(data: try PilgrimageFixtures.data("route.json"), encoding: .utf8)!
        for (from, to) in [("\"stageCount\": 2", "\"stageCount\": 0"),
                           ("\"distanceKm\": 46.1", "\"distanceKm\": 99999"),
                           ("\"id\": \"camino-frances\"", "\"id\": \"../etc\"")] {
            let json = base.replacingOccurrences(of: from, with: to)
            XCTAssertNotEqual(json, base)
            XCTAssertThrowsError(try PilgrimageWayImporter.route(from: Data(json.utf8))) {
                XCTAssertEqual($0 as? PilgrimageError, .notWalkable)
            }
        }
    }

    func testEveryErrorHasItsOwnLine() {
        XCTAssertEqual(PilgrimageCopy.line(for: .notWalkable), "this route isn't walkable yet")
        XCTAssertEqual(PilgrimageCopy.line(for: .incomplete), "the download didn't finish")
        XCTAssertEqual(PilgrimageCopy.line(for: .walkInProgress), "finish your walk first")
        XCTAssertEqual(PilgrimageCopy.line(for: .catalogUnreachable), "the routes are out of reach right now")
        XCTAssertEqual(PilgrimageCopy.line(for: .diskFull),
                       HonorImportCopy.line(for: .failed(.diskFull)),
                       "disk full keeps the copy the share importer already ships")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/PilgrimageWayImporterTests 2>&1 | grep -E "error:|Executed"
```
Expected: `cannot find 'PilgrimageWayImporter' in scope`.

- [ ] **Step 3: Create `PilgrimageWayImporter.swift`**

```swift
import Foundation

/// What can go wrong on the way to a walkable route. Distinct from
/// `WayError` because each of these has its own line on screen.
enum PilgrimageError: Error, Equatable {
    case notWalkable
    case incomplete
    case diskFull
    case walkInProgress
    case catalogUnreachable
}

enum PilgrimageCopy {
    static func line(for error: PilgrimageError) -> String {
        switch error {
        case .notWalkable: return "this route isn't walkable yet"
        case .incomplete: return "the download didn't finish"
        case .diskFull: return HonorImportCopy.line(for: .failed(.diskFull)) ?? "not enough space on this phone"
        case .walkInProgress: return "finish your walk first"
        case .catalogUnreachable: return "the routes are out of reach right now"
        }
    }
}

struct PilgrimageRouteStage: Equatable {
    let index: Int
    let name: String
    let distanceKm: Double
    let gainMeters: Double
    let hours: WayStageHours
    let difficulty: String
}

struct PilgrimageRoute: Equatable {
    let id: String
    let name: String
    let names: [String: String]
    let country: String?
    let region: String?
    let distanceKm: Double
    let stageCount: Int
    let tradition: String?
    let summary: String?
    let stages: [PilgrimageRouteStage]
}

/// The sibling of `WayImporter` for the dataset's packaged stages: it decodes
/// the build's wire format and hands back the `Way` the engine already walks.
/// Every number is range-checked before any `Int(_:)` conversion and every
/// string capped, before anything reaches a view.
enum PilgrimageWayImporter {

    static let maxStageBytes = 2 * 1024 * 1024
    static let maxRouteBytes = 512 * 1024
    /// A town stage can carry over a hundred service points; four hundred is
    /// far past anything the dataset produces and still bounds the parse.
    static let maxMarks = 400
    static let maxThemeCharacters = 80
    static let maxNarrativeCharacters = 2_000
    static let maxClosingCharacters = 400
    static let maxWarningCharacters = 300
    static let maxStageNameCharacters = 120
    static let maxMarkNameCharacters = 80
    static let maxSummaryCharacters = 600
    static let maxWarnings = 20
    static let maxLocalNames = 20
    static let maxDistanceKm = 10_000.0
    static let maxStageCount = 200
    static let maxGainMeters = 30_000.0
    static let maxHours = 100.0

    // MARK: - Wire format

    private struct Coordinate: Decodable {
        let lat: Double
        let lon: Double
    }

    private struct StageFile: Decodable {
        struct Point: Decodable {
            let lat: Double
            let lon: Double
            let alt: Double?
            let t: Double
        }
        struct Moment: Decodable {
            let id: String
            let frac: Double
            let kind: String
            let label: String?
            let icon: String?
            let text: String?
            let names: [String: String]?
            let sitMinutes: Int?
            let at: Coordinate?
            let pin: Coordinate?
        }
        struct Mark: Decodable {
            let id: String
            let kind: String
            let name: String
            let at: Coordinate
            let frac: Double
            let offLineMeters: Double
        }
        struct Hours: Decodable {
            let min: Double
            let max: Double
        }
        struct Place: Decodable {
            let name: String
            let at: Coordinate
        }
        struct Stage: Decodable {
            let routeId: String
            let index: Int
            let count: Int
            let name: String
            let theme: String
            let narrative: String
            let closing: String
            let warnings: [String]
            let distanceKm: Double
            let gainMeters: Double
            let hours: Hours
            let difficulty: String
            let start: Place
            let end: Place
        }
        let id: String
        let title: String
        let departedAt: String
        let tzIdentifier: String?
        let route: [Point]
        let totalDistanceMeters: Double
        let theirActiveSeconds: Double
        let moments: [Moment]
        let marks: [Mark]
        let stage: Stage
    }

    private struct RouteFile: Decodable {
        struct Stage: Decodable {
            let index: Int
            let name: String
            let distanceKm: Double
            let gainMeters: Double
            let hours: StageFile.Hours
            let difficulty: String
        }
        let id: String
        let name: String
        let names: [String: String]?
        let country: String?
        let region: String?
        let distanceKm: Double
        let stageCount: Int
        let tradition: String?
        let summary: String?
        let stages: [Stage]
    }

    // MARK: - Stage

    static func way(from data: Data, routeId: String, stageIndex: Int) throws -> Way {
        guard WayStore.isValidRouteId(routeId), (0..<maxStageCount).contains(stageIndex) else {
            throw PilgrimageError.notWalkable
        }
        guard data.count <= maxStageBytes, let file = try? JSONDecoder().decode(StageFile.self, from: data) else {
            throw PilgrimageError.notWalkable
        }
        // The file must be the one that was asked for: a package is only ever
        // as trustworthy as the path it came from.
        let expectedId = WayStore.stageWayId(routeId: routeId, stageIndex: stageIndex)
        guard file.id == expectedId, file.stage.routeId == routeId, file.stage.index == stageIndex else {
            throw PilgrimageError.notWalkable
        }
        guard validate(file) else { throw PilgrimageError.notWalkable }
        guard let departed = WayImporter.isoDate(file.departedAt) else { throw PilgrimageError.notWalkable }

        let route = file.route.map { WayPoint(lat: $0.lat, lon: $0.lon, alt: $0.alt, t: $0.t) }
        let geometry = WayGeometry(route: route)
        guard geometry.totalMeters >= OwnWalkWayBuilder.minLengthMeters else { throw PilgrimageError.notWalkable }

        var way = Way(
            id: expectedId,
            source: .pilgrimage(routeId: routeId, stageIndex: stageIndex),
            title: capped(file.title, maxStageNameCharacters),
            departedAt: departed,
            tzIdentifier: file.tzIdentifier.map { capped($0, WayImporter.maxLabelCharacters) },
            expires: nil,
            route: route,
            totalDistanceMeters: geometry.totalMeters,
            theirActiveSeconds: file.theirActiveSeconds,
            moments: moments(from: file.moments),
            weather: nil)
        way.marks = marks(from: file.marks)
        way.stage = stage(from: file.stage)
        return way
    }

    /// Unknown moment kinds are skipped, like unknown encounter types in a
    /// share manifest; a stage that packaged only unknown kinds is a quiet
    /// stage, not a broken one.
    private static func moments(from raw: [StageFile.Moment]) -> [WayMoment] {
        var built: [WayMoment] = []
        for entry in raw where entry.kind == "waypoint" {
            var moment = WayMoment(
                id: capped(entry.id, WayImporter.maxLabelCharacters),
                frac: entry.frac,
                at: entry.at.map { WayCoordinate(lat: $0.lat, lon: $0.lon) },
                kind: .waypoint(label: capped(entry.label ?? "", WayImporter.maxLabelCharacters),
                                icon: capped(entry.icon ?? "mappin", WayImporter.maxIconCharacters)))
            moment.text = trimmed(entry.text, WayMoment.maxTranscriptCharacters)
            moment.names = localNames(entry.names)
            moment.sitMinutes = entry.sitMinutes
            moment.pin = entry.pin.map { WayCoordinate(lat: $0.lat, lon: $0.lon) }
            built.append(moment)
        }
        // A tiebreak on id keeps ordering deterministic when two moments
        // share a frac — the rule `WayImporter` and the tracker both sort by.
        return built.sorted { $0.frac == $1.frac ? $0.id < $1.id : $0.frac < $1.frac }
    }

    private static func marks(from raw: [StageFile.Mark]) -> [WayMark] {
        raw.compactMap { entry in
            guard let kind = WayMarkKind(rawValue: entry.kind) else { return nil }
            return WayMark(id: capped(entry.id, WayImporter.maxLabelCharacters), kind: kind,
                           name: capped(entry.name, maxMarkNameCharacters),
                           at: WayCoordinate(lat: entry.at.lat, lon: entry.at.lon),
                           frac: entry.frac, offLineMeters: entry.offLineMeters)
        }
    }

    private static func stage(from raw: StageFile.Stage) -> WayStage {
        WayStage(
            routeId: raw.routeId, index: raw.index, count: raw.count,
            name: capped(raw.name, maxStageNameCharacters),
            theme: capped(raw.theme, maxThemeCharacters),
            narrative: capped(raw.narrative, maxNarrativeCharacters),
            closing: capped(raw.closing, maxClosingCharacters),
            warnings: raw.warnings.prefix(maxWarnings).map { capped($0, maxWarningCharacters) },
            distanceKm: raw.distanceKm, gainMeters: raw.gainMeters,
            hours: WayStageHours(min: raw.hours.min, max: raw.hours.max),
            difficulty: capped(raw.difficulty, WayImporter.maxLabelCharacters),
            start: WayStagePlace(name: capped(raw.start.name, maxStageNameCharacters),
                                 at: WayCoordinate(lat: raw.start.at.lat, lon: raw.start.at.lon)),
            end: WayStagePlace(name: capped(raw.end.name, maxStageNameCharacters),
                               at: WayCoordinate(lat: raw.end.at.lat, lon: raw.end.at.lon)))
    }

    // MARK: - Route

    static func route(from data: Data) throws -> PilgrimageRoute {
        guard data.count <= maxRouteBytes, let file = try? JSONDecoder().decode(RouteFile.self, from: data) else {
            throw PilgrimageError.notWalkable
        }
        guard WayStore.isValidRouteId(file.id),
              isSaneDistance(file.distanceKm),
              (1...maxStageCount).contains(file.stageCount),
              file.stages.count <= maxStageCount,
              file.stages.allSatisfy(isSaneStageRow) else { throw PilgrimageError.notWalkable }
        return PilgrimageRoute(
            id: file.id,
            name: capped(file.name, maxStageNameCharacters),
            names: localNames(file.names) ?? [:],
            country: file.country.map { capped($0, WayImporter.maxLabelCharacters) },
            region: file.region.map { capped($0, WayImporter.maxLabelCharacters) },
            distanceKm: file.distanceKm,
            stageCount: file.stageCount,
            tradition: file.tradition.map { capped($0, WayImporter.maxLabelCharacters) },
            summary: trimmed(file.summary, maxSummaryCharacters),
            stages: file.stages
                .sorted { $0.index < $1.index }
                .map { PilgrimageRouteStage(index: $0.index, name: capped($0.name, maxStageNameCharacters),
                                            distanceKm: $0.distanceKm, gainMeters: $0.gainMeters,
                                            hours: WayStageHours(min: $0.hours.min, max: $0.hours.max),
                                            difficulty: capped($0.difficulty, WayImporter.maxLabelCharacters)) })
    }

    private static func isSaneStageRow(_ row: RouteFile.Stage) -> Bool {
        (0..<maxStageCount).contains(row.index)
            && isSaneDistance(row.distanceKm)
            && isSaneGain(row.gainMeters)
            && isSaneHours(row.hours)
    }

    // MARK: - Validation

    /// The whole stage file, checked before a single value is converted or
    /// shown. `Int(_:)` traps on an out-of-range or non-finite `Double`, so
    /// finiteness is checked everywhere a number can reach a formatter.
    private static func validate(_ file: StageFile) -> Bool {
        func inLat(_ v: Double) -> Bool { v.isFinite && (-90...90).contains(v) }
        func inLon(_ v: Double) -> Bool { v.isFinite && (-180...180).contains(v) }
        func inFrac(_ v: Double) -> Bool { v.isFinite && (0...1).contains(v) }

        guard file.route.count >= 2, file.route.count <= WayImporter.maxRoutePoints,
              file.moments.count <= WayImporter.maxEncounters,
              file.marks.count <= maxMarks else { return false }
        guard file.route.allSatisfy({ point in
            inLat(point.lat) && inLon(point.lon) && point.t.isFinite && (0...WayImporter.maxActiveDurationSeconds).contains(point.t)
                && (point.alt.map { $0.isFinite && abs($0) < WayImporter.maxAltitudeMeters } ?? true)
        }) else { return false }
        for i in file.route.indices.dropFirst() where file.route[i].t < file.route[i - 1].t { return false }
        guard file.totalDistanceMeters.isFinite, file.totalDistanceMeters >= 0,
              file.theirActiveSeconds.isFinite,
              (0...WayImporter.maxActiveDurationSeconds).contains(file.theirActiveSeconds) else { return false }

        for moment in file.moments {
            guard inFrac(moment.frac) else { return false }
            if let at = moment.at, !(inLat(at.lat) && inLon(at.lon)) { return false }
            if let pin = moment.pin, !(inLat(pin.lat) && inLon(pin.lon)) { return false }
            if let minutes = moment.sitMinutes, !(0...WayImporter.maxRestMinutes).contains(minutes) { return false }
        }
        for mark in file.marks {
            guard inFrac(mark.frac), inLat(mark.at.lat), inLon(mark.at.lon),
                  mark.offLineMeters.isFinite, (0...100_000).contains(mark.offLineMeters) else { return false }
        }

        let stage = file.stage
        guard (0..<maxStageCount).contains(stage.index),
              (1...maxStageCount).contains(stage.count),
              stage.index < stage.count,
              isSaneDistance(stage.distanceKm), isSaneGain(stage.gainMeters), isSaneHours(stage.hours),
              stage.warnings.count <= maxWarnings,
              inLat(stage.start.at.lat), inLon(stage.start.at.lon),
              inLat(stage.end.at.lat), inLon(stage.end.at.lon) else { return false }
        return true
    }

    private static func isSaneDistance(_ km: Double) -> Bool { km.isFinite && (0...maxDistanceKm).contains(km) }
    private static func isSaneGain(_ meters: Double) -> Bool { meters.isFinite && (0...maxGainMeters).contains(meters) }
    private static func isSaneHours(_ hours: StageFile.Hours) -> Bool {
        hours.min.isFinite && hours.max.isFinite
            && (0...maxHours).contains(hours.min) && (0...maxHours).contains(hours.max) && hours.max >= hours.min
    }

    // MARK: - Strings

    private static func capped(_ value: String, _ max: Int) -> String { String(value.prefix(max)) }

    private static func trimmed(_ raw: String?, _ max: Int) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(max))
    }

    /// Language codes come from an untrusted file and end up as dictionary
    /// keys a card reads; both halves are bounded and the map itself capped.
    private static func localNames(_ raw: [String: String]?) -> [String: String]? {
        guard let raw, !raw.isEmpty else { return nil }
        let pairs = raw.sorted { $0.key < $1.key }.prefix(maxLocalNames).compactMap { key, value -> (String, String)? in
            guard key.range(of: "\\A[a-z]{2,3}\\z", options: .regularExpression) != nil else { return nil }
            guard let name = trimmed(value, maxStageNameCharacters) else { return nil }
            return (key, name)
        }
        return pairs.isEmpty ? nil : Dictionary(uniqueKeysWithValues: pairs)
    }
}
```

- [ ] **Step 4: Register, run the tests**

```bash
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Models/Honor/PilgrimageWayImporter.swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/PilgrimageWayImporterTests 2>&1 | grep -E "error:|Executed"
```
Expected: `Executed 17 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(honor): PilgrimageWayImporter turns a packaged stage into a Way

Same validate-before-Int discipline as the share importer: every number
range-checked and every string capped before anything reaches a view.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `PilgrimageCatalogService`

**Files:**
- Create: `Pilgrim/Models/Honor/PilgrimageCatalogService.swift`
- Create: `UnitTests/Helpers/StubURLProtocol.swift`
- Test: `UnitTests/Honor/PilgrimageCatalogServiceTests.swift`

**Interfaces:**
- Consumes: `PilgrimageError`, `WayStore.isValidRouteId`, `PilgrimageFixtures`.
- Produces:
  - `struct PilgrimageCatalogEntry: Codable, Equatable, Hashable, Identifiable { let id: String; let name: String; let names: [String: String]; let country: String?; let region: String?; let distanceKm: Double; let tradition: String?; let stageCount: Int; let bytes: Int; let placesPerStage: Double; let sparse: Bool }` — the last two carry `init` defaults (`0` and `false`) so every literal that does not care about them stays short. `Hashable` is load-bearing: Task 8 pushes an entry through `navigationDestination(item:)`, which requires it.
  - `struct PilgrimageCatalog: Codable, Equatable { let release: String; let routes: [PilgrimageCatalogEntry] }`
  - `@MainActor final class PilgrimageCatalogService: ObservableObject` with `static let shared`, `init(session:directory:now:)`, `@Published private(set) var catalog: PilgrimageCatalog?`, `func load(force: Bool = false) async throws -> PilgrimageCatalog`, `static let indexURL: URL`, `static func packageURL(release:routeId:file:) -> URL?`, `static let cacheLifetime: TimeInterval`, `static let maxIndexBytes: Int`, `static func parse(_ data: Data) throws -> PilgrimageCatalog`.
- Produces for tests: `StubURLProtocol.stub(url:status:body:headers:)`, `StubURLProtocol.reset()`, `StubURLProtocol.session()`, `StubURLProtocol.requestedURLs`.

- [ ] **Step 1: Write the stub protocol**

`UnitTests/Helpers/StubURLProtocol.swift`:

```swift
import Foundation

/// Answers `URLSession` requests from a table, so a spec can drive a service
/// that streams bytes without a network. Registered through
/// `URLSessionConfiguration.protocolClasses`, which `URLSession.bytes(from:)`
/// goes through like every other transfer.
final class StubURLProtocol: URLProtocol {

    struct Response {
        let status: Int
        let body: Data
        let headers: [String: String]
    }

    private static let lock = NSLock()
    private static var responses: [String: Response] = [:]
    private static var seen: [URL] = []

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        responses = [:]
        seen = []
    }

    static func stub(url: URL, status: Int = 200, body: Data, headers: [String: String]? = nil) {
        lock.lock(); defer { lock.unlock() }
        responses[url.absoluteString] = Response(
            status: status, body: body,
            headers: headers ?? ["Content-Length": String(body.count), "Content-Type": "application/json"])
    }

    static var requestedURLs: [URL] {
        lock.lock(); defer { lock.unlock() }
        return seen
    }

    /// An ephemeral session that only this protocol answers.
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.lock.lock()
        Self.seen.append(url)
        let stub = Self.responses[url.absoluteString]
        Self.lock.unlock()
        guard let stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: stub.status,
                                       httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
```

- [ ] **Step 2: Write the failing tests**

`UnitTests/Honor/PilgrimageCatalogServiceTests.swift`:

```swift
import XCTest
@testable import Pilgrim

@MainActor
final class PilgrimageCatalogServiceTests: XCTestCase {

    private var dir: URL!
    private var clock = Date(timeIntervalSince1970: 3_000_000)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        clock = Date(timeIntervalSince1970: 3_000_000)
        StubURLProtocol.reset()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func makeService() -> PilgrimageCatalogService {
        PilgrimageCatalogService(session: StubURLProtocol.session(),
                                 directory: dir,
                                 now: { [unowned self] in self.clock })
    }

    private func stubIndex(_ data: Data, status: Int = 200, headers: [String: String]? = nil) {
        StubURLProtocol.stub(url: PilgrimageCatalogService.indexURL, status: status, body: data, headers: headers)
    }

    /// Never a tag: jsDelivr caches a tag URL forever, so the moving `v1`
    /// tag still serves a March index with three routes.
    func testTheIndexIsReadFromTheBranchNotAMovingTag() {
        XCTAssertEqual(PilgrimageCatalogService.indexURL.absoluteString,
                       "https://cdn.jsdelivr.net/gh/walktalkmeditate/open-pilgrimages@main/index.json")
        XCTAssertFalse(PilgrimageCatalogService.indexURL.absoluteString.contains("@v1"))
    }

    func testPackageURLsArePinnedToTheExactRelease() {
        XCTAssertEqual(
            PilgrimageCatalogService.packageURL(release: "v1.7.0", routeId: "camino-frances", file: "stage-00.json")?.absoluteString,
            "https://cdn.jsdelivr.net/gh/walktalkmeditate/open-pilgrimages@v1.7.0/routes/camino-frances/ways/stage-00.json")
        XCTAssertNil(PilgrimageCatalogService.packageURL(release: "v1.7.0", routeId: "../etc", file: "route.json"))
        XCTAssertNil(PilgrimageCatalogService.packageURL(release: "main", routeId: "camino-frances", file: "route.json"))
        XCTAssertNil(PilgrimageCatalogService.packageURL(release: "v1.7.0", routeId: "camino-frances", file: "../../secret"))
    }

    func testParsesOnlyRoutesThatCarryAWaysEntryAndALegalSlug() throws {
        let catalog = try PilgrimageCatalogService.parse(PilgrimageFixtures.data("index.json"))
        XCTAssertEqual(catalog.release, "v1.7.0")
        XCTAssertEqual(catalog.routes.map(\.id), ["camino-frances"],
                       "camino-norte has no ways entry; the third id is not a slug")
        let route = try XCTUnwrap(catalog.routes.first)
        XCTAssertEqual(route.name, "Camino de Santiago (Frances)")
        XCTAssertEqual(route.names["es"], "Camino de Santiago (Francés)")
        XCTAssertEqual(route.country, "ES")
        XCTAssertEqual(route.stageCount, 2)
        XCTAssertEqual(route.bytes, 214_000)
    }

    func testTheSparseFlagAndItsDensityCarryThrough() throws {
        let catalog = try PilgrimageCatalogService.parse(PilgrimageFixtures.data("index.json"))
        let route = try XCTUnwrap(catalog.routes.first)
        XCTAssertTrue(route.sparse, "the Camino Francés carries a curated place on fewer than half its stages")
        XCTAssertEqual(route.placesPerStage, 0.4, accuracy: 0.0001)

        // An index written before the flag existed still parses, as dense.
        let base = String(data: try PilgrimageFixtures.data("index.json"), encoding: .utf8)!
        let older = base.replacingOccurrences(
            of: "\"stageCount\": 2, \"bytes\": 214000, \"placesPerStage\": 0.4, \"sparse\": true",
            with: "\"stageCount\": 2, \"bytes\": 214000")
        XCTAssertNotEqual(older, base)
        let olderRoute = try XCTUnwrap(PilgrimageCatalogService.parse(Data(older.utf8)).routes.first)
        XCTAssertFalse(olderRoute.sparse)
        XCTAssertEqual(olderRoute.placesPerStage, 0)
    }

    func testAnAbsurdPlaceDensityDropsTheRoute() throws {
        let base = String(data: try PilgrimageFixtures.data("index.json"), encoding: .utf8)!
        for bad in ["\"placesPerStage\": 51", "\"placesPerStage\": -1", "\"placesPerStage\": 1e300"] {
            let json = base.replacingOccurrences(of: "\"placesPerStage\": 0.4", with: bad)
            XCTAssertNotEqual(json, base, bad)
            XCTAssertTrue(try PilgrimageCatalogService.parse(Data(json.utf8)).routes.isEmpty, bad)
        }
    }

    func testARepairedReleaseTagIsRefused() throws {
        let base = String(data: try PilgrimageFixtures.data("index.json"), encoding: .utf8)!
        for bad in ["\"release\": \"main\"", "\"release\": \"v1.7\"", "\"release\": \"1.7.0\""] {
            let json = base.replacingOccurrences(of: "\"release\": \"v1.7.0\"", with: bad)
            XCTAssertThrowsError(try PilgrimageCatalogService.parse(Data(json.utf8)), bad) {
                XCTAssertEqual($0 as? PilgrimageError, .catalogUnreachable, bad)
            }
        }
    }

    func testOutOfRangeRouteNumbersDropTheRoute() throws {
        let base = String(data: try PilgrimageFixtures.data("index.json"), encoding: .utf8)!
        for (from, to) in [("\"distanceKm\": 46.1", "\"distanceKm\": 20000"),
                           ("\"stageCount\": 2, \"bytes\": 214000", "\"stageCount\": 900, \"bytes\": 214000"),
                           ("\"stageCount\": 2, \"bytes\": 214000", "\"stageCount\": 2, \"bytes\": 99000000")] {
            let json = base.replacingOccurrences(of: from, with: to)
            XCTAssertNotEqual(json, base, to)
            let catalog = try PilgrimageCatalogService.parse(Data(json.utf8))
            XCTAssertTrue(catalog.routes.isEmpty, to)
        }
    }

    func testFetchesOnceAndThenServesTheCacheForTwentyFourHours() async throws {
        stubIndex(try PilgrimageFixtures.data("index.json"))
        let service = makeService()
        _ = try await service.load()
        XCTAssertEqual(StubURLProtocol.requestedURLs.count, 1)

        clock = clock.addingTimeInterval(23 * 3600)
        let second = makeService()
        let cached = try await second.load()
        XCTAssertEqual(cached.routes.map(\.id), ["camino-frances"])
        XCTAssertEqual(StubURLProtocol.requestedURLs.count, 1, "still inside the 24 h window")

        clock = clock.addingTimeInterval(2 * 3600)
        let third = makeService()
        _ = try await third.load()
        XCTAssertEqual(StubURLProtocol.requestedURLs.count, 2, "past 24 h, it asks again")
    }

    func testAnIndexBiggerThanTheCapIsNeverBuffered() async throws {
        let huge = Data(repeating: 0x7B, count: PilgrimageCatalogService.maxIndexBytes + 1)
        stubIndex(huge)
        let service = makeService()
        do {
            _ = try await service.load()
            XCTFail("expected catalogUnreachable")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .catalogUnreachable)
        }
    }

    func testAFailedFetchWithACachedIndexDegradesSilently() async throws {
        stubIndex(try PilgrimageFixtures.data("index.json"))
        _ = try await makeService().load()
        StubURLProtocol.reset()
        clock = clock.addingTimeInterval(48 * 3600)
        let offline = makeService()
        let catalog = try await offline.load()
        XCTAssertEqual(catalog.routes.map(\.id), ["camino-frances"],
                       "a stale cache still answers when the network does not")
    }

    func testAFailedFetchWithNoCacheIsOutOfReach() async {
        let service = makeService()
        do {
            _ = try await service.load()
            XCTFail("expected catalogUnreachable")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .catalogUnreachable)
        }
        XCTAssertNil(service.catalog)
    }
}
```

- [ ] **Step 3: Register and run to verify it fails**

```bash
ruby scripts/xcode-add.rb UnitTests UnitTests/Helpers/StubURLProtocol.swift
ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/PilgrimageCatalogServiceTests.swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/PilgrimageCatalogServiceTests 2>&1 | grep -E "error:|Executed"
```
Expected: `cannot find 'PilgrimageCatalogService' in scope`.

- [ ] **Step 4: Create `PilgrimageCatalogService.swift`**

```swift
import Combine
import Foundation

/// `Hashable` as well as `Identifiable`: the route view is pushed with
/// `navigationDestination(item:)`, which takes a `Hashable` item.
struct PilgrimageCatalogEntry: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let name: String
    let names: [String: String]
    let country: String?
    let region: String?
    let distanceKm: Double
    let tradition: String?
    let stageCount: Int
    let bytes: Int
    /// Curated places per stage beyond the start and end towns, as the
    /// build's coverage report measured them.
    let placesPerStage: Double
    /// The build's own verdict: fewer than half this route's stages carry a
    /// curated place. True of the Camino Francés today, so the catalog says
    /// so rather than letting the route promise more than it holds.
    let sparse: Bool

    /// The two coverage fields default, so a literal that does not care
    /// about them stays short and an older cache is the only thing that has
    /// to be refetched.
    init(id: String, name: String, names: [String: String], country: String?, region: String?,
         distanceKm: Double, tradition: String?, stageCount: Int, bytes: Int,
         placesPerStage: Double = 0, sparse: Bool = false) {
        self.id = id
        self.name = name
        self.names = names
        self.country = country
        self.region = region
        self.distanceKm = distanceKm
        self.tradition = tradition
        self.stageCount = stageCount
        self.bytes = bytes
        self.placesPerStage = placesPerStage
        self.sparse = sparse
    }
}

struct PilgrimageCatalog: Codable, Equatable {
    /// The git tag every package file is then pinned to, so a route's stages
    /// are always from one build.
    let release: String
    let routes: [PilgrimageCatalogEntry]
}

/// The dataset's index, read from the repository's default branch at most
/// once a day. Nothing here reaches for a package: the catalog only says
/// which routes exist, how big they are, and which release to pin to.
@MainActor
final class PilgrimageCatalogService: ObservableObject {

    static let shared = PilgrimageCatalogService()

    /// `@main`, never `@v1`: jsDelivr caches a tag URL permanently, so a tag
    /// that the release step moves still serves the bytes it first saw — the
    /// `v1` alias returns a March index with three routes while `v1.6.0` has
    /// seven. A branch ref refreshes on jsDelivr's own 12 h cycle, and the
    /// 24 h cache below sits on top of it. Package files stay pinned to the
    /// exact `release` tag the index names, because those tags never move.
    static let indexURL = URL(string: "https://cdn.jsdelivr.net/gh/walktalkmeditate/open-pilgrimages@main/index.json")!
    private static let packageBase = "https://cdn.jsdelivr.net/gh/walktalkmeditate/open-pilgrimages"

    static let maxIndexBytes = 256 * 1024
    static let cacheLifetime: TimeInterval = 24 * 3600
    static let maxDistanceKm = 10_000.0
    static let maxStageCount = 200
    static let maxPackageBytes = 50 * 1024 * 1024
    /// A stage cannot plausibly carry fifty curated places; anything beyond
    /// this is a broken report, not a rich route.
    static let maxPlacesPerStage = 50.0

    @Published private(set) var catalog: PilgrimageCatalog?

    private let session: URLSession
    private let directory: URL
    private let now: () -> Date

    /// The overview's copy promises a quick answer, so the catalog gets its
    /// own short-lived session rather than `.shared`'s multi-minute defaults —
    /// the same reasoning as `WayImporter.defaultSession`.
    private static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    private static var defaultDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Pilgrimages", isDirectory: true)
    }

    init(session: URLSession = PilgrimageCatalogService.defaultSession,
         directory: URL = PilgrimageCatalogService.defaultDirectory,
         now: @escaping () -> Date = Date.init) {
        self.session = session
        self.directory = directory
        self.now = now
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - URLs

    /// Package files are pinned to the exact tag the index named. Both the
    /// release and the route id are validated before either reaches a URL,
    /// and the file name is drawn from a closed set — a path is never built
    /// from a string the dataset chose.
    static func packageURL(release: String, routeId: String, file: String) -> URL? {
        guard isValidRelease(release), WayStore.isValidRouteId(routeId),
              file.range(of: "\\A(route\\.json|stage-[0-9]{2,3}\\.json)\\z", options: .regularExpression) != nil,
              let url = URL(string: "\(packageBase)@\(release)/routes/\(routeId)/ways/\(file)") else { return nil }
        return url
    }

    static func isValidRelease(_ release: String) -> Bool {
        release.range(of: "\\Av[0-9]+\\.[0-9]+\\.[0-9]+\\z", options: .regularExpression) != nil
    }

    // MARK: - Loading

    /// Serves the cache while it is under a day old, then asks the CDN. A
    /// failed fetch with a cache on disk degrades silently to that cache —
    /// the catalog still shows what is on the phone.
    @discardableResult
    func load(force: Bool = false) async throws -> PilgrimageCatalog {
        let cached = readCache()
        if !force, let cached, now().timeIntervalSince(cached.fetchedAt) < Self.cacheLifetime {
            catalog = cached.catalog
            return cached.catalog
        }
        do {
            let fresh = try Self.parse(try await fetchIndex())
            writeCache(Cached(fetchedAt: now(), catalog: fresh))
            catalog = fresh
            return fresh
        } catch {
            if let cached {
                catalog = cached.catalog
                return cached.catalog
            }
            throw PilgrimageError.catalogUnreachable
        }
    }

    private func fetchIndex() async throws -> Data {
        do {
            let (bytes, response) = try await session.bytes(from: Self.indexURL)
            // Checked before draining: an oversized declared length must not
            // cost a full download first.
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.expectedContentLength <= Int64(Self.maxIndexBytes) else { throw PilgrimageError.catalogUnreachable }
            var buffer = Data()
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count > Self.maxIndexBytes { throw PilgrimageError.catalogUnreachable }
            }
            return buffer
        } catch let error as PilgrimageError {
            throw error
        } catch {
            throw PilgrimageError.catalogUnreachable
        }
    }

    // MARK: - Parsing

    private struct IndexFile: Decodable {
        struct Ways: Decodable {
            let stageCount: Int
            let bytes: Int
            /// Both optional: an index written before the build measured
            /// coverage still parses, as a dense route with no figure.
            let placesPerStage: Double?
            let sparse: Bool?
        }
        struct Route: Decodable {
            let id: String
            let name: [String: String]
            let region: String?
            let country: String?
            let distanceKm: Double
            let tradition: String?
            let ways: Ways?
        }
        let release: String
        let routes: [Route]
    }

    /// A route without a `ways` entry failed the build's length gate and the
    /// app hides it; a route the build only flagged `sparse` is still listed,
    /// and says so on its card. A route whose id or numbers fail validation
    /// is dropped rather than failing the whole catalog: one bad row must not
    /// cost the pilgrim every route.
    static func parse(_ data: Data) throws -> PilgrimageCatalog {
        guard let file = try? JSONDecoder().decode(IndexFile.self, from: data),
              isValidRelease(file.release) else { throw PilgrimageError.catalogUnreachable }
        let routes = file.routes.compactMap { row -> PilgrimageCatalogEntry? in
            guard let ways = row.ways, WayStore.isValidRouteId(row.id),
                  row.distanceKm.isFinite, (0...maxDistanceKm).contains(row.distanceKm),
                  (1...maxStageCount).contains(ways.stageCount),
                  (0..<maxPackageBytes).contains(ways.bytes),
                  ways.placesPerStage.map({ $0.isFinite && (0...maxPlacesPerStage).contains($0) }) ?? true
            else { return nil }
            let names = row.name.filter { $0.key.range(of: "\\A[a-z]{2,3}\\z", options: .regularExpression) != nil }
            guard let display = names["en"] ?? names.sorted(by: { $0.key < $1.key }).first?.value else { return nil }
            return PilgrimageCatalogEntry(
                id: row.id,
                name: String(display.prefix(PilgrimageWayImporter.maxStageNameCharacters)),
                names: names.mapValues { String($0.prefix(PilgrimageWayImporter.maxStageNameCharacters)) },
                country: row.country.map { String($0.prefix(WayImporter.maxLabelCharacters)) },
                region: row.region.map { String($0.prefix(WayImporter.maxLabelCharacters)) },
                distanceKm: row.distanceKm,
                tradition: row.tradition.map { String($0.prefix(WayImporter.maxLabelCharacters)) },
                stageCount: ways.stageCount,
                bytes: ways.bytes,
                placesPerStage: ways.placesPerStage ?? 0,
                sparse: ways.sparse ?? false)
        }
        return PilgrimageCatalog(release: file.release, routes: routes)
    }

    // MARK: - Cache

    private struct Cached: Codable {
        let fetchedAt: Date
        let catalog: PilgrimageCatalog
    }

    private var cacheURL: URL { directory.appendingPathComponent("catalog.json") }

    /// A cache written by a build that did not know about the coverage
    /// fields fails to decode and is simply refetched — there is nothing in
    /// it worth a migration.
    private func readCache() -> Cached? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Cached.self, from: data)
    }

    private func writeCache(_ cached: Cached) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(cached).write(to: cacheURL, options: .atomic)
    }
}
```

- [ ] **Step 5: Register, run the tests**

```bash
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Models/Honor/PilgrimageCatalogService.swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/PilgrimageCatalogServiceTests 2>&1 | grep -E "error:|Executed"
```
Expected: `Executed 11 tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(honor): the pilgrimage catalog, read once a day from the branch

Not the moving v1 tag: jsDelivr caches a tag URL permanently and still
serves a March index behind it. Routes without a ways entry are below the
dataset's floor and stay hidden; a bad row is dropped rather than costing
the pilgrim every route.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: `PilgrimageLedger` — the route remembers your place

**Files:**
- Create: `Pilgrim/Models/Honor/PilgrimageLedger.swift`
- Test: `UnitTests/Honor/PilgrimageLedgerTests.swift`

**Interfaces:**
- Consumes: `WayStage`, `PilgrimageRouteStage`, `WayStore.pilgrimageDirectory(for:)`, `StatsHelper`.
- Produces:
  - `struct HonorStageOutcome: Equatable { let progressFrac: Double; let arrived: Bool }`
  - `struct PilgrimageLedger: Codable, Equatable` with `routeId`, `var stages: [String: Entry]`, `var carriedKm: Double?`, `var redrawNoticePending: Bool?`; nested `struct Entry: Codable, Equatable { let name: String; let distanceKm: Double; var walkedAt: Date; var kmWalked: Double; var completed: Bool; var stoppedAtFrac: Double? }`
  - `var totalKmWalked: Double`, `var completedCount: Int`
  - `func next(stageCount: Int) -> Next?` where `struct Next: Equatable { let index: Int; let resumeFrac: Double? }`
  - `mutating func record(stageIndex:name:distanceKm:outcome:at:)`
  - `func reconciled(against stages: [PilgrimageRouteStage]) -> PilgrimageLedger`
  - `static func progressLine(ledger: PilgrimageLedger?, stageCount: Int) -> String`
  - `enum PilgrimageLedgerWriter { static func entry(stage: WayStage, outcome: HonorStageOutcome?) -> (index: Int, name: String, distanceKm: Double, outcome: HonorStageOutcome)? }`
  - `final class PilgrimageLedgerStore { init(store: WayStore = .shared); func load(routeId: String) -> PilgrimageLedger?; func save(_ ledger: PilgrimageLedger); func clearRedrawNotice(routeId: String) }`

- [ ] **Step 1: Write the failing tests**

`UnitTests/Honor/PilgrimageLedgerTests.swift`:

```swift
import XCTest
@testable import Pilgrim

final class PilgrimageLedgerTests: XCTestCase {

    private let day = Date(timeIntervalSince1970: 1_800_000_000)

    private func ledger() -> PilgrimageLedger {
        PilgrimageLedger(routeId: "camino-frances")
    }

    private func stage(_ index: Int, name: String, km: Double) -> WayStage {
        WayStage(routeId: "camino-frances", index: index, count: 33, name: name, theme: "t",
                 narrative: "n", closing: "c", warnings: [], distanceKm: km, gainMeters: 100,
                 hours: WayStageHours(min: 5, max: 7), difficulty: "moderate",
                 start: WayStagePlace(name: "a", at: WayCoordinate(lat: 0, lon: 0)),
                 end: WayStagePlace(name: "b", at: WayCoordinate(lat: 0, lon: 0.01)))
    }

    private func routeStage(_ index: Int, name: String, km: Double) -> PilgrimageRouteStage {
        PilgrimageRouteStage(index: index, name: name, distanceKm: km, gainMeters: 100,
                             hours: WayStageHours(min: 5, max: 7), difficulty: "moderate")
    }

    // MARK: - Recording

    func testACompletedStageAndAPartialOneAreBothRemembered() {
        var led = ledger()
        led.record(stageIndex: 0, name: "SJPP to Roncesvalles", distanceKm: 24.2,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: day)
        led.record(stageIndex: 1, name: "Roncesvalles to Zubiri", distanceKm: 21.9,
                   outcome: HonorStageOutcome(progressFrac: 0.58, arrived: false), at: day)
        XCTAssertEqual(led.stages["0"]?.completed, true)
        XCTAssertEqual(led.stages["0"]?.kmWalked ?? 0, 24.2, accuracy: 0.01)
        XCTAssertNil(led.stages["0"]?.stoppedAtFrac)
        XCTAssertEqual(led.stages["1"]?.completed, false)
        XCTAssertEqual(led.stages["1"]?.stoppedAtFrac ?? 0, 0.58, accuracy: 0.001)
        XCTAssertEqual(led.stages["1"]?.kmWalked ?? 0, 21.9 * 0.58, accuracy: 0.01)
        XCTAssertEqual(led.totalKmWalked, 24.2 + 21.9 * 0.58, accuracy: 0.01)
        XCTAssertEqual(led.completedCount, 1)
    }

    func testASecondWalkOfTheSameStageNeverLosesGround() {
        var led = ledger()
        led.record(stageIndex: 0, name: "s", distanceKm: 24.2,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: day)
        led.record(stageIndex: 0, name: "s", distanceKm: 24.2,
                   outcome: HonorStageOutcome(progressFrac: 0.2, arrived: false), at: day.addingTimeInterval(86_400))
        XCTAssertEqual(led.stages["0"]?.completed, true, "walking it again half-way does not un-walk it")
        XCTAssertEqual(led.stages["0"]?.kmWalked ?? 0, 24.2, accuracy: 0.01)
    }

    // MARK: - The next row

    func testNextOffersTheFirstUnwalkedStageAndResumesAPartialOne() {
        var led = ledger()
        led.record(stageIndex: 0, name: "a", distanceKm: 24.2,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: day)
        XCTAssertEqual(led.next(stageCount: 3), PilgrimageLedger.Next(index: 1, resumeFrac: nil))
        led.record(stageIndex: 1, name: "b", distanceKm: 21.9,
                   outcome: HonorStageOutcome(progressFrac: 0.58, arrived: false), at: day)
        XCTAssertEqual(led.next(stageCount: 3), PilgrimageLedger.Next(index: 1, resumeFrac: 0.58))
        led.record(stageIndex: 1, name: "b", distanceKm: 21.9,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: day)
        led.record(stageIndex: 2, name: "c", distanceKm: 20,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: day)
        XCTAssertNil(led.next(stageCount: 3), "every stage walked")
    }

    func testAnEmptyLedgerOffersTheFirstStage() {
        XCTAssertEqual(PilgrimageLedger(routeId: "x").next(stageCount: 33),
                       PilgrimageLedger.Next(index: 0, resumeFrac: nil))
    }

    func testProgressLineReadsTheStageYouAreOn() {
        var led = ledger()
        XCTAssertEqual(PilgrimageLedger.progressLine(ledger: nil, stageCount: 33), "33 stages")
        for index in 0..<4 {
            led.record(stageIndex: index, name: "s\(index)", distanceKm: 28,
                       outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: day)
        }
        XCTAssertEqual(PilgrimageLedger.progressLine(ledger: led, stageCount: 33),
                       "stage 5 of 33 · \(StatsHelper.string(for: 112_000, unit: UnitLength.meters, type: .distance)) walked")
        for index in 4..<33 {
            led.record(stageIndex: index, name: "s\(index)", distanceKm: 10,
                       outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: day)
        }
        XCTAssertTrue(PilgrimageLedger.progressLine(ledger: led, stageCount: 33).hasPrefix("you have walked the whole way"))
    }

    // MARK: - Identity across an update

    func testReconcileKeepsStagesWhoseIdentityHeldAndCarriesTheRestsKilometres() {
        var led = ledger()
        led.record(stageIndex: 0, name: "SJPP to Roncesvalles", distanceKm: 24.2,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: day)
        led.record(stageIndex: 1, name: "Roncesvalles to Zubiri", distanceKm: 21.9,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: day)
        led.record(stageIndex: 2, name: "Zubiri to Pamplona", distanceKm: 20.4,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: day)

        let reconciled = led.reconciled(against: [
            routeStage(0, name: "SJPP to Roncesvalles", km: 24.2),          // identical
            routeStage(1, name: "Roncesvalles to Zubiri", km: 22.7),        // 3.7% — inside 5%
            routeStage(2, name: "Zubiri to Larrasoaña", km: 20.4)           // renamed
        ])
        XCTAssertEqual(Set(reconciled.stages.keys), ["0", "1"])
        XCTAssertEqual(reconciled.carriedKm ?? 0, 20.4, accuracy: 0.01, "the dropped stage's kilometres are kept")
        XCTAssertEqual(reconciled.totalKmWalked, 24.2 + 21.9 + 20.4, accuracy: 0.01)
        XCTAssertEqual(reconciled.redrawNoticePending, true)
    }

    func testAStageWhoseDistanceMovedMoreThanFivePercentIsDropped() {
        var led = ledger()
        led.record(stageIndex: 0, name: "a", distanceKm: 20,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: day)
        let reconciled = led.reconciled(against: [routeStage(0, name: "a", km: 21.5)])   // 7.5%
        XCTAssertTrue(reconciled.stages.isEmpty)
        XCTAssertEqual(reconciled.carriedKm ?? 0, 20, accuracy: 0.01)
    }

    func testAnUnchangedRouteRaisesNoNotice() {
        var led = ledger()
        led.record(stageIndex: 0, name: "a", distanceKm: 20,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: day)
        let reconciled = led.reconciled(against: [routeStage(0, name: "a", km: 20)])
        XCTAssertEqual(reconciled.stages.count, 1)
        XCTAssertNil(reconciled.redrawNoticePending)
        XCTAssertNil(reconciled.carriedKm)
    }

    // MARK: - The writer

    func testNothingIsWrittenWithoutAnAnchor() {
        XCTAssertNil(PilgrimageLedgerWriter.entry(stage: stage(0, name: "a", km: 24.2), outcome: nil),
                     "the engine never anchored on the Way: no stage was walked")
        let written = PilgrimageLedgerWriter.entry(
            stage: stage(3, name: "a", km: 24.2),
            outcome: HonorStageOutcome(progressFrac: 0.4, arrived: false))
        XCTAssertEqual(written?.index, 3)
        XCTAssertEqual(written?.distanceKm, 24.2)
    }

    // MARK: - The file

    func testTheLedgerOutlivesTheStages() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let wayStore = WayStore(baseDirectory: dir)
        let store = PilgrimageLedgerStore(store: wayStore)
        var led = ledger()
        led.record(stageIndex: 0, name: "a", distanceKm: 24.2,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: day)
        store.save(led)
        XCTAssertEqual(store.load(routeId: "camino-frances")?.completedCount, 1)

        // Remove takes the stage Ways; the package folder's ledger stays.
        wayStore.delete(id: WayStore.stageWayId(routeId: "camino-frances", stageIndex: 0))
        XCTAssertEqual(store.load(routeId: "camino-frances")?.completedCount, 1)
        XCTAssertNil(store.load(routeId: "../etc"))
    }
}
```

- [ ] **Step 2: Register and run to verify it fails**

```bash
ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/PilgrimageLedgerTests.swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/PilgrimageLedgerTests 2>&1 | grep -E "error:|Executed"
```
Expected: `cannot find 'PilgrimageLedger' in scope`.

- [ ] **Step 3: Create `PilgrimageLedger.swift`**

```swift
import Foundation

/// What the engine had to say about a stage when the walk ended. Captured
/// before teardown, because the engine is gone by the time the walk is saved.
struct HonorStageOutcome: Equatable {
    let progressFrac: Double
    let arrived: Bool
}

/// The per-route record of stages walked. It outlives the package: Replace
/// and Remove take the stages, never this file, so a route that comes back
/// finds its record.
struct PilgrimageLedger: Codable, Equatable {

    struct Entry: Codable, Equatable {
        /// The stage's identity across an update, with `distanceKm`.
        let name: String
        let distanceKm: Double
        var walkedAt: Date
        var kmWalked: Double
        var completed: Bool
        var stoppedAtFrac: Double?
    }

    struct Next: Equatable {
        let index: Int
        /// Where a partial stage stopped, so the overview opens with the
        /// camera there. Nil for a stage never begun.
        let resumeFrac: Double?
    }

    let routeId: String
    /// Keyed by stage index as a string, the shape the file on disk carries.
    var stages: [String: Entry]
    /// Kilometres from entries a redraw dropped, so the total never shrinks
    /// under the walker.
    var carriedKm: Double?
    /// Set by `reconciled(against:)`; the route view says so once.
    var redrawNoticePending: Bool?

    init(routeId: String, stages: [String: Entry] = [:], carriedKm: Double? = nil, redrawNoticePending: Bool? = nil) {
        self.routeId = routeId
        self.stages = stages
        self.carriedKm = carriedKm
        self.redrawNoticePending = redrawNoticePending
    }

    /// Non-finite values would reach a formatter and, through `Int(_:)`, a
    /// trap; a ledger read off disk is as untrusted as any other file.
    var totalKmWalked: Double {
        let walked = stages.values.map(\.kmWalked).filter(\.isFinite).reduce(0, +)
        return walked + ((carriedKm?.isFinite ?? false) ? carriedKm! : 0)
    }

    var completedCount: Int { stages.values.filter(\.completed).count }

    // MARK: - Writing

    mutating func record(stageIndex: Int, name: String, distanceKm: Double, outcome: HonorStageOutcome, at date: Date) {
        let frac = min(max(outcome.progressFrac.isFinite ? outcome.progressFrac : 0, 0), 1)
        let km = distanceKm.isFinite ? max(0, distanceKm) : 0
        let key = String(stageIndex)
        let existing = stages[key]
        // A second, shorter walk of the same stage never un-walks it: the
        // ledger keeps the best the pilgrim has done.
        let completed = outcome.arrived || (existing?.completed ?? false)
        let walkedKm = max(completed ? km : km * frac, existing?.kmWalked ?? 0)
        stages[key] = Entry(
            name: name, distanceKm: km, walkedAt: date, kmWalked: walkedKm,
            completed: completed, stoppedAtFrac: completed ? nil : frac)
    }

    // MARK: - Reading

    /// The first stage without a completed entry, resumed where it stopped.
    /// Nil when every stage is walked — the row then reads
    /// "you have walked the whole way" and offers the first stage again.
    func next(stageCount: Int) -> Next? {
        guard stageCount > 0 else { return nil }
        for index in 0..<stageCount where stages[String(index)]?.completed != true {
            return Next(index: index, resumeFrac: stages[String(index)]?.stoppedAtFrac)
        }
        return nil
    }

    /// "stage 5 of 33 · 112 km walked", in the walker's own distance unit.
    static func progressLine(ledger: PilgrimageLedger?, stageCount: Int) -> String {
        guard let ledger, !ledger.stages.isEmpty || (ledger.carriedKm ?? 0) > 0 else {
            return stageCount == 1 ? "1 stage" : "\(stageCount) stages"
        }
        let walked = StatsHelper.string(for: ledger.totalKmWalked * 1000, unit: UnitLength.meters, type: .distance)
        guard let next = ledger.next(stageCount: stageCount) else {
            return "you have walked the whole way · \(walked)"
        }
        return "stage \(next.index + 1) of \(stageCount) · \(walked) walked"
    }

    // MARK: - Across an update

    static let identityToleranceRatio = 0.05

    /// An entry survives an update only if the new package's stage at that
    /// index has the same name and a `distanceKm` within 5%. What is dropped
    /// leaves its kilometres behind in `carriedKm`.
    func reconciled(against newStages: [PilgrimageRouteStage]) -> PilgrimageLedger {
        let byIndex = Dictionary(newStages.map { ($0.index, $0) }, uniquingKeysWith: { first, _ in first })
        var kept: [String: Entry] = [:]
        var dropped = 0.0
        for (key, entry) in stages {
            guard let index = Int(key), let fresh = byIndex[index], fresh.name == entry.name,
                  entry.distanceKm > 0, fresh.distanceKm.isFinite,
                  abs(fresh.distanceKm - entry.distanceKm) / entry.distanceKm <= Self.identityToleranceRatio else {
                dropped += entry.kmWalked.isFinite ? entry.kmWalked : 0
                continue
            }
            kept[key] = entry
        }
        guard dropped > 0 else {
            return PilgrimageLedger(routeId: routeId, stages: kept,
                                    carriedKm: carriedKm, redrawNoticePending: redrawNoticePending)
        }
        return PilgrimageLedger(routeId: routeId, stages: kept,
                                carriedKm: (carriedKm ?? 0) + dropped, redrawNoticePending: true)
    }
}

/// The one place that decides whether a walk earned a ledger entry.
enum PilgrimageLedgerWriter {

    /// Nil when the engine never anchored on the Way — Begin's frac-0
    /// fallback means the walker was still approaching, and an approach is
    /// not a stage walked.
    static func entry(stage: WayStage, outcome: HonorStageOutcome?)
        -> (index: Int, name: String, distanceKm: Double, outcome: HonorStageOutcome)? {
        guard let outcome else { return nil }
        return (stage.index, stage.name, stage.distanceKm, outcome)
    }
}

/// `Ways/pilgrimage/<route-id>/ledger.json`.
final class PilgrimageLedgerStore {

    private let store: WayStore
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(store: WayStore = .shared) {
        self.store = store
    }

    func load(routeId: String) -> PilgrimageLedger? {
        guard let url = store.pilgrimageDirectory(for: routeId)?.appendingPathComponent("ledger.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(PilgrimageLedger.self, from: data)
    }

    func save(_ ledger: PilgrimageLedger) {
        guard let dir = store.pilgrimageDirectory(for: ledger.routeId) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? encoder.encode(ledger).write(to: dir.appendingPathComponent("ledger.json"), options: .atomic)
    }

    func clearRedrawNotice(routeId: String) {
        guard var ledger = load(routeId: routeId), ledger.redrawNoticePending == true else { return }
        ledger.redrawNoticePending = nil
        save(ledger)
    }
}
```

- [ ] **Step 4: Register, run the tests**

```bash
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Models/Honor/PilgrimageLedger.swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/PilgrimageLedgerTests 2>&1 | grep -E "error:|Executed"
```
Expected: `Executed 10 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(honor): the per-route ledger, which outlives the package

Replace and Remove take a route's stages, never the record of having
walked them; an update keeps only the stages whose identity held.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: `PilgrimagePackageManager` — download into a temporary set, then move

**Files:**
- Create: `Pilgrim/Models/Honor/PilgrimagePackageManager.swift`
- Modify: `Pilgrim/Models/Honor/WayStore.swift` (add `pilgrimageRouteIds()`)
- Modify: `Pilgrim/Models/Honor/WayMediaDownloader.swift:240` (drop `private` from `isDiskFull`)
- Test: `UnitTests/Honor/PilgrimagePackageManagerTests.swift`

**Interfaces:**
- Consumes: `PilgrimageCatalogEntry`, `PilgrimageCatalogService.packageURL(release:routeId:file:)`, `PilgrimageWayImporter.way(from:routeId:stageIndex:)` / `.route(from:)` / `.maxStageBytes` / `.maxRouteBytes`, `PilgrimageError`, `PilgrimageLedger`, `PilgrimageLedgerStore`, `WayStore`, `WayMediaDownloader.isDiskFull(_:)`.
- Produces:
  - `WayStore.pilgrimageRouteIds() -> [String]`
  - `@MainActor final class PilgrimagePackageManager: ObservableObject` with `static let shared`, `init(store:ledgers:session:)`, `var isWalkActive: () -> Bool`, `var saveStage: (Way) throws -> Void`, `var maxPackageBytes: Int`, `@Published private(set) var phase: Phase`, `struct Installed: Equatable { let routeId: String; let release: String; let route: PilgrimageRoute }`, `enum Phase: Equatable { case idle; case downloading(done: Int, total: Int); case failed(PilgrimageError) }`, `func installed() -> Installed?`, `func download(entry: PilgrimageCatalogEntry, release: String) async throws`, `static func stageFileName(_ index: Int) -> String`.

- [ ] **Step 1: Write the failing tests**

`UnitTests/Honor/PilgrimagePackageManagerTests.swift`:

```swift
import XCTest
@testable import Pilgrim

@MainActor
final class PilgrimagePackageManagerTests: XCTestCase {

    private var dir: URL!
    private var wayStore: WayStore!
    private var ledgers: PilgrimageLedgerStore!

    private let entry = PilgrimageCatalogEntry(
        id: "camino-frances", name: "Camino de Santiago (Francés)", names: [:], country: "ES",
        region: "Europe", distanceKm: 46.1, tradition: "christian", stageCount: 2, bytes: 214_000)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        wayStore = WayStore(baseDirectory: dir)
        ledgers = PilgrimageLedgerStore(store: wayStore)
        StubURLProtocol.reset()
        try stubWholePackage()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func url(_ file: String, release: String = "v1.7.0") throws -> URL {
        try XCTUnwrap(PilgrimageCatalogService.packageURL(release: release, routeId: "camino-frances", file: file))
    }

    private func stubWholePackage(release: String = "v1.7.0") throws {
        StubURLProtocol.stub(url: try url("route.json", release: release), body: try PilgrimageFixtures.data("route.json"))
        StubURLProtocol.stub(url: try url("stage-00.json", release: release), body: try PilgrimageFixtures.data("stage-00.json"))
        StubURLProtocol.stub(url: try url("stage-01.json", release: release), body: try PilgrimageFixtures.data("stage-01.json"))
    }

    private func makeManager() -> PilgrimagePackageManager {
        PilgrimagePackageManager(store: wayStore, ledgers: ledgers, session: StubURLProtocol.session())
    }

    func testStageFilesAreZeroPaddedFromZero() {
        XCTAssertEqual(PilgrimagePackageManager.stageFileName(0), "stage-00.json")
        XCTAssertEqual(PilgrimagePackageManager.stageFileName(9), "stage-09.json")
        XCTAssertEqual(PilgrimagePackageManager.stageFileName(32), "stage-32.json")
        XCTAssertEqual(PilgrimagePackageManager.stageFileName(120), "stage-120.json")
    }

    func testDownloadInstallsEveryStageAndRecordsTheRelease() async throws {
        let manager = makeManager()
        try await manager.download(entry: entry, release: "v1.7.0")

        XCTAssertEqual(wayStore.load(id: "pilgrimage:camino-frances:0")?.stage?.theme, "Initiation")
        XCTAssertEqual(wayStore.load(id: "pilgrimage:camino-frances:1")?.stage?.theme, "Descent")
        let installed = try XCTUnwrap(manager.installed())
        XCTAssertEqual(installed.routeId, "camino-frances")
        XCTAssertEqual(installed.release, "v1.7.0")
        XCTAssertEqual(installed.route.stages.count, 2)
        XCTAssertEqual(manager.phase, .idle)
    }

    func testProgressCountsTheRouteFileAndEveryStage() async throws {
        let manager = makeManager()
        var seen: [PilgrimagePackageManager.Phase] = []
        let cancellable = manager.$phase.sink { seen.append($0) }
        try await manager.download(entry: entry, release: "v1.7.0")
        cancellable.cancel()
        XCTAssertTrue(seen.contains(.downloading(done: 1, total: 3)), "route.json landed")
        XCTAssertTrue(seen.contains(.downloading(done: 3, total: 3)), "both stages landed")
        XCTAssertEqual(seen.last, .idle)
    }

    func testAStageThatFailsValidationLeavesNothingBehind() async throws {
        let broken = String(data: try PilgrimageFixtures.data("stage-01.json"), encoding: .utf8)!
            .replacingOccurrences(of: "\"frac\": 1.0", with: "\"frac\": 9.0")
        StubURLProtocol.stub(url: try url("stage-01.json"), body: Data(broken.utf8))
        let manager = makeManager()
        do {
            try await manager.download(entry: entry, release: "v1.7.0")
            XCTFail("expected notWalkable")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .notWalkable)
        }
        XCTAssertNil(wayStore.load(id: "pilgrimage:camino-frances:0"), "the first stage is rolled back too")
        XCTAssertNil(manager.installed())
        XCTAssertEqual(manager.phase, .failed(.notWalkable))
    }

    func testANetworkFailureMidwayReportsAnUnfinishedDownload() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(url: try url("route.json"), body: try PilgrimageFixtures.data("route.json"))
        StubURLProtocol.stub(url: try url("stage-00.json"), body: try PilgrimageFixtures.data("stage-00.json"))
        // stage-01 is not stubbed: the protocol answers .notConnectedToInternet.
        let manager = makeManager()
        do {
            try await manager.download(entry: entry, release: "v1.7.0")
            XCTFail("expected incomplete")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .incomplete)
        }
        XCTAssertNil(wayStore.load(id: "pilgrimage:camino-frances:0"))
        XCTAssertEqual(manager.phase, .failed(.incomplete))
    }

    func testAnOversizedStageFileIsRefusedBeforeItIsBuffered() async throws {
        let huge = Data(repeating: 0x20, count: PilgrimageWayImporter.maxStageBytes + 1)
        StubURLProtocol.stub(url: try url("stage-00.json"), body: huge)
        let manager = makeManager()
        do {
            try await manager.download(entry: entry, release: "v1.7.0")
            XCTFail("expected incomplete")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .incomplete)
        }
    }

    func testARouteFileThatDoesNotMatchTheCatalogEntryIsRefused() async throws {
        let mismatched = String(data: try PilgrimageFixtures.data("route.json"), encoding: .utf8)!
            .replacingOccurrences(of: "\"stageCount\": 2", with: "\"stageCount\": 5")
        StubURLProtocol.stub(url: try url("route.json"), body: Data(mismatched.utf8))
        let manager = makeManager()
        do {
            try await manager.download(entry: entry, release: "v1.7.0")
            XCTFail("expected notWalkable")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .notWalkable)
        }
    }

    func testDownloadIsRefusedWhileAWalkIsOn() async throws {
        let manager = makeManager()
        manager.isWalkActive = { true }
        do {
            try await manager.download(entry: entry, release: "v1.7.0")
            XCTFail("expected walkInProgress")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .walkInProgress)
        }
        XCTAssertNil(wayStore.load(id: "pilgrimage:camino-frances:0"))
    }

    /// The commit loop is the one place a half-route could survive: a stage
    /// saved before the disk filled would sit in the Ways list with no
    /// `route.json` to name it and no `installed()` able to reach it.
    func testAFailedSaveMidCommitRollsBackEveryStageAlreadyWritten() async throws {
        let manager = makeManager()
        let store = wayStore!
        var saves = 0
        manager.saveStage = { way in
            saves += 1
            // The second stage is where the disk runs out.
            if saves == 2 { throw CocoaError(.fileWriteOutOfSpace) }
            try store.save(way)
        }
        do {
            try await manager.download(entry: entry, release: "v1.7.0")
            XCTFail("expected diskFull")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .diskFull)
        }
        XCTAssertNil(wayStore.load(id: "pilgrimage:camino-frances:0"),
                     "the stage that did save is taken back up")
        XCTAssertNil(wayStore.load(id: "pilgrimage:camino-frances:1"))
        XCTAssertTrue(wayStore.list().isEmpty, "no orphan Ways left in the list")
        XCTAssertNil(manager.installed())
        let packageDir = try XCTUnwrap(wayStore.pilgrimageDirectory(for: "camino-frances"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: packageDir.appendingPathComponent("route.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: packageDir.appendingPathComponent("release.txt").path))
        XCTAssertEqual(manager.phase, .failed(.diskFull))
    }

    /// The index's `bytes` is a hint the dataset wrote, not a promise the CDN
    /// keeps. The ceiling has to hold against what actually lands.
    func testTheWholePackageIsBoundedByRealBytesNotTheIndexsClaim() async throws {
        let manager = makeManager()
        manager.maxPackageBytes = 1_000
        do {
            try await manager.download(entry: entry, release: "v1.7.0")
            XCTFail("expected incomplete")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .incomplete)
        }
        XCTAssertNil(manager.installed())
        XCTAssertTrue(wayStore.list().isEmpty)
    }
}
```

- [ ] **Step 2: Register and run to verify it fails**

```bash
ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/PilgrimagePackageManagerTests.swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/PilgrimagePackageManagerTests 2>&1 | grep -E "error:|Executed"
```
Expected: `cannot find 'PilgrimagePackageManager' in scope`.

- [ ] **Step 3: Let the store list installed routes**

Add to `Pilgrim/Models/Honor/WayStore.swift`, beneath `pilgrimageDirectory(for:)`:

```swift
    /// Route ids with a package folder on this phone. A folder left holding
    /// only its ledger still appears here; the package manager decides what
    /// counts as installed.
    func pilgrimageRouteIds() -> [String] {
        let root = base.appendingPathComponent("pilgrimage", isDirectory: true)
        return ((try? fileManager.contentsOfDirectory(atPath: root.path)) ?? []).filter(Self.isValidRouteId)
    }
```

- [ ] **Step 4: Share the disk-full test with the media downloader**

In `Pilgrim/Models/Honor/WayMediaDownloader.swift`, change the declaration at line 240 from

```swift
    nonisolated private static func isDiskFull(_ error: Error) -> Bool {
```

to

```swift
    /// Shared with `PilgrimagePackageManager`: a full disk surfaces the same
    /// three ways whichever transfer hit it.
    nonisolated static func isDiskFull(_ error: Error) -> Bool {
```

- [ ] **Step 5: Create `PilgrimagePackageManager.swift`**

```swift
import Combine
import Foundation

/// One route at a time, all or nothing. Files land in a temporary directory
/// and are validated there; only a complete, valid set is moved into the
/// store. A failure mid-way leaves the phone exactly as it was.
@MainActor
final class PilgrimagePackageManager: ObservableObject {

    static let shared = PilgrimagePackageManager()

    struct Installed: Equatable {
        let routeId: String
        let release: String
        let route: PilgrimageRoute
    }

    enum Phase: Equatable {
        case idle
        /// `total` counts `route.json` plus every stage file.
        case downloading(done: Int, total: Int)
        case failed(PilgrimageError)
    }

    @Published private(set) var phase: Phase = .idle

    /// Set by `MainCoordinatorView`. Downloading a second route, Replace,
    /// Update, and Remove are all refused while a walk is on.
    var isWalkActive: () -> Bool = { false }

    /// The commit's one write to the store, behind a seam so a spec can fail
    /// it mid-loop and prove the rollback below.
    var saveStage: (Way) throws -> Void

    /// The whole package's ceiling, counted on the bytes that actually land.
    /// Injectable so a spec need not serve 50 MB to prove it holds.
    var maxPackageBytes = PilgrimageCatalogService.maxPackageBytes

    let store: WayStore
    let ledgers: PilgrimageLedgerStore
    private let session: URLSession

    private static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    init(store: WayStore = .shared,
         ledgers: PilgrimageLedgerStore = PilgrimageLedgerStore(),
         session: URLSession = PilgrimagePackageManager.defaultSession) {
        self.store = store
        self.ledgers = ledgers
        self.session = session
        // Captures the parameter, not `self`: assigned before `self` is fully
        // initialized and free of a retain cycle either way.
        self.saveStage = { try store.save($0) }
    }

    /// Zero-padded from 00, widening only when a route needs it — the shape
    /// the build step emits.
    static func stageFileName(_ index: Int) -> String {
        String(format: index < 100 ? "stage-%02d.json" : "stage-%03d.json", index)
    }

    // MARK: - What is on the phone

    func installed() -> Installed? {
        for routeId in store.pilgrimageRouteIds() {
            guard let dir = store.pilgrimageDirectory(for: routeId),
                  let routeData = try? Data(contentsOf: dir.appendingPathComponent("route.json")),
                  let route = try? PilgrimageWayImporter.route(from: routeData),
                  let release = try? String(contentsOf: dir.appendingPathComponent("release.txt"), encoding: .utf8),
                  PilgrimageCatalogService.isValidRelease(release) else { continue }
            return Installed(routeId: routeId, release: release, route: route)
        }
        return nil
    }

    /// True when the catalog names a release the installed package was not
    /// built at. Any difference counts: the index only ever moves forward.
    func hasUpdate(catalogRelease: String) -> Bool {
        guard let installed = installed(), PilgrimageCatalogService.isValidRelease(catalogRelease) else { return false }
        return installed.release != catalogRelease
    }

    // MARK: - Download

    /// Fetches `route.json` and every stage at the exact release the index
    /// named, into a temporary directory, and swaps the finished set in.
    func download(entry: PilgrimageCatalogEntry, release: String) async throws {
        guard !isWalkActive() else { throw PilgrimageError.walkInProgress }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pilgrimage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        do {
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            let total = entry.stageCount + 1
            // Counted across every file, not per file: 200 stages each just
            // under the 2 MB per-file cap would otherwise be 400 MB.
            var packageBytes = 0
            let fetched = try await stageRouteFile(entry: entry, release: release, into: temp)
            packageBytes += fetched.bytes
            try checkBudget(packageBytes)
            phase = .downloading(done: 1, total: total)
            for index in 0..<fetched.route.stageCount {
                packageBytes += try await stageOneStage(entry: entry, release: release, index: index, into: temp)
                try checkBudget(packageBytes)
                phase = .downloading(done: index + 2, total: total)
            }
            try commit(routeId: entry.id, release: release, stageCount: fetched.route.stageCount, from: temp)
            phase = .idle
        } catch {
            let failure = (error as? PilgrimageError) ?? .incomplete
            phase = .failed(failure)
            throw failure
        }
    }

    /// The index's `bytes` is a figure the dataset wrote; this is the one the
    /// phone actually paid.
    private func checkBudget(_ bytes: Int) throws {
        guard bytes <= maxPackageBytes else { throw PilgrimageError.incomplete }
    }

    /// The route file must describe the route the catalog offered: a package
    /// whose own idea of itself differs from the index's is not walkable.
    private func stageRouteFile(entry: PilgrimageCatalogEntry, release: String, into temp: URL) async throws
        -> (route: PilgrimageRoute, bytes: Int) {
        let data = try await fetch(routeId: entry.id, release: release, file: "route.json",
                                   cap: PilgrimageWayImporter.maxRouteBytes)
        let route = try PilgrimageWayImporter.route(from: data)
        guard route.id == entry.id, route.stageCount == entry.stageCount,
              route.stages.count == entry.stageCount else { throw PilgrimageError.notWalkable }
        try write(data, to: temp.appendingPathComponent("route.json"))
        return (route, data.count)
    }

    /// Validated as it lands, then written in the store's own encoding, so
    /// the commit below is a decode-and-save rather than a second parse of
    /// untrusted bytes. Returns the bytes it cost.
    @discardableResult
    private func stageOneStage(entry: PilgrimageCatalogEntry, release: String, index: Int, into temp: URL) async throws -> Int {
        let data = try await fetch(routeId: entry.id, release: release, file: Self.stageFileName(index),
                                   cap: PilgrimageWayImporter.maxStageBytes)
        let way = try PilgrimageWayImporter.way(from: data, routeId: entry.id, stageIndex: index)
        try write(try Self.encoder.encode(way), to: temp.appendingPathComponent("\(index).way.json"))
        return data.count
    }

    private func fetch(routeId: String, release: String, file: String, cap: Int) async throws -> Data {
        guard let url = PilgrimageCatalogService.packageURL(release: release, routeId: routeId, file: file) else {
            throw PilgrimageError.notWalkable
        }
        do {
            let (bytes, response) = try await session.bytes(from: url)
            // Checked before draining: an oversized declared length must not
            // cost a full download first.
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.expectedContentLength <= Int64(cap) else { throw PilgrimageError.incomplete }
            var buffer = Data()
            buffer.reserveCapacity(min(cap, 256 * 1024))
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count > cap { throw PilgrimageError.incomplete }
            }
            return buffer
        } catch let error as PilgrimageError {
            throw error
        } catch {
            throw WayMediaDownloader.isDiskFull(error) ? PilgrimageError.diskFull : PilgrimageError.incomplete
        }
    }

    private func write(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw WayMediaDownloader.isDiskFull(error) ? PilgrimageError.diskFull : PilgrimageError.incomplete
        }
    }

    // MARK: - Commit

    /// The only place a downloaded set becomes the installed route. Every
    /// file has already landed and validated in `temp`, but the writes here
    /// can still fail on a full disk — so each stage saved is remembered and
    /// taken back up if a later one throws. A half-committed route is worse
    /// than none: its stage Ways would sit in the Ways list with no
    /// `route.json` to name them and no `installed()` able to reach them.
    private func commit(routeId: String, release: String, stageCount: Int, from temp: URL) throws {
        guard let dir = store.pilgrimageDirectory(for: routeId) else { throw PilgrimageError.notWalkable }
        var saved: [Int] = []
        do {
            for index in 0..<stageCount {
                let data = try Data(contentsOf: temp.appendingPathComponent("\(index).way.json"))
                let way = try Self.decoder.decode(Way.self, from: data)
                try saveStage(way)
                saved.append(index)
            }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try write(try Data(contentsOf: temp.appendingPathComponent("route.json")),
                      to: dir.appendingPathComponent("route.json"))
            try write(Data(release.utf8), to: dir.appendingPathComponent("release.txt"))
        } catch {
            rollBack(routeId: routeId, savedStageIndices: saved)
            if let failure = error as? PilgrimageError { throw failure }
            throw WayMediaDownloader.isDiskFull(error) ? PilgrimageError.diskFull : PilgrimageError.incomplete
        }
    }

    /// Undoes everything this commit put down. An Update that fails here
    /// leaves the route removed rather than half-replaced — the earlier
    /// package's stages were already overwritten by the time the failure
    /// landed, so "nothing" is the only honest state left. The ledger is
    /// untouched, so re-downloading restores what was walked.
    private func rollBack(routeId: String, savedStageIndices: [Int]) {
        for index in savedStageIndices {
            store.delete(id: WayStore.stageWayId(routeId: routeId, stageIndex: index))
        }
        guard let dir = store.pilgrimageDirectory(for: routeId) else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("route.json"))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("release.txt"))
    }

    /// The store's own encoding, so a temp file round-trips into exactly the
    /// `way.json` the store would have written.
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
```

- [ ] **Step 6: Register, run the tests**

```bash
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Models/Honor/PilgrimagePackageManager.swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/PilgrimagePackageManagerTests 2>&1 | grep -E "error:|Executed"
```
Expected: `Executed 10 tests, with 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(honor): download a route's package all or nothing

Every file is streamed under its own byte ceiling into a temporary
directory and validated there, the whole package is bounded by the bytes
that actually land, and a commit that fails halfway takes back every
stage it had already saved.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Replace, Update, Remove, and the mid-walk guard

**Files:**
- Modify: `Pilgrim/Models/Honor/PilgrimagePackageManager.swift`
- Test: `UnitTests/Honor/PilgrimagePackageManagerTests.swift` (extend)

**Interfaces:**
- Consumes: everything Task 5 produced, plus `PilgrimageLedger.reconciled(against:)` and `PilgrimageLedgerStore`.
- Produces on `PilgrimagePackageManager`:
  - `func replace(with entry: PilgrimageCatalogEntry, release: String) async throws` — downloads first, removes the old route only once the new set is complete.
  - `func update(entry: PilgrimageCatalogEntry, release: String) async throws` — same swap, then reconciles the ledger by stage identity.
  - `func remove(routeId: String) throws` — takes the stages and the package files, keeps the ledger.
  - `static func replaceConfirmation(routeName: String) -> String`
  - `static func removeConfirmation(routeName: String) -> String`

- [ ] **Step 1: Write the failing tests**

Append to `UnitTests/Honor/PilgrimagePackageManagerTests.swift`:

```swift
extension PilgrimagePackageManagerTests {

    private var norte: PilgrimageCatalogEntry {
        PilgrimageCatalogEntry(id: "camino-norte", name: "Camino del Norte", names: [:], country: "ES",
                               region: "Europe", distanceKm: 46.1, tradition: "christian",
                               stageCount: 2, bytes: 214_000)
    }

    /// The same two fixture stages, re-slugged as a second route.
    private func stubNorte(release: String = "v1.7.0") throws {
        func reslugged(_ name: String) throws -> Data {
            let text = String(data: try PilgrimageFixtures.data(name), encoding: .utf8)!
                .replacingOccurrences(of: "camino-frances", with: "camino-norte")
            return Data(text.utf8)
        }
        for (file, fixture) in [("route.json", "route.json"),
                                ("stage-00.json", "stage-00.json"),
                                ("stage-01.json", "stage-01.json")] {
            let url = try XCTUnwrap(PilgrimageCatalogService.packageURL(release: release, routeId: "camino-norte", file: file))
            StubURLProtocol.stub(url: url, body: try reslugged(fixture))
        }
    }

    func testReplaceOnlyRemovesTheFirstRouteOnceTheSecondIsComplete() async throws {
        let manager = makeManager()
        try await manager.download(entry: entry, release: "v1.7.0")
        var led = PilgrimageLedger(routeId: "camino-frances")
        led.record(stageIndex: 0, name: "Saint-Jean-Pied-de-Port to Roncesvalles", distanceKm: 24.2,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: Date())
        ledgers.save(led)

        try stubNorte()
        try await manager.replace(with: norte, release: "v1.7.0")

        XCTAssertNil(wayStore.load(id: "pilgrimage:camino-frances:0"), "the first route's stages left")
        XCTAssertNil(wayStore.load(id: "pilgrimage:camino-frances:1"))
        XCTAssertNotNil(wayStore.load(id: "pilgrimage:camino-norte:0"))
        XCTAssertEqual(manager.installed()?.routeId, "camino-norte")
        XCTAssertEqual(ledgers.load(routeId: "camino-frances")?.completedCount, 1,
                       "what you walked of it is remembered if it comes back")
    }

    func testAFailedReplaceLeavesTheFirstRouteUntouched() async throws {
        let manager = makeManager()
        try await manager.download(entry: entry, release: "v1.7.0")
        // camino-norte is never stubbed, so every fetch fails.
        do {
            try await manager.replace(with: norte, release: "v1.7.0")
            XCTFail("expected incomplete")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .incomplete)
        }
        XCTAssertEqual(manager.installed()?.routeId, "camino-frances")
        XCTAssertNotNil(wayStore.load(id: "pilgrimage:camino-frances:0"))
        XCTAssertNil(wayStore.load(id: "pilgrimage:camino-norte:0"))
    }

    func testUpdateReconcilesTheLedgerByStageIdentity() async throws {
        let manager = makeManager()
        try await manager.download(entry: entry, release: "v1.7.0")
        var led = PilgrimageLedger(routeId: "camino-frances")
        led.record(stageIndex: 0, name: "Saint-Jean-Pied-de-Port to Roncesvalles", distanceKm: 24.2,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: Date())
        led.record(stageIndex: 1, name: "Roncesvalles to Zubiri", distanceKm: 21.9,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: Date())
        ledgers.save(led)

        // v1.8.0 redraws stage 1 under a new name.
        let redrawnRoute = String(data: try PilgrimageFixtures.data("route.json"), encoding: .utf8)!
            .replacingOccurrences(of: "\"name\": \"Roncesvalles to Zubiri\"", with: "\"name\": \"Roncesvalles to Larrasoaña\"")
        let redrawnStage = String(data: try PilgrimageFixtures.data("stage-01.json"), encoding: .utf8)!
            .replacingOccurrences(of: "Roncesvalles to Zubiri", with: "Roncesvalles to Larrasoaña")
        StubURLProtocol.stub(url: try url("route.json", release: "v1.8.0"), body: Data(redrawnRoute.utf8))
        StubURLProtocol.stub(url: try url("stage-00.json", release: "v1.8.0"), body: try PilgrimageFixtures.data("stage-00.json"))
        StubURLProtocol.stub(url: try url("stage-01.json", release: "v1.8.0"), body: Data(redrawnStage.utf8))

        XCTAssertTrue(manager.hasUpdate(catalogRelease: "v1.8.0"))
        try await manager.update(entry: entry, release: "v1.8.0")

        XCTAssertEqual(manager.installed()?.release, "v1.8.0")
        let after = try XCTUnwrap(ledgers.load(routeId: "camino-frances"))
        XCTAssertEqual(Set(after.stages.keys), ["0"])
        XCTAssertEqual(after.carriedKm ?? 0, 21.9, accuracy: 0.01)
        XCTAssertEqual(after.redrawNoticePending, true)
        XCTAssertFalse(manager.hasUpdate(catalogRelease: "v1.8.0"))
    }

    func testRemoveTakesTheStagesAndKeepsTheLedger() async throws {
        let manager = makeManager()
        try await manager.download(entry: entry, release: "v1.7.0")
        var led = PilgrimageLedger(routeId: "camino-frances")
        led.record(stageIndex: 0, name: "a", distanceKm: 24.2,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: Date())
        ledgers.save(led)

        try manager.remove(routeId: "camino-frances")

        XCTAssertNil(wayStore.load(id: "pilgrimage:camino-frances:0"))
        XCTAssertNil(wayStore.load(id: "pilgrimage:camino-frances:1"))
        XCTAssertNil(manager.installed())
        XCTAssertEqual(ledgers.load(routeId: "camino-frances")?.completedCount, 1)
    }

    func testReplaceUpdateAndRemoveAreAllRefusedMidWalk() async throws {
        let manager = makeManager()
        try await manager.download(entry: entry, release: "v1.7.0")
        manager.isWalkActive = { true }
        try stubNorte()

        do {
            try await manager.replace(with: norte, release: "v1.7.0")
            XCTFail("replace")
        } catch { XCTAssertEqual(error as? PilgrimageError, .walkInProgress) }
        do {
            try await manager.update(entry: entry, release: "v1.8.0")
            XCTFail("update")
        } catch { XCTAssertEqual(error as? PilgrimageError, .walkInProgress) }
        XCTAssertThrowsError(try manager.remove(routeId: "camino-frances")) {
            XCTAssertEqual($0 as? PilgrimageError, .walkInProgress)
        }
        XCTAssertEqual(manager.installed()?.routeId, "camino-frances", "nothing moved")
    }

    func testTheConfirmationsNameTheRouteAndTheirOwnVerb() {
        XCTAssertEqual(
            PilgrimagePackageManager.replaceConfirmation(routeName: "Camino Francés"),
            "Replace the Camino Francés? Its stages leave your phone; what you've walked of it is remembered if it comes back. Walks in your journal stay.")
        XCTAssertEqual(
            PilgrimagePackageManager.removeConfirmation(routeName: "Camino Francés"),
            "Remove the Camino Francés? Its stages leave your phone; what you've walked of it is remembered if it comes back. Walks in your journal stay.")
        XCTAssertFalse(PilgrimagePackageManager.removeConfirmation(routeName: "x").hasPrefix("Replace"),
                       "the Remove alert must not ask about replacing")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/PilgrimagePackageManagerTests 2>&1 | grep -E "error:|Executed"
```
Expected: `value of type 'PilgrimagePackageManager' has no member 'replace'`.

- [ ] **Step 3: Add replace, update, and remove**

Append inside `PilgrimagePackageManager`, after `download(entry:release:)`:

```swift
    // MARK: - Replace, update, remove

    static func replaceConfirmation(routeName: String) -> String {
        "Replace the \(routeName)? Its stages leave your phone; what you've walked of it is remembered if it comes back. Walks in your journal stay."
    }

    /// The same promise, asked about the route being let go rather than the
    /// one arriving — the Remove alert must not ask about replacing.
    static func removeConfirmation(routeName: String) -> String {
        "Remove the \(routeName)? Its stages leave your phone; what you've walked of it is remembered if it comes back. Walks in your journal stay."
    }

    /// Downloads the new route in full before the old one is touched, so a
    /// failed replace leaves the pilgrim with the route they already had.
    func replace(with entry: PilgrimageCatalogEntry, release: String) async throws {
        guard !isWalkActive() else { throw PilgrimageError.walkInProgress }
        let previous = installed()
        try await download(entry: entry, release: release)
        if let previous, previous.routeId != entry.id {
            // The ledger stays: a route that comes back finds its record.
            removeStagesAndPackage(routeId: previous.routeId, stageCount: previous.route.stageCount)
        }
    }

    /// The same swap, then the ledger is reconciled against the stages the
    /// new package actually carries.
    func update(entry: PilgrimageCatalogEntry, release: String) async throws {
        guard !isWalkActive() else { throw PilgrimageError.walkInProgress }
        let previousStageCount = installed()?.route.stageCount ?? 0
        try await download(entry: entry, release: release)
        guard let fresh = installed(), fresh.routeId == entry.id else { throw PilgrimageError.incomplete }
        // A route that shrank leaves stage Ways above the new count behind;
        // nothing lists them and no next row reaches them, so they go.
        for index in fresh.route.stageCount..<max(previousStageCount, fresh.route.stageCount) {
            store.delete(id: WayStore.stageWayId(routeId: entry.id, stageIndex: index))
        }
        if let ledger = ledgers.load(routeId: entry.id) {
            ledgers.save(ledger.reconciled(against: fresh.route.stages))
        }
    }

    func remove(routeId: String) throws {
        guard !isWalkActive() else { throw PilgrimageError.walkInProgress }
        let stageCount = installed().flatMap { $0.routeId == routeId ? $0.route.stageCount : nil }
            ?? PilgrimageWayImporter.maxStageCount
        removeStagesAndPackage(routeId: routeId, stageCount: stageCount)
    }

    /// Takes the stages, `route.json`, and `release.txt`. Never `ledger.json`
    /// — the record of having walked a route outlives the route.
    private func removeStagesAndPackage(routeId: String, stageCount: Int) {
        for index in 0..<stageCount {
            store.delete(id: WayStore.stageWayId(routeId: routeId, stageIndex: index))
        }
        guard let dir = store.pilgrimageDirectory(for: routeId) else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("route.json"))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("release.txt"))
    }
```

- [ ] **Step 4: Run the tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/PilgrimagePackageManagerTests 2>&1 | grep -E "error:|Executed"
```
Expected: `Executed 16 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(honor): replace, update, and remove a route's package

Replace downloads first and only then lets the old route go; update
reconciles the ledger by stage identity; all three are refused mid-walk.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: The walk writes the ledger when it is saved

**Files:**
- Modify: `Pilgrim/Models/Honor/HonorEngine.swift:38-47` (add `isAnchoredOnWay`)
- Modify: `Pilgrim/Scenes/ActiveWalk/ActiveWalkViewModel.swift:104-110` (add `honorStageOutcome`)
- Modify: `Pilgrim/Scenes/ActiveWalk/ActiveWalkViewModel+Honor.swift` (`teardownHonor`)
- Modify: `Pilgrim/Scenes/Root/MainCoordinatorView.swift:104-113`
- Test: `UnitTests/Honor/PilgrimageStageWalkTests.swift`

**Interfaces:**
- Consumes: `HonorStageOutcome`, `PilgrimageLedgerWriter.entry(stage:outcome:)`, `PilgrimageLedger`, `PilgrimageLedgerStore`, `WayStage`.
- Produces:
  - `HonorEngine.isAnchoredOnWay: Bool` — true once the engine anchored on the Way itself, never on Begin's frac-0 fallback.
  - `ActiveWalkViewModel.honorStageOutcome: HonorStageOutcome?` — captured in `teardownHonor()` and deliberately surviving it, like `honorArrival`.
  - `MainCoordinator.recordStageWalk(way:outcome:at:)` — the one place a stage walk reaches the route's ledger.

- [ ] **Step 1: Write the failing tests**

`UnitTests/Honor/PilgrimageStageWalkTests.swift`:

```swift
import XCTest
import Combine
import CoreLocation
@testable import Pilgrim

/// Walking a stage: what the engine, the view model, and the coordinator do
/// differently when the Way came from a pilgrimage package.
final class PilgrimageStageWalkTests: XCTestCase {

    let start = Date(timeIntervalSince1970: 1_000_000)

    /// A 1 km stage running east along the equator, so every distance below
    /// is arithmetic: 0.000898° of longitude is 100 m.
    func stageWay(index: Int = 0, marks: [WayMark] = []) -> Way {
        var moment = WayMoment(id: "wp-orisson", frac: 0.3, at: WayCoordinate(lat: 0, lon: 300 / 111_320),
                               kind: .waypoint(label: "Vierge d'Orisson", icon: "building.columns"))
        moment.text = "A shepherd carried this Madonna up from Lourdes."
        moment.names = ["eu": "Orissongo Ama Birjina", "fr": "Vierge d'Orisson"]
        moment.sitMinutes = 5
        moment.pin = WayCoordinate(lat: 0.0002, lon: 300 / 111_320)
        var way = Way(
            id: WayStore.stageWayId(routeId: "camino-frances", stageIndex: index),
            source: .pilgrimage(routeId: "camino-frances", stageIndex: index),
            title: "Saint-Jean-Pied-de-Port to Roncesvalles",
            departedAt: start, tzIdentifier: "Europe/Madrid", expires: nil,
            route: (0...10).map { WayPoint(lat: 0, lon: Double($0) * 0.000898, alt: nil, t: Double($0) * 60) },
            totalDistanceMeters: 1000, theirActiveSeconds: 600,
            moments: [moment], weather: nil)
        way.marks = marks
        way.stage = WayStage(
            routeId: "camino-frances", index: index, count: 33,
            name: "Saint-Jean-Pied-de-Port to Roncesvalles", theme: "Initiation",
            narrative: "The Pyrenees are the first question the way asks.",
            closing: "You crossed a border on foot.",
            warnings: ["The Napoleon Route closes in winter."],
            distanceKm: 24.2, gainMeters: 1419, hours: WayStageHours(min: 7, max: 9), difficulty: "hard",
            start: WayStagePlace(name: "Saint-Jean-Pied-de-Port", at: WayCoordinate(lat: 0, lon: 0)),
            end: WayStagePlace(name: "Roncesvalles", at: WayCoordinate(lat: 0, lon: 0.00898)))
        return way
    }

    func testTheEngineReportsWhetherItEverAnchoredOnTheWay() {
        let engine = HonorEngine(way: stageWay(), softTapEnabled: false, voicesEnabled: false)
        XCTAssertFalse(engine.isAnchoredOnWay, "no fix yet")
        // A kilometre north of the line: Begin falls back to frac 0.
        engine.processLocation(CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0.01, longitude: 0),
                                          altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                                          timestamp: start))
        XCTAssertFalse(engine.isAnchoredOnWay, "the frac-0 fallback is not a stage joined")
        engine.processLocation(CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.000898),
                                          altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                                          timestamp: start.addingTimeInterval(60)))
        XCTAssertTrue(engine.isAnchoredOnWay)
    }

    func testTheOutcomeSurvivesTeardown() {
        let vm = ActiveWalkViewModel(mode: .honor, way: stageWay())
        vm.builder.setStatus(.ready)
        vm.startRecording()
        let engine = try? XCTUnwrap(vm.honorEngine)
        engine?.processLocation(CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.002694),
                                           altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                                           timestamp: start))
        vm.teardownHonor()
        let outcome = vm.honorStageOutcome
        XCTAssertNotNil(outcome, "the engine is gone by the time the walk is saved")
        XCTAssertEqual(outcome?.progressFrac ?? 0, 0.3, accuracy: 0.02)
        XCTAssertFalse(outcome?.arrived ?? true)
    }

    func testNoOutcomeWithoutAnAnchor() {
        let vm = ActiveWalkViewModel(mode: .honor, way: stageWay())
        vm.builder.setStatus(.ready)
        vm.startRecording()
        vm.honorEngine?.processLocation(
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0.01, longitude: 0),
                       altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: start))
        vm.teardownHonor()
        XCTAssertNil(vm.honorStageOutcome)
    }

    @MainActor
    func testTheCoordinatorWritesTheStageIntoTheRoutesLedger() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let store = WayStore(baseDirectory: dir)
        let ledgers = PilgrimageLedgerStore(store: store)
        let coordinator = MainCoordinator()
        coordinator.pilgrimageLedgers = ledgers

        coordinator.recordStageWalk(way: stageWay(index: 4),
                                    outcome: HonorStageOutcome(progressFrac: 0.58, arrived: false),
                                    at: start)

        let ledger = try XCTUnwrap(ledgers.load(routeId: "camino-frances"))
        XCTAssertEqual(ledger.stages["4"]?.name, "Saint-Jean-Pied-de-Port to Roncesvalles")
        XCTAssertEqual(ledger.stages["4"]?.stoppedAtFrac ?? 0, 0.58, accuracy: 0.001)
        XCTAssertEqual(ledger.stages["4"]?.completed, false)
        XCTAssertEqual(ledger.next(stageCount: 33), PilgrimageLedger.Next(index: 0, resumeFrac: nil),
                       "stages 0 to 3 are still unwalked")
    }

    @MainActor
    func testNothingIsWrittenForAWayThatIsNotAStageOrAWalkThatNeverJoined() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let ledgers = PilgrimageLedgerStore(store: WayStore(baseDirectory: dir))
        let coordinator = MainCoordinator()
        coordinator.pilgrimageLedgers = ledgers

        coordinator.recordStageWalk(way: stageWay(), outcome: nil, at: start)
        XCTAssertNil(ledgers.load(routeId: "camino-frances"))

        var notAStage = stageWay()
        notAStage.stage = nil
        coordinator.recordStageWalk(way: notAStage,
                                    outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: start)
        XCTAssertNil(ledgers.load(routeId: "camino-frances"))
    }
}
```

- [ ] **Step 2: Register and run to verify it fails**

```bash
ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/PilgrimageStageWalkTests.swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/PilgrimageStageWalkTests 2>&1 | grep -E "error:|Executed"
```
Expected: `value of type 'HonorEngine' has no member 'isAnchoredOnWay'`.

- [ ] **Step 3: Let the engine say whether it ever joined the Way**

In `Pilgrim/Models/Honor/HonorEngine.swift`, add beneath `distanceWalkedMeters` (line 38-40):

```swift
    /// Whether the walker ever actually joined the Way. Begin's frac-0
    /// fallback (nothing within 60 m) is an approach, not a joining, and a
    /// stage the walker never joined earns no ledger entry.
    var isAnchoredOnWay: Bool { startFrac != nil && !anchoredByFallback }
```

- [ ] **Step 4: Capture the outcome before teardown**

In `Pilgrim/Scenes/ActiveWalk/ActiveWalkViewModel.swift`, beside `honorArrival` (line 104):

```swift
    /// The engine's last word on this stage, captured in `teardownHonor()`
    /// and deliberately surviving it — the engine is gone by the time the
    /// snapshot reaches `onWalkCompleted`, and the ledger is written there.
    @Published var honorStageOutcome: HonorStageOutcome?
```

In `Pilgrim/Scenes/ActiveWalk/ActiveWalkViewModel+Honor.swift`, at the top of `teardownHonor()` — before the generation bump and the `honorEngine = nil`:

```swift
    func teardownHonor() {
        guard honorEngine != nil || wayVoicePlayer != nil else { return }
        if let engine = honorEngine, engine.isAnchoredOnWay {
            honorStageOutcome = HonorStageOutcome(progressFrac: engine.progressFrac,
                                                  arrived: engine.phase == .arrived)
        }
        honorGeneration += 1
```

(The rest of the method is unchanged; `honorStageOutcome`, like `honorArrival`, is not cleared here.)

- [ ] **Step 5: Write the ledger where the walk is bound to its Way**

In `Pilgrim/Scenes/Root/MainCoordinatorView.swift`, add a stored property beside `importShare` (line 33):

```swift
    /// Injectable so a spec can point the ledger at a temporary directory.
    var pilgrimageLedgers = PilgrimageLedgerStore()
```

Inside `startWalk`'s save callback, extend the block at lines 109-113:

```swift
                    if let way, let uuid = walk?.uuid {
                        try? WayStore.shared.save(way)
                        let arrival = vm?.honorArrival.map { (theirSeconds: $0.theirSeconds, yourSeconds: $0.yourSeconds) }
                        try? WayStore.shared.link(walkUUID: uuid, to: way.id, arrival: arrival)
                        self.recordStageWalk(way: way, outcome: vm?.honorStageOutcome)
                    }
```

And add beneath `retryMedia(for:)` in the `// MARK: - Honor` section:

```swift
    /// The one place a stage walk reaches the route's ledger. Silent for a
    /// Way that is not a stage, and for a walk whose engine never anchored on
    /// the Way — an approach to a trailhead is not a stage walked.
    func recordStageWalk(way: Way?, outcome: HonorStageOutcome?, at date: Date = Date()) {
        guard let stage = way?.stage,
              let written = PilgrimageLedgerWriter.entry(stage: stage, outcome: outcome) else { return }
        var ledger = pilgrimageLedgers.load(routeId: stage.routeId) ?? PilgrimageLedger(routeId: stage.routeId)
        ledger.record(stageIndex: written.index, name: written.name,
                      distanceKm: written.distanceKm, outcome: written.outcome, at: date)
        pilgrimageLedgers.save(ledger)
    }
```

- [ ] **Step 6: Run the tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/PilgrimageStageWalkTests 2>&1 | grep -E "error:|Executed"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/MainCoordinatorHonorTests -only-testing:UnitTests/ActiveWalkHonorTests 2>&1 | grep -E "error:|Executed"
```
Expected: `Executed 5 tests, with 0 failures` for the new suite, and no regression in the two slice-one suites.

- [ ] **Step 7: Commit**

```bash
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(honor): a saved stage walk reaches the route's ledger

The engine is gone by the time the snapshot lands, so teardown keeps its
last word; a walk that never joined the Way earns no entry.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: The third door — catalog and route views

**Files:**
- Create: `Pilgrim/Scenes/Honor/PilgrimageCatalogView.swift` (holds `PilgrimageCatalogModel` and the list)
- Create: `Pilgrim/Scenes/Honor/PilgrimageRouteView.swift` (holds `WayStageFacts`, `PilgrimageRouteModel`, and the route screen)
- Modify: `Pilgrim/Models/Honor/PilgrimageCatalogService.swift` (generalize the fetch; add `routePreview`)
- Modify: `Pilgrim/Scenes/Honor/HonorWaysSheet.swift:36-43`, `:12-19`, `:76-89`
- Modify: `Pilgrim/Scenes/Root/MainCoordinatorView.swift` (`chooseWay`)
- Test: `UnitTests/Honor/PilgrimageCatalogServiceTests.swift` (extend: the preview test on the existing suite, plus the model suite)

**Interfaces:**
- Consumes: `PilgrimageCatalogService`, `PilgrimageCatalogEntry`, `PilgrimagePackageManager`, `PilgrimageRoute`, `PilgrimageRouteStage`, `PilgrimageLedger`, `PilgrimageLedgerStore`, `PilgrimageCopy`, `PilgrimageWayImporter.route(from:)` / `.maxRouteBytes`, `WayStore`, `StatsHelper`, `Constants.Typography.*`.
- Produces:
  - `PilgrimageCatalogService.routePreview(entry:release:) async throws -> PilgrimageRoute` — the route's stage list before anything is downloaded, cached beside the index cache.
  - `enum WayStageFacts { static func line(distanceKm: Double, gainMeters: Double, hours: WayStageHours, difficulty: String) -> String }` — the single stage-facts formatter; Task 13's morning card reuses it.
  - `enum PilgrimageCatalogModel { static func card(entry:ledger:isInstalled:) -> String; static func sparseNote(for entry: PilgrimageCatalogEntry) -> String? }`
  - `enum PilgrimageRouteModel { static func stageLine(_:) -> String; static func nextRow(ledger:stageCount:) -> String; static func buttonLabel(isInstalled:hasUpdate:) -> String; static let redrawNotice: String }`
  - `struct PilgrimageCatalogView: View` — `init(onChoose: @escaping (Way) -> Void)`
  - `struct PilgrimageRouteView: View` — `init(entry: PilgrimageCatalogEntry, release: String, onChoose: @escaping (Way) -> Void)`

- [ ] **Step 1: Write the failing tests**

Append to `PilgrimageCatalogServiceTests` (the preview lives on the service, so it is tested with the service):

```swift
extension PilgrimageCatalogServiceTests {

    /// Spec 2.2 wants a stage list before anything is downloaded, so tapping
    /// a stage of an undownloaded route has a row to tap.
    func testTheRoutePreviewArrivesBeforeAnythingIsDownloaded() async throws {
        let entry = PilgrimageCatalogEntry(
            id: "camino-frances", name: "Camino", names: [:], country: "ES", region: "Europe",
            distanceKm: 46.1, tradition: "christian", stageCount: 2, bytes: 214_000)
        let url = try XCTUnwrap(PilgrimageCatalogService.packageURL(
            release: "v1.7.0", routeId: "camino-frances", file: "route.json"))
        StubURLProtocol.stub(url: url, body: try PilgrimageFixtures.data("route.json"))

        let service = makeService()
        let route = try await service.routePreview(entry: entry, release: "v1.7.0")
        XCTAssertEqual(route.stages.map(\.index), [0, 1])
        XCTAssertEqual(route.stages[0].name, "Saint-Jean-Pied-de-Port to Roncesvalles")
        XCTAssertEqual(StubURLProtocol.requestedURLs.count, 1)

        // Cached beside the index: a second view of the same route is free.
        _ = try await makeService().routePreview(entry: entry, release: "v1.7.0")
        XCTAssertEqual(StubURLProtocol.requestedURLs.count, 1)
    }

    func testAPreviewThatDoesNotMatchTheEntryIsNotWalkable() async throws {
        let entry = PilgrimageCatalogEntry(
            id: "camino-frances", name: "Camino", names: [:], country: "ES", region: "Europe",
            distanceKm: 46.1, tradition: "christian", stageCount: 5, bytes: 214_000)
        let url = try XCTUnwrap(PilgrimageCatalogService.packageURL(
            release: "v1.7.0", routeId: "camino-frances", file: "route.json"))
        StubURLProtocol.stub(url: url, body: try PilgrimageFixtures.data("route.json"))
        do {
            _ = try await makeService().routePreview(entry: entry, release: "v1.7.0")
            XCTFail("expected notWalkable")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .notWalkable)
        }
    }

    func testAPreviewWithNoNetworkIsOutOfReach() async {
        let entry = PilgrimageCatalogEntry(
            id: "camino-frances", name: "Camino", names: [:], country: "ES", region: "Europe",
            distanceKm: 46.1, tradition: "christian", stageCount: 2, bytes: 214_000)
        do {
            _ = try await makeService().routePreview(entry: entry, release: "v1.7.0")
            XCTFail("expected catalogUnreachable")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .catalogUnreachable)
        }
    }
}

final class PilgrimageCatalogModelTests: XCTestCase {

    private let entry = PilgrimageCatalogEntry(
        id: "camino-frances", name: "Camino de Santiago (Francés)", names: [:], country: "ES",
        region: "Europe", distanceKm: 764, tradition: "christian", stageCount: 33, bytes: 2_140_000)

    private var sparseEntry: PilgrimageCatalogEntry {
        PilgrimageCatalogEntry(
            id: "camino-frances", name: "Camino de Santiago (Francés)", names: [:], country: "ES",
            region: "Europe", distanceKm: 764, tradition: "christian", stageCount: 33,
            bytes: 2_140_000, placesPerStage: 0.4, sparse: true)
    }

    private func stage(_ index: Int) -> PilgrimageRouteStage {
        PilgrimageRouteStage(index: index, name: "Saint-Jean-Pied-de-Port to Roncesvalles",
                             distanceKm: 24.2, gainMeters: 1419,
                             hours: WayStageHours(min: 7, max: 9), difficulty: "hard")
    }

    func testACardWithoutAPackageJustCountsTheStages() {
        XCTAssertEqual(PilgrimageCatalogModel.card(entry: entry, ledger: nil, isInstalled: false),
                       "ES · \(StatsHelper.string(for: 764_000, unit: UnitLength.meters, type: .distance)) · 33 stages")
    }

    func testACardWithAPackageSaysSoAndCarriesItsProgress() {
        var led = PilgrimageLedger(routeId: "camino-frances")
        led.record(stageIndex: 0, name: "a", distanceKm: 24.2,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: Date())
        let line = PilgrimageCatalogModel.card(entry: entry, ledger: led, isInstalled: true)
        XCTAssertTrue(line.contains("on your phone"), line)
        XCTAssertTrue(line.contains("stage 2 of 33"), line)
    }

    func testASparseRouteSaysSoWithoutHidingItself() {
        XCTAssertEqual(PilgrimageCatalogModel.sparseNote(for: sparseEntry), "few places marked yet")
        XCTAssertNil(PilgrimageCatalogModel.sparseNote(for: entry))
        // The note is its own quiet line, never folded into the meta line.
        XCTAssertFalse(PilgrimageCatalogModel.card(entry: sparseEntry, ledger: nil, isInstalled: false)
            .contains("few places marked yet"))
    }

    func testStageLineReadsDistanceClimbHoursAndDifficulty() {
        let line = PilgrimageRouteModel.stageLine(stage(0))
        XCTAssertTrue(line.hasPrefix(StatsHelper.string(for: 24_200, unit: UnitLength.meters, type: .distance)), line)
        XCTAssertTrue(line.contains(StatsHelper.string(for: 1419, unit: UnitLength.meters, type: .altitude)), line)
        XCTAssertTrue(line.contains("7 to 9 hours"), line)
        XCTAssertTrue(line.hasSuffix("hard"), line)
    }

    func testAStageWithOneHourFigureDoesNotSayItTwice() {
        let single = PilgrimageRouteStage(index: 0, name: "n", distanceKm: 10, gainMeters: 40,
                                          hours: WayStageHours(min: 4, max: 4), difficulty: "easy")
        XCTAssertTrue(PilgrimageRouteModel.stageLine(single).contains("4 hours"))
        XCTAssertFalse(PilgrimageRouteModel.stageLine(single).contains("4 to 4"))
    }

    /// One formatter, two callers: the stage list and the morning card must
    /// not drift apart, and a non-finite figure must never reach `Int(_:)`.
    func testTheStageFactsFormatterIsTheOneBothCallersUse() {
        let facts = WayStageFacts.line(distanceKm: 24.2, gainMeters: 1419,
                                       hours: WayStageHours(min: 7, max: 9), difficulty: "hard")
        XCTAssertEqual(PilgrimageRouteModel.stageLine(stage(0)), facts)
        XCTAssertEqual(WayStageFacts.line(distanceKm: 10, gainMeters: 0,
                                          hours: WayStageHours(min: 4, max: 4), difficulty: ""),
                       "\(StatsHelper.string(for: 10_000, unit: UnitLength.meters, type: .distance)) · " +
                       "\(StatsHelper.string(for: 0, unit: UnitLength.meters, type: .altitude)) up · 4 hours",
                       "an empty difficulty adds no trailing separator")
        XCTAssertTrue(WayStageFacts.line(distanceKm: 10, gainMeters: 40,
                                         hours: WayStageHours(min: .nan, max: .infinity), difficulty: "easy")
            .contains("0 to 100 hours"), "clamped, never trapped")
    }

    func testTheNextRowOffersResumesAndFinallyCongratulates() {
        var led = PilgrimageLedger(routeId: "camino-frances")
        XCTAssertEqual(PilgrimageRouteModel.nextRow(ledger: nil, stageCount: 33), "start with stage 1")
        led.record(stageIndex: 0, name: "a", distanceKm: 24.2,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: Date())
        XCTAssertEqual(PilgrimageRouteModel.nextRow(ledger: led, stageCount: 33), "next: stage 2")
        led.record(stageIndex: 1, name: "b", distanceKm: 21.9,
                   outcome: HonorStageOutcome(progressFrac: 0.58, arrived: false), at: Date())
        XCTAssertEqual(PilgrimageRouteModel.nextRow(ledger: led, stageCount: 33), "continue from where you stopped")
        for index in 1..<33 {
            led.record(stageIndex: index, name: "s", distanceKm: 20,
                       outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: Date())
        }
        XCTAssertEqual(PilgrimageRouteModel.nextRow(ledger: led, stageCount: 33), "you have walked the whole way")
    }

    func testTheButtonSaysWhatItWillDo() {
        XCTAssertEqual(PilgrimageRouteModel.buttonLabel(isInstalled: false, hasUpdate: false), "Download")
        XCTAssertEqual(PilgrimageRouteModel.buttonLabel(isInstalled: true, hasUpdate: true), "Update")
        XCTAssertEqual(PilgrimageRouteModel.buttonLabel(isInstalled: true, hasUpdate: false), "On your phone")
    }

    func testTheRedrawNoticeIsTheSpecsWords() {
        XCTAssertEqual(PilgrimageRouteModel.redrawNotice,
                       "the route's stages were redrawn; your kilometres are kept.")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/PilgrimageCatalogModelTests 2>&1 | grep -E "error:|Executed"
```
Expected: `cannot find 'PilgrimageCatalogModel' in scope`, and `value of type 'PilgrimageCatalogService' has no member 'routePreview'`.

- [ ] **Step 3: Let the catalog fetch one route's stage list**

In `Pilgrim/Models/Honor/PilgrimageCatalogService.swift`, generalize the private fetch so the preview can share its cap-before-draining discipline. Replace `fetchIndex()` with:

```swift
    private func fetchIndex() async throws -> Data {
        try await fetch(Self.indexURL, cap: Self.maxIndexBytes)
    }

    /// Streamed with a cap, checked before draining: an oversized declared
    /// length must not cost a full download first.
    private func fetch(_ url: URL, cap: Int) async throws -> Data {
        do {
            let (bytes, response) = try await session.bytes(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.expectedContentLength <= Int64(cap) else { throw PilgrimageError.catalogUnreachable }
            var buffer = Data()
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count > cap { throw PilgrimageError.catalogUnreachable }
            }
            return buffer
        } catch let error as PilgrimageError {
            throw error
        } catch {
            throw PilgrimageError.catalogUnreachable
        }
    }
```

Then add the preview beneath `load(force:)`:

```swift
    /// A route's `route.json` before its package is downloaded, so the route
    /// screen can list the stages the pilgrim is being offered. Same byte cap
    /// and same validation as the download path; cached beside the index so
    /// reopening a route costs nothing. The preview never writes into the
    /// package folder — only `PilgrimagePackageManager` installs a route.
    func routePreview(entry: PilgrimageCatalogEntry, release: String) async throws -> PilgrimageRoute {
        if let cached = readRoutePreview(routeId: entry.id, release: release) { return cached }
        guard let url = Self.packageURL(release: release, routeId: entry.id, file: "route.json") else {
            throw PilgrimageError.notWalkable
        }
        let data = try await fetch(url, cap: PilgrimageWayImporter.maxRouteBytes)
        let route = try PilgrimageWayImporter.route(from: data)
        // The same identity check the download makes: a route file that
        // disagrees with the index is not the route being offered.
        guard route.id == entry.id, route.stageCount == entry.stageCount,
              route.stages.count == entry.stageCount else { throw PilgrimageError.notWalkable }
        writeRoutePreview(data, routeId: entry.id, release: release)
        return route
    }

    /// Keyed by release as well as route: a preview from an older build must
    /// never stand in for the stages the current index names.
    private func routePreviewURL(routeId: String, release: String) -> URL? {
        guard WayStore.isValidRouteId(routeId), Self.isValidRelease(release) else { return nil }
        return directory.appendingPathComponent("route-\(routeId)-\(release).json")
    }

    private func readRoutePreview(routeId: String, release: String) -> PilgrimageRoute? {
        guard let url = routePreviewURL(routeId: routeId, release: release),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? PilgrimageWayImporter.route(from: data)
    }

    private func writeRoutePreview(_ data: Data, routeId: String, release: String) {
        guard let url = routePreviewURL(routeId: routeId, release: release) else { return }
        try? data.write(to: url, options: .atomic)
    }
```

- [ ] **Step 4: Create `PilgrimageCatalogView.swift`**

```swift
import SwiftUI

enum PilgrimageCatalogModel {

    /// "ES · 764 km · 33 stages", or, once the package is here, the route's
    /// own progress instead of the bare stage count.
    static func card(entry: PilgrimageCatalogEntry, ledger: PilgrimageLedger?, isInstalled: Bool) -> String {
        var parts: [String] = []
        if let country = entry.country, !country.isEmpty { parts.append(country) }
        parts.append(StatsHelper.string(for: entry.distanceKm * 1000, unit: UnitLength.meters, type: .distance))
        if isInstalled {
            parts.append("on your phone")
            parts.append(PilgrimageLedger.progressLine(ledger: ledger, stageCount: entry.stageCount))
        } else {
            parts.append(entry.stageCount == 1 ? "1 stage" : "\(entry.stageCount) stages")
        }
        return parts.joined(separator: " · ")
    }

    /// The build marks a route sparse when fewer than half its stages carry
    /// a curated place beyond the start and end towns. The route is still
    /// walkable and still listed — this is the honest caption that keeps it
    /// from promising more than it holds.
    static func sparseNote(for entry: PilgrimageCatalogEntry) -> String? {
        entry.sparse ? "few places marked yet" : nil
    }
}

/// The third door: the routes the dataset says are walkable. A route with a
/// package on this phone is marked; everything else is an invitation.
struct PilgrimageCatalogView: View {

    let onChoose: (Way) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var catalogService = PilgrimageCatalogService.shared
    @ObservedObject private var packages = PilgrimagePackageManager.shared
    @State private var isLoading = true
    @State private var failure: PilgrimageError?
    @State private var ledgers: [String: PilgrimageLedger] = [:]
    @State private var installedRouteId: String?
    @State private var opened: PilgrimageCatalogEntry?

    private let ledgerStore = PilgrimageLedgerStore()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Pilgrimages")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                            .font(Constants.Typography.button)
                            .foregroundColor(.stone)
                    }
                }
                .navigationDestination(item: $opened) { entry in
                    PilgrimageRouteView(entry: entry,
                                        release: catalogService.catalog?.release ?? "",
                                        onChoose: onChoose)
                }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading, catalogService.catalog == nil {
            // SwiftUI's, not the project's own ProgressView.
            SwiftUI.ProgressView()
                .tint(.stone)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let routes = catalogService.catalog?.routes, !routes.isEmpty {
            List(routes) { entry in
                Button { opened = entry } label: { row(entry) }
            }
        } else {
            unreachable
        }
    }

    private var unreachable: some View {
        VStack(spacing: Constants.UI.Padding.normal) {
            Text(PilgrimageCopy.line(for: failure ?? .catalogUnreachable))
                .font(Constants.Typography.body)
                .foregroundColor(.fog)
                .multilineTextAlignment(.center)
            Button("try again") { Task { await load(force: true) } }
                .font(Constants.Typography.button)
                .foregroundColor(.stone)
                .frame(minHeight: 44)
        }
        .padding(Constants.UI.Padding.big)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ entry: PilgrimageCatalogEntry) -> some View {
        HStack(alignment: .top, spacing: Constants.UI.Padding.normal) {
            coverPlate(entry)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink)
                Text(PilgrimageCatalogModel.card(entry: entry, ledger: ledgers[entry.id],
                                                 isInstalled: installedRouteId == entry.id))
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                if let sparseNote = PilgrimageCatalogModel.sparseNote(for: entry) {
                    Text(sparseNote)
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog.opacity(0.7))
                }
            }
        }
    }

    /// The dataset ships no cover images yet (spec open question 1), so the
    /// plate stands where one will go rather than leaving the row lopsided.
    private func coverPlate(_ entry: PilgrimageCatalogEntry) -> some View {
        RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.small)
            .fill(Color.parchmentSecondary)
            .frame(width: 44, height: 44)
            .overlay(
                Text(entry.name.prefix(1))
                    .font(Constants.Typography.heading)
                    .foregroundColor(.stone)
            )
            .accessibilityHidden(true)
    }

    private func load(force: Bool = false) async {
        isLoading = true
        failure = nil
        do {
            let catalog = try await catalogService.load(force: force)
            installedRouteId = packages.installed()?.routeId
            ledgers = Dictionary(uniqueKeysWithValues: catalog.routes.compactMap { entry in
                ledgerStore.load(routeId: entry.id).map { (entry.id, $0) }
            })
        } catch {
            failure = (error as? PilgrimageError) ?? .catalogUnreachable
        }
        isLoading = false
    }
}
```

- [ ] **Step 5: Create `PilgrimageRouteView.swift`**

```swift
import SwiftUI

/// "24 km · 1,400 m up · 7 to 9 hours · hard" — the one stage-facts line,
/// shared by the route screen's stage list and the morning card. Two copies
/// of this drifted apart once already.
enum WayStageFacts {

    static func line(distanceKm: Double, gainMeters: Double, hours: WayStageHours, difficulty: String) -> String {
        var parts = [
            StatsHelper.string(for: distanceKm * 1000, unit: UnitLength.meters, type: .distance),
            "\(StatsHelper.string(for: gainMeters, unit: UnitLength.meters, type: .altitude)) up",
            hoursText(hours)
        ]
        if !difficulty.isEmpty { parts.append(difficulty) }
        return parts.joined(separator: " · ")
    }

    /// `Int(_:)` traps on a non-finite Double; the importer already bounds
    /// these, and this is the last step before the number reaches the screen.
    private static func hoursText(_ hours: WayStageHours) -> String {
        let low = boundedHours(hours.min)
        let high = boundedHours(hours.max)
        return low == high ? "\(low) hours" : "\(low) to \(high) hours"
    }

    /// An infinite figure is an absurdly large one and clamps to the ceiling
    /// like any other; a NaN orders against nothing, so `min`/`max` would
    /// carry it straight through to the trap and it takes the floor instead.
    private static func boundedHours(_ value: Double) -> Int {
        guard !value.isNaN else { return 0 }
        return Int(min(max(value, 0), 100).rounded())
    }
}

enum PilgrimageRouteModel {

    static let redrawNotice = "the route's stages were redrawn; your kilometres are kept."

    static func stageLine(_ stage: PilgrimageRouteStage) -> String {
        WayStageFacts.line(distanceKm: stage.distanceKm, gainMeters: stage.gainMeters,
                           hours: stage.hours, difficulty: stage.difficulty)
    }

    static func nextRow(ledger: PilgrimageLedger?, stageCount: Int) -> String {
        guard let next = (ledger ?? PilgrimageLedger(routeId: "")).next(stageCount: stageCount) else {
            return "you have walked the whole way"
        }
        if next.resumeFrac != nil { return "continue from where you stopped" }
        return next.index == 0 ? "start with stage 1" : "next: stage \(next.index + 1)"
    }

    static func buttonLabel(isInstalled: Bool, hasUpdate: Bool) -> String {
        if !isInstalled { return "Download" }
        return hasUpdate ? "Update" : "On your phone"
    }
}

/// One route: what it is, where you are in it, and every stage it divides
/// into. A downloaded stage opens the Honor overview with Begin.
struct PilgrimageRouteView: View {

    let entry: PilgrimageCatalogEntry
    let release: String
    let onChoose: (Way) -> Void

    @ObservedObject private var packages = PilgrimagePackageManager.shared
    @State private var route: PilgrimageRoute?
    @State private var ledger: PilgrimageLedger?
    @State private var installed: PilgrimagePackageManager.Installed?
    @State private var failure: PilgrimageError?
    /// The stage list is fetched separately when nothing is downloaded yet;
    /// its own two states, so a failed preview does not read as a failed
    /// download.
    @State private var isLoadingStages = false
    @State private var stagesFailure: PilgrimageError?
    @State private var confirmReplace = false
    @State private var confirmRemove = false
    @State private var showRedrawNotice = false
    @State private var promptDownload = false

    private let ledgerStore = PilgrimageLedgerStore()

    private var isInstalled: Bool { installed?.routeId == entry.id }
    private var hasUpdate: Bool { isInstalled && packages.hasUpdate(catalogRelease: release) }
    private var stages: [PilgrimageRouteStage] { route?.stages ?? [] }

    var body: some View {
        List {
            Section { header } footer: { statusFooter }
            if isInstalled {
                Section { nextRow }
            }
            Section {
                stageSection
            } header: {
                Text("Stages").font(Constants.Typography.caption)
            }
        }
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isInstalled {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Remove", role: .destructive) { confirmRemove = true }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .task {
            reload()
            await loadStagesIfNeeded()
        }
        .alert("Replace?", isPresented: $confirmReplace) {
            Button("Replace", role: .destructive) { Task { await install(replacing: true) } }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(PilgrimagePackageManager.replaceConfirmation(routeName: installed?.route.name ?? "route"))
        }
        .alert("Remove?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { removeRoute() }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(PilgrimagePackageManager.removeConfirmation(routeName: entry.name))
        }
        .alert("Download this route first?", isPresented: $promptDownload) {
            // The same gate the download button uses: with another route
            // already on the phone, this is a Replace and must say so.
            Button("Download") { beginInstall() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Its stages have to be on your phone before you can walk one.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            if let summary = route?.summary ?? entryFallbackSummary {
                Text(summary).font(Constants.Typography.body).foregroundColor(.ink)
            }
            // Directly under the summary: what the route can promise, before
            // the button that offers to download it.
            if let sparseNote = PilgrimageCatalogModel.sparseNote(for: entry) {
                Text(sparseNote)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog.opacity(0.7))
            }
            Text(PilgrimageCatalogModel.card(entry: entry, ledger: ledger, isInstalled: isInstalled))
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
            downloadButton
        }
    }

    private var entryFallbackSummary: String? {
        entry.tradition.map { "\($0.capitalized) · \(entry.region ?? "")" }
    }

    private var downloadButton: some View {
        Button {
            if isInstalled && !hasUpdate { return }
            beginInstall()
        } label: {
            Text(PilgrimageRouteModel.buttonLabel(isInstalled: isInstalled, hasUpdate: hasUpdate))
                .font(Constants.Typography.button)
                .foregroundColor(.parchment)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isBusy || (isInstalled && !hasUpdate) ? Color.fog : Color.stone)
                .cornerRadius(Constants.UI.CornerRadius.normal)
        }
        .disabled(isBusy || (isInstalled && !hasUpdate))
    }

    @ViewBuilder
    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.xs) {
            if case .downloading(let done, let total) = packages.phase {
                Text("stage \(done) of \(total)").font(Constants.Typography.caption).foregroundColor(.fog)
            }
            if let failure {
                Text(PilgrimageCopy.line(for: failure)).font(Constants.Typography.caption).foregroundColor(.rust)
            }
            if showRedrawNotice {
                Text(PilgrimageRouteModel.redrawNotice).font(Constants.Typography.caption).foregroundColor(.fog)
            }
        }
    }

    private var nextRow: some View {
        Button {
            guard let next = (ledger ?? PilgrimageLedger(routeId: entry.id)).next(stageCount: entry.stageCount)
                ?? stages.first.map({ PilgrimageLedger.Next(index: $0.index, resumeFrac: nil) }) else { return }
            open(index: next.index)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(PilgrimageRouteModel.nextRow(ledger: ledger, stageCount: entry.stageCount))
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink)
                Text(PilgrimageLedger.progressLine(ledger: ledger, stageCount: entry.stageCount))
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
        }
    }

    /// The stage list stands whether or not the package is here: spec 2.2
    /// wants a row to tap before anything is downloaded.
    @ViewBuilder
    private var stageSection: some View {
        if !stages.isEmpty {
            ForEach(stages, id: \.index) { stage in
                Button { open(stage) } label: { stageRow(stage) }
            }
        } else if isLoadingStages {
            HStack {
                SwiftUI.ProgressView().tint(.stone)
                Text("reaching for the stages…")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
        } else if let stagesFailure {
            VStack(alignment: .leading, spacing: Constants.UI.Padding.xs) {
                Text(PilgrimageCopy.line(for: stagesFailure))
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                Button("try again") { Task { await loadStagesIfNeeded(force: true) } }
                    .font(Constants.Typography.caption)
                    .foregroundColor(.stone)
                    .frame(minHeight: 44)
            }
        }
    }

    private func stageRow(_ stage: PilgrimageRouteStage) -> some View {
        HStack(alignment: .top, spacing: Constants.UI.Padding.small) {
            Image(systemName: ledger?.stages[String(stage.index)]?.completed == true ? "circle.fill" : "circle")
                .font(Constants.Typography.caption)
                .foregroundColor(.stone)
                .padding(.top, 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(stage.index + 1). \(stage.name)")
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink)
                Text(PilgrimageRouteModel.stageLine(stage))
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
        }
    }

    // MARK: - Actions

    private var isBusy: Bool {
        if case .downloading = packages.phase { return true }
        return false
    }

    private func open(_ stage: PilgrimageRouteStage) { open(index: stage.index) }

    private func open(index: Int) {
        guard isInstalled,
              let way = WayStore.shared.load(id: WayStore.stageWayId(routeId: entry.id, stageIndex: index)) else {
            promptDownload = true
            return
        }
        onChoose(way)
    }

    /// Every path that starts an install goes through here, so the Replace
    /// confirmation can never be skipped by tapping a stage instead of the
    /// button.
    private func beginInstall() {
        if installed != nil && !isInstalled {
            confirmReplace = true
        } else {
            Task { await install(replacing: false) }
        }
    }

    private func install(replacing: Bool) async {
        failure = nil
        do {
            if hasUpdate {
                try await packages.update(entry: entry, release: release)
            } else if replacing {
                try await packages.replace(with: entry, release: release)
            } else {
                try await packages.download(entry: entry, release: release)
            }
            reload()
        } catch {
            failure = (error as? PilgrimageError) ?? .incomplete
        }
    }

    private func removeRoute() {
        do {
            try packages.remove(routeId: entry.id)
            reload()
        } catch {
            failure = (error as? PilgrimageError) ?? .incomplete
        }
    }

    /// The redraw notice is shown once and then cleared from the ledger, so
    /// the route says it the next time the pilgrim opens this screen and
    /// never again. An installed route's own `route.json` is authoritative;
    /// the preview only fills the gap before one exists.
    private func reload() {
        installed = packages.installed()
        if installed?.routeId == entry.id { route = installed?.route }
        ledger = ledgerStore.load(routeId: entry.id)
        if ledger?.redrawNoticePending == true {
            showRedrawNotice = true
            ledgerStore.clearRedrawNotice(routeId: entry.id)
        }
    }

    /// Fetches the route's stage list when nothing is downloaded, so the
    /// pilgrim can see what they are being offered before they take it.
    private func loadStagesIfNeeded(force: Bool = false) async {
        guard force || route == nil, !release.isEmpty else { return }
        isLoadingStages = true
        stagesFailure = nil
        do {
            route = try await PilgrimageCatalogService.shared.routePreview(entry: entry, release: release)
        } catch {
            stagesFailure = (error as? PilgrimageError) ?? .catalogUnreachable
        }
        isLoadingStages = false
    }
}
```

- [ ] **Step 6: Open the third door**

In `Pilgrim/Scenes/Honor/HonorWaysSheet.swift`, add beside `showOwnWalks` (line 13):

```swift
    @State private var showPilgrimages = false
```

Add a section directly after the "Your own walks" section (line 43):

```swift
                Section {
                    Button { showPilgrimages = true } label: {
                        settingNavRow(label: "Walk a pilgrimage")
                    }
                } header: {
                    Text("A pilgrimage").font(Constants.Typography.caption)
                } footer: {
                    Text("A route from the open-pilgrimages dataset, walked one stage at a time.")
                        .font(Constants.Typography.caption)
                }
```

And a nested sheet beside the `OwnWalkPicker` one (after line 89):

```swift
            .sheet(isPresented: $showPilgrimages) {
                // Same handoff as the own-walk picker: choosing dismisses the
                // parent sheet, which takes this nested one with it.
                PilgrimageCatalogView(onChoose: onChoose)
            }
```

- [ ] **Step 7: Tell the package manager what a live walk is**

In `Pilgrim/Scenes/Root/MainCoordinatorView.swift`, at the top of `chooseWay()`. `MainCoordinator` is not actor-isolated and `PilgrimagePackageManager` is `@MainActor`, so the assignment hops exactly the way `retryMedia(for:)` already does:

```swift
    func chooseWay() {
        // Downloading a second route, Replace, Update, and Remove are all
        // refused while a walk is on; this is where the manager learns what
        // "on" means.
        Task { @MainActor in
            PilgrimagePackageManager.shared.isWalkActive = { [weak self] in self?.activeWalkViewModel != nil }
        }
        honorImportState = .idle
```

- [ ] **Step 8: Register, build, run the tests**

```bash
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Scenes/Honor/PilgrimageCatalogView.swift
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Scenes/Honor/PilgrimageRouteView.swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/PilgrimageCatalogServiceTests -only-testing:UnitTests/PilgrimageCatalogModelTests 2>&1 | grep -E "error:|Executed"
```
Expected: `** BUILD SUCCEEDED **`, then `Executed 14 tests, with 0 failures` for the service suite and `Executed 9 tests, with 0 failures` for the model suite.

- [ ] **Step 9: Lint and commit**

```bash
swiftlint --quiet | grep -E "error|Pilgrimage" || echo "clean"
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(honor): a pilgrimage is the third way to choose a way

The catalog lists what the dataset says is walkable; the route screen
shows the stages before you download them, offers the next one, marks
what you have walked, and downloads once. A route the build marked sparse
says "few places marked yet" rather than promising more than it holds.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: A stage walks without a companion, a soft tap, or a date

**Files:**
- Modify: `Pilgrim/Models/Honor/Way.swift` (add `isPilgrimageStage`)
- Modify: `Pilgrim/Scenes/Honor/WayMomentHeader.swift` (add `WayStageLine`)
- Modify: `Pilgrim/Scenes/ActiveWalk/ActiveWalkViewModel+Honor.swift` (`HonorArrivalCard`, `startHonorEngineIfNeeded`, `companionCoordinate`, `recordHonorArrival`)
- Modify: `Pilgrim/Scenes/ActiveWalk/WayPlaceCard.swift:334-355` (`HonorArrivalCardView`)
- Modify: `Pilgrim/Scenes/Honor/HonorOverviewView.swift:174-176`
- Modify: `Pilgrim/Scenes/Honor/HonorWaysSheet.swift:109-114`
- Modify: `Pilgrim/Scenes/Honor/WayMomentPreview.swift:48-57`
- Modify: `Pilgrim/Scenes/Settings/WaysListView.swift:61-68`
- Modify: `Pilgrim/Scenes/WalkSummary/HonorSummarySection.swift`, `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift:742-754`
- Test: `UnitTests/Honor/PilgrimageStageWalkTests.swift` (extend)

**Interfaces:**
- Consumes: `WayStage`, `PilgrimageLedger`, `PilgrimageLedgerStore`, `HonorStageOutcome`.
- Produces:
  - `Way.isPilgrimageStage: Bool`
  - `enum WayStageLine { static func line(for way: Way) -> String?; static func line(for stage: WayStage) -> String }`
  - `HonorArrivalCard` gains `let stageName: String?` and `let distanceWalkedMeters: Double`.
  - `HonorSummaryData` gains `let isPilgrimageStage: Bool` and `let stageProgressLine: String?`; `HonorSummaryModel.summaryData(for:way:link:replies:ledger:)`.
  - `HonorSummarySection.kicker(for:) -> String` — the block's opening line, which must not say "their steps" on a stage.

- [ ] **Step 1: Write the failing tests**

Append to `UnitTests/Honor/PilgrimageStageWalkTests.swift`:

```swift
extension PilgrimageStageWalkTests {

    func testTheStageLineStandsWhereADateWould() {
        let way = stageWay()
        XCTAssertEqual(WayStageLine.line(for: way),
                       "stage 1 of 33 · \(StatsHelper.string(for: 24_200, unit: UnitLength.meters, type: .distance)) · hard")
        var notAStage = way
        notAStage.stage = nil
        XCTAssertNil(WayStageLine.line(for: notAStage), "a shared walk still shows its date")
        XCTAssertTrue(way.isPilgrimageStage)
        XCTAssertFalse(notAStage.isPilgrimageStage)
    }

    func testAStageWalksWithNoCompanionAndNoSoftTap() {
        UserPreferences.honorSoftTapEnabled.value = true
        addTeardownBlock { UserPreferences.honorSoftTapEnabled.delete() }
        let vm = ActiveWalkViewModel(mode: .honor, way: stageWay())
        vm.builder.setStatus(.ready)
        vm.startRecording()
        XCTAssertNotNil(vm.honorEngine)
        XCTAssertNil(vm.companionCoordinate, "the stage's own voice walks with you, not a dot")

        // 400 m off the line for well past the soft-tap window: still silent.
        let far = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0.0036, longitude: 0.002694),
                             altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: start)
        for _ in 0..<5 { vm.honorEngine?.processLocation(far) }
        XCTAssertNil(vm.softTapCaption)
    }

    func testAnOwnWalkWayKeepsItsCompanion() {
        var way = stageWay()
        way.stage = nil
        let vm = ActiveWalkViewModel(mode: .honor, way: way)
        vm.builder.setStatus(.ready)
        vm.startRecording()
        vm.honorEngine?.processLocation(
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                       altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: start))
        XCTAssertNotNil(vm.companionCoordinate)
    }

    func testTheArrivalCardForAStageNamesTheStageAndCarriesNoDelta() {
        let card = HonorArrivalCard(wayTitle: "Saint-Jean-Pied-de-Port to Roncesvalles",
                                    voicesHeard: 0, placesPassed: 3, theirSeconds: 0, yourSeconds: 0,
                                    stageName: "Saint-Jean-Pied-de-Port to Roncesvalles",
                                    distanceWalkedMeters: 24_200)
        XCTAssertEqual(HonorArrivalCardView.title(for: card), "you walked the stage")
        XCTAssertTrue(HonorArrivalCardView.line(for: card).contains("3 places passed"))
        XCTAssertTrue(HonorArrivalCardView.line(for: card)
            .contains(StatsHelper.string(for: 24_200, unit: UnitLength.meters, type: .distance)))

        let sharedWalk = HonorArrivalCard(wayTitle: "Rúa do Franco → Obradoiro", voicesHeard: 2,
                                          placesPassed: 1, theirSeconds: 600, yourSeconds: 540,
                                          stageName: nil, distanceWalkedMeters: 900)
        XCTAssertEqual(HonorArrivalCardView.title(for: sharedWalk), "you walked their way")
    }

    func testTheSummaryForAStageReadsKilometresAndNoCompanionDelta() {
        var led = PilgrimageLedger(routeId: "camino-frances")
        led.record(stageIndex: 0, name: "Saint-Jean-Pied-de-Port to Roncesvalles", distanceKm: 24.2,
                   outcome: HonorStageOutcome(progressFrac: 0.58, arrived: false), at: start)
        let walk = WalkDataFactory.makeWalk(
            uuid: UUID(), startDate: start, endDate: start.addingTimeInterval(3600),
            workoutEvents: [TempWalkEvent(uuid: nil, eventType: .honorMode, timestamp: start)])
        let data = HonorSummaryModel.summaryData(
            for: walk, way: stageWay(),
            link: WayLink(wayId: "pilgrimage:camino-frances:0", theirSeconds: 600, yourSeconds: 540),
            replies: [:], ledger: led)
        XCTAssertNil(data?.arrivedBeforeTheirsSeconds, "a stage has no companion to arrive before")
        let line = try? XCTUnwrap(data?.stageProgressLine)
        XCTAssertEqual(line?.hasSuffix("of the stage"), true, line ?? "nil")
        XCTAssertTrue(line?.contains(StatsHelper.string(for: 24.2 * 0.58 * 1000, unit: UnitLength.meters, type: .distance)) ?? false, line ?? "nil")
    }

    /// The summary block opens with a kicker that says "in their steps".
    /// A stage has no "their", and the flag is carried explicitly rather than
    /// inferred from the progress line — a walk that earned no ledger entry
    /// is still a stage walk.
    func testTheSummaryKickerDropsTheirStepsForAStage() throws {
        let walk = WalkDataFactory.makeWalk(
            uuid: UUID(), startDate: start, endDate: start.addingTimeInterval(3600),
            workoutEvents: [TempWalkEvent(uuid: nil, eventType: .honorMode, timestamp: start)])

        let stageData = try XCTUnwrap(HonorSummaryModel.summaryData(
            for: walk, way: stageWay(), link: nil, replies: [:], ledger: nil))
        XCTAssertTrue(stageData.isPilgrimageStage)
        XCTAssertNil(stageData.stageProgressLine, "no ledger entry, but still a stage")
        XCTAssertEqual(HonorSummarySection.kicker(for: stageData), "the stage you walked")

        var notAStage = stageWay()
        notAStage.stage = nil
        let shared = try XCTUnwrap(HonorSummaryModel.summaryData(
            for: walk, way: notAStage, link: nil, replies: [:], ledger: nil))
        XCTAssertFalse(shared.isPilgrimageStage)
        XCTAssertEqual(HonorSummarySection.kicker(for: shared), "in their steps")

        let removed = try XCTUnwrap(HonorSummaryModel.summaryData(
            for: walk, way: nil, link: nil, replies: [:], ledger: nil))
        XCTAssertFalse(removed.isPilgrimageStage, "a Way that is gone says nothing about stages")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/PilgrimageStageWalkTests 2>&1 | grep -E "error:|Executed"
```
Expected: `cannot find 'WayStageLine' in scope`.

- [ ] **Step 3: Add `isPilgrimageStage` and the stage line**

In `Pilgrim/Models/Honor/Way.swift`, inside `struct Way`, beneath `photoCount`:

```swift
    /// A Way that came from a downloaded route. Honor speaks differently
    /// about one: no other walker, so no companion, no soft tap, no date.
    var isPilgrimageStage: Bool { stage != nil }
```

In `Pilgrim/Scenes/Honor/WayMomentHeader.swift`, beneath `enum WayDistance`:

```swift
/// "stage 1 of 33 · 24 km · hard" — what stands where a shared walk shows
/// the day it was walked. A stage's own date is the build's timestamp and
/// means nothing to the walker.
enum WayStageLine {

    static func line(for way: Way) -> String? {
        way.stage.map(line(for:))
    }

    static func line(for stage: WayStage) -> String {
        var parts = ["stage \(stage.index + 1) of \(stage.count)",
                     StatsHelper.string(for: stage.distanceKm * 1000, unit: UnitLength.meters, type: .distance)]
        if !stage.difficulty.isEmpty { parts.append(stage.difficulty) }
        return parts.joined(separator: " · ")
    }
}
```

- [ ] **Step 4: Suppress the companion and the soft tap**

In `Pilgrim/Scenes/ActiveWalk/ActiveWalkViewModel+Honor.swift`:

Extend `HonorArrivalCard`:

```swift
struct HonorArrivalCard: Equatable {
    let wayTitle: String
    let voicesHeard: Int
    let placesPassed: Int
    /// The engine's numbers on the companion's timeline; persisted into the
    /// index link at save time so the summary can read them back. Both are
    /// zero for a stage, which has no companion.
    let theirSeconds: Double
    let yourSeconds: Double
    /// Set only for a pilgrimage stage; the card then speaks of the stage
    /// rather than of another walker.
    let stageName: String?
    let distanceWalkedMeters: Double
}
```

In `startHonorEngineIfNeeded`, replace the engine construction:

```swift
        let engine = HonorEngine(
            way: way,
            // A stage has no other walker to be off the way *from*; the soft
            // tap and the companion dot are both about someone else.
            softTapEnabled: UserPreferences.honorSoftTapEnabled.value && !way.isPilgrimageStage,
            voicesEnabled: UserPreferences.honorVoicesEnabled.value && UserPreferences.soundsEnabled.value
        )
```

Replace `companionCoordinate`:

```swift
    /// Where the companion is now: a binary search over the route on the
    /// engine's published frac, cheap enough for the map's per-frame read.
    /// The map itself throttles the dot to one move every two seconds.
    /// A stage has no companion — its clock is synthesized so the engine
    /// works unchanged, and nothing draws it.
    var companionCoordinate: CLLocationCoordinate2D? {
        guard way?.isPilgrimageStage != true else { return nil }
        return honorEngine.map { $0.geometry.coordinate(atFrac: $0.companionFrac) }
    }
```

Replace the tail of `recordHonorArrival`:

```swift
        honorArrival = HonorArrivalCard(
            wayTitle: way.title, voicesHeard: heardVoiceIDs.count,
            placesPassed: reachedMomentIDs.count,
            theirSeconds: theirSeconds, yourSeconds: yourSeconds,
            stageName: way.stage?.name,
            distanceWalkedMeters: honorEngine?.distanceWalkedMeters ?? 0)
```

- [ ] **Step 5: Let the arrival card speak of the stage**

In `Pilgrim/Scenes/ActiveWalk/WayPlaceCard.swift`, replace `HonorArrivalCardView` whole:

```swift
struct HonorArrivalCardView: View {
    let card: HonorArrivalCard
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            Text(Self.title(for: card)).font(Constants.Typography.heading).foregroundColor(.ink)
            Text(card.stageName ?? card.wayTitle).font(Constants.Typography.body).foregroundColor(.fog)
            Text(Self.line(for: card)).font(Constants.Typography.caption).foregroundColor(.fog)
            Button("continue", action: onDismiss).font(Constants.Typography.button).foregroundColor(.stone)
        }
        .padding(Constants.UI.Padding.normal)
        .background(RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.normal).fill(Color.parchmentSecondary))
    }

    static func title(for card: HonorArrivalCard) -> String {
        card.stageName == nil ? "you walked their way" : "you walked the stage"
    }

    /// A stage counts places and kilometres; a shared walk counts voices and
    /// places, because a voice is what the other walker left.
    static func line(for card: HonorArrivalCard) -> String {
        var parts: [String] = []
        if card.stageName == nil, card.voicesHeard > 0 {
            parts.append(card.voicesHeard == 1 ? "one voice heard" : "\(card.voicesHeard) voices heard")
        }
        if card.placesPassed > 0 {
            parts.append(card.placesPassed == 1 ? "one place passed" : "\(card.placesPassed) places passed")
        }
        if card.stageName != nil {
            parts.append(StatsHelper.string(for: card.distanceWalkedMeters, unit: UnitLength.meters, type: .distance))
        }
        if parts.isEmpty { return card.stageName == nil ? "the whole way, in their steps" : "the whole stage" }
        return parts.joined(separator: " · ")
    }
}
```

- [ ] **Step 6: Put the stage line where the date was**

`HonorOverviewView.card` (line 174-176) — replace the date `Text` with:

```swift
            Text(WayStageLine.line(for: way)
                 ?? DateFormatter.localizedString(from: way.departedAt, dateStyle: .long, timeStyle: .short))
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
```

And, in the same card, wrap the voice toggle (line 197-204) so it never
offers to walk with a voice a stage does not have:

```swift
            // A stage carries no recordings, so "walk with their voice" would
            // be a switch over nothing — and would say "their" besides.
            if !way.isPilgrimageStage {
                Toggle(isOn: $voicesEnabled) {
                    Text("walk with their voice")
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)
                }
                .tint(.stone)
                .onChange(of: voicesEnabled) { _, on in UserPreferences.honorVoicesEnabled.value = on }
                .disabled(way.voiceCount == 0)
            }
```

`HonorWaysSheet.wayRow` (line 109-114) — replace the date `Text`:

```swift
            HStack {
                Text(WayStageLine.line(for: way)
                     ?? DateFormatter.localizedString(from: way.departedAt, dateStyle: .medium, timeStyle: .none))
                Text("·")
                Text(withMedia.contains(way.id) || way.voiceCount + way.photoCount == 0
                     ? HonorOverviewModel.countsLine(way: way) : "voices returned to the trail")
            }
```

`WaysListView.detail(for:)` — replace its first line:

```swift
    private func detail(for way: Way) -> String {
        let lead = WayStageLine.line(for: way)
            ?? DateFormatter.localizedString(from: way.departedAt, dateStyle: .medium, timeStyle: .none)
        if way.voiceCount + way.photoCount > 0, !WayStore.shared.hasMedia(id: way.id) {
            return "\(lead) · voices returned to the trail"
        }
        let mb = String(format: "%.1f MB", Double(WayStore.shared.diskUsage(id: way.id)) / 1_000_000)
        return "\(lead) · \(mb)"
    }
```

`WayMomentPreview.alongTheWay` — drop the clock for a stage:

```swift
    /// "1.2 km along their way · 8:41 AM · Rúa do Franco": the moment's place
    /// on the line, the hour it happened in the walk's own time zone, and the
    /// street the sharer's page names when it has one. A stage keeps the
    /// distance and drops the hour: its clock is synthesized by the build.
    private static func alongTheWay(way: Way, moment: WayMoment) -> String {
        let distance = StatsHelper.string(for: moment.frac * way.totalDistanceMeters, unit: UnitLength.meters, type: .distance)
        var parts: [String] = []
        if way.isPilgrimageStage {
            parts.append("\(distance) along the stage")
        } else {
            let elapsed = WayGeometry(route: way.route).elapsed(atFrac: moment.frac)
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.timeZone = way.tzIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
            parts.append("\(distance) along their way")
            parts.append(formatter.string(from: way.departedAt.addingTimeInterval(elapsed)))
        }
        if let place = moment.place, !place.isEmpty { parts.append(place) }
        return parts.joined(separator: " · ")
    }
```

- [ ] **Step 7: The summary of a stage counts kilometres, not a delta**

In `Pilgrim/Scenes/WalkSummary/HonorSummarySection.swift`, extend the data and the model:

```swift
struct HonorSummaryData: Equatable {
    let wayTitle: String
    /// Positive when the honoring walker arrived before the companion. Nil
    /// for a stage: there is no companion to arrive before.
    let arrivedBeforeTheirsSeconds: Double?
    /// Every voice the Way carries, not the subset this walk played — the
    /// arrival card's `voicesHeard` is the one that counts what was heard.
    let voicesAlongTheWay: Int
    let repliesMade: Int
    /// Carried explicitly, never inferred from `stageProgressLine`: a stage
    /// walk that earned no ledger entry (the walker never joined the line) is
    /// still a stage walk, and must not be told it walked in someone's steps.
    let isPilgrimageStage: Bool
    /// "14 of 24 km of the stage", from the ledger this walk just wrote.
    let stageProgressLine: String?
}

enum HonorSummaryModel {
    static func summaryData(for walk: WalkInterface, way: Way?, link: WayLink?,
                            replies: [Int: String], ledger: PilgrimageLedger?) -> HonorSummaryData? {
        let types = walk.workoutEvents.map(\.eventType)
        guard types.contains(.honorMode) else { return nil }
        let stage = way?.stage
        // The dot walked the companion's timeline; the summary reads the
        // numbers the engine recorded at arrival, never a recomputation.
        var delta: Double?
        if stage == nil, let theirs = link?.theirSeconds, let yours = link?.yourSeconds { delta = theirs - yours }
        return HonorSummaryData(
            wayTitle: way?.title ?? "a way that has been removed",
            arrivedBeforeTheirsSeconds: delta,
            voicesAlongTheWay: way?.voiceCount ?? 0,
            repliesMade: replies.count,
            isPilgrimageStage: stage != nil,
            stageProgressLine: stage.flatMap { stageProgressLine(stage: $0, ledger: ledger) })
    }

    /// The kilometres the ledger recorded for this stage, against the stage's
    /// own length. Silent when the walk earned no entry.
    static func stageProgressLine(stage: WayStage, ledger: PilgrimageLedger?) -> String? {
        guard let entry = ledger?.stages[String(stage.index)] else { return nil }
        let walked = StatsHelper.string(for: entry.kmWalked * 1000, unit: UnitLength.meters, type: .distance)
        let whole = StatsHelper.string(for: stage.distanceKm * 1000, unit: UnitLength.meters, type: .distance)
        return "\(walked) of \(whole) of the stage"
    }
}
```

And in `HonorSummarySection`, replace the block's unconditional opening
`Text("in their steps")` with the kicker, and insert the progress line under
the title:

```swift
            Text(Self.kicker(for: data)).font(Constants.Typography.caption).foregroundColor(.fog)
            Text(data.wayTitle).font(Constants.Typography.heading).foregroundColor(.ink)
            if let stageProgressLine = data.stageProgressLine {
                Text(stageProgressLine).font(Constants.Typography.caption).foregroundColor(.fog)
            }
```

with, beside `countsLine`:

```swift
    /// The block's opening line. Honor's copy assumes another walker; a
    /// downloaded stage has none, so it names what was actually walked —
    /// the same split `HonorArrivalCardView.title(for:)` makes.
    static func kicker(for data: HonorSummaryData) -> String {
        data.isPilgrimageStage ? "the stage you walked" : "in their steps"
    }
```

In `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift`, `computeHonorState(for:)` — pass the ledger:

```swift
        let replies = link.map { WayStore.shared.replies(for: $0.wayId) } ?? [:]
        let ledger = way?.stage.flatMap { PilgrimageLedgerStore().load(routeId: $0.routeId) }
        guard let data = HonorSummaryModel.summaryData(
            for: walk, way: way, link: link, replies: replies, ledger: ledger
        ) else { return nil }
```

- [ ] **Step 8: Run the tests and build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/PilgrimageStageWalkTests -only-testing:UnitTests/ActiveWalkHonorTests -only-testing:UnitTests/HonorJournalTests 2>&1 | grep -E "error:|Executed"
```
Expected: `Executed 11 tests, with 0 failures` for the stage suite and no regression in the other two. Any other caller of `HonorArrivalCard(...)` or `HonorSummaryModel.summaryData(...)` fails to compile and names itself; add the new arguments there.

- [ ] **Step 9: Commit**

```bash
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(honor): a stage walks with its own voice, not a companion's

No dot, no soft tap, no arrival delta, no voice toggle, and neither the
summary's kicker nor the date line says "their".

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: What a card can carry — text, a local name, and a sitting

**Files:**
- Modify: `Pilgrim/Scenes/Honor/WayMomentHeader.swift` (local-name selection, stage subline)
- Modify: `Pilgrim/Scenes/ActiveWalk/WayPlaceCard.swift:122-125` (the waypoint body)
- Modify: `Pilgrim/Scenes/Honor/WayMomentPreview.swift:71-73`
- Modify: `Pilgrim/Views/PilgrimMapView+HonorWay.swift:120-135` (`wayPins` draws at `pin`)
- Test: `UnitTests/Honor/PilgrimageStageWalkTests.swift` (extend)

**Interfaces:**
- Produces: `WayMomentHeader.localName(for moment: WayMoment) -> String?` with the fixed order `eu, gl, es, fr, ja, pt, it, de`; `WayMomentHeader.placeCopy(for moment: WayMoment, isStage: Bool) -> String` (`"A place on the way."` / `"A place they marked."` / the moment's own `text`).

- [ ] **Step 1: Write the failing tests**

Append to `UnitTests/Honor/PilgrimageStageWalkTests.swift`:

```swift
extension PilgrimageStageWalkTests {

    private func waypoint(names: [String: String]?, label: String = "Vierge d'Orisson",
                          text: String? = nil, sitMinutes: Int? = nil) -> WayMoment {
        var moment = WayMoment(id: "wp-x", frac: 0.3, at: WayCoordinate(lat: 0, lon: 0),
                               kind: .waypoint(label: label, icon: "building.columns"))
        moment.names = names
        moment.text = text
        moment.sitMinutes = sitMinutes
        return moment
    }

    func testTheLocalNameFollowsAFixedOrderAndNeverEchoesTheLabel() {
        XCTAssertEqual(WayMomentHeader.localName(for: waypoint(names: ["es": "Virgen de Orisson",
                                                                      "eu": "Orissongo Ama Birjina",
                                                                      "fr": "Vierge d'Orisson"])),
                       "Orissongo Ama Birjina", "eu comes first")
        XCTAssertEqual(WayMomentHeader.localName(for: waypoint(names: ["es": "Virgen de Orisson",
                                                                      "fr": "Vierge d'Orisson"])),
                       "Virgen de Orisson", "the French name is the label; es is next in order")
        XCTAssertNil(WayMomentHeader.localName(for: waypoint(names: ["fr": "Vierge d'Orisson"])),
                     "the only local name is the label itself")
        XCTAssertNil(WayMomentHeader.localName(for: waypoint(names: nil)))
        XCTAssertNil(WayMomentHeader.localName(for: waypoint(names: ["ru": "Орисон"])),
                     "a language outside the order is not shown")
    }

    func testThePlaceCopyChangesForAStage() {
        XCTAssertEqual(WayMomentHeader.placeCopy(for: waypoint(names: nil), isStage: true),
                       "A place on the way.")
        XCTAssertEqual(WayMomentHeader.placeCopy(for: waypoint(names: nil), isStage: false),
                       "A place they marked.")
        XCTAssertEqual(WayMomentHeader.placeCopy(for: waypoint(names: nil, text: "A shepherd carried this Madonna."),
                                                 isStage: true),
                       "A shepherd carried this Madonna.")
    }

    func testAPinDrawsAtItsOwnCoordinateWhileTheTriggerStaysOnTheLine() {
        let way = stageWay()
        let pins = PilgrimMapView.wayPins(for: way, heardVoiceIDs: [])
        let pin = try? XCTUnwrap(pins.first { $0.kind.wayMomentID == "wp-orisson" })
        XCTAssertEqual(pin?.coordinate.latitude ?? 0, 0.0002, accuracy: 1e-9, "drawn at `pin`")
        XCTAssertEqual(way.moments[0].at?.lat, 0, "triggered on the line")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/PilgrimageStageWalkTests 2>&1 | grep -E "error:|Executed"
```
Expected: `type 'WayMomentHeader' has no member 'localName'`.

- [ ] **Step 3: Add the local name and the place copy**

In `Pilgrim/Scenes/Honor/WayMomentHeader.swift`, inside `struct WayMomentHeader`, beneath `relation(distanceMeters:place:)`:

```swift
    /// The languages a place's own name is worth showing in, in the order
    /// the routes run: Basque and Galician before Spanish on the caminos,
    /// Japanese for Shikoku. A name equal to the label says nothing twice.
    static let localNameOrder = ["eu", "gl", "es", "fr", "ja", "pt", "it", "de"]

    static func localName(for moment: WayMoment) -> String? {
        guard let names = moment.names else { return nil }
        let label = kicker(for: moment)
        for code in localNameOrder {
            guard let name = names[code], !name.isEmpty, name != label else { continue }
            return name
        }
        return nil
    }

    /// A card body for a place: the dataset's own words when it has them,
    /// otherwise the shortest true thing. A stage has no "they".
    static func placeCopy(for moment: WayMoment, isStage: Bool) -> String {
        if let text = moment.text, !text.isEmpty { return text }
        return isStage ? "A place on the way." : "A place they marked."
    }
```

And render the local name inside the header, under the kicker (after the `Text(Self.kicker(for: moment))` line inside the `VStack`):

```swift
                if let localName = Self.localName(for: moment) {
                    Text(localName)
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
```

- [ ] **Step 4: Let the walk card carry the text and the sitting**

In `Pilgrim/Scenes/ActiveWalk/WayPlaceCard.swift`, the `WayPlaceCard` struct gains one input beside `moment` (add after `let moment: WayMoment`):

```swift
    /// True when the Way came from a downloaded route: the copy then never
    /// says "they".
    var isStage = false
```

Replace the `.waypoint` branch of `body(for:)`:

```swift
        case .waypoint:
            VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
                Text(WayMomentHeader.placeCopy(for: moment, isStage: isStage))
                    .font(Constants.Typography.caption).foregroundColor(.fog)
                if let minutes = moment.sitMinutes, minutes > 0 {
                    sitRow(minutes: minutes)
                }
            }
```

Extract the sitting row so both branches share it and the struct stays small (add beneath `body(for:)`):

```swift
    /// The same offer a sitting card makes, wired to the same `onSit`.
    private func sitRow(minutes: Int) -> some View {
        HStack(spacing: Constants.UI.Padding.normal) {
            Button { onTouch(); onSit(minutes) } label: {
                Text("Sit?").font(Constants.Typography.button).foregroundColor(.parchment)
                    .padding(.horizontal, Constants.UI.Padding.big).padding(.vertical, Constants.UI.Padding.small)
                    .background(Color.stone).cornerRadius(Constants.UI.CornerRadius.normal)
            }
            .accessibilityLabel("Sit here for \(minutes) minutes")
            Text("your soundscape holds while you sit")
                .font(Constants.Typography.caption).foregroundColor(.fog)
        }
    }
```

and replace the `.meditation` branch's inline `HStack` with `sitRow(minutes: minutes)`.

In `Pilgrim/Scenes/ActiveWalk/ActiveWalkView+Honor.swift`, pass the flag where `WayPlaceCard` is built (immediately after `moment: moment,`):

```swift
                    moment: moment,
                    isStage: viewModel.way?.isPilgrimageStage == true,
```

- [ ] **Step 5: The preview says the same thing**

In `Pilgrim/Scenes/Honor/WayMomentPreview.swift`, replace the `.waypoint` branch of `content`:

```swift
        case .waypoint:
            VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
                Text(WayMomentHeader.placeCopy(for: moment, isStage: way.isPilgrimageStage))
                    .font(Constants.Typography.body).foregroundColor(.ink)
                if let minutes = moment.sitMinutes, minutes > 0 {
                    Text("When you walk it, the way will offer you \(minutes) minutes of sitting here.")
                        .font(Constants.Typography.caption).foregroundColor(.fog)
                } else {
                    Text("When you walk it, it rises as a card as you reach it.")
                        .font(Constants.Typography.caption).foregroundColor(.fog)
                }
            }
```

- [ ] **Step 6: Draw pins where the place actually stands**

In `Pilgrim/Views/PilgrimMapView+HonorWay.swift`, replace the coordinate line inside `wayPins(for:heardVoiceIDs:)`:

```swift
        return way.moments.map { moment in
            // `pin` is the place itself; `at` is its projection onto the
            // line, which is where the engine's 60 m trigger fires. The pin
            // must stand where the place does.
            let coordinate = (moment.pin ?? moment.at).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                ?? geometry.coordinate(atFrac: moment.frac)
```

- [ ] **Step 7: Run the tests and build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/PilgrimageStageWalkTests -only-testing:UnitTests/HonorWayRenderingTests 2>&1 | grep -E "error:|Executed"
```
Expected: `** BUILD SUCCEEDED **`, then `Executed 14 tests, with 0 failures` for the stage suite, no regression in `HonorWayRenderingTests`.

- [ ] **Step 8: Commit**

```bash
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(honor): a place card carries the dataset's words and its own name

Local names in the languages the routes run through, the sitting the
dataset suggests, and a pin that stands where the place does.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Marks on the map

**Files:**
- Create: `Pilgrim/Models/Honor/WayMarkPins.swift`
- Modify: `Pilgrim/Models/Walk/MapManagement/PilgrimAnnotation.swift:9-47`
- Modify: `Pilgrim/Views/PilgrimMapView.swift:432-435` (`buildCircles`), `:546-551` (`buildPoints`)
- Modify: `Pilgrim/Views/PilgrimMapView+HonorWay.swift:296-314` (`wayAnnotationPoint`)
- Modify: `Pilgrim/Models/Honor/HonorTuning.swift`
- Modify: `Pilgrim/Scenes/ActiveWalk/ActiveWalkViewModel.swift` (`honorMarkPins`), `ActiveWalkViewModel+Honor.swift`, `ActiveWalkView+Map.swift:26`
- Modify: `Pilgrim/Scenes/Honor/HonorOverviewView.swift`
- Test: `UnitTests/Honor/WayMarkPinsTests.swift`

**Interfaces:**
- Consumes: `WayMark`, `WayMarkKind`, `PilgrimAnnotation`, `MapGlyph.wayMark`, `HonorTuning`.
- Produces:
  - `PilgrimAnnotation.Kind.wayMark(id: String, kind: WayMarkKind)` — never returns a `wayMomentID`, never tappable.
  - `enum WayMarkPins { static let drawFromZoom: CGFloat = 13; static let maxPerScreen = 40; static func symbol(for kind: WayMarkKind) -> String; static func pins(marks: [WayMark], zoom: CGFloat, near: CLLocationCoordinate2D?) -> [PilgrimAnnotation] }`
  - `HonorTuning.markPinRefreshMeters = 200.0`
  - `ActiveWalkViewModel.honorMarkPins: [PilgrimAnnotation]`

- [ ] **Step 1: Write the failing tests**

`UnitTests/Honor/WayMarkPinsTests.swift`:

```swift
import XCTest
import CoreLocation
@testable import Pilgrim

final class WayMarkPinsTests: XCTestCase {

    /// `count` water marks strung east along the equator, 100 m apart.
    private func marks(_ count: Int) -> [WayMark] {
        (0..<count).map { index in
            WayMark(id: "m\(index)", kind: .water, name: "f\(index)",
                    at: WayCoordinate(lat: 0, lon: Double(index) * 0.000898),
                    frac: Double(index) / Double(max(count - 1, 1)), offLineMeters: 10)
        }
    }

    func testEveryKindHasItsOwnGlyph() {
        XCTAssertEqual(WayMarkPins.symbol(for: .water), "drop.fill")
        XCTAssertEqual(WayMarkPins.symbol(for: .food), "fork.knife")
        XCTAssertEqual(WayMarkPins.symbol(for: .bed), "bed.double.fill")
        XCTAssertEqual(WayMarkPins.symbol(for: .transport), "bus.fill")
        XCTAssertEqual(WayMarkPins.symbol(for: .supply), "bag.fill")
        XCTAssertEqual(WayMarkPins.symbol(for: .medical), "cross.case.fill")
    }

    func testNothingIsDrawnBelowZoomThirteen() {
        XCTAssertTrue(WayMarkPins.pins(marks: marks(5), zoom: 12.9, near: nil).isEmpty)
        XCTAssertEqual(WayMarkPins.pins(marks: marks(5), zoom: 13, near: nil).count, 5)
    }

    func testTheScreenNeverCarriesMoreThanFortyNearestFirst() {
        let all = marks(200)
        // Standing at the 150th mark: the forty nearest run 130 to 169.
        let here = CLLocationCoordinate2D(latitude: 0, longitude: 150 * 0.000898)
        let pins = WayMarkPins.pins(marks: all, zoom: 15, near: here)
        XCTAssertEqual(pins.count, WayMarkPins.maxPerScreen)
        let ids = Set(pins.compactMap { pin -> String? in
            if case .wayMark(let id, _) = pin.kind { return id }
            return nil
        })
        XCTAssertTrue(ids.contains("m150"))
        XCTAssertTrue(ids.contains("m131"))
        XCTAssertTrue(ids.contains("m169"))
        XCTAssertFalse(ids.contains("m0"))
        XCTAssertFalse(ids.contains("m199"))
    }

    func testWithoutAFixTheFirstFortyAlongTheStageAreDrawn() {
        let pins = WayMarkPins.pins(marks: marks(100), zoom: 15, near: nil)
        XCTAssertEqual(pins.count, 40)
        guard case .wayMark(let first, _) = pins[0].kind else { return XCTFail("kind") }
        XCTAssertEqual(first, "m0")
    }

    func testAMarkIsNeverAMomentAndNeverTappable() {
        let pin = PilgrimAnnotation(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                                    kind: .wayMark(id: "m1", kind: .water))
        XCTAssertNil(pin.kind.wayMomentID, "a mark has no card to open")
    }

    func testMarkPinsSitBeforeMomentPinsSoTheyDrawUnderneath() {
        // The walk map composes `marks + moments`; a mark must never cover a
        // moment's pin. Pinned here so the order in ActiveWalkView+Map holds.
        let marks = WayMarkPins.pins(marks: marks(2), zoom: 15, near: nil)
        let moment = PilgrimAnnotation(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                                       kind: .wayWaypoint(id: "wp-1", label: "x", icon: "mappin"))
        let composed = marks + [moment]
        XCTAssertNil(composed.first?.kind.wayMomentID)
        XCTAssertEqual(composed.last?.kind.wayMomentID, "wp-1")
    }
}
```

- [ ] **Step 2: Register and run to verify it fails**

```bash
ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/WayMarkPinsTests.swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/WayMarkPinsTests 2>&1 | grep -E "error:|Executed"
```
Expected: `cannot find 'WayMarkPins' in scope`.

- [ ] **Step 3: Add the annotation kind**

In `Pilgrim/Models/Walk/MapManagement/PilgrimAnnotation.swift`, add to `Kind` after `wayWaypoint`:

```swift
        /// A service point on a pilgrimage stage. Drawn under the moment
        /// pins, never tappable, hidden when the map is zoomed out.
        case wayMark(id: String, kind: WayMarkKind)
```

`wayMomentID` is unchanged: `.wayMark` falls to its `default` and returns nil, which is what keeps marks out of `handleMapTap` and out of the card queue.

- [ ] **Step 4: Create `WayMarkPins.swift`**

```swift
import CoreLocation
import Foundation

/// Which service points a screen may carry, and what each one looks like.
/// Pure: the map and the walk both ask it, and a spec can too.
enum WayMarkPins {

    /// Below this a whole stage's services read as a rash rather than a map.
    static let drawFromZoom: CGFloat = 13
    /// Inside a town a stage can carry over a hundred at zoom 13.
    static let maxPerScreen = 40

    static func symbol(for kind: WayMarkKind) -> String {
        switch kind {
        case .water: return "drop.fill"
        case .food: return "fork.knife"
        case .bed: return "bed.double.fill"
        case .transport: return "bus.fill"
        case .supply: return "bag.fill"
        case .medical: return "cross.case.fill"
        }
    }

    /// The marks worth drawing right now: nothing when zoomed out, otherwise
    /// the nearest `maxPerScreen` to the walker. Without a fix the stage's
    /// own order stands in, so the overview still shows the first stretch.
    static func pins(marks: [WayMark], zoom: CGFloat, near: CLLocationCoordinate2D?) -> [PilgrimAnnotation] {
        guard zoom >= drawFromZoom, !marks.isEmpty else { return [] }
        let chosen: [WayMark]
        if let near {
            let here = CLLocation(latitude: near.latitude, longitude: near.longitude)
            chosen = marks
                .map { (mark: $0, meters: here.distance(from: CLLocation(latitude: $0.at.lat, longitude: $0.at.lon))) }
                // A tiebreak on id keeps the selection stable between fixes.
                .sorted { $0.meters == $1.meters ? $0.mark.id < $1.mark.id : $0.meters < $1.meters }
                .prefix(maxPerScreen)
                .map(\.mark)
        } else {
            chosen = Array(marks.prefix(maxPerScreen))
        }
        return chosen.map {
            PilgrimAnnotation(coordinate: CLLocationCoordinate2D(latitude: $0.at.lat, longitude: $0.at.lon),
                              kind: .wayMark(id: $0.id, kind: $0.kind))
        }
    }
}
```

- [ ] **Step 5: Render them**

In `Pilgrim/Views/PilgrimMapView.swift`, extend the two exhaustive switches.

`buildCircles`, line 432:

```swift
            case .wayVoice, .wayPhoto, .wayRest, .waySit, .wayWaypoint, .wayMark:
                // Way moments and marks render as faded PointAnnotations in
                // `buildPoints` (via MapGlyph.wayMark) — no filled circle
                // underneath.
                continue
```

`buildPoints`, line 546:

```swift
            case .wayVoice, .wayPhoto, .wayRest, .waySit, .wayWaypoint, .wayMark:
                // Branching on the specific way* kind, and the shared
                // wayPoint() builder, both live in PilgrimMapView+HonorWay.swift
                // — keeps this switch (and SwiftLint's cyclomatic-complexity
                // count for it) from growing with every new moment kind.
                points.append(wayAnnotationPoint(for: pin, coordinator: coordinator))
```

In `Pilgrim/Views/PilgrimMapView+HonorWay.swift`, add a case to `wayAnnotationPoint` before `default:`, and give marks their own smaller disc:

```swift
        case .wayMark(_, let kind):
            return wayPoint(pin, symbol: WayMarkPins.symbol(for: kind), tint: .stone,
                            coordinator: coordinator, size: 18)
```

and widen `wayPoint` with a size:

```swift
    /// Faded pin for a Way moment or a service mark, sharing `buildPoints`'
    /// image-caching pattern. Marks draw smaller: they are the map's
    /// background, not its subject.
    private static func wayPoint(_ pin: PilgrimAnnotation, symbol: String, tint: UIColor,
                                 coordinator: Coordinator, size: CGFloat = 22) -> PointAnnotation {
        var point = PointAnnotation(coordinate: pin.coordinate)
        let glyph = MapGlyph.wayMark(symbol: symbol, tint: tint)
        if let image = MapGlyphImageBuilder.image(for: glyph, size: size) {
            point.image = .init(image: image, name: "\(MapGlyphImageBuilder.cacheKey(for: glyph))-\(Int(size))")
        }
        point.iconSize = 1.0
        return point
    }
```

- [ ] **Step 6: Feed them to the walk map**

In `Pilgrim/Models/Honor/HonorTuning.swift`, add:

```swift
    /// How far the walker moves before the nearest-forty mark selection is
    /// recomputed. A resort of every mark on the stage is not a per-fix job.
    static let markPinRefreshMeters = 200.0
```

In `Pilgrim/Scenes/ActiveWalk/ActiveWalkViewModel.swift`, beside `honorPins` (line 131):

```swift
    /// The stage's service pins, memoized like `honorPins` and re-selected
    /// only when the walker has moved (see `refreshMarkPinsIfWalkerMoved`).
    @Published var honorMarkPins: [PilgrimAnnotation] = []
    var markPinAnchor: CLLocationCoordinate2D?
```

In `Pilgrim/Scenes/ActiveWalk/ActiveWalkViewModel+Honor.swift`, inside `startHonorEngineIfNeeded`, right before `refreshHonorPins()`:

```swift
        // The nearest-forty selection follows the walker, but a resort of
        // every mark on the stage is not a per-fix job — 200 m at a time.
        $currentLocation
            .compactMap { $0 }
            .sink { [weak self] sample in
                self?.refreshMarkPinsIfWalkerMoved(
                    to: CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude))
            }
            .store(in: &honorCancellables)
        markPinAnchor = nil
```

and beneath `refreshHonorPins()`:

```swift
    /// The walk map is fixed at zoom 16, so a stage's marks always draw
    /// there; only which forty changes.
    func refreshMarkPinsIfWalkerMoved(to coordinate: CLLocationCoordinate2D) {
        guard let marks = way?.marks, !marks.isEmpty else { return }
        if let anchor = markPinAnchor {
            let moved = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            guard moved >= HonorTuning.markPinRefreshMeters else { return }
        }
        markPinAnchor = coordinate
        honorMarkPins = WayMarkPins.pins(marks: marks, zoom: 16, near: coordinate)
    }
```

and in `teardownHonor()`, beside the other honor state resets:

```swift
        honorMarkPins.removeAll()
        markPinAnchor = nil
```

In `Pilgrim/Scenes/ActiveWalk/ActiveWalkView+Map.swift`, line 26 — marks first so they draw under the moments:

```swift
            pinAnnotations: waypointPins + viewModel.proximityPins + viewModel.honorMarkPins + viewModel.honorPins,
```

- [ ] **Step 7: And to the overview**

In `Pilgrim/Scenes/Honor/HonorOverviewView.swift`, add state and wire it:

```swift
    @State private var markPins: [PilgrimAnnotation] = []
```

Pass them under the moment pins in the map's `pinAnnotations`:

```swift
                pinAnnotations: markPins + (rendering?.pins ?? []),
```

Recompute on the Way and on every zoom change — the selection is cheap and the zoom gate is the whole point:

```swift
        .task(id: way.id) {
            rendering = WayRendering(
                pins: PilgrimMapView.wayPins(for: way, heardVoiceIDs: []),
                bounds: HonorOverviewModel.bounds(of: way),
                state: HonorWayState(way: way)
            )
            markPins = WayMarkPins.pins(marks: way.marks ?? [], zoom: cameraZoom, near: cameraCenter)
        }
        .onChange(of: cameraZoom) { _, zoom in
            markPins = WayMarkPins.pins(marks: way.marks ?? [], zoom: zoom, near: cameraCenter)
        }
```

- [ ] **Step 8: Run the tests and build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/WayMarkPinsTests -only-testing:UnitTests/HonorWayRenderingTests -only-testing:UnitTests/MapGlyphImageBuilderTests 2>&1 | grep -E "error:|Executed"
```
Expected: `** BUILD SUCCEEDED **`, then `Executed 6 tests, with 0 failures` for `WayMarkPinsTests` and no regression in the two rendering suites.

- [ ] **Step 9: Commit**

```bash
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(honor): the stage's services sit on the map as quiet pins

Drawn under the moment pins, never tappable, hidden below zoom 13, and
capped at the forty nearest so a town does not read as a rash.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Water ahead

**Files:**
- Modify: `Pilgrim/Models/Honor/HonorTuning.swift`
- Modify: `Pilgrim/Models/Honor/HonorMomentTracker.swift`
- Modify: `Pilgrim/Models/Honor/HonorEngine.swift:7-15`, `:140-153`, `:303-313`
- Modify: `Pilgrim/Models/Haptics/HapticManager.swift:85-98`, `:200-219`, and the Core Haptics helpers
- Modify: `Pilgrim/Scenes/ActiveWalk/ActiveWalkViewModel+Honor.swift` (`handleHonorEvent`, caption)
- Test: `UnitTests/Honor/HonorMomentTrackerTests.swift` (extend), `UnitTests/Honor/PilgrimageStageWalkTests.swift` (extend)

**Interfaces:**
- Produces:
  - `HonorTuning.markAheadMeters = 300.0`, `HonorTuning.markQuietSeconds: TimeInterval = 3600`
  - `HonorMomentTracker.Action.markAhead(WayMark, meters: Double)`
  - `HonorMomentTracker.init(moments:marks:geometry:voicesEnabled:)` with `marks: [WayMark] = []`
  - `HonorMomentTracker.update(location:progressFrac:gates:isStationary:activeSeconds:isOnWay:)` with `activeSeconds: TimeInterval = 0, isOnWay: Bool = true`
  - `HonorEngineEvent.markAhead(mark: WayMark, meters: Double)`
  - `HapticPattern.honorWaterAhead`
  - `ActiveWalkViewModel.showMarkCaption(mark:meters:)`

- [ ] **Step 1: Write the failing tracker tests**

Append to `UnitTests/Honor/HonorMomentTrackerTests.swift`:

```swift
extension HonorMomentTrackerTests {

    private func water(_ id: String, frac: Double, offLine: Double = 10) -> WayMark {
        WayMark(id: id, kind: .water, name: "Fuente \(id)",
                at: WayCoordinate(lat: 0, lon: frac * 1000 / 111_320), frac: frac, offLineMeters: offLine)
    }

    private func markTracker(_ marks: [WayMark]) -> HonorMomentTracker {
        HonorMomentTracker(moments: [], marks: marks, geometry: geometry, voicesEnabled: false)
    }

    private func markAhead(_ actions: [HonorMomentTracker.Action]) -> [String] {
        actions.compactMap { if case .markAhead(let mark, _) = $0 { return mark.id } else { return nil } }
    }

    func testWaterFiresOnceInsideThreeHundredMetresBeforeIt() {
        var t = markTracker([water("a", frac: 0.5)])
        // 400 m short: too early.
        XCTAssertEqual(markAhead(t.update(location: coord(100), progressFrac: 0.1, gates: .init(),
                                          isStationary: false, activeSeconds: 0, isOnWay: true)), [])
        // 250 m short: the caption.
        let hit = t.update(location: coord(250), progressFrac: 0.25, gates: .init(),
                           isStationary: false, activeSeconds: 60, isOnWay: true)
        XCTAssertEqual(markAhead(hit), ["a"])
        guard case .markAhead(_, let meters) = hit.first else { return XCTFail("action") }
        XCTAssertEqual(meters, 250, accuracy: 5)
        // And never again.
        XCTAssertEqual(markAhead(t.update(location: coord(300), progressFrac: 0.3, gates: .init(),
                                          isStationary: false, activeSeconds: 120, isOnWay: true)), [])
    }

    func testWaterNeverFiresOnceItIsBehindYou() {
        var t = markTracker([water("a", frac: 0.5)])
        XCTAssertEqual(markAhead(t.update(location: coord(600), progressFrac: 0.6, gates: .init(),
                                          isStationary: false, activeSeconds: 0, isOnWay: true)), [],
                       "a fountain you have already passed is not news")
    }

    func testAFountainOffTheTrailIsADetourNotADrink() {
        var t = markTracker([water("far", frac: 0.5, offLine: 250)])
        XCTAssertEqual(markAhead(t.update(location: coord(250), progressFrac: 0.25, gates: .init(),
                                          isStationary: false, activeSeconds: 0, isOnWay: true)), [])
    }

    func testOffWayWalkersGetNothing() {
        var t = markTracker([water("a", frac: 0.5)])
        XCTAssertEqual(markAhead(t.update(location: coord(250), progressFrac: 0.25, gates: .init(),
                                          isStationary: false, activeSeconds: 0, isOnWay: false)), [])
    }

    func testTheFirstIsFreeThenOnePerHourOfWalking() {
        var t = markTracker([water("a", frac: 0.3), water("b", frac: 0.5), water("c", frac: 0.9)])
        XCTAssertEqual(markAhead(t.update(location: coord(100), progressFrac: 0.1, gates: .init(),
                                          isStationary: false, activeSeconds: 0, isOnWay: true)), ["a"])
        // b is 200 m ahead, 20 minutes later: inside the quiet hour.
        XCTAssertEqual(markAhead(t.update(location: coord(300), progressFrac: 0.3, gates: .init(),
                                          isStationary: false, activeSeconds: 1200, isOnWay: true)), [],
                       "a skipped mark stays a silent pin")
        // c is 200 m ahead, an hour and a half in.
        XCTAssertEqual(markAhead(t.update(location: coord(700), progressFrac: 0.7, gates: .init(),
                                          isStationary: false, activeSeconds: 5400, isOnWay: true)), ["c"])
    }

    func testOnlyWaterSpeaks() {
        let bed = WayMark(id: "bed", kind: .bed, name: "Albergue",
                          at: WayCoordinate(lat: 0, lon: 500 / 111_320), frac: 0.5, offLineMeters: 10)
        var t = markTracker([bed])
        XCTAssertEqual(markAhead(t.update(location: coord(250), progressFrac: 0.25, gates: .init(),
                                          isStationary: false, activeSeconds: 0, isOnWay: true)), [])
    }
}
```

- [ ] **Step 2: Write the failing view-model test**

Append to `UnitTests/Honor/PilgrimageStageWalkTests.swift`:

```swift
extension PilgrimageStageWalkTests {

    func testWaterAheadBorrowsTheCaptionLineAndNothingElse() {
        let mark = WayMark(id: "wp-fuente", kind: .water, name: "Fuente de Roldán",
                           at: WayCoordinate(lat: 0, lon: 500 / 111_320), frac: 0.5, offLineMeters: 12)
        var senses = HonorSenses()
        senses.isAppActive = { false }
        let vm = ActiveWalkViewModel(mode: .honor, way: stageWay(marks: [mark]), honorSenses: senses)
        vm.builder.setStatus(.ready)
        vm.startRecording()

        vm.handleHonorEvent(.markAhead(mark: mark, meters: 280))

        XCTAssertEqual(vm.softTapCaption, "water in \(WayDistance.string(meters: 280))")
        XCTAssertTrue(vm.honorCards.isEmpty, "a mark is never a card")
    }
}
```

- [ ] **Step 3: Run to verify both fail**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/HonorMomentTrackerTests -only-testing:UnitTests/PilgrimageStageWalkTests 2>&1 | grep -E "error:|Executed"
```
Expected: `extra argument 'marks' in call` and `type 'HonorEngineEvent' has no member 'markAhead'`.

- [ ] **Step 4: Add the tuning**

In `Pilgrim/Models/Honor/HonorTuning.swift`:

```swift
    /// How far before an on-way water source the caption rises.
    static let markAheadMeters = 300.0
    /// The Camino Francés carries a median of eight on-way sources per stage
    /// and 23 on its wettest day; without this the caption would be the
    /// day's loudest voice.
    static let markQuietSeconds: TimeInterval = 3600
```

- [ ] **Step 5: Teach the tracker to watch the water**

In `Pilgrim/Models/Honor/HonorMomentTracker.swift`:

Add to `Action`:

```swift
        /// A water source `meters` ahead on the line.
        case markAhead(WayMark, meters: Double)
```

Add stored state beside `reached`:

```swift
    private let marks: [WayMark]
    private var firedMarks: Set<String> = []
    /// Active seconds at the last water caption; nil means the first is free.
    private var lastMarkSeconds: TimeInterval?
```

Widen the initializer (defaults keep every existing call site compiling):

```swift
    init(moments: [WayMoment], marks: [WayMark] = [], geometry: WayGeometry, voicesEnabled: Bool) {
        // A tiebreak on id keeps ordering deterministic when two moments
        // share a frac — the same rule `WayImporter` sorts by.
        self.moments = moments.sorted { $0.frac == $1.frac ? $0.id < $1.id : $0.frac < $1.frac }
        // Only on-way water speaks: a fountain 250 m off the trail is a
        // detour, not a drink. Filtering once here keeps the per-fix scan to
        // the handful that could ever fire.
        self.marks = marks
            .filter { $0.kind == .water && $0.offLineMeters <= HonorTuning.onWayMeters }
            .sorted { $0.frac < $1.frac }
        self.geometry = geometry
        self.voicesEnabled = voicesEnabled
    }
```

Widen `update` and call the watcher:

```swift
    mutating func update(
        location: CLLocationCoordinate2D,
        progressFrac: Double,
        gates: Gates,
        isStationary: Bool,
        activeSeconds: TimeInterval = 0,
        isOnWay: Bool = true
    ) -> [Action] {
        var actions: [Action] = []
```

and, immediately before `actions += startNextIfPossible(gates: gates)`:

```swift
        actions += waterAhead(progressFrac: progressFrac, activeSeconds: activeSeconds, isOnWay: isOnWay)
```

Add the watcher beneath `startNextIfPossible`:

```swift
    /// The nearest unfired water source the walker is about to reach. Never
    /// one already behind them, never off the way, and at most one an hour
    /// of walking — the marks skipped inside the quiet hour stay silent pins.
    private mutating func waterAhead(progressFrac: Double, activeSeconds: TimeInterval, isOnWay: Bool) -> [Action] {
        guard isOnWay, !marks.isEmpty, geometry.totalMeters > 0 else { return [] }
        if let last = lastMarkSeconds, activeSeconds - last < HonorTuning.markQuietSeconds { return [] }
        for mark in marks where !firedMarks.contains(mark.id) {
            let ahead = (mark.frac - progressFrac) * geometry.totalMeters
            guard ahead >= 0 else { continue }
            guard ahead <= HonorTuning.markAheadMeters else { break }
            firedMarks.insert(mark.id)
            lastMarkSeconds = activeSeconds
            return [.markAhead(mark, meters: ahead)]
        }
        return []
    }
```

- [ ] **Step 6: Let the engine carry it**

In `Pilgrim/Models/Honor/HonorEngine.swift`, add to `HonorEngineEvent`:

```swift
    case markAhead(mark: WayMark, meters: Double)
```

Build the tracker with the Way's marks (in `init`):

```swift
        self.moments = HonorMomentTracker(moments: way.moments, marks: way.marks ?? [],
                                          geometry: geometry, voicesEnabled: voicesEnabled)
```

Pass the two new inputs from `processLocation`'s last line:

```swift
        let stationary = location.speed >= 0 && location.speed < HonorTuning.stationarySpeed
        emit(moments.update(location: coordinate, progressFrac: progressFrac, gates: gates,
                            isStationary: stationary, activeSeconds: activeDuration, isOnWay: isOnWay))
```

And forward the action in `emit`:

```swift
            case .markAhead(let mark, let meters): subject.send(.markAhead(mark: mark, meters: meters))
```

- [ ] **Step 7: A single soft tap for water**

In `Pilgrim/Models/Haptics/HapticManager.swift`, add the case to `HapticPattern` after `honorArrival`:

```swift
    case honorWaterAhead
```

Route it in `fire()`:

```swift
        case .honorOffWay, .honorArrival, .honorWaterAhead:
            fireHonor()
```

Add to `fireHonor()`:

```swift
        case .honorWaterAhead:
            // One tap at the whisper's intensity: a notice, not an alert.
            if !Self.playHonorWaterAhead() {
                let generator = UIImpactFeedbackGenerator(style: .soft)
                generator.prepare()
                generator.impactOccurred()
            }
```

And the Core Haptics helper beside `playWhisperProximity()`:

```swift
    /// `playWhisperProximity`'s single event: same softness and roundness,
    /// once instead of three times.
    private static func playHonorWaterAhead() -> Bool {
        let soft = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4)
        let round = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
        return HapticEngineHost.shared.play(
            [CHHapticEvent(eventType: .hapticTransient, parameters: [soft, round], relativeTime: 0)])
    }
```

- [ ] **Step 8: Put the notice on the caption line**

In `Pilgrim/Scenes/ActiveWalk/ActiveWalkViewModel+Honor.swift`, add a case to `handleHonorEvent`:

```swift
        case .markAhead(let mark, let meters):
            showMarkCaption(mark: mark, meters: meters)
            fireHonorHaptic(.honorWaterAhead)
```

and, beside `showSoftTapCaption`:

```swift
    /// The water notice borrows the soft tap's slot — nothing new in the
    /// stats sheet — and retires itself the same way, generation-guarded so
    /// teardown makes this write a no-op.
    func showMarkCaption(mark: WayMark, meters: Double) {
        softTapCaption = "water in \(WayDistance.string(meters: max(0, meters.isFinite ? meters : 0)))"
        let generation = honorGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.softTapCaptionSeconds) { [weak self] in
            guard let self, self.honorGeneration == generation else { return }
            self.softTapCaption = nil
        }
    }
```

`softTapCaptionSeconds` is `private static` on the extension; change it to `static let softTapCaptionSeconds: TimeInterval = 20` so both captions read it.

- [ ] **Step 9: Run the tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/HonorMomentTrackerTests -only-testing:UnitTests/PilgrimageStageWalkTests -only-testing:UnitTests/HonorEngineTests 2>&1 | grep -E "error:|Executed"
```
Expected: no failures in any of the three suites; `HonorMomentTrackerTests` grows by 6 and `PilgrimageStageWalkTests` by 1.

- [ ] **Step 10: Commit**

```bash
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(honor): water announces itself, at most once an hour

On-way sources only, 300 m before, one soft tap and one line on the
caption slot the soft tap already borrows. Nothing new in the stats sheet.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: The morning card

**Files:**
- Create: `Pilgrim/Scenes/Honor/StageMorningCard.swift`
- Modify: `Pilgrim/Scenes/Honor/HonorOverviewView.swift` (Begin presents it)
- Modify: `Pilgrim/Scenes/ActiveWalk/WalkOptionsSheet.swift` (a "the day" row)
- Modify: `Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift:17`, `:223-290`
- Test: `UnitTests/Honor/PilgrimageStageWalkTests.swift` (extend)

**Interfaces:**
- Consumes: `WayStage`, `WayStageFacts.line(distanceKm:gainMeters:hours:difficulty:)` (Task 8), `WeatherSnapshot`, `WeatherService.shared.fetchCurrent(for:)`, `StatsHelper`, `UserPreferences.distanceMeasurementType`.
- Produces:
  - `enum StageMorningCardModel { static func factsLine(for stage: WayStage) -> String; static func weatherLine(_ snapshot: WeatherSnapshot?) -> String? }` — `factsLine` is a one-line call through to `WayStageFacts`, kept as a named entry point so the card reads at its own level.
  - `struct StageMorningCard: View` — `init(stage: WayStage, weather: WeatherSnapshot?, buttonTitle: String, onAction: @escaping () -> Void)`

- [ ] **Step 1: Write the failing tests**

Append to `UnitTests/Honor/PilgrimageStageWalkTests.swift`:

```swift
extension PilgrimageStageWalkTests {

    func testTheFactsLineReadsInTheWalkersOwnUnit() throws {
        let stage = try XCTUnwrap(stageWay().stage)
        let line = StageMorningCardModel.factsLine(for: stage)
        XCTAssertEqual(line, [
            StatsHelper.string(for: 24_200, unit: UnitLength.meters, type: .distance),
            "\(StatsHelper.string(for: 1419, unit: UnitLength.meters, type: .altitude)) up",
            "7 to 9 hours",
            "hard"
        ].joined(separator: " · "))
    }

    func testTheWeatherLineIsSilentWithoutASnapshot() {
        XCTAssertNil(StageMorningCardModel.weatherLine(nil))
        let snapshot = WeatherSnapshot(condition: .clear, temperature: 9, humidity: 0.4, windSpeed: 1)
        let line = try? XCTUnwrap(StageMorningCardModel.weatherLine(snapshot))
        XCTAssertEqual(line?.hasPrefix("clear, "), true, line ?? "nil")
        XCTAssertEqual(line?.contains("9"), true, line ?? "nil")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/PilgrimageStageWalkTests 2>&1 | grep -E "error:|Executed"
```
Expected: `cannot find 'StageMorningCardModel' in scope`.

- [ ] **Step 3: Create `StageMorningCard.swift`**

```swift
import CoreLocation
import SwiftUI

enum StageMorningCardModel {

    /// "24 km · 1,400 m up · 7 to 9 hours · hard", in the walker's own unit —
    /// the same line the route screen's stage list shows, from the same
    /// formatter (`WayStageFacts`, Task 8). The two must not drift.
    static func factsLine(for stage: WayStage) -> String {
        WayStageFacts.line(distanceKm: stage.distanceKm, gainMeters: stage.gainMeters,
                           hours: stage.hours, difficulty: stage.difficulty)
    }

    /// "clear, 9°". Nothing at all when the fetch found nothing — a stage's
    /// words do not need weather to stand.
    static func weatherLine(_ snapshot: WeatherSnapshot?) -> String? {
        guard let snapshot else { return nil }
        let imperial = UserPreferences.distanceMeasurementType.safeValue == .miles
        return "\(snapshot.condition.label.lowercased()), \(snapshot.formattedTemperature(imperial: imperial))"
    }
}

/// The stage's own words before the walk, and again from the walk's overflow
/// as "the day". The copy is the dataset's, unedited.
struct StageMorningCard: View {

    let stage: WayStage
    let weather: WeatherSnapshot?
    /// "walk" before the walk; "close" once it has begun.
    let buttonTitle: String
    let onAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Constants.UI.Padding.normal) {
                    Text(stage.theme)
                        .font(Constants.Typography.displayMedium)
                        .foregroundColor(.ink)
                    Text(stage.narrative)
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)
                    Text(StageMorningCardModel.factsLine(for: stage))
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                    warnings
                    if let weatherLine = StageMorningCardModel.weatherLine(weather) {
                        Text(weatherLine)
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Constants.UI.Padding.normal)
            }
            Button(action: onAction) {
                Text(buttonTitle)
                    .font(Constants.Typography.button)
                    .foregroundColor(.parchment)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.stone)
                    .cornerRadius(Constants.UI.CornerRadius.normal)
            }
            .padding(Constants.UI.Padding.normal)
        }
        .background(Color.parchment)
    }

    /// Each warning its own short paragraph: two crowded onto one line is
    /// how a warning stops being read.
    @ViewBuilder
    private var warnings: some View {
        if !stage.warnings.isEmpty {
            VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
                ForEach(Array(stage.warnings.enumerated()), id: \.offset) { _, warning in
                    HStack(alignment: .top, spacing: Constants.UI.Padding.small) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(Constants.Typography.caption)
                            .foregroundColor(.rust)
                        Text(warning)
                            .font(Constants.Typography.caption)
                            .foregroundColor(.ink)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 4: Present it at Begin**

In `Pilgrim/Scenes/Honor/HonorOverviewView.swift`, add state:

```swift
    @State private var showMorningCard = false
    @State private var todayWeather: WeatherSnapshot?
```

Replace the Begin button's action so a stage reads its words first:

```swift
            Button {
                if way.isPilgrimageStage { showMorningCard = true } else { onBegin() }
            } label: {
                Text("Begin")
```

Fill the snapshot inside `fetchToday()` (it already fetches; keep both uses of the one call):

```swift
    private func fetchToday() async {
        guard let here = CLLocationManager().location,
              let snapshot = await WeatherService.shared.fetchCurrent(for: here) else { return }
        todayCondition = snapshot.condition.rawValue
        todayWeather = snapshot
    }
```

And present the sheet beside the existing `previewMoment` one:

```swift
        .sheet(isPresented: $showMorningCard) {
            if let stage = way.stage {
                StageMorningCard(stage: stage, weather: todayWeather, buttonTitle: "walk") {
                    showMorningCard = false
                    onBegin()
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
```

- [ ] **Step 5: Reopen it mid-walk as "the day"**

In `Pilgrim/Scenes/ActiveWalk/WalkOptionsSheet.swift`, add two inputs beside the seek ones:

```swift
    /// The stage being walked, when the Way came from a downloaded route.
    var stageDay: WayStage?
    var onOpenStageDay: (() -> Void)?
```

and a row inside the `ScrollView`'s `VStack`, directly after the intention row:

```swift
                    if stageDay != nil, let onOpenStageDay {
                        optionRow(icon: "sun.horizon", title: "the day", subtitle: stageDay?.theme) {
                            onOpenStageDay()
                        }
                    }
```

In `Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift`, add state beside `showOptions` (line 17):

```swift
    @State private var showStageDay = false
```

pass the two inputs into `WalkOptionsSheet(...)` (line 224):

```swift
                stageDay: viewModel.way?.stage,
                onOpenStageDay: {
                    showOptions = false
                    showStageDay = true
                },
```

and present the card, mid-walk reading "close" and doing nothing but dismissing:

```swift
        .sheet(isPresented: $showStageDay) {
            if let stage = viewModel.way?.stage {
                StageMorningCard(stage: stage, weather: viewModel.weatherSnapshot, buttonTitle: "close") {
                    showStageDay = false
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
```

- [ ] **Step 6: Register, build, run the tests**

```bash
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Scenes/Honor/StageMorningCard.swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/PilgrimageStageWalkTests 2>&1 | grep -E "error:|Executed"
```
Expected: `** BUILD SUCCEEDED **`, then `Executed 17 tests, with 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(honor): the stage's words open the day

Theme, narrative, the day's facts, each warning its own paragraph, and
today's weather when there is any. Reopenable mid-walk as "the day".

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

## Task 14: The arrival reflection and its reply

**Files:**
- Modify: `Pilgrim/Models/Honor/HonorPersistence.swift`
- Modify: `Pilgrim/Scenes/ActiveWalk/ActiveWalkViewModel+Honor.swift` (`originIndex(of:)`, `replyToStageReflection`, `stageReflectionReplyURL`)
- Modify: `Pilgrim/Scenes/ActiveWalk/WayPlaceCard.swift` (`HonorArrivalCardView`)
- Modify: `Pilgrim/Scenes/ActiveWalk/ActiveWalkView+Honor.swift` (`HonorCardHost`)
- Modify: `Pilgrim/Scenes/WalkSummary/HonorSummarySection.swift`, `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift`
- Test: `UnitTests/Honor/PilgrimageStageWalkTests.swift` (extend)

**Interfaces:**
- Produces:
  - `HonorPersistence.stageReflectionOrigin = -1`, `HonorPersistence.stageReflectionMomentID = "stage-reflection"`, `HonorPersistence.stageReflectionMoment(for stage: WayStage) -> WayMoment`
  - `ActiveWalkViewModel.originIndex(of:)` gains the `-1` branch (and loses `private` so it can be exercised).
  - `ActiveWalkViewModel.replyToStageReflection()`, `ActiveWalkViewModel.stageReflectionReplyURL() -> URL?`
  - `HonorArrivalCard` gains `var closing: String?` (a `var`, so it defaults in the memberwise init).
  - `HonorArrivalCardView` gains `onStopReply: (() -> Void)?`.
  - `HonorSummaryData` gains `let closing: String?` and `let replyRelativePath: String?`.

- [ ] **Step 1: Write the failing tests**

Append to `UnitTests/Honor/PilgrimageStageWalkTests.swift`:

```swift
extension PilgrimageStageWalkTests {

    func testTheReflectionIsFiledUnderTheReservedOrigin() throws {
        let stage = try XCTUnwrap(stageWay().stage)
        let moment = HonorPersistence.stageReflectionMoment(for: stage)
        XCTAssertEqual(moment.id, HonorPersistence.stageReflectionMomentID)
        XCTAssertEqual(ActiveWalkViewModel.originIndex(of: moment), HonorPersistence.stageReflectionOrigin)
        XCTAssertEqual(HonorPersistence.stageReflectionOrigin, -1)
        XCTAssertEqual(moment.at, stage.end.at, "the reply is recorded at the stage's end place")

        var voice = WayMoment(id: "voice-3", frac: 0.5, at: nil,
                              kind: .voice(endFrac: 0.6, duration: 10, kind: .spoken, media: .file("audio/3.m4a")))
        voice.place = nil
        XCTAssertEqual(ActiveWalkViewModel.originIndex(of: voice), 3, "voice replies are unchanged")
        XCTAssertNil(ActiveWalkViewModel.originIndex(of:
            WayMoment(id: "wp-orisson", frac: 0.3, at: nil, kind: .waypoint(label: "x", icon: "mappin"))))
    }

    func testAReplyToTheReflectionRoundTrips() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let store = WayStore(baseDirectory: dir)
        let way = stageWay()
        try store.save(way)
        var senses = HonorSenses()
        senses.store = { store }
        senses.isAppActive = { false }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recording = docs.appendingPathComponent("Recordings/stage-reply.m4a")
        try FileManager.default.createDirectory(at: recording.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try TestAudioFile.writeSilentAudioFile(to: recording)
        addTeardownBlock { try? FileManager.default.removeItem(at: recording) }

        let vm = ActiveWalkViewModel(mode: .honor, way: way, honorSenses: senses)
        XCTAssertNil(vm.stageReflectionReplyURL())
        try store.setReply(wayId: way.id, originN: HonorPersistence.stageReflectionOrigin,
                           relativePath: "Recordings/stage-reply.m4a")
        XCTAssertEqual(vm.stageReflectionReplyURL(), recording)
    }

    func testTheArrivalCardAppendsTheStagesClosingLine() {
        let card = HonorArrivalCard(wayTitle: "t", voicesHeard: 0, placesPassed: 2,
                                    theirSeconds: 0, yourSeconds: 0,
                                    stageName: "Saint-Jean-Pied-de-Port to Roncesvalles",
                                    distanceWalkedMeters: 24_200,
                                    closing: "You crossed a border on foot.")
        XCTAssertEqual(card.closing, "You crossed a border on foot.")
        XCTAssertEqual(HonorArrivalCardView.title(for: card), "you walked the stage")
    }

    func testTheSummaryCarriesTheClosingOnlyWhenArrivalFired() {
        let walk = WalkDataFactory.makeWalk(
            uuid: UUID(), startDate: start, endDate: start.addingTimeInterval(3600),
            workoutEvents: [TempWalkEvent(uuid: nil, eventType: .honorMode, timestamp: start)])
        let noArrival = HonorSummaryModel.summaryData(for: walk, way: stageWay(), link: nil,
                                                      replies: [:], ledger: nil)
        XCTAssertNil(noArrival?.closing, "the way was left before its end")

        let arrived = WalkDataFactory.makeWalk(
            uuid: UUID(), startDate: start, endDate: start.addingTimeInterval(3600),
            workoutEvents: [TempWalkEvent(uuid: nil, eventType: .honorMode, timestamp: start),
                            TempWalkEvent(uuid: nil, eventType: .honorArrival, timestamp: start)])
        let data = HonorSummaryModel.summaryData(
            for: arrived, way: stageWay(), link: nil,
            replies: [HonorPersistence.stageReflectionOrigin: "Recordings/stage-reply.m4a"], ledger: nil)
        XCTAssertEqual(data?.closing, "You crossed a border on foot.")
        XCTAssertEqual(data?.replyRelativePath, "Recordings/stage-reply.m4a")
        XCTAssertEqual(data?.repliesMade, 1)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/PilgrimageStageWalkTests 2>&1 | grep -E "error:|Executed"
```
Expected: `type 'HonorPersistence' has no member 'stageReflectionOrigin'`.

- [ ] **Step 3: Reserve the origin**

In `Pilgrim/Models/Honor/HonorPersistence.swift`, add inside the enum:

```swift
    /// Replies are keyed by the `n` in a `voice-n` id. A stage has no
    /// voices, so its arrival reflection is filed under a reserved index no
    /// `voice-n` can ever produce.
    static let stageReflectionOrigin = -1
    static let stageReflectionMomentID = "stage-reflection"

    /// The moment the reply path records against: not a moment of the Way,
    /// but the stage's end place wearing a moment's shape so `replyHere`,
    /// `originIndex(of:)`, and `existingReplyURL(for:)` all work unchanged.
    static func stageReflectionMoment(for stage: WayStage) -> WayMoment {
        WayMoment(id: stageReflectionMomentID, frac: 1, at: stage.end.at,
                  kind: .waypoint(label: stage.end.name, icon: arrivalWaypointIcon))
    }
```

- [ ] **Step 4: Teach the reply path the reserved origin**

In `Pilgrim/Scenes/ActiveWalk/ActiveWalkViewModel+Honor.swift`, replace `originIndex(of:)` (dropping `private` so a spec can exercise it):

```swift
    /// The `n` in the `voice-n` ids `OwnWalkWayBuilder` writes — the index a
    /// reply is filed under — or the reserved index the stage's arrival
    /// reflection uses. Nil for any other moment id.
    static func originIndex(of moment: WayMoment) -> Int? {
        if moment.id == HonorPersistence.stageReflectionMomentID { return HonorPersistence.stageReflectionOrigin }
        guard moment.id.hasPrefix(voiceIDPrefix) else { return nil }
        return Int(moment.id.dropFirst(voiceIDPrefix.count))
    }
```

and add beside `existingReplyURL(for:)`:

```swift
    /// Starts a reply to the stage's closing line, at the stage's end place.
    func replyToStageReflection() {
        guard let stage = way?.stage else { return }
        replyHere(to: HonorPersistence.stageReflectionMoment(for: stage))
    }

    /// The walker's reply to this stage's reflection, from this walk or an
    /// earlier one. Nil when the recording is gone.
    func stageReflectionReplyURL() -> URL? {
        guard let stage = way?.stage else { return nil }
        return existingReplyURL(for: HonorPersistence.stageReflectionMoment(for: stage))
    }
```

- [ ] **Step 5: Append the reflection to the arrival card**

Extend `HonorArrivalCard` (in the same file) with one more field, declared
as a **`var`** so it defaults at the call site:

```swift
    /// The stage's closing line, present only once arrival fired on a stage.
    /// Optional and last, like `WayMoment.place` and `.transcript`.
    var closing: String?
```

`HonorArrivalCard` uses the synthesized memberwise initializer, and only a
`var` optional gets a `nil` default there — a `let closing: String? = nil`
would be dropped from the initializer entirely and could never be set. As a
`var` it keeps Task 9's already-committed `HonorArrivalCard(...)`
constructions compiling untouched while `recordHonorArrival` below passes
`closing:` explicitly. No `= nil` on the declaration: SwiftLint's
`implicit_optional_initialization` forbids it.

and in `recordHonorArrival`, pass it:

```swift
            stageName: way.stage?.name,
            distanceWalkedMeters: honorEngine?.distanceWalkedMeters ?? 0,
            closing: way.stage?.closing)
```

In `Pilgrim/Scenes/ActiveWalk/WayPlaceCard.swift`, `HonorArrivalCardView` gains the closing and a reply pill — its inputs become:

```swift
struct HonorArrivalCardView: View {
    let card: HonorArrivalCard
    /// The stage's reply, when the walker has already recorded one.
    var existingReply: URL?
    var isRecordingReply = false
    var onReply: (() -> Void)?
    var onStopReply: (() -> Void)?
    var onPlayReply: ((URL) -> Void)?
    let onDismiss: () -> Void
```

and its body gains, between the counts line and "continue":

```swift
            if let closing = card.closing {
                Text(closing)
                    .font(Constants.Typography.displayMedium)
                    .foregroundColor(.ink)
                replyRow
            }
```

with

```swift
    /// The same reply a voice card offers, at the stage's end place — and,
    /// while it records, the same way to stop it. Without this the walker
    /// could start a recording the card gave them no way to end.
    @ViewBuilder
    private var replyRow: some View {
        HStack(spacing: Constants.UI.Padding.small) {
            if isRecordingReply {
                Text("recording your reply here").font(Constants.Typography.caption).foregroundColor(.ink)
                Spacer()
                if let onStopReply {
                    Button { onStopReply() } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(Constants.Typography.displayMedium)
                            .foregroundColor(.rust)
                    }
                    .accessibilityLabel("Stop recording your reply")
                }
            } else if let onReply {
                Button { onReply() } label: {
                    Label(existingReply == nil ? "reply here" : "record again", systemImage: "mic")
                        .font(Constants.Typography.caption).foregroundColor(.stone)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Record a reply to this stage")
            }
            if let existingReply, let onPlayReply {
                Spacer()
                Button { onPlayReply(existingReply) } label: {
                    Label("your reply", systemImage: "play.circle")
                        .font(Constants.Typography.caption).foregroundColor(.stone)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Play your reply")
            }
        }
    }
```

In `Pilgrim/Scenes/ActiveWalk/ActiveWalkView+Honor.swift`, wire the card up inside `HonorCardHost`:

```swift
            if let card = viewModel.honorArrival, !viewModel.honorArrivalCardDismissed {
                HonorArrivalCardView(
                    card: card,
                    existingReply: stageReply,
                    isRecordingReply: viewModel.isRecordingVoice
                        && viewModel.pendingReplyOrigin?.id == HonorPersistence.stageReflectionMomentID,
                    onReply: { viewModel.replyToStageReflection() },
                    // The same toggle `WayPlaceCard`'s voice body stops with.
                    onStopReply: { viewModel.toggleVoiceRecording() },
                    onPlayReply: { url in viewModel.playReply(url: url) },
                    onDismiss: { viewModel.honorArrivalCardDismissed = true })
                    .task(id: viewModel.completedRecordingCount) {
                        stageReply = viewModel.stageReflectionReplyURL()
                    }
            }
```

with one more piece of state on `HonorCardHost`:

```swift
    /// Resolved off the body, like `mediaURL`: the lookup is a disk read.
    @State private var stageReply: URL?
```

- [ ] **Step 6: And to the summary**

In `Pilgrim/Scenes/WalkSummary/HonorSummarySection.swift`, add two fields to `HonorSummaryData`:

```swift
    /// The stage's closing line, present only when arrival actually fired.
    let closing: String?
    /// The walker's reply to it, relative to Documents.
    let replyRelativePath: String?
```

and fill them in `summaryData`:

```swift
        let arrived = types.contains(.honorArrival)
        return HonorSummaryData(
            wayTitle: way?.title ?? "a way that has been removed",
            arrivedBeforeTheirsSeconds: delta,
            voicesAlongTheWay: way?.voiceCount ?? 0,
            repliesMade: replies.count,
            stageProgressLine: stage.flatMap { stageProgressLine(stage: $0, ledger: ledger) },
            closing: arrived ? stage?.closing : nil,
            replyRelativePath: replies[HonorPersistence.stageReflectionOrigin])
```

and render them at the end of `HonorSummarySection.body`'s `VStack`:

```swift
            if let closing = data.closing {
                Text(closing)
                    .font(Constants.Typography.displayMedium)
                    .foregroundColor(.ink)
                    .padding(.top, Constants.UI.Padding.xs)
            }
            if let replyRelativePath = data.replyRelativePath, let url = replyURL(replyRelativePath) {
                Button { player.toggle(url: url) } label: {
                    Label(player.isPlaying ? "pause" : "your reply",
                          systemImage: player.isPlaying ? "pause.circle" : "play.circle")
                        .font(Constants.Typography.caption).foregroundColor(.stone)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Play your reply to this stage")
            }
```

`AudioPlayerModel` has no singleton (`Pilgrim/Scenes/WalkSummary/AudioPlayerModel.swift`), so the section owns one exactly as `WayMomentPreview` does — declared on `HonorSummarySection` beside `data`:

```swift
    @StateObject private var player = AudioPlayerModel()
```

and stopped when the section leaves, so a reply never outlives the summary:

```swift
        .onDisappear { player.stop() }
```

with the resolver beneath `deltaLine(_:)`:

```swift
    /// A relative path from the Way's own replies file: contained under
    /// Documents before it is opened, the way `localMediaURL` does it.
    private func replyURL(_ relativePath: String) -> URL? {
        ActiveWalkViewModel.localMediaURL(for: .recording(relativePath: relativePath),
                                          wayId: "", store: WayStore.shared)
    }
```

- [ ] **Step 7: Run the tests and build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/PilgrimageStageWalkTests -only-testing:UnitTests/ActiveWalkHonorTests 2>&1 | grep -E "error:|Executed"
```
Expected: `** BUILD SUCCEEDED **`, then `Executed 21 tests, with 0 failures` for the stage suite and no regression in `ActiveWalkHonorTests`.

- [ ] **Step 8: Commit**

```bash
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(honor): the stage closes with its own line, and you may answer it

Filed under a reserved origin no voice-n can produce, so the reply round
trips the next time the stage is walked.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

## Task 15: Honor's language for a stage

**Files:**
- Modify: `Pilgrim/Models/Walk/WalkMode.swift`
- Modify: `Pilgrim/Models/Prompt/ActivityContext.swift:17-23`
- Modify: `Pilgrim/Models/Prompt/PromptAssembler.swift:170-177`
- Modify: `Pilgrim/Scenes/Prompts/PromptListView.swift:227-233`
- Modify: `Pilgrim/Scenes/Honor/HonorOverviewView.swift` (Begin's accessibility label)
- Test: `UnitTests/Honor/WalkModeTests.swift` (extend), `UnitTests/PracticeLexiconTests.swift` (extend)

**Interfaces:**
- Produces:
  - `WalkMode.subtitle(for way: Way?) -> String` — the instance `subtitle` is unchanged; this is the Way-aware form.
  - `HonorStoryContext` gains `let routeName: String?` and `let stageLabel: String?` (both defaulting to nil so every existing construction keeps compiling).
  - `PromptAssembler.practiceLexicon` names the route and stage instead of another walker.

- [ ] **Step 1: Write the failing tests**

Append to `UnitTests/Honor/WalkModeTests.swift`:

```swift
extension WalkModeTests {

    func testHonorSpeaksOfAStageWhenTheWayIsOne() {
        var way = Way(id: "pilgrimage:camino-frances:0",
                      source: .pilgrimage(routeId: "camino-frances", stageIndex: 0),
                      title: "s", departedAt: Date(), tzIdentifier: nil, expires: nil,
                      route: [WayPoint(lat: 0, lon: 0, alt: nil, t: 0),
                              WayPoint(lat: 0, lon: 0.001, alt: nil, t: 60)],
                      totalDistanceMeters: 111, theirActiveSeconds: 60, moments: [], weather: nil)
        XCTAssertEqual(WalkMode.honor.subtitle(for: way), "walk in their steps",
                       "not a stage until it carries a stage block")
        way.stage = WayStage(routeId: "camino-frances", index: 0, count: 33, name: "n", theme: "t",
                             narrative: "n", closing: "c", warnings: [], distanceKm: 24.2, gainMeters: 100,
                             hours: WayStageHours(min: 5, max: 7), difficulty: "hard",
                             start: WayStagePlace(name: "a", at: WayCoordinate(lat: 0, lon: 0)),
                             end: WayStagePlace(name: "b", at: WayCoordinate(lat: 0, lon: 0.001)))
        XCTAssertEqual(WalkMode.honor.subtitle(for: way), "walk the stage")
        XCTAssertEqual(WalkMode.honor.subtitle(for: nil), "walk in their steps")
        XCTAssertEqual(WalkMode.wander.subtitle(for: way), WalkMode.wander.subtitle,
                       "only Honor's copy assumes another walker")
    }
}
```

Append to `UnitTests/PracticeLexiconTests.swift`:

```swift
extension PracticeLexiconTests {

    private func honorContext(_ story: HonorStoryContext) -> ActivityContext {
        ActivityContext.make(startDate: Date(timeIntervalSince1970: 1_700_000_000),
                             mode: .honor, honorStory: story)
    }

    func testTheLexiconForAStageNamesTheRouteAndNotAnotherWalker() {
        let text = PromptAssembler.practiceLexicon(context: honorContext(
            HonorStoryContext(wayTitle: "Saint-Jean-Pied-de-Port to Roncesvalles", arrived: true,
                              routeName: "Camino de Santiago (Francés)", stageLabel: "stage 1 of 33")))
        XCTAssertTrue(text.contains("Camino de Santiago (Francés)"), text)
        XCTAssertTrue(text.contains("stage 1 of 33"), text)
        XCTAssertFalse(text.contains("another walker"), text)
        XCTAssertFalse(text.contains("their voices"), text)
        XCTAssertTrue(text.contains("The end of the stage was reached."), text)
    }

    func testTheLexiconForASharedWalkIsUnchanged() {
        let text = PromptAssembler.practiceLexicon(context: honorContext(
            HonorStoryContext(wayTitle: "Rúa do Franco → Obradoiro", arrived: false)))
        XCTAssertTrue(text.contains("a Way another walker laid down"), text)
        XCTAssertTrue(text.contains("Rúa do Franco → Obradoiro"), text)
        XCTAssertTrue(text.contains("The Way was left before its end"), text)
    }
}
```

- [ ] **Step 2: Run to verify both fail**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/WalkModeTests -only-testing:UnitTests/PracticeLexiconTests 2>&1 | grep -E "error:|Executed"
```
Expected: `value of type 'WalkMode' has no member 'subtitle(for:)'` and `extra arguments at positions #3, #4 in call`.

- [ ] **Step 3: Give `WalkMode` the Way-aware subtitle**

In `Pilgrim/Models/Walk/WalkMode.swift`, add beneath `subtitle`:

```swift
    /// Honor's copy assumes another walker. A downloaded stage has none, so
    /// the mode says what is actually happening instead.
    func subtitle(for way: Way?) -> String {
        guard self == .honor, way?.isPilgrimageStage == true else { return subtitle }
        return "walk the stage"
    }
```

In `Pilgrim/Scenes/Honor/HonorOverviewView.swift`, use it on Begin:

```swift
            .accessibilityLabel(WalkMode.honor.subtitle(for: way))
```

(replacing `.accessibilityLabel("Begin honoring this way")`).

- [ ] **Step 4: Let the story carry the route and the stage**

In `Pilgrim/Models/Prompt/ActivityContext.swift`:

```swift
/// What this honor held: whose Way was followed, and whether its end was
/// reached. The title is nil until a caller that can reach the Way store
/// fills it — the event stream alone does not carry it. `routeName` and
/// `stageLabel` are set only for a pilgrimage stage, where there is no other
/// walker for the lexicon to speak of.
struct HonorStoryContext {
    let wayTitle: String?
    let arrived: Bool
    var routeName: String?
    var stageLabel: String?

    init(wayTitle: String?, arrived: Bool, routeName: String? = nil, stageLabel: String? = nil) {
        self.wayTitle = wayTitle
        self.arrived = arrived
        self.routeName = routeName
        self.stageLabel = stageLabel
    }
}
```

- [ ] **Step 5: Split the lexicon's honor branch**

In `Pilgrim/Models/Prompt/PromptAssembler.swift`, replace the `.honor` case of `practiceLexicon(context:)`:

```swift
        case .honor:
            guard let story = context.honorStory else {
                return "**About this practice:** This walk was an Honor. The walker followed a Way another walker laid down, hearing their voices where they were spoken. Two traveling together; the line was traced, not raced."
            }
            return story.routeName == nil ? sharedWalkLexicon(story) : stageLexicon(story)
        }
    }

    /// A stage has no other walker: the route itself is the company, and the
    /// lexicon must never put a voice where there is none.
    private static func stageLexicon(_ story: HonorStoryContext) -> String {
        var text = "**About this practice:** This walk was an Honor on a pilgrimage route. The walker followed one day's stage of a route walked for centuries, guided by the route's own places rather than by another walker's voice. The line was traced, not raced."
        if let route = story.routeName { text += " The route: \(route)." }
        if let stage = story.stageLabel { text += " The stage: \(stage)." }
        if let title = story.wayTitle { text += " Named: \(title)." }
        text += story.arrived
            ? " The end of the stage was reached."
            : " The stage was left before its end, which the practice honors too."
        return text
    }

    private static func sharedWalkLexicon(_ story: HonorStoryContext) -> String {
        var text = "**About this practice:** This walk was an Honor. The walker followed a Way another walker laid down, hearing their voices where they were spoken. Two traveling together; the line was traced, not raced."
        if let title = story.wayTitle { text += " The Way: \(title)." }
        text += story.arrived ? " The end of the Way was reached." : " The Way was left before its end, which the practice honors too."
        return text
    }
```

(The `case .wander` and `case .seek` branches above are untouched; the closing brace of the original `switch` and function is the one that now ends the `case .honor` block.)

- [ ] **Step 6: Fill them where the Way is reachable**

In `Pilgrim/Scenes/Prompts/PromptListView.swift`, replace the tail of `practice`:

```swift
        let way = WayStore.shared.way(forWalk: uuid)
        return (practice.mode, practice.seekStory,
                HonorStoryContext(wayTitle: way?.title, arrived: story.arrived,
                                  routeName: routeName(for: way),
                                  stageLabel: way?.stage.map { "stage \($0.index + 1) of \($0.count)" }))
    }

    /// The route's own name when its package is still on the phone, else the
    /// slug the stage carries — the journal must still name the route after
    /// the package has been removed.
    private func routeName(for way: Way?) -> String? {
        guard let stage = way?.stage else { return nil }
        return PilgrimagePackageManager.shared.installed().flatMap {
            $0.routeId == stage.routeId ? $0.route.name : nil
        } ?? stage.routeId
    }
```

- [ ] **Step 7: Run the tests and build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/WalkModeTests -only-testing:UnitTests/PracticeLexiconTests -only-testing:UnitTests/HonorJournalTests 2>&1 | grep -E "error:|Executed"
```
Expected: `** BUILD SUCCEEDED **` and no failures across the three suites.

- [ ] **Step 8: Grep for any remaining "they" on a stage surface**

```bash
grep -rn "they \|their \|A place they" Pilgrim/Scenes/Honor Pilgrim/Scenes/ActiveWalk/WayPlaceCard.swift Pilgrim/Scenes/WalkSummary/HonorSummarySection.swift
```
Expected hits, every one now unreachable for a stage:

| String | What gates it |
|---|---|
| `"A place they marked."` | `WayMomentHeader.placeCopy(for:isStage:)` (Task 10) |
| `"in their steps"` | `HonorSummarySection.kicker(for:)` (Task 9) |
| `"you walked their way"` | `HonorArrivalCardView.title(for:)` (Task 9) |
| `"walk with their voice"` | `if !way.isPilgrimageStage` around the toggle (Task 9) |
| `"along their way"` | the `else` branch of `WayMomentPreview.alongTheWay` (Task 9) |
| `"they walked this in"` | `HonorOverviewModel.weatherLine(theirs:today:)`, which returns nil without `way.weather` — a stage's is always nil (spec 1.2) |
| `"they rested here"`, `"what they saw here"`, `"spoken here"`, `"they sat here"` | `WayMomentHeader.kicker(for:)`'s voice/photo/rest/meditation cases — a stage carries `waypoint` moments only (spec 1.3) |

Anything the grep turns up that is **not** in this table is reachable on a stage surface and must be fixed here, not left for the device pass.

- [ ] **Step 9: Commit**

```bash
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(honor): a stage is walked, not followed

The mode, the lexicon, and the journal all stop saying "they" when the
Way came from a route rather than from another walker.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

## Task 16: Offline on the trail, and the device pass

**Files:**
- Create: `docs/honor-slice-two-device-pass.md`
- Modify: `Pilgrim/Models/Preferences/UserPreferences.swift`
- Modify: `Pilgrim/Scenes/Honor/HonorOverviewView.swift`
- Test: `UnitTests/Honor/PilgrimageStageWalkTests.swift` (extend)

**Interfaces:**
- Produces: `UserPreferences.pilgrimageOfflineNoteShown` (`UserPreference.Required<Bool>`, default `false`); `HonorOverviewModel.offlineNote(isStage:isConnected:alreadyShown:) -> String?`.

- [ ] **Step 1: Write the failing test**

Append to `UnitTests/Honor/PilgrimageStageWalkTests.swift`:

```swift
extension PilgrimageStageWalkTests {

    func testTheOfflineNoteIsSaidOnceAndOnlyForAStage() {
        XCTAssertEqual(HonorOverviewModel.offlineNote(isStage: true, isConnected: false, alreadyShown: false),
                       "map tiles need a connection; the way itself is on your phone.")
        XCTAssertNil(HonorOverviewModel.offlineNote(isStage: true, isConnected: false, alreadyShown: true),
                     "said once")
        XCTAssertNil(HonorOverviewModel.offlineNote(isStage: true, isConnected: true, alreadyShown: false),
                     "the tiles are coming")
        XCTAssertNil(HonorOverviewModel.offlineNote(isStage: false, isConnected: false, alreadyShown: false),
                     "a shared walk offline has a different problem: its voices")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/PilgrimageStageWalkTests 2>&1 | grep -E "error:|Executed"
```
Expected: `type 'HonorOverviewModel' has no member 'offlineNote'`.

- [ ] **Step 3: Add the preference and the note**

In `Pilgrim/Models/Preferences/UserPreferences.swift`, beside `honorSoftTapEnabled` (line 78):

```swift
    static let pilgrimageOfflineNoteShown = UserPreference.Required<Bool>(key: "pilgrimageOfflineNoteShown", defaultValue: false)
```

In `Pilgrim/Scenes/Honor/HonorOverviewView.swift`, add to `enum HonorOverviewModel`:

```swift
    /// Offline tiles are slice three. Until then a stage walked without a
    /// connection draws over the basemap's empty grey, and the overview says
    /// so once — the ghost line, the pins, the marks, the cards, the water,
    /// and the ledger all work without a network.
    static func offlineNote(isStage: Bool, isConnected: Bool, alreadyShown: Bool) -> String? {
        guard isStage, !isConnected, !alreadyShown else { return nil }
        return "map tiles need a connection; the way itself is on your phone."
    }
```

and render it in `card`, under the status line, with a one-shot connectivity probe modelled on `WalkOptionsSheet.checkConnectivity()`:

```swift
    @State private var isConnected = true
    @State private var offlineNote: String?
```

```swift
            if let offlineNote {
                Text(offlineNote)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
```

```swift
    /// A single probe, cancelled in its own handler — no monitor outlives
    /// this screen.
    private func checkConnectivity() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            let connected = path.status == .satisfied
            DispatchQueue.main.async {
                isConnected = connected
                if let note = HonorOverviewModel.offlineNote(
                    isStage: way.isPilgrimageStage, isConnected: connected,
                    alreadyShown: UserPreferences.pilgrimageOfflineNoteShown.value) {
                    offlineNote = note
                    UserPreferences.pilgrimageOfflineNoteShown.value = true
                }
            }
            monitor.cancel()
        }
        monitor.start(queue: DispatchQueue(label: "honor-connectivity-check"))
    }
```

called from the existing `.onAppear { probeDistance() }`:

```swift
        .onAppear { probeDistance(); checkConnectivity() }
```

Add `import Network` at the top of the file.

- [ ] **Step 4: Write the device-pass checklist**

`docs/honor-slice-two-device-pass.md`:

```markdown
# Honor slice two: device pass

One real stage on the test device, location simulated from the stage's own
GPX. Everything here is a thing the simulator cannot answer.

## Prerequisite: the dataset has to exist first

**None of this can be run yet.** It needs, from open-pilgrimages:

- `index.json` on `main` carrying a top-level `release` and, per listed
  route, a `ways` entry (`stageCount`, `bytes`, and — once the build
  measures coverage — `placesPerStage` and `sparse`);
- a `vX.Y.Z` tag, named by that `release`, carrying
  `routes/<route-id>/ways/route.json` and `routes/<route-id>/ways/stage-NN.json`.

Neither exists today: `main`'s index has no `release` and no `ways`, and no
tag carries a `ways/` directory. Until both land, the catalog shows
**"the routes are out of reach right now"** — which is correct behaviour,
not a bug — and the only proof this slice works is its unit tests, which run
against the checked-in fixture package. Check the CDN before booking device
time:

```bash
curl -sS https://cdn.jsdelivr.net/gh/walktalkmeditate/open-pilgrimages@main/index.json \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print("release:", d.get("release")); print("with ways:", [r["id"] for r in d["routes"] if r.get("ways")])'
```
Expected once the build has landed: a `vX.Y.Z` release and at least one route
id. An empty list means the device pass is still blocked.

## Before the walk

- [ ] Export the stage's GPX: open the stage's overview, ladybug menu →
      **Export simulation GPX**, AirDrop the file to the Mac.
- [ ] Xcode → Debug → Simulate Location → Add GPX File to Workspace, pick it.
- [ ] Settings → Data → **Export My Data** first if the device carries real
      walks. (`.worktrees/honor-slice-two` has no schema migration, but the
      export is the cheap insurance.)

## The catalog and the package

- [ ] Choose a way → **Walk a pilgrimage** → the catalog lists only routes the
      index marks with a `ways` entry.
- [ ] Airplane mode with nothing downloaded: **"the routes are out of reach
      right now"** and a retry that works once the radio is back.
- [ ] Download shows per-stage progress and finishes; the card then reads
      "on your phone".
- [ ] Kill the app mid-download, relaunch: nothing half-installed, no stage
      Ways in Settings → Ways.
- [ ] Try to Download / Replace / Remove during a walk: **"finish your walk
      first"** each time.

## Walking the stage

- [ ] Morning card at Begin: theme in the display face, the narrative, the
      facts line in your own unit, each warning its own paragraph, today's
      weather when there is any. One button, "walk".
- [ ] Reopen from the walk's ellipsis → **the day**; its button reads
      "close" and only dismisses.
- [ ] **No companion dot** anywhere, on the overview or the walk.
- [ ] **No soft tap**: walk 300 m off the line for three minutes; the caption
      slot stays empty.
- [ ] Service pins draw under the moment pins; zoom out past 13 and they go;
      inside a town at 13 there are never more than 40 on screen.
- [ ] A sacred site rises as a card with the dataset's text, the local name
      under the kicker, and a **Sit?** button that starts the meditation.
- [ ] Water caption and its haptic 300 m before an on-way fountain; the next
      fountain inside the hour stays a silent pin; one after the hour speaks.
- [ ] Airplane mode for one leg: grey basemap, ghost line, pins, marks, and
      cards all still there; the overview says the tiles line **once**.

## After the walk

- [ ] Arrival: the card reads "you walked the stage", names it, counts places
      and kilometres, and carries **no** companion delta.
- [ ] The closing line, then **reply here** — record one, then reopen the
      stage and confirm it plays back as "your reply".
- [ ] Summary: stage name, "14 of 24 km of the stage", the closing line, the
      reply.
- [ ] Route view: the stage is marked walked, the next row moved on, the
      progress line counts the kilometres.
- [ ] End a stage early: the row reads "continue from where you stopped" and
      the overview opens on that frac.
- [ ] Start a stage far from its line and walk normally: no cards, no
      captions, no arrival, **no ledger entry**.
- [ ] Grep the screens for "they" or "their" on a stage surface. There should
      be none.
```

- [ ] **Step 5: Run the tests, build, lint**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests 2>&1 | grep -E "error:|failed|Executed [0-9]+ tests"
swiftlint --quiet || echo "lint clean"
```
Expected: `** BUILD SUCCEEDED **`, the whole `UnitTests` bundle passing with 0 failures, and no SwiftLint errors.

- [ ] **Step 6: Commit**

```bash
git add -A Pilgrim UnitTests docs Pilgrim.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(honor): say the tiles line once, and write the device pass

Offline tiles are slice three; everything else on a stage works without a
network, and the overview says so once.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

## Self-review

**Spec coverage (sections 2–7):**

| Spec | Task |
|---|---|
| 2.1 third door, catalog states, "on your phone" | 8 |
| 2.2 route view, stage list (before **and** after download, via `routePreview`), next row, download prompt, off-line start | 8 (walk-as-ordinary comes free: the engine never anchors, Task 7 writes nothing) |
| 2.3 download / replace / update / remove / guard | 5, 6 |
| 2.4 index fetch, slug + release regex, 24 h cache, byte cap, ranges | 3 (the catalog reads `@main`, never a moving tag — see the constraint block and resolved ambiguity 7) |
| Sparse routes: `placesPerStage` + `sparse` on the index, "few places marked yet" | 1 (fixture), 3 (model + validation), 8 (both surfaces) |
| 2.5 `marks`, `stage`, moment fields, `.pilgrimage`, id allow-list, importer | 1, 2 |
| 3.1 no soft tap, no companion, arrival without delta, date hidden | 9 |
| 3.2 `text`, local names, `sitMinutes`, preview | 10 |
| 3.3 marks on the map, zoom floor, per-screen cap | 11 |
| 3.4 water ahead, quiet hour, caption, haptic | 12 |
| 3.5 anchor anywhere, summary's stage line | 7, 9 |
| 3.6 mode subtitle, lexicon, story context, fallback copy | 10, 15 |
| 4.1 morning card, reopen as "the day" | 13 |
| 4.2 arrival reflection, reply under origin −1 | 14 |
| 5 ledger: next, resume, km sum, anchor gate, identity, all-complete, redraw notice | 4, 7, 8 |
| 6 every error line, offline copy | 2 (copy), 5, 6, 16 |
| 7 every named unit test | 1–16; the device pass is Task 16's checklist |

**Type consistency:** `PilgrimageError` and `PilgrimageCopy` (Task 2) are used by Tasks 3, 5, 6, 8. `PilgrimageRoute`/`PilgrimageRouteStage` (Task 2) are used by Tasks 4, 5, 6, 8. `HonorStageOutcome` and `PilgrimageLedgerWriter` (Task 4) are used by Task 7. `WayStore.stageWayId` and `isValidRouteId` (Task 1) are used by Tasks 4, 5, 6, 8. `WayMarkPins.symbol` (Task 11) is the only place mark glyphs are named.

**Three formatters, each with one home.** They are easy to confuse, so:

| Formatter | Home | Reads | Callers |
|---|---|---|---|
| `WayStageFacts.line(distanceKm:gainMeters:hours:difficulty:)` | Task 8 | "24 km · 1,400 m up · 7 to 9 hours · hard" | `PilgrimageRouteModel.stageLine` (the stage list) and `StageMorningCardModel.factsLine` (the morning card) — **one implementation, two named entry points**; they were byte-identical copies once and must never be again |
| `WayStageLine.line(for:)` | Task 9 | "stage 1 of 33 · 24 km · hard" | wherever a shared walk would show its date: the overview, the Ways sheet, the Ways list |
| `PilgrimageLedger.progressLine(ledger:stageCount:)` | Task 4 | "stage 5 of 33 · 112 km walked" | the catalog card and the route view's next row |

**Shapes that must not drift:** `HonorArrivalCard` grows in Task 9 (`stageName`, `distanceWalkedMeters`) and again in Task 14 (`var closing`, defaulted so Task 9's constructions still compile) — Task 14's test constructs it with all three. `HonorSummaryData` grows in Task 9 (`isPilgrimageStage`, `stageProgressLine`) and Task 14 (`closing`, `replyRelativePath`) — same. `HonorSummaryModel.summaryData` gains its `ledger:` argument in Task 9 and is called with it in Task 14's tests. `PilgrimageCatalogEntry` grows `placesPerStage`/`sparse` in Task 3, both defaulted, so the literals in Tasks 5, 6, and 8 are untouched.

**One-way seams for testing:** `PilgrimagePackageManager.saveStage` and `.maxPackageBytes` (Task 5) exist so a spec can fail a commit and prove the rollback, and prove the package ceiling, without a full disk or 50 MB of fixtures. Both default to the production behaviour; neither is read by any view.
