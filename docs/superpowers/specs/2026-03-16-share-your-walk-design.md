# Share Your Walk — Design Spec

## Overview

A sharing feature that generates beautiful, ephemeral HTML pages from walk data. Users tap "Share" on any walk summary, customize what to include, and receive a URL at `walk.pilgrimapp.org/{id}`. The page is self-contained HTML with no JS dependencies, styled in the app's wabi-sabi aesthetic.

Every shared walk is ephemeral. No permanent links. The user chooses how long it lives: 1 moon (30 days), 1 season (90 days), or 1 cycle (1 year). When it expires, the URL shows a tombstone page: "This walk has returned to the trail."

This is Pilgrim's first backend service (Cloudflare Workers + R2).

## Architecture

```
iOS App                     Cloudflare Worker              R2 Storage
│                           │                              │
├─ POST /api/share ────────►│                              │
│  { stats, coords,         ├─ Reverse-geocode start/end   │
│    journal, prefs,         ├─ GET Mapbox Static Image     │
│    intervals, expiry,      ├─ Generate sumi-e SVG overlay │
│    units }                 ├─ Generate passport stamp SVG │
│                           ├─ Generate QR code SVG        │
│                           ├─ Render HTML from template    │
│                           ├─ PUT {id}.html ──────────────►│
│                           ├─ PUT {id}-og.png ────────────►│
│  ◄─── { url, id } ───────┤                              │
│                           │                              │
│                           │                              │
Visitor ────► GET /:id ────►├─ Check expiry                │
                            ├─ Serve HTML (or tombstone) ◄─┤
                            │                              │
                     Cron ──├─ Find expired walks          │
                            ├─ Replace with tombstone ─────►│
```

## iOS: Share Preparation Screen

### Entry Point

Share button added to `WalkSummaryView` toolbar (trailing, before "Done"). Available both after completing a walk and when viewing past walks from the log.

Tapping "Share" presents a full-screen sheet: `WalkShareView`.

### WalkShareView Layout

**Top: Map Preview**
- Route drawn with sumi-e ink effect
- Activity-colored segments (moss = walking, dawn = meditation, rust = reflection)
- Occupies ~200pt, no horizontal padding

**Stat Toggles**
- Each stat is a toggle row in a list
- Default ON: Distance, Duration, Elevation, Walk/Meditation/Talk breakdown
- Default OFF: Steps
- Section header: "Share these details"
- Only toggled-on stats appear on the shared page

**Journal Entry**
- Text field, 140 character limit
- Placeholder: "A few words about this walk..."
- Section header: "Reflection"
- Optional — empty is fine

**Expiration Picker**
- Three segmented options: "1 moon" / "1 season" / "1 cycle"
- Maps to 30 / 90 / 365 days
- Default: "1 season" (3 months)
- Shows computed expiration date below: "Expires June 16, 2026"

**Share Button**
- Primary action button at bottom
- Text: "Share Walk"
- Triggers upload flow

### Upload Flow

1. Build JSON payload from selections
2. Show loading state (indeterminate progress)
3. POST to Worker API
4. On success: show URL with copy button + native share sheet
5. On failure: show error with retry option
6. Store share metadata locally via UserDefaults (keyed by walk UUID): `{ url, id, expiry_date }`. Not in CoreStore — avoids migration for a lightweight cache. Used to show "Shared" indicator on walk rows and re-show the URL if the user taps share again on an already-shared walk.

### JSON Payload

```json
{
  "stats": {
    "distance": 12400,
    "active_duration": 9240,
    "elevation_ascent": 347,
    "elevation_descent": 210,
    "steps": 15240,
    "meditate_duration": 840,
    "talk_duration": 480
  },
  "route": [
    { "lat": 48.123, "lon": 11.456, "alt": 520, "ts": 1710576000 },
    { "lat": 48.124, "lon": 11.457, "alt": 522, "ts": 1710576060 }
  ],
  "activity_intervals": [
    { "type": "meditation", "start_ts": 1710576300, "end_ts": 1710577140 },
    { "type": "talk", "start_ts": 1710577800, "end_ts": 1710578280 }
  ],
  "journal": "The fog lifted somewhere past the old bridge...",
  "expiry_days": 90,
  "units": "metric",
  "start_date": "2026-03-16T07:30:00Z",
  "toggled_stats": ["distance", "duration", "elevation", "activity_breakdown"]
}
```

**Route downsampling**: Full walks can have thousands of GPS points. Downsample to ~200 points using the Ramer-Douglas-Peucker algorithm before sending. Preserves route shape, reduces payload from ~100KB to ~5KB.

**Activity intervals**: Sent as timestamp ranges. Meditation intervals come directly from `walk.activityIntervals`. Talk intervals are synthesized from `walk.voiceRecordings` (each has `startDate`/`endDate`) — there is no `talk` type in `ActivityInterval.ActivityType`. The existing `ActivityTimelineBar` in `WalkSummaryView` already does an equivalent merge. The Worker maps these timestamps to route point indices by finding the nearest timestamps in the route array.

**Walking duration derivation**: The Worker computes walking duration as `active_duration - meditate_duration` (talk time is NOT subtracted — talk happens while walking). This matches `WalkSummaryView.walkDuration`'s formula. Note: `WalkSnapshot.walkOnlyDuration` in the home list uses a different formula that subtracts talk. The shared page should match the summary view the user just saw.

**Stats filtering**: Only include stats the user toggled on. The Worker renders only what's present in the payload.

## Cloudflare Worker: API

### POST /api/share

**Rate limiting**: Per-device token (UUID generated on first share, stored in Keychain). Max 10 uploads per day per device.

**Processing pipeline**:

1. Validate payload structure and size (max 500KB)
2. Generate unique ID (nanoid, 10 chars, URL-safe)
3. Reverse-geocode start/end coordinates → place names (Mapbox Geocoding API)
4. Fetch Mapbox Static Image (1280x800, style matching app's wabi-sabi map)
5. Generate HTML page from template:
   - Inject base64-encoded map image
   - Generate sumi-e SVG route overlay from coordinates
   - Generate activity-colored route segments
   - Place meditation glow markers at meditation intervals
   - Place distance marker stones at km/mi intervals
   - Generate procedural passport stamp SVG
   - Generate QR code SVG (App Store link)
   - Apply staged reveal CSS animations
   - Set OG meta tags
   - Apply unit formatting (metric/imperial)
   - Include walk character text (auto-generated from metadata)
6. Store HTML in R2: `walks/{id}/index.html`
7. Store OG image in R2: `walks/{id}/og.png` (the raw Mapbox static image — no SVG overlay, since Workers V8 isolate has no canvas/PNG rendering. The static map with the route drawn by Mapbox's path overlay parameter is sufficient for social previews)
8. Store metadata in R2: `walks/{id}/meta.json` (expiry date, created date)
9. Return `{ "url": "https://walk.pilgrimapp.org/{id}", "id": "{id}" }`

### GET /:id

1. Check `walks/{id}/meta.json` for expiry
2. If expired: serve tombstone HTML
3. If valid: serve `walks/{id}/index.html`
4. Set appropriate cache headers (short TTL since pages expire)

### Cron: Expiry Cleanup

- On share creation, store expiry date in KV: key = `expiry:{id}`, value = ISO date, TTL = expiry duration + 1 day
- Cron runs daily, reads KV keys with `expiry:` prefix, checks dates
- Expired walks: delete HTML + OG image from R2, delete KV entry
- Tombstone pages are generated on-the-fly by the Worker when `meta.json` exists but `index.html` does not
- Avoids expensive R2 object listing at scale

## Walk Page: HTML Design

### Visual Identity

Based on Alternative A ("The Journey") — timeline-narrative layout.

**Colors** (light mode):
- Background: `#F5F0E8` (parchment)
- Text: `#2C241E` (ink)
- Accent: `#8B7355` (stone)
- Walking: `#7A8B6F` (moss)
- Meditation: `#C4956A` (dawn)
- Reflection: `#A0634B` (rust)
- Secondary: `#B8AFA2` (fog)
- Cards: `#EDE6D8` (parchment-secondary)

**Dark mode** (via `prefers-color-scheme: dark`):
- Background: `#141D1C`, Text: `#F0EBE1`, Accent: `#B8976E`
- Moss: `#95A895`, Dawn: `#D4A87A`, Rust: `#C47E63`, Fog: `#6B6359`
- Note: these are design-intent approximations. The iOS app applies dynamic seasonal color shifts via `SeasonalColorEngine`, so exact hex matching is not possible. The web page uses static values that capture the intended mood.

**Typography**:
- Display/headings/journal: Cormorant Garamond italic + regular (base64-encoded Latin subset, ~25KB)
- Stats/labels: Lato regular (base64-encoded Latin subset, ~20KB)
- Total font payload: ~45KB — keeps page well under 500KB target
- Fonts inlined as `@font-face` with `src: url(data:font/woff2;base64,...)` — self-contained, no CDN, works forever
- Fallback stacks: `'Cormorant Garamond', 'Georgia', serif` / `'Lato', -apple-system, sans-serif`

**Spacing**: 8px base grid, generous vertical breathing room

### Page Structure (top to bottom)

1. **Map** — edge-to-edge, ~320px height
   - Mapbox static image as CSS background
   - SVG overlay with sumi-e ink stroke route
   - Activity-colored segments (moss/dawn/rust)
   - Meditation glow markers (soft dawn-colored radial gradients)
   - Distance marker stones (small stone dots at km/mi intervals)
   - Start dot (filled) / End dot (hollow)
   - Gradient fade to parchment at bottom
   - **Ink draw animation**: route animates drawing itself on load via CSS `stroke-dasharray` + `@keyframes` (3-4 seconds)

2. **Date + Walk Character** — left-aligned
   - Date: "March 16, 2026 · Morning" (Lato uppercase, fog color)
   - Walk character: "A morning walk with moments of meditation and three spoken reflections" (italic, stone color)
   - Auto-generated from: time of day, season, activity composition

3. **Journal Entry** — hero text
   - Large Cormorant Garamond, light weight, 22-26px
   - Italic
   - Max width ~480px for comfortable reading

4. **Activity Timeline Bar**
   - Horizontal bar showing walk composition
   - Segmented by activity type with moss/dawn/rust colors
   - Legend below: Walking · Meditation · Reflection

5. **Mindful Stats** — 3-column grid
   - Walking time (moss), Meditation time (dawn), Reflection time (rust)
   - Parchment-secondary background cards
   - Only shown if user toggled "activity breakdown" on

6. **Movement Stats** — horizontal row with hairline borders
   - Distance, Elevation, Steps (whichever the user toggled on)
   - Compact: value + label, separated by thin borders

7. **Elevation Profile** — SVG sparkline
   - Stone-colored gradient fill + thin line
   - Full width, ~60px height
   - Only shown if user toggled "elevation" on and walk has significant elevation change (>10m)

8. **Footer** — passport stamp + colophon side by side
   - Left: procedural passport stamp (80x80px)
   - Right: "Recorded with Pilgrim" + "pilgrimapp.org"

9. **Colophon Area**
   - QR code (80x80px, SVG-generated)
   - "Embed this walk" via `<details>/<summary>` (pure HTML, no JS)

10. **Ephemeral Notice** — very bottom
    - "This walk returns to the trail on [date]"
    - Extremely subtle (fog color, 0.4 opacity, italic)

**Note**: Start/end place names (from geocoding) are integrated into the date line at position 2: "March 16, 2026 · Morning · Riverside Trail → Cathedral Hill". Only shown if geocoding succeeds; gracefully omitted otherwise.

### Staged Reveal Animation

CSS-only with `@keyframes` and `animation-delay`:
- Map: immediate
- Date + character: 0.5s delay
- Journal: 1.0s delay
- Timeline: 1.5s delay
- Stats: 2.0s delay
- Elevation: 2.5s delay
- Footer: 3.0s delay

Each section fades in + slides up 12px. Duration: 0.6s each. Easing: `ease-out`.

### Sumi-e Ink Stroke Effect

SVG filter chain applied to route path:
```svg
<filter id="sumi-e">
  <feTurbulence type="turbulence" baseFrequency="0.03" numOctaves="4" seed="{walk-specific}" />
  <feDisplacementMap in="SourceGraphic" in2="noise" scale="4" />
</filter>
```
- Seed derived from walk UUID for consistent rendering
- Shadow layer: same path, 12px width, 15% opacity, Gaussian blur for ink bleed
- Main stroke: 4px width, round caps/joins

### Procedural Passport Stamp

SVG generated from walk metadata:
- **Outer ring**: circle with rough filter (feTurbulence displacement)
- **Inner ring**: dashed circle
- **Top arc text**: "PILGRIM · {SEASON} {YEAR}" (Lato uppercase)
- **Bottom arc text**: "{TIME_OF_DAY} WALK" (Lato uppercase)
- **Center**: distance value (large Cormorant Garamond) + unit label

Metadata encoding:
- Season: derived from start date + hemisphere
- Time of day: derived from start date hour (morning/afternoon/evening)
- Ring count: 2 rings for <5km, 3 rings for 5-15km, 4 rings for >15km

### Print Layout (@media print)

- Remove: ephemeral notice, embed button, staged animations
- Map: reduced height (300px)
- Page break: avoid inside footer
- Background: white
- The printed version IS the permanent keepsake

### Accessibility

- Semantic HTML: `<header>`, `<main>`, `<section>`, `<footer>`
- Map image: `alt="Walk route from {start} to {end}, {distance}"`
- Stats: proper `aria-label` attributes
- Color contrast: all text passes WCAG AA on parchment background
- Route colors: distinguishable for common color vision deficiencies (moss/dawn/rust chosen deliberately)

### Embed Snippet

Uses `<details>/<summary>` HTML elements (no JavaScript) to toggle visibility of the iframe code block:
```html
<details>
  <summary>Embed this walk</summary>
  <code>&lt;iframe src="https://walk.pilgrimapp.org/{id}?embed=1"
        width="100%" height="600" frameborder="0"&gt;&lt;/iframe&gt;</code>
</details>
```
- `?embed=1` param hides the colophon/QR/ephemeral notice for cleaner embedding
- Zero JavaScript on the entire page

## Tombstone Page

Shown when a walk's expiry date has passed.

- Parchment background
- Centered vertically
- Pilgrim logo (small, 48px)
- Text: "This walk has returned to the trail." (Cormorant Garamond italic, fog color)
- Small "Recorded with Pilgrim" colophon below
- QR code to App Store
- OG tags still present (generic Pilgrim branding)
- Dark mode supported
- Generated on-the-fly by the Worker (not stored in R2)

## Backend Infrastructure

### Cloudflare Workers + R2

- **Worker**: `share-worker` — handles upload, serving, expiry
- **R2 Bucket**: `pilgrim-walks`
- **Custom domain**: `walk.pilgrimapp.org` → Worker route
- **KV Store**: rate limit counters per device token + expiry date index for cron cleanup

### R2 Object Structure

```
walks/
  {id}/
    index.html    — the walk page
    og.png        — OG image (Mapbox static with route overlay)
    meta.json     — { created: ISO, expires: ISO, device_token_hash: SHA256 }
```

### API Authentication

- No user accounts
- Device token: UUID generated on first share, stored in iOS Keychain
- Sent as `X-Device-Token` header
- Hashed (SHA-256) before storing in meta.json (privacy)
- Used only for rate limiting, not for ownership/editing

### Rate Limits

- 10 shares per device per 24-hour window
- 500KB max payload size
- Enforced via Cloudflare KV with TTL

### Cost Estimate

- R2: $0.015/GB-month storage, $0.36/million reads. At 1000 shared walks (~500KB each): ~$0.01/month storage
- Workers: 10 million requests/month free tier
- Mapbox Static Images: 50,000 free/month, then $0.25/1000
- Mapbox Geocoding: 100,000 free/month
- Total for early stage: effectively free within free tiers

## Walk Character Text Generation

Auto-generated description from walk metadata. No AI — deterministic template selection.

**Template structure**: "{time_of_day_phrase} with {activity_description}"

**Time of day phrases** (based on startDate hour):
- 5-8: "An early morning walk"
- 8-11: "A morning walk"
- 11-14: "A midday walk"
- 14-17: "An afternoon walk"
- 17-20: "An evening walk"
- 20-5: "A night walk"

**Activity descriptions** (based on duration ratios):
- Meditation only: "long stretches of silence"
- Talk only: "{count} spoken reflections"
- Both: "moments of meditation and {count} spoken reflections"
- Neither: "steady footsteps" (walking only)
- High meditation ratio (>30%): "deep meditation woven through each step"
- High talk ratio (>30%): "rich spoken reflection along the way"

**Season** (for stamp, based on startDate + rough hemisphere detection from coordinates):
- March-May (N) or Sept-Nov (S): "Spring"
- June-Aug (N) or Dec-Feb (S): "Summer"
- Sept-Nov (N) or March-May (S): "Autumn"
- Dec-Feb (N) or June-Aug (S): "Winter"

## Key Files to Create/Modify

### iOS (New Files)
- `Pilgrim/Scenes/WalkShare/WalkShareView.swift` — share preparation screen
- `Pilgrim/Scenes/WalkShare/WalkShareViewModel.swift` — share flow state
- `Pilgrim/Models/Share/ShareService.swift` — API client for Worker
- `Pilgrim/Models/Share/RouteDownsampler.swift` — Ramer-Douglas-Peucker implementation
- `Pilgrim/Models/Share/SharePayload.swift` — JSON payload model

### iOS (Modified Files)
- `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift` — add share button to toolbar

### Backend (Separate Repository: `pilgrim-worker`)
- `src/index.ts` — Worker entry point, routing
- `src/handlers/share.ts` — POST /api/share handler
- `src/handlers/serve.ts` — GET /:id handler
- `src/handlers/expiry.ts` — Cron expiry cleanup
- `src/generators/html-template.ts` — HTML page generation
- `src/generators/sumi-e-route.ts` — SVG route overlay generation
- `src/generators/passport-stamp.ts` — procedural stamp SVG
- `src/generators/qr-code.ts` — QR code SVG generation
- `src/generators/walk-character.ts` — text generation
- `src/generators/elevation.ts` — elevation profile SVG
- `src/generators/tombstone.ts` — expired walk page
- `src/generators/polyline.ts` — Google polyline encoding
- `src/services/mapbox.ts` — Mapbox Static Images API
- `src/services/geocode.ts` — Mapbox Geocoding API
- `src/types.ts` — shared TypeScript types
- `wrangler.toml` — Worker configuration

## Existing Code to Reuse

- **Route data**: `WalkInterface` (not `WalkSnapshot`) provides route coordinates via `routeData` and activity intervals via `activityIntervals`. The share screen needs access to the full `Walk` object from CoreStore, not the lightweight snapshot.
- **Stats computation**: `WalkStats` in `Pilgrim/Models/Walk/Stats/WalkStats.swift`
- **Elevation smoothing**: `Computation.calculateElevationData` in `Pilgrim/Models/Data/DataModels/Computation.swift`
- **Activity timeline**: `WalkSummaryView` already renders activity timeline bars
- **Color definitions**: `Color.swift` extension has all hex values
- **Unit formatting**: existing `UserPreferences` tracks metric/imperial setting
- **Mapbox token**: already configured in the app for `PilgrimMapView`
- **Export infrastructure**: `ExportManager.swift` has file-sharing patterns (UIActivityViewController)

## Verification Plan

### iOS
1. Build: `xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build`
2. Test share button appears in WalkSummaryView toolbar
3. Test share preparation screen opens with correct walk data
4. Test stat toggles work and affect preview
5. Test journal entry with character limit
6. Test expiration picker shows correct dates
7. Test upload flow with mock/staging Worker
8. Test error handling (no network, Worker error)
9. Test URL copy and native share sheet

### Worker
1. `wrangler dev` for local development
2. Test POST /api/share with sample payload → returns URL
3. Test GET /:id → serves correct HTML
4. Test expired walk → serves tombstone
5. Test rate limiting (11th request fails)
6. Verify HTML passes W3C validator
7. Verify OG tags render correctly (use Facebook OG debugger, Twitter card validator)
8. Verify dark mode works
9. Verify print layout
10. Verify accessibility (Lighthouse audit)
11. Test ink draw animation renders correctly
12. Test page loads under 1 second (target: <500KB total)

### End-to-End
1. Complete a walk in the simulator
2. Open walk summary, tap share
3. Configure stats, write journal, pick expiration
4. Share walk → get URL
5. Open URL in browser → see beautiful walk page
6. Open URL on mobile → responsive design works
7. Share URL in iMessage → OG preview shows
8. Wait for expiry (or manually expire) → tombstone shows
