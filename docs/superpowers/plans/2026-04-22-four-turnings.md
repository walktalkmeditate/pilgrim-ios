# Four Turnings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Acknowledge the four astronomical turning points (solstices and equinoxes) with quiet, distributed visual touches across Pilgrim: home banner + inline scroll glyphs, active-walk kanji watermark + sunrise-azimuth ray, turning-colored walking-route segments, kanji suffix on walk-summary date, matching goshuin seal color.

**Architecture:** Extends existing `SeasonalMarker` enum (at `Pilgrim/Models/Astrology/AstrologyModels.swift:139`) with kanji/bannerText/color/sealColor computed properties. New `Hemisphere` enum + `TurningDayService` helper handle the per-walk, per-hemisphere mapping (southern-hemisphere users see 冬至 on June solstice, not December). Adds one new `CelestialCalculator.sunriseAzimuth(at:on:)` method; everything else leverages the existing `CelestialCalculator.snapshot(for:).seasonalMarker` detection.

**Tech Stack:** Swift / SwiftUI / Combine, CoreLocation, Mapbox Maps iOS SDK, CocoaPods. No new dependencies.

**Reference:** Design spec at `docs/superpowers/specs/2026-04-22-four-turnings-design.md`.

**Branch:** Assumes work happens on a feature branch (e.g., `feat/four-turnings`) created before Task 1.

---

## File Structure

**New files:**
- `Pilgrim/Models/Hemisphere.swift` — enum + coordinate extension
- `Pilgrim/Models/Astrology/SeasonalMarker+Turnings.swift` — computed properties (kanji, bannerText, color, sealColor, isTurning)
- `Pilgrim/Models/Astrology/TurningDayService.swift` — hemisphere-aware detection
- `Pilgrim/Scenes/Home/InkScrollView+TurningMarkers.swift` — inline glyph rendering, mirrors `InkScrollView+LunarMarkers.swift`
- `Pilgrim/Support Files/Assets.xcassets/turningJade.colorset/` (and `turningGold`, `turningClaret`, `turningIndigo`) — 4 colorsets with light/dark variants
- `UnitTests/HemisphereTests.swift`
- `UnitTests/SeasonalMarkerTurningTests.swift`
- `UnitTests/TurningDayServiceTests.swift`
- `UnitTests/CelestialCalculatorSunriseAzimuthTests.swift`
- `UnitTests/SealColorPaletteTurningTests.swift`

**Modified files:**
- `Pilgrim/Models/Astrology/CelestialCalculator.swift` — adds `sunriseAzimuth(at:on:)`
- `Pilgrim/Models/Seal/SealColorPalette.swift` — 4 new `SealColor` entries + new `uiColor(for: SealInput)` entry point
- `Pilgrim/Models/Seal/SealGenerator.swift` — call site at line 44 uses new entry point
- `Pilgrim/Scenes/Home/InkScrollView.swift` — banner + turning-marker call + pathSegmentColor override
- `Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift` — kanji watermark overlay + sunrise-ray overlay
- `Pilgrim/Views/PilgrimMapView.swift` — route color expression turning branch + sunrise ray layer
- `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift` — date title kanji suffix
- `Pilgrim/Scenes/WalkShare/WalkShareViewModel.swift` + `Pilgrim/Models/ShareService.swift` — `turningDay` payload field
- `Pilgrim/Models/LS.swift` — localized strings
- `Pilgrim.xcodeproj/project.pbxproj` — register all new files (Pilgrim/ and UnitTests/ are NOT synchronized root groups; manual pbxproj edits required — see pattern in commit `96ae8e4`)

---

## Task 1: Hemisphere enum

**Files:**
- Create: `Pilgrim/Models/Hemisphere.swift`
- Create: `UnitTests/HemisphereTests.swift`

- [ ] **Step 1: Write the failing test**

Create `UnitTests/HemisphereTests.swift`:

```swift
import XCTest
import CoreLocation
@testable import Pilgrim

final class HemisphereTests: XCTestCase {

    func testNorthern_positiveLatitude() {
        let coord = CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0)
        XCTAssertEqual(Hemisphere(coordinate: coord), .northern)
    }

    func testSouthern_negativeLatitude() {
        let coord = CLLocationCoordinate2D(latitude: -33.9, longitude: 151.2)
        XCTAssertEqual(Hemisphere(coordinate: coord), .southern)
    }

    func testEquator_returnsNorthern() {
        let coord = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        XCTAssertEqual(Hemisphere(coordinate: coord), .northern)
    }

    func testNil_returnsNorthern() {
        XCTAssertEqual(Hemisphere(coordinate: nil), .northern)
    }
}
```

- [ ] **Step 2: Run the test to verify compile failure**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/HemisphereTests 2>&1 | tail -10
```

Expected: compile error (`Hemisphere` undefined).

- [ ] **Step 3: Implement `Hemisphere`**

Create `Pilgrim/Models/Hemisphere.swift`:

```swift
import Foundation
import CoreLocation

enum Hemisphere: Equatable {
    case northern
    case southern

    init(coordinate: CLLocationCoordinate2D?) {
        guard let coord = coordinate else {
            self = .northern
            return
        }
        self = coord.latitude < 0 ? .southern : .northern
    }
}
```

- [ ] **Step 4: Register new files in Xcode project**

Run:
```bash
grep -c "Hemisphere.swift\|HemisphereTests.swift" Pilgrim.xcodeproj/project.pbxproj
```

Expected: `>= 4`. If less, manually add both files to `project.pbxproj` following the pattern from commit `96ae8e4` — add `PBXFileReference`, `PBXBuildFile`, group membership (Pilgrim target for `Hemisphere.swift`, UnitTests target for `HemisphereTests.swift`), and the appropriate `PBXSourcesBuildPhase` entries.

- [ ] **Step 5: Run tests to verify pass**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/HemisphereTests 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`, 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Pilgrim/Models/Hemisphere.swift UnitTests/HemisphereTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(turnings): add Hemisphere enum with coordinate-based derivation"
```

---

## Task 2: Four turning Color assets

**Files:**
- Create: `Pilgrim/Support Files/Assets.xcassets/turningJade.colorset/Contents.json`
- Create: `Pilgrim/Support Files/Assets.xcassets/turningGold.colorset/Contents.json`
- Create: `Pilgrim/Support Files/Assets.xcassets/turningClaret.colorset/Contents.json`
- Create: `Pilgrim/Support Files/Assets.xcassets/turningIndigo.colorset/Contents.json`

Colorsets have both light and dark variants. Light values match the spec; dark values are slightly lighter/brighter variants for legibility on dark parchment.

- [ ] **Step 1: Create turningJade colorset**

Create directory `Pilgrim/Support Files/Assets.xcassets/turningJade.colorset/` and `Contents.json` inside:

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.584",
          "green" : "0.706",
          "red" : "0.455"
        }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.627",
          "green" : "0.769",
          "red" : "0.533"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 2: Create turningGold colorset**

Directory `Pilgrim/Support Files/Assets.xcassets/turningGold.colorset/` and `Contents.json`:

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.275",
          "green" : "0.651",
          "red" : "0.788"
        }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.365",
          "green" : "0.710",
          "red" : "0.835"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 3: Create turningClaret colorset**

Directory `Pilgrim/Support Files/Assets.xcassets/turningClaret.colorset/` and `Contents.json`:

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.333",
          "green" : "0.267",
          "red" : "0.545"
        }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.439",
          "green" : "0.376",
          "red" : "0.635"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 4: Create turningIndigo colorset**

Directory `Pilgrim/Support Files/Assets.xcassets/turningIndigo.colorset/` and `Contents.json`:

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.643",
          "green" : "0.467",
          "red" : "0.137"
        }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.729",
          "green" : "0.569",
          "red" : "0.275"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 5: Verify build picks up the new assets**

Run:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. (Xcode Asset Catalog picks up colorsets automatically — no pbxproj edit needed for .colorset directories inside a registered .xcassets.)

- [ ] **Step 6: Commit**

```bash
git add "Pilgrim/Support Files/Assets.xcassets/turningJade.colorset" "Pilgrim/Support Files/Assets.xcassets/turningGold.colorset" "Pilgrim/Support Files/Assets.xcassets/turningClaret.colorset" "Pilgrim/Support Files/Assets.xcassets/turningIndigo.colorset"
git commit -m "feat(turnings): add 4 turning colorsets with light and dark variants"
```

---

## Task 3: SeasonalMarker+Turnings extension

**Files:**
- Create: `Pilgrim/Models/Astrology/SeasonalMarker+Turnings.swift`
- Create: `UnitTests/SeasonalMarkerTurningTests.swift`
- Modify: `Pilgrim/Models/LS.swift` — add 2 new localized strings

- [ ] **Step 1: Write the failing test**

Create `UnitTests/SeasonalMarkerTurningTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import Pilgrim

final class SeasonalMarkerTurningTests: XCTestCase {

    // MARK: - kanji

    func testKanji_springEquinox() {
        XCTAssertEqual(SeasonalMarker.springEquinox.kanji, "春分")
    }

    func testKanji_summerSolstice() {
        XCTAssertEqual(SeasonalMarker.summerSolstice.kanji, "夏至")
    }

    func testKanji_autumnEquinox() {
        XCTAssertEqual(SeasonalMarker.autumnEquinox.kanji, "秋分")
    }

    func testKanji_winterSolstice() {
        XCTAssertEqual(SeasonalMarker.winterSolstice.kanji, "冬至")
    }

    func testKanji_crossQuarter_returnsNil() {
        XCTAssertNil(SeasonalMarker.imbolc.kanji)
        XCTAssertNil(SeasonalMarker.beltane.kanji)
        XCTAssertNil(SeasonalMarker.lughnasadh.kanji)
        XCTAssertNil(SeasonalMarker.samhain.kanji)
    }

    // MARK: - bannerText

    func testBannerText_solstices_saySunStandsStill() {
        XCTAssertEqual(SeasonalMarker.summerSolstice.bannerText, "Today the sun stands still")
        XCTAssertEqual(SeasonalMarker.winterSolstice.bannerText, "Today the sun stands still")
    }

    func testBannerText_equinoxes_sayDayEqualsNight() {
        XCTAssertEqual(SeasonalMarker.springEquinox.bannerText, "Today, day equals night")
        XCTAssertEqual(SeasonalMarker.autumnEquinox.bannerText, "Today, day equals night")
    }

    func testBannerText_crossQuarter_returnsNil() {
        XCTAssertNil(SeasonalMarker.imbolc.bannerText)
    }

    // MARK: - colorAssetName

    func testColorAssetName_forEachTurning() {
        XCTAssertEqual(SeasonalMarker.springEquinox.colorAssetName, "turningJade")
        XCTAssertEqual(SeasonalMarker.summerSolstice.colorAssetName, "turningGold")
        XCTAssertEqual(SeasonalMarker.autumnEquinox.colorAssetName, "turningClaret")
        XCTAssertEqual(SeasonalMarker.winterSolstice.colorAssetName, "turningIndigo")
    }

    func testColorAssetName_crossQuarter_returnsNil() {
        XCTAssertNil(SeasonalMarker.imbolc.colorAssetName)
    }

    // MARK: - isTurning

    func testIsTurning_trueForFourMainMarkers() {
        XCTAssertTrue(SeasonalMarker.springEquinox.isTurning)
        XCTAssertTrue(SeasonalMarker.summerSolstice.isTurning)
        XCTAssertTrue(SeasonalMarker.autumnEquinox.isTurning)
        XCTAssertTrue(SeasonalMarker.winterSolstice.isTurning)
    }

    func testIsTurning_falseForCrossQuarter() {
        XCTAssertFalse(SeasonalMarker.imbolc.isTurning)
        XCTAssertFalse(SeasonalMarker.beltane.isTurning)
        XCTAssertFalse(SeasonalMarker.lughnasadh.isTurning)
        XCTAssertFalse(SeasonalMarker.samhain.isTurning)
    }
}
```

- [ ] **Step 2: Run the test to verify compile failure**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/SeasonalMarkerTurningTests 2>&1 | tail -10
```

Expected: compile error (properties `kanji`, `bannerText`, `colorAssetName`, `isTurning` undefined on `SeasonalMarker`).

- [ ] **Step 3: Add LS entries**

Open `Pilgrim/Models/LS.swift` and add two new static properties alongside existing `LS.*` definitions. Look for a section that makes sense (banner/UI strings); follow the existing naming convention.

Add:

```swift
/// Banner text shown on the home scroll during solstices.
static let turningSolsticeBanner = NSLocalizedString(
    "turning.solstice.banner",
    value: "Today the sun stands still",
    comment: "Home-scroll banner text on winter or summer solstice."
)

/// Banner text shown on the home scroll during equinoxes.
static let turningEquinoxBanner = NSLocalizedString(
    "turning.equinox.banner",
    value: "Today, day equals night",
    comment: "Home-scroll banner text on spring or autumn equinox."
)
```

- [ ] **Step 4: Implement the extension**

Create `Pilgrim/Models/Astrology/SeasonalMarker+Turnings.swift`:

```swift
import SwiftUI

extension SeasonalMarker {

    /// Single-character kanji representing this turning. Nil for cross-quarter markers.
    var kanji: String? {
        switch self {
        case .springEquinox:  return "春分"
        case .summerSolstice: return "夏至"
        case .autumnEquinox:  return "秋分"
        case .winterSolstice: return "冬至"
        case .imbolc, .beltane, .lughnasadh, .samhain: return nil
        }
    }

    /// Localized banner copy. Solstices read "Today the sun stands still";
    /// equinoxes read "Today, day equals night". Nil for cross-quarter.
    var bannerText: String? {
        switch self {
        case .springEquinox, .autumnEquinox:  return LS.turningEquinoxBanner
        case .summerSolstice, .winterSolstice: return LS.turningSolsticeBanner
        case .imbolc, .beltane, .lughnasadh, .samhain: return nil
        }
    }

    /// Asset Catalog color name for this turning's walking-segment color.
    /// Nil for cross-quarter.
    var colorAssetName: String? {
        switch self {
        case .springEquinox:  return "turningJade"
        case .summerSolstice: return "turningGold"
        case .autumnEquinox:  return "turningClaret"
        case .winterSolstice: return "turningIndigo"
        case .imbolc, .beltane, .lughnasadh, .samhain: return nil
        }
    }

    /// SwiftUI Color resolved from the asset catalog. Nil for cross-quarter.
    var color: Color? {
        guard let name = colorAssetName else { return nil }
        return Color(name)
    }

    /// UIColor resolved from the asset catalog. Nil for cross-quarter.
    var uiColor: UIColor? {
        guard let name = colorAssetName else { return nil }
        return UIColor(named: name)
    }

    /// True iff this marker is one of the 4 main solstices/equinoxes.
    /// False for the 4 cross-quarter markers (imbolc/beltane/lughnasadh/samhain)
    /// which are out of scope for the Four Turnings feature.
    var isTurning: Bool {
        switch self {
        case .springEquinox, .summerSolstice, .autumnEquinox, .winterSolstice: return true
        case .imbolc, .beltane, .lughnasadh, .samhain: return false
        }
    }
}
```

- [ ] **Step 5: Register new file in Xcode project**

Check: `grep -c "SeasonalMarker+Turnings.swift\|SeasonalMarkerTurningTests.swift" Pilgrim.xcodeproj/project.pbxproj`. Expected `>= 4`. If not, add both files to the project manually following the `96ae8e4` pattern (Pilgrim target for extension, UnitTests target for test).

- [ ] **Step 6: Run tests to verify pass**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/SeasonalMarkerTurningTests 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`, 13 tests pass.

- [ ] **Step 7: Commit**

```bash
git add Pilgrim/Models/Astrology/SeasonalMarker+Turnings.swift UnitTests/SeasonalMarkerTurningTests.swift Pilgrim/Models/LS.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(turnings): add SeasonalMarker properties for kanji, banner, color"
```

---

## Task 4: CelestialCalculator.sunriseAzimuth

**Files:**
- Modify: `Pilgrim/Models/Astrology/CelestialCalculator.swift`
- Create: `UnitTests/CelestialCalculatorSunriseAzimuthTests.swift`

- [ ] **Step 1: Write the failing test**

Create `UnitTests/CelestialCalculatorSunriseAzimuthTests.swift`:

```swift
import XCTest
import CoreLocation
@testable import Pilgrim

final class CelestialCalculatorSunriseAzimuthTests: XCTestCase {

    /// Approximate equality for azimuths (degrees). Astronomical formulas
    /// have ~1° accuracy depending on refraction assumptions.
    private let azimuthTolerance: Double = 3.0

    private func date(year: Int, month: Int, day: Int) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = 12
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    // MARK: - Equinox at equator: sunrise due east (~90°)

    func testEquinox_atEquator_risesDueEast() {
        let equator = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let marchEquinox = date(year: 2024, month: 3, day: 20)
        guard let azimuth = CelestialCalculator.sunriseAzimuth(at: equator, on: marchEquinox) else {
            return XCTFail("expected non-nil azimuth at equator on equinox")
        }
        XCTAssertEqual(azimuth, 90.0, accuracy: azimuthTolerance)
    }

    // MARK: - Summer solstice at mid-latitude: north of east

    func testSummerSolstice_atNewYork_northOfEast() {
        let nyc = CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0)
        let juneSolstice = date(year: 2024, month: 6, day: 20)
        guard let azimuth = CelestialCalculator.sunriseAzimuth(at: nyc, on: juneSolstice) else {
            return XCTFail("expected non-nil azimuth")
        }
        // Summer solstice at ~41°N: sunrise azimuth ~57-60° (well north of due east)
        XCTAssertLessThan(azimuth, 70.0)
        XCTAssertGreaterThan(azimuth, 50.0)
    }

    // MARK: - Winter solstice at mid-latitude: south of east

    func testWinterSolstice_atNewYork_southOfEast() {
        let nyc = CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0)
        let decSolstice = date(year: 2024, month: 12, day: 21)
        guard let azimuth = CelestialCalculator.sunriseAzimuth(at: nyc, on: decSolstice) else {
            return XCTFail("expected non-nil azimuth")
        }
        // Winter solstice at ~41°N: sunrise azimuth ~120-123° (south of due east)
        XCTAssertGreaterThan(azimuth, 115.0)
        XCTAssertLessThan(azimuth, 130.0)
    }

    // MARK: - Polar: sun doesn't rise

    func testWinterSolstice_aboveArcticCircle_returnsNil() {
        // 78°N, December solstice: polar night, sun doesn't rise.
        let svalbard = CLLocationCoordinate2D(latitude: 78.0, longitude: 15.0)
        let decSolstice = date(year: 2024, month: 12, day: 21)
        XCTAssertNil(CelestialCalculator.sunriseAzimuth(at: svalbard, on: decSolstice))
    }

    // MARK: - Azimuth is in [0, 360)

    func testAzimuth_alwaysInValidRange() {
        let coords = [
            CLLocationCoordinate2D(latitude: 40, longitude: 0),
            CLLocationCoordinate2D(latitude: -33, longitude: 151),
            CLLocationCoordinate2D(latitude: 60, longitude: -120),
        ]
        let dates = [
            date(year: 2024, month: 3, day: 20),
            date(year: 2024, month: 6, day: 20),
            date(year: 2024, month: 9, day: 22),
            date(year: 2024, month: 12, day: 21),
        ]
        for coord in coords {
            for d in dates {
                if let az = CelestialCalculator.sunriseAzimuth(at: coord, on: d) {
                    XCTAssertGreaterThanOrEqual(az, 0.0)
                    XCTAssertLessThan(az, 360.0)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Run the test to verify compile failure**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/CelestialCalculatorSunriseAzimuthTests 2>&1 | tail -10
```

Expected: compile error (`sunriseAzimuth(at:on:)` undefined).

- [ ] **Step 3: Implement `sunriseAzimuth(at:on:)`**

In `Pilgrim/Models/Astrology/CelestialCalculator.swift`, add after the existing `seasonalMarker` function:

```swift
// MARK: - Sunrise Azimuth

/// Compass azimuth (degrees clockwise from true north) where the sun rises
/// on the given date at the given location. Returns nil if the sun does
/// not rise that day (polar night/day).
///
/// Uses the standard formula:
///   cos(A) = (sin(δ) - sin(φ) · sin(h)) / (cos(φ) · cos(h))
/// where δ is the sun's declination, φ is the observer's latitude, and
/// h is the sun's altitude at sunrise (~-0.833° accounting for refraction
/// and solar disk radius). Azimuth A is measured from due south in the
/// traditional formula; we convert to compass-from-true-north below.
///
/// Accuracy is ~1-2 degrees, sufficient for a visual orientation marker.
static func sunriseAzimuth(at coordinate: CLLocationCoordinate2D, on date: Date) -> CLLocationDirection? {
    let lat = coordinate.latitude
    let T = julianCenturies(from: julianDayNumber(from: date))
    let sunLon = solarLongitude(T: T)

    // Sun's declination (degrees)
    // δ = asin(sin(obliquity) · sin(sunLon))
    let obliquity = 23.439291 - 0.0130042 * T
    let declination = degrees(asin(
        sin(radians(obliquity)) * sin(radians(sunLon))
    ))

    // Standard altitude at sunrise: -0.833° (atmospheric refraction + solar radius)
    let h: Double = -0.833

    let phi = radians(lat)
    let delta = radians(declination)
    let hRad = radians(h)

    let cosLat = cos(phi)
    guard abs(cosLat) > 1e-9 else { return nil }

    let numerator = sin(delta) - sin(phi) * sin(hRad)
    let denominator = cosLat * cos(hRad)
    let cosA = numerator / denominator

    // If |cosA| > 1, the sun doesn't rise (polar) — return nil.
    guard cosA >= -1.0 && cosA <= 1.0 else { return nil }

    // A is measured clockwise from true north at sunrise (east side).
    // acos returns [0, π], giving an angle from north via east.
    let azimuth = degrees(acos(cosA))
    return azimuth
}
```

- [ ] **Step 4: Register new test file in Xcode project**

Check: `grep -c "CelestialCalculatorSunriseAzimuthTests.swift" Pilgrim.xcodeproj/project.pbxproj`. Expected `>= 2`. If not, add it to UnitTests target.

- [ ] **Step 5: Run tests to verify pass**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/CelestialCalculatorSunriseAzimuthTests 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`, 5 tests pass.

If tests fail on the tolerance checks, the formula may be off by a sign convention or refraction constant. The tolerances in the tests (±3°) are generous; if you're outside them by ~5-10°, re-examine the azimuth direction convention (some formulas give azimuth from south, ours should give from north).

- [ ] **Step 6: Commit**

```bash
git add Pilgrim/Models/Astrology/CelestialCalculator.swift UnitTests/CelestialCalculatorSunriseAzimuthTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(turnings): add CelestialCalculator.sunriseAzimuth(at:on:)"
```

---

## Task 5: TurningDayService

**Files:**
- Create: `Pilgrim/Models/Astrology/TurningDayService.swift`
- Create: `UnitTests/TurningDayServiceTests.swift`

- [ ] **Step 1: Write the failing test**

Create `UnitTests/TurningDayServiceTests.swift`:

```swift
import XCTest
import CoreLocation
@testable import Pilgrim

final class TurningDayServiceTests: XCTestCase {

    private func date(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    // MARK: - Northern hemisphere: astronomical = seasonal

    func testMarchEquinox_northern_returnsSpringEquinox() {
        let coord = CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0)
        let d = date(year: 2024, month: 3, day: 20)
        XCTAssertEqual(TurningDayService.turning(for: d, at: coord), .springEquinox)
    }

    func testJuneSolstice_northern_returnsSummerSolstice() {
        let coord = CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0)
        let d = date(year: 2024, month: 6, day: 20)
        XCTAssertEqual(TurningDayService.turning(for: d, at: coord), .summerSolstice)
    }

    func testDecemberSolstice_northern_returnsWinterSolstice() {
        let coord = CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0)
        let d = date(year: 2024, month: 12, day: 21)
        XCTAssertEqual(TurningDayService.turning(for: d, at: coord), .winterSolstice)
    }

    // MARK: - Southern hemisphere: mirrored

    func testJuneSolstice_southern_returnsWinterSolstice() {
        let sydney = CLLocationCoordinate2D(latitude: -33.9, longitude: 151.2)
        let d = date(year: 2024, month: 6, day: 20)
        XCTAssertEqual(TurningDayService.turning(for: d, at: sydney), .winterSolstice)
    }

    func testDecemberSolstice_southern_returnsSummerSolstice() {
        let sydney = CLLocationCoordinate2D(latitude: -33.9, longitude: 151.2)
        let d = date(year: 2024, month: 12, day: 21)
        XCTAssertEqual(TurningDayService.turning(for: d, at: sydney), .summerSolstice)
    }

    func testMarchEquinox_southern_returnsAutumnEquinox() {
        let sydney = CLLocationCoordinate2D(latitude: -33.9, longitude: 151.2)
        let d = date(year: 2024, month: 3, day: 20)
        XCTAssertEqual(TurningDayService.turning(for: d, at: sydney), .autumnEquinox)
    }

    func testSeptemberEquinox_southern_returnsSpringEquinox() {
        let sydney = CLLocationCoordinate2D(latitude: -33.9, longitude: 151.2)
        let d = date(year: 2024, month: 9, day: 22)
        XCTAssertEqual(TurningDayService.turning(for: d, at: sydney), .springEquinox)
    }

    // MARK: - Non-turning

    func testNonTurningDay_returnsNil() {
        let coord = CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0)
        let d = date(year: 2024, month: 5, day: 15)
        XCTAssertNil(TurningDayService.turning(for: d, at: coord))
    }

    // MARK: - Cross-quarter markers excluded

    func testCrossQuarterDate_returnsNil() {
        let coord = CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0)
        // Beltane is around May 5-6 (sun at ecliptic longitude 45°)
        let d = date(year: 2024, month: 5, day: 5)
        XCTAssertNil(TurningDayService.turning(for: d, at: coord))
    }

    // MARK: - Nil coordinate defaults to northern

    func testNilCoordinate_defaultsToNorthern() {
        let d = date(year: 2024, month: 12, day: 21)
        XCTAssertEqual(TurningDayService.turning(for: d, at: nil), .winterSolstice)
    }
}
```

- [ ] **Step 2: Run the test to verify compile failure**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/TurningDayServiceTests 2>&1 | tail -10
```

Expected: compile error (`TurningDayService` undefined).

- [ ] **Step 3: Implement `TurningDayService`**

Create `Pilgrim/Models/Astrology/TurningDayService.swift`:

```swift
import Foundation
import CoreLocation

/// Hemisphere-aware turning-day detection.
///
/// `CelestialCalculator.seasonalMarker(sunLongitude:)` returns astronomical
/// markers (always named by their northern-hemisphere meaning: a June
/// solstice always returns `.summerSolstice`). This service translates
/// that to the seasonally-correct marker for the observer's hemisphere.
///
/// Only the 4 main solstices/equinoxes are surfaced. Cross-quarter markers
/// (imbolc/beltane/lughnasadh/samhain) are filtered out.
enum TurningDayService {

    /// Returns the seasonally-correct turning for the given date and location.
    ///
    /// - Parameters:
    ///   - date: The date to check. Used for the astronomical calculation;
    ///           the `CelestialCalculator` uses its day-resolution sun
    ///           longitude to detect turnings.
    ///   - coordinate: The observer's location. Used to determine hemisphere
    ///                 (positive latitude → northern; negative → southern;
    ///                 nil → northern). Pass the walk's first coordinate for
    ///                 a historical walk; pass the most recent walk's
    ///                 coordinate for "today's" queries.
    /// - Returns: A `SeasonalMarker` of one of the 4 turnings, or nil if
    ///            the date is not a turning day (including cross-quarter
    ///            astronomical markers, which this feature doesn't surface).
    static func turning(for date: Date, at coordinate: CLLocationCoordinate2D?) -> SeasonalMarker? {
        let snapshot = CelestialCalculator.snapshot(for: date)
        guard let astronomical = snapshot.seasonalMarker, astronomical.isTurning else {
            return nil
        }
        let hemisphere = Hemisphere(coordinate: coordinate)
        return mapping(astronomical: astronomical, hemisphere: hemisphere)
    }

    /// Translates the astronomical (northern-named) marker to the
    /// seasonally-correct marker for the given hemisphere.
    private static func mapping(astronomical: SeasonalMarker, hemisphere: Hemisphere) -> SeasonalMarker {
        guard hemisphere == .southern else { return astronomical }
        switch astronomical {
        case .springEquinox:  return .autumnEquinox
        case .summerSolstice: return .winterSolstice
        case .autumnEquinox:  return .springEquinox
        case .winterSolstice: return .summerSolstice
        case .imbolc, .beltane, .lughnasadh, .samhain: return astronomical  // not surfaced
        }
    }
}
```

- [ ] **Step 4: Register new files in Xcode project**

Check: `grep -c "TurningDayService.swift\|TurningDayServiceTests.swift" Pilgrim.xcodeproj/project.pbxproj`. Expected `>= 4`. Add manually if not.

- [ ] **Step 5: Run tests to verify pass**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/TurningDayServiceTests 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`, 11 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Pilgrim/Models/Astrology/TurningDayService.swift UnitTests/TurningDayServiceTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(turnings): add TurningDayService with hemisphere-aware mapping"
```

---

## Task 6: SealColorPalette turning colors + SeasonalMarker.sealColor

**Files:**
- Modify: `Pilgrim/Models/Seal/SealColorPalette.swift` — 4 new `SealColor` entries, new `uiColor(for: SealInput)` entry point
- Modify: `Pilgrim/Models/Seal/SealGenerator.swift` — call site update at line 44
- Modify: `Pilgrim/Models/Astrology/SeasonalMarker+Turnings.swift` — add `sealColor` property
- Create: `UnitTests/SealColorPaletteTurningTests.swift`

- [ ] **Step 1: Write the failing test**

Create `UnitTests/SealColorPaletteTurningTests.swift`:

```swift
import XCTest
import CoreLocation
import UIKit
@testable import Pilgrim

final class SealColorPaletteTurningTests: XCTestCase {

    private func date(year: Int, month: Int, day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = 12
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func sealInput(startDate: Date, lat: Double, lon: Double, favicon: String? = "leaf") -> SealInput {
        SealInput(
            uuid: UUID(),
            startDate: startDate,
            activeDuration: 1800,
            meditateDuration: 300,
            talkDuration: 0,
            distance: 2000,
            steps: 3000,
            elevationUp: 10,
            elevationDown: 10,
            averagePace: 0.9,
            routePoints: [SealInput.RoutePoint(lat: lat, lon: lon)],
            favicon: favicon,
            intention: nil,
            weather: nil
        )
    }

    // MARK: - Turning day override

    func testTurningDayInput_northernJuneSolstice_returnsGoldSealColor() {
        let input = sealInput(startDate: date(year: 2024, month: 6, day: 20), lat: 40.7, lon: -74.0)
        let color = SealColorPalette.uiColor(for: input)
        XCTAssertEqual(color, UIColor(named: "turningGold"))
    }

    func testTurningDayInput_southernJuneSolstice_returnsIndigoSealColor() {
        let input = sealInput(startDate: date(year: 2024, month: 6, day: 20), lat: -33.9, lon: 151.2)
        let color = SealColorPalette.uiColor(for: input)
        XCTAssertEqual(color, UIColor(named: "turningIndigo"))
    }

    func testTurningDayInput_northernMarchEquinox_returnsJadeSealColor() {
        let input = sealInput(startDate: date(year: 2024, month: 3, day: 20), lat: 40.7, lon: -74.0)
        let color = SealColorPalette.uiColor(for: input)
        XCTAssertEqual(color, UIColor(named: "turningJade"))
    }

    func testTurningDayInput_northernSeptemberEquinox_returnsClaretSealColor() {
        let input = sealInput(startDate: date(year: 2024, month: 9, day: 22), lat: 40.7, lon: -74.0)
        let color = SealColorPalette.uiColor(for: input)
        XCTAssertEqual(color, UIColor(named: "turningClaret"))
    }

    // MARK: - Turning override ignores favicon

    func testTurningDayInput_ignoresFaviconHashSelection() {
        // A turning-day walk with a "flame" favicon would normally pick a warm color.
        // On a turning day it should return the turning color instead.
        let input = sealInput(
            startDate: date(year: 2024, month: 6, day: 20),
            lat: 40.7,
            lon: -74.0,
            favicon: "flame"
        )
        let color = SealColorPalette.uiColor(for: input)
        XCTAssertEqual(color, UIColor(named: "turningGold"))
        XCTAssertNotEqual(color, SealColorPalette.rust.light)
    }

    // MARK: - Non-turning walks unchanged

    func testNonTurningInput_returnsFaviconHashColor() {
        // Non-turning date — should fall through to favicon-hash logic.
        let input = sealInput(
            startDate: date(year: 2024, month: 5, day: 15),
            lat: 40.7,
            lon: -74.0,
            favicon: "leaf"
        )
        let color = SealColorPalette.uiColor(for: input)
        // Leaf → coolColors. We can't know which specific color the hash picks
        // without computing it, but it should be one of the cool set.
        let coolColors = SealColorPalette.coolColors.map { $0.light }
        XCTAssertTrue(coolColors.contains(color), "Expected a cool color for non-turning leaf walk")
    }

    // MARK: - SeasonalMarker.sealColor

    func testSealColor_forEachTurning() {
        XCTAssertEqual(SeasonalMarker.springEquinox.sealColor?.light, UIColor(named: "turningJade"))
        XCTAssertEqual(SeasonalMarker.summerSolstice.sealColor?.light, UIColor(named: "turningGold"))
        XCTAssertEqual(SeasonalMarker.autumnEquinox.sealColor?.light, UIColor(named: "turningClaret"))
        XCTAssertEqual(SeasonalMarker.winterSolstice.sealColor?.light, UIColor(named: "turningIndigo"))
    }

    func testSealColor_crossQuarter_returnsNil() {
        XCTAssertNil(SeasonalMarker.imbolc.sealColor)
    }
}
```

- [ ] **Step 2: Run the test to verify compile failure**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/SealColorPaletteTurningTests 2>&1 | tail -10
```

Expected: compile errors — `SealColorPalette.uiColor(for: SealInput)` and `SeasonalMarker.sealColor` undefined.

- [ ] **Step 3: Add 4 new `SealColor` entries to `SealColorPalette.swift`**

In `Pilgrim/Models/Seal/SealColorPalette.swift`, find the section with existing seal colors (around `static let rust = SealColor(...)`) and add 4 new entries. Place them in a new group with a clear comment:

```swift
// Turning (solstice / equinox overrides — not included in warm/cool/accent/neutral arrays)
static let turningJade    = SealColor(
    light: UIColor(named: "turningJade")  ?? UIColor(hex: "#74B495"),
    dark:  UIColor(named: "turningJade")  ?? UIColor(hex: "#88C5A0"),
    cssVar: "--seal-turning-jade"
)
static let turningGold    = SealColor(
    light: UIColor(named: "turningGold")  ?? UIColor(hex: "#C9A646"),
    dark:  UIColor(named: "turningGold")  ?? UIColor(hex: "#D5B55D"),
    cssVar: "--seal-turning-gold"
)
static let turningClaret  = SealColor(
    light: UIColor(named: "turningClaret") ?? UIColor(hex: "#8B4455"),
    dark:  UIColor(named: "turningClaret") ?? UIColor(hex: "#A26070"),
    cssVar: "--seal-turning-claret"
)
static let turningIndigo  = SealColor(
    light: UIColor(named: "turningIndigo") ?? UIColor(hex: "#2377A4"),
    dark:  UIColor(named: "turningIndigo") ?? UIColor(hex: "#4691BA"),
    cssVar: "--seal-turning-indigo"
)
```

These are intentionally NOT added to `warmColors`/`coolColors`/`accentColors`/`neutralColors` — they exist only as turning-day overrides.

- [ ] **Step 4: Add `uiColor(for: SealInput)` entry point**

Still in `SealColorPalette.swift`, add after the existing `color(for: favicon, hashByte:)` and `uiColor(for: favicon, hashByte:)` functions:

```swift
/// Entry point used by `SealGenerator`. Pre-checks for a turning day
/// and returns the matching turning seal color; otherwise falls back
/// to the existing favicon+hash selection.
static func uiColor(for input: SealInput) -> UIColor {
    let firstPoint = input.routePoints.first
    let coord = firstPoint.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    if let turning = TurningDayService.turning(for: input.startDate, at: coord),
       let sealColor = turning.sealColor {
        return sealColor.light
    }
    let favicon = input.favicon.flatMap { WalkFavicon(rawValue: $0) }
    let bytes = SealHashComputer.hexToBytes(SealHashComputer.computeHashFromInput(input))
    return uiColor(for: favicon, hashByte: bytes[30])
}
```

Ensure `import CoreLocation` is present at the top of the file; add it if missing.

- [ ] **Step 5: Add `sealColor` property to `SeasonalMarker+Turnings.swift`**

Open `Pilgrim/Models/Astrology/SeasonalMarker+Turnings.swift` and append this property inside the `extension SeasonalMarker { }` block:

```swift
/// `SealColorPalette` entry to use for the goshuin seal on this turning.
/// Nil for cross-quarter.
var sealColor: SealColorPalette.SealColor? {
    switch self {
    case .springEquinox:  return SealColorPalette.turningJade
    case .summerSolstice: return SealColorPalette.turningGold
    case .autumnEquinox:  return SealColorPalette.turningClaret
    case .winterSolstice: return SealColorPalette.turningIndigo
    case .imbolc, .beltane, .lughnasadh, .samhain: return nil
    }
}
```

- [ ] **Step 6: Update `SealGenerator.swift` call site**

In `Pilgrim/Models/Seal/SealGenerator.swift`, line 44, replace:

```swift
let color = SealColorPalette.uiColor(for: favicon, hashByte: bytes[30])
```

with:

```swift
let color = SealColorPalette.uiColor(for: input)
```

The `favicon` and `bytes` local variables can still exist if used elsewhere in the function — leave them. Only the single assignment to `color` changes.

- [ ] **Step 7: Register new test file in Xcode project**

Check: `grep -c "SealColorPaletteTurningTests.swift" Pilgrim.xcodeproj/project.pbxproj`. Expected `>= 2`. Add to UnitTests target if not.

- [ ] **Step 8: Run tests to verify pass**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/SealColorPaletteTurningTests 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`, 8 tests pass.

- [ ] **Step 9: Run the full unit test suite to verify no regression**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests 2>&1 | grep -E "Executed [0-9]+ tests|TEST SUCCEEDED|TEST FAILED" | tail -3
```

Expected: all tests still pass, count has increased by the new tests from Tasks 1–6.

- [ ] **Step 10: Commit**

```bash
git add Pilgrim/Models/Seal/SealColorPalette.swift Pilgrim/Models/Seal/SealGenerator.swift Pilgrim/Models/Astrology/SeasonalMarker+Turnings.swift UnitTests/SealColorPaletteTurningTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(turnings): match goshuin seal color to route on turning days"
```

---

## Task 7: InkScrollView turning-day banner

**Files:**
- Modify: `Pilgrim/Scenes/Home/InkScrollView.swift`

The banner renders at the top of `scrollContent`, **independent of walk history**. It uses today's date and the hemisphere derived from the most-recent walk (or northern if no walks).

- [ ] **Step 1: Read current scrollContent**

Run:
```bash
sed -n '52,75p' Pilgrim/Scenes/Home/InkScrollView.swift
```

Confirm the structure: `scrollContent(width:height:)` returns a `ZStack(alignment: .top)` containing a Group with `journeySummaryHeader` gated by `!snapshots.isEmpty`.

- [ ] **Step 2: Add the banner view inside scrollContent**

In `InkScrollView.swift`, add a new computed property (near the other private view helpers, after `scrollContent`):

```swift
/// Banner shown at the top of the home scroll on solstices / equinoxes.
/// Renders regardless of whether the user has any walks yet, so new users
/// see the acknowledgment on their first turning day.
@ViewBuilder
private var turningBanner: some View {
    if let turning = currentTurning, let text = turning.bannerText, let kanji = turning.kanji {
        HStack(spacing: 8) {
            Text(text)
                .font(Constants.Typography.body)
                .foregroundColor(.fog)
            Text("·")
                .font(Constants.Typography.body)
                .foregroundColor(.fog.opacity(0.5))
            if let color = turning.color {
                Text(kanji)
                    .font(Constants.Typography.body)
                    .foregroundColor(color)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Constants.UI.Padding.big)
        .padding(.bottom, Constants.UI.Padding.small)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(text). \(turning.name).")
    }
}

/// Turning for today, based on the hemisphere of the most recent walk
/// (or northern if the user has no walks yet).
private var currentTurning: SeasonalMarker? {
    let coord = snapshots.first.flatMap { snapshot in
        snapshot.routeData.first.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }
    return TurningDayService.turning(for: Date(), at: coord)
}
```

Ensure `import CoreLocation` is present at the top of the file; add it if missing.

- [ ] **Step 3: Render the banner at the top of scrollContent**

Find the `scrollContent(width:height:)` function. Inside its returned ZStack, find the `Group { if !snapshots.isEmpty { journeySummaryHeader(...) } ... }` and prepend the banner **outside** the `!snapshots.isEmpty` gate:

```swift
return ZStack(alignment: .top) {
    turningBanner
    Group {
        if !snapshots.isEmpty {
            journeySummaryHeader(width: width)
        }
        // ... rest of existing code
    }
}
```

The banner uses `.frame(maxWidth: .infinity)` and padding, so it occupies its natural height at the very top of the scroll regardless of other content.

Adjust `journeySummaryHeader`'s top offset or padding if it now overlaps with the banner. Simplest: add top padding to journeySummaryHeader so it sits below the banner when the banner is present. This can be done via a conditional padding modifier tied to `currentTurning != nil`.

- [ ] **Step 4: Build and manually verify**

Run:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

Since today is not likely a turning day, the banner won't render in the simulator without a date stub. Defer visual verification to Task 16 (full QA).

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Scenes/Home/InkScrollView.swift
git commit -m "feat(turnings): add home-scroll banner on solstice and equinox days"
```

---

## Task 8: InkScrollView+TurningMarkers

**Files:**
- Create: `Pilgrim/Scenes/Home/InkScrollView+TurningMarkers.swift`
- Modify: `Pilgrim/Scenes/Home/InkScrollView.swift` — call the new marker function from `scrollContent`

Mirrors the pattern of `InkScrollView+LunarMarkers.swift`. Renders a small faint kanji glyph at the position of each walk that fell on a turning day.

- [ ] **Step 1: Read the lunar-markers pattern**

Run:
```bash
cat Pilgrim/Scenes/Home/InkScrollView+LunarMarkers.swift
```

Note: the lunar markers function takes `positions: [CalligraphyPathRenderer.DotPosition]` and renders small circles at those positions.

- [ ] **Step 2: Create the turning markers extension**

Create `Pilgrim/Scenes/Home/InkScrollView+TurningMarkers.swift`:

```swift
import SwiftUI
import CoreLocation

extension InkScrollView {

    /// Renders an inline kanji glyph at the position of each turning-day
    /// walk in the user's history. Uses the walk's own starting coordinate
    /// to determine hemisphere (so past walks keep their classification
    /// even if the user has since moved hemispheres).
    func turningMarkers(positions: [CalligraphyPathRenderer.DotPosition]) -> some View {
        let markers = computeTurningMarkers(positions: positions)
        return ForEach(markers, id: \.id) { marker in
            Text(marker.kanji)
                .font(Constants.Typography.caption)
                .foregroundColor(marker.color.opacity(0.55))
                .position(x: marker.x, y: marker.y - 14)  // above the walk dot
                .accessibilityHidden(true)
        }
    }

    struct TurningMarker: Identifiable {
        let id: UUID
        let x: CGFloat
        let y: CGFloat
        let kanji: String
        let color: Color
    }

    private func computeTurningMarkers(positions: [CalligraphyPathRenderer.DotPosition]) -> [TurningMarker] {
        guard positions.count == snapshots.count else { return [] }
        var markers: [TurningMarker] = []
        for (snapshot, position) in zip(snapshots, positions) {
            let coord = snapshot.routeData.first.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
            guard let turning = TurningDayService.turning(for: snapshot.startDate, at: coord),
                  let kanji = turning.kanji,
                  let color = turning.color else {
                continue
            }
            markers.append(TurningMarker(
                id: snapshot.id,
                x: position.center.x,
                y: position.center.y,
                kanji: kanji,
                color: color
            ))
        }
        return markers
    }
}
```

- [ ] **Step 3: Call the new function from InkScrollView's scrollContent**

In `InkScrollView.swift`'s `scrollContent(width:height:)`, find the spot where `lunarMarkers(positions:viewportWidth:)` is called (search for "lunarMarkers"). Add a sibling call to `turningMarkers(positions:)` immediately after or before it:

```swift
turningMarkers(positions: positions)
lunarMarkers(positions: positions, viewportWidth: width)
```

- [ ] **Step 4: Register new file in Xcode project**

Check: `grep -c "InkScrollView+TurningMarkers.swift" Pilgrim.xcodeproj/project.pbxproj`. Expected `>= 2`. Add to Pilgrim target if not.

- [ ] **Step 5: Build**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. Visual verification deferred to Task 16.

- [ ] **Step 6: Commit**

```bash
git add Pilgrim/Scenes/Home/InkScrollView+TurningMarkers.swift Pilgrim/Scenes/Home/InkScrollView.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(turnings): render inline kanji at turning-day walk positions"
```

---

## Task 9: InkScrollView pathSegmentColor turning override

**Files:**
- Modify: `Pilgrim/Scenes/Home/InkScrollView.swift`

The existing `pathSegmentColor(index:)` picks colors by index. For turning-day walks, we need to override the color. Simplest path: pre-compute a lookup map in `scrollContent(width:height:)` where `snapshots` is accessible, then reference the map inside `pathSegmentColor`.

- [ ] **Step 1: Add a stored-property-equivalent computed helper**

In `InkScrollView.swift`, add a new private method that maps indices to turning colors:

```swift
/// Returns the turning-day color override for the walk at the given index,
/// or nil if that walk was not a turning-day walk. Uses the walk's own
/// starting coordinate for hemisphere classification.
private func turningColorForSegment(index: Int) -> Color? {
    guard index >= 0 && index < snapshots.count else { return nil }
    let snapshot = snapshots[index]
    let coord = snapshot.routeData.first.map {
        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
    }
    guard let turning = TurningDayService.turning(for: snapshot.startDate, at: coord) else {
        return nil
    }
    return turning.color
}
```

- [ ] **Step 2: Apply the override inside pathSegmentColor**

Find the existing `pathSegmentColor(index:)` function. Modify to prefer the turning override:

```swift
private func pathSegmentColor(index: Int) -> Color {
    if let turningColor = turningColorForSegment(index: index) {
        return turningColor.opacity(0.85)  // softened so it blends with scroll palette
    }
    // … existing color-selection logic unchanged
}
```

Keep the rest of the original `pathSegmentColor` body intact — the override is a pre-check only.

- [ ] **Step 3: Build**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Pilgrim/Scenes/Home/InkScrollView.swift
git commit -m "feat(turnings): override ink-scroll segment color for turning-day walks"
```

---

## Task 10: ActiveWalkView kanji watermark overlay

**Files:**
- Modify: `Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift`

- [ ] **Step 1: Locate where the map is rendered**

Find the main `body` of `ActiveWalkView`. Look for the Mapbox or map container (probably `PilgrimMapView` inside a `ZStack`). The watermark should sit as an overlay on the map, centered horizontally, positioned above the collapsed stats-sheet peek.

Run:
```bash
grep -n "PilgrimMapView\|statsSheet\|bottomSheet\|ZStack" Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift | head -20
```

- [ ] **Step 2: Add a turning computed property to the view**

Add near existing state variables:

```swift
/// Turning for today if this walk started on a turning day (determined from
/// the walk's first recorded location sample). Nil on non-turning days.
private var activeTurning: SeasonalMarker? {
    let firstSample = viewModel.routeData.first
    let coord = firstSample.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    return TurningDayService.turning(for: viewModel.walkStartDate ?? Date(), at: coord)
}
```

Adjust `viewModel.routeData` and `viewModel.walkStartDate` to the actual property names on `ActiveWalkViewModel`. Inspect that file if unsure.

- [ ] **Step 3: Add the watermark overlay**

Inside the ZStack that contains the map, add an overlay that renders only when `activeTurning != nil`. Position it near the bottom-center, above where the collapsed stats sheet would be.

Example (exact placement depends on existing layout):

```swift
.overlay(alignment: .bottom) {
    if let turning = activeTurning, let kanji = turning.kanji {
        Text(kanji)
            .font(.system(size: 18, weight: .light))
            .foregroundColor(.stone.opacity(0.18))
            .padding(.bottom, 140)  // above the stats sheet peek; tune to existing sheet height
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
```

The exact `.bottom` padding depends on the stats sheet's current collapsed height. If the app has a PreferenceKey-based measured height for the sheet, bind the padding to that; otherwise a hardcoded 140pt is an acceptable starting point and can be tuned visually.

- [ ] **Step 4: Build**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift
git commit -m "feat(turnings): add kanji watermark overlay to active walk map"
```

---

## Task 11: PilgrimMapView route color turning override

**Files:**
- Modify: `Pilgrim/Views/PilgrimMapView.swift`

Update the Mapbox route layer's color match expression. The existing match maps `activityType` to `moss` / `dawn` / `rust`. On turning days, the default (walking) color becomes the turning's color. Meditation (`dawn`) and talking (`rust`) are unchanged.

- [ ] **Step 1: Read current expression**

```bash
sed -n '270,290p' Pilgrim/Views/PilgrimMapView.swift
```

Confirm the existing match expression structure around line 273–281.

- [ ] **Step 2: Thread the walking color into the map view**

`PilgrimMapView` needs to know which walking color to use. The simplest approach: add a new stored property `walkingColor: UIColor` (defaulting to `UIColor.moss`) and replace the hardcoded `UIColor.moss` in the default match branch with the property.

At the top of `PilgrimMapView` struct (or wherever stored properties live):

```swift
/// Color used for the walking-activity segments of the route. Callers override
/// to `SeasonalMarker.turningColor` on turning-day walks; default is `.moss`.
let walkingColor: UIColor
```

Update the initializer (if `PilgrimMapView` has an explicit init) to accept and default this parameter:

```swift
init(
    // ... existing params ...
    walkingColor: UIColor = .moss
) {
    // ... existing assignments ...
    self.walkingColor = walkingColor
}
```

If the struct uses synthesized memberwise init, add the property with a default (which preserves source-compat):

```swift
var walkingColor: UIColor = .moss
```

- [ ] **Step 3: Update the match expression**

Around line 273–281, replace:

```swift
layer.lineColor = .expression(
    Exp(.match) {
        Exp(.get) { "activityType" }
        "meditating"
        UIColor.dawn
        "talking"
        UIColor.rust
        UIColor.moss
    }
)
```

With:

```swift
layer.lineColor = .expression(
    Exp(.match) {
        Exp(.get) { "activityType" }
        "meditating"
        UIColor.dawn
        "talking"
        UIColor.rust
        walkingColor
    }
)
```

- [ ] **Step 4: Propagate walkingColor from ActiveWalkView**

In `Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift`, find where `PilgrimMapView(...)` is instantiated. Pass the walking color derived from `activeTurning`:

```swift
PilgrimMapView(
    // ... existing args ...
    walkingColor: activeTurning?.uiColor ?? UIColor.moss
)
```

- [ ] **Step 5: Propagate walkingColor from WalkSummaryView**

In `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift`, find where `PilgrimMapView(...)` is instantiated. Compute the turning from the walk's own starting coordinate:

```swift
private var walkTurning: SeasonalMarker? {
    let coord = walk.routeData.first.map {
        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
    }
    return TurningDayService.turning(for: walk.startDate, at: coord)
}
```

And pass to the map view:

```swift
PilgrimMapView(
    // ... existing args ...
    walkingColor: walkTurning?.uiColor ?? UIColor.moss
)
```

- [ ] **Step 6: Build**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Pilgrim/Views/PilgrimMapView.swift Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift
git commit -m "feat(turnings): route walking-segments in turning color on turning days"
```

---

## Task 12: Sunrise-azimuth ray overlay on active walk

**Files:**
- Modify: `Pilgrim/Views/PilgrimMapView.swift` (adds a LineAnnotation for the ray)
- Modify: `Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift` (passes the azimuth in)

Mapbox has a `PolylineAnnotation` / `LineAnnotation` API that can render a line from a starting coordinate at a given bearing. The ray starts at the user's location puck and extends ~150pt in the direction of today's sunrise.

- [ ] **Step 1: Add a sunriseRay property to PilgrimMapView**

In `Pilgrim/Views/PilgrimMapView.swift`, add:

```swift
/// Optional sunrise-azimuth ray to render from the user's location on
/// turning days. Nil means no ray (non-turning day, or polar latitude).
let sunriseRay: SunriseRay?

struct SunriseRay {
    /// Compass direction (degrees from true north) of sunrise.
    let azimuth: CLLocationDirection
    /// Color of the ray (matches the turning's walking color).
    let color: UIColor
}
```

Default to nil in the initializer / memberwise init.

- [ ] **Step 2: Render the ray as a LineAnnotation**

In `PilgrimMapView`'s map configuration (near where the route layer is added), add logic that creates a polyline annotation when `sunriseRay != nil`. The ray uses a short geographic distance (~1km) so it's visible at typical zoom levels:

```swift
private func updateSunriseRay(on mapView: MBMapView, userLocation: CLLocationCoordinate2D?) {
    // Remove any existing ray annotation manager
    if let manager = coordinator.sunriseRayManager {
        mapView.annotations.removeAnnotationManager(withId: manager.id)
        coordinator.sunriseRayManager = nil
    }
    guard let ray = sunriseRay, let origin = userLocation else { return }

    let endpoint = coordinate(from: origin, bearingDegrees: ray.azimuth, distanceMeters: 1000)
    let manager = mapView.annotations.makePolylineAnnotationManager(id: "sunrise-ray")
    var annotation = PolylineAnnotation(lineCoordinates: [origin, endpoint])
    annotation.lineColor = StyleColor(ray.color.withAlphaComponent(0.15))
    annotation.lineWidth = 2
    manager.annotations = [annotation]
    coordinator.sunriseRayManager = manager
}

/// Compute a coordinate `distanceMeters` along the bearing `bearingDegrees`
/// from the origin. Great-circle approximation.
private func coordinate(
    from origin: CLLocationCoordinate2D,
    bearingDegrees: CLLocationDirection,
    distanceMeters: Double
) -> CLLocationCoordinate2D {
    let earthRadius = 6_371_000.0
    let bearingRad = bearingDegrees * .pi / 180.0
    let lat1 = origin.latitude * .pi / 180.0
    let lon1 = origin.longitude * .pi / 180.0
    let angular = distanceMeters / earthRadius

    let lat2 = asin(
        sin(lat1) * cos(angular) +
        cos(lat1) * sin(angular) * cos(bearingRad)
    )
    let lon2 = lon1 + atan2(
        sin(bearingRad) * sin(angular) * cos(lat1),
        cos(angular) - sin(lat1) * sin(lat2)
    )
    return CLLocationCoordinate2D(
        latitude: lat2 * 180.0 / .pi,
        longitude: lon2 * 180.0 / .pi
    )
}
```

Add a `sunriseRayManager: PolylineAnnotationManager?` property to the `Coordinator` class so the annotation can be removed later. Call `updateSunriseRay(on:userLocation:)` whenever the user's location or `sunriseRay` changes (location update path, or `updateUIView` if state-driven).

- [ ] **Step 3: Compute the ray in ActiveWalkView**

In `Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift`, add:

```swift
/// Sunrise azimuth ray for today's turning, if any. Computed once from
/// the walk's first location sample.
private var sunriseRay: PilgrimMapView.SunriseRay? {
    guard let turning = activeTurning,
          let color = turning.uiColor,
          let firstSample = viewModel.routeData.first else {
        return nil
    }
    let coord = CLLocationCoordinate2D(latitude: firstSample.latitude, longitude: firstSample.longitude)
    guard let azimuth = CelestialCalculator.sunriseAzimuth(
        at: coord,
        on: viewModel.walkStartDate ?? Date()
    ) else {
        return nil
    }
    return PilgrimMapView.SunriseRay(azimuth: azimuth, color: color)
}
```

Adjust property names (`routeData`, `walkStartDate`) to match the actual `ActiveWalkViewModel` API. Pass `sunriseRay: sunriseRay` to the `PilgrimMapView` initializer.

- [ ] **Step 4: Build**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. If Mapbox API names differ (e.g., `PolylineAnnotation` is named `LineAnnotation` in your version), adjust accordingly.

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Views/PilgrimMapView.swift Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift
git commit -m "feat(turnings): draw sunrise-azimuth ray on active walk map"
```

---

## Task 13: Walk summary date title kanji suffix

**Files:**
- Modify: `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift`

- [ ] **Step 1: Locate the date title**

Run:
```bash
grep -n "dateTitleFormatted\|dateTitle\b" Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift
```

- [ ] **Step 2: Extend dateTitle to append kanji**

Find the existing `dateTitle` or `dateTitleFormatted` computed property. Update it to append the kanji when applicable:

```swift
private var dateTitle: String {
    let base = Self.dateTitleFormatter.string(from: walk.startDate)
    if let kanji = walkTurning?.kanji {
        return "\(base) · \(kanji)"
    }
    return base
}
```

`walkTurning` is already defined from Task 11's changes. If it's not yet in this file (because Task 11 didn't touch this property), add it:

```swift
private var walkTurning: SeasonalMarker? {
    let coord = walk.routeData.first.map {
        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
    }
    return TurningDayService.turning(for: walk.startDate, at: coord)
}
```

- [ ] **Step 3: Apply turning color to the kanji portion (optional polish)**

If the date title is rendered as a single `Text`, the kanji inherits the title's color. For the turning color to come through on just the kanji, split the title into two Text views joined with `+`:

```swift
private var dateTitleView: some View {
    let base = Self.dateTitleFormatter.string(from: walk.startDate)
    if let kanji = walkTurning?.kanji, let color = walkTurning?.color {
        return Text(base)
            .foregroundColor(.ink)
            + Text(" · ")
            .foregroundColor(.fog.opacity(0.5))
            + Text(kanji)
            .foregroundColor(color)
    }
    return Text(base).foregroundColor(.ink)
}
```

Replace the existing `Text(dateTitle)` call site with `dateTitleView`. If that's more invasive than warranted, leave the single-string version and move this as a follow-up.

- [ ] **Step 4: Build**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift
git commit -m "feat(turnings): append kanji suffix to walk summary date title"
```

---

## Task 14: Forward-compatible turningDay share-payload field

**Files:**
- Modify: `Pilgrim/Scenes/WalkShare/WalkShareViewModel.swift`
- Modify: `Pilgrim/Models/ShareService.swift` (or wherever the share payload struct lives)

The iOS app populates a new optional field on the share payload. The `pilgrim-worker` consumes it later in a follow-up PR; until then, the worker ignores unknown fields.

- [ ] **Step 1: Find the share payload struct**

Run:
```bash
grep -n "struct.*Payload\|func buildPayload\|struct.*Share" Pilgrim/Scenes/WalkShare/WalkShareViewModel.swift Pilgrim/Models/ShareService.swift | head -10
```

Identify where the Codable payload is declared and where `buildPayload(...)` assembles it.

- [ ] **Step 2: Add a turningDay field to the payload struct**

In the struct declaration, add an optional string field:

```swift
/// Nil for non-turning-day walks. Values: "winter-solstice",
/// "summer-solstice", "spring-equinox", "autumn-equinox". Used by the
/// pilgrim-worker HTML renderer to style the hosted page with the
/// matching color palette and kanji mark.
var turningDay: String?
```

- [ ] **Step 3: Populate it in buildPayload**

Find the `buildPayload(placeStart:placeEnd:)` method in `WalkShareViewModel.swift` (or wherever the payload is assembled). Add:

```swift
let coord = walk.routeData.first.map {
    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
}
let turningDay = TurningDayService.turning(for: walk.startDate, at: coord).flatMap { marker -> String? in
    switch marker {
    case .winterSolstice: return "winter-solstice"
    case .summerSolstice: return "summer-solstice"
    case .springEquinox:  return "spring-equinox"
    case .autumnEquinox:  return "autumn-equinox"
    case .imbolc, .beltane, .lughnasadh, .samhain: return nil
    }
}
```

Include `turningDay` when constructing the payload.

- [ ] **Step 4: Build**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Scenes/WalkShare/WalkShareViewModel.swift Pilgrim/Models/ShareService.swift
git commit -m "feat(turnings): add turningDay to share payload (forward-compatible)"
```

---

## Task 15: Full test suite + manual QA sweep

- [ ] **Step 1: Run the full unit test suite**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests 2>&1 | grep -E "Executed [0-9]+ tests|TEST SUCCEEDED|TEST FAILED" | tail -3
```

Expected: `** TEST SUCCEEDED **`. Count should be the pre-feature total + new tests from Tasks 1, 3, 4, 5, 6 (roughly 40 new tests).

- [ ] **Step 2: Date stub for manual verification**

To exercise the UI on a non-turning day, introduce a temporary date stub. Add a launch argument check in `PilgrimApp.swift` (DEBUG only) that overrides `Date()` to a turning date:

```swift
#if DEBUG
if CommandLine.arguments.contains("--stub-date-winter-solstice") {
    // Override Date() globally or via a test-only TimeProvider singleton
    // Pattern specific to how the project handles time — may require
    // introducing a `DateProvider` if one doesn't already exist.
}
#endif
```

If introducing a DateProvider is too invasive, temporarily hardcode the date in `TurningDayService.turning(for:at:)` for manual testing (revert before commit):

```swift
let testDate = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2024, month: 12, day: 21))!
let snapshot = CelestialCalculator.snapshot(for: testDate)  // was: date parameter
```

Remove the stub before committing.

- [ ] **Step 3: Manual QA checklist (on simulator or device)**

With the date stubbed to a turning day, verify each surface:

1. **Home (InkScrollView)**: banner appears at the top of the scroll (*"Today the sun stands still · 冬至"* or equivalent); if there's at least one past turning-day walk, its dot has an inline kanji glyph above it.
2. **New user (zero walks)**: banner still appears. The scroll may be empty otherwise; confirm banner isn't hidden by the `!snapshots.isEmpty` gate.
3. **Active walk**: start a walk (or demo mode). Verify kanji watermark at bottom-center of the map above the stats sheet. Verify walking-route segments render in the turning color (use demo mode with walking-only data if meditation/talk confuses the color check).
4. **Sunrise ray**: visible on the active walk map, starting at the user's puck, extending in a compass direction matching today's sunrise.
5. **Walk summary**: after finishing a turning-day walk, the date title in the summary reads *"December 21, 2024 · 冬至"*; the route in the summary map uses the turning color for walking segments.
6. **Goshuin seal**: after a turning-day walk, the generated seal (SealReveal animation and GoshuinView collection entry) uses the turning color regardless of the walk's favicon.
7. **Non-turning day (remove stub)**: all of the above are absent. Regression confirmed.
8. **Dark mode**: switch appearance, verify all 4 turning colors render legibly against dark parchment with no halo/inversion issues.
9. **Hemisphere flip**: stub the hemisphere by creating a walk with `latitude = -33.9`. On the December solstice stub, the UI should show 夏至 (summer solstice) and the gold color — not the winter blue.
10. **VoiceOver**: enable and navigate the home screen. Banner should be readable ("Today, day equals night. Spring Equinox."). Margin glyphs silent (accessibility hidden). Walk summary date reads with the English label instead of raw kanji.
11. **Polar sunrise ray**: stub the user's location to latitude 78° on winter solstice. Ray should NOT render. No crash.
12. **Walk crossing midnight**: start a walk at 23:55 on a turning day (stub the system clock). Verify the walk is classified as turning-day (date-based on start).

- [ ] **Step 4: Remove all stubs and verify clean build**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **` + `** TEST SUCCEEDED **`.

- [ ] **Step 5: No commit required unless stubs or fixes were made during QA**

If QA revealed issues that were fixed, commit those fixes with appropriate messages.

---

## Task 16: Final review + push

- [ ] **Step 1: Diff review**

```bash
git log main..HEAD --oneline
git diff main..HEAD --stat
```

Expected: ~14 commits, 5+ new files + several modified files. Confirm nothing unexpected.

- [ ] **Step 2: Stale debug-print scan**

```bash
git diff main..HEAD -- '*.swift' | grep -E '^\+.*print\('
```

Expected: no output.

- [ ] **Step 3: Full build + test one more time**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **` + `** TEST SUCCEEDED **`.

- [ ] **Step 4: Push the feature branch**

```bash
git push -u origin HEAD
```

Return the PR-creation URL printed by the remote so the user can open a pull request.

---

## Notes for the engineer

- **Follow the `96ae8e4` pbxproj pattern** for every new .swift file you add. `Pilgrim/` and `UnitTests/` are NOT synchronized root groups in this project, so manual `project.pbxproj` edits are required. Look at that commit for a worked example.
- **The Mapbox API in this project** uses Mapbox Maps SDK for iOS. Exact symbol names may shift between minor versions — if `PolylineAnnotation` or `StyleColor` don't exist under those names in your version, check the Pods directory for the current API and adapt Task 12 accordingly.
- **Don't over-engineer the date stub** in Task 15. If introducing a `DateProvider` would ripple through the codebase, prefer temporary hardcoded test dates that you revert. The stub is only for manual verification; production code reads real `Date()`.
- **The spec specifies the exact hex values** for all 4 colors, but final tuning should be done against the rendered parchment on a real device before v1 ships. If the colors look off in testing, adjust the .colorset JSON and recommit.
- **`pilgrim-worker` follow-up** is out of scope for this iOS plan. Once the iOS PR merges, the worker can consume the new `turningDay` payload field and render matching colors on the hosted share page. That's a separate PR on the separate repo.
