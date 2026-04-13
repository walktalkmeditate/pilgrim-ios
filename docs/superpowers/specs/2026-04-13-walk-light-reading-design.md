# Walk Light Reading — Design

**Date:** 2026-04-13
**Status:** Draft for review
**Context:** Sharing a walk should feel like a small ritual with a gift attached. This spec adds a "light reading" to the post-walk share area — a single true sentence about the astronomical conditions at the moment the walk happened. Every walk gets one. It's rendered from real orbital math and the walk's own start location and time, so it's always deterministic, always factual, and never feels canned.

## Goal

After the user taps Share, surface one sentence that describes the sky at the moment they walked. Examples of what it could say (one per tier, showing the range):

- *"This walk happened during a total lunar eclipse. The moon turned red for 84 minutes."*
- *"You walked under the October supermoon — the full moon at its closest to Earth this orbit."*
- *"You walked on the autumn equinox — the year tipping toward winter."*
- *"This walk happened on the peak night of the Perseids — up to 100 meteors per hour."*
- *"The full moon watched over this walk — 98% illuminated."*
- *"This walk happened under the dark of the new moon. Stars at their clearest."*
- *"Your walk began 14 minutes before sunrise. The sun rose at 6:23."*
- *"You walked through civil twilight — the blue hour between day and night."*
- *"You walked through the last hour of golden light."*
- *"You walked under a waxing gibbous moon, 78% illuminated."*

The feature is:
- **True.** Every fact is computed from orbital math, the walk's start coordinates, and the walk's timestamp. Nothing is invented.
- **Deterministic.** Same walk → same reading, forever.
- **Local.** Zero network. Zero ML. Reads entirely from data the walk already carries.
- **Independent of celestial awareness preference.** This is astronomy (moon phase, sunrise, solstice proximity), not astrology (zodiac sign interpretation). Works for everyone. Users with the preference enabled get slightly richer phrasings that can reference constellations; users with it disabled get pure astronomy with no zodiac naming.

## UX

### Placement
A new `WalkLightReadingCard` view in `WalkSummaryView`'s VStack, inserted **directly above `shareCard`** (around line 71). The card is conditionally present — absent from the layout until the first Share tap, appears on reveal.

### Lifecycle
1. **On `WalkSummaryView.onAppear`**: generate the `LightReading` synchronously from the walk (it's fast, <10ms worst case — see "Generation" below). Store in `@State var lightReading: LightReading?`.
2. **Before first share**: card is not in the view tree. Reveal state is tracked in a single UserDefaults key, `"sharedWalkUUIDs"`, holding an `[String]` of UUIDs that have been shared at least once. On appear, initialize `@State var hasRevealedLightReading = sharedUUIDs.contains(walkUUID)`.
3. **On Share button tap** (not on share-sheet completion — see rationale in haiku spec rev): insert `walkUUID` into the set, write back to UserDefaults, and animate the card in with `withAnimation(.easeInOut(duration: 1.2)) { hasRevealedLightReading = true }` + a subtle scale bump from 0.97 to 1.0.
4. **On subsequent views of the same walk**: the set already contains the UUID, so the card renders immediately at full opacity. User can scroll back to it anytime.
5. **Long-press the card**: haptic + copies the reading sentence to the pasteboard.

**Why a single key instead of one-per-walk**: UserDefaults performance degrades past ~1000 keys. A power-user with five years of walks could accumulate thousands of per-walk flags. Holding the set in a single `[String]`-encoded key bounds UserDefaults to O(1) entries regardless of walk count and keeps serialization cheap (set membership checks run over a Swift `Set<String>` built from the stored array).

### What the card shows
```
┌─────────────────────────────────────────┐
│                                         │
│          [SF Symbol: sunrise]           │
│                                         │
│    Your walk began 14 minutes before    │
│      sunrise. The sun rose at 6:23.     │
│                                         │
│           — a light reading             │
│                                         │
└─────────────────────────────────────────┘
```

- Parchment background (`Color.parchment`), body serif typography
- Center-aligned, two-to-three-line reading (never more than 3 lines of text)
- Small SF Symbol header chosen by the reading's **tier** (see "Glyph → tier mapping" table below). Rendered at `.title2` weight, stone color, accessibility-hidden since it's decorative.
- Footer caption: "— a light reading"
- No decoration, no animation after reveal

### What it is NOT
- **Not** embedded in the shared URL or Goshuin/Etegami artifacts. Private reward for the sharer.
- **Not** a modal.
- **Not** regenerable or randomizable. Same walk always gives the same reading.
- **Not** gated by `celestialAwarenessEnabled`. The preference only controls which phrasing pool is used (see "Phrasings" below).

## Data model

```swift
struct LightReading {
    let sentence: String       // the final rendered text
    let tier: Tier             // which priority tier fired
    let symbolName: String     // SF Symbol name, e.g. "moon.stars.fill"

    // Enum order IS the priority order (rarest → most common).
    // Lower raw value = higher priority = fires first.
    enum Tier: Int, Comparable {
        case lunarEclipse      // partial or total lunar eclipse on the walk date (~1-3% of walks)
        case supermoon         // full moon within ±3 days of perigee (~5-7%)
        case seasonalMarker    // equinox / solstice / cross-quarter, within ±24h (~4%)
        case meteorShowerPeak  // walk date is within ±1 day of a major shower peak (~5-7%)
        case fullMoon          // 95%+ illumination, not already claimed by eclipse or supermoon (~10%)
        case newMoon           // ≤5% illumination (~10%)
        case deepNight         // sun ≤-18°, moon ≤10% illumination (~5-15%)
        case sunriseSunset     // walk began within ±30 min of sunrise or sunset (~15-25%)
        case twilight          // walk entirely in civil/nautical/astronomical twilight (~15-25%)
        case goldenHour        // walk overlapped the hour around sunrise/sunset (~20-30%)
        case moonPhase         // baseline — always fires, never embarrassingly generic

        // Swift does NOT auto-synthesize Comparable for Int-raw enums.
        // Must provide the implementation explicitly so `tier1 < tier2`
        // works for the priority-ladder sort.
        static func < (lhs: Tier, rhs: Tier) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}
```

### Glyph → tier mapping (SF Symbols)

Instead of Unicode characters (which render inconsistently across fonts and sometimes don't exist in the Cormorant Garamond / Lato stack the app uses), the glyph header on the card is an SF Symbol. SF Symbols are guaranteed to render on iOS, respect Dynamic Type, and respect color schemes.

| Tier | SF Symbol | Rationale |
|---|---|---|
| `lunarEclipse` | `moon.circle.fill` | filled disc = full obscuration |
| `supermoon` | `moon.stars.fill` | moon with surrounding stars, emphasized |
| `seasonalMarker` (equinox) | `circle.lefthalf.filled` | half-filled disc = balance |
| `seasonalMarker` (solstice) | `sun.max` (summer) / `moon.fill` (winter) | light vs. dark extreme |
| `seasonalMarker` (cross-quarter) | `circle.dashed` | midpoint marker |
| `meteorShowerPeak` | `sparkles` | brief flashes across the sky |
| `fullMoon` | `moon.stars.fill` | same as supermoon, but supermoon fires first for supermoon nights |
| `newMoon` | `circle` | empty outline = no illumination |
| `deepNight` | `sparkle` (singular) | a single point of light in darkness |
| `sunriseSunset` | `sunrise` or `sunset` (depending on which edge) | literal |
| `goldenHour` | `sun.haze` | diffused warm light |
| `twilight` | `sun.horizon` | sun at the horizon |
| `moonPhase` | `moon.fill`, `moon`, `circle.bottomhalf.filled`, etc. | chosen per phase sub-case |

The `symbolName` field on `LightReading` is just a `String`, allowing the generator to pick the exact symbol per walk without a closed enum set. Tests assert that every returned symbol name resolves to a real SF Symbol.

## Priority ladder

The generator evaluates tiers in rarity order (rarest first) and picks the **first one that fires**. The ordering reflects how rare each condition is for a random walker. Rarer conditions win because they are more striking to surface — *"you walked during a lunar eclipse"* deserves top billing over *"you walked under a full moon"* even though both are technically true on an eclipse night.

Rarity estimates assume a walker who walks ~3 times per week across all hours of day, averaged over a year.

Tiers 1–4 evaluate date matching against the walker's **local date** (derived from `Calendar.current`), not UTC — see "Date matching: local, not UTC" below for the rule and rationale. Tiers 5–10 use the walk's actual UTC timestamp with location-based sunrise/sunset math, which is already time-zone correct by construction.

1. **`lunarEclipse`** — is the walker's local date for `walk.startDate` during a lunar eclipse (partial, total, or penumbral) from the pre-computed eclipse table? ~1-3% of walks.
2. **`supermoon`** — is the walker's local date within ±3 days of a supermoon event from the pre-computed perigee-full-moon table? ~5-7%.
3. **`seasonalMarker`** — is the walker's local date within ±24h of an equinox, solstice, or cross-quarter day? Use `CelestialCalculator.seasonalMarker(sunLongitude:)` (already exists). ~4%.
4. **`meteorShowerPeak`** — is the walker's local date within ±1 day of a major meteor shower peak from the recurring annual catalog? ~5-7%.
5. **`fullMoon`** — lunar illumination ≥95%? ~10% (excluding eclipse/supermoon cases which fired earlier).
6. **`newMoon`** — lunar illumination ≤5%? ~10%.
7. **`deepNight`** — sun altitude ≤ -18° (astronomical night) AND moon illumination ≤ 10%? ~5-15%.
8. **`sunriseSunset`** — `walk.startDate` is within ±30 minutes of the computed sunrise or sunset time at the walk's start coordinates? ~15-25%.
9. **`twilight`** — did the walk occur entirely during civil twilight (sun between -6° and 0°), nautical (-12° to -6°), or astronomical (-18° to -12°)? ~15-25%.
10. **`goldenHour`** — walk started within the golden hour window (sun altitude between -6° and +6°)? ~20-30%.
11. **`moonPhase`** — always-fires baseline. Pick the current phase bucket and phrase accordingly. 100%.

The baseline tier (`moonPhase`) guarantees every walk gets a valid reading. It's the "there was nothing more striking than this, so here's where the moon was" fallback.

### Note on overlap

The rare tiers (1–4) and the specific tiers (8–10) don't usually fire for the same walk. But when they do overlap, higher priority wins:
- A dawn walk on the autumn equinox returns `seasonalMarker`, not `sunriseSunset`. The equinox is rarer and more culturally resonant than a dawn walk.
- A walk during a supermoon full moon returns `supermoon`, not `fullMoon`. The more specific variant wins.
- A walk on the peak night of the Perseids that also happens at 2am returns `meteorShowerPeak`, not `deepNight`.

This means each walk is assigned its *one most distinctive fact*. Users walking a lot will see a mix of readings across their walk history, never just the baseline.

### Note on seasonalMarker vs. meteorShowerPeak

These two tiers are approximately equally rare (~4% each, both producing ~16 qualifying days per year). The ordering is a deliberate choice, not an accident of rarity:

- Seasonal markers are **civil and cultural**. They anchor the year as a shared human experience — everyone knows "the winter solstice" even if they don't track the sky. An equinox reading lands more universally than a meteor shower reading.
- Meteor showers are **observational**. They're only meaningful if the walker actually looked up and saw one, which depends on cloud cover, light pollution, and whether they were looking at their phone. A Perseids-peak walk at 10am in a cloudy city is factually true but culturally hollow.
- On the rare walk that coincides with both (e.g., a cross-quarter day that happens to land on a meteor shower peak), we surface the more universally meaningful marker.

V2 could get more sophisticated — e.g., check cloud cover and light-pollution index to demote meteor showers that weren't actually visible — but V1 keeps the ordering fixed.

## Astronomy

### What we already have in `CelestialCalculator`
- Solar longitude (`solarLongitude(T:)`)
- Lunar longitude (`lunarLongitude(T:)`)
- Seasonal markers (`seasonalMarker(sunLongitude:)`)
- Planetary positions (for V2)

### What we need to add to `CelestialCalculator`

**1. Lunar illumination.** Derive from the angular distance between sun and moon along the ecliptic (existing data). ~15 lines. Note the wrap-around normalization — without it, ~half of moon phases (when the moon's ecliptic longitude is "before" the sun's) compute incorrectly.
```swift
static func lunarIllumination(T: Double) -> Double {
    let sunLon = solarLongitude(T: T)
    let moonLon = lunarLongitude(T: T)
    // Normalize the elongation to [0, 360). Without this, a moon at
    // longitude 10° with sun at 350° would compute as -340° instead
    // of +20°, and cos() would flip the sign.
    var diff = moonLon - sunLon
    if diff < 0 { diff += 360 }
    let phase = radians(diff)
    return (1 - cos(phase)) / 2  // [0, 1]
}
```

**2. Lunar phase name.** Classify illumination + waxing/waning into one of 8 standard phases. ~20 lines. Needs to know whether the moon is waxing (elongation increasing) or waning.

**3. Sunrise/sunset at observer location.** NOAA simplified algorithm. Input: date, latitude, longitude. Output: `(sunriseUTC, sunsetUTC, solarNoonUTC)`. ~40 lines of well-documented math. Adds a new file `Pilgrim/Models/Astrology/SolarHorizon.swift`.

**4. Solar altitude at a given instant and location.** Derived from the above. Used for twilight detection, golden/blue hour, deep night check. ~15 lines.

**Total added astronomy code: ~85 lines across 1-2 files.** All self-contained, testable against known reference dates (e.g., sunrise at a specific lat/lon on a specific date compared to NOAA/USNO published values).

### Static event tables (supermoons, eclipses, meteor showers)

For the three rarest tiers we don't compute at runtime — we ship a pre-generated static table and do a simple date lookup. This is the right call because:

- **Events are fixed.** A lunar eclipse on 2028-01-12 is a historical certainty. We don't need orbital math at runtime to find it.
- **Tables are small.** ~100 entries total, <10 KB bundled.
- **Lookup is O(n) on ~100 items.** Cheaper than any ephemeris calculation.
- **Easy to update.** Run a one-time Python script with `skyfield` before each release, commit the regenerated Swift file.

The tables live in `Pilgrim/Models/Astrology/AstronomicalEvents.swift`. Event dates are Unix timestamps (UTC seconds since epoch), not ISO strings — integer comparison is faster, no DateFormatter parsing at lookup, and literals are compile-time validated:

```swift
enum AstronomicalEvents {

    // Lunar eclipses 2026–2045 from NASA Goddard canon (eclipse.gsfc.nasa.gov).
    // unixTime is the instant of maximum eclipse in UTC.
    // Comment next to each entry shows the human-readable ISO date for review.
    static let lunarEclipses: [LunarEclipseEvent] = [
        LunarEclipseEvent(unixTime: 1772_452_380, type: .total, magnitude: 1.15),    // 2026-03-03T11:33:00Z
        LunarEclipseEvent(unixTime: 1787_718_840, type: .partial, magnitude: 0.93),  // 2026-08-28T04:14:00Z
        // ... ~40 total entries through 2045
    ]

    // Supermoons 2026–2045 from Fred Espenak's tables. A supermoon is defined
    // as a full moon within 90% of the closest lunar perigee in that orbit.
    static let supermoons: [SupermoonEvent] = [
        SupermoonEvent(unixTime: 1793_174_720, distanceKm: 357_364),  // 2026-10-27T11:12:00Z
        SupermoonEvent(unixTime: 1795_720_320, distanceKm: 356_823),  // 2026-11-25T16:52:00Z
        // ... ~60 total entries through 2045
    ]

    // Major annual meteor showers from the IMO (International Meteor Organization).
    // Peak dates shift by ±1 day year-to-year due to Earth's orbit; we accept that
    // error and do a ±1 day match against (month, day) in the walker's local date.
    static let meteorShowers: [MeteorShowerEvent] = [
        MeteorShowerEvent(name: "Quadrantids", peakMonth: 1, peakDay: 3, zhr: 120),
        MeteorShowerEvent(name: "Lyrids", peakMonth: 4, peakDay: 22, zhr: 18),
        MeteorShowerEvent(name: "Eta Aquariids", peakMonth: 5, peakDay: 6, zhr: 50),
        MeteorShowerEvent(name: "Perseids", peakMonth: 8, peakDay: 12, zhr: 100),
        MeteorShowerEvent(name: "Orionids", peakMonth: 10, peakDay: 21, zhr: 20),
        MeteorShowerEvent(name: "Leonids", peakMonth: 11, peakDay: 17, zhr: 15),
        MeteorShowerEvent(name: "Geminids", peakMonth: 12, peakDay: 14, zhr: 150),
        MeteorShowerEvent(name: "Ursids", peakMonth: 12, peakDay: 22, zhr: 10),
    ]

    struct LunarEclipseEvent {
        let unixTime: Int64    // UTC seconds since epoch at max eclipse
        let type: EclipseType  // .penumbral / .partial / .total
        let magnitude: Double
        var date: Date { Date(timeIntervalSince1970: TimeInterval(unixTime)) }
    }

    struct SupermoonEvent {
        let unixTime: Int64    // UTC seconds since epoch
        let distanceKm: Int
        var date: Date { Date(timeIntervalSince1970: TimeInterval(unixTime)) }
    }

    struct MeteorShowerEvent {
        let name: String
        let peakMonth: Int  // 1-12
        let peakDay: Int    // 1-31
        let zhr: Int        // zenithal hourly rate at peak (used in phrasing)
    }

    enum EclipseType { case penumbral, partial, total }
}
```

The Python generator computes the integer literals; reviewers can eyeball the ISO comments to sanity-check. At runtime, lookup is a sorted-array linear scan (or a binary search against the sorted-by-unixTime invariant asserted in tests).

**Visibility and geography**: eclipses and meteor showers have geographic visibility constraints (an eclipse over Asia might be invisible from the Americas). V1 **does not filter by location** — we just check whether the event occurred during the walker's local date. Rationale: the fact that an eclipse was happening somewhere on Earth during the walk is still true, and the vast majority of walks during any given eclipse/shower will be at least partially in its visibility zone anyway. V2 can add location filtering if users report false positives for walks in the "wrong" hemisphere.

### Date matching: local, not UTC

A subtle correctness issue: the generator needs to know the walker's *local date* of the walk, not the UTC date, because:
- The Perseids peak "tonight" for a user in Tokyo at 00:30 local on August 13 (which is August 12 UTC) — the walker experiences that as the peak night, so we should fire `meteorShowerPeak`.
- The autumn equinox happens at a specific UTC instant, but culturally it's "the equinox day" in local time. A walk on September 22 local time should fire `seasonalMarker` regardless of where the equinox instant falls in UTC.
- Deep night at 2am local is a local-clock concept, not UTC.

**Rule**: all date-based tier matching uses the walker's local date derived from `Calendar.current` at the moment of generation. This uses the device's current time zone, which is a pragmatic simplification:

- **Normal case**: the walker walked and viewed the walk summary while in the same time zone. Local date is unambiguous and correct.
- **Edge case**: the walker walked in Tokyo then flew to Paris before viewing the walk. `Calendar.current` at render time would use Paris's time zone, which doesn't match the walker's zone at walk time. Result: a Tokyo-August-13 walk might be classified using Paris's August 12 — the Perseids match still fires, but for the wrong reason. This is acceptable for V1. V2 can store the walk's original time zone alongside `startDate` if needed.

**What we specifically do not do**:
- Derive time zone from walk coordinates via `CLLocation` + `CLPlacemark` — network call, adds async complexity, overkill for V1.
- Use UTC — would cause false negatives on meteor showers and seasonal markers for off-UTC walkers (most of the world).
- Store time zone as a new field on the walk — a data-model change that's out of scope for this feature.

**Scope of the local-date rule**: it applies to `seasonalMarker`, `meteorShowerPeak`, and the date portion of `lunarEclipse` / `supermoon` lookups. It does NOT apply to `sunriseSunset`, `goldenHour`, `twilight`, `deepNight`, or `moonPhase` — those compute times-of-day from the walk's actual UTC timestamp and the walk's coordinates, which is already time-zone-correct.

**Data generation**: a one-time Python script at `scripts/generate_astronomical_events.py` uses `skyfield` + the NASA eclipse canon + IMO meteor shower data to output the Swift file. Committed to the repo, regenerated once per year (or when the 20-year window starts running out). Not run at app runtime.

**Total static table payload**: ~100 Swift literals, ~5 KB compiled. Smaller than the existing whisper manifest.

## Phrasings

Each tier has a small set of hand-written template phrasings — 4–8 per tier, ~70 total across the 11 tiers. These are **sentence templates** that fill in real numbers at generation time:

### Example templates (illustrative, not exhaustive)

**`lunarEclipse`** (parameterized by type and magnitude):
- `"This walk happened during a total lunar eclipse. The moon turned red for {minutes} minutes."`
- `"A partial lunar eclipse shadowed the moon during this walk — {pct}% obscured."`
- `"You walked under a penumbral lunar eclipse. The moon dimmed but never darkened."`
- `"The {eclipseDate} lunar eclipse was above the horizon during this walk."`

**`supermoon`** (parameterized by distance and month):
- `"You walked under the {month} supermoon — the full moon at its closest to Earth this orbit."`
- `"This was a supermoon walk. The moon appeared about 14% larger than at its farthest."`
- `"The supermoon of {month} {year} watched over this walk. {distanceKm} km away, brighter than average."`

**`meteorShowerPeak`** (parameterized by shower name and ZHR):
- `"This walk happened on the peak night of the {showerName} — up to {zhr} meteors per hour."`
- `"You walked through the peak of the {showerName} meteor shower."`
- `"The {showerName} radiant was overhead during this walk."`
- `"This walk coincided with the {showerName} at peak — a good night to watch the sky."`

**`seasonalMarker`:**
- `"You walked on the {marker}. {flavor}."`
  - `springEquinox`: "The turning point of the year, light lengthening."
  - `summerSolstice`: "The longest day of the year."
  - `autumnEquinox`: "The year tipping toward winter."
  - `winterSolstice`: "The longest night of the year. Light begins to return tomorrow."
  - `imbolc`: "Halfway from the solstice to the equinox — the first stirring of spring."
  - `beltane`: "Halfway to the summer solstice — the cross-quarter of green."
  - `lughnasadh`: "Halfway to the autumn equinox — the cross-quarter of harvest."
  - `samhain`: "Halfway to the winter solstice — the cross-quarter of the ancestors."

**Note on the equinox wording**: common usage says "day and night are equal on the equinox", but that's technically wrong — the moment of equal day and night is the *equilux*, which happens several days before/after the equinox depending on latitude. The equinox itself is when the sun crosses the celestial equator. Since the spec's core promise is "every fact is TRUE," we use metaphorical phrasings ("turning point", "tipping toward") that don't make a measurement claim we can't back up.

Summer and winter solstices ARE factually "longest day" / "longest night" so those templates keep the measurement claim.

**`fullMoon`:**
- `"The full moon watched over this walk — {pct}% illuminated."`
- `"You walked under a full moon. {pct}% lit, the brightest sky of the month."`

**`newMoon`:**
- `"This walk happened under the dark of the new moon. Stars at their clearest."`
- `"No moon tonight. The sky belonged to the stars."`

**`sunriseSunset`** (parameterized by which edge and how many minutes):
- `"Your walk began {N} minutes before sunrise. The sun rose at {time}."`
- `"Your walk began {N} minutes after sunset. The sun had set at {time}."`
- `"You walked into the sunrise at {time}."`  (if within 5 min of exact sunrise)
- `"You walked into the sunset at {time}."`  (if within 5 min of exact sunset)
- `"Your walk ended {N} minutes after sunset. The light was just fading."`  (if walk ended near sunset but started earlier)

**Note**: earlier drafts used phrases like "first light came at {time}" but that conflated civil twilight start with sunrise — two different astronomical events. Civil twilight ("first light" in common usage) typically begins ~30 min before sunrise, depending on latitude and season. To keep the "every fact is true" promise, we name only sunrise and sunset times in this tier. Civil twilight gets its own phrasing under the `twilight` tier below.

**`goldenHour`:**
- `"You walked through the last hour of golden light."`
- `"Golden hour followed you the whole way."`
- `"Your walk began in the warm hour before sunset."`

**`twilight`:**
- `"You walked through civil twilight — the blue hour between day and night."`
- `"You walked through nautical twilight. The brightest stars had come out."`
- `"This walk happened in astronomical twilight — the sky fully dark to most eyes."`

**`deepNight`:**
- `"This walk happened in full dark — no moon, the sky at its clearest."`
- `"2am, moonless. Stars were at their brightest."`

**`moonPhase`** (baseline):
- `"You walked under a {phaseName} moon, {pct}% illuminated."`
- `"A {phaseName} moon was in the sky during this walk."`
- Phase names: new / waxing crescent / first quarter / waxing gibbous / full / waning gibbous / last quarter / waning crescent.

### Selection
For each tier, the generator picks one template from the set using a seeded RNG (same UUID → same template). Templates are hand-written in the Pilgrim wabi-sabi voice — quiet, no exclamation points, no emoji, no "wow".

**Critical — stable seed derivation from UUID**: Swift's built-in `UUID.hashValue` is randomized per process launch for DoS resistance, which means using `walk.uuid.hashValue` as a seed produces a different template on every app launch. That breaks the "same walk → same reading forever" guarantee. We must derive a stable UInt64 seed from the UUID's raw bytes:

```swift
static func stableSeed(from uuid: UUID) -> UInt64 {
    // UUID.uuid is a 16-tuple of UInt8 bytes. Take the first 8 and
    // pack them into a UInt64. The specific byte-ordering doesn't
    // matter as long as it's consistent across runs — same input
    // bytes always produce the same seed.
    let bytes = uuid.uuid
    var seed: UInt64 = 0
    seed = (seed << 8) | UInt64(bytes.0)
    seed = (seed << 8) | UInt64(bytes.1)
    seed = (seed << 8) | UInt64(bytes.2)
    seed = (seed << 8) | UInt64(bytes.3)
    seed = (seed << 8) | UInt64(bytes.4)
    seed = (seed << 8) | UInt64(bytes.5)
    seed = (seed << 8) | UInt64(bytes.6)
    seed = (seed << 8) | UInt64(bytes.7)
    return seed
}
```

A unit test asserts that generating the same walk twice in the same test run and across process restarts (via a fixed UUID constant) produces the same template.

**Nil UUID fallback**: `walk.uuid` is `UUID?`. If nil (shouldn't happen for a persisted walk, but the type allows it), fall back to `UInt64(walk.startDate.timeIntervalSince1970)` — still deterministic, just uses the walk's start time as the seed instead of the UUID.

### Preference interaction
When `celestialAwarenessEnabled` is `true`, the moon-phase baseline template can optionally include constellation flavor:
- Off: *"You walked under a waxing gibbous moon, 78% illuminated."*
- On: *"You walked under a waxing gibbous moon in Libra, 78% illuminated."*

The preference **only affects phrasing variants** in the `moonPhase` and (V2) planetary-position tiers. All other tiers produce the same sentence regardless of the preference.

## Files to create

1. `Pilgrim/Models/Astrology/SolarHorizon.swift` — sunrise/sunset/solar altitude at observer location (~80 lines)
2. `Pilgrim/Models/Astrology/AstronomicalEvents.swift` — generated static tables for eclipses, supermoons, meteor showers (~250 lines, most of it data)
3. `Pilgrim/Models/LightReading/LightReading.swift` — struct + Tier enum + Comparable impl (~50 lines)
4. `Pilgrim/Models/LightReading/LightReadingGenerator.swift` — priority ladder + template selection (~180 lines)
5. `Pilgrim/Models/LightReading/LightReadingTemplates.swift` — ~70 hand-written templates organized by tier (~160 lines)
6. `Pilgrim/Views/WalkLightReadingCard.swift` — SwiftUI card (~60 lines)
7. `scripts/generate_astronomical_events.py` — one-time Python generator for AstronomicalEvents.swift using `skyfield` and NASA data (~120 lines)
8. `UnitTests/SolarHorizonTests.swift` — sunrise/sunset math validated against known reference dates (~80 lines)
9. `UnitTests/LightReadingGeneratorTests.swift` — see test plan (~200 lines)
10. `UnitTests/AstronomicalEventsTests.swift` — lookup correctness + data integrity tests (~60 lines)

## Files to modify

1. `Pilgrim/Models/Astrology/CelestialCalculator.swift` — add `lunarIllumination`, `lunarPhase`, small helpers (~40 lines added)
2. `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift` — add `@State var lightReading`, `hasRevealedLightReading`, insert `WalkLightReadingCard` above `shareCard`, compute on `onAppear`, hook reveal into Share action (~15 lines added)

## Test plan

**Pool integrity tests:**
- `testAllTiersHaveTemplates` — every `LightReading.Tier` case has at least 2 templates defined
- `testNoTemplatePlaceholdersUnfilled` — no template ships with an unfilled `{placeholder}`

**Astronomy correctness tests:**
- `testSunriseAtKnownLocations` — sunrise at e.g. Paris on 2024-06-21 matches the USNO published value to within 2 minutes
- `testSunsetAtKnownLocations` — same for sunset
- `testPolarDayReturnsNil` — sunrise at 80°N in July correctly returns nil (midnight sun)
- `testPolarNightReturnsNil` — sunset at 80°N in December returns nil (polar night)
- `testLunarIlluminationFullMoon` — a known full-moon date returns illumination > 0.98
- `testLunarIlluminationNewMoon` — a known new-moon date returns illumination < 0.02
- `testLunarIlluminationWrapAround` — construct a synthetic case where sunLon=355° and moonLon=5° (moon just past new, wrapped past 360°). Without the normalization fix the formula would return ~0.98 (wrongly reporting a full moon). The test asserts the computed illumination is < 0.02 (correctly new). This is the B1 regression guard.
- `testSeasonalMarkerAtExactEquinox` — 2024-03-20 at 03:06 UTC returns `.springEquinox`

**Priority ladder tests (covers rarity ordering):**
- `testLunarEclipseBeatsAllOthers` — a walk on the 2028-01-12 total lunar eclipse date (which is also a full moon) returns `lunarEclipse`, not `fullMoon` or `supermoon`
- `testSupermoonBeatsFullMoon` — a walk on a supermoon date returns `supermoon`, not `fullMoon`
- `testSeasonalMarkerBeatsMeteorShower` — if a walk happens on both a seasonal marker and a meteor shower peak, the marker wins
- `testMeteorShowerBeatsFullMoon` — a Perseids-peak walk also during a full moon returns `meteorShowerPeak`
- `testFullMoonBeatsNewMoon` — obvious but covers enum ordering
- `testFullMoonDetection` — 95%+ illumination returns the fullMoon tier (when not overridden by eclipse/supermoon)
- `testSunriseWindow` — walks within 30 minutes of sunrise return the `sunriseSunset` tier
- `testSunriseWindowBoundary` — a walk exactly 31 minutes before sunrise does NOT return `sunriseSunset`
- `testDeepNightRequiresMoonlessAndDark` — a walk at 2am with a full moon does NOT return `deepNight`
- `testBaselineAlwaysFires` — a walk with no distinguishing features returns `moonPhase`

**Static event table tests:**
- `testLunarEclipseLookupKnownDate` — generator sees the 2026-03-03 total eclipse and returns `lunarEclipse`
- `testLunarEclipseLookupNegative` — a walk on an ordinary date returns a lower tier
- `testSupermoonLookupKnownDate` — walk on a supermoon date returns `supermoon`
- `testSupermoonWindowBoundary` — walk 4 days before a supermoon does NOT fire `supermoon` (window is ±3 days)
- `testMeteorShowerLookupPerseidsPeak` — walk on August 12 returns the Perseids reading
- `testMeteorShowerLookupBoundary` — walk on August 14 does NOT fire (peak window is ±1 day)
- `testEventTablesChronologicallyOrdered` — eclipses and supermoons are sorted by date (enforces data-file invariant)
- `testEventTablesHaveNoDuplicates` — no duplicate dates in either table
- `testEventTablesCoverCurrentDecade` — assert both tables have entries for every year 2026-2035 inclusive (catches stale data if the generation script is forgotten)
- `testMeteorShowersHave8Entries` — exact count, matches the IMO major-shower list

**Determinism tests:**
- `testSameWalkSameReading` — generate twice for the same walk, same output
- `testDifferentWalksDifferentReadings` — 20 synthetic walks across different dates/locations, assert at least 12 distinct outputs
- `testStableSeedFromUUIDBytes` — construct a fixed UUID like `"12345678-1234-1234-1234-123456789012"`, call `stableSeed(from:)` twice, assert the returned `UInt64` is identical. Also assert it equals the expected hand-computed value from packing the first 8 bytes. Guards I5: any change to the seed derivation function that would break cross-launch determinism fails the test.
- `testNilUUIDFallsBackToStartDate` — generate a reading for a walk with `uuid = nil`, assert the seed used equals `UInt64(walk.startDate.timeIntervalSince1970)`

**Local-date matching tests** (B3 regression guards):
- `testMeteorShowerMatchesLocalDate` — construct a walk with `startDate` equivalent to Tokyo 00:30 local on August 13 (which is August 12 12:30 UTC). With `Calendar.current` set to Asia/Tokyo during the test, assert `meteorShowerPeak` fires with the Perseids match.
- `testSeasonalMarkerUsesLocalDate` — a walk at Tokyo 23:30 local on September 22 (~14:30 UTC) during the autumn equinox. `Calendar.current` set to Asia/Tokyo returns `.autumnEquinox`. Confirms the ±24h window is computed against the walker's local date, not UTC.
- `testTimezoneEdgeCaseCrossingUTCMidnight` — walk at Honolulu 22:00 local on August 12 (08:00 UTC August 13). With `Calendar.current` set to Pacific/Honolulu, the local date is August 12, so the Perseids match (peakDay=12) fires. Asserts the generator uses local date, not UTC date, for the lookup.

**Reveal-state persistence tests** (I1 regression guards):
- `testFirstShareWritesUUIDToSet` — set up an empty `sharedWalkUUIDs` in mock UserDefaults, call the reveal hook for a given walkUUID, assert the set now contains that UUID
- `testSecondViewReadsRevealedState` — seed `sharedWalkUUIDs` with a UUID, initialize `WalkSummaryView` state for that walk, assert `hasRevealedLightReading` starts as `true`
- `testMultipleWalksAccumulateInOneKey` — reveal 5 different walks, assert all 5 UUIDs are in the single `sharedWalkUUIDs` array, and only that one key exists (not 5 separate `hasSharedWalk_*` keys)

**Nil-tolerance tests:**
- `testNilLocationFallback` — walk with no coordinates falls back to tiers that don't require location (seasonal marker, full/new moon, moonPhase baseline)
- `testNilStartDateFallback` — should never happen (walks always have a start date), but handle gracefully

**Preference tests:**
- `testMoonPhasePhraseWithoutCelestialPref` — phrasing does NOT include constellation name
- `testMoonPhasePhraseWithCelestialPref` — phrasing DOES include constellation name

**Visual regression (informal):**
- `testCardRendersAtSmallDynamicType` — snapshot test at `.large`
- `testCardRendersAtExtraLargeDynamicType` — snapshot test at `.accessibilityExtraExtraExtraLarge`

## Accessibility

- `.accessibilityElement(children: .combine)` on the card so VoiceOver reads it as one unit
- Accessibility label: "A light reading for this walk: {sentence}"
- Supports Dynamic Type up to `.accessibilityExtraExtraExtraLarge` with `minimumScaleFactor(0.85)` on the text
- The SF Symbol header is marked `.accessibilityHidden(true)` — it's decorative, the sentence already communicates the content

## What this is not (yet)

- **Not** moon altitude or azimuth at observer location. V2.
- **Not** planet visibility ("Venus was up at 12°"). V2.
- **Not** geographic filtering on eclipses and meteor showers — V1 checks date only, accepts that a walk in one hemisphere during an eclipse visible in the other hemisphere still gets the reading. V2 can refine.
- **Not** planetary conjunctions. V2 or V3.
- **Not** localized phrasings. V1 English only.
- **Not** shared with the recipient. Private reward only.

## Estimated effort

- Sunrise/sunset + lunar illumination math: half day (with reference-value tests)
- Static event tables (Python generator script + data source wiring + Swift data file): half day
- Generator + priority ladder + template selection: half day
- Card UI + WalkSummaryView integration: 2 hours
- Hand-writing the ~70 templates across 11 tiers: 3 hours
- Polish + tests + TestFlight verification: half day

**Total: ~3 days of focused work.** (Up from the original 2-day estimate because we added the three rare tiers; the astronomy-events tables add ~1 day of work but substantially raise the ceiling of what the feature can surface.)

## Why this beats the haiku idea

- **Content is true, not invented.** Every sentence points at a real sky condition. Users can verify by looking up.
- **Smaller phrasing pool.** ~70 templates vs. 108 haiku phrases, spread across 11 tiers of varying rarity. Less authoring burden, easier to curate for tone, and each template is anchored to a real astronomical condition so the voice self-constrains.
- **No syllable constraint.** Authoring is an order of magnitude easier; there's no "evening is 2 or 3 syllables?" pain.
- **Every walk is different for a real reason.** Two walks at the same time of day a week apart will have noticeably different moon conditions. The feature feels alive without hand-tuned variation.
- **Progressive disclosure.** Priority ladder means striking conditions surface first. A walk that happened on a solstice LEADS with that fact. Ordinary walks get a moon phase baseline. Users who walk frequently will learn what "tier 3 — sunrise" means by seeing it for their dawn walks.
- **Builds on existing code.** Uses `CelestialCalculator` that the app already ships. Adds ~85 lines of sun-horizon math plus the static astronomical events tables. No new runtime dependencies.
