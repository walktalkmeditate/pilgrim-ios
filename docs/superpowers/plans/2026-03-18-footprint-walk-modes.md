# Footprint Walk Mode Visuals — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the footprint display above the path screen's mode selector respond to Wander/Together/Seek with distinct arrangements and a breath transition between them.

**Architecture:** Replace the static `footprintPair` in `WalkStartView` with a mode-aware `footprintDisplay` that switches arrangement based on `activeMode`. A generation-counter-guarded `onChange` drives a breath transition (exhale → pause → inhale) when the user taps between modes.

**Tech Stack:** SwiftUI, FootprintShape (existing custom Shape)

**Spec:** `docs/superpowers/specs/2026-03-18-footprint-walk-modes-design.md`

---

### Task 1: Add transition state and replace footprintPair reference

**Files:**
- Modify: `Pilgrim/Scenes/Home/WalkStartView.swift`

- [ ] **Step 1: Add new state properties after line 16**

Add these three state vars after `entranceGeneration`:

```swift
@State private var activeMode: WalkMode = .wander
@State private var footprintVisible = true
@State private var transitionGeneration = 0
```

- [ ] **Step 2: Replace `footprintPair` reference in content**

Change line 110 from:
```swift
footprintPair
    .padding(.bottom, Constants.UI.Padding.normal)
```
to:
```swift
footprintDisplay
    .padding(.bottom, Constants.UI.Padding.normal)
```

- [ ] **Step 3: Add onChange handler for breath transition**

Add this after the existing `.onChange(of: selectedMode)` block (after line 35):

```swift
.onChange(of: selectedMode) { _, newMode in
    if UIAccessibility.isReduceMotionEnabled {
        activeMode = newMode
        return
    }
    transitionGeneration += 1
    let gen = transitionGeneration
    withAnimation(.easeIn(duration: 0.3)) {
        footprintVisible = false
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
        guard transitionGeneration == gen else { return }
        activeMode = newMode
        withAnimation(.easeOut(duration: 0.3)) {
            footprintVisible = true
        }
    }
}
```

Note: There are now two `.onChange(of: selectedMode)` handlers — the existing one handles quote transitions, the new one handles footprint transitions. SwiftUI calls both.

- [ ] **Step 4: Reset transition state in onDisappear**

Add inside the existing `.onDisappear` block (around line 37):
```swift
transitionGeneration += 1
footprintVisible = true
activeMode = .wander
```

- [ ] **Step 5: Build to verify compiles**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build`
Expected: BUILD SUCCEEDED (with `footprintDisplay` not yet defined — will error. Skip this step if it errors, it's resolved in Task 2.)

---

### Task 2: Implement the three footprint arrangements

**Files:**
- Modify: `Pilgrim/Scenes/Home/WalkStartView.swift`

- [ ] **Step 1: Replace the `footprintPair` computed property (lines 137-151) with `footprintDisplay`**

Replace the entire `// MARK: - Footprint Pair` section with:

```swift
// MARK: - Footprint Display

private var footprintDisplay: some View {
    Group {
        switch activeMode {
        case .wander: wanderFootprints
        case .together: togetherFootprints
        case .seek: seekFootprints
        }
    }
    .scaleEffect(footprintVisible ? 1.0 : (footprintVisible ? 1.0 : 1.08))
    .opacity(footprintVisible ? 1.0 : 0.0)
    .accessibilityHidden(true)
}

private var wanderFootprints: some View {
    HStack(spacing: 2) {
        FootprintShape()
            .fill(Color.ink.opacity(0.08))
            .frame(width: 16, height: 26)
            .scaleEffect(x: -1)
            .rotationEffect(.degrees(-12))

        FootprintShape()
            .fill(Color.ink.opacity(0.06))
            .frame(width: 16, height: 26)
            .rotationEffect(.degrees(12))
    }
}

private var togetherFootprints: some View {
    ZStack {
        // Left pair (behind, offset left)
        HStack(spacing: 2) {
            FootprintShape()
                .fill(Color.ink.opacity(0.06))
                .frame(width: 14, height: 22)
                .scaleEffect(x: -1)
                .rotationEffect(.degrees(-18))
            FootprintShape()
                .fill(Color.ink.opacity(0.05))
                .frame(width: 14, height: 22)
                .rotationEffect(.degrees(6))
        }
        .offset(x: -14, y: -10)

        // Right pair (behind, offset right)
        HStack(spacing: 2) {
            FootprintShape()
                .fill(Color.ink.opacity(0.05))
                .frame(width: 14, height: 22)
                .scaleEffect(x: -1)
                .rotationEffect(.degrees(8))
            FootprintShape()
                .fill(Color.ink.opacity(0.04))
                .frame(width: 14, height: 22)
                .rotationEffect(.degrees(-16))
        }
        .offset(x: 12, y: -8)

        // Front pair (yours, centered)
        HStack(spacing: 2) {
            FootprintShape()
                .fill(Color.ink.opacity(0.10))
                .frame(width: 16, height: 26)
                .scaleEffect(x: -1)
                .rotationEffect(.degrees(-12))
            FootprintShape()
                .fill(Color.ink.opacity(0.08))
                .frame(width: 16, height: 26)
                .rotationEffect(.degrees(12))
        }
    }
    .frame(width: 60, height: 50)
}

private var seekFootprints: some View {
    HStack(spacing: 2) {
        // Solid left foot
        FootprintShape()
            .fill(Color.ink.opacity(0.10))
            .frame(width: 16, height: 26)
            .scaleEffect(x: -1)
            .rotationEffect(.degrees(-12))

        // Dissolving right — scattered dots
        dissolvingDots
            .frame(width: 16, height: 30)
            .rotationEffect(.degrees(12))
    }
}

private var dissolvingDots: some View {
    Canvas { context, size in
        let dots: [(x: CGFloat, y: CGFloat, r: CGFloat, a: Double)] = [
            (0.5, 0.85, 2.5, 0.08),
            (0.3, 0.65, 2.0, 0.07),
            (0.7, 0.55, 2.0, 0.06),
            (0.4, 0.38, 1.5, 0.04),
            (0.6, 0.20, 1.5, 0.03),
            (0.5, 0.05, 1.0, 0.02),
        ]
        for dot in dots {
            let rect = CGRect(
                x: size.width * dot.x - dot.r,
                y: size.height * dot.y - dot.r,
                width: dot.r * 2,
                height: dot.r * 2
            )
            context.fill(Circle().path(in: rect), with: .color(.ink.opacity(dot.a)))
        }
    }
}
```

- [ ] **Step 2: Fix the scaleEffect logic in footprintDisplay**

The `scaleEffect` line should use a ternary that differentiates exhale vs inhale. Replace the `.scaleEffect` and `.opacity` lines in `footprintDisplay` with:

```swift
.scaleEffect(footprintVisible ? 1.0 : 1.08)
.opacity(footprintVisible ? 1.0 : 0.0)
```

Note: The exhale scales UP to 1.08 when `footprintVisible` becomes false. The inhale starts at 0.92 and scales to 1.0 — but since we set `footprintVisible = true` with `.easeOut`, the view appears at whatever SwiftUI interpolates from. For a cleaner inhale, the `activeMode` change swaps the view identity (new arrangement fades in at scale 1.0 via the easeOut), which handles the visual naturally.

- [ ] **Step 3: Build and verify**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```
git add Pilgrim/Scenes/Home/WalkStartView.swift
git commit -m "feat: mode-aware footprint display with breath transition

Wander shows solo pair, Together shows three overlapping pairs,
Seek shows one solid foot with dissolving dots. Breath transition
(exhale/pause/inhale) animates between modes with generation
counter for rapid-tap safety."
```

---

### Task 3: Add Seek float animation

**Files:**
- Modify: `Pilgrim/Scenes/Home/WalkStartView.swift`

- [ ] **Step 1: Add float state**

Add after the `transitionGeneration` state var:

```swift
@State private var seekFloatOffset: CGFloat = 0
```

- [ ] **Step 2: Apply float to dissolving dots in seekFootprints**

Wrap the `dissolvingDots` in the `seekFootprints` view with the offset and onAppear:

```swift
// Dissolving right — scattered dots
dissolvingDots
    .frame(width: 16, height: 30)
    .rotationEffect(.degrees(12))
    .offset(y: seekFloatOffset)
    .onAppear {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
            seekFloatOffset = -2
        }
    }
    .onDisappear {
        seekFloatOffset = 0
    }
```

- [ ] **Step 3: Reset float in onDisappear**

Add to the existing `.onDisappear` block:
```swift
seekFloatOffset = 0
```

- [ ] **Step 4: Build and verify**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```
git add Pilgrim/Scenes/Home/WalkStartView.swift
git commit -m "feat: add subtle float animation to Seek dissolving dots"
```

---

### Task 4: Visual verification

- [ ] **Step 1: Run in simulator and verify all three modes**

Launch the app in simulator. On the path screen:
- **Wander** (default): Single pair of footprints, same as before
- Tap **Together**: Breath transition plays, three overlapping pairs appear with depth
- Tap **Seek**: Breath transition plays, one solid foot + dissolving dots floating gently upward
- Tap back to **Wander**: Breath transition returns to single pair

- [ ] **Step 2: Test rapid tapping**

Quickly tap Wander → Together → Seek within 0.5s. Only the final mode (Seek) should render after the transition. No flashing of intermediate states.

- [ ] **Step 3: Test reduce motion**

Enable Settings → Accessibility → Reduce Motion in simulator. Switch modes — should be instant crossfade with no scale animation. Seek dots should be static (no float).

- [ ] **Step 4: Test re-entrance**

Switch to Settings tab, then back to Path tab. Footprints should show Wander (default reset).
