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

A turning day is a day on which the sun's ecliptic longitude passes one of the four cardinal angles (0°, 90°, 180°, 270°).

**The existing codebase already has what we need.** `Pilgrim/Models/Astrology/CelestialCalculator.swift` exposes:

- `CelestialCalculator.seasonalMarker(sunLongitude: Double) -> SeasonalMarker?` — returns a case of the existing `SeasonalMarker` enum (`.springEquinox`, `.summerSolstice`, `.autumnEquinox`, `.winterSolstice`, plus 4 cross-quarter days we won't use) if the sun's longitude is within 1.5° of a cardinal angle, else nil.
- `CelestialCalculator.snapshot(for: Date) -> CelestialSnapshot` — returns a snapshot whose `seasonalMarker: SeasonalMarker?` field is already populated. This is how existing code (`LightReadingGenerator`) detects turning days.

**Detection is already a one-liner:** `CelestialCalculator.snapshot(for: date).seasonalMarker`. We don't need a new `solsticesAndEquinoxes(forYear:)` method.

**Only one new `CelestialCalculator` method is required:**

- `sunriseAzimuth(at: CLLocationCoordinate2D, on: Date) -> CLLocationDirection?` — the compass azimuth (degrees from true north) where the sun rises on a given date at a given location. Nil at polar latitudes where the sun doesn't rise. Used only for the sunrise-azimuth ray on the active walk map.

**Note on existing user-facing touchpoint:** the app already surfaces seasonal markers via the `LightReading` system (see `LightReadingGenerator.swift:91–95`) — a ~4% chance of a seasonal-marker-themed reading on turning days. That feature continues unchanged. The Four Turnings visual language (banner, inline markers, route color, ray, kanji) stacks on top of it; the two channels are independent and complementary.

### Hemisphere Handling

The kanji 冬至 literally means *winter solstice*. For a user in Sydney, the December solstice is their *summer* solstice — so mapping the December astronomical moment to 冬至 is wrong for them.

**Hemisphere is determined per-context, not globally:**

- **For today's banner** (and any "right now" query): use the hemisphere of the user's **most recent walk's starting coordinate**. Positive latitude → northern, negative → southern. If no walks exist (new user), default to northern.
- **For a historical walk** (inline scroll marker, summary date-suffix, route color on archived walks): use the hemisphere of **that specific walk's starting coordinate**. This way, a user who walks in Bogotá two years ago then moves to Sydney still sees their Bogotá walks classified as northern-hemisphere at the time, and new Sydney walks as southern. No re-writing history.
- **For the active walk mid-session**: use the hemisphere of the walk's first captured location sample. If the user somehow crosses the equator mid-walk (rare), the classification doesn't change.

The Astronomical Moment → Hemisphere-Specific Turning mapping:

| Astronomical moment | Northern hemisphere | Southern hemisphere |
|---|---|---|
| March equinox | 春分 / Spring equinox | 秋分 / Autumn equinox |
| June solstice | 夏至 / Summer solstice | 冬至 / Winter solstice |
| September equinox | 秋分 / Autumn equinox | 春分 / Spring equinox |
| December solstice | 冬至 / Winter solstice | 夏至 / Summer solstice |

The color palette maps to the *seasonal* kanji, not the astronomical month. So a southern-hemisphere user on December solstice sees the **summer-solstice gold**, not the winter blue.

Because `SeasonalMarker` returned by `CelestialCalculator.seasonalMarker(sunLongitude:)` is the astronomical marker (always northern-hemisphere-named), the hemisphere-aware mapping is applied as a view-level translation. A helper — see `TurningDayService` below — takes the astronomical `SeasonalMarker` plus a hemisphere and returns the seasonally-correct turning.

No user-facing hemisphere setting is exposed in v1. The per-walk classification is good enough for shipping; if it misfires, users can course-correct by walking once in their current location.

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

Three additions to `InkScrollView`:

1. **Turning-day banner** rendered at the top of `scrollContent`, **independent of walk history** (critical — the existing `journeySummaryHeader` is gated by `if !snapshots.isEmpty`, which would hide the banner from new users on their first turning day). The banner appears whenever today is a turning day, regardless of how many walks the user has.

   On a turning day, a single line reads:

   > *Today the sun stands still · 冬至*

   The copy varies per turning:
   - Solstices: *"Today the sun stands still · [kanji]"*
   - Equinoxes: *"Today, day equals night · [kanji]"*

   The kanji is rendered in the turning's color. Typography and exact placement to be tuned during implementation (likely `Constants.Typography.body` or `.caption`, placed with enough breathing room above `journeySummaryHeader` to feel like a distinct element). The banner fades out at local midnight when the turning day ends.

2. **Inline turning marker at walk-dot position** — a new extension file `InkScrollView+TurningMarkers.swift`, mirroring `InkScrollView+LunarMarkers.swift`. The lunar pattern renders small (10×10) annotations **inline on the scroll at each walk's dot position** (not in a side margin). The turning marker mirrors that: for every walk in the user's history whose start date was a turning day, a faint kanji glyph is drawn at that walk's dot position.

   Permanent. A user scrolling through 3 years of history sees up to 12 kanji glyphs scattered inline through their scroll — a visual timeline of the turnings they walked.

   The glyph uses the turning's color (per-walk hemisphere) and is marked `.accessibilityHidden(true)` (VoiceOver navigates via the dot itself).

3. **Segment/dot color override** — the existing `pathSegmentColor(index:)` currently takes only an integer index and has no direct access to the walk's snapshot or date. To honor turning-day coloring, the simplest path is to extend its access: either change the signature to `pathSegmentColor(index:snapshot:)` (small refactor) or pre-compute a `[Int: Color]` override map in `scrollContent(width:height:)` where the snapshot is available. Either way, the end state is: if the segment's walk falls on a turning day, the color is the turning's color at slightly softened opacity so it blends with the scroll palette rather than popping.

   Uses the per-walk hemisphere classification (not the user's current hemisphere).

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

### Existing Types (Reused)

- **`SeasonalMarker`** — already exists at `Pilgrim/Models/Astrology/AstrologyModels.swift:139` with cases `.springEquinox`, `.summerSolstice`, `.autumnEquinox`, `.winterSolstice` (plus 4 cross-quarter days we ignore for this feature). Already has a `name` property. We add computed properties via extension — see "New Extensions" below.

### New Types

- **`Hemisphere`** — simple enum `.northern / .southern`, derived from `CLLocationCoordinate2D.latitude`. Negative → southern; otherwise northern.

- **`TurningDayService`** — helper (likely `enum` with static methods, given stateless nature) that wraps detection with hemisphere-aware mapping:
  - `static func turning(for date: Date, at coordinate: CLLocationCoordinate2D?) -> SeasonalMarker?` — takes a date and optional coordinate, returns the seasonally-correct marker for that context. Used by historical walks (coordinate from the walk itself), by today's banner (coordinate from most-recent walk), and by the active walk (coordinate from first location sample). If coordinate is nil, assumes northern hemisphere.
  - Internally translates the astronomical `SeasonalMarker` returned by `CelestialCalculator.snapshot(for:).seasonalMarker` through the hemisphere mapping in the Hemisphere Handling section.
  - Caching: the per-date snapshot call is cheap; trivially memoize by date if profiling shows it matters.

### New Extensions on `SeasonalMarker`

In a new file `Pilgrim/Models/Astrology/SeasonalMarker+Turnings.swift`:

- `var kanji: String?` — "春分" / "夏至" / "秋分" / "冬至" for the 4 turnings; nil for the cross-quarter days (which this feature doesn't surface).
- `var bannerText: String?` — *"Today, day equals night"* (equinoxes) or *"Today the sun stands still"* (solstices); nil for cross-quarter. Localized via `LS.swift`.
- `var color: Color?` — the walking-segment override color; nil for cross-quarter.
- `var isTurning: Bool` — true iff the case is one of the 4 main turnings.

VoiceOver-accessible label uses the existing `name` property ("Spring Equinox" etc.), which needs to flow through `LS.swift` for localization.

### CelestialCalculator Extensions

**One new public method** (existing detection is already sufficient):

- `static func sunriseAzimuth(at coordinate: CLLocationCoordinate2D, on date: Date) -> CLLocationDirection?` — computes the compass bearing (degrees from true north) of sunrise. Combines the sun's declination on the date with the observer's latitude using the standard sunrise-azimuth formula (`cos(azimuth) = sin(declination) / cos(latitude)` adjusted for hemisphere and atmospheric refraction). Returns nil at extreme latitudes where the sun doesn't rise that day.

### File Touch List

**New files:**
- `Pilgrim/Models/Astrology/SeasonalMarker+Turnings.swift` — extensions on the existing enum (kanji / bannerText / color / isTurning)
- `Pilgrim/Models/Astrology/TurningDayService.swift` — hemisphere-aware detection helper
- `Pilgrim/Scenes/Home/InkScrollView+TurningMarkers.swift` — inline kanji glyphs at turning-day dot positions, mirroring `InkScrollView+LunarMarkers.swift`
- `Pilgrim/Support Files/Assets.xcassets/turningJade.colorset/` (and `turningGold`, `turningClaret`, `turningIndigo`) — 4 new color assets, each with light + dark variants
- `UnitTests/SeasonalMarkerTurningTests.swift` — extension properties, hemisphere mapping, edge cases (date ±1 day, cross-quarter returns nil)
- `UnitTests/CelestialCalculatorSunriseAzimuthTests.swift` — azimuth accuracy vs published reference data; polar return nil

**Modified files:**
- `Pilgrim/Models/Astrology/CelestialCalculator.swift` — adds `sunriseAzimuth(at:on:)`
- `Pilgrim/Scenes/Home/InkScrollView.swift` — adds turning banner (at top of `scrollContent`, outside the `if !snapshots.isEmpty` gate); `pathSegmentColor` adjusts to accept snapshot access for turning-day override
- `Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift` — adds kanji watermark at bottom-center over the map + sunrise-ray overlay
- `Pilgrim/Views/PilgrimMapView.swift` — route color match expression's default (walking) branch becomes conditional on turning-day classification for that walk; adds line annotation for the sunrise-azimuth ray
- `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift` — `dateTitleFormatted` appends kanji for turning-day walks
- `Pilgrim/Scenes/WalkShare/WalkShareViewModel.swift` + `ShareService.swift` — adds `turningDay` to the share payload (forward-compatible; worker doesn't need to consume it immediately)
- `Pilgrim/Models/LS.swift` — new localized strings for banner copy and VoiceOver labels

**Unchanged (but noted):**
- `Pilgrim/Models/LightReading/LightReadingGenerator.swift` — already surfaces seasonal-marker readings on turning days. No changes needed. The Four Turnings feature layers visual acknowledgments on top of this existing textual one.

## Accessibility

- **VoiceOver**: the home banner reads the full label ("Today, day equals night. Autumn equinox."). The kanji watermark and scroll-margin glyphs are marked `.accessibilityHidden(true)` — they're decorative. The date title suffix *is* read, rendering as "March 20, 2026, Spring equinox" for VoiceOver rather than the raw kanji.
- **Dynamic Type**: the home banner and date suffix scale with Dynamic Type; the kanji watermark is a fixed decorative element (scaling it would break layout).
- **Reduce Motion**: no motion in this feature to reduce. The banner fade at midnight is a date-based state change, not an animation.
- **Color contrast**: each of the 4 turning colors will be verified against the parchment background for WCAG AA contrast in both light and dark modes. Dark-mode variants of each color are required in the Asset Catalog.

## Test Plan

### Unit tests

1. `TurningDayService.turning(for:at:)` — returns the correct hemisphere-mapped turning for known historical dates (e.g., June solstice 2024 at a northern coordinate returns `.summerSolstice`; same date at a southern coordinate returns `.winterSolstice`).
2. `TurningDayService.turning(for:at:)` returns nil for non-turning dates and for the cross-quarter astronomical markers (imbolc / beltane / lughnasadh / samhain are out of scope).
3. `Hemisphere` derivation: positive latitude → `.northern`, negative → `.southern`, zero and nil coordinate → `.northern` (consistent default).
4. `SeasonalMarker.kanji` / `.bannerText` / `.color` return correct values for the 4 turnings and nil for cross-quarter cases.
5. `CelestialCalculator.sunriseAzimuth(at:on:)` — returns ~90° (due east) at the equator on equinox, returns extreme values at high latitudes on solstice (e.g., ~128° summer solstice at 60° N), returns nil above the arctic circle on winter solstice.
6. Walk spanning local midnight: a walk starting at 23:55 on a turning day remains classified as a turning-day walk even though most of its route is recorded the next day (classification uses start date).

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
