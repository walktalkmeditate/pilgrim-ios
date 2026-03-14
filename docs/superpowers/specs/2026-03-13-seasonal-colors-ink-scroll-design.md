# Seasonal Color Shifts + Ink Scroll Visualization

## Problem

Pilgrim's wabi-sabi palette names its colors after nature — stone, moss, rust, dawn, fog — but the palette itself is static. The walk history is a standard `List` with rows. Both miss an opportunity: the app talks about impermanence but doesn't embody it.

## Goal

Make the app feel like a living artifact that breathes with the seasons and records your journey as a hand-painted scroll.

Two interconnected features:
1. **Seasonal color drift** — the entire palette shifts continuously through the year
2. **Ink scroll** — walk history becomes a winding calligraphy path with expressive dots and brushstroke scenery

---

## Feature 1: Seasonal Color Engine

### Behavior

Every day, the app's color palette is slightly different. The shift is continuous (sinusoidal over 365 days), with no hard season boundaries. The change is "noticeable delight" level — you won't see it day-to-day, but comparing January to July you'd notice.

### Seasonal Mood Curve

| Season | Peak | Hue | Saturation | Brightness |
|--------|------|-----|------------|------------|
| Spring | April | Slight green push | +10% | +5% |
| Summer | July | Warm neutral | +15% | +3% |
| Autumn | October | Amber/warm push | +5% | -3% |
| Winter | January | Cool/blue push | -15% | -5% |

### Per-Color Intensity

Not all colors shift equally:
- **Full shift**: stone, moss, rust, dawn — these are the expressive accent colors
- **Minimal shift**: ink, parchment, parchmentSecondary, parchmentTertiary — text and background must stay readable
- **Moderate shift**: fog — slightly bluer in winter, warmer in summer

### Hemisphere Awareness

Read latitude from the user's most recent walk location data. If latitude is negative (Southern Hemisphere), offset the seasonal cycle by 182 days. Store the hemisphere flag in `UserPreferences`.

**Fallback**: Before any walks are recorded (or if location permission hasn't been granted yet), default to Northern Hemisphere. After the first walk completes, extract latitude from the walk's route data and update the stored hemisphere flag. Re-check on subsequent walks in case the user travels across hemispheres.

### Technical Approach

Replace static `Color` extension properties with computed properties:
1. Resolve the named color via `UIColor(named:)` for the current trait collection using `UIColor.resolvedColor(with: UITraitCollection.current)` — this gives concrete RGB values for the active light/dark mode
2. Extract HSB components from the resolved `UIColor`
3. Apply sinusoidal seasonal transform based on current day-of-year
4. Convert back to `Color(UIColor(...))`

This resolves the dynamic color *first* (so dark mode is handled), then applies the seasonal shift to concrete values. The computed property re-evaluates whenever SwiftUI re-renders, so trait collection changes (light↔dark toggle) are picked up automatically.

### Key Files
- **Modify**: `Pilgrim/Extensions/SwiftUI/Color.swift` — computed properties with seasonal transform
- **Modify**: `Pilgrim/Models/Constants.swift` — seasonal curve parameters
- **Modify**: `Pilgrim/Models/Preferences/UserPreferences.swift` — hemisphere storage
- **Create**: `Pilgrim/Models/SeasonalColorEngine.swift` — curve math, hemisphere logic

---

## Feature 2: Ink Scroll Walk History

### Behavior

The standard walk list is replaced entirely by a vertical scroll visualization. The vertical axis represents cumulative distance walked. **Newest walks appear at top, oldest at bottom** — natural scroll direction (scroll down to explore your history). Each walk is a dot on a winding calligraphy path. The path meanders like a brushstroke. Scenery elements (trees, stones, mountains) appear along the path like a sumi-e landscape painting.

### Data Layer

Walk data must be extracted into plain structs (`WalkSnapshot`) in the ViewModel before passing to the rendering layer. CoreStore entities use `threadSafeSyncReturn` per property access, which would cause lock contention if accessed directly during Canvas rendering of many walks. The ViewModel pre-computes an array of `WalkSnapshot` (id, startDate, distance, duration, averagePace) on load, and the scroll renders from these lightweight value types.

### The Path

**Winding calligraphy bezier:**
- Cubic Bezier curves that gently undulate left-right (like a river seen from above)
- Control points generated deterministically from walk data
- Rendered as a filled shape (two parallel offset curves), not a stroked line
- **Variable width**: each walk contributes one segment of the path between its dot and the next. The segment width reflects that walk's *average pace*: a fast walk → narrow stroke, a slow contemplative walk → wide stroke. This is macro-level variation (one width per walk segment), not intra-walk detail.

### The Dots

Each walk leaves a mark:
- **Size**: proportional to walk duration (longer = larger, clamped to min/max)
- **Color**: ink tinted by the season *when the walk happened* (warm amber for autumn, cool ash for winter)
- **Opacity**: 100% for recent walks, fading to ~40% for oldest
- **Position**: centered on the path at cumulative distance point

### Interaction

- **Tap a dot** → opens `WalkSummaryView` as a sheet (reuses existing pattern)
- **Long-press a dot** → floating label with date + distance appears nearby
- **Scroll** → light haptic pulse as finger crosses each dot (prayer bead effect)

### Empty State

Single dot labeled "Begin" at top, with a short calligraphy stroke trailing into nothing.

### Brushstroke Scenery (7 shapes)

All built as SwiftUI `Shape` conformances (like existing `FootprintShape`):

| Shape | Strokes | Seasonal Behavior | Rarity |
|-------|---------|-------------------|--------|
| TreeShape | 3-4 | Lush (moss) → golden (dawn) → bare branches (ink) | ~15% |
| StoneShape | 1-2 | None — eternal, stone/fog colored | ~10% |
| PondShape | 2 | Fog in winter, moss hint in spring | ~8% |
| MountainShape | 2-3 | Fog snow cap in winter, clean in summer | ~6% |
| GrassShape | 3-5 | Moss → dawn → absent in winter | ~12% |
| ToriiGateShape | 3 | None — stone colored, biased toward milestones | ~3% |
| MoonShape | 1 | None — fog crescent, extremely rare | ~1-2% |

**Procedural placement**: Each walk's data (start date, distance, duration) is hashed to a deterministic seed. Two-step roll: first, determine if this dot gets scenery at all (~35% chance). If yes, roll against a weighted distribution to pick exactly one shape (tree 27%, stone 18%, grass 22%, pond 14%, mountain 11%, torii 5%, moon 3%). Then determine left/right placement and offset. Each dot gets at most one scenery element. The same walk always generates the same scenery.

**Seasonal tinting**: Scenery near each walk is tinted by the season *when that walk happened* (not the current season). A July tree is always lush green. A December tree is always bare. The scroll is a permanent color record of seasons walked.

### Distance Milestones

Horizontal fog-colored line at 100km, 500km, 1000km, then every 1000km. No text — quiet visual acknowledgment. Slightly wider spacing above/below. ToriiGateShape placement biased toward these markers.

### Aging Parchment

Vertical gradient overlay: top (newest) is fresh parchment, bottom (oldest) overlays dawn at ~3-5% opacity. The paper itself subtly yellows with age.

### Haptic Prayer Beads

- Small dots: `UIImpactFeedbackGenerator(.light)`
- Large dots: `UIImpactFeedbackGenerator(.medium)`
- Milestones: `UIImpactFeedbackGenerator(.rigid)`

**Scroll position tracking**: Use a `PreferenceKey` with `GeometryReader` inside the scroll content to report dot positions relative to the viewport. The haptic engine compares current scroll offset against known dot positions to fire feedback at crossing points. This avoids iOS version dependency on `ScrollView` position APIs.

### Key Files
- **Modify**: `Pilgrim/Scenes/Home/HomeView.swift` — replace List with InkScrollView
- **Modify**: `Pilgrim/Scenes/Home/HomeViewModel.swift` — cumulative distance, pace data
- **Create**: `Pilgrim/Scenes/Home/InkScrollView.swift` — main scroll container
- **Create**: `Pilgrim/Scenes/Home/CalligraphyPathRenderer.swift` — bezier path + variable width
- **Create**: `Pilgrim/Scenes/Home/WalkDotView.swift` — dot rendering + interaction
- **Create**: `Pilgrim/Scenes/Home/ScrollHapticEngine.swift` — haptic feedback
- **Create**: `Pilgrim/Scenes/Home/MilestoneMarkerView.swift` — horizontal markers
- **Create**: `Pilgrim/Models/SceneryGenerator.swift` — deterministic seed → placement
- **Create**: `Pilgrim/Views/Scenery/TreeShape.swift`
- **Create**: `Pilgrim/Views/Scenery/StoneShape.swift`
- **Create**: `Pilgrim/Views/Scenery/PondShape.swift`
- **Create**: `Pilgrim/Views/Scenery/MountainShape.swift`
- **Create**: `Pilgrim/Views/Scenery/GrassShape.swift`
- **Create**: `Pilgrim/Views/Scenery/ToriiGateShape.swift`
- **Create**: `Pilgrim/Views/Scenery/MoonShape.swift`

---

## Implementation Order

**Stage 1: Seasonal Color Engine** — standalone, benefits entire app immediately
**Stage 2: Core Ink Scroll** — winding path + dots + tap/long-press interaction
**Stage 3: Scenery & Enhancements** — shapes, milestones, haptics, aging parchment

Each stage is independently shippable and testable.

---

## Accessibility

- Respect `UIAccessibility.isReduceMotionEnabled` — disable scroll haptics, simplify path animations
- Maintain WCAG contrast ratios at all seasonal extremes
- VoiceOver: dots announce "Walk on [date], [distance], [duration]" when focused
- Scenery shapes are decorative — marked `accessibilityHidden(true)`

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Seasonal shifts break readability | ink/parchment shift minimally; test contrast at all seasonal extremes |
| Scroll performance with many walks | Use Canvas for rendering, not individual SwiftUI views per dot |
| Variable-width path is complex to render | Start with uniform width, add variable width as enhancement |
| Procedural scenery looks random/ugly | Tune seed algorithm and rarity percentages; test with real walk data |
| Users miss having a data-dense list | Long-press preview shows date+distance; WalkSummaryView has full detail |
