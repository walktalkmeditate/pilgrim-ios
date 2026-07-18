---
date: 2026-07-18
topic: daily-rotating-pilgrimage-routes
---

# Daily-Rotating Pilgrimage Routes

## Summary

Replace the app's hardcoded pilgrimage route table with a daily-rotating selection drawn from a shared route artifact that the web, iOS, and Android all read. Two surfaces render it: the existing collective line at the top of Settings, and a new line in the walk summary that measures a contributed walk against the day's route.

---

## Problem Frame

`Pilgrim/Models/Collective/PilgrimageProgress.swift` carries a hardcoded route table that is both wrong and frozen.

**Wrong.** Kumano Kodo is listed at 40 km (the dataset says 39). Camino de Santiago at 800 km (764). It includes "Via Francigena stage," which is not in the route dataset at all, alongside Te Araroa and the Appalachian Trail — thru-hikes rather than pilgrimages.

**Frozen.** Selection picks the largest route the collective has surpassed, so the line climbs and then sits. At the collective's 696.98 km (2026-07-18) it reads *"Together, the Via Francigena stage walked 6 times."* In roughly seventeen days it becomes *"Together, one Camino de Santiago complete."* and stays on that one sentence until 1,600 km — about five months at the current rate of roughly 6 km/day.

This is the fourth copy of a table the web already deleted three of. `../pilgrim-landing` shipped a fix in July 2026 that bakes route facts from `../open-pilgrimages` and rotates the lens daily; the app never received it. `../pilgrim-android` mirrors iOS verbatim, so the same staleness is pinned downstream.

Separately, the walk summary ends without any connection to the collective a pilgrim just contributed to — the one moment they have most recently acted and are most open to being told what it meant.

---

## Actors

- A1. Contributing pilgrim: has the collective toggle on; their walks move the counter, and they see both the Settings line and the walk summary line.
- A2. Non-contributing pilgrim: toggle off, which is the default; sees the Settings line, never the walk summary line.
- A3. Route curator: adds or edits routes upstream and re-runs the bake. Their wording reaches all three surfaces without an app release, so the artifact's phrasing rules bind them.

---

## Key Flows

- F1. Daily route selection
  - **Trigger:** Any surface needs the day's entry.
  - **Actors:** A1, A2
  - **Steps:** The app resolves the current UTC date, selects one entry from its cached route data using seasonal weighting, and renders the appropriate phrasing for that entry against the collective's total distance. No network call is required at read time.
  - **Outcome:** Every pilgrim worldwide sees the same route for the same UTC day, online or off.
  - **Covered by:** R6, R7, R8, R9

- F2. Walk completion to summary line
  - **Trigger:** A walk is saved.
  - **Actors:** A1, A2
  - **Steps:** The walk is contributed to the collective only if the toggle is on. The summary screen resolves the day's entry, and — for contributed walks only — renders a line placing that walk's distance against the entry and naming who has really walked it. Non-contributed walks render nothing in this position.
  - **Outcome:** A contributing pilgrim's walk is placed among real pilgrims; a non-contributing pilgrim is not told they moved something they did not move.
  - **Covered by:** R12, R13, R14, R15

---

## Requirements

**Route data and distribution**

- R1. Route facts — name, length, seasonality, and annual figures — come from a single baked artifact published to the CDN and consumed by web, iOS, and Android.
- R2. Adding, editing, retiring, or reordering a route requires no app release.
- R3. Each entry carries a short display phrase naming who has actually walked it, reflecting that entry's real metric rather than a generic claim.
- R4. Display phrases contain no distances and no units. Numbers and units are supplied by the app at render time.
- R5. The app tolerates entries it cannot parse: unknown or malformed entries are dropped, and the remaining catalog still renders.
- R6. The app ships a bundled copy of the artifact so a fresh install with no network still rotates.

**Daily selection**

- R7. Exactly one entry — a pilgrimage route or a cosmic horizon — is selected per UTC day, identically for every pilgrim.
- R8. Selection is seasonally weighted so in-season routes surface more often, and scattered so consecutive days do not repeat the same entry more than the weighting implies.
- R9. Selection runs on-device against cached data and produces a result with no network available.
- R10. Both surfaces show the same entry on the same day.

**Settings line**

- R11. The daily line replaces the current hardcoded line in the same position at the top of Settings, keeping its existing single-line shape and styling.

**Walk summary line**

- R12. The line renders only when the walk was actually contributed to the collective. When the collective toggle is off, nothing renders in this position.
- R13. The line places the walk's distance against the day's entry and names who has walked that entry, using the entry's display phrase.
- R14. Every entry type produces a line — routes and cosmic horizons alike. A contributed walk is never left without one.
- R15. The line coexists with the existing personal distance milestone; when both apply to the same walk, both render.

**Units and attribution**

- R16. Every distance rendered on either surface respects the pilgrim's chosen unit, including the sub-one-percent cosmic case, which is the only phrasing branch that states a raw distance.
- R17. ODbL attribution for the route dataset appears in Settings → About → Data Sources alongside the existing WeatherKit entry.

---

## Phrasing Matrix

What each surface renders, by the day's entry and the collective's position against it. Figures are real, using the 2026-07-18 collective total of 696.98 km and a 4.2 km walk.

| Day's entry | Settings line | Walk summary line (contributed only) |
|---|---|---|
| Route, reached 2+ times | Together, we've walked the Kumano Kodo 17 times. | Your 4.2 km — a tenth of the Kumano Kodo. 44,540 stayed along it last year. |
| Route, reached once | Together, one Camino Portugués complete. | Your 4.2 km against the Camino Portugués. 100,839 walked it last year. |
| Route, not yet reached | We are 89% of the way to one Camino del Norte. | Your 4.2 km against the Camino del Norte. 21,521 walked it last year. |
| Horizon, 1% or more | We are 1.7% of the way around the Earth. | Your 4.2 km against 40,075 around the Earth. A handful have ever walked it; the first finished in 1974. |
| Horizon, under 1% | 149,599,306 km to the Sun. **(only unit-bearing branch)** | Your 4.2 km against 149,600,000 to the Sun. No one ever will. |

---

## Acceptance Examples

- AE1. **Covers R12.** Given the collective toggle is off, when a walk is saved and its summary opens, no collective line appears — and no prompt to enable the toggle appears either.
- AE2. **Covers R14.** Given the day's entry is a cosmic horizon and the walk was contributed, when the summary opens, the line renders using the horizon's phrasing rather than being skipped.
- AE3. **Covers R16.** Given the pilgrim's unit is miles and the day's entry is a cosmic horizon under one percent, when the Settings line renders, the remaining distance is stated in miles.
- AE4. **Covers R6, R9.** Given a fresh install that has never reached the network, when Settings opens, the daily line renders from bundled data and selects a different entry the following day.
- AE5. **Covers R5.** Given the artifact contains an entry the app cannot parse, when the catalog loads, that entry is dropped and every other entry still selects and renders normally.
- AE6. **Covers R15.** Given a contributed walk that also crosses a personal distance milestone, when the summary opens, both the personal milestone and the collective line render.
- AE7. **Covers R10.** Given a contributed walk on a given UTC day, when the pilgrim views the summary and then opens Settings, both surfaces name the same route.

---

## Success Criteria

- The line changes meaningfully across days rather than sitting for months, and every figure in it is traceable to the upstream dataset.
- A contributing pilgrim finishes a walk and is placed among real pilgrims on a real route, without being told anything untrue about what they moved.
- Adding an eighth route upstream reaches all three surfaces with no app release, no web deploy, and no code change.
- Planning does not need to invent phrasing rules, gating behavior, the unit contract, or what happens on cosmic days.

---

## Scope Boundaries

- Widget surface for the daily route — deferred, not blocked by this.
- Crossings-as-milestones ("since your last walk, together we completed the Camino Portugués") — deferred.
- Reflection questions, season-resonance lines, and full annual notes in Settings — deferred; the dataset carries them, and neither surface renders them in this scope.
- Any map, route geometry, or geographic visualization. The web spec rejected this explicitly, and the product already rules out a global atlas screen.
- Sentence structure and phrase templates as data. Only the per-entry display phrase is data; the surrounding sentence stays in code.
- Localization. The app ships English only today, which is what makes copy-in-data viable at all.
- Automating the bake, and reconciling the stale `docs/superpowers/specs/2026-03-23-pilgrimage-route-packages-design.md`.

---

## Key Decisions

- **UTC day boundary rather than local midnight**: preserves the property that every pilgrim sees the same route on the same day, which is the point of a collective feature. It also keeps the port verifiable against the web's existing pinned test vectors. The cost is that the entry changes at 9am in Japan and late afternoon in California — acceptable for two low-frequency surfaces.
- **Selection runs on-device, not server-side**: the app is used on multi-day walks without signal. Date-seeded selection over cached data keeps working; a server call would not.
- **One shared artifact rather than a per-platform copy**: two baked copies from one upstream is the exact drift pattern the web just spent a PR eliminating. A shared artifact also means Android inherits new routes without a parity port.
- **Display phrases in data, sentence structure in code**: the seven routes do not share a metric — Compostela certificates for the Caminos, foreign overnight visitors for Kumano, all-modes estimates for Shikoku. Generic "N people walked it" copy would be false for two of seven. Per-entry phrasing is the only honest option, and putting it in data keeps future routes release-free.
- **Display phrases carry no units**: the app converts distances per the pilgrim's preference, and a phrase with an embedded distance cannot be converted. This is the constraint most likely to be violated silently by a future curator.
- **Silent when not contributing**: a non-contributed walk did not move the collective. Saying otherwise would fabricate a contribution, and prompting to enable the toggle at that moment would read as a growth nag.
- **Personal milestone and collective line stack**: both are short caption rows. A priority rule would invent a problem that does not exist.
- **The Earth horizon claims "a handful," not a figure**: there is no authoritative count of pedestrian circumnavigations. The World Runners Association — described by the BBC as the sport's de facto governing body — has ratified eight; broader lists run to a few dozen depending on criteria, and the historical record is dominated by wager-driven frauds. The one fixed, citable fact is that Dave Kunst was the first independently verified, finishing 5 October 1974 — five years after Apollo 11. "A handful have ever walked it; the first finished in 1974" is true under every counting method and ages without maintenance.

---

## Dependencies / Assumptions

- `../open-pilgrimages` remains the upstream source of truth, ODbL-1.0 licensed, requiring attribution wherever its data appears.
- The bake that produces the artifact is currently manual and wired to no CI or hook. Making the artifact shared widens its blast radius: one un-run bake would freeze all three surfaces rather than one.
- The collective's distance figure is identical across the two worker endpoints the app and web read (verified 2026-07-18: both return `696.9791986605028`).
- `PilgrimageProgress` has exactly one consumer and no test coverage, so the replacement is contained.
- `../pilgrim-android` mirrors iOS verbatim and will inherit route data automatically once the artifact is shared, but will still need its own port of the selection logic.
- The app ships English only. If localization arrives later, display phrases in data become a translation surface.

---

## Outstanding Questions

### Deferred to Planning

- [Affects R1][Technical] How the artifact reaches the CDN — extend the existing bake, or add a separate publish step.
- [Affects R1][Technical] How the app decides its cached artifact is stale. The app's existing manifests carry a version field; this artifact currently has none, and the bake is deliberately idempotent with no timestamp.
- [Affects R1][Technical] Whether the landing page switches to the CDN copy or keeps its same-origin file as primary with the CDN as the app-facing publication.
- [Affects R16][Technical] Whether to route the new distance rendering through `Pilgrim/Models/Formatting/CustomMeasurementFormatting.swift` or follow the five existing hand-rolled conversion sites. Preference is the formatter.
