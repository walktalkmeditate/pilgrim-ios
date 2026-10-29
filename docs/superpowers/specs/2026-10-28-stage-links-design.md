# Stage Links: One Address per Pilgrimage Stage

**Date:** 2026-10-28
**Repos:** pilgrim-ios (link + landing), pilgrim-worker (fallback page), open-pilgrimages (numbering rule + check). Android and pilgrimag.es follow in their own passes.
**Builds on:** Honor slice two (`2026-09-03-honor-slice-two-pilgrimage-stages-design.md`: the pilgrimage package, one route at a time, the route screen) and the honor host (`pilgrim-worker/docs/superpowers/plans/2026-09-03-honor-host.md`: AASA, asset links, the walk fallback page).
**Not in this design:** route-only links, the Android port, the buttons on pilgrimag.es, opening a stage automatically after a download finishes.

## Summary

Today a link can open Pilgrim in exactly one way: a shared walk, `honor.pilgrimapp.org/AbC123xYz0`. A "walk this stage" button on pilgrimag.es can only send people to the App Store, and someone who already has the app taps six times to reach a stage (Path → Honor → Walk a pilgrimage → the route → Download → the stage).

This design adds a second link shape, `honor.pilgrimapp.org/camino-frances/14`. With Pilgrim installed it lands on that stage: its overview with Begin if the route is on the phone, otherwise the route screen scrolled to the stage with the existing download prompt raised. Without Pilgrim, the same address is a small page about the stage with a store button.

The domain already claims every path for both apps (the AASA's `"/*"` component and Android's `handle_all_urls`), so no association file changes. The flip side: every Pilgrim build already installed opens on a stage link and drops it silently. That fixes the release order (§6).

## Decisions (from the 2026-10-28 brainstorm)

1. **The link uses open-pilgrimages route ids, the unit the app can walk.** pilgrimag.es has one page for `shikoku-88` and one for `kumano-kodo`. The app walks their sections (`shikoku-88-tosa`, `kumano-kodo-nakahechi`) and numbers stages within each one. A Shikoku link is `/shikoku-88-tosa/7`. Converting its own stage numbering is pilgrimag.es's job; `index.json` already records each section's `pilgrimage`. (Rejected: pilgrimag.es slugs in the link, which would need a second numbering scheme inside the app.)
2. **Stage numbers count from 1,** as the route screen shows them ("14. Hornillos del Camino to Castrojeriz"). The data counts from 0; the conversion happens once, in the parser.
3. **A stage link does what tapping that stage on the route screen does.** Downloaded: the overview with Begin. Not downloaded: the route screen and its existing "Download this route first?" prompt, which goes through `beginInstall()`, so Replace still asks first when another route is on the phone. No new download logic.
4. **Stage links only.** Every use named in the brainstorm is a stage. A one-segment route link would collide with share ids whenever a route id is exactly 10 characters.
5. **The route screen opens in its own sheet** (approach A). (Rejected: B, replaying the taps by presenting the Ways sheet, then the nested Pilgrimages sheet, then pushing the route in code, which is the sheet-on-sheet race the AF60 comments already fight; C, a new stage preview screen that works before download, which would duplicate the route screen.)
6. **The fallback page shows real stage facts** read from the same files the app reads, so the page and the app cannot disagree. If they can't be fetched, the page falls back to the stage number alone.
7. **Unrecognised honor-host links say so.** This build shows "this link needs a newer Pilgrim" for an honor-host path it can't parse, so the next new link shape never dead-ends silently the way this one will on today's builds.
8. **Stage numbers become a public promise,** enforced by a check in open-pilgrimages rather than only written in prose. The app's existing redraw notice (`PilgrimageRouteModel.redrawNotice`, "the route's stages were redrawn; your kilometres are kept.") shows that redraws do happen.

## 1. The link

```
https://honor.pilgrimapp.org/<route>/<stage>[/]
```

- `<route>`: an open-pilgrimages route id, validated by `WayStore.isValidRouteId` (`[a-z0-9-]{1,64}`).
- `<stage>`: `[1-9][0-9]{0,2}`, and at most `PilgrimageCatalogService.maxStageCount` (200). No leading zeros, so each stage has one canonical address.
- An optional trailing slash, as share links allow today.
- Query strings and fragments are ignored, so tracking tags don't break it.
- **Honor host only.** Share links parse on `honor.pilgrimapp.org` and `walk.pilgrimapp.org`; stage links parse only on the honor host, where the fallback page lives.

A share id is one path segment and a stage link is two, so the shapes cannot be confused.

## 2. The app: parsing

`HonorLink.parse(_ url:)` returns a destination instead of a bare share id:

```swift
enum HonorLinkDestination: Equatable {
    case share(id: String)
    case stage(routeId: String, index: Int)   // 0-based; the URL's number minus one
    case unrecognised                         // honor host, but neither shape
}
```

- `parse(_ url:)` returns `nil` for any other host, so non-Pilgrim URLs stay ignored. The honor host's bare root (`/`) also returns `nil`: it isn't a link to anything.
- `parse(text:)` (the Ways sheet's paste field) accepts stage links too. Pasted text that matches neither shape keeps returning `nil`, so the paste field keeps its current handling. Only a URL the OS hands the app yields `.unrecognised`.
- `PilgrimApp.route(_:)` posts the destination on `.pilgrimOpenWay`, and `PilgrimApp.pendingShareId` becomes `pendingLink: HonorLinkDestination?`, still claimed exactly once by `MainTabView.onAppear` for a cold launch.

## 3. The app: landing

### 3.1 One entry point

`MainCoordinatorView` gains `open(_ link: HonorLinkDestination)`, and `MainTabView` calls it from both its `.onReceive(.pilgrimOpenWay)` and its `.onAppear` drain. Both keep today's rule: switch to the Path tab unless a walk is on.

- `.share(id)` → `openWay(shareId:)`, unchanged.
- `.stage(routeId, index)` → `openStage(routeId:index:)` (§3.2).
- `.unrecognised` → toast "this link needs a newer Pilgrim".

### 3.2 Resolving a stage

`openStage` asks a pure `StageLinkResolver` what to do, then performs it:

```swift
enum StageLinkOutcome: Equatable {
    case overview(wayId: String)                                // stage Way is on the phone
    case routeSheet(entry: PilgrimageCatalogEntry, focus: Int?) // focus nil when out of range
    case notInCatalog
    case needsCatalog                                           // no catalog in hand yet
}

static func resolve(routeId: String, index: Int, installedRouteId: String?,
                    stageWayExists: Bool, catalog: PilgrimageCatalog?) -> StageLinkOutcome
```

The coordinator gathers the inputs (`PilgrimagePackageManager.installed()`, `WayStore.load(id:)`, `PilgrimageCatalogService.shared.catalog`), calls `resolve`, and on `.needsCatalog` loads the catalog and calls it again. In order:

1. **A walk is on:** toast "finish this walk first", exactly as `openWay` does. Nothing else happens.
2. **The installed route is this route and `WayStore` has the stage Way** (`WayStore.stageWayId(routeId:stageIndex:)`): `.overview`, then `openOverview(for:)`. No network. This holds whether or not an Update is pending, just as tapping the stage on the route screen does today.
3. **Otherwise, with a catalog already in memory:** decide from it, no network.
4. **Otherwise:** `.needsCatalog`. Toast "reaching for the route…", then `PilgrimageCatalogService.shared.load()`, then resolve again.
   - Route not in the catalog: toast "this route isn't in Pilgrim yet".
   - Catalog unreachable with nothing cached: the existing `PilgrimageCopy.line(for:)` failure, as a toast.
   - Found: present the route sheet with `focus: index` when `index < entry.stageCount`, else `focus: nil`.
5. **The newest link wins.** Stage links use the coordinator's existing `importTask`: a new link of either kind cancels the one in flight, and a cancelled task lands nothing.
6. **A Begin in flight wins.** If `activeWalkViewModel` or `pendingStartWay` is set when the catalog returns, the outcome is dropped silently, matching `openWay`.

### 3.3 The route sheet

`MainTabView` presents `honorRouteLink: HonorRouteLink?` (the catalog entry, the catalog's release, and the focus index) as a sheet:

```swift
NavigationStack {
    PilgrimageRouteView(entry: link.entry, release: link.release,
                        focusStage: link.focus, onChoose: { coordinator.openOverview(for: $0) })
}
```

with a Close button in the cancellation slot, styled like `PilgrimageCatalogView`'s.

`PilgrimageRouteView` gains `focusStage: Int? = nil`. Existing callers pass nothing and behave exactly as today. When set:

- The `List` sits in a `ScrollViewReader`. Once the stages are loaded (installed route or preview), it scrolls the focused row to the centre.
- If the route isn't installed, it sets `promptDownload = true` once. A `@State` flag stops a reload or a return to the screen from raising it again. If the route is installed but the stage is missing (an older release with fewer stages), there's no prompt: the Update button is the call to action.
- After a download the walker taps the stage themselves. It's in view, and nothing opens on its own after a wait.

### 3.4 Never two sheets at once

- **Ways sheet or summary open:** hold the route link in `pendingRouteLink`, close the Ways sheet, and promote it from the same dismiss hooks that call `promotePendingHonorWay()` (the Ways sheet's `onDismiss` and `handleSummaryDismiss`).
- **An overview open:** set `honorOverviewWay = nil`, hold the link, and promote it from `handleOverviewDismiss()`. A pending Begin there still wins and the link is dropped.
- **Choosing a stage inside the route sheet:** `openOverview(for:)` treats an open route sheet like an open Ways sheet. It parks the Way in `pendingHonorWay`, closes the sheet, and the sheet's `onDismiss` calls `promotePendingHonorWay()`.
- **Other sheets elsewhere in the app:** the same coverage share links have today, no more.

### 3.5 Copy

Toasts are lowercase, like the existing ones ("reaching for the walk…", "finish this walk first"):

- "reaching for the route…"
- "this route isn't in Pilgrim yet"
- "this link needs a newer Pilgrim"

## 4. The fallback page (pilgrim-worker)

### 4.1 Routing

`dispatchHonorHost` gains a branch after the share-id branch:

```ts
const stage = url.pathname.match(/^\/([a-z0-9-]{1,64})\/([1-9][0-9]{0,2})\/?$/);
```

Methods follow the walk page: GET and HEAD (HEAD with an empty body), 405 with `allow: GET, HEAD` otherwise. Every other path still 404s.

### 4.2 Data

New `src/open-pilgrimages.ts`, reading exactly what the app reads:

- `https://cdn.jsdelivr.net/gh/walktalkmeditate/open-pilgrimages@main/index.json`: is the route present with a `ways` block? Its `name.en`, `ways.stageCount`, and the top-level `release`. Edge-cached for 1 hour (`cf: { cacheTtl: 3600 }`).
- `…/open-pilgrimages@<release>/routes/<id>/ways/route.json`: `stages[n-1]`'s `name`, `distanceKm`, `gainMeters`, `hours.min`/`hours.max` and `difficulty`. Tags never move, so this is edge-cached for a day.
- `release` is checked against `^v[0-9]+\.[0-9]+\.[0-9]+$` before it reaches a URL, as the app does. Both fetches are size-capped and time-limited. A non-200, oversized, slow or unparseable response counts as "unreachable".

### 4.3 Responses

| Case | Status | Body | `cache-control` |
|---|---|---|---|
| Route walkable, stage in range | 200 | full page | `public, max-age=300` |
| Route unknown, no `ways`, or stage > `stageCount` | 404 | `Not Found` | — |
| open-pilgrimages unreachable | 200 | basic page: "stage 14", generic copy, store buttons | `public, max-age=60` |

Every response carries `x-robots-tag: noindex` and `x-content-type-options: nosniff`, like the walk page. pilgrimag.es stays the indexed home for stage content. The basic page never shows the route id as if it were a name.

### 4.4 The page

New `src/generators/stage-page.ts`, modelled on `honor-page.ts` (same palette, platform script and QR helper):

- Logo.
- Small line: "Camino de Santiago (Frances) · stage 14 of 33" (the index's `name.en`; the page is one cached document, so it doesn't vary by language).
- Heading: the stage name, "Hornillos del Camino to Castrojeriz".
- Facts in the app's `WayStageFacts` format: "19.9 km · 174 m up · 5 to 6 hours · moderate", always metric.
- One sentence inviting them to walk it with Pilgrim.
- **iPhone:** App Store button; "Once it's installed, tap Open in the banner above, or go back and tap the link again."
- **Android:** Play button, with no `honor=` install referrer for now. The Android port adds a stage referrer if it wants post-install landing.
- **Desktop:** a QR code of the page's own address, plus store links.
- `<meta name="apple-itunes-app" content="app-id=6760921056, app-argument=<this address>">`.

Every value from open-pilgrimages is HTML-escaped. The route id and stage number are re-validated in the generator before they reach an `href` or `app-argument`, mirroring `generateHonorPage`'s guard.

## 5. The numbering rule (open-pilgrimages)

- **Docs:** README "Versioning" and CLAUDE.md say a walkable route's stage numbers are public addresses (`honor.pilgrimapp.org/<route>/<stage>`), and redrawing them is a MAJOR release.
- **Check:** `check-stage-numbering` (tsx script plus a test, run in `validate.yml` next to the existing checks). For every route with a `ways` package at the latest release tag, it compares the working tree's `stages.json` (what `build-ways` builds each package from) with that tag's. It fails if:
  - the stage count changed, or
  - stage N's start or end moved more than 500 m,

  unless `package.json`'s version (the release tag source, per `build-index.ts`'s `releaseTag`) is a MAJOR bump over the tag. Names aren't compared, so typo and accent fixes pass. A route that is new since the tag has nothing to compare and passes.
- **The check never switches itself off.** CI's checkout must fetch tags. If no release tag is reachable, the check fails with a message saying so, rather than passing with nothing compared. A run that compared zero routes when the tag had walkable routes also fails.

## 6. Release order

1. **open-pilgrimages:** the rule and the check. Independent of everything else.
2. **pilgrim-worker:** deploy the stage page. Harmless alone, since nothing links to it yet. Verify with `curl -i https://honor.pilgrimapp.org/camino-frances/14` (200 with the facts), `/camino-frances/99` (404), `/AbC123xYz0`-shaped share paths (unchanged).
3. **pilgrim-ios:** the build with stage links, sent to TestFlight only on the owner's explicit go, then the App Store.
4. **pilgrim-android:** port via `/ios-parity`, including the unrecognised-link notice and optionally the stage install referrer.
5. **pilgrimag.es:** stage buttons about two weeks after both store builds are live, so most installs have updated. Before that, an installed app on either platform opens on the link and drops it.

## 7. Testing

### 7.1 pilgrim-ios (unit)

`UnitTests/Honor/HonorLinkTests.swift`, extended:
- `/camino-frances/14` → `.stage("camino-frances", 13)`; with a trailing slash; with a query string.
- Rejected as stage links: `/camino-frances/0`, `/camino-frances/014`, `/camino-frances/201`, `/Camino-Frances/14`, and a stage link on `walk.pilgrimapp.org`.
- Honor host, unknown shape (`/a/b/c`, `/camino-frances`) → `.unrecognised`; honor host root → `nil`; other host → `nil`.
- Share links unchanged on both hosts.
- `parse(text:)` accepts a bare `honor.pilgrimapp.org/camino-frances/14` and returns `nil` for junk.

`UnitTests/Honor/StageLinkResolverTests.swift`, new:
- Installed with the stage Way → `.overview`.
- Installed, stage Way missing → `.routeSheet(focus: index)`.
- Not installed, in range → `.routeSheet(focus: index)`.
- Another route installed → `.routeSheet` (Replace is the route screen's business).
- Index ≥ `stageCount` → `.routeSheet(focus: nil)`.
- Route absent from catalog → `.notInCatalog`.
- Not installed, no catalog in hand → `.needsCatalog`; installed with the stage Way and no catalog → still `.overview`.

### 7.2 pilgrim-ios (manual, simulator)

Using `xcrun simctl openurl booted https://honor.pilgrimapp.org/…`. If the simulator won't route it as a universal link, `HonorLink.parse(text:)` through the paste field exercises the same coordinator path. Cases: warm launch, cold launch, Ways sheet open, overview open, summary open, mid-walk, route installed, another route installed, nothing installed, out-of-range stage, unknown route, offline with no cached catalog. Universal links and the Smart App Banner on a real iPhone are the owner's check.

### 7.3 pilgrim-worker (vitest)

In `test/honor-host.test.ts` or a sibling `test/stage-page.test.ts`, with `fetch` stubbed:
- Full page for a walkable stage: name, facts line, "stage 14 of 33", banner `app-argument`.
- 404 for an unknown route, a route with no `ways`, and a stage beyond `stageCount`.
- Basic page with `max-age=60` when either fetch fails, returns non-200, or returns bad JSON.
- HEAD with an empty body; 405 for POST; trailing slash.
- A stage name containing `<script>` comes out escaped.
- A malformed `release` never reaches a URL.
- Share-id paths and the AASA and asset links are unchanged; other paths still 404.
- Headers: `noindex`, `nosniff`, cache-control per case.

### 7.4 open-pilgrimages

Fixture tests for `check-stage-numbering`: an unchanged route passes; a renamed stage passes; an endpoint moved 600 m fails; a changed stage count fails; the same changes with a MAJOR bump pass; a route new since the tag passes; no reachable tag fails; zero routes compared fails.

## 8. Out of scope

- Route-only links (`/camino-frances`).
- Opening the stage automatically once a download triggered by a link finishes.
- Localising the fallback page by `Accept-Language`.
- An install referrer for stage links on Android.
- Indexing the fallback page.
- The Android port and the pilgrimag.es buttons (§6, their own passes).
