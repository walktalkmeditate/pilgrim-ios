# WeatherKit Integration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fetch real-time weather at walk start via Apple WeatherKit, display it as atmospheric overlay + vignette on the active walk screen, persist it with the walk, and feed it into AI prompt context.

**Architecture:** WeatherService singleton fetches current conditions → WeatherSnapshot stored on ActiveWalkViewModel → visual layer reads snapshot for overlay/vignette → snapshot persisted to existing DB weather fields (dormant since V1) via WalkInterface/TempWalk/DataManager plumbing → PromptGenerator reads weather for AI context.

**Tech Stack:** WeatherKit (system framework), SwiftUI Canvas (particles), CoreStore (existing ORM), CoreLocation (existing)

**Spec:** `docs/superpowers/specs/2026-03-18-weatherkit-integration-design.md`

**Key discovery:** The DB already has weather fields on the Workout entity since PilgrimV1 (`_weatherCondition`, `_weatherTemperature`, `_weatherHumidity`, `_weatherWindSpeed`) — inherited from OutRun but never populated. No migration needed. We just need to wire them up.

---

### Task 1: WeatherService + WeatherSnapshot + WeatherCondition

**Files:**
- Create: `Pilgrim/Models/Weather/WeatherService.swift`

- [ ] **Step 1: Create the Weather directory**

```bash
mkdir -p Pilgrim/Models/Weather
```

- [ ] **Step 2: Create WeatherService.swift with WeatherCondition enum, WeatherSnapshot struct, and service**

```swift
import Foundation
import WeatherKit
import CoreLocation

enum WeatherCondition: String, Codable {
    case clear, partlyCloudy, overcast
    case lightRain, heavyRain, thunderstorm
    case snow, fog, wind, haze

    var icon: String {
        switch self {
        case .clear: return "sun.max.fill"
        case .partlyCloudy: return "cloud.sun.fill"
        case .overcast: return "cloud.fill"
        case .lightRain: return "cloud.drizzle.fill"
        case .heavyRain: return "cloud.heavyrain.fill"
        case .thunderstorm: return "cloud.bolt.fill"
        case .snow: return "cloud.snow.fill"
        case .fog: return "cloud.fog.fill"
        case .wind: return "wind"
        case .haze: return "sun.haze.fill"
        }
    }

    var label: String {
        switch self {
        case .clear: return "Clear"
        case .partlyCloudy: return "Partly cloudy"
        case .overcast: return "Overcast"
        case .lightRain: return "Light rain"
        case .heavyRain: return "Heavy rain"
        case .thunderstorm: return "Thunderstorm"
        case .snow: return "Snow"
        case .fog: return "Foggy"
        case .wind: return "Windy"
        case .haze: return "Hazy"
        }
    }
}

struct WeatherSnapshot: Codable {
    let condition: WeatherCondition
    let temperature: Double
    let humidity: Double
    let windSpeed: Double

    var description: String {
        let tempStr = String(format: "%.0f", temperature)
        return "\(condition.label), \(tempStr)°C"
    }

    func formattedTemperature(imperial: Bool) -> String {
        if imperial {
            return String(format: "%.0f°F", temperature * 9 / 5 + 32)
        }
        return String(format: "%.0f°C", temperature)
    }
}

final class WeatherService {

    static let shared = WeatherService()
    private let service = WeatherKit.WeatherService.shared
    private init() {}

    func fetchCurrent(for location: CLLocation) async -> WeatherSnapshot? {
        do {
            let weather = try await service.weather(for: location, including: .current)
            let condition = mapCondition(weather.condition, windSpeed: weather.wind.speed.converted(to: .metersPerSecond).value)
            return WeatherSnapshot(
                condition: condition,
                temperature: weather.temperature.converted(to: .celsius).value,
                humidity: weather.humidity,
                windSpeed: weather.wind.speed.converted(to: .metersPerSecond).value
            )
        } catch {
            print("[WeatherService] Failed to fetch weather: \(error.localizedDescription)")
            return nil
        }
    }

    private func mapCondition(_ condition: WeatherKit.WeatherCondition, windSpeed: Double) -> WeatherCondition {
        if windSpeed > 10 { return .wind }

        switch condition {
        case .clear, .mostlyClear, .hot:
            return .clear
        case .partlyCloudy:
            return .partlyCloudy
        case .cloudy, .mostlyCloudy:
            return .overcast
        case .drizzle:
            return .lightRain
        case .rain:
            return windSpeed > 5 ? .heavyRain : .lightRain
        case .heavyRain:
            return .heavyRain
        case .thunderstorms, .tropicalStorm, .hurricane, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms:
            return .thunderstorm
        case .snow, .flurries, .sleet, .freezingRain, .blizzard, .heavySnow, .freezingDrizzle, .blowingSnow, .wintryMix:
            return .snow
        case .foggy:
            return .fog
        case .windy, .breezy:
            return .wind
        case .haze, .smoky, .blowingDust:
            return .haze
        @unknown default:
            return .clear
        }
    }
}
```

- [ ] **Step 3: Add file to Xcode project and build**

Add `WeatherService.swift` to the Pilgrim target in `project.pbxproj`.

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```
git add Pilgrim/Models/Weather/WeatherService.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat: add WeatherService with WeatherKit integration"
```

---

### Task 2: Data plumbing — WalkInterface, TempWalk, DataManager, NewWalk, SessionGuard

**Files:**
- Modify: `Pilgrim/Protocols/DataInterfaces/WalkInterface.swift`
- Modify: `Pilgrim/Models/Data/Temp/Versions/TempV4.swift`
- Modify: `Pilgrim/Models/Data/DataManager.swift`
- Modify: `Pilgrim/Models/Data/NewWalk.swift`
- Modify: `Pilgrim/Models/Walk/WalkSessionGuard.swift`

- [ ] **Step 1: Add weather properties to WalkInterface protocol**

In `WalkInterface.swift`, add after the existing properties (near `var waypoints`):

```swift
var weatherCondition: String? { get }
var weatherTemperature: Double? { get }
var weatherHumidity: Double? { get }
var weatherWindSpeed: Double? { get }
```

And add default `throwOnAccess()` implementations in the default extension at the bottom of the file.

- [ ] **Step 2: Add weather fields to TempV4.Workout**

In `Pilgrim/Models/Data/Temp/Versions/TempV4.swift`, add to the `Workout` class:

Properties (after `favicon`):
```swift
public var weatherCondition: String?
public var weatherTemperature: Double?
public var weatherHumidity: Double?
public var weatherWindSpeed: Double?
```

Add to the `init` parameter list:
```swift
weatherCondition: String? = nil, weatherTemperature: Double? = nil, weatherHumidity: Double? = nil, weatherWindSpeed: Double? = nil
```

Add to init body:
```swift
self.weatherCondition = weatherCondition
self.weatherTemperature = weatherTemperature
self.weatherHumidity = weatherHumidity
self.weatherWindSpeed = weatherWindSpeed
```

Add to `CodingKeys`:
```swift
case weatherCondition, weatherTemperature, weatherHumidity, weatherWindSpeed
```

Add to `init(from decoder:)`:
```swift
weatherCondition = try container.decodeIfPresent(String.self, forKey: .weatherCondition)
weatherTemperature = try container.decodeIfPresent(Double.self, forKey: .weatherTemperature)
weatherHumidity = try container.decodeIfPresent(Double.self, forKey: .weatherHumidity)
weatherWindSpeed = try container.decodeIfPresent(Double.self, forKey: .weatherWindSpeed)
```

- [ ] **Step 3: Write weather fields in DataManager.saveWalk**

In `DataManager.swift`, inside the `for object in validatedObjects` loop (after line 212 `walk._favicon .= object.favicon`), add:

```swift
walk._weatherCondition .= object.weatherCondition
walk._weatherTemperature .= object.weatherTemperature
walk._weatherHumidity .= object.weatherHumidity
walk._weatherWindSpeed .= object.weatherWindSpeed
```

- [ ] **Step 4: Add weather params to NewWalk init**

In `NewWalk.swift`, add weather parameters to the `init`:

```swift
weatherCondition: String? = nil, weatherTemperature: Double? = nil, weatherHumidity: Double? = nil, weatherWindSpeed: Double? = nil
```

Pass them through to `super.init(...)` by setting them after the super.init call:
```swift
self.weatherCondition = weatherCondition
self.weatherTemperature = weatherTemperature
self.weatherHumidity = weatherHumidity
self.weatherWindSpeed = weatherWindSpeed
```

- [ ] **Step 5: Include weather in session guard recovery**

In `WalkSessionGuard.swift`, in the recovery `NewWalk(...)` constructor call, add:

```swift
weatherCondition: walk.weatherCondition,
weatherTemperature: walk.weatherTemperature,
weatherHumidity: walk.weatherHumidity,
weatherWindSpeed: walk.weatherWindSpeed
```

- [ ] **Step 6: Build and commit**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build`

```
git add -A
git commit -m "feat: wire weather fields through data layer

Add weather properties to WalkInterface, TempV4.Workout, NewWalk,
DataManager save path, and session guard recovery. DB fields existed
since V1 but were never populated."
```

---

### Task 3: ActiveWalkViewModel — fetch weather at walk start

**Files:**
- Modify: `Pilgrim/Scenes/ActiveWalk/ActiveWalkViewModel.swift`

- [ ] **Step 1: Add weather state and fetch on init**

Add published property:
```swift
@Published var weatherSnapshot: WeatherSnapshot?
```

Add a method to fetch weather:
```swift
func fetchWeather() {
    guard let location = locationManagement.locationManager.location else { return }
    Task {
        let snapshot = await WeatherService.shared.fetchCurrent(for: location)
        await MainActor.run {
            self.weatherSnapshot = snapshot
        }
    }
}
```

Call `fetchWeather()` at the end of the view model's `init` (or from a `.task` in the view after location is available).

- [ ] **Step 2: Pass weather to snapshot on walk completion**

In the `WalkBuilder.createSnapshot()` flow or wherever `NewWalk` is constructed, pass the weather fields:

```swift
weatherCondition: weatherSnapshot?.condition.rawValue,
weatherTemperature: weatherSnapshot?.temperature,
weatherHumidity: weatherSnapshot?.humidity,
weatherWindSpeed: weatherSnapshot?.windSpeed
```

- [ ] **Step 3: Build and commit**

```
git add Pilgrim/Scenes/ActiveWalk/ActiveWalkViewModel.swift
git commit -m "feat: fetch weather at walk start via WeatherService"
```

---

### Task 4: Weather visual layer — overlay + vignette

**Files:**
- Create: `Pilgrim/Models/Weather/WeatherOverlayView.swift`
- Create: `Pilgrim/Models/Weather/WeatherVignetteView.swift`
- Modify: `Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift`

- [ ] **Step 1: Create WeatherOverlayView**

```swift
import SwiftUI

struct WeatherOverlayView: View {

    let condition: WeatherCondition?

    var body: some View {
        ZStack {
            switch condition {
            case .clear:
                Color.orange.opacity(0.01)
            case .partlyCloudy:
                cloudOverlay(opacity: 0.03)
            case .overcast:
                Color.gray.opacity(0.02)
            case .lightRain:
                Color(.systemBlue).opacity(0.01)
                    .overlay { rainParticles(density: 20, speed: 1.0) }
            case .heavyRain:
                Color(.systemBlue).opacity(0.02)
                    .overlay { rainParticles(density: 40, speed: 1.5) }
            case .thunderstorm:
                Color.ink.opacity(0.03)
                    .overlay { lightningFlash }
            case .snow:
                Color(.systemCyan).opacity(0.01)
                    .overlay { snowParticles }
            case .fog:
                RadialGradient(
                    colors: [Color.white.opacity(0.04), Color.white.opacity(0.01)],
                    center: .center, startRadius: 50, endRadius: 300
                )
            case .wind:
                windStreaks
            case .haze:
                Color.brown.opacity(0.02)
            case nil:
                Color.clear
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // Rain: diagonal falling lines using Canvas
    private func rainParticles(density: Int, speed: Double) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate * speed
                for i in 0..<density {
                    let seed = Double(i) * 137.508
                    let x = (seed.truncatingRemainder(dividingBy: size.width))
                    let rawY = (time * 80 + seed * 3).truncatingRemainder(dividingBy: size.height + 20) - 10
                    let y = rawY < 0 ? rawY + size.height + 20 : rawY
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x - 2, y: y + 12))
                    context.stroke(path, with: .color(.ink.opacity(0.03)), lineWidth: 0.5)
                }
            }
        }
    }

    // Snow: gentle falling dots
    private var snowParticles: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<25 {
                    let seed = Double(i) * 97.31
                    let x = (seed.truncatingRemainder(dividingBy: size.width)) + sin(time * 0.5 + seed) * 10
                    let y = (time * 20 + seed * 5).truncatingRemainder(dividingBy: size.height + 10)
                    let r = 1.0 + (seed.truncatingRemainder(dividingBy: 2))
                    let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                    context.fill(Circle().path(in: rect), with: .color(.white.opacity(0.04)))
                }
            }
        }
    }

    // Cloud: drifting soft shapes
    private func cloudOverlay(opacity: Double) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<3 {
                    let seed = Double(i) * 200
                    let x = (time * 3 + seed).truncatingRemainder(dividingBy: size.width + 200) - 100
                    let y = 50 + seed.truncatingRemainder(dividingBy: size.height * 0.4)
                    let w = 120 + seed.truncatingRemainder(dividingBy: 80)
                    let rect = CGRect(x: x, y: y, width: w, height: 40)
                    context.fill(Ellipse().path(in: rect), with: .color(.fog.opacity(opacity)))
                }
            }
        }
    }

    // Lightning: brief flash every 8-15s
    private var lightningFlash: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let cycle = time.truncatingRemainder(dividingBy: 12)
            let flash = cycle > 11.8 && cycle < 11.9
            Color.white.opacity(flash ? 0.06 : 0)
        }
    }

    // Wind: fast diagonal streaks
    private var windStreaks: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<12 {
                    let seed = Double(i) * 73.7
                    let x = (time * 120 + seed * 20).truncatingRemainder(dividingBy: size.width + 100) - 50
                    let y = seed.truncatingRemainder(dividingBy: size.height)
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x + 30, y: y - 2))
                    context.stroke(path, with: .color(.fog.opacity(0.03)), lineWidth: 0.5)
                }
            }
        }
    }
}
```

For reduce motion: wrap `TimelineView` content in a check — if reduce motion, show only the static color tint.

- [ ] **Step 2: Create WeatherVignetteView**

```swift
import SwiftUI

struct WeatherVignetteView: View {

    let snapshot: WeatherSnapshot?
    let imperial: Bool
    @State private var expanded = false

    var body: some View {
        if let snapshot {
            Button {
                withAnimation(.spring(duration: 0.3)) { expanded.toggle() }
            } label: {
                HStack(spacing: Constants.UI.Padding.xs) {
                    Image(systemName: snapshot.condition.icon)
                        .font(.system(size: 12))
                    Text(snapshot.formattedTemperature(imperial: imperial))
                        .font(Constants.Typography.caption)
                    if expanded {
                        Text("·")
                            .foregroundColor(.fog.opacity(0.3))
                        Text("\(Int(snapshot.humidity * 100))%")
                            .font(Constants.Typography.caption)
                        Text("·")
                            .foregroundColor(.fog.opacity(0.3))
                        Text(formatWind(snapshot.windSpeed))
                            .font(Constants.Typography.caption)
                    }
                }
                .foregroundColor(.fog)
                .padding(.horizontal, Constants.UI.Padding.small)
                .padding(.vertical, Constants.UI.Padding.xs)
                .background(
                    Capsule().fill(.ultraThinMaterial)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func formatWind(_ speed: Double) -> String {
        switch speed {
        case ..<2: return "calm"
        case 2..<5: return "gentle"
        case 5..<10: return "moderate"
        case 10..<15: return "strong"
        default: return "very strong"
        }
    }
}
```

- [ ] **Step 3: Add overlay + vignette to ActiveWalkView**

In `ActiveWalkView.swift`, add the overlay behind the content (inside the main ZStack) and the vignette near the map/stats area. The overlay goes at the back of the ZStack, the vignette near the audio indicators.

- [ ] **Step 4: Add new files to Xcode project, build and commit**

```
git add -A
git commit -m "feat: weather overlay and vignette on active walk screen

Atmospheric overlay renders rain/snow/fog/wind particles via Canvas.
Compact vignette shows condition icon + temperature, tappable to
expand with humidity and wind."
```

---

### Task 5: Prompt integration

**Files:**
- Modify: `Pilgrim/Models/PromptGenerator.swift`

- [ ] **Step 1: Add formatWeather method**

Add a new static method to `PromptGenerator`:

```swift
private static func formatWeather(_ walk: WalkInterface) -> String? {
    guard let conditionStr = walk.weatherCondition,
          let condition = WeatherCondition(rawValue: conditionStr),
          let temp = walk.weatherTemperature else { return nil }

    var parts = ["\(condition.label)", String(format: "%.0f°C", temp)]

    if let humidity = walk.weatherHumidity {
        parts.append("humidity \(Int(humidity * 100))%")
    }

    if let wind = walk.weatherWindSpeed {
        let desc: String
        switch wind {
        case ..<2: desc = "calm"
        case 2..<5: desc = "gentle breeze"
        case 5..<10: desc = "moderate wind"
        case 10..<15: desc = "strong wind"
        default: desc = "very strong wind"
        }
        parts.append(desc)
    }

    return "Weather: \(parts.joined(separator: ", "))"
}
```

- [ ] **Step 2: Add weather to buildPrompt**

In `buildPrompt()` or `formatMetadata()`, add after the lunar phase line:

```swift
if let weather = formatWeather(walk) {
    sections.append(weather)
}
```

- [ ] **Step 3: Build and commit**

```
git add Pilgrim/Models/PromptGenerator.swift
git commit -m "feat: add weather context to AI prompt generation"
```

---

### Task 6: Walk summary weather display

**Files:**
- Modify: `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift`

- [ ] **Step 1: Add weather line to summary stats**

Find the stats section in WalkSummaryView and add a weather line (condition icon + description) when weather data exists:

```swift
if let condStr = walk.weatherCondition,
   let cond = WeatherCondition(rawValue: condStr),
   let temp = walk.weatherTemperature {
    let imperial = UserPreferences.distanceMeasurementType.safeValue == .miles
    HStack(spacing: Constants.UI.Padding.xs) {
        Image(systemName: cond.icon)
            .font(.system(size: 12))
        Text(WeatherSnapshot(condition: cond, temperature: temp, humidity: walk.weatherHumidity ?? 0, windSpeed: walk.weatherWindSpeed ?? 0).formattedTemperature(imperial: imperial))
            .font(Constants.Typography.caption)
        Text(cond.label)
            .font(Constants.Typography.caption)
    }
    .foregroundColor(.fog)
}
```

- [ ] **Step 2: Build and commit**

```
git add Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift
git commit -m "feat: display weather in walk summary stats"
```

---

### Task 7: Verification

- [ ] **Step 1: Build full project**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build`

- [ ] **Step 2: Test on physical device** (requires WeatherKit provisioning)

1. Start a walk → weather overlay should appear, vignette shows temp + icon
2. Tap vignette → expands to show humidity + wind
3. End walk → summary shows weather line
4. Generate prompts → weather section present in prompt text

- [ ] **Step 3: Test offline**

1. Enable airplane mode → start walk → no weather visuals, no crash
2. Walk completes normally, summary has no weather line

- [ ] **Step 4: Test reduce motion**

1. Enable Accessibility → Reduce Motion
2. Start walk → overlay shows static tint only (no particles)
3. Vignette still functional

- [ ] **Step 5: Test session guard**

1. Start walk with weather → force-quit app → relaunch
2. Recovered walk should include weather data
