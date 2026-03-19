# Auto-Detect Units Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-detect metric/imperial from locale at first launch and update the units label to include temperature.

**Architecture:** Extract the existing `applyUnitSystem(metric:)` logic to a shared static method, call it during setup with `Locale.current.usesMetricSystem`, and update the label strings.

**Tech Stack:** SwiftUI, Foundation (Locale)

**Spec:** `docs/superpowers/specs/2026-03-19-auto-detect-units-design.md`

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| Modify | `Pilgrim/Models/Preferences/UserPreferences.swift` | Add static `applyUnitSystem(metric:)` method |
| Modify | `Pilgrim/Scenes/Settings/GeneralSettingsView.swift` | Call shared method instead of private one, update label strings |
| Modify | `Pilgrim/Scenes/Setup/SetupCoordinatorView.swift:34` | Call unit detection before setting `isSetUp` |
| Create | `UnitTests/UnitSystemTests.swift` | Tests for extracted method |

---

### Task 1: Extract `applyUnitSystem` and Update Label

**Files:**
- Create: `UnitTests/UnitSystemTests.swift`
- Modify: `Pilgrim/Models/Preferences/UserPreferences.swift`
- Modify: `Pilgrim/Scenes/Settings/GeneralSettingsView.swift`

- [ ] **Step 1: Write failing tests for the shared method**

**Note:** The new test file must be registered in `Pilgrim.xcodeproj/project.pbxproj` (PBXFileReference, PBXBuildFile, group membership, test target Sources build phase) for Xcode to compile it. Follow the pattern used for `AppearanceModeTests.swift`.

In `UnitTests/UnitSystemTests.swift`:

```swift
import XCTest
@testable import Pilgrim

final class UnitSystemTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        UserPreferences.distanceMeasurementType.delete()
        UserPreferences.altitudeMeasurementType.delete()
        UserPreferences.speedMeasurementType.delete()
        UserPreferences.weightMeasurementType.delete()
        UserPreferences.energyMeasurementType.delete()
    }

    func testApplyUnitSystem_metric_setsKilometers() {
        UserPreferences.applyUnitSystem(metric: true)
        XCTAssertEqual(UserPreferences.distanceMeasurementType.value, .kilometers)
    }

    func testApplyUnitSystem_metric_setsMeters() {
        UserPreferences.applyUnitSystem(metric: true)
        XCTAssertEqual(UserPreferences.altitudeMeasurementType.value, .meters)
    }

    func testApplyUnitSystem_metric_setsKilojoules() {
        UserPreferences.applyUnitSystem(metric: true)
        XCTAssertEqual(UserPreferences.energyMeasurementType.value, .kilojoules)
    }

    func testApplyUnitSystem_imperial_setsMiles() {
        UserPreferences.applyUnitSystem(metric: false)
        XCTAssertEqual(UserPreferences.distanceMeasurementType.value, .miles)
    }

    func testApplyUnitSystem_imperial_setsFeet() {
        UserPreferences.applyUnitSystem(metric: false)
        XCTAssertEqual(UserPreferences.altitudeMeasurementType.value, .feet)
    }

    func testApplyUnitSystem_metric_setsMinutesPerKilometer() {
        UserPreferences.applyUnitSystem(metric: true)
        XCTAssertEqual(UserPreferences.speedMeasurementType.value, .minutesPerLengthUnit(from: .kilometers))
    }

    func testApplyUnitSystem_metric_setsKilograms() {
        UserPreferences.applyUnitSystem(metric: true)
        XCTAssertEqual(UserPreferences.weightMeasurementType.value, .kilograms)
    }

    func testApplyUnitSystem_imperial_setsKilocalories() {
        UserPreferences.applyUnitSystem(metric: false)
        XCTAssertEqual(UserPreferences.energyMeasurementType.value, .kilocalories)
    }

    func testApplyUnitSystem_imperial_setsMinutesPerMile() {
        UserPreferences.applyUnitSystem(metric: false)
        XCTAssertEqual(UserPreferences.speedMeasurementType.value, .minutesPerLengthUnit(from: .miles))
    }

    func testApplyUnitSystem_imperial_setsPounds() {
        UserPreferences.applyUnitSystem(metric: false)
        XCTAssertEqual(UserPreferences.weightMeasurementType.value, .pounds)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/UnitSystemTests 2>&1 | tail -20`

Expected: Build failure — `UserPreferences.applyUnitSystem` not found.

- [ ] **Step 3: Add static method to UserPreferences**

In `Pilgrim/Models/Preferences/UserPreferences.swift`, add after the `reset()` function (after line 70):

```swift
    static func applyUnitSystem(metric: Bool) {
        if metric {
            distanceMeasurementType.value = .kilometers
            altitudeMeasurementType.value = .meters
            speedMeasurementType.value = .minutesPerLengthUnit(from: .kilometers)
            weightMeasurementType.value = .kilograms
            energyMeasurementType.value = .kilojoules
        } else {
            distanceMeasurementType.value = .miles
            altitudeMeasurementType.value = .feet
            speedMeasurementType.value = .minutesPerLengthUnit(from: .miles)
            weightMeasurementType.value = .pounds
            energyMeasurementType.value = .kilocalories
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/UnitSystemTests 2>&1 | tail -20`

Expected: All 10 tests PASS.

- [ ] **Step 5: Update GeneralSettingsView to use shared method**

In `Pilgrim/Scenes/Settings/GeneralSettingsView.swift`, replace the private `applyUnitSystem` method (lines 243-257) with a call to the shared one:

```swift
    private func applyUnitSystem(metric: Bool) {
        UserPreferences.applyUnitSystem(metric: metric)
    }
```

- [ ] **Step 6: Update units label to include temperature**

In `GeneralSettingsView.swift`, change the label text (line 150) from:

```swift
                Text(isMetric ? "km · min/km · m" : "mi · min/mi · ft")
```

To:

```swift
                Text(isMetric ? "km · min/km · m · °C" : "mi · min/mi · ft · °F")
```

- [ ] **Step 7: Build and run full test suite**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20`

Expected: All tests PASS.

- [ ] **Step 8: Commit**

```bash
git add Pilgrim/Models/Preferences/UserPreferences.swift Pilgrim/Scenes/Settings/GeneralSettingsView.swift UnitTests/UnitSystemTests.swift
git commit -m "refactor: extract applyUnitSystem to UserPreferences, add temperature to units label"
```

---

### Task 2: Auto-Detect During Setup

**Files:**
- Modify: `Pilgrim/Scenes/Setup/SetupCoordinatorView.swift:33-35`

- [ ] **Step 1: Add locale-based unit detection to setup flow**

In `SetupCoordinatorView.swift`, modify the `BreathTransitionView` closure (lines 33-35) from:

```swift
            case .breathTransition:
                BreathTransitionView {
                    UserPreferences.isSetUp.value = true
                }
```

To:

```swift
            case .breathTransition:
                BreathTransitionView {
                    UserPreferences.applyUnitSystem(metric: Locale.current.usesMetricSystem)
                    UserPreferences.isSetUp.value = true
                }
```

- [ ] **Step 2: Build and run full test suite**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20`

Expected: All tests PASS.

- [ ] **Step 3: Commit**

```bash
git add Pilgrim/Scenes/Setup/SetupCoordinatorView.swift
git commit -m "feat: auto-detect metric/imperial from locale at first launch"
```
