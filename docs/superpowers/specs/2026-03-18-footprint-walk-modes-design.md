# Footprint Walk Mode Visuals

## Context

The path screen's mode selector (Wander / Together / Seek) shows a single static footprint pair above it regardless of which mode is selected. Each mode has a distinct philosophy — solo contemplation, communal walking, stepping into the unknown — but the footprints don't reflect this. This change makes the footprint display mode-aware with a breathing transition between modes.

## Three Footprint Arrangements

### Wander (solo)

One pair of footprints — left and right foot, slightly rotated inward, low opacity. This is essentially what exists today in `footprintPair`.

- Left foot: `FootprintShape`, mirrored (`scaleEffect(x: -1)`), rotated -12°, opacity 0.08
- Right foot: `FootprintShape`, rotated 12°, opacity 0.06
- Size: 16×26pt per foot, spacing: 2pt
- Color: `Color.ink`

### Together (group pilgrimage)

Three pairs of footprints overlapping at different angles and opacities, like a small group gathered on the trail.

- **Front pair** (yours): Same as Wander — centered, strongest opacity (0.10 / 0.08)
- **Left pair**: Offset ~(-14, -10) from center, rotated -18°/+6°, opacity 0.06 / 0.05
- **Right pair**: Offset ~(12, -8) from center, rotated +8°/-16°, opacity 0.05 / 0.04
- Each pair uses the same `FootprintShape` at 14×22pt (slightly smaller than the front pair to suggest depth)
- All in `Color.ink`

The back pairs are smaller and more transparent, creating a sense of depth — others walking with you, slightly behind.

### Seek (transcendent)

One solid left footprint, and where the right foot should be — scattered dots dissolving upward.

- **Left foot**: `FootprintShape`, mirrored, rotated -12°, opacity 0.10, 16×26pt, `Color.ink`
- **Dissolving right**: 5-6 small circles (3-5pt diameter) arranged in a loose upward drift where the right foot would be. Opacity fades from 0.08 (bottom) to 0.02 (top). Positioned in a ~16×30pt area, offset slightly upward from the right foot's normal position.
- Circles use `Color.ink` fills

The dissolving dots have a subtle continuous float animation (gentle upward drift of ~2pt over 4s, looping) when Seek is active. Use the same `onAppear` / generation-counter pattern as the existing `glowScale` animation in `WalkStartView`: start the float from `onAppear` of the Seek footprint view, and the animation naturally stops when the view is removed during the breath transition (since `activeMode` changes, the Seek view is replaced). Do NOT use `withAnimation(.repeatForever)` + state mutation — per CLAUDE.md resource safety guidelines.

## Breath Transition

When the user taps a different mode, the footprint arrangement transitions with a breathing metaphor:

1. **Exhale** (0.3s easeIn): Current footprints scale up to 1.08 + opacity fades to 0
2. **Pause** (0.15s): Empty space — a beat of stillness
3. **Inhale** (0.3s easeOut): New footprints scale from 0.92 → 1.0 + opacity fades in

Total duration: ~0.75s.

Implementation: Use `@State private var footprintVisible = true`, `@State private var activeMode: WalkMode`, and `@State private var transitionGeneration = 0`. When `selectedMode` changes via `.onChange`:
1. Increment `transitionGeneration` (cancels any in-flight transition)
2. Capture `let gen = transitionGeneration`
3. Set `footprintVisible = false` (triggers exhale)
4. After 0.45s delay, guard `transitionGeneration == gen` before proceeding
5. Update `activeMode` to the new mode and set `footprintVisible = true` (triggers inhale)

The generation counter ensures rapid taps (A → B → C within 0.45s) only complete the final transition. Stale callbacks become no-ops.

The scale + opacity are driven by `footprintVisible` with an `.animation(.easeIn(duration: 0.3))` for exhale and `.easeOut(duration: 0.3)` for inhale.

### Reduce Motion

When `UIAccessibility.isReduceMotionEnabled`:
- No scale animation, no breath pause
- Instant crossfade (opacity only, 0.2s) between arrangements
- Seek's dissolving dots are static (no float animation)

## File Changes

| File | Action |
|------|--------|
| `Pilgrim/Scenes/Home/WalkStartView.swift` | **Modify** — replace `footprintPair` with mode-aware `footprintDisplay`, add breath transition logic |

No new files needed. All changes are within `WalkStartView.swift`. The `FootprintShape` is reused as-is.

## Reused Components

- `FootprintShape` — `Pilgrim/Views/FootprintShape.swift`
- `Constants.UI.Padding.*` — spacing
- Opacity values use inline literals (0.02–0.10) matching the existing `footprintPair` pattern — `Constants.UI.Opacity` values don't map to these fine-grained levels
- `Color.ink` — footprint fill color
- Generation counter pattern — already used in `WalkStartView` for entrance animations

## Verification

1. **Build**: `xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build`
2. **Wander**: Shows single pair of footprints (unchanged from current)
3. **Together**: Shows three overlapping pairs with depth (back pairs smaller, more transparent)
4. **Seek**: Shows one solid foot + dissolving dots floating upward
5. **Transition**: Tapping between modes triggers breath animation (exhale → pause → inhale)
6. **Reduce motion**: Instant crossfade, no scale, no float animation on Seek dots
7. **Re-entrance**: `selectedMode` resets to `.wander` on tab recreation (it's `@State`), so footprints correctly show Wander on return. No persistence needed — this matches the existing behavior where the mode selector always starts on Wander
8. **Rapid tapping**: Quickly tapping Wander → Together → Seek should only complete the final transition to Seek, with no flash of intermediate states
