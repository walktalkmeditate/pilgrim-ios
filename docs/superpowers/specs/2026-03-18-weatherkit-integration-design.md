# WeatherKit Integration Design

## Context

Pilgrim already responds to time-of-day (background tinting) and season (scenery colors, animations). Weather is the missing third dimension. With the Apple Developer Program now enrolled and WeatherKit capability enabled, we can fetch real-time weather and weave it into the active walk experience, post-walk summary, and AI prompt context.

Weather appears on the **active walk screen** (not the path/home screen) because GPS is already active there, giving us location for free. No extra permission needed.

## Architecture Overview

Three layers, all additive:

1. **WeatherService** — fetches current conditions via WeatherKit, returns a lightweight snapshot
2. **Visual layer** — atmospheric overlay + weather vignette on the active walk screen
3. **Data layer** — weather persisted with each walk, fed to prompt generator

## 1. WeatherService

**New file:** `Pilgrim/Models/Weather/WeatherService.swift`

Singleton wrapping Apple's `WeatherKit` framework.

```
WeatherService.shared.fetchCurrent(for: CLLocation) async → WeatherSnapshot?
```

**WeatherSnapshot** — lightweight Codable struct:
- `condition`: `WeatherCondition` enum (clear, partlyCloudy, overcast, lightRain, heavyRain, thunderstorm, snow, fog, wind, haze)
- `temperature`: Double (Celsius)
- `humidity`: Double (0–1)
- `windSpeed`: Double (m/s)
- `windDirection`: Double (degrees, 0–360)
- `uvIndex`: Int
- `visibility`: Double (meters)
- `cloudCover`: Double (0–1)
- `precipitationIntensity`: Double (mm/hr)
- `description`: String (human-readable, e.g. "Light rain, 14°C")

**WeatherCondition** enum maps from Apple's `WeatherKit.WeatherCondition`:
- `.clear` ← clear, mostlyClear, hot
- `.partlyCloudy` ← partlyCloudy
- `.overcast` ← cloudy, mostlyCloudy
- `.lightRain` ← drizzle, rain (low intensity)
- `.heavyRain` ← heavyRain, rain (high intensity)
- `.thunderstorm` ← thunderstorms, tropicalStorm, hurricane
- `.snow` ← snow, flurries, sleet, freezingRain, blizzard, heavySnow
- `.fog` ← foggy
- `.wind` ← windy, breezy (or wind speed > 10 m/s regardless of condition)
- `.haze` ← haze, smoky, blowingDust

**Error handling:** Returns nil on any failure (no network, WeatherKit unavailable, location unavailable). Never blocks walk start. Fire-and-forget async call.

**Caching:** Result cached for the session. One fetch per walk, at walk start.

## 2. Data Persistence

**New migration:** PilgrimV7 extending the Walk entity with optional weather fields.

New fields on Workout entity (all optional):
- `_weatherCondition`: String? (raw value of WeatherCondition enum)
- `_weatherTemperature`: Double? (Celsius)
- `_weatherHumidity`: Double?
- `_weatherWindSpeed`: Double?
- `_weatherWindDirection`: Double?
- `_weatherUVIndex`: Int16?
- `_weatherVisibility`: Double?
- `_weatherCloudCover`: Double?

All optional — walks without weather (offline, pre-update, pre-V7) simply have nil. No separate entity needed; weather is a property of the walk, not a standalone object.

**Save flow:**
1. Walk starts → `ActiveWalkViewModel` calls `WeatherService.fetchCurrent(for: location)`
2. Result stored as `@Published var weatherSnapshot: WeatherSnapshot?` on the view model
3. At walk completion, snapshot fields written into `NewWalk` and saved to DB
4. Session guard checkpoint includes weather fields (so crash recovery preserves weather)

**TempWalk extension:** Add weather fields to `TempV4.Workout` for checkpoint serialization. Codable — encoded into existing checkpoint JSON.

## 3. Active Walk Screen — Visual Layer

Weather manifests as two visual layers on the active walk screen (Option C — Layered):

### Atmospheric Overlay (mood layer)

A subtle full-screen overlay behind the walk content. Very quiet — wabi-sabi, not a weather app.

| Condition | Visual Treatment |
|-----------|-----------------|
| Clear | Warm golden tint intensified (+0.01 opacity on time-of-day gradient) |
| Partly cloudy | Gentle drifting cloud shapes, opacity 0.03–0.05, slow lateral movement |
| Overcast | Flat, desaturated tint, reduced contrast (subtle grey veil at 0.02 opacity) |
| Light rain | Subtle falling particle lines (thin, 0.03 opacity, diagonal), cool blue-grey tint |
| Heavy rain | Denser particles, darker tint (+0.02), very slight blur on edges |
| Thunderstorm | Dark overlay (0.03), occasional brief opacity flash (lightning, every 8–15s random) |
| Snow | Gentle falling dots (white, 0.04 opacity), cool blue-white tint |
| Fog | Soft radial gradient overlay (white, 0.04 center → 0.01 edges), dreamy |
| Wind | Diagonal particle streaks (fast, subtle), existing scenery sway amplified if present |
| Haze | Warm golden-brown veil (0.02 opacity), slightly washed out |

**Implementation:** New `WeatherOverlayView` — a SwiftUI view that takes `WeatherCondition?` and renders the appropriate overlay. Uses `Canvas` for particles (rain, snow) to avoid per-particle view overhead. Respects reduce-motion (static tint only, no particles).

**Resource safety:** Particle animations use `TimelineView` at 20fps max. The overlay is removed when the walk ends. No accumulating state.

### Weather Vignette (fact layer)

A compact indicator showing current conditions. Positioned near the walk stats (map area or stats bar).

- Condition SF Symbol icon (sun.max, cloud, cloud.rain, cloud.bolt, cloud.snow, cloud.fog, wind, sun.haze)
- Temperature in user's preferred unit
- Tappable to expand: shows humidity, wind, UV index
- Uses app typography: `statValue` for temperature, `caption` for labels
- Color: `fog` for icon/text, matching the understated aesthetic

**Expand/collapse:** Tap toggles between compact (icon + temp) and expanded (icon + temp + humidity + wind + UV). Uses `.spring(duration: 0.3)` animation.

## 4. Post-Walk Summary

Weather displayed in the walk summary stats section:

- One line: condition icon + "Light rain, 14°C" (or "57°F" for imperial users)
- Positioned alongside distance, duration, pace
- Only shown if weather data exists (nil = hidden, graceful for pre-update walks)
- Uses `Constants.Typography.caption` and `Color.fog`

Temperature unit follows `UserPreferences.distanceMeasurementType` — if imperial (miles), show Fahrenheit; if metric (km), show Celsius.

## 5. Prompt Integration

**New section in PromptGenerator:** `formatWeather(_ snapshot: WeatherSnapshot?) → String?`

Output format:
```
Weather: Light rain, 14°C, humidity 82%, gentle breeze from the west (12 km/h)
Visibility: 5.2 km, cloud cover 75%, UV index 2
```

Wind description uses cardinal directions and qualitative terms:
- < 2 m/s: "calm"
- 2–5 m/s: "gentle breeze"
- 5–10 m/s: "moderate wind"
- 10–15 m/s: "strong wind"
- > 15 m/s: "very strong wind"

Direction converted to cardinal: "from the north", "from the southwest", etc.

Added to the existing metadata section in `buildPrompt()`, after time-of-day and lunar phase. Returns nil if no weather data — prompt continues without it.

## 6. Offline / Error Handling

- WeatherKit fetch fails → `weatherSnapshot` stays nil
- No weather → no overlay, no vignette, no prompt section, no summary line
- Walk continues normally — weather is enhancement, never requirement
- No error shown to user
- Session guard checkpoint handles nil weather fields gracefully

## Files to Create/Modify

| File | Action |
|------|--------|
| `Pilgrim/Models/Weather/WeatherService.swift` | **Create** — WeatherKit wrapper + WeatherSnapshot + WeatherCondition |
| `Pilgrim/Models/Weather/WeatherOverlayView.swift` | **Create** — atmospheric overlay for active walk |
| `Pilgrim/Models/Weather/WeatherVignetteView.swift` | **Create** — compact weather indicator |
| `Pilgrim/Models/Data/DataModels/Versions/PilgrimV7.swift` | **Create** — DB migration adding weather fields |
| `Pilgrim/Models/Data/DataModels/Versions/PilgrimV6.swift` | **Modify** — update migration chain reference |
| `Pilgrim/Models/Data/NewWalk.swift` | **Modify** — add weather fields |
| `Pilgrim/Models/Data/Temp/Versions/TempWaypoint.swift` (TempV4) | **Modify** — add weather fields to checkpoint serialization |
| `Pilgrim/Scenes/ActiveWalk/ActiveWalkViewModel.swift` | **Modify** — fetch weather on walk start, expose to views |
| `Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift` | **Modify** — add overlay + vignette |
| `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift` | **Modify** — add weather line to stats |
| `Pilgrim/Models/PromptGenerator.swift` | **Modify** — add formatWeather() section |
| `Pilgrim/Models/Walk/WalkSessionGuard.swift` | **Modify** — include weather in checkpoint/recovery |
| `Pilgrim.xcodeproj/project.pbxproj` | **Modify** — add new files |

## Reused Components

- `Constants.Typography.*` — all text styling
- `Constants.UI.Padding.*` — spacing
- `Color.fog/stone/ink/parchment` — weather UI colors
- `SeasonalColorEngine` — overlay tinting could use seasonal modulation
- `UserPreferences.distanceMeasurementType` — imperial/metric for temperature unit
- Generation counter pattern — for overlay animations

## Verification

1. **Build**: `xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build`
2. **Simulator**: WeatherKit returns data in simulator with a developer account (may need physical device for real data)
3. **Active walk**: Start a walk — atmospheric overlay matches current conditions, vignette shows temp + icon
4. **Vignette tap**: Expand/collapse shows additional weather details
5. **Walk summary**: After ending walk, weather line appears in summary stats
6. **Prompts**: Generate prompts after a walk — weather section present in prompt text
7. **Offline**: Disable network → start walk → no weather visuals, no crash, walk works normally
8. **Reduce motion**: Overlay shows static tint only (no particles), vignette still functional
9. **Session guard**: Kill app during walk → relaunch → recovered walk includes weather data
10. **Imperial/Metric**: Switch units → temperature displays in correct unit (°F/°C)
