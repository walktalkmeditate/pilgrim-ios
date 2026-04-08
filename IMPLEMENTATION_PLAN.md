# Collapsible Stats Panel — ActiveWalkView Redesign

## Context

Current `ActiveWalkView` uses a fixed `VStack { map, stats, controls }` layout with a hardcoded map height fraction (0.6 default, 0.35 for accessibility large text). This breaks on:

- **iPhone SE3 (4.7")**: Stats panel cramped, controls squeezed
- **Accessibility large text**: Stats row fights for space, relies on `minimumScaleFactor(0.5–0.7)` hacks

Target: Apple Maps-style collapsible bottom sheet overlay. Map fills the screen. Sheet floats on top. Content-driven sizing adapts to any text size or screen.

## Goals

1. Map is full-screen background at all times
2. Sheet overlays the map with 3 states: **pre-walk** (expanded), **walking-minimized** (compact), **walking-expanded** (detail)
3. Sheet sizing is content-driven (no hardcoded heights, no `minimumScaleFactor` hacks)
4. Swipe gesture transitions between walking-minimized and walking-expanded
5. Auto-collapse on walk start
6. Preserve all existing functionality (voice recording, meditation, options sheet, waypoints, etc.)
7. Resource safety — no leaks during 30+ minute walks

## Non-Goals

- Not changing the map itself (`PilgrimMapView`)
- Not changing stats content or calculations
- Not changing controls (Start, Meditate, Mic, End)
- Not changing the weather overlay, audio indicators, celestial greeting, etc.
- Not changing any ViewModel logic

## Architecture

### New component: `WalkStatsSheet`

A self-contained collapsible sheet view. Owns:
- `@Binding var sheetState: SheetState` (enum: `minimized`, `expanded`)
- Drag gesture for swipe-to-expand/collapse
- Visual appearance (background, drag indicator, shadow)
- The stats content and controls (pulled from current `statsSection` and `controlsSection`)

```swift
enum SheetState {
    case minimized  // Thin bar: timer + distance
    case expanded   // Full stats: timer, intention, distance/steps/ascent, walk/talk/meditate, controls
}
```

### New layout in `ActiveWalkView.body`

```swift
ZStack(alignment: .bottom) {
    // Full-screen background layer
    WeatherOverlayView(...)
    mapSection(fillScreen: true)  // Map as full background

    // Gradient fade at bottom for readability
    VStack { Spacer(); LinearGradient(...) }

    // Audio indicators + weather/celestial vignettes (top, over map)
    VStack {
        HStack { audioIndicators; Spacer(); vignettes }
        Spacer()
    }

    // Weather/celestial greeting (floating text)
    greetingOverlay

    // Pace sparkline (floating)
    if showPace { LivePaceSparklineView(...) }

    // Top overlay buttons (ellipsis + close)
    mapOverlayButtons

    // The collapsible sheet
    WalkStatsSheet(
        state: $sheetState,
        viewModel: viewModel,
        onStart: { ... },
        onMeditate: { ... },
        onEndWalk: { ... },
        onToggleVoice: { ... }
    )
}
.onChange(of: viewModel.status) { _, newStatus in
    // Auto-collapse when walk starts
    if newStatus == .recording {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            sheetState = .minimized
        }
    }
}
```

### `WalkStatsSheet` internal structure

```swift
struct WalkStatsSheet: View {
    @Binding var state: SheetState
    @ObservedObject var viewModel: ActiveWalkViewModel
    // ... callbacks

    @State private var dragOffset: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            dragHandle  // Small pill indicator

            if state == .minimized && viewModel.status.isActiveStatus {
                minimizedContent  // Timer + distance, thin bar
            } else {
                expandedContent  // Full stats + controls
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.parchment)
                .shadow(color: .ink.opacity(0.15), radius: 12, y: -4)
        )
        .offset(y: dragOffset)
        .gesture(dragGesture)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: state)
    }
}
```

### Content-driven sizing

The sheet does NOT set a `.frame(height:)`. SwiftUI calculates height from content:

- **minimized**: drag handle + `HStack { timer, distance }` → ~60pt at default text, ~80pt at XXL
- **expanded**: drag handle + full stats + controls → variable height, grows with content

The sheet stays pinned to the bottom via `ZStack(alignment: .bottom)`. When expanded grows taller, it pushes up from the bottom.

No `minimumScaleFactor` needed — expanded layout stacks vertically, each element gets its natural size.

## States and Transitions

| State | Trigger | Visual |
|-------|---------|--------|
| **pre-walk** | `status == .waiting` or `.ready` | Expanded, showing Start button (disabled if waiting, enabled if ready) |
| **walking-minimized** | `status == .recording` AND user hasn't manually expanded | Thin bar: timer + distance |
| **walking-expanded** | User swiped up OR `status == .paused/.autoPaused` | Full stats + Meditate/Mic/End controls |

**Auto transitions:**
- `waiting → recording`: sheet auto-collapses to minimized
- `recording → paused`: sheet auto-expands (user needs context when paused)

**User transitions:**
- Swipe up on minimized: → expanded
- Swipe down on expanded: → minimized (only if status == .recording)
- Can't collapse during pre-walk or when paused

## Drag Gesture

```swift
private var dragGesture: some Gesture {
    DragGesture()
        .onChanged { value in
            // Only allow drag if in a transition-allowed state
            guard viewModel.status == .recording else { return }
            // Constrain drag to direction
            if state == .minimized && value.translation.height < 0 {
                dragOffset = max(value.translation.height, -100)
            } else if state == .expanded && value.translation.height > 0 {
                dragOffset = min(value.translation.height, 100)
            }
        }
        .onEnded { value in
            let threshold: CGFloat = 40
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                if state == .minimized && value.translation.height < -threshold {
                    state = .expanded
                } else if state == .expanded && value.translation.height > threshold {
                    state = .minimized
                }
                dragOffset = 0
            }
        }
}
```

## Map Layout Change

Current: `mapSection(height: geometry.size.height * mapHeightFraction)` → fixed height
New: Map fills the entire `ZStack` background

```swift
mapSection()  // No height parameter — fills ZStack
    .frame(maxWidth: .infinity, maxHeight: .infinity)
```

The sheet overlays the bottom of the map. User's location marker should remain visible when sheet is minimized (map's safe area insets can account for this if needed, but likely fine as-is since Mapbox centers on user).

## Safe Area Considerations

- Sheet must respect bottom safe area (home indicator)
- Use `.padding(.bottom, 0)` on sheet but let the content account for safe area
- Or: `.safeAreaInset(edge: .bottom)` on the outer `ZStack` to push the sheet above the home indicator

## Reduce Motion

- Sheet state transitions skip spring animation when `UIAccessibility.isReduceMotionEnabled`
- Drag gesture still works, just without the bouncy spring

## Testing Checklist

- [ ] iPhone 17 Pro (default text) — sheet feels right, map visible
- [ ] iPhone SE3 (4.7" simulator) — sheet fits, map has room
- [ ] iPhone 17 Pro (XXL text) — expanded sheet grows, still fits
- [ ] iPhone SE3 (XXL text) — worst case, sheet might cover most of map but user can still collapse
- [ ] Dark mode — sheet background, shadow, drag indicator all visible
- [ ] Reduce motion — transitions are instant
- [ ] Walking 30+ minutes — no memory leaks from drag gesture or animation
- [ ] All existing flows work: start, pause, auto-pause, meditate, voice record, waypoint, whisper, stone, options sheet, intention, end walk

## Implementation Stages

### Stage 1: Extract existing stats into `WalkStatsSheet` component
**Goal**: No visual change, just pull `statsSection` + `controlsSection` into new file
**Tests**: Build passes, existing walks work identically
**Files**: Create `Pilgrim/Scenes/ActiveWalk/WalkStatsSheet.swift`, modify `ActiveWalkView.swift`

### Stage 2: Restructure `ActiveWalkView.body` to use full-screen map with ZStack
**Goal**: Map fills screen, sheet is a `ZStack(alignment: .bottom)` overlay with current sheet layout
**Tests**: Walk start/end still work, stats visible, controls work, drag NOT yet implemented
**Files**: `ActiveWalkView.swift`

### Stage 3: Add `SheetState` enum and conditional content rendering
**Goal**: Sheet shows different content in minimized vs expanded states
**Tests**: Manually flip state to verify both layouts render correctly
**Files**: `WalkStatsSheet.swift`, `ActiveWalkView.swift`

**Key decisions from review:**
- `SheetState` lives in `ActiveWalkView` (not `WalkStatsSheet`), passed as `@Binding`. Parent needs to drive auto-collapse on `viewModel.status` change.
- Only `dragOffset` lives as `@State` inside `WalkStatsSheet`.
- The conditional branches (`minimizedContent` vs `expandedContent`) must live inside `WalkStatsSheet.body` to preserve view identity — don't conditionally render `WalkStatsSheet` itself from the parent.
- Auto-collapse logic goes in the EXISTING `onChange(of: viewModel.status)` handler in `ActiveWalkView` (don't add a second one).
- **Restructure before state transitions**: The ambient elements (audio indicators, vignettes, sparkline, gradient) currently live inside `bottomSheet` VStack. When the sheet collapses, they'll slide down with it by ~200pt. Extract them into their own `ambientOverlay` layer BEFORE adding SheetState, so that only the stats content collapses. Or keep them attached to the sheet top — decide which behavior is desired first.
- **Gradient behavior with state transitions**: If ambient stays with sheet, gradient does too. If ambient is extracted, gradient needs to decide: stay with sheet (will be below ambient when expanded) or stay with ambient (will be above minimized sheet).

### Stage 4: Add drag gesture
**Goal**: User can manually swipe to expand/collapse the sheet
**Tests**: Drag works smoothly, doesn't conflict with button taps, resource safety
**Files**: `WalkStatsSheet.swift`, `ActiveWalkView.swift`

**Key decisions from reviews:**
- **Drag gesture attaches to the whole sheet VStack** via `.simultaneousGesture(DragGesture())`, NOT just the drag handle. The 40x5pt pill is too small a target on a moving walk. Apple Maps and iOS presentation sheets let users drag from anywhere in the header region. BUT: attach via `simultaneousGesture` or explicitly reject drags starting near the control buttons, so tapping Mic/End/Meditate doesn't get eaten.
- Remove the `Button` wrapper from `minimizedContent` (already done in Stage 3 polish) — use plain `.onTapGesture` so gestures arbitrate cleanly.
- Add light haptic (`UIImpactFeedbackGenerator(style: .soft)`) on state transition. Guard against firing on every `sheetState` assignment — only when previous state != new state.
- Every `.animation(...)` must be `value:`-scoped. NO blanket `withAnimation { ... }` around state changes.
- In `onEnded`: set state and reset dragOffset as BARE assignments. The existing `.animation(value: showsMinimized)` handles state transitions; add `.animation(value: dragOffset)` with `.interactiveSpring()` for drag offset. Two independent animation scopes — don't wrap either in `withAnimation`.
- When drag threshold is crossed AND state is about to change, reset `dragOffset = 0` inside a `Transaction(animation: nil)` to avoid double-animation (layout change + slide-back).

### Stage 5: Polish and accessibility
**Goal**: Visual polish, state restoration correctness, accessibility
**Tests**: Test on SE3 simulator, iPhone 17 Pro, XXL text, both themes, VoiceOver
**Files**: `WalkStatsSheet.swift`, `ActiveWalkView.swift`, `PilgrimMapView.swift`

**Additions:**
- **Sheet visual styling**: Rounded top corners (20pt radius, .continuous) and shadow (`ink.opacity(0.15)`, radius 12, y: -4). Use `UnevenRoundedRectangle` for top-only corners. Verify shadow doesn't clip through `.ignoresSafeArea(edges: .bottom)`.
- **`minimizedSheetHeight` should scale with dynamic type** OR — better — switch to `.safeAreaInset(edge: .bottom) { bottomSheet }` on the ZStack contents. This makes the ambient overlay automatically respect the sheet's content-driven height and eliminates the hardcoded constant.
- **Mapbox camera padding**: Verify user location marker isn't hidden under the sheet. Add a `bottomInset: CGFloat` parameter to `PilgrimMapView` and pass the minimized sheet height.
- **Mapbox battery cost**: Full-screen map rasterizes ~40% more pixels. Expect ~1-3% extra battery/hour. Accepted; revisit in Battery Optimization project.
- **VoiceOver focus order**: Verify traversal is top buttons → stats sheet. Mark map, weather overlay, and `floatingGreetings` as `accessibilityHidden`.
- **Group expanded sheet stats into a single VoiceOver element** via `.accessibilityElement(children: .combine)` so users don't traverse every stat individually.
- **Dynamic Island**: Verify `mapOverlayButtons` clears the island on iPhone 15 Pro and later.
- **Haptic debounce**: Guard haptic firing on actual state change, not on every assignment.
- **SE3 testing**: Actually run on 4.7" simulator at accessibility3+ text size to verify the collapsible design solves the crowding.
- **iPad landscape**: Cap `bottomSheet` width at 600pt via `.frame(maxWidth: 600)` so it doesn't stretch edge-to-edge on iPad.
- **Audio indicators in paused state**: Decide if audio indicators should be accessible during pause. If yes, move them into the top overlay or expanded sheet header — they're currently hidden behind the expanded sheet.

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Animation causes re-render storms during walk | Use `.animation(value:)` tied to explicit state, not blanket `withAnimation` |
| Drag gesture captures taps meant for controls | Use `simultaneousGesture` or limit drag to drag handle area |
| Sheet covers map user location marker | Map's viewport follows user — when user is at bottom of visible map, they'll still see themselves |
| Memory leak from drag gesture closures | Use `@State` local to sheet, no captured `self` references |
| Resource safety violations (per CLAUDE.md) | No timers, no audio players, no Combine subscriptions in sheet — just pure view state |
| Breaking existing functionality | Stage 1 is pure extraction with zero behavior change |

## Out of Scope for This PR

- Changing the `LivePaceSparklineView` placement
- Changing the audio indicators or weather/celestial vignettes
- Changing meditation view
- Changing the options/intention/waypoint sheets
- Adding new stats to the expanded view
