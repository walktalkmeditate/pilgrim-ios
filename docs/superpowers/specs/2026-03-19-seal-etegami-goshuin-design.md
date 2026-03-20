# Seal, Etegami & Goshuin

Viral sharing system rooted in pilgrimage tradition. Every walk produces a unique visual seal. Seals collect into a goshuin (stamp book). Walks can be shared as seals (image), etegami (postcard), or journeys (web page) — three tiers of increasing richness and publicity.

## Naming

| Name | What | Format | Where it lives |
|------|------|--------|---------------|
| **Seal** | Individual walk stamp (visual SHA-256 hash) | PNG image, on-device | Share sheet |
| **Etegami** (絵手紙) | Walking postcard (route + text + seal) | PNG image, on-device | Share sheet |
| **Journey** | Full walk page (existing Share Your Walk) | HTML, hosted at walk.pilgrimapp.org | Web URL |
| **Goshuin** (御朱印) | Collection of all seals | View in app | Pilgrim Log FAB |

## Privacy Model

Seal and Etegami are generated entirely on-device. No server call, no URL, no data leaves the phone until the user hands it to the system share sheet. They are images — like sharing a photo.

Journey uploads walk data to Cloudflare Workers + R2 and creates a public (ephemeral) URL. This distinction is communicated through spatial separation in the UI (seal/etegami grouped above a divider, journey below) and interaction difference (instant share sheet vs. configuration flow).

## 1. Seal Generation

### On-Device (iOS)

Port `generatePassportStamp()` from `pilgrim-worker/src/generators/passport-stamp.ts` to Swift. The function is ~150 lines of deterministic geometry derived from 32 SHA-256 hash bytes.

**Hash input** (must match worker for consistency):
```
[route points as "lat.5digits,lon.5digits", distance, active_duration, meditate_duration, talk_duration, start_date_iso8601].join("|")
```

Note: always use `active_duration` (excludes pause time), not total duration. The hash must always use the real walk values, never the optionally-toggled values from sharing preferences. The worker's `computeWalkHash()` must also be updated to always hash the full stat values regardless of sharing toggles — the current implementation uses `payload.stats.distance ?? 0` which produces a different hash when the user untoggle stats. Fix: send full stats for hashing separately from toggled stats for display.

**Visual elements** (all derived from hash bytes):
- Concentric rings (bytes 1-6, count influenced by meditation ratio)
- Radial lines (bytes 8-23, count influenced by talk ratio)
- Arc segments (bytes 24-28)
- Decorative dots (bytes 28-31)
- Curved text arcs: "PILGRIM · [SEASON] [YEAR]" top, "[TIME OF DAY] WALK" bottom
- Center: distance value + unit label
- Overall rotation from byte 0
- Weather-influenced edge texture (see below)
- Elevation ring (see below)
- Ghost route watermark (iOS only, see below)

**Rendering**: Core Graphics via `UIGraphicsImageRenderer` → `UIImage` at 512×512, transparent background. Core Graphics is required (not SwiftUI Canvas) because curved text along an arc path needs `CTLine` placement along a Bezier path. Visual equivalence with the web seal is the goal, not pixel-identical output.

### Ghost Route (iOS Only)

The walk's actual route shape is embedded as a faint watermark inside the seal, woven into the rings. At thumbnail size (128×128 in the goshuin grid), it's invisible. At full size (512×512), it reveals itself — each seal secretly contains a map of the walk.

Scale the route to fit within the seal's inner circle. Draw at 5-10% opacity as a background layer before the rings. Same route data already available. Not included on the web seal (80×80 is too small for the detail to be visible, and the Journey page already displays the full route map).

### Elevation Ring

One concentric ring is the walk's actual elevation profile wrapped into a circle. Flat walks produce a smooth ring. Hilly walks produce a jagged, dramatic ring. People who walk the same route in different directions get mirrored elevation profiles.

Plot altitude values as radius offsets along one designated ring (e.g., ring index 2). The ring's base radius comes from the hash as usual; altitude deltas add/subtract from it.

**Fallback**: if altitude data is unavailable (indoor walks, GPS issues), the ring renders as a normal smooth circle. No visual penalty.

**Web**: included on the worker-generated seal. The worker already has route altitude data and iterates over rings — add altitude offsets to one ring.

### Weather Texture

The seal's edge treatment varies based on weather conditions during the walk:

| Weather | Edge treatment |
|---------|---------------|
| Clear | crisp, clean edges (default) |
| Rain | softer, slightly dissolved edges |
| Wind | subtle directional distortion |
| Snow | crystalline, fragmented edge |

On iOS: vary the edge rendering parameters (noise amplitude, frequency). On web: vary the existing feTurbulence filter parameters (`baseFrequency`, `numOctaves`, scale). Both use the weather snapshot data already captured.

**Fallback**: if weather data is unavailable, defaults to "clear" (crisp edges). This is the existing behavior.

### Wax Stamp Animation (Seal Reveal)

On the walk completion seal reveal screen, the seal doesn't fade in — it presses into existence like a physical wax seal:

1. Seal drops from slightly above (~20pt offset)
2. Presses into the surface with a slight scale squish (1.0 → 0.95 → 1.0)
3. Subtle shadow appears beneath as it "lifts" to reveal the impression
4. Haptic feedback (`UIImpactFeedbackGenerator`, `.medium`) on the press moment

Total animation: ~0.8 seconds. SwiftUI `.spring()` animation with custom damping. Makes the completion moment feel physical and ceremonial.

### Mark-Influenced Color Palette

The seal color is determined by the walk's mark AND the hash. Each mark narrows the palette; the hash picks within it.

| Mark | Colors (4) | Tone |
|------|-----------|------|
| Transformative 🔥 | rust, ember, burnt sienna, copper | warm |
| Peaceful 🍃 | moss, sage, sea glass, mist | cool |
| Extraordinary ⭐ | indigo, gold, twilight, amethyst | accent |
| Unmarked | stone, dawn, fog | neutral (3) |

**Selection**: `hash_byte[30] % 4` for marked walks, `hash_byte[30] % 3` for unmarked. Total: 15 unique colors.

**Rationale**: In the goshuin grid, filtering by mark reveals a color cluster — Peaceful walks show a wash of greens, Transformative glows warm. The emotional texture of your walking life becomes visible at a glance.

### Color Definitions

Light mode / Dark mode values TBD during implementation. All colors should feel like natural pigments — muted, earthy, wabi-sabi. No neon, no pure hues.

### Worker Update

Update `pilgrim-worker/src/generators/passport-stamp.ts`:
- **Mark-influenced colors**: Add optional `mark` field to `SharePayload` in `types.ts` (`"transformative" | "peaceful" | "extraordinary" | null`). Update color selection to use the 15-color palette. Define CSS variables for all 15 colors. Backward compatible: if `mark` is absent, fall back to existing 3-color logic (stone/dawn/moss).
- **Elevation ring**: Use route altitude data to vary one ring's radius. The worker already iterates rings and has route altitude — add altitude-delta offsets to one designated ring. Falls back to smooth ring if altitude data is absent.
- **Weather texture**: Map `payload.stats.weather.condition` to feTurbulence parameters (`baseFrequency`, `numOctaves`, displacement scale). Falls back to existing "clear" parameters if weather data is absent.
- **Hash fix**: Always hash full stat values regardless of sharing toggles. Send full stats for hashing separately from toggled stats for display.
- **Ghost route**: NOT included on web (80×80 is too small). iOS only.

## 2. Etegami Generation

Composed image rendered on-device using Core Graphics (`UIGraphicsImageRenderer`). Each etegami is unique — shaped by when you walked, where you went, what you did, and what the sky looked like.

**Layout**:
```
┌─────────────────────────┐
│              🌙         │
│                         │
│    [sumi-e route with   │
│     meditation ripples  │
│     and voice marks]    │
│                [seal]   │  ← placed at route endpoint
│                         │
│  "March evening walk    │
│   forty minutes silence │
│   under a waning moon"  │
│                         │
│           pilgrimapp.org│
└─────────────────────────┘
```

### Time-of-Day Paper

The parchment background color shifts based on when the walk occurred. Every etegami immediately feels different.

| Time | Paper tone |
|------|-----------|
| Dawn (5-7am) | warm amber |
| Morning (7-11am) | light parchment |
| Midday (11am-2pm) | sun-bleached white |
| Afternoon (2-5pm) | golden |
| Dusk (5-8pm) | deep rose |
| Night (8pm-5am) | indigo-blue (ink stroke renders in light silver) |

Implemented as a bundled parchment texture tinted with the time-of-day color. One texture asset, six tint values.

### Narrative Route Stroke (Sumi-e)

The route is rendered as a calligraphic ink stroke where visual properties encode the walk's story. All variations happen inside a single route-point iteration loop (~50-100ms for 2000 points).

- **Elevation as ink density**: uphill segments get thicker, darker strokes (heavy, labored). Downhill gets lighter, thinner (flowing). Reads the altitude delta between consecutive points to scale `lineWidth` and opacity.
- **Taper**: stroke ramps from thin→thick over the first 10% of points and thick→thin over the last 10%. Shows direction of travel, like a calligraphy brush stroke.
- **Meditation ripples**: at GPS coordinates where meditation occurred, draw 2-3 concentric circles with decreasing opacity. Like ink dropped in water. Cost: ~1ms.
- **Voice marks**: at GPS coordinates where voice recording occurred, draw a tiny waveform squiggle along the path. Cost: <1ms.
- **Ink bleed**: semi-transparent overlapping segments with slight width variation naturally create a bleed-like effect without needing a gaussian blur pass.

### Moon Phase

For walks with celestial data (`celestialAwarenessEnabled`), render the actual lunar phase as a small illustration in the upper portion of the card. Position reflects approximate sky position at the time of the walk (low on card for setting moon, high for zenith). Omitted if celestial data is unavailable.

### Haiku-Style Text

Instead of just the user's intention, compose a three-line observation in haiku rhythm (short / longer / short) from walk data:

```
March evening walk
forty minutes in silence
under waning moon
```

Generated from templates using: season, time of day, duration, primary activity (walking/meditation/talk), celestial context (if available), weather (if available). Not AI — templated natural language. Falls back to user's intention or reflection if one exists (user words take priority).

### Other Components
- **Seal**: Placed at the route's endpoint — as if the pilgrim stamped their credential at arrival. The seal is part of the route narrative, not decoration.
- **Provenance**: `pilgrimapp.org` in small caption text, bottom edge.

**Size**: 1080×1920 (Stories format) only for v1. Square format deferred.

**Typography**: Cormorant Garamond for haiku/text, Lato for provenance mark.

## 3. Walk Completion Flow

The current completion flow in `MainCoordinatorView`: `onWalkCompleted` → `DataManager.saveWalk` → nil out `activeWalkViewModel` (dismisses full-screen cover) → `handleActiveWalkDismiss()` presents `WalkSummaryView` as sheet.

The seal reveal inserts between the full-screen cover dismiss and the summary sheet presentation:

```
Walk ends
  → Save walk data (existing)
    → Dismiss active walk cover (existing)
      → Seal reveal overlay (new, 1-2 sec interstitial)
        → Walk summary sheet (existing, enhanced with sharing)
```

**Seal reveal**: A full-screen overlay (not a sheet) that shows the seal fading in centered. Tap the seal to share immediately via share sheet. Tap anywhere else or wait ~2 seconds to auto-dismiss and present the walk summary sheet. Implemented as a transient state in `MainCoordinatorView` between walk dismissal and summary presentation.

## 4. Sharing UI (Walk Summary & Walk Detail)

Three share options in a grouped layout:

```
┌─────────────────────────────────────┐
│    [ 🔴 Seal ]   [ 🖼 Etegami ]    │
│    ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─    │
│         [ 🔗 Share Journey ]        │
│          walk.pilgrimapp.org        │
└─────────────────────────────────────┘
```

- **Seal**: Tap → system share sheet with 512×512 seal PNG
- **Etegami**: Tap → system share sheet with etegami PNG (default Stories size)
- **Journey**: Tap → existing share configuration view (toggles, journal, expiry)

This layout appears on:
1. Walk summary (after completion)
2. Walk detail (revisiting from journal)
3. Goshuin view (tap a seal → detail overlay with share options)

## 5. Goshuin (Collection View)

### Access

Floating action button (FAB) on the Pilgrim Log screen, bottom-right, above the tab bar. The FAB face shows a placeholder seal icon initially. Once the most recent walk's seal has been rendered and cached (async, background), it replaces the placeholder. This avoids blocking the Pilgrim Log load on seal rendering.

### View — Accordion Book

The goshuin opens like a real 御朱印帳 — a horizontal accordion-fold book. Swipe left/right through pages. Each page holds 4-6 seals on a warm parchment background. The physical metaphor makes the collection feel precious, not like a photo gallery.

Implementation: `ScrollView(.horizontal)` with paging behavior, or `TabView(.page)`. Each page is a parchment-textured card with seals arranged in a 2×2 or 2×3 grid.

**Top**: Mark filter toggles — 🔥 Transformative | 🍃 Peaceful | ⭐ Extraordinary | All

**Pages**: Seals rendered at 128×128 thumbnails for performance, cached in the file-backed seal cache.

**Bottom**: "Share Goshuin" button — renders the current page (respecting active filter) as a shareable image.

### The Book Ages

The goshuin's appearance evolves with your walking practice. More walks = more patina. Your dedication becomes visible in the artifact itself.

| Walks | Appearance |
|-------|-----------|
| 1-10 | Fresh, clean parchment. New book. |
| 11-30 | Slightly warm tone, light wear at edges. |
| 31-70 | Golden parchment, visible character. Well-used. |
| 71+ | Deep patina, weathered edges. A well-traveled credential. |

Implementation: `walkCount` maps to a parchment tint value and edge texture variant. Four bundled texture variants (or one base texture with four tint/overlay combinations).

### Milestone Seals

Certain walks receive a special presentation — a thin decorative ring around the outside of the seal (in addition to the seal itself, which is unchanged). The ring uses a metallic/lighter variant of the seal's mark color.

Milestone seals also display a small caption label below them on the accordion page, in `--fog` color, Lato caption weight.

**Milestone criteria**:
- Your 1st walk ever — "First Walk"
- Every 10th walk (10, 20, 30...) — "10th Walk", "20th Walk", etc.
- Your longest walk — "Longest Walk"
- Your longest meditation — "Longest Meditation"
- First walk of each season — "First of Spring", "First of Winter", etc.

These are discovered by browsing, not announced. No notifications, no badges, no popups. They reward the people who look closely — like finding a special stamp in a real credential.

Milestone detection is computed when rendering the goshuin, not stored in the data model. Query walks by count, duration, meditation time, and season to determine which qualify.

### Interactions

- Swipe left/right → page through the accordion book
- Tap a seal → navigate to that walk's detail view
- Tap a mark filter → pages show only walks with that mark; color clustering becomes visible
- "Share Goshuin" → renders current page as image → system share sheet

### Trail Integration (Optional Enhancement)

When a mark filter is active in the goshuin, the walk dots on the Pilgrim Log trail below could subtly highlight matching walks (glow or tint) while dimming non-matching ones. This visually connects the two representations of your walk history.

## 6. Data Requirements

### Existing Fields

The walk mark already exists in the data model as the `favicon` field (`WalkFavicon` enum with rawValues `"flame"`, `"leaf"`, `"star"`). No new CoreStore migration needed for the mark.

**Mapping to share payload and color palette**:
| WalkFavicon | rawValue | SharePayload value | Color palette |
|------------|----------|-------------------|---------------|
| `.flame` | `"flame"` | `"transformative"` | warm |
| `.leaf` | `"leaf"` | `"peaceful"` | cool |
| `.star` | `"star"` | `"extraordinary"` | accent |
| `nil` | — | `null` | neutral |

### No sealHash Storage

The seal hash is deterministic and SHA-256 computation is microsecond-fast. No need to store it in CoreStore (which would require a PilgrimV7 migration). Compute on demand. Cache rendered seal images in a file-backed cache keyed by walk UUID under the app's caches directory.

### SharePayload Update

Add to `SharePayload` in pilgrim-worker:
```typescript
mark?: "transformative" | "peaceful" | "extraordinary" | null;
```

## 7. Out of Scope

- Apple Watch complications
- iMessage sticker extension
- Home/Lock screen widgets
- Seasonal Pilgrimage / Wrapped feature
- Trail Letters
- "Walk With Me" invitations

These are separate projects that build on this foundation.

## 8. Success Criteria

- Every completed walk generates a deterministic seal on-device
- Seals match between app and Journey web page (same hash, same color when mark is provided)
- Sharing a seal or etegami requires zero server calls
- Goshuin view loads and filters seals performantly (target: <100ms for 100+ walks)
- Mark-based color clustering is visually obvious when filtering
