# Appearance Mode — Design Spec

## Summary

Add a user-facing appearance mode picker to Pilgrim, allowing users to override iOS system appearance (light/dark) within the app. Includes a celestial-aware "Follow the Sun" option that automatically switches based on sunrise/sunset at the user's location.

## Motivation

Pilgrim is used during walks at all hours — dawn, dusk, night. A pilgrim walking a Camino stage at 5am shouldn't be blasted with light mode because their phone is set that way for daytime use. Conversely, someone meditating indoors at noon might want dark mode's calm. This gives the pilgrim control over their walking environment independent of iOS settings.

## Design

### Data Model

**`AppearanceMode` enum** with four cases:

| Case | Raw string | Resolved `ColorScheme?` | Behavior |
|------|-----------|------------------------|----------|
| `.system` | `"system"` | `nil` | Follow iOS setting |
| `.light` | `"light"` | `.light` | Always light in Pilgrim |
| `.dark` | `"dark"` | `.dark` | Always dark in Pilgrim |
| `.followTheSun` | `"followTheSun"` | `.light` or `.dark` | Light after sunrise, dark after sunset |

Stored in `UserPreferences` as a `UserPreference.Required<String>` with default `"system"`. Raw string storage matches existing preference patterns (e.g., zodiac system). Existing users who upgrade receive `"system"` by default — no behavioral change.

### Sunrise/Sunset Calculator

The existing `CelestialCalculator` computes solar longitude (ecliptic coordinates) but not observer-dependent sunrise/sunset times. A new `SunCalculator` utility is needed:

- Computes sunrise and sunset times from latitude, longitude, and date
- Uses the standard solar altitude equation (sun center at -0.833 degrees below horizon, accounting for atmospheric refraction)
- Pure computation — no network calls, no external API
- Can extend `CelestialCalculator` or be a standalone struct (implementation decision)

**Location source for Follow the Sun:**

- Primary: last recorded walk location from CoreStore (most recent `RouteDataSample` latitude/longitude)
- Fallback: if no walks have been recorded, "Follow the Sun" option is hidden (same as when celestial awareness is off) — the user must complete at least one walk before this option appears
- Location does not need to be real-time for sunrise/sunset — even a day-old location gives accurate enough sunrise/sunset times (they shift by seconds, not minutes, for typical daily movement)

### AppearanceManager

A lightweight `ObservableObject` created and owned in `PilgrimApp.swift`:

- `@Published var resolvedScheme: ColorScheme?` — `nil` means follow system
- Reads `AppearanceMode` from `UserPreferences`
- For `.system`, `.light`, `.dark`: direct mapping, no computation
- For `.followTheSun`: uses `SunCalculator` with last walk location to determine if current time is between sunrise and sunset
- Schedules a single timer for the next sunrise or sunset transition (whichever comes first), then re-evaluates. Timer cancelled in `deinit` and when mode changes away from `.followTheSun`
- Subscribes to `UserPreferences.celestialAwarenessEnabled.publisher` (Combine). If celestial awareness is turned off while `.followTheSun` is active, immediately resets stored preference to `"system"` and updates `resolvedScheme` to `nil`
- Subscribes to `UserPreferences.appearanceMode.publisher` to react to settings changes

### Settings UI

New "Appearance" section in `GeneralSettingsView`, placed as the **first section** (before Walk):

- `Picker` showing available options
- When celestial awareness is **off** or no walk location exists: System, Light, Dark (3 options)
- When celestial awareness is **on** and walk location exists: System, Light, Dark, Follow the Sun (4 options)
- All text uses `Constants.Typography`
- Follows existing settings patterns for pickers

New localization strings needed: "Appearance" (section header), "System", "Light", "Dark", "Follow the Sun" (picker options).

No separate preview needed — the effect applies immediately via the root modifier.

### Root Integration

- `AppearanceManager` instantiated as `@StateObject` in `PilgrimApp.swift`
- `.preferredColorScheme(appearanceManager.resolvedScheme)` applied to root view content inside `WindowGroup`
- `AppearanceManager` passed into environment via `.environmentObject()` for settings access

### Transition Animation

`.preferredColorScheme()` causes a system-level trait change that is not controllable via SwiftUI's `withAnimation`. For a gentle crossfade, use the standard UIKit technique:

```swift
UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve, animations: {}, completion: nil)
```

`AppearanceManager` triggers this on the app's key window before updating `resolvedScheme`. Window reference obtained via `UIApplication.shared.connectedScenes`.

### Propagation

Existing `@Environment(\.colorScheme)` usage in `PilgrimMapView`, `WalkCard`, `MoonPhaseView`, `InkScrollView+LunarMarkers`, and color assets will automatically receive the overridden value through SwiftUI's trait propagation.

**Note on `SeasonalColorEngine`**: it resolves base colors via `UITraitCollection.current`, which should reflect the override when called during view layout (since `.preferredColorScheme()` sets traits on the hosting controller). Verify during implementation that seasonal colors resolve correctly in the overridden mode; if not, pass explicit trait collection to `resolvedColor(with:)`.

## Scope

### In scope

- `AppearanceMode` enum and `UserPreferences` key
- `SunCalculator` for sunrise/sunset computation
- `AppearanceManager` with sun-aware logic
- Appearance section in `GeneralSettingsView`
- Root-level `.preferredColorScheme()` integration
- Crossfade animation via `UIView.transition`
- Graceful fallback when celestial awareness is disabled
- Localization strings via existing `LS` pattern

### Out of scope

- Dawn/dusk intermediate palette (future consideration)
- UIKit window override fallback for Mapbox (only needed if trait propagation doesn't reach the map)
- Real-time location updates for Follow the Sun (last walk location is sufficient)

## Risks

- **Mapbox trait propagation**: `.preferredColorScheme()` should propagate to UIKit representables, but Mapbox's map view may need verification. Mitigation: test during implementation, add targeted `overrideUserInterfaceStyle` on the map's hosting view if needed.
- **Timer lifecycle**: the sunrise/sunset timer in `AppearanceManager` must be properly cancelled to avoid resource leaks per project resource safety guidelines. Mitigation: cancel in `deinit` and when mode changes away from `.followTheSun`.
- **SeasonalColorEngine trait context**: `UITraitCollection.current` in static method calls may not always reflect the override. Mitigation: verify during implementation, pass explicit trait if needed.
- **Follow the Sun during active walks**: appearance will change at sunrise/sunset, which could be momentarily surprising. This is intentional — the gentle crossfade makes it feel natural rather than jarring.
