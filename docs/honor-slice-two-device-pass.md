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
- [ ] With a different route already installed, Download shows a **Replace?**
      confirmation naming the installed route's stages leaving the phone;
      cancel with **Keep it** and nothing changes.
- [ ] With a new release for the route you already have, the button reads
      **Update** and tapping it installs the new release directly — **no
      confirmation dialog** (that's only Replace's). A route that shrank
      drops its now-out-of-range stage Ways and the ledger; the redraw
      notice reads "the route's stages were redrawn; your kilometres are
      kept."

## Walking the stage

- [ ] Morning card at Begin: theme in the display face, the narrative, the
      facts line in your own unit, each warning its own paragraph, today's
      weather when there is any. One button, "walk".
- [ ] Reopen from the walk's ellipsis → **the day**; its button reads
      "close" and only dismisses.
- [ ] **No companion dot** anywhere, on the overview or the walk.
- [ ] **No soft tap**: walk 300 m off the line for three minutes; the caption
      slot stays empty.
- [ ] Service pins draw under the moment pins, gated by the map's own live
      zoom rather than a fixed one: the overview opens fit to the whole
      stage, which sits below the zoom-13 floor, so **no service pins show
      until you zoom in**; zoom out past 13 and they go again; inside a town
      at 13 there are never more than 40 on screen.
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
- [ ] Start a reply, then press **stop** on the walk while it is still
      recording (before tapping done on the card) — reopen the stage and
      confirm it still plays back as "your reply". The recording that was
      still open when the walk ended must not be orphaned.
- [ ] Summary: stage name, "14 of 24 km of the stage", the closing line, the
      reply.
- [ ] Route view: the stage is marked walked, the next row moved on, the
      progress line counts the kilometres.
- [ ] End a stage early: the row reads "continue from where you stopped".
      Tapping it reopens the stage the same way any stage opens — fit to
      the whole line, no camera or progress seeded from where you stopped —
      and the walk re-anchors from wherever you actually are when you press
      Begin, same as a first attempt.
- [ ] Start a stage far from its line and walk normally: no cards, no
      captions, no arrival, **no ledger entry**.
- [ ] Grep the screens for "they" or "their" on a stage surface. There should
      be none.
