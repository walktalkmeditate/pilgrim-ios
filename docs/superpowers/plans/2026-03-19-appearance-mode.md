# Appearance Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 3-way appearance mode toggle (System / Light / Dark) so users can override iOS system appearance within Pilgrim.

**Architecture:** New `AppearanceMode` enum + `UserPreferences` key for storage. `AppearanceManager` (ObservableObject) subscribes to the preference and publishes `resolvedScheme: ColorScheme?`. Applied via `.preferredColorScheme()` at the app root in `PilgrimApp.swift`. Segmented picker in `GeneralSettingsView`.

**Tech Stack:** SwiftUI, Combine, UserDefaults (via existing `UserPreference` wrapper)

**Spec:** `docs/superpowers/specs/2026-03-19-appearance-mode-design.md`

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `Pilgrim/Models/AppearanceMode.swift` | Enum with 3 cases + raw string mapping + `resolvedScheme` computed property |
| Create | `Pilgrim/Models/AppearanceManager.swift` | ObservableObject publishing resolved `ColorScheme?`, crossfade animation |
| Modify | `Pilgrim/Models/Preferences/UserPreferences.swift` | Add `appearanceMode` preference key |
| Modify | `Pilgrim/PilgrimApp.swift` | Own `AppearanceManager`, apply `.preferredColorScheme()` |
| Modify | `Pilgrim/Scenes/Settings/GeneralSettingsView.swift` | Add Appearance section with segmented picker |
| ~~Modify~~ | ~~`Pilgrim/Support Files/Base.lproj/Localizable.strings`~~ | ~~Add localization strings~~ (not needed — file uses hardcoded strings) |
| Create | `UnitTests/AppearanceModeTests.swift` | Tests for enum mapping + manager behavior |

---

### Task 1: AppearanceMode Enum

**Files:**
- Create: `Pilgrim/Models/AppearanceMode.swift`
- Create: `UnitTests/AppearanceModeTests.swift`

- [ ] **Step 1: Write failing tests for AppearanceMode enum**

In `UnitTests/AppearanceModeTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import Pilgrim

final class AppearanceModeTests: XCTestCase {

    func testInit_system_fromRawString() {
        XCTAssertEqual(AppearanceMode(rawValue: "system"), .system)
    }

    func testInit_light_fromRawString() {
        XCTAssertEqual(AppearanceMode(rawValue: "light"), .light)
    }

    func testInit_dark_fromRawString() {
        XCTAssertEqual(AppearanceMode(rawValue: "dark"), .dark)
    }

    func testInit_invalidString_returnsNil() {
        XCTAssertNil(AppearanceMode(rawValue: "invalid"))
    }

    func testResolvedScheme_system_returnsNil() {
        XCTAssertNil(AppearanceMode.system.resolvedScheme)
    }

    func testResolvedScheme_light_returnsLight() {
        XCTAssertEqual(AppearanceMode.light.resolvedScheme, .light)
    }

    func testResolvedScheme_dark_returnsDark() {
        XCTAssertEqual(AppearanceMode.dark.resolvedScheme, .dark)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/AppearanceModeTests 2>&1 | tail -20`

Expected: Build failure — `AppearanceMode` not found.

- [ ] **Step 3: Implement AppearanceMode enum**

In `Pilgrim/Models/AppearanceMode.swift`:

```swift
import SwiftUI

enum AppearanceMode: String {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var resolvedScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/AppearanceModeTests 2>&1 | tail -20`

Expected: All 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/AppearanceMode.swift UnitTests/AppearanceModeTests.swift
git commit -m "feat: add AppearanceMode enum with resolved scheme mapping"
```

---

### Task 2: UserPreferences Key + AppearanceManager

**Files:**
- Modify: `Pilgrim/Models/Preferences/UserPreferences.swift:55` (add after `zodiacSystem`)
- Create: `Pilgrim/Models/AppearanceManager.swift`
- Modify: `UnitTests/AppearanceModeTests.swift` (add manager tests)

- [ ] **Step 1: Write failing tests for AppearanceManager**

Append to `UnitTests/AppearanceModeTests.swift`:

```swift
final class AppearanceManagerTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        UserPreferences.appearanceMode.value = "system"
    }

    func testPreferenceDefault_isSystem() {
        UserPreferences.appearanceMode.delete()
        XCTAssertEqual(UserPreferences.appearanceMode.value, "system")
    }

    func testResolvedScheme_defaultIsNil() {
        UserPreferences.appearanceMode.value = "system"
        let manager = AppearanceManager()
        XCTAssertNil(manager.resolvedScheme)
    }

    func testResolvedScheme_light_returnsLight() {
        UserPreferences.appearanceMode.value = "light"
        let manager = AppearanceManager()
        XCTAssertEqual(manager.resolvedScheme, .light)
    }

    func testResolvedScheme_dark_returnsDark() {
        UserPreferences.appearanceMode.value = "dark"
        let manager = AppearanceManager()
        XCTAssertEqual(manager.resolvedScheme, .dark)
    }

    func testResolvedScheme_invalidValue_fallsBackToNil() {
        UserPreferences.appearanceMode.value = "bogus"
        let manager = AppearanceManager()
        XCTAssertNil(manager.resolvedScheme)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/AppearanceModeTests 2>&1 | tail -20`

Expected: Build failure — `UserPreferences.appearanceMode` and `AppearanceManager` not found.

- [ ] **Step 3: Add preference key to UserPreferences**

In `Pilgrim/Models/Preferences/UserPreferences.swift`, add after the `zodiacSystem` line (line 55):

```swift
    static let appearanceMode = UserPreference.Required<String>(key: "appearanceMode", defaultValue: "system")
```

- [ ] **Step 4: Implement AppearanceManager**

In `Pilgrim/Models/AppearanceManager.swift`:

```swift
import SwiftUI
import Combine

final class AppearanceManager: ObservableObject {

    @Published var resolvedScheme: ColorScheme?

    private var cancellables = Set<AnyCancellable>()

    init() {
        resolvedScheme = Self.resolve(UserPreferences.appearanceMode.value)

        UserPreferences.appearanceMode.publisher
            .sink { [weak self] newValue in
                guard let self else { return }
                let newScheme = Self.resolve(newValue)
                guard newScheme != self.resolvedScheme else { return }
                self.animateTransition()
                self.resolvedScheme = newScheme
            }
            .store(in: &cancellables)
    }

    private static func resolve(_ raw: String) -> ColorScheme? {
        (AppearanceMode(rawValue: raw) ?? .system).resolvedScheme
    }

    private func animateTransition() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else { return }
        UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve, animations: {}, completion: nil)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/AppearanceModeTests 2>&1 | tail -20`

Expected: All 12 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Pilgrim/Models/Preferences/UserPreferences.swift Pilgrim/Models/AppearanceManager.swift UnitTests/AppearanceModeTests.swift
git commit -m "feat: add AppearanceManager with crossfade transition"
```

---

### Task 3: Root Integration in PilgrimApp

**Files:**
- Modify: `Pilgrim/PilgrimApp.swift`

- [ ] **Step 1: Add AppearanceManager to PilgrimApp**

In `PilgrimApp.swift`, add a `@StateObject` property and apply `.preferredColorScheme()` to the root view. Preserve the existing license header and structure.

Add the property after the `@UIApplicationDelegateAdaptor` line:

```swift
    @StateObject private var appearanceManager = AppearanceManager()
```

Add the modifier to `RootCoordinatorView`:

```swift
            RootCoordinatorView(viewModel: RootCoordinatorViewModel())
                .preferredColorScheme(appearanceManager.resolvedScheme)
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run full test suite to verify no regressions**

Run: `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20`

Expected: All tests PASS.

- [ ] **Step 4: Commit**

```bash
git add Pilgrim/PilgrimApp.swift
git commit -m "feat: wire AppearanceManager into app root with preferredColorScheme"
```

---

### Task 4: Settings UI

**Files:**
- Modify: `Pilgrim/Scenes/Settings/GeneralSettingsView.swift`

- [ ] **Step 1: Add appearance section to GeneralSettingsView**

In `GeneralSettingsView.swift`, add a new `@State` property alongside the existing ones (after line 9):

```swift
    @State private var appearanceMode = UserPreferences.appearanceMode.value
```

Add a new computed property for the appearance section (follow the pattern of `walkSection`, `celestialSection`, etc.). Uses hardcoded strings to match existing convention in this file:

```swift
    private var appearanceSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Appearance")
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)
                }
                Spacer()
                Picker("", selection: $appearanceMode) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .onChange(of: appearanceMode) { _, newValue in
                    UserPreferences.appearanceMode.value = newValue
                }
            }
        } header: {
            Text("Appearance")
                .font(Constants.Typography.caption)
        }
    }
```

Add `appearanceSection` as the **first section** in the `List` body, before `walkSection`.

- [ ] **Step 3: Build to verify compilation**

Run: `xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run full test suite**

Run: `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20`

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Scenes/Settings/GeneralSettingsView.swift
git commit -m "feat: add appearance mode segmented picker to General settings"
```

---

### Task 5: Verify Mapbox + SeasonalColorEngine Propagation

**Files:**
- Possibly modify: `Pilgrim/Scenes/Map/PilgrimMapView.swift` (only if trait propagation fails)

- [ ] **Step 1: Manual verification**

Build and run in simulator. In Settings > General:
1. Set appearance to "Light" — verify the whole app (including map) uses light mode regardless of simulator system setting
2. Set appearance to "Dark" — verify the whole app (including map) uses dark mode
3. Set appearance to "System" — verify it follows the simulator's system setting
4. Toggle system appearance in simulator (Features > Toggle Appearance) — verify "System" mode responds, "Light"/"Dark" modes don't
5. Verify crossfade animation plays when switching modes

- [ ] **Step 2: Verify SeasonalColorEngine resolves correctly**

While in forced Dark mode, check that colors still look correct (seasonal tinting applied on top of dark variants). If `SeasonalColorEngine` resolves against system appearance instead of the override, the colors will look wrong in override mode.

- [ ] **Step 3: If Mapbox doesn't pick up the override**

Add `.environment(\.colorScheme, ...)` or `overrideUserInterfaceStyle` on the map's hosting view. This is a contingency — likely not needed.

- [ ] **Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: ensure appearance override propagates to map and seasonal colors"
```

Only commit if changes were needed. If everything works, skip this step.
