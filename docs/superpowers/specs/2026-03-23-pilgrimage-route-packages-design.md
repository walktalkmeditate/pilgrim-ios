# Pilgrimage Route Packages

**Date:** 2026-03-23
**Status:** Approved design, not yet scheduled

## Summary

Downloadable pilgrimage route packages that transform Pilgrim from a walk recorder into a pilgrimage companion. Route data lives in a public GitHub repo (`pilgrim-routes`), served via jsDelivr CDN. The app downloads route GeoJSON + Mapbox offline tiles for fully offline trail guidance with waypoint proximity notifications.

One route downloaded at a time. Schema designed for future voice guides, meditation prompts, and community contributions.

## Principles

- **The repo is the product.** No backend, no worker, no server-side logic. `pilgrim-routes` is the single source of truth. jsDelivr is the CDN. The app is a thin client.
- **One route at a time.** A pilgrimage is a commitment. Downloading a new route replaces the previous one. This is a philosophical choice and a technical safeguard (tile pack budget).
- **AI-first, community-intended.** Launch routes built by AI agent from OSM/Waymarked Trails data. Schema and repo structure designed from day one so community contributors produce the same artifact via PR.
- **Companion, not navigator.** The trail is rendered as a quiet suggestion. Waypoint notifications are gentle. No turn-by-turn, no "off course" warnings. The app gets out of the way.
- **Ship the skeleton.** v1 is route geometry + waypoints + descriptions. Voice guides, meditation prompts, and soundscapes are schema fields that exist but are empty. Layer richness based on what pilgrims actually want.

## Data Source

**OpenStreetMap** via Waymarked Trails API — the richest open-licensed source for pilgrimage route data.

- Routes exist as OSM relations (e.g., Camino Frances: 2819556, Shikoku 88: 4445382)
- Waymarked Trails serves GPX, KML, and GeoJSON per relation with elevation data
- Download URL pattern: `https://hiking.waymarkedtrails.org/api/v1/details/relation/{ID}/geometry/geojson`
- License: ODbL 1.0 — redistributable with attribution ("Data from OpenStreetMap contributors")

**Route extraction pipeline** (AI agent or script):
1. Query Waymarked Trails / Overpass API for route geometry
2. Extract waypoints from OSM tagged nodes within the relation
3. Enrich waypoint descriptions via Wikipedia/Wikidata
4. Generate cover image from Mapbox Static API
5. Validate against JSON Schema
6. Open PR to `pilgrim-routes` repo

## pilgrim-routes Repo

Public GitHub repo: `momentmaker/pilgrim-routes`

### Structure

```
pilgrim-routes/
  manifest.json                    <- catalog index, fetched by app
  schema/
    route.schema.json              <- JSON Schema for validation
    metadata.schema.json
  camino-frances/
    route.geojson                  <- trail path + waypoints as FeatureCollection
    metadata.json                  <- name, description, distance, difficulty, stages
    cover.jpg                      <- hero image for catalog UI (~200KB, 3:2 ratio)
    stages.json                    <- stage breakdowns
  shikoku-88/
    route.geojson
    metadata.json
    cover.jpg
    stages.json
  ...
```

### manifest.json

```json
{
  "schemaVersion": 1,
  "routes": [
    {
      "id": "camino-frances",
      "name": "Camino de Santiago (Frances)",
      "region": "Spain",
      "distance_km": 780,
      "estimated_days": "30-35",
      "difficulty": "moderate",
      "cover": "camino-frances/cover.jpg",
      "size_bytes": 245000,  // route data only (geojson + metadata + cover), NOT tile estimate
      "updated": "2026-03-20"
    }
  ]
}
```

App fetches from: `https://cdn.jsdelivr.net/gh/momentmaker/pilgrim-routes@v{schemaVersion}/manifest.json`

Individual route files: `https://cdn.jsdelivr.net/gh/momentmaker/pilgrim-routes@v1/camino-frances/route.geojson`

Version pinning: `schemaVersion: 1` maps to git tag `v1`. New schema versions require tagging a new release. Cache purging automatic on new commits within a tag.

### route.geojson

GeoJSON FeatureCollection with two feature types:

**LineString features** — trail segments:
- Properties: `name`, `stage` (optional), `surface` (paved/trail/road)

**Point features** — waypoints:
- Properties: `name`, `type` (temple, albergue, water, viewpoint, town, sacred_site), `icon` (SF Symbol name), `description`, `elevation_m`
- Future fields (empty in v1): `voice_guide`, `meditation`, `soundscape`

**Coordinate format:** Standard GeoJSON `[longitude, latitude, altitude]`. Altitude included where available from source data (Waymarked Trails includes elevation). Matches the existing PilgrimPackage GeoJSON format.

### metadata.json

```json
{
  "id": "camino-frances",
  "name": "Camino de Santiago (Frances)",
  "name_local": "Camino de Santiago (Frances)",
  "region": "Spain",
  "country_codes": ["ES", "FR"],
  "description": "The most popular route to Santiago de Compostela...",
  "distance_km": 780,
  "elevation_gain_m": 14600,
  "elevation_loss_m": 14200,
  "estimated_days": "30-35",
  "difficulty": "moderate",
  "terrain": ["paved", "trail", "road"],
  "best_months": [4, 5, 6, 9, 10],
  "osmRelationId": 2819556,
  "source": "OpenStreetMap contributors",
  "license": "ODbL-1.0",
  "attribution": "Data from OpenStreetMap contributors, licensed under ODbL",
  "stages": "stages.json"
}
```

### stages.json

```json
{
  "stages": [
    {
      "name": "Saint-Jean-Pied-de-Port to Roncesvalles",
      "distance_km": 25.7,
      "elevation_gain_m": 1390,
      "elevation_loss_m": 880,
      "difficulty": "hard",
      "description": "The Pyrenees crossing. The most demanding day."
    }
  ]
}
```

## App Architecture

### New Files

```
Pilgrim/Models/Routes/
  RouteManifestService.swift       <- fetches + caches manifest.json
  RoutePackageManager.swift        <- downloads, stores, deletes packages
  RoutePackage.swift               <- Codable models for manifest/metadata/route
  RouteMapOverlay.swift            <- renders route GeoJSON + waypoints on map
  RouteProximityMonitor.swift      <- waypoint approach notifications
```

### RouteManifestService

Mirrors `AudioManifestService` pattern:
- Fetches manifest from jsDelivr on app launch + pull-to-refresh
- Caches in Application Support directory
- `@Published var routes: [RouteManifestEntry]`
- Version-based cache invalidation via `schemaVersion`

### RoutePackageManager

Mirrors `AudioDownloadManager` pattern:
- Downloads `route.geojson`, `metadata.json`, `cover.jpg`, `stages.json` per route
- Stores in `Application Support/RoutePackages/{route-id}/`
- Tracks download state: `.available`, `.downloading(progress)`, `.downloaded`, `.updateAvailable`
- **Single route constraint:** `currentRoute: RoutePackage?` — downloading a new route prompts to replace
- Delete removes local files + purges Mapbox tile region
- Compares `manifest.updated` against local copy to detect updates

**Download atomicity:** All four files must succeed before the package is marked `.downloaded`. If any file fails, clean up partial downloads and revert to `.available`. Tile region download is a separate phase — if tiles fail but route data succeeded, mark as `.downloaded` with a "Maps unavailable offline" indicator. Single retry per file (matching `AudioDownloadManager` pattern).

**Disk space check:** Before initiating download, check available disk space using `FileManager.attributesOfFileSystem`. Route data is small (~200KB), but tile regions can be large (~200-500MB). Show estimated size and warn if space is low. The DiskSpace API is already declared in the privacy manifest (E174.1).

### Mapbox Offline Integration

**One-time change:** `AppDelegate` switches `tileStoreUsageMode` from `.readOnly` to `.shared`. Note: this means tiles viewed online will also be cached for offline use, which may increase disk usage over time. Acceptable trade-off for offline support.

On route download, after GeoJSON is saved — two steps: style pack + tile region:

```swift
let offlineManager = OfflineManager()

// 1. Download style pack (glyphs, sprites, style resources)
let stylePackOptions = StylePackLoadOptions(glyphsRasterizationMode: .ideographsRasterizedLocally)
offlineManager.loadStylePack(for: .light, loadOptions: stylePackOptions)

// 2. Download tile region
let descriptorOptions = TilesetDescriptorOptions(
    styleURI: .light,
    zoomRange: 6...14,
    tilesets: nil
)
let descriptor = offlineManager.createTilesetDescriptor(for: descriptorOptions)

guard let regionOptions = TileRegionLoadOptions(
    geometry: boundingBoxPolygon,  // computed from route.geojson
    descriptors: [descriptor],
    acceptExpired: true
) else { /* handle failure */ }

tileStore.loadTileRegion(forId: "route-\(routeId)", loadOptions: regionOptions)
```

Deletion: `tileStore.removeTileRegion(forId: "route-\(routeId)")`

**Light vs dark mode:** Only `.light` tiles are downloaded for offline. PilgrimMapStyle applies wabi-sabi palette transformations (color overrides) on top of the base style, so light tiles with dark palette colors are acceptable offline. Downloading both styles would double storage for minimal benefit.

**Tile budget:** Tested with Shikoku 88 (200km x 192km bounding box) at z6-14: **183 tile packs, 15,811 tiles.** Hard limit is 750 tile packs. One-route-at-a-time constraint ensures this is never exceeded.

**Billing:** Mapbox Maps SDK v11 docs state offline tile downloads are included in MAU billing. One user = one MAU regardless of online viewing or offline downloads. Confirm with Mapbox support before shipping.

### RouteMapOverlay

Extends existing PilgrimMapView GeoJSON rendering:
- Route trail as LineString in a subtle color (`fog` or `dawn` from wabi-sabi palette)
- Waypoints as Point annotations with SF Symbol icons
- User's live walk track renders on top in `stone` color
- Route is a quiet suggestion, not a command

### RouteProximityMonitor

A `WalkBuilderComponent` conformant — instantiated by `WalkBuilder` when a route is active, receives the same location updates as other components. Reads route data from `RoutePackageManager.currentRoute`.

- On each location update, checks distance to upcoming waypoints via `CLLocation.distance(from:)`
- Within ~200m of unvisited waypoint: mark visited, in-app overlay with waypoint name + description, gentle haptic (`.soft`)
- Uses in-app overlay (not `UNUserNotificationCenter`) to avoid requiring a new permission. The overlay is a transient banner similar to the existing walk event toasts.
- Lightweight — distance comparison against a small coordinate array
- Uses `[weak self]` per resource safety rules
- Runs in background during walks (same lifecycle as other WalkBuilder components)

### Schema Versioning

- `manifest.json` has `schemaVersion` field
- App checks on fetch; if newer than understood, shows catalog read-only with "Update app" message
- Individual route packages carry format implicitly through GeoJSON structure
- Future fields (voice_guide, meditation, soundscape) simply absent in v1

## App UI

### Route Catalog

Section on home view: "Pilgrimage Routes" with "See All" link.

Each row:
- Cover image, route name, region
- Distance, estimated days, difficulty
- Download state: cloud icon / progress ring / checkmark

Tapping opens Route Detail.

### Route Detail

- Full-screen map showing trail overlay on PilgrimMapView
- Route name, description from metadata
- Stats: distance, elevation gain/loss, estimated days, difficulty
- Stage list (collapsible)
- Waypoint count
- Attribution: "Data from OpenStreetMap contributors"
- **Download button** — two-phase progress: "Downloading route..." then "Downloading maps..."
- Once downloaded: "Start Walking" button appears

### Active Route (During Walk)

- Trail rendered as subtle line (distinct from live track)
- Waypoints as small markers with icons
- Approaching waypoint (~200m): gentle haptic + notification with name and description
- No turn-by-turn, no deviation warnings

### Settings

- "Current Route: Shikoku 88 Temple Pilgrimage — 350MB"
- "Remove" button — confirmation dialog, deletes files + tile region
- No list management needed with one-route constraint

## Distribution

```
pilgrim-routes repo (GitHub)
    |  merge to main
jsDelivr CDN (automatic, global, free for open source)
    |  app fetches manifest.json
RouteManifestService (caches locally)
    |  user taps Download
RoutePackageManager
    |-- downloads GeoJSON + metadata + cover from jsDelivr
    |-- triggers Mapbox OfflineManager for tile region at z6-14
    |
Device (Application Support + Mapbox TileStore)
```

No worker. No backend. No server-side logic. The repo is the CDN.

## What Doesn't Change

- **PilgrimMapView** — already renders GeoJSON, gets a second source for route overlay
- **WalkBuilder** — walks record identically regardless of active route
- **CoreStore** — no new entities, route packages are file-based
- **PilgrimPackage** — unrelated, that's walk export/import
- **Collective counter** — independent feature

## v1 Launch Routes (Target)

| Route | OSM Relation | Distance | Region |
|---|---|---|---|
| Camino Frances | 2819556 | 780 km | Spain |
| Camino Portugues | 2362220 | 620 km | Portugal/Spain |
| Via Francigena | 2028505 | 1,900 km | UK/France/Switzerland/Italy |
| Shikoku 88 Temple | 4445382 | 1,200 km | Japan |
| Kumano Kodo (Nakahechi) | 3930988 | 38 km | Japan |
| St. Olav's Way | 67092 | 643 km | Norway |

## Future Enhancements (Designed For, Not Built)

- **Voice context at waypoints** — `voice_guide` field on Point features, plugs into existing voice guide infrastructure
- **Meditation prompts at sacred sites** — `meditation` field triggers meditation timer at waypoints
- **Ambient soundscapes per terrain** — `soundscape` field on LineString features
- **Community contributions** — public repo accepts PRs, schema is human-readable
- **Pilgrimage summary** — completing a route stitches all walks into a single journey artifact
- **Trail whispers** — anonymous location-pinned messages from other pilgrims, ephemeral
- **Seasonal cover art** — catalog images reflect current season
- **Preparation phase** — daily meditation prompts before departure
- **Return integration** — post-completion reflection prompts
- **User-created routes** — draw a path, mark waypoints, contribute back to repo
- **Collective pilgrimage tracking** — anonymous "a pilgrim has begun/completed" events
- **Paper companion** — printable PDF fold-out map from route GeoJSON

## Open Questions

1. **Mapbox billing confirmation** — verify offline tile downloads are MAU-inclusive in SDK v11 with Mapbox support
2. **Tile region size estimates** — test additional routes in Offline Estimator to confirm all fit under 750 tile packs
3. **Cover image generation** — decide whether AI agent generates via Mapbox Static API or curated photos
4. **Catalog placement** — section on home vs dedicated tab (decide during implementation)
5. **Walk-route association** — walks recorded while a route is active have no link back to that route if the route is later deleted. Consider storing route ID + name on the Walk at recording time (could use existing event system or metadata field to avoid a schema migration)
