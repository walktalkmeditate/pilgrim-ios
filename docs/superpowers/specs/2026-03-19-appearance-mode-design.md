# Appearance Mode — Design Spec

## Summary

Add a user-facing appearance mode toggle to Pilgrim, allowing users to override iOS system appearance (light/dark) within the app. Three options: System, Light, Dark.

## Motivation

Pilgrim is used during walks at all hours — dawn, dusk, night. A pilgrim walking a Camino stage at 5am shouldn't be blasted with light mode because their phone is set that way for daytime use. Conversely, someone meditating indoors at noon might want dark mode's calm. This gives the pilgrim control over their walking environment independent of iOS settings.

## Design

### Data Model

**`AppearanceMode` enum** with three cases:

| Case | Raw string | Resolved `ColorScheme?` | Behavior |
|------|-----------|------------------------|----------|
| `.system` | `"system"` | `nil` | Follow iOS setting |
| `.light` | `"light"` | `.light` | Always light in Pilgrim |
| `.dark` | `"dark"` | `.dark` | Always dark in Pilgrim |

Stored in `UserPreferences` as a `UserPreference.Required<String>` with default `"system"`. Raw string storage matches existing preference patterns (e.g., zodiac system). Existing users who upgrade receive `"system"` by default — no behavioral change.

### AppearanceManager

A lightweight `ObservableObject` created and owned as `@StateObject` in `PilgrimApp.swift`:

- `@Published var resolvedScheme: ColorScheme?` — `nil` means follow system
- Subscribes to `UserPreferences.appearanceMode.publisher` to react to settings changes
- Maps the stored string to the resolved `ColorScheme?` — pure mapping, no computation

### Settings UI

New "Appearance" section in `GeneralSettingsView`, placed as the **first section** (before Walk):

- 3-way segmented `Picker` (`.pickerStyle(.segmented)`) with options: System, Light, Dark
- Section header: "Appearance"
- All text uses `Constants.Typography`
- Follows existing settings patterns

New localization strings needed: "Appearance" (section header), "System", "Light", "Dark" (picker segments).

The effect applies immediately — no separate preview needed.

### Root Integration

- `AppearanceManager` instantiated as `@StateObject` in `PilgrimApp.swift`
- `.preferredColorScheme(appearanceManager.resolvedScheme)` applied to root view content inside `WindowGroup`
- `AppearanceManager` passed into environment via `.environmentObject()` for settings access

### Transition Animation

`.preferredColorScheme()` causes a system-level trait change not controllable via SwiftUI's `withAnimation`. For a gentle crossfade:

```swift
UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve, animations: {}, completion: nil)
```

`AppearanceManager` triggers this on the app's key window before updating `resolvedScheme`. Window reference obtained via `UIApplication.shared.connectedScenes`.

### Propagation

Existing `@Environment(\.colorScheme)` usage in `PilgrimMapView`, `WalkCard`, `MoonPhaseView`, `InkScrollView+LunarMarkers`, and color assets will automatically receive the overridden value through SwiftUI's trait propagation.

**Note on `SeasonalColorEngine`**: it resolves base colors via `UITraitCollection.current`, which should reflect the override when called during view layout. Verify during implementation; if not, pass explicit trait collection to `resolvedColor(with:)`.

## Scope

### In scope

- `AppearanceMode` enum and `UserPreferences` key
- `AppearanceManager` (ObservableObject with Combine subscription)
- Appearance section with segmented picker in `GeneralSettingsView`
- Root-level `.preferredColorScheme()` integration in `PilgrimApp.swift`
- Crossfade animation via `UIView.transition`
- Localization strings via existing `LS` pattern

### Out of scope

- Follow the Sun / celestial-aware auto-switching (future consideration)
- Dawn/dusk intermediate palette (future consideration)
- UIKit window override fallback for Mapbox (only if trait propagation doesn't reach the map)

## Risks

- **Mapbox trait propagation**: `.preferredColorScheme()` should propagate to UIKit representables, but Mapbox's map view may need verification. Mitigation: test during implementation, add targeted `overrideUserInterfaceStyle` on the map's hosting view if needed.
- **SeasonalColorEngine trait context**: `UITraitCollection.current` in static method calls may not always reflect the override. Mitigation: verify during implementation, pass explicit trait if needed.
