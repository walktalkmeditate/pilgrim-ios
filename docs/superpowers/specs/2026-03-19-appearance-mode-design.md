# Appearance Mode — Design Spec

## Summary

Add a user-facing appearance mode picker to Pilgrim, allowing users to override iOS system appearance (light/dark) within the app. Includes a celestial-aware "Follow the Sun" option that automatically switches based on sunrise/sunset at the user's location.

## Motivation

Pilgrim is used during walks at all hours — dawn, dusk, night. A pilgrim walking a Camino stage at 5am shouldn't be blasted with light mode because their phone is set that way for daytime use. Conversely, someone meditating indoors at noon might want dark mode's calm. This gives the pilgrim control over their walking environment independent of iOS settings.

## Design

### Data Model

**`AppearanceMode` enum** with four cases:

| Case | Resolved `ColorScheme?` | Behavior |
|------|------------------------|----------|
| `.system` | `nil` | Follow iOS setting |
| `.light` | `.light` | Always light in Pilgrim |
| `.dark` | `.dark` | Always dark in Pilgrim |
| `.followTheSun` | `.light` or `.dark` | Light after sunrise, dark after sunset |

Stored in `UserPreferences` as a `UserPreference.Required<String>` with default `"system"`. Raw string storage matches existing preference patterns (e.g., zodiac system).

### AppearanceManager

A lightweight `ObservableObject` that publishes the resolved appearance:

- `@Published var resolvedScheme: ColorScheme?` — `nil` means follow system
- Reads `AppearanceMode` from `UserPreferences`
- For `.system`, `.light`, `.dark`: direct mapping, no computation
- For `.followTheSun`: reads sunrise/sunset from the existing celestial awareness system, compares against current time
- Uses a single scheduled timer targeting the next sunrise/sunset transition (not polling)
- **Fallback**: if celestial awareness is turned off while `.followTheSun` is active, resets preference to `.system`

### Settings UI

New "Appearance" section in `GeneralSettingsView`, placed as the **first section** (before Walk):

- `Picker` showing available options
- When celestial awareness is **off**: System, Light, Dark (3 options)
- When celestial awareness is **on**: System, Light, Dark, Follow the Sun (4 options)
- All text uses `Constants.Typography`
- Follows existing settings patterns for pickers

No separate preview needed — the effect applies immediately via the root modifier.

### Root Integration

- `AppearanceManager` created and owned at the app level (`PilgrimApp.swift` or `RootCoordinatorView`)
- `.preferredColorScheme(appearanceManager.resolvedScheme)` applied to root view content inside `WindowGroup`
- Transition animated with `withAnimation(.easeInOut(duration: 0.3))` on resolved scheme changes for a gentle crossfade
- `AppearanceManager` injected into environment for settings access

### Propagation

No changes needed to individual views. Existing `@Environment(\.colorScheme)` usage in `PilgrimMapView`, `WalkCard`, `MoonPhaseView`, `InkScrollView+LunarMarkers`, and color assets will automatically receive the overridden value through SwiftUI's trait propagation.

## Scope

### In scope

- `AppearanceMode` enum and `UserPreferences` key
- `AppearanceManager` with sun-aware logic
- Appearance section in `GeneralSettingsView`
- Root-level `.preferredColorScheme()` integration
- Gentle crossfade animation on transitions
- Graceful fallback when celestial awareness is disabled

### Out of scope

- Dawn/dusk intermediate palette (future consideration)
- UIKit window override fallback (only needed if Mapbox doesn't pick up trait changes)
- Localization of new strings (will use existing `LS` pattern)

## Risks

- **Mapbox trait propagation**: `.preferredColorScheme()` should propagate to UIKit representables, but Mapbox's map view may need verification. Mitigation: test during implementation, add targeted `overrideUserInterfaceStyle` on the map's hosting view if needed.
- **Timer lifecycle**: the sunrise/sunset timer in `AppearanceManager` must be properly cancelled to avoid resource leaks per project resource safety guidelines. Mitigation: cancel in `deinit` and when mode changes away from `.followTheSun`.
