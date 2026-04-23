# Four Turnings — Design Spec

## Summary

Acknowledge the four astronomical turning points of the year — the two solstices and two equinoxes — with quiet, distributed touches across Pilgrim: a banner on the home ink-scroll, a permanent scroll-margin glyph marking today forever, a faint kanji watermark during the walk itself, a walking-segment route color, a sunrise-azimuth ray on the live map, and a kanji suffix on the walk summary's date title.

No badges. No push notifications. No achievements. The app simply knows when the sun stands still or balance returns, and marks the day lightly.

## Motivation

Pilgrim is a walking-as-practice app. The solstices and equinoxes are the oldest spiritual walking days in human history — Stonehenge alignments, Newgrange's dawn chamber, Camino peaks at Mid-Summer, Shinto equinox visits to ancestral graves. The app already has the vocabulary for celestial time (lunar markers in the ink scroll, a `CelestialCalculator`, a seasonal color palette for the ink). It has been quietly waiting for this.

The goal is *not* to call attention to itself on these four days. The goal is for the user — if they happen to walk on a turning — to sense that the day matters, through peripheral visual details that feel like the app has always known. Users who walk every turning accumulate a permanent, beautiful marked history over years.

## Non-Goals (for v1)

- The Four Seals / goshuin-style collection for completing all four turnings in a year (deferred)
- Turning of the Wheel annual mandala visualization (deferred)
- Sunrise-alignment challenge or walking-window suggestions (deferred)
- Collective global simultaneous-walk feature on solstice (deferred)
- Weather-aware whisper variants on turning days (deferred)
- Year-in-walks compendium artifact (deferred)
- Day-of special whispers from the R2 catalog (deferred — possible v1.1 add)
- User-facing hemisphere setting (v1 auto-detects from walk history)

## Design

### Date Computation

A turning day is the **local calendar date** containing the astronomical moment of that year's solstice or equinox. The moment varies year to year (e.g., December solstices fall between Dec 20–22).

Pilgrim already has `CelestialCalculator` in the codebase (referenced by `CelestialCalculatorTests` in the unit test target). It must support — or be extended to support — these two queries:

- `solsticesAndEquinoxes(forYear: Int) -> [Date]` — returns the 4 astronomical moments for a given Gregorian year. Used to determine whether today is a turning day.
- `sunriseAzimuth(at: CLLocationCoordinate2D, on: Date) -> CLLocationDirection?` — the compass azimuth (degrees from true north) where the sun rises on a given date at a given location. Nil at poles where the sun doesn't rise. Used for the sunrise-azimuth ray on the active walk map.

Detection happens at runtime each time the feature is queried: "does today's local date contain one of the 4 astronomical moments for this year?" If yes, we know which turning it is.

### Hemisphere Handling

The kanji 冬至 literally means *winter solstice*. For a user in Sydney, the December solstice is their *summer* solstice — so mapping the December astronomical moment to 冬至 is wrong for them.

The app detects the user's hemisphere from their **most recent walk's starting coordinate**. If the latitude is negative, hemisphere is southern; otherwise northern. If no walks exist yet (new user), default to northern.

For southern-hemisphere users, the kanji and seasonal labels are mirrored:

| Astronomical moment | Northern-hemisphere kanji & label | Southern-hemisphere kanji & label |
|---|---|---|
| March equinox | 春分 / Spring equinox | 秋分 / Autumn equinox |
| June solstice | 夏至 / Summer solstice | 冬至 / Winter solstice |
| September equinox | 秋分 / Autumn equinox | 春分 / Spring equinox |
| December solstice | 冬至 / Winter solstice | 夏至 / Summer solstice |

The color palette maps to the *seasonal* kanji, not the astronomical month. So a southern-hemisphere user on December solstice sees the **summer-solstice gold**, not the winter blue.

No user-facing hemisphere setting is exposed in v1. The auto-detect is good enough for shipping; if it misfires, users can course-correct by walking once in their current location.

### Color Palette

Four new colors, all tuned to match the existing wabi-sabi muted palette (saturations comparable to `moss`, `rust`, `dawn`):

| Turning (kanji) | Color name | Approximate hex | Character |
|---|---|---|---|
| **春分** Spring equinox | `turningJade` | `#74B495` | muted jade — thaw, balance |
| **夏至** Summer solstice | `turningGold` | `~#C9A646` | dusty honey-gold — peak light |
| **秋分** Autumn equinox | `turningClaret` | `~#8B4455` | muted wine — harvest, moon festival |
| **冬至** Winter solstice | `turningIndigo` | `#2377A4` | dusty blue — longest night |

Final hex values are to be fine-tuned during implementation against the rendered parchment background and the existing activity colors. The spec-level commitment is the *character* and *saturation level* — each color must sit at or below the saturation of `moss`/`rust`/`dawn` to preserve the wabi-sabi restraint.

**Autumn's claret** is intentionally chosen over the instinctive "orange" to avoid collision with `rust` (talking) and `dawn` (meditating), both of which are orange-family warms.

### Home: InkScrollView

Two additions to `InkScrollView`:

1. **Turning-day banner** inside `journeySummaryHeader` (the existing top-of-scroll summary). On a turning day, a single line appears above the existing summary content:

   > *Today the sun stands still · 冬至*

   The copy varies per turning:
   - Solstices: *"Today the sun stands still · [kanji]"*
   - Equinoxes: *"Today, day equals night · [kanji]"*

   The kanji is rendered in the turning's color. The text uses `Constants.Typography.body` or `.caption` (implementation choice; probably body). The banner fades out at local midnight when the turning day ends.

2. **Scroll-margin glyph** — a new extension file `InkScrollView+TurningMarkers.swift`, mirroring the pattern of `InkScrollView+LunarMarkers.swift`. For every day in the user's walk history that was a turning day, a faint kanji glyph is drawn in the scroll's margin at that row's vertical position. Permanent. A user scrolling through 3 years of history sees 12 kanji glyphs scattered through their scroll — a visual timeline of the turnings they were present for.

3. **Segment/dot color override** — the existing `pathSegmentColor(index:)` logic gains a conditional: if the segment's walk fell on a turning day, the color is overridden to that turning's color (at slightly softened opacity so it blends into the scroll's overall palette rather than popping).

### Active Walk

Three layered changes to the active walk scene:

1. **Kanji watermark** — a faint character positioned at bottom-center of the map, just above where the collapsed stats sheet peeks. `Color.stone.opacity(0.15–0.2)`, approximately 12pt, using the kanji for today's turning. Renders only on turning days. Placed as an overlay on the map, does not interact, does not scroll.

2. **Walking-route color override** — the Mapbox route layer at `PilgrimMapView.swift:273–281` currently uses a match expression on `activityType`: `meditating` → `dawn`, `talking` → `rust`, default → `moss`. On turning days, the default (walking) branch is replaced with the turning's color. Meditation and talking colors are unchanged, preserving activity-type legibility.

3. **Sunrise-azimuth ray** — a faint line drawn from the user's location puck outward in the compass direction of today's sunrise. Length approximately 150pt in screen space (rendered in map-projection coordinates so it scales with zoom), opacity ~0.15, fading to transparent at the tip. Uses `CelestialCalculator.sunriseAzimuth(at:on:)` with the user's current coordinate and today's date.

   The ray is static for the whole turning day (doesn't rotate with time — the azimuth is a daily fact, not a moment-to-moment one). If the user moves to a meaningfully different latitude mid-walk (rare), it could be recomputed; for v1, compute once at walk start and leave fixed.

   The ray should use the turning's color at higher transparency, so it coheres with the route color visually.

### Post-Walk Summary

Two additions to `WalkSummaryView`:

1. **Date title kanji suffix** — the existing `dateTitleFormatted` string becomes:

   > *March 20, 2026 · 春分*

   when the walk fell on a turning day. Kanji rendered in the turning's color, same font size as the rest of the title (Constants.Typography.heading, probably).

2. **Route color** — the summary map uses the same route-layer expression as the active walk, so walking segments on a turning-day walk are already drawn in the turning color. No separate wiring needed beyond the `PilgrimMapView` change; the summary view reuses the same component.

**Not in the summary**: the sunrise-azimuth ray. The ray is a live-walk feature — it orients the user in the moment. The archival summary doesn't need it.

### Shared HTML Page (pilgrim-worker handoff)

Out of scope for this iOS spec, but flagging the handoff contract so the worker PR can follow cleanly:

- The walk share payload gets a new optional field: `turningDay: "winter-solstice" | "spring-equinox" | "summer-solstice" | "autumn-equinox" | null`.
- The iOS app populates it when calling `ShareService.share(...)` using the same detection logic as the rest of the feature.
- The worker's HTML template checks for the field. If present, renders the route color using a matching palette and places the kanji near the date header on the hosted page.
- Worker-side changes tracked as a follow-up; iOS ships the payload field even if the worker doesn't consume it yet (forward-compatibility).

## Technical Architecture

### New Types

- **`TurningDay`** — enum in `Pilgrim/Models/` with cases `.springEquinox`, `.summerSolstice`, `.autumnEquinox`, `.winterSolstice`. Methods:
  - `static func forDate(_ date: Date, hemisphere: Hemisphere) -> TurningDay?` — returns the turning if the date is one, accounting for hemisphere (the same astronomical moment maps to different turnings in north vs south).
  - `var kanji: String` — "春分" / "夏至" / "秋分" / "冬至"
  - `var label: String` — "Spring equinox" / "Summer solstice" / etc.
  - `var bannerText: String` — *"Today, day equals night"* or *"Today the sun stands still"*
  - `var color: Color` — the walking-segment color for this turning

- **`Hemisphere`** — simple enum `.northern / .southern`, derived from `CLLocationCoordinate2D.latitude`.

- **`TurningDayService`** (or similar helper) — caches the 4 astronomical moments for the current year so we don't recompute on every view body evaluation. Invalidates at year boundary.

### CelestialCalculator Extensions

Two new public methods (add to the existing class):

- `solsticesAndEquinoxes(forYear year: Int) -> [Date]` — uses standard astronomical formulas (Jean Meeus *Astronomical Algorithms* chapter 27 for equinox/solstice times). Returns 4 dates in UTC.
- `sunriseAzimuth(at coordinate: CLLocationCoordinate2D, on date: Date) -> CLLocationDirection?` — computes the compass bearing of sunrise. Combines the sun's declination on the date with the observer's latitude using the sunrise-azimuth formula. Returns nil at extreme latitudes where the sun doesn't rise.

### File Touch List

**New files:**
- `Pilgrim/Models/TurningDay.swift` — the enum + helpers
- `Pilgrim/Models/TurningDayService.swift` — caching + hemisphere detection
- `Pilgrim/Scenes/Home/InkScrollView+TurningMarkers.swift` — scroll-margin glyph rendering
- `Pilgrim/Support Files/Assets.xcassets/turningJade.colorset/` (and three more) — the 4 new color assets, each with light and dark variants
- `UnitTests/TurningDayTests.swift` — date detection, hemisphere mapping, edge cases
- `UnitTests/CelestialCalculatorSolsticeTests.swift` — accuracy of solstice/equinox dates and sunrise azimuth within reasonable tolerance against known reference data

**Modified files:**
- `Pilgrim/Scenes/Home/InkScrollView.swift` — `journeySummaryHeader` gets the conditional banner; `pathSegmentColor(index:)` gains turning-day override
- `Pilgrim/Scenes/Home/HomeView.swift` — may need to thread the turning info into InkScrollView (if the service lives higher up)
- `Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift` — adds kanji watermark + sunrise-ray overlay
- `Pilgrim/Views/PilgrimMapView.swift` — route color match expression gains turning-day branch; new overlay layer for the sunrise ray
- `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift` — date title suffix
- `Pilgrim/Scenes/WalkShare/WalkShareViewModel.swift` + `ShareService.swift` — adds `turningDay` to the share payload (forward-compatible)
- `Pilgrim/Models/Astronomy/CelestialCalculator.swift` (or wherever it lives) — the two new methods

## Accessibility

- **VoiceOver**: the home banner reads the full label ("Today, day equals night. Autumn equinox."). The kanji watermark and scroll-margin glyphs are marked `.accessibilityHidden(true)` — they're decorative. The date title suffix *is* read, rendering as "March 20, 2026, Spring equinox" for VoiceOver rather than the raw kanji.
- **Dynamic Type**: the home banner and date suffix scale with Dynamic Type; the kanji watermark is a fixed decorative element (scaling it would break layout).
- **Reduce Motion**: no motion in this feature to reduce. The banner fade at midnight is a date-based state change, not an animation.
- **Color contrast**: each of the 4 turning colors will be verified against the parchment background for WCAG AA contrast in both light and dark modes. Dark-mode variants of each color are required in the Asset Catalog.

## Test Plan

### Unit tests

1. `TurningDay.forDate(_:hemisphere:)` — returns the correct turning for known historical dates (e.g., 2024-06-20 is summer solstice in Northern, winter in Southern).
2. `TurningDay.forDate(_:hemisphere:)` returns nil for non-turning dates.
3. Hemisphere detection: positive latitude → .northern, negative → .southern, zero → .northern (arbitrary but consistent).
4. `CelestialCalculator.solsticesAndEquinoxes(forYear:)` — each returned date falls within ±1 day of published astronomical references for that year.
5. `CelestialCalculator.sunriseAzimuth(at:on:)` — returns ~90° (due east) at the equator on equinox, returns extreme values at high latitudes on solstice, returns nil above the arctic circle on winter solstice.
6. Cross-year: a year boundary during a walk does not crash the service; cache invalidates cleanly.

### Manual checks

1. Launch on a non-turning day — no banner, no watermark, no margin glyph, default route color. Regression check.
2. Simulate a turning day by stubbing the system date (or a debug launch arg) — verify:
   - Home screen shows the banner and margin glyph at today's scroll position
   - Starting a walk shows the kanji watermark at bottom-center and the sunrise-azimuth ray from the puck
   - Walking segments render in the turning color; meditation stays dawn, talking stays rust
   - Finishing the walk shows the kanji-suffixed date in the summary and the turning-color route
3. Hemisphere test: simulate a walk at latitude -33 (Sydney), then simulate June solstice — verify the app shows 冬至 (winter) not 夏至 (summer). Reset.
4. Dark mode: each of the 4 colors renders correctly against dark parchment; no halo/inversion issues.
5. VoiceOver: banner, date title, and scroll-margin glyphs read as expected.
6. A walk that *crosses* local midnight from a turning day into a non-turning day: the walk is recorded as a turning-day walk because the walk's start date was the turning day. Verify this tie-breaker in the helper.

### Edge cases

- Polar user on winter solstice: sunrise azimuth is nil — the sunrise-azimuth ray simply isn't drawn. No crash.
- Year boundary: a walk starting at 23:55 on December 31 of a turning year should still register the turning-day classification even though most of the walk is in the following year.
- User with no walk history: hemisphere defaults to northern. First walk anywhere establishes hemisphere going forward.
- User who moves hemispheres (traveler): hemisphere updates based on most-recent-walk coordinate. Their next turning-day walk in the new hemisphere shows the correct kanji. No backfill of historical walks (those stay as they were classified at the time).

## Decisions & Tradeoffs

- **No push notifications.** Requires permission, risks noise. The home-screen banner rewards users who open the app; users who don't, don't miss anything bad (the turning day just passes quietly — which is arguably true to the contemplative nature).
- **Hemisphere auto-detect from walk history over user-facing setting.** Fewer settings = less friction. If it misfires, users course-correct by walking once in their actual location. A hemisphere setting can be added in v1.1 if the auto-detect proves unreliable in practice.
- **Kanji over western text.** 春分/夏至/秋分/冬至 are visually elegant and part of a long walking-meditation tradition. VoiceOver reads the English label, so accessibility is preserved.
- **Claret for autumn, not orange.** Deliberately avoids hue-collision with `rust` (talking) and `dawn` (meditating). East Asian autumn-moon-festival motifs support wine/purple; the app's existing vocabulary accepts it.
- **Walking-segment color override only.** Meditation and talking keep their existing colors so activity-type legibility survives. The turning is carried by walking — which is most of a walk — which is enough signal.
- **Scroll-margin glyph is permanent.** Users who walk many turnings accumulate a long-term artifact in their history. This is the feature's long-tail reward.
- **Sunrise azimuth, not sunset.** Only one ray to avoid visual clutter. Sunrise is the more-walked time (especially in summer). Sunset rays could be added in v1.1 as an enhancement if users want them.
- **Turning-color applies to shared HTML too.** Preserves visual continuity across surfaces (active walk → summary → shared page). Requires a small payload change and worker-side follow-up.
- **No achievement/badge/streak framing.** Pilgrim is not that kind of app.

## Open Questions (for implementation)

- Exact hex values for the 4 colors (light + dark mode variants) — tune against the rendered parchment background during implementation.
- Exact font size and position of the kanji watermark on the active walk — depends on the stats sheet's current peek height, which varies. Position relative to the sheet, not absolute.
- Sunrise-azimuth ray rendering: Mapbox line annotation vs. custom `MapOverlay` vs. a SwiftUI overlay that does its own projection — implementation choice. The line annotation approach is probably simplest.
- Caching strategy for `solsticesAndEquinoxes(forYear:)` — in-memory is fine; 4 dates per year is trivial. Invalidate on year boundary.
- Whether the home banner copy should vary year to year or stay static — v1: static per-turning copy is fine.
