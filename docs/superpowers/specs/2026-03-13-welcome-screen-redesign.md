# Welcome Screen Redesign — "The Threshold"

## Overview

Redesign the Pilgrim onboarding from a 3+ screen setup flow into a two-screen journey with a cinematic transition into the app. The onboarding should feel like crossing a threshold, not filling out forms.

**Current flow:** Welcome (feature cards + Begin Setup) → 3 separate permission screens → app
**New flow:** The Threshold (emotional) → Preparing for the Journey (practical) → The Breath (transition) → app

## Screen 1: The Threshold

The first screen the user ever sees. Pure emotion, zero information. An arrival.

### Choreographed Entrance Animation

The screen builds itself piece by piece with deliberate pacing:

| Time | Event |
|------|-------|
| 0.0s | Pure parchment — nothing on screen |
| 0.5s | Logo fades in + scales (0.85 → 1.0) over ~1.5s with `.easeInOut` |
| 2.0s | Logo begins continuous breathing cycle (never stops) |
| 2.5s | Tagline fades in, line by line |
| 3.5s | First footprint pair fades in with light haptic tap |
| 4.2s | Second footprint pair fades in with light haptic tap |
| 4.9s | Third footprint pair fades in, holds briefly, then fades |
| 5.5s | "Begin" button slides up from below with warm haptic pulse |
| 6.0s | Ambient background gradient begins slow drift |

### Breathing Logo

`PilgrimLogoView` gains a continuous breathing mode:
- Scale oscillates 1.0 → 1.02 → 1.0 on a ~8-second cycle (4s inhale, 4s exhale — matches `MeditationView` breathing cadence)
- Uses `.easeInOut`
- Begins after the entrance fade-in completes
- Driven by a `@State var isBreathing: Bool` flag — set to `false` to cleanly stop the cycle before exit animation
- Never stops while on screen (until exit begins)

### Rotating Wisdom Quotes

Each app launch shows a randomly selected quote from a pool of ~6 walking/pilgrimage quotes. Displayed in two lines, centered below the logo, `displayMedium` font, `.fog` color.

Quote pool:
- "Every journey begins with a single step"
- "The path is made by walking"
- "Not all who wander are lost"
- "Solvitur ambulando — it is solved by walking"
- "Walk as if you are kissing the earth with your feet"
- "The journey of a thousand miles begins beneath your feet"

### Footprint Animation

Three pairs of footprints appear sequentially between the tagline and the Begin button, leading the eye downward.

**Visual design:**
- Custom `Shape` — two small angled ovals per step (left foot, right foot)
- Alternating slight left/right offset per pair, mimicking a natural gait
- Color: `.fog` — subtle, like impressions in sand
- Wabi-sabi aesthetic: imperfect, organic shapes — not clip-art shoe prints

**Animation behavior:**
- Each pair fades in over ~0.3s at walking cadence (~0.7s between pairs)
- After appearing, each pair fades to ~15% opacity over ~1s (ghost impressions)
- The third/last pair holds at full opacity slightly longer before fading
- Each pair triggers `UIImpactFeedbackGenerator(.light)` on appearance

### Ambient Background

A slow-moving radial gradient behind the main content:
- Uses `parchment` as the base with a very subtle warmer tint at the gradient center
- Gradient center point drifts slowly (~30-second cycle) using a repeating animation
- Barely perceptible — creates warmth and life without being consciously noticed

### Begin Button

A centered button — **not** the existing `ActionButton` (which has a chevron.right that feels wrong for a threshold moment). Instead, a simple centered label:
- Text: "Begin" in `Constants.Typography.button`, `.parchment` color
- Full-width stone background with `CornerRadius.normal`
- `.padding(.vertical, 12)` — same height feel as ActionButton but without the chevron
- No arrow, no icon — just the word.

### Exit Animation (on Begin tap)

Everything fades out in reverse order, creating a mirror of the entrance:
1. Set `isBreathing = false` — breathing animation settles to scale 1.0
2. Begin button slides down + fades (0.3s)
3. Footprints fade to 0 (0.3s, overlapping)
4. Tagline fades out (0.3s)
5. Logo fades + scales down slightly (0.5s)
6. Brief beat of pure parchment before Screen 2 content fades in

Total exit: ~1s. Feels like the trailhead dissolving as you step onto the path.

## Screen 2: Preparing for the Journey

One screen, three permission cards. The practical moment — packing your bag before the walk.

### Layout

- Heading: "Prepare for the journey" — `displayMedium` font, `.stone` color, centered
- Subtitle: "Pilgrim walks best with these" — `caption` font, `.fog` color, centered
- Three permission cards stacked vertically with `Constants.UI.Padding.normal` spacing

### Permission Cards

Cards use `parchmentSecondary` background and `CornerRadius.normal` (from `FeatureView`'s styling). The layout follows the existing `PermissionView` HStack pattern with the addition of an SF Symbol icon on the left.

| Order | SF Symbol | Title | Description | Required |
|-------|-----------|-------|-------------|----------|
| 1 | `location.fill` | "To walk with you" | "Track your route, distance, and pace" | Yes |
| 2 | `mic.fill` | "To hear your thoughts" | "Capture voice reflections along the way" | Yes |
| 3 | `figure.walk` | "To count your steps" | "Measure steps as you move" | No — labeled "(optional)" in `.fog` |

**Card structure:**
- Left side: icon (`.stone`, large) + title (`heading` font, `.ink`) + description (`caption`, `.fog`)
- Right side: "Grant" button (`.stone` outline style)

### Grant Flow

**On "Grant" tap:** Triggers the iOS system permission dialog.

**If granted:**
- "Grant" button transforms into a checkmark icon
- Card gets a subtle `.moss` tint (color of life/growth) — very light background shift
- Smooth transition animation (~0.3s)

**If denied (Location or Mic — required):**
- Gentle shake animation on the card (horizontal, ~3 oscillations)
- Helper text appears below the card: "Pilgrim needs this to walk with you" in `.fog`
- "Grant" button remains — subsequent taps open iOS Settings via `UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)` (navigates to the app's Settings page where the user can toggle permissions)

**If denied (Motion — optional):**
- Card accepts gracefully — button becomes a subtle "Skipped" label in `.fog`
- No shake, no pressure, no helper text

### Auto-Transition Trigger

Once Location AND Microphone are both granted, the auto-transition fires immediately — Motion is optional and does not gate the transition. If the user hasn't interacted with the Motion card yet, it is treated as skipped by omission.

**Behavior change from current app:** The existing `SetupPermissionsView` only requires Location to continue. This redesign requires both Location AND Microphone before `UserPreferences.isSetUp.value` is set to `true`.

- 0.8s pause after the last required permission is granted (stillness before the crossing)
- The Breath Transition begins automatically
- No additional button tap required — the path opens when you're ready

## The Breath Transition

The crossing from onboarding into the app. Subtle, somatic, unforgettable.

### Sequence

| Phase | Duration | Visual | Haptic |
|-------|----------|--------|--------|
| **Stillness** | 0.8s | Nothing moves. Nervous system registers a shift is coming. | None |
| **Inhale** | ~1.2s | Screen scales 1.0 → 1.015. Permission cards dissolve (opacity → 0). A single ghostly footprint appears center-screen. | None |
| **Peak** | 0.3s | Footprint holds. Scale holds at 1.015. | Single warm pulse: `UIImpactFeedbackGenerator(.soft)` |
| **Exhale** | ~1.2s | Scale returns 1.015 → 1.0. Footprint fades. Main app content fades in (opacity 0 → 1). | None |
| **Settle** | 0.6s | Main screen elements drift up ~3pt to their final positions. | None |

Total: ~4s

### Color Warmth Shift

During the entire onboarding, the parchment background has a barely perceptible golden warmth via `.overlay(Color.yellow.opacity(0.02))`. During the exhale phase, the overlay opacity animates to 0, shifting to standard parchment. Subliminal — you can't see it, you feel it.

### The Ghostly Footprint

A single footprint (same custom shape as the threshold screen) appears centered during the inhale, holds at the peak, and dissolves during the exhale. The path that led you here has disappeared. You've arrived.

## Files to Change

### New Files
- `Pilgrim/Views/FootprintShape.swift` — custom SwiftUI `Shape` for the two-oval footprint
- `Pilgrim/Scenes/Setup/Welcome/WelcomeAnimationState.swift` — `ObservableObject` managing the choreographed entrance/exit animation timeline
- `Pilgrim/Scenes/Setup/Permissions/PermissionsView.swift` — the consolidated "Preparing for the Journey" screen
- `Pilgrim/Scenes/Setup/Permissions/PermissionsViewModel.swift` — permission state tracking, grant flow, auto-transition trigger
- `Pilgrim/Scenes/Setup/BreathTransitionView.swift` — the inhale/peak/exhale crossing animation

### Modified Files
- `Pilgrim/Scenes/Setup/Welcome/WelcomeView.swift` — gutted and rebuilt as The Threshold
- `Pilgrim/Scenes/Setup/Welcome/WelcomeViewModel.swift` — simplified to quote pool + Begin action
- `Pilgrim/Views/PilgrimLogoView.swift` — add continuous breathing animation mode
- `Pilgrim/Scenes/Setup/SetupCoordinatorView.swift` — new flow: Threshold → Permissions → Breath → app

### Removed / Deprecated
- Feature cards no longer shown on welcome screen (`FeatureView`/`FeatureViewModel` stay in codebase — may be used elsewhere)
- `Pilgrim/Scenes/Setup/SetupView.swift` — replaced by direct Threshold → Permissions flow
- `Pilgrim/Scenes/Setup/SetupViewModel.swift` — step management no longer needed
- `Pilgrim/Scenes/Setup/SetupCoordinatorViewModel.swift` — simplified; may be gutted or replaced
- `Pilgrim/Scenes/Setup/Steps/SetupPermissionsView.swift` — replaced by new `PermissionsView`
- Any other step views under `Pilgrim/Scenes/Setup/Steps/` (e.g., `SetupStepBaseView`, `SetupFormalitiesView`, `SetupUserInfoView`) — replaced by consolidated flow

### Not Touched
- No data model changes
- No CoreStore migration
- No changes to walk recording, voice recording, or any functional code
- `ActionButton`, `Constants`, color definitions — unchanged
- `PermissionManager.swift` — used as-is for requesting permissions

## Design System Alignment

All animations use existing `Constants.UI.Motion` values where applicable:
- `Constants.UI.Motion.gentle` (0.6s) for card transitions, settle effects
- `Constants.UI.Motion.breath` (1.2s) for the inhale/exhale phases
- `Constants.UI.Motion.appear` (0.4s) for quick element appearances
- Custom longer durations (4s breathing cycle, 30s ambient drift) where the design requires it

Colors: `.stone`, `.fog`, `.ink`, `.parchment`, `.parchmentSecondary`, `.moss` — all existing palette. The warm parchment variant is the only new color consideration (may be a simple opacity overlay rather than a new named color).

Typography: `displayMedium`, `heading`, `caption`, `button` — all existing `Constants.Typography`.

Haptics: New to the codebase. Uses inline `UIImpactFeedbackGenerator` calls — no wrapper/manager needed for this scope. Two styles: `.light` (footstep taps) and `.soft` (breath peak pulse).

## Edge Cases

- **User kills app during onboarding:** No state persisted until permissions are granted. Relaunching restarts from The Threshold. This is fine — it's a 30-second experience.
- **Permissions already granted (reinstall):** If permissions were previously granted at OS level, cards start in the granted state. If all required are already granted, auto-transition triggers after a brief delay — the user barely sees Screen 2.
- **Accessibility / Reduce Motion:** If the user has "Reduce Motion" enabled in iOS settings, all animations collapse to simple cross-fades. The choreography simplifies but the flow remains the same. Breathing logo becomes static. Footprints appear all at once. Breath transition becomes a simple fade.
- **VoiceOver:** All elements need accessibility labels. Footprints are decorative (`.accessibilityHidden(true)`). Animation states announced appropriately.
- **Screen sizes:** Layout uses flexible spacing (Spacers) to adapt. Footprints and cards should work on iPhone SE through Pro Max.

## Localization

All user-facing strings (quotes, permission titles/descriptions, button labels, helper text) must be added to `Localizable.strings` via `LS` keys, following the existing localization pattern in `Pilgrim/Models/LS.swift`.
