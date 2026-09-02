# Honor Mode, Slice One: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Honor walking mode: follow a Way (your own past walk, or a shared walk) with a ghost line, a companion dot, their voices and photos at the places they happened, and an honest arrival.

**Architecture:** One value type, `Way`, is the only thing the engine knows. `OwnWalkWayBuilder` (Phase A) and `WayImporter` (Phase B) produce it. `HonorEngine` consumes the existing location and activity publishers exactly like `SeekEngine`, persists nothing, and emits events the view model turns into audio, cards, haptics, and walk events. Persistence is Seek-shaped: two new `WalkEvent` types plus a reserved waypoint icon, and a `Ways/` folder under Application Support keyed by walk UUID. Zero CoreStore migration.

**Tech Stack:** Swift 5.10 / SwiftUI / Combine / CoreStore / MapboxMaps 11.20 (SPM) / XCTest. Spec: `docs/superpowers/specs/2026-09-01-honor-mode-design.md`.

## Global Constraints

- Typography: always `Constants.Typography.*`; never `.system()`.
- Fixed hex colors on the map (adaptive `.fog`/`.ink` invert in dark mode); SwiftUI views use the palette (`.stone`, `.ink`, `.fog`, `.parchment`, `.moss`).
- Every timer, player, and Combine subscription owned by the engine or view model has a cancellation path in `stop()`; `[weak self]` in every sink.
- `AVAudioPlayer`: one per role; `coordinator.deactivate(consumer:)` in every completion and error path.
- No CoreStore schema change. `.honorMode` rawValue 5, `.honorArrival` rawValue 6. Reserved waypoint icon `"signpost.right.fill"`.
- New Swift files are NOT auto-registered: `Pilgrim/` and `UnitTests/` are plain groups. Every task that creates a file runs `ruby scripts/xcode-add.rb <target> <path>` (Task 1) and commits `Pilgrim.xcodeproj/project.pbxproj`.
- Build: `xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build`. Test one class: `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/<ClassName>`.
- SwiftLint: `type_body_length` errors at 750 lines; extract subviews before a struct nears 700. Run `swiftlint` on the repo before pushing.
- Every commit compiles and passes the tests it touches. Branch: `feat/honor-mode` off `main`. Everything ships through a PR; never commit to `main`.
- Phase B (Tasks 17 to 22) depends on the worker contract in the spec (host `honor.pilgrimapp.org`, `lat`/`lon` and `duration` on tour.json). The worker plan lives in `pilgrim-worker` and deploys first. Phase A ships without it.

## File map

Phase A, new:
- `scripts/xcode-add.rb` — register a file with an Xcode target.
- `Pilgrim/Models/Honor/Way.swift` — `Way`, `WayPoint`, `WayCoordinate`, `WayMoment`, `WayMomentKind`, `WayMedia`, `WaySource`, `WayWeather`, `VoiceKind`.
- `Pilgrim/Models/Honor/WayGeometry.swift` — cumulative distances, frac math, windowed nearest point.
- `Pilgrim/Models/Honor/OwnWalkWayBuilder.swift` — `Way` from a `WalkInterface`.
- `Pilgrim/Models/Honor/HonorPersistence.swift` — reserved icon, labels, event names.
- `Pilgrim/Models/Honor/HonorTuning.swift` — every threshold in one place.
- `Pilgrim/Models/Honor/HonorEngine.swift` — the session engine.
- `Pilgrim/Models/Honor/WayVoicePlayer.swift` — voice playback modeled on `AudioPriorityQueue`.
- `Pilgrim/Models/Honor/WayStore.swift` — `Ways/` folder, index, replies, sweep.
- `Pilgrim/Models/Honor/WayGPXExporter.swift` — DEBUG simulation export.
- `Pilgrim/Models/Walk/Seek/ArrivalDebounce.swift` — extracted from `SeekEngine`.
- `Pilgrim/Views/PilgrimMapView+HonorWay.swift` — ghost line + companion layers.
- `Pilgrim/Views/Scenery/StaffsShape.swift` — two staffs leaning together.
- `Pilgrim/Scenes/ActiveWalk/ActiveWalkViewModel+Honor.swift` — engine lifecycle, persistence, cards.
- `Pilgrim/Scenes/ActiveWalk/WayPlaceCard.swift` — the sheet card (photo / voice / rest / sitting).
- `Pilgrim/Scenes/Honor/HonorWaysSheet.swift` — "Choose a way": own walks, accepted shares, paste.
- `Pilgrim/Scenes/Honor/HonorOverviewView.swift` — map fit to the Way, card, Begin.
- `Pilgrim/Scenes/WalkSummary/HonorSummarySection.swift`.
- `UnitTests/Honor/*Tests.swift` — one file per unit.

Phase A, modified: `WalkMode.swift`, `WalkStartView.swift`, `Localizable.strings` (Base + en), `WalkEvent.swift`, `PilgrimPackageConverter.swift`, `SeekEngine.swift`, `AudioPriorityQueue.swift`, `PilgrimAnnotation.swift`, `PilgrimMapView.swift`, `ActiveWalkViewModel.swift`, `ActiveWalkView.swift`, `WalkStatsSheet.swift`, `MainCoordinatorView.swift`, `MainTabView.swift`, `HomeView.swift`, `WalkSummaryView.swift`, `HomeViewModel.swift`, `InkScrollView.swift`, `WalkModeFootprints.swift`, `SceneryGenerator.swift`, `GoshuinMilestones.swift`, `SealInput.swift`, `SealGenerator.swift`, `SealRenderer.swift`, `ActivityContext.swift`, `PromptAssembler.swift`, `HapticManager.swift`, `UserPreferences.swift`, `ScreenshotDataSeeder.swift`, `WalkActivityAttributes.swift`, `WalkActivityManager.swift`, `PilgrimWidgetLiveActivity.swift`.

Phase B, new: `Pilgrim/Models/Honor/TourManifest.swift`, `WayImporter.swift`, `WayMediaDownloader.swift`, `HonorLink.swift`, `Pilgrim/Scenes/Settings/WaysListView.swift`. Modified: `Pilgrim.entitlements`, `PilgrimApp.swift`, `AppDelegate.swift`, `SharePayload.swift`, `TourBuilder.swift`, `WalkShareViewModel.swift`, `DataCard.swift`.

---

## Phase A: the engine on your own walks

### Task 1: Xcode registration script

**Files:**
- Create: `scripts/xcode-add.rb`

**Interfaces:**
- Produces: `ruby scripts/xcode-add.rb <target> <repo-relative-path>` registers a `.swift` file with the target's sources build phase, creating intermediate groups that mirror the path. Idempotent.

- [ ] **Step 1: Write the script**

```ruby
#!/usr/bin/env ruby
# Registers a source file with an Xcode target. The Pilgrim and UnitTests
# groups are plain PBXGroups (not synchronized folders), so a file on disk
# is invisible to the build until it has a file reference and a sources
# build-phase entry. Groups are created to mirror the on-disk path.
require "xcodeproj"

target_name, rel_path = ARGV
abort "usage: xcode-add.rb <target> <path/from/repo/root.swift>" unless target_name && rel_path

project = Xcodeproj::Project.open("Pilgrim.xcodeproj")
target = project.targets.find { |t| t.name == target_name } or abort "target #{target_name} not found"

parts = rel_path.split("/")
filename = parts.pop
group = project.main_group
parts.each do |part|
  child = group.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && (c.path == part || c.name == part) }
  child ||= group.new_group(part, part)
  group = child
end

file_ref = group.files.find { |f| f.path == filename }
file_ref ||= group.new_file(filename)

phase = target.source_build_phase
unless phase.files_references.include?(file_ref)
  phase.add_file_reference(file_ref)
  puts "added #{rel_path} to #{target_name}"
end
project.save
```

- [ ] **Step 2: Verify on a scratch file**

```bash
mkdir -p Pilgrim/Models/Honor && printf 'enum HonorScratch {}\n' > Pilgrim/Models/Honor/HonorScratch.swift
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Models/Honor/HonorScratch.swift
grep -c HonorScratch.swift Pilgrim.xcodeproj/project.pbxproj
```
Expected: `added ...` then a count of at least 3 (file ref, build file, group child). Run the script a second time: no output, count unchanged.

- [ ] **Step 3: Build, then remove the scratch file and its references**

```bash
xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -3
git checkout Pilgrim.xcodeproj/project.pbxproj && rm Pilgrim/Models/Honor/HonorScratch.swift
```
Expected: `** BUILD SUCCEEDED **` before the revert.

- [ ] **Step 4: Commit**

```bash
git add scripts/xcode-add.rb
git commit -m "chore: script to register source files with an Xcode target"
```

---

### Task 2: Honor replaces Together in `WalkMode`

**Files:**
- Modify: `Pilgrim/Models/Walk/WalkMode.swift`
- Modify: `Pilgrim/Scenes/Home/WalkStartView.swift:125-137`, `:227-241`, `:257-323` (together footprints), `:410-436`, and the `together*` state at `:24-25`, `:78-79`
- Modify: `Pilgrim/Support Files/Base.lproj/Localizable.strings:165-167`, `Pilgrim/Support Files/en.lproj/Localizable.strings` (same keys)
- Test: `UnitTests/Honor/WalkModeTests.swift`

**Interfaces:**
- Produces: `WalkMode.honor` (rawValue `"honor"`), `subtitle == "walk in their steps"`, `buttonLabel == "Choose a way"`, `isAvailable == true`. `WalkMode.together` no longer exists.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Pilgrim

final class WalkModeTests: XCTestCase {

    func testHonorIsTheThirdMode() {
        XCTAssertEqual(WalkMode.allCases, [.wander, .honor, .seek])
        XCTAssertTrue(WalkMode.honor.isAvailable)
        XCTAssertEqual(WalkMode.honor.subtitle, "walk in their steps")
        XCTAssertEqual(WalkMode.honor.buttonLabel, "Choose a way")
    }

    func testHonorQuotesAreLocalized() {
        XCTAssertEqual(WalkMode.honor.quotes.count, 3)
        XCTAssertFalse(WalkMode.honor.quotes.contains(""))
        XCTAssertFalse(WalkMode.honor.quotes.contains { $0.hasPrefix("Honor.Quote") })
    }
}
```

- [ ] **Step 2: Register and run to verify it fails**

```bash
mkdir -p UnitTests/Honor
ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/WalkModeTests.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/WalkModeTests 2>&1 | grep -E "error:|Executed"
```
Expected: compile error `type 'WalkMode' has no member 'honor'`.

- [ ] **Step 3: Replace the enum**

`Pilgrim/Models/Walk/WalkMode.swift`, whole file:

```swift
import Foundation

enum WalkMode: String, CaseIterable {
    case wander, honor, seek

    var subtitle: String {
        switch self {
        case .wander: return "walk · talk · meditate"
        case .honor: return "walk in their steps"
        case .seek: return "follow the unknown"
        }
    }

    var buttonLabel: String {
        switch self {
        case .wander: return "Wander"
        case .honor: return "Choose a way"
        case .seek: return "Seek"
        }
    }

    var isAvailable: Bool { true }

    var quotes: [String] {
        switch self {
        case .wander: return (1...6).map { LS["Welcome.Quote.\($0)"] }
        case .honor: return (1...3).map { LS["Honor.Quote.\($0)"] }
        case .seek: return (1...3).map { LS["Seek.Quote.\($0)"] }
        }
    }
}
```

- [ ] **Step 4: Replace the quote strings in both `.lproj` files**

Replace the three `Together.Quote.N` lines with (the user may swap the copy later; the keys stay):

```
"Honor.Quote.1" = "Where they walked,\nyou walk";
"Honor.Quote.2" = "Two traveling together";
"Honor.Quote.3" = "Their steps\nare still warm";
```

- [ ] **Step 5: Update `WalkStartView`**

In `modeAtmosphere` replace `case .together: Color.dawn.opacity(0.01)` with `case .honor: Color.stone.opacity(0.015)`. In `footprintForMode` replace `case .together: togetherFootprints` with `case .honor: honorFootprints`. In `trailUnderline` replace the `.together` gradient case label with `.honor`, keeping its centered gradient. Delete `togetherDriftOffset` and `togetherCompanionsVisible` (`:24-25`, `:78-79`) and every use of them inside the old `togetherFootprints`. Replace the whole `togetherFootprints` view with:

```swift
    /// One print and a staff beside it: dōgyō ninin, two traveling together.
    private var honorFootprints: some View {
        HStack(alignment: .bottom, spacing: 4) {
            FootprintShape()
                .fill(Color.ink.opacity(0.08))
                .frame(width: 16, height: 26)
                .scaleEffect(x: -1)
                .rotationEffect(.degrees(-12))
            StaffGlyph()
                .stroke(Color.ink.opacity(0.10), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 10, height: 34)
        }
    }
```

Add at the bottom of `WalkStartView.swift`:

```swift
/// A walking staff: one leaning stroke with a short crossbar near the top.
struct StaffGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.65, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.maxY))
        let barY = rect.minY + rect.height * 0.18
        path.move(to: CGPoint(x: rect.minX, y: barY + 2))
        path.addLine(to: CGPoint(x: rect.maxX, y: barY - 2))
        return path
    }
}
```

The `Begin` button already reads `selectedMode.buttonLabel`; Task 13 routes Honor's tap to the Ways sheet.

- [ ] **Step 6: Build, run the test**

```bash
xcodebuild build -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator 2>&1 | grep -E "error:|BUILD"
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/WalkModeTests 2>&1 | grep -E "error:|Executed"
```
Expected: `BUILD SUCCEEDED`; `Executed 2 tests, with 0 failures`. If any other file switched over `.together`, the compiler names it; fix it the same way.

- [ ] **Step 7: Commit**

```bash
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(honor): Honor takes Together's slot on the path screen"
```

---

### Task 3: Persistence vocabulary: events, reserved icon, `.pilgrim` mapping

**Files:**
- Create: `Pilgrim/Models/Honor/HonorPersistence.swift`
- Modify: `Pilgrim/Models/Data/DataModels/WalkEvent.swift:30-98`
- Modify: `Pilgrim/Models/Data/PilgrimPackage/PilgrimPackageConverter.swift:493-513`
- Test: `UnitTests/Honor/HonorPersistenceTests.swift`

**Interfaces:**
- Produces: `WalkEvent.EventType.honorMode` (5), `.honorArrival` (6); `HonorPersistence.arrivalWaypointIcon == "signpost.right.fill"`, `HonorPersistence.isArrivalWaypoint(_:)`, `HonorPersistence.arrivalWaypointLabel(wayTitle:)`, `HonorPersistence.honorModeEventName`, `honorArrivalEventName`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Pilgrim

final class HonorPersistenceTests: XCTestCase {

    func testEventRawValuesRoundTrip() {
        XCTAssertEqual(WalkEvent.EventType(rawValue: 5), .honorMode)
        XCTAssertEqual(WalkEvent.EventType(rawValue: 6), .honorArrival)
        XCTAssertEqual(WalkEvent.EventType.honorMode.rawValue, 5)
        XCTAssertEqual(WalkEvent.EventType.honorArrival.rawValue, 6)
        XCTAssertEqual(WalkEvent.EventType(rawValue: 99), .unknown)
    }

    func testReservedIconIsDisjointFromUserIcons() {
        let userIcons = WaypointChip.presets.map(\.icon) + ["mappin", SeekPersistence.arrivalWaypointIcon]
        XCTAssertFalse(userIcons.contains(HonorPersistence.arrivalWaypointIcon))
        let waypoint = TempWaypoint(uuid: nil, latitude: 0, longitude: 0, label: "x",
                                    icon: HonorPersistence.arrivalWaypointIcon, timestamp: Date())
        XCTAssertTrue(HonorPersistence.isArrivalWaypoint(waypoint))
        XCTAssertFalse(SeekPersistence.isArrivalWaypoint(waypoint))
    }

    func testArrivalLabelCarriesTheWayTitle() {
        XCTAssertEqual(HonorPersistence.arrivalWaypointLabel(wayTitle: "Rúa do Franco → Obradoiro"),
                       "Walked their way: Rúa do Franco → Obradoiro")
    }

    func testPilgrimPackageEventStringsRoundTrip() {
        XCTAssertEqual(PilgrimPackageConverter.workoutEventTypeString(.honorMode), "honorMode")
        XCTAssertEqual(PilgrimPackageConverter.walkEventType(from: "honorArrival"), .honorArrival)
    }
}
```

`WaypointChip.presets` is declared at `Pilgrim/Scenes/ActiveWalk/WaypointMarkingSheet.swift:8`; each chip exposes `icon`.

- [ ] **Step 2: Register and run to verify it fails**

```bash
ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/HonorPersistenceTests.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/HonorPersistenceTests 2>&1 | grep -E "error:|Executed"
```
Expected: compile errors for `.honorMode` and `HonorPersistence`.

- [ ] **Step 3: Create `HonorPersistence.swift`**

```swift
import Foundation

/// The persistence vocabulary for honor walks, shaped like SeekPersistence:
/// a `.honorMode` event at recording start, and on reaching the end of the
/// Way a `.honorArrival` event plus a waypoint with the reserved icon.
enum HonorPersistence {

    /// Must never collide with WaypointMarkingSheet's presets, "mappin", or
    /// SeekPersistence.arrivalWaypointIcon.
    static let arrivalWaypointIcon = "signpost.right.fill"

    static func isArrivalWaypoint(_ waypoint: WaypointInterface) -> Bool {
        waypoint.icon == arrivalWaypointIcon
    }

    static func arrivalWaypointLabel(wayTitle: String) -> String {
        String(format: arrivalLabelFormat, wayTitle)
    }

    static let honorModeEventName = NSLocalizedString(
        "honor.event.honor_mode", value: "Honor",
        comment: "Name of the walk event marking a walk as an honor walk.")

    static let honorArrivalEventName = NSLocalizedString(
        "honor.event.arrival", value: "Way walked",
        comment: "Name of the walk event written when the end of a Way is reached.")

    private static let arrivalLabelFormat = NSLocalizedString(
        "honor.arrival.label", value: "Walked their way: %@",
        comment: "Waypoint label at the end of an honored Way; %@ is the Way's title.")
}
```

- [ ] **Step 4: Extend `WalkEvent.EventType`**

In `WalkEvent.swift` add `honorMode, honorArrival` to the case list (before `unknown`), and to each switch:

```swift
            case 5:
                self = .honorMode
            case 6:
                self = .honorArrival
```
```swift
            case .honorMode:
                return 5
            case .honorArrival:
                return 6
```
```swift
            case .honorMode:
                return HonorPersistence.honorModeEventName
            case .honorArrival:
                return HonorPersistence.honorArrivalEventName
```
```swift
            case .honorMode:
                return "HonorMode"
            case .honorArrival:
                return "HonorArrival"
```

- [ ] **Step 5: Extend the converter and make its helpers testable**

In `PilgrimPackageConverter.swift` change both helpers from `private static` to `static`, and add `case .honorMode: return "honorMode"`, `case .honorArrival: return "honorArrival"` to `workoutEventTypeString`, and `case "honorMode": return .honorMode`, `case "honorArrival": return .honorArrival` to `walkEventType(from:)`.

- [ ] **Step 6: Register, build, test**

```bash
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Models/Honor/HonorPersistence.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/HonorPersistenceTests 2>&1 | grep -E "error:|Executed"
```
Expected: `Executed 4 tests, with 0 failures`. Any exhaustive `switch` over `EventType` elsewhere fails to compile and names itself; add the two cases there with the obvious mapping.

- [ ] **Step 7: Commit**

```bash
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(honor): honorMode/honorArrival events and the reserved arrival icon"
```

---

### Task 4: The `Way` model and `WayGeometry`

**Files:**
- Create: `Pilgrim/Models/Honor/Way.swift`
- Create: `Pilgrim/Models/Honor/WayGeometry.swift`
- Test: `UnitTests/Honor/WayGeometryTests.swift`

**Interfaces:**
- Produces the types below. `WayMoment` is a struct with a `kind` enum (the spec sketches per-case `frac`/`at`; the struct carries them once). Moment ids are stable strings: `"voice-\(n)"`, `"photo-\(n)"`, `"waypoint-\(n)"`, `"rest-\(n)"`, `"sit-\(n)"`, 1-based within kind.
- `WayGeometry(route:)`, `coordinate(atFrac:)`, `frac(atElapsed:)`, `elapsed(atFrac:)`, `nearest(to:within:)`, `static distanceMeters(from:to:)`, `totalMeters`, `totalSeconds`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import CoreLocation
@testable import Pilgrim

final class WayGeometryTests: XCTestCase {

    /// A 1 km straight line east along the equator, 11 points, 100 m apart, 60 s apart.
    private func straight() -> WayGeometry {
        let points = (0...10).map { i in
            WayPoint(lat: 0, lon: Double(i) * 0.000898, alt: nil, t: Double(i) * 60)
        }
        return WayGeometry(route: points)
    }

    /// Out and back: 500 m east then the same 500 m west, 11 points.
    private func outAndBack() -> WayGeometry {
        let out = (0...5).map { i in WayPoint(lat: 0, lon: Double(i) * 0.000898, alt: nil, t: Double(i) * 60) }
        let back = (1...5).map { i in WayPoint(lat: 0, lon: Double(5 - i) * 0.000898, alt: nil, t: Double(5 + i) * 60) }
        return WayGeometry(route: out + back)
    }

    func testTotalsAndFracRoundTrips() {
        let geo = straight()
        XCTAssertEqual(geo.totalMeters, 1000, accuracy: 5)
        XCTAssertEqual(geo.totalSeconds, 600)
        let mid = geo.coordinate(atFrac: 0.5)
        XCTAssertEqual(mid.longitude, 0.00449, accuracy: 0.00002)
        XCTAssertEqual(geo.elapsed(atFrac: 0.5), 300, accuracy: 1)
        XCTAssertEqual(geo.frac(atElapsed: 300), 0.5, accuracy: 0.01)
        XCTAssertEqual(geo.frac(atElapsed: 9999), 1)
        XCTAssertEqual(geo.frac(atElapsed: -5), 0)
    }

    func testNearestOnStraightLine() {
        let geo = straight()
        let probe = CLLocationCoordinate2D(latitude: 0.00018, longitude: 0.00449)
        let hit = geo.nearest(to: probe, within: nil)
        XCTAssertEqual(hit.frac, 0.5, accuracy: 0.01)
        XCTAssertEqual(hit.meters, 20, accuracy: 2)
    }

    func testWindowedNearestStaysOnTheOutboundLeg() {
        let geo = outAndBack()
        // 250 m along: both legs pass here. Unwindowed search is ambiguous.
        let probe = CLLocationCoordinate2D(latitude: 0, longitude: 0.000898 * 2.5)
        let windowed = geo.nearest(to: probe, within: 0.20...0.35)
        XCTAssertEqual(windowed.frac, 0.25, accuracy: 0.01)
        let returnLeg = geo.nearest(to: probe, within: 0.70...0.85)
        XCTAssertEqual(returnLeg.frac, 0.75, accuracy: 0.01)
    }

    func testDegenerateRoutes() {
        let single = WayGeometry(route: [WayPoint(lat: 1, lon: 1, alt: nil, t: 0)])
        XCTAssertEqual(single.totalMeters, 0)
        XCTAssertEqual(single.frac(atElapsed: 10), 1)
        let hit = single.nearest(to: CLLocationCoordinate2D(latitude: 1, longitude: 1), within: nil)
        XCTAssertEqual(hit.frac, 0)
        XCTAssertEqual(hit.meters, 0, accuracy: 0.01)
    }
}
```

- [ ] **Step 2: Register and run to verify it fails**

```bash
ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/WayGeometryTests.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/WayGeometryTests 2>&1 | grep -E "error:|Executed"
```
Expected: compile errors, `WayPoint` and `WayGeometry` undefined.

- [ ] **Step 3: Create `Way.swift`**

```swift
import Foundation

struct WayCoordinate: Codable, Equatable {
    let lat: Double
    let lon: Double
}

struct WayPoint: Codable, Equatable {
    let lat: Double
    let lon: Double
    let alt: Double?
    /// Seconds since departure. Wall clock: the original walker's pauses
    /// are inside it, so the companion rests where they rested.
    let t: Double
}

enum VoiceKind: String, Codable { case spoken, ambient }

enum WayMedia: Codable, Equatable {
    /// Relative to `Ways/{id}/media/`.
    case file(String)
    /// Own walk: relative to the Documents directory.
    case recording(relativePath: String)
    /// Own walk: PhotoKit asset.
    case photoAsset(localIdentifier: String)
}

enum WayMomentKind: Codable, Equatable {
    case voice(endFrac: Double, duration: Double, kind: VoiceKind, media: WayMedia)
    case photo(media: WayMedia)
    case waypoint(label: String, icon: String)
    case rest(minutes: Int)
    case meditation(minutes: Int, isEstimate: Bool)
}

struct WayMoment: Codable, Equatable, Identifiable {
    let id: String
    /// Distance fraction along the route: orders moments and gates progress.
    let frac: Double
    /// The true place when the source knows it. Triggers fire on this;
    /// nil falls back to `WayGeometry.coordinate(atFrac:)`.
    let at: WayCoordinate?
    let kind: WayMomentKind

    var isVoice: Bool {
        if case .voice = kind { return true }
        return false
    }
}

enum WaySource: Codable, Equatable {
    case ownWalk(UUID)
    case share(id: String, pageURL: URL)
}

struct WayWeather: Codable, Equatable {
    let condition: String
    let temperatureC: Double?
}

struct Way: Codable, Equatable {
    let id: String
    let source: WaySource
    let title: String
    let departedAt: Date
    let tzIdentifier: String?
    let expires: Date?
    let route: [WayPoint]
    let totalDistanceMeters: Double
    let theirActiveSeconds: Double
    let moments: [WayMoment]
    let weather: WayWeather?

    var voiceCount: Int { moments.filter(\.isVoice).count }
    var photoCount: Int {
        moments.filter { if case .photo = $0.kind { return true } else { return false } }.count
    }
}
```

- [ ] **Step 4: Create `WayGeometry.swift`**

```swift
import CoreLocation
import Foundation

/// The only place Honor does geometry. Cumulative haversine distances over
/// the Way's route; every other consumer talks in fracs (0...1 of the
/// total length) or seconds since departure.
struct WayGeometry {

    let points: [WayPoint]
    /// cumulative[i] = meters from the first point to point i.
    let cumulative: [Double]
    let totalMeters: Double
    let totalSeconds: Double

    init(route: [WayPoint]) {
        points = route
        var running = 0.0
        var cum: [Double] = []
        cum.reserveCapacity(route.count)
        for (index, point) in route.enumerated() {
            if index > 0 {
                running += Self.distanceMeters(from: route[index - 1], to: point)
            }
            cum.append(running)
        }
        cumulative = cum
        totalMeters = running
        totalSeconds = route.last.map { $0.t - (route.first?.t ?? 0) } ?? 0
    }

    // MARK: - Frac ↔ coordinate ↔ time

    func coordinate(atFrac frac: Double) -> CLLocationCoordinate2D {
        guard let first = points.first else { return CLLocationCoordinate2D(latitude: 0, longitude: 0) }
        guard points.count > 1, totalMeters > 0 else {
            return CLLocationCoordinate2D(latitude: first.lat, longitude: first.lon)
        }
        let target = min(max(frac, 0), 1) * totalMeters
        let (i, u) = segment(atDistance: target)
        let a = points[i], b = points[i + 1]
        return CLLocationCoordinate2D(latitude: a.lat + (b.lat - a.lat) * u,
                                      longitude: a.lon + (b.lon - a.lon) * u)
    }

    func elapsed(atFrac frac: Double) -> Double {
        guard points.count > 1, totalMeters > 0 else { return 0 }
        let (i, u) = segment(atDistance: min(max(frac, 0), 1) * totalMeters)
        let a = points[i], b = points[i + 1]
        return (a.t + (b.t - a.t) * u) - points[0].t
    }

    func frac(atElapsed elapsed: Double) -> Double {
        guard points.count > 1, totalMeters > 0 else { return 1 }
        let t0 = points[0].t
        if elapsed <= 0 { return 0 }
        if elapsed >= totalSeconds { return 1 }
        for i in 0..<(points.count - 1) {
            let ta = points[i].t - t0, tb = points[i + 1].t - t0
            if elapsed >= ta && elapsed <= tb {
                let u = tb > ta ? (elapsed - ta) / (tb - ta) : 0
                let d = cumulative[i] + (cumulative[i + 1] - cumulative[i]) * u
                return d / totalMeters
            }
        }
        return 1
    }

    // MARK: - Nearest point

    /// Closest point on the polyline to `coordinate`, optionally restricted
    /// to segments whose frac span overlaps `window`. Returns the frac of
    /// the projection and the distance to it in meters.
    func nearest(
        to coordinate: CLLocationCoordinate2D,
        within window: ClosedRange<Double>?
    ) -> (frac: Double, meters: Double) {
        guard let first = points.first else { return (0, .infinity) }
        guard points.count > 1, totalMeters > 0 else {
            return (0, Self.distanceMeters(from: first, to: WayPoint(lat: coordinate.latitude, lon: coordinate.longitude, alt: nil, t: 0)))
        }
        var best: (frac: Double, meters: Double) = (0, .infinity)
        let cosLat = cos(coordinate.latitude * .pi / 180)
        for i in 0..<(points.count - 1) {
            let fa = cumulative[i] / totalMeters, fb = cumulative[i + 1] / totalMeters
            if let window, fb < window.lowerBound || fa > window.upperBound { continue }
            let a = points[i], b = points[i + 1]
            // Local equirectangular projection (meters) is accurate enough
            // for the tens-of-meters decisions the engine makes.
            let ax = (a.lon - coordinate.longitude) * cosLat, ay = a.lat - coordinate.latitude
            let bx = (b.lon - coordinate.longitude) * cosLat, by = b.lat - coordinate.latitude
            let dx = bx - ax, dy = by - ay
            let lengthSq = dx * dx + dy * dy
            let u = lengthSq > 0 ? min(max(-(ax * dx + ay * dy) / lengthSq, 0), 1) : 0
            let px = ax + dx * u, py = ay + dy * u
            let meters = sqrt(px * px + py * py) * 111_320
            if meters < best.meters {
                best = (fa + (fb - fa) * u, meters)
            }
        }
        return best
    }

    // MARK: - Helpers

    private func segment(atDistance d: Double) -> (index: Int, u: Double) {
        var lo = 0, hi = points.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if cumulative[mid] <= d { lo = mid } else { hi = mid }
        }
        let span = cumulative[hi] - cumulative[lo]
        let u = span > 0 ? (d - cumulative[lo]) / span : 0
        return (lo, min(max(u, 0), 1))
    }

    static func distanceMeters(from a: WayPoint, to b: WayPoint) -> Double {
        let r = 6_371_000.0
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLon = (b.lon - a.lon) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.lat * .pi / 180) * cos(b.lat * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(sqrt(h), sqrt(1 - h))
    }
}
```

- [ ] **Step 5: Register, run the tests**

```bash
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Models/Honor/Way.swift
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Models/Honor/WayGeometry.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/WayGeometryTests 2>&1 | grep -E "error:|Executed"
```
Expected: `Executed 4 tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(honor): Way model and WayGeometry"
```

---

### Task 5: `OwnWalkWayBuilder`

**Files:**
- Create: `Pilgrim/Models/Honor/OwnWalkWayBuilder.swift`
- Test: `UnitTests/Honor/OwnWalkWayBuilderTests.swift`

**Interfaces:**
- Consumes: `Way`, `WayGeometry`, `TourBuilder.classify(transcription:)`, `RouteDownsampler` (via a local RDP over `WayPoint`).
- Produces: `OwnWalkWayBuilder.make(from walk: WalkInterface) -> Way?` (nil when fewer than 2 route samples). `OwnWalkWayBuilder.maxRoutePoints == 4000`. Way id `"walk:\(uuid)"`, title = `walk.comment` if non-empty else the date formatted `.medium`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Pilgrim

final class OwnWalkWayBuilderTests: XCTestCase {

    private let start = DateFactory.makeDate(2026, 5, 1, 8, 0, 0)

    private func sample(_ i: Int, lon: Double) -> TempRouteDataSample {
        TempRouteDataSample(uuid: nil, timestamp: start.addingTimeInterval(Double(i) * 60),
                            latitude: 42.88, longitude: lon, altitude: 300,
                            horizontalAccuracy: 5, verticalAccuracy: 5, speed: 1.4, direction: 90)
    }

    /// Ten samples 100 m apart, one per minute.
    private func walk(uuid: UUID = UUID()) -> TempWalk {
        let route = (0..<10).map { sample($0, lon: -8.54 + Double($0) * 0.00122) }
        let recording = TempVoiceRecording(
            uuid: nil, startDate: start.addingTimeInterval(4 * 60 + 10),
            endDate: start.addingTimeInterval(5 * 60), duration: 50,
            fileRelativePath: "Recordings/a/b.m4a",
            transcription: "a thought that runs on for more than eight words in total")
        let sitting = TempActivityInterval(
            uuid: nil, activityType: .meditation,
            startDate: start.addingTimeInterval(7 * 60), endDate: start.addingTimeInterval(19 * 60))
        let pin = TempWaypoint(uuid: nil, latitude: 42.88, longitude: -8.54 + 2 * 0.00122,
                               label: "Oak", icon: "leaf", timestamp: start.addingTimeInterval(120))
        let arrival = TempWaypoint(uuid: nil, latitude: 42.88, longitude: -8.54,
                                   label: "x", icon: SeekPersistence.arrivalWaypointIcon, timestamp: start)
        let pause = TempWalkPause(uuid: nil, startDate: start.addingTimeInterval(3 * 60),
                                  endDate: start.addingTimeInterval(3 * 60 + 200), pauseType: .manual)
        return WalkDataFactory.makeWalk(
            uuid: uuid, startDate: start, endDate: start.addingTimeInterval(9 * 60),
            activeDuration: 540 - 200, routeData: route, pauses: [pause],
            voiceRecordings: [recording], activityIntervals: [sitting],
            waypoints: [pin, arrival])
    }

    func testBuildsMomentsAtTheRightFracsWithCoordinates() throws {
        let way = try XCTUnwrap(OwnWalkWayBuilder.make(from: walk()))
        XCTAssertEqual(way.route.count, 10)
        XCTAssertEqual(way.totalDistanceMeters, 900, accuracy: 10)
        XCTAssertEqual(way.theirActiveSeconds, 340)

        let voice = try XCTUnwrap(way.moments.first { $0.id == "voice-1" })
        XCTAssertEqual(voice.frac, 4.0 / 9.0, accuracy: 0.03)
        XCTAssertEqual(voice.at?.lon ?? 0, -8.54 + 4 * 0.00122, accuracy: 0.0001)
        guard case .voice(_, let duration, let kind, let media) = voice.kind else { return XCTFail("kind") }
        XCTAssertEqual(duration, 50)
        XCTAssertEqual(kind, .spoken)
        XCTAssertEqual(media, .recording(relativePath: "Recordings/a/b.m4a"))

        let sit = try XCTUnwrap(way.moments.first { $0.id == "sit-1" })
        guard case .meditation(let minutes, let isEstimate) = sit.kind else { return XCTFail("kind") }
        XCTAssertEqual(minutes, 12)
        XCTAssertFalse(isEstimate)

        let rest = try XCTUnwrap(way.moments.first { $0.id == "rest-1" })
        guard case .rest(let restMinutes) = rest.kind else { return XCTFail("kind") }
        XCTAssertEqual(restMinutes, 3)

        XCTAssertTrue(way.moments.contains { $0.id == "waypoint-1" })
        XCTAssertEqual(way.moments.filter { if case .waypoint = $0.kind { return true }; return false }.count, 1,
                       "reserved-icon waypoints are excluded")
        XCTAssertEqual(way.moments.map(\.frac), way.moments.map(\.frac).sorted())
    }

    func testNilWithoutARoute() {
        XCTAssertNil(OwnWalkWayBuilder.make(from: WalkDataFactory.makeWalk(routeData: [])))
    }

    func testIdentityAndTitle() throws {
        let id = UUID()
        let way = try XCTUnwrap(OwnWalkWayBuilder.make(from: walk(uuid: id)))
        XCTAssertEqual(way.id, "walk:\(id.uuidString)")
        XCTAssertEqual(way.source, .ownWalk(id))
        XCTAssertNil(way.expires)
    }
}
```

- [ ] **Step 2: Register and run to verify it fails**

```bash
ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/OwnWalkWayBuilderTests.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/OwnWalkWayBuilderTests 2>&1 | grep -E "error:|Executed"
```
Expected: `OwnWalkWayBuilder` undefined.

- [ ] **Step 3: Create `OwnWalkWayBuilder.swift`**

```swift
import Foundation

/// A Way from one of the walker's own walks. Nothing is copied: voices
/// reference their recording files and photos their PhotoKit assets.
enum OwnWalkWayBuilder {

    static let maxRoutePoints = 4000
    static let minRestSeconds = 180.0

    static func make(from walk: WalkInterface) -> Way? {
        let samples = walk.routeData.sorted { $0.timestamp < $1.timestamp }
        guard samples.count >= 2, let first = samples.first, let uuid = walk.uuid else { return nil }
        let t0 = first.timestamp
        let full = samples.map {
            WayPoint(lat: $0.latitude, lon: $0.longitude, alt: $0.altitude,
                     t: $0.timestamp.timeIntervalSince(t0))
        }
        let fullGeometry = WayGeometry(route: full)
        let route = full.count > maxRoutePoints ? strideSample(full, target: maxRoutePoints) : full

        var moments: [WayMoment] = []
        // Positions come from the FULL-resolution samples, before any
        // downsampling, so a voice lands where it was spoken.
        func place(_ date: Date) -> (frac: Double, at: WayCoordinate) {
            let nearest = samples.min { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) } ?? first
            let frac = fullGeometry.frac(atElapsed: nearest.timestamp.timeIntervalSince(t0))
            return (frac, WayCoordinate(lat: nearest.latitude, lon: nearest.longitude))
        }

        for (n, rec) in walk.voiceRecordings.sorted(by: { $0.startDate < $1.startDate }).enumerated()
        where !rec.fileRelativePath.isEmpty {
            let start = place(rec.startDate)
            let end = place(rec.endDate)
            moments.append(WayMoment(
                id: "voice-\(n + 1)", frac: start.frac, at: start.at,
                kind: .voice(endFrac: max(end.frac, start.frac), duration: rec.duration,
                             kind: TourBuilder.classify(transcription: rec.transcription) == .spoken ? .spoken : .ambient,
                             media: .recording(relativePath: rec.fileRelativePath))))
        }
        for (n, photo) in walk.walkPhotos.sorted(by: { $0.capturedAt < $1.capturedAt }).enumerated() {
            let p = place(photo.capturedAt)
            moments.append(WayMoment(
                id: "photo-\(n + 1)", frac: p.frac,
                at: WayCoordinate(lat: photo.capturedLat, lon: photo.capturedLng),
                kind: .photo(media: .photoAsset(localIdentifier: photo.localIdentifier))))
        }
        let userWaypoints = walk.waypoints
            .filter { !SeekPersistence.isArrivalWaypoint($0) && !HonorPersistence.isArrivalWaypoint($0) }
            .sorted { $0.timestamp < $1.timestamp }
        for (n, wp) in userWaypoints.enumerated() {
            moments.append(WayMoment(
                id: "waypoint-\(n + 1)", frac: place(wp.timestamp).frac,
                at: WayCoordinate(lat: wp.latitude, lon: wp.longitude),
                kind: .waypoint(label: wp.label, icon: wp.icon)))
        }
        let rests = walk.pauses
            .filter { $0.endDate.timeIntervalSince($0.startDate) >= minRestSeconds }
            .sorted { $0.startDate < $1.startDate }
        for (n, pause) in rests.enumerated() {
            let p = place(pause.startDate)
            moments.append(WayMoment(
                id: "rest-\(n + 1)", frac: p.frac, at: p.at,
                kind: .rest(minutes: Int((pause.endDate.timeIntervalSince(pause.startDate) / 60).rounded()))))
        }
        let sittings = walk.activityIntervals
            .filter { $0.activityType == .meditation }
            .sorted { $0.startDate < $1.startDate }
        for (n, sit) in sittings.enumerated() {
            let p = place(sit.startDate)
            moments.append(WayMoment(
                id: "sit-\(n + 1)", frac: p.frac, at: p.at,
                kind: .meditation(minutes: Int((sit.endDate.timeIntervalSince(sit.startDate) / 60).rounded()),
                                  isEstimate: false)))
        }
        moments.sort { $0.frac < $1.frac }

        let title: String
        if let comment = walk.comment?.trimmingCharacters(in: .whitespacesAndNewlines), !comment.isEmpty {
            title = comment
        } else {
            title = DateFormatter.localizedString(from: walk.startDate, dateStyle: .medium, timeStyle: .none)
        }
        let weather = walk.weatherCondition.map { WayWeather(condition: $0, temperatureC: walk.weatherTemperature) }

        return Way(
            id: "walk:\(uuid.uuidString)", source: .ownWalk(uuid), title: title,
            departedAt: walk.startDate, tzIdentifier: TimeZone.current.identifier, expires: nil,
            route: route, totalDistanceMeters: fullGeometry.totalMeters,
            theirActiveSeconds: walk.activeDuration, moments: moments, weather: weather)
    }

    private static func strideSample(_ points: [WayPoint], target: Int) -> [WayPoint] {
        let step = Double(points.count - 1) / Double(target - 1)
        var result = (0..<(target - 1)).map { points[Int((Double($0) * step).rounded())] }
        result.append(points[points.count - 1])
        return result
    }
}
```

- [ ] **Step 4: Register, test**

```bash
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Models/Honor/OwnWalkWayBuilder.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/OwnWalkWayBuilderTests 2>&1 | grep -E "error:|Executed"
```
Expected: `Executed 3 tests, with 0 failures`. If `TempVoiceRecording`'s initializer has more required parameters than the test passes, mirror the call in `ScreenshotDataSeeder.swift:236`.

- [ ] **Step 5: Commit**

```bash
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(honor): build a Way from one of your own walks"
```

---

### Task 6: Extract `ArrivalDebounce` from `SeekEngine`

**Files:**
- Create: `Pilgrim/Models/Walk/Seek/ArrivalDebounce.swift`
- Modify: `Pilgrim/Models/Walk/Seek/SeekEngine.swift:66`, `:287-299`, `:303`, `:346`
- Test: `UnitTests/Seek/ArrivalDebounceTests.swift`

**Interfaces:**
- Produces: `struct ArrivalDebounce { init(requiredFixes: Int, accuracyMeters: Double); mutating func register(distance: Double, radius: Double, accuracy: Double) -> Bool; mutating func reset() }`. Returns true on the fix that completes the count. A fix with `accuracy < 0` or `> accuracyMeters` neither advances nor resets.

- [ ] **Step 1: Write the failing tests (they pin Seek's current behavior)**

```swift
import XCTest
@testable import Pilgrim

final class ArrivalDebounceTests: XCTestCase {

    func testThreeConsecutiveInsideFixesArrive() {
        var d = ArrivalDebounce(requiredFixes: 3, accuracyMeters: 50)
        XCTAssertFalse(d.register(distance: 10, radius: 30, accuracy: 5))
        XCTAssertFalse(d.register(distance: 10, radius: 30, accuracy: 5))
        XCTAssertTrue(d.register(distance: 10, radius: 30, accuracy: 5))
    }

    func testAnOutsideFixResetsTheCount() {
        var d = ArrivalDebounce(requiredFixes: 3, accuracyMeters: 50)
        _ = d.register(distance: 10, radius: 30, accuracy: 5)
        _ = d.register(distance: 10, radius: 30, accuracy: 5)
        XCTAssertFalse(d.register(distance: 40, radius: 30, accuracy: 5))
        XCTAssertFalse(d.register(distance: 10, radius: 30, accuracy: 5))
        XCTAssertFalse(d.register(distance: 10, radius: 30, accuracy: 5))
        XCTAssertTrue(d.register(distance: 10, radius: 30, accuracy: 5))
    }

    func testPoorAccuracyNeitherAdvancesNorResets() {
        var d = ArrivalDebounce(requiredFixes: 3, accuracyMeters: 50)
        _ = d.register(distance: 10, radius: 30, accuracy: 5)
        _ = d.register(distance: 10, radius: 30, accuracy: 5)
        XCTAssertFalse(d.register(distance: 10, radius: 30, accuracy: 120))
        XCTAssertFalse(d.register(distance: 10, radius: 30, accuracy: -1))
        XCTAssertTrue(d.register(distance: 10, radius: 30, accuracy: 5))
    }
}
```

- [ ] **Step 2: Register and run to verify it fails**

```bash
ruby scripts/xcode-add.rb UnitTests UnitTests/Seek/ArrivalDebounceTests.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/ArrivalDebounceTests 2>&1 | grep -E "error:|Executed"
```
Expected: `ArrivalDebounce` undefined.

- [ ] **Step 3: Create `ArrivalDebounce.swift`**

```swift
import Foundation

/// Consecutive-inside-fix arrival gate shared by Seek and Honor. Fixes worse
/// than the accuracy gate neither advance nor reset the count: a momentary
/// multipath fix must not erase honest progress, and must never fake it.
struct ArrivalDebounce {
    let requiredFixes: Int
    let accuracyMeters: Double
    private(set) var consecutiveInside = 0

    init(requiredFixes: Int, accuracyMeters: Double) {
        self.requiredFixes = requiredFixes
        self.accuracyMeters = accuracyMeters
    }

    /// True on the fix that completes the count.
    mutating func register(distance: Double, radius: Double, accuracy: Double) -> Bool {
        guard accuracy >= 0, accuracy <= accuracyMeters else { return false }
        consecutiveInside = distance <= radius ? consecutiveInside + 1 : 0
        return consecutiveInside >= requiredFixes
    }

    mutating func reset() { consecutiveInside = 0 }
}
```

- [ ] **Step 4: Use it in `SeekEngine`**

Replace `private var consecutiveInsideCount = 0` (`:66`) with:
```swift
    private var arrivalDebounce = ArrivalDebounce(
        requiredFixes: SeekEngineTuning.arrivalFixCount,
        accuracyMeters: SeekEngineTuning.arrivalAccuracyMeters
    )
```
Replace the body of `updateArrivalDebounce` (`:287-299`) with:
```swift
    private func updateArrivalDebounce(location: CLLocation, distance: Double, radius: Double) {
        if arrivalDebounce.register(distance: distance, radius: radius, accuracy: location.horizontalAccuracy) {
            transitionToArrived()
        } else {
            ensurePulseScheduled()
        }
    }
```
Replace `consecutiveInsideCount = 0` at `:303` and `:346` with `arrivalDebounce.reset()`.

- [ ] **Step 5: Register, run the Seek suite and the new tests**

```bash
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Models/Walk/Seek/ArrivalDebounce.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/ArrivalDebounceTests -only-testing:UnitTests/SeekEngineTests -only-testing:UnitTests/ActiveWalkSeekTests 2>&1 | grep -E "error:|Executed"
```
Expected: all green, `0 failures` on each class.

- [ ] **Step 6: Commit**

```bash
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "refactor(seek): extract ArrivalDebounce so Honor can share the arrival gate"
```

---

### Task 7: `HonorEngine` core: position, companion, arrival

**Files:**
- Create: `Pilgrim/Models/Honor/HonorTuning.swift`
- Create: `Pilgrim/Models/Honor/HonorEngine.swift`
- Modify: `Pilgrim/Models/Honor/WayGeometry.swift` (add `lowestFrac(within:of:)`)
- Test: `UnitTests/Honor/HonorEngineTests.swift`

**Interfaces:**
- Consumes: `Way`, `WayGeometry`, `ArrivalDebounce`.
- Produces: `HonorTuning` constants; `HonorPhase { walking, arrived }`; `HonorEngineEvent` (`.momentReached`, `.voiceStart`, `.voicePause`, `.voiceResume`, `.voiceDropped`, `.softTap(offWayMeters:)`, `.arrived(theirSeconds:yourSeconds:)`); `HonorEngine(way:softTapEnabled:voicesEnabled:now:)` with `@Published progressFrac, distanceRemainingMeters, offWayMeters, isOnWay, companionFrac, phase`, `events`, `startFrac`, `companionT0`, `distanceWalkedMeters`, `processLocation(_:)`, `updateActiveDuration(_:)`, `setGates(paused:meditating:recording:externalAudio:)`, `voiceDidFinish()`, `bind(...)`, `stop()`. Task 8 fills in the moment tracker the engine already calls.
- `WayGeometry.lowestFrac(within meters: Double, of: CLLocationCoordinate2D) -> Double?`: the smallest frac whose segment passes within `meters`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import CoreLocation
@testable import Pilgrim

final class HonorEngineTests: XCTestCase {

    private var clock = Date(timeIntervalSince1970: 1_000_000)

    /// Out and back along the equator: 500 m east (6 points), 500 m west (5 points), 60 s per point.
    private func outAndBackWay() -> Way {
        let out = (0...5).map { i in WayPoint(lat: 0, lon: Double(i) * 0.000898, alt: nil, t: Double(i) * 60) }
        let back = (1...5).map { i in WayPoint(lat: 0, lon: Double(5 - i) * 0.000898, alt: nil, t: Double(5 + i) * 60) }
        return Way(id: "walk:test", source: .ownWalk(UUID()), title: "loop", departedAt: clock,
                   tzIdentifier: nil, expires: nil, route: out + back,
                   totalDistanceMeters: 1000, theirActiveSeconds: 600, moments: [], weather: nil)
    }

    private func fix(lon: Double, lat: Double = 0, accuracy: Double = 5, speed: Double = 1.4, at seconds: Double) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), altitude: 0,
                   horizontalAccuracy: accuracy, verticalAccuracy: 5, course: 90, speed: speed,
                   timestamp: clock.addingTimeInterval(seconds))
    }

    private func makeEngine(way: Way? = nil) -> HonorEngine {
        HonorEngine(way: way ?? outAndBackWay(), softTapEnabled: true, voicesEnabled: true, now: { self.clock })
    }

    func testAnchorsAtLowestFracAndFollowsTheOutboundLeg() {
        let engine = makeEngine()
        engine.processLocation(fix(lon: 0.000898 * 0.5, at: 0))
        XCTAssertEqual(engine.startFrac ?? -1, 0.05, accuracy: 0.01, "lowest frac within 60 m, not the return leg")
        XCTAssertTrue(engine.isOnWay)
        // Walk out to 250 m: both legs share this pavement; progress must read 0.25, never 0.75.
        engine.processLocation(fix(lon: 0.000898 * 2.5, at: 120))
        XCTAssertEqual(engine.progressFrac, 0.25, accuracy: 0.02)
        XCTAssertEqual(engine.distanceRemainingMeters, 750, accuracy: 30)
    }

    func testFarFromTheWayAnchorsAtZeroAndIsOffWay() {
        let engine = makeEngine()
        engine.processLocation(fix(lon: 0.05, lat: 0.05, at: 0))
        XCTAssertEqual(engine.startFrac, 0)
        XCTAssertFalse(engine.isOnWay)
        XCTAssertGreaterThan(engine.offWayMeters, 1000)
    }

    func testCompanionRunsOnActiveDurationFromTheAnchor() {
        let engine = makeEngine()
        engine.processLocation(fix(lon: 0.000898 * 2, at: 0))     // 200 m in → their t = 120 s
        XCTAssertEqual(engine.companionT0, 120, accuracy: 2)
        engine.updateActiveDuration(60)
        XCTAssertEqual(engine.companionFrac, 0.30, accuracy: 0.02)
        engine.updateActiveDuration(1200)
        XCTAssertEqual(engine.companionFrac, 1)
    }

    func testArrivalNeedsProgressAndDistanceNotJustProximity() {
        let engine = makeEngine()
        var arrived: [HonorEngineEvent] = []
        let sub = engine.events.sink { if case .arrived = $0 { arrived.append($0) } }
        defer { sub.cancel() }
        // Standing at the start, which is also the end: three fixes must NOT arrive.
        for i in 0..<3 { engine.processLocation(fix(lon: 0, at: Double(i))) }
        XCTAssertTrue(arrived.isEmpty)
        XCTAssertEqual(engine.phase, .walking)
        // Walk the whole loop.
        for i in 1...5 { engine.processLocation(fix(lon: 0.000898 * Double(i), at: Double(i) * 60)) }
        for i in 1...4 { engine.processLocation(fix(lon: 0.000898 * Double(5 - i), at: Double(5 + i) * 60)) }
        engine.updateActiveDuration(540)
        for i in 0..<3 { engine.processLocation(fix(lon: 0.00001, at: 600 + Double(i))) }
        XCTAssertEqual(engine.phase, .arrived)
        guard case .arrived(let theirs, let yours) = arrived.first else { return XCTFail("no arrival") }
        XCTAssertEqual(theirs, 600, accuracy: 1)
        XCTAssertEqual(yours, 540)
    }

    func testSoftTapFiresOnceAfterSustainedDriftAndRearms() {
        let engine = makeEngine()
        var taps = 0
        let sub = engine.events.sink { if case .softTap = $0 { taps += 1 } }
        defer { sub.cancel() }
        engine.processLocation(fix(lon: 0.000898, at: 0))
        // 400 m north of the line, for 3 minutes.
        for s in stride(from: 10.0, through: 180, by: 10) {
            clock = Date(timeIntervalSince1970: 1_000_000 + s)
            engine.processLocation(fix(lon: 0.000898, lat: 0.0036, at: s))
        }
        XCTAssertEqual(taps, 1)
        clock = Date(timeIntervalSince1970: 1_000_000 + 190)
        engine.processLocation(fix(lon: 0.000898, lat: 0.0036, at: 190))
        XCTAssertEqual(taps, 1, "no repeat while still off")
        clock = Date(timeIntervalSince1970: 1_000_000 + 200)
        engine.processLocation(fix(lon: 0.000898, at: 200))
        for s in stride(from: 210.0, through: 340, by: 10) {
            clock = Date(timeIntervalSince1970: 1_000_000 + s)
            engine.processLocation(fix(lon: 0.000898, lat: 0.0036, at: s))
        }
        XCTAssertEqual(taps, 2, "re-armed after returning within 60 m")
    }

    func testReacquiresAfterSustainedOffWay() {
        let engine = makeEngine()
        engine.processLocation(fix(lon: 0, at: 0))
        for s in stride(from: 10.0, through: 130, by: 10) {
            clock = Date(timeIntervalSince1970: 1_000_000 + s)
            engine.processLocation(fix(lon: 0.000898 * 4, lat: 0.01, at: s))
        }
        clock = Date(timeIntervalSince1970: 1_000_000 + 140)
        engine.processLocation(fix(lon: 0.000898 * 4, at: 140))
        XCTAssertEqual(engine.progressFrac, 0.4, accuracy: 0.02, "global re-acquire takes the lowest frac within 60 m")
        XCTAssertTrue(engine.isOnWay)
    }
}
```

- [ ] **Step 2: Register and run to verify it fails**

```bash
ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/HonorEngineTests.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/HonorEngineTests 2>&1 | grep -E "error:|Executed"
```
Expected: `HonorEngine` undefined.

- [ ] **Step 3: Create `HonorTuning.swift`**

```swift
import Foundation

/// Every Honor threshold in one place. Values from the spec; on-device
/// tuning candidates, not commitments.
enum HonorTuning {
    static let fixAccuracyMeters = 50.0
    static let onWayMeters = 60.0
    static let windowMeters = 300.0
    static let backwardTolerance = 0.02
    static let momentFracTolerance = 0.05
    static let reacquireSeconds: TimeInterval = 120
    static let voiceRadiusMeters = 42.0
    static let momentRadiusMeters = 60.0
    static let voiceDropMeters = 300.0
    static let stationarySpeed = 0.4
    static let softTapMeters = 200.0
    static let softTapSeconds: TimeInterval = 120
    static let arrivalRadiusMeters = 30.0
    static let arrivalMinFrac = 0.9
    static let arrivalMinDistanceRatio = 0.5
    static let arrivalFixCount = SeekEngineTuning.arrivalFixCount
    static let arrivalAccuracyMeters = SeekEngineTuning.arrivalAccuracyMeters
}
```

- [ ] **Step 4: Add `lowestFrac` to `WayGeometry`**

Append inside `struct WayGeometry`:

```swift
    /// The smallest frac whose segment passes within `meters` of the
    /// coordinate: the anchor for a walker who starts mid-Way, and the
    /// re-acquire target after sustained drift. Nil when nothing is near.
    func lowestFrac(within meters: Double, of coordinate: CLLocationCoordinate2D) -> Double? {
        guard points.count > 1, totalMeters > 0 else {
            return nearest(to: coordinate, within: nil).meters <= meters ? 0 : nil
        }
        for i in 0..<(points.count - 1) {
            let fa = cumulative[i] / totalMeters, fb = cumulative[i + 1] / totalMeters
            let hit = nearest(to: coordinate, within: fa...fb)
            if hit.meters <= meters { return hit.frac }
        }
        return nil
    }
```

- [ ] **Step 5: Create `HonorEngine.swift`**

```swift
import Combine
import CoreLocation
import Foundation

enum HonorPhase: Equatable { case walking, arrived }

enum HonorEngineEvent: Equatable {
    case momentReached(WayMoment)
    case voiceStart(WayMoment)
    case voicePause
    case voiceResume
    case voiceDropped(WayMoment)
    case softTap(offWayMeters: Double)
    case arrived(theirSeconds: Double, yourSeconds: Double)
}

/// Session engine for an honor walk: consumes the walk's streams, keeps
/// position along the Way, moves the companion on the walker's active
/// clock, triggers moments, and detects arrival. Persists nothing.
final class HonorEngine: ObservableObject {

    let way: Way
    let geometry: WayGeometry
    let events: AnyPublisher<HonorEngineEvent, Never>

    @Published private(set) var progressFrac: Double = 0
    @Published private(set) var distanceRemainingMeters: Double
    @Published private(set) var offWayMeters: Double = 0
    @Published private(set) var isOnWay = false
    @Published private(set) var companionFrac: Double = 0
    @Published private(set) var phase: HonorPhase = .walking

    private(set) var startFrac: Double?
    private(set) var companionT0: Double = 0
    private(set) var distanceWalkedMeters: Double = 0

    private let now: () -> Date
    private let softTapEnabled: Bool
    private let subject = PassthroughSubject<HonorEngineEvent, Never>()
    private var cancellables: [AnyCancellable] = []
    private var arrival: ArrivalDebounce
    private var moments: HonorMomentTracker
    private var gates = HonorMomentTracker.Gates()
    private var activeDuration: TimeInterval = 0
    private var lastAcceptedCoordinate: CLLocationCoordinate2D?
    private var offWaySince: Date?
    private var softTapSince: Date?
    private var softTapArmed = true

    init(way: Way, softTapEnabled: Bool, voicesEnabled: Bool, now: @escaping () -> Date = { Date() }) {
        self.way = way
        self.geometry = WayGeometry(route: way.route)
        self.now = now
        self.softTapEnabled = softTapEnabled
        self.events = subject.eraseToAnyPublisher()
        self.distanceRemainingMeters = geometry.totalMeters
        self.arrival = ArrivalDebounce(requiredFixes: HonorTuning.arrivalFixCount,
                                       accuracyMeters: HonorTuning.arrivalAccuracyMeters)
        self.moments = HonorMomentTracker(moments: way.moments, geometry: geometry, voicesEnabled: voicesEnabled)
    }

    // MARK: - Binding

    func bind(
        locations: AnyPublisher<CLLocation, Never>,
        activeDuration: AnyPublisher<TimeInterval, Never>,
        isPaused: AnyPublisher<Bool, Never>,
        isMeditating: AnyPublisher<Bool, Never>,
        isRecordingVoice: AnyPublisher<Bool, Never>,
        externalAudio: AnyPublisher<Bool, Never>
    ) {
        cancellables.removeAll()
        locations.receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.processLocation($0) }.store(in: &cancellables)
        activeDuration.receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateActiveDuration($0) }.store(in: &cancellables)
        isPaused.combineLatest(isMeditating, isRecordingVoice, externalAudio)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] paused, meditating, recording, audio in
                self?.setGates(paused: paused, meditating: meditating, recording: recording, externalAudio: audio)
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
    }

    // MARK: - Inputs

    func updateActiveDuration(_ seconds: TimeInterval) {
        activeDuration = seconds
        guard startFrac != nil else { return }
        companionFrac = geometry.frac(atElapsed: companionT0 + seconds)
    }

    func setGates(paused: Bool, meditating: Bool, recording: Bool, externalAudio: Bool) {
        gates = HonorMomentTracker.Gates(paused: paused, meditating: meditating,
                                         recording: recording, externalAudio: externalAudio)
        emit(moments.gatesDidChange(gates))
    }

    func voiceDidFinish() {
        emit(moments.voiceDidFinish(gates: gates))
    }

    func processLocation(_ location: CLLocation) {
        let accuracy = location.horizontalAccuracy
        guard accuracy >= 0, accuracy <= HonorTuning.fixAccuracyMeters else { return }
        let coordinate = location.coordinate
        if let last = lastAcceptedCoordinate {
            distanceWalkedMeters += CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: location)
        }
        lastAcceptedCoordinate = coordinate

        if startFrac == nil { anchor(at: coordinate) }
        track(coordinate)
        distanceRemainingMeters = (1 - progressFrac) * geometry.totalMeters
        evaluateSoftTap()
        evaluateArrival(location)

        let stationary = location.speed >= 0 && location.speed < HonorTuning.stationarySpeed
        emit(moments.update(location: coordinate, progressFrac: progressFrac, gates: gates, isStationary: stationary))
    }

    // MARK: - Position

    private func anchor(at coordinate: CLLocationCoordinate2D) {
        let frac = geometry.lowestFrac(within: HonorTuning.onWayMeters, of: coordinate) ?? 0
        startFrac = frac
        progressFrac = frac
        companionT0 = geometry.elapsed(atFrac: frac)
        companionFrac = geometry.frac(atElapsed: companionT0 + activeDuration)
    }

    private func track(_ coordinate: CLLocationCoordinate2D) {
        let windowSpan = geometry.totalMeters > 0 ? HonorTuning.windowMeters / geometry.totalMeters : 1
        let lower = max(0, progressFrac - HonorTuning.backwardTolerance)
        let upper = min(1, progressFrac + windowSpan)
        let local = geometry.nearest(to: coordinate, within: lower...upper)
        offWayMeters = local.meters
        if local.meters <= HonorTuning.onWayMeters {
            isOnWay = true
            offWaySince = nil
            progressFrac = max(lower, local.frac)
            return
        }
        isOnWay = false
        let time = now()
        if offWaySince == nil { offWaySince = time }
        if let since = offWaySince, time.timeIntervalSince(since) >= HonorTuning.reacquireSeconds,
           let found = geometry.lowestFrac(within: HonorTuning.onWayMeters, of: coordinate) {
            progressFrac = found
            offWayMeters = geometry.nearest(to: coordinate, within: found...found).meters
            isOnWay = true
            offWaySince = nil
        }
    }

    // MARK: - Soft tap

    private func evaluateSoftTap() {
        guard softTapEnabled else { return }
        if offWayMeters <= HonorTuning.onWayMeters {
            softTapSince = nil
            softTapArmed = true
            return
        }
        guard softTapArmed, offWayMeters > HonorTuning.softTapMeters else {
            if offWayMeters <= HonorTuning.softTapMeters { softTapSince = nil }
            return
        }
        let time = now()
        if softTapSince == nil { softTapSince = time }
        if let since = softTapSince, time.timeIntervalSince(since) >= HonorTuning.softTapSeconds {
            softTapArmed = false
            softTapSince = nil
            subject.send(.softTap(offWayMeters: offWayMeters))
        }
    }

    // MARK: - Arrival

    private func evaluateArrival(_ location: CLLocation) {
        guard phase == .walking, let last = geometry.points.last else { return }
        guard progressFrac >= HonorTuning.arrivalMinFrac,
              distanceWalkedMeters >= HonorTuning.arrivalMinDistanceRatio * geometry.totalMeters else {
            arrival.reset()
            return
        }
        let end = CLLocation(latitude: last.lat, longitude: last.lon)
        let distance = location.distance(from: end)
        if arrival.register(distance: distance, radius: HonorTuning.arrivalRadiusMeters,
                            accuracy: location.horizontalAccuracy) {
            phase = .arrived
            subject.send(.arrived(theirSeconds: geometry.totalSeconds - companionT0, yourSeconds: activeDuration))
        }
    }

    private func emit(_ actions: [HonorMomentTracker.Action]) {
        for action in actions {
            switch action {
            case .reached(let moment): subject.send(.momentReached(moment))
            case .voiceStart(let moment): subject.send(.voiceStart(moment))
            case .voicePause: subject.send(.voicePause)
            case .voiceResume: subject.send(.voiceResume)
            case .voiceDropped(let moment): subject.send(.voiceDropped(moment))
            }
        }
    }
}
```

Until Task 8 lands, add this minimal `HonorMomentTracker` at the bottom of `HonorEngine.swift` so the file compiles; Task 8 moves and completes it:

```swift
struct HonorMomentTracker {
    enum Action: Equatable {
        case reached(WayMoment), voiceStart(WayMoment), voicePause, voiceResume, voiceDropped(WayMoment)
    }
    struct Gates: Equatable {
        var paused = false, meditating = false, recording = false, externalAudio = false
        var isClosed: Bool { paused || meditating || recording || externalAudio }
    }
    init(moments: [WayMoment], geometry: WayGeometry, voicesEnabled: Bool) {}
    mutating func update(location: CLLocationCoordinate2D, progressFrac: Double, gates: Gates, isStationary: Bool) -> [Action] { [] }
    mutating func gatesDidChange(_ gates: Gates) -> [Action] { [] }
    mutating func voiceDidFinish(gates: Gates) -> [Action] { [] }
}
```

- [ ] **Step 6: Register, run**

```bash
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Models/Honor/HonorTuning.swift
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Models/Honor/HonorEngine.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/HonorEngineTests -only-testing:UnitTests/WayGeometryTests 2>&1 | grep -E "error:|Executed"
```
Expected: `Executed 6 tests, with 0 failures` and the geometry suite green.

- [ ] **Step 7: Commit**

```bash
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(honor): HonorEngine position, companion clock, progress-gated arrival, soft tap"
```

---

### Task 8: `HonorMomentTracker`: triggers, voice queue, gates, drop rule

**Files:**
- Create: `Pilgrim/Models/Honor/HonorMomentTracker.swift` (move the stub out of `HonorEngine.swift`)
- Test: `UnitTests/Honor/HonorMomentTrackerTests.swift`

**Interfaces:**
- Produces the full `HonorMomentTracker` with the same signatures as the Task 7 stub, plus `var playing: WayMoment?`, `var isVoicePaused: Bool`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import CoreLocation
@testable import Pilgrim

final class HonorMomentTrackerTests: XCTestCase {

    /// 1 km straight east; a voice at 300 m, a sitting at 300 m, a second voice at 500 m, a photo at 700 m.
    private let route = (0...10).map { i in WayPoint(lat: 0, lon: Double(i) * 0.000898, alt: nil, t: Double(i) * 60) }
    private lazy var geometry = WayGeometry(route: route)
    private func at(_ meters: Double) -> WayCoordinate { WayCoordinate(lat: 0, lon: meters / 111_320) }
    private func coord(_ meters: Double, lat: Double = 0) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: meters / 111_320)
    }
    private lazy var voice1 = WayMoment(id: "voice-1", frac: 0.3, at: at(300),
        kind: .voice(endFrac: 0.35, duration: 40, kind: .spoken, media: .file("audio/1.m4a")))
    private lazy var sit1 = WayMoment(id: "sit-1", frac: 0.3, at: at(300), kind: .meditation(minutes: 12, isEstimate: false))
    private lazy var voice2 = WayMoment(id: "voice-2", frac: 0.5, at: at(500),
        kind: .voice(endFrac: 0.55, duration: 30, kind: .spoken, media: .file("audio/2.m4a")))
    private lazy var photo1 = WayMoment(id: "photo-1", frac: 0.7, at: at(700), kind: .photo(media: .file("photos/1.jpg")))

    private func tracker(voicesEnabled: Bool = true) -> HonorMomentTracker {
        HonorMomentTracker(moments: [voice1, sit1, voice2, photo1], geometry: geometry, voicesEnabled: voicesEnabled)
    }

    func testFiresOnceAndRespectsTheFracGate() {
        var t = tracker()
        // Standing at 300 m but progress says 0.1: too early (a crossing path), nothing fires.
        XCTAssertEqual(t.update(location: coord(300), progressFrac: 0.1, gates: .init(), isStationary: false), [])
        let actions = t.update(location: coord(300), progressFrac: 0.3, gates: .init(), isStationary: false)
        XCTAssertEqual(actions, [.reached(sit1), .voiceStart(voice1)])
        XCTAssertEqual(t.update(location: coord(300), progressFrac: 0.3, gates: .init(), isStationary: false), [])
    }

    func testRadiiDifferByKind() {
        var t = tracker()
        // 50 m north of the photo: inside the 60 m card radius.
        XCTAssertEqual(t.update(location: coord(700, lat: 50 / 111_320), progressFrac: 0.7, gates: .init(), isStationary: false),
                       [.reached(photo1)])
        // 50 m north of voice 2: outside the 42 m voice radius.
        XCTAssertEqual(t.update(location: coord(500, lat: 50 / 111_320), progressFrac: 0.5, gates: .init(), isStationary: false), [])
    }

    func testQueueWaitsForThePlayingVoiceThenStartsTheNext() {
        var t = tracker()
        _ = t.update(location: coord(300), progressFrac: 0.3, gates: .init(), isStationary: false)
        XCTAssertEqual(t.update(location: coord(500), progressFrac: 0.5, gates: .init(), isStationary: false), [],
                       "voice 2 is queued behind voice 1")
        XCTAssertEqual(t.voiceDidFinish(gates: .init()), [.voiceStart(voice2)])
        XCTAssertEqual(t.voiceDidFinish(gates: .init()), [])
    }

    func testSitPausesThePlayingVoiceAndResumesIt() {
        var t = tracker()
        _ = t.update(location: coord(300), progressFrac: 0.3, gates: .init(), isStationary: false)
        XCTAssertEqual(t.gatesDidChange(.init(meditating: true)), [.voicePause])
        XCTAssertTrue(t.isVoicePaused)
        XCTAssertEqual(t.gatesDidChange(.init(meditating: true)), [], "no repeat")
        XCTAssertEqual(t.gatesDidChange(.init()), [.voiceResume])
    }

    func testGatedVoiceWaitsThenStartsWhenTheGateClears() {
        var t = tracker()
        let actions = t.update(location: coord(300), progressFrac: 0.3, gates: .init(recording: true), isStationary: false)
        XCTAssertEqual(actions, [.reached(sit1)])
        XCTAssertEqual(t.gatesDidChange(.init()), [.voiceStart(voice1)])
    }

    func testQueuedVoiceDropsWhenMovingPastButNotWhileStationary() {
        var t = tracker()
        _ = t.update(location: coord(300), progressFrac: 0.3, gates: .init(recording: true), isStationary: false)
        // 320 m past the spot, standing still: exempt (and 80 m short of the photo, so no card).
        XCTAssertEqual(t.update(location: coord(620), progressFrac: 0.62, gates: .init(recording: true), isStationary: true), [])
        // Moving: dropped.
        XCTAssertEqual(t.update(location: coord(630), progressFrac: 0.63, gates: .init(recording: true), isStationary: false),
                       [.voiceDropped(voice1)])
        XCTAssertEqual(t.gatesDidChange(.init()), [])
    }

    func testVoicesDisabledStillReachesCardsAndNeverStartsAudio() {
        var t = tracker(voicesEnabled: false)
        let actions = t.update(location: coord(300), progressFrac: 0.3, gates: .init(), isStationary: false)
        XCTAssertEqual(actions, [.reached(sit1)])
        XCTAssertNil(t.playing)
    }
}
```

- [ ] **Step 2: Register and run to verify it fails**

```bash
ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/HonorMomentTrackerTests.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/HonorMomentTrackerTests 2>&1 | grep -E "error:|Executed"
```
Expected: failures (the stub returns `[]`) and a compile error on `playing`/`isVoicePaused`.

- [ ] **Step 3: Create `HonorMomentTracker.swift` and delete the stub from `HonorEngine.swift`**

```swift
import CoreLocation
import Foundation

/// Pure moment bookkeeping for an honor walk: which moments have been
/// reached, which voice is playing or waiting, and when a waiting voice is
/// abandoned. No Combine, no timers; the engine feeds it fixes and gates.
struct HonorMomentTracker {

    enum Action: Equatable {
        case reached(WayMoment)
        case voiceStart(WayMoment)
        case voicePause
        case voiceResume
        case voiceDropped(WayMoment)
    }

    struct Gates: Equatable {
        var paused = false
        var meditating = false
        var recording = false
        var externalAudio = false
        var isClosed: Bool { paused || meditating || recording || externalAudio }
    }

    private let moments: [WayMoment]
    private let geometry: WayGeometry
    private let voicesEnabled: Bool
    private var reached: Set<String> = []
    private var queue: [WayMoment] = []
    private(set) var playing: WayMoment?
    private(set) var isVoicePaused = false

    init(moments: [WayMoment], geometry: WayGeometry, voicesEnabled: Bool) {
        self.moments = moments.sorted { $0.frac < $1.frac }
        self.geometry = geometry
        self.voicesEnabled = voicesEnabled
    }

    mutating func update(
        location: CLLocationCoordinate2D,
        progressFrac: Double,
        gates: Gates,
        isStationary: Bool
    ) -> [Action] {
        var actions: [Action] = []
        let here = CLLocation(latitude: location.latitude, longitude: location.longitude)

        for moment in moments where !reached.contains(moment.id) {
            guard progressFrac >= moment.frac - HonorTuning.momentFracTolerance else { continue }
            let radius = moment.isVoice ? HonorTuning.voiceRadiusMeters : HonorTuning.momentRadiusMeters
            guard here.distance(from: place(of: moment)) <= radius else { continue }
            reached.insert(moment.id)
            if moment.isVoice {
                if voicesEnabled { queue.append(moment) }
            } else {
                actions.append(.reached(moment))
            }
        }

        if !isStationary {
            // Abandon voices the walker has left far behind, playing-but-paused included.
            let dropped = queue.filter { here.distance(from: place(of: $0)) > HonorTuning.voiceDropMeters }
            queue.removeAll { dropped.contains($0) }
            actions += dropped.map { .voiceDropped($0) }
            if let current = playing, isVoicePaused,
               here.distance(from: place(of: current)) > HonorTuning.voiceDropMeters {
                playing = nil
                isVoicePaused = false
                actions.append(.voiceDropped(current))
            }
        }

        actions += startNextIfPossible(gates: gates)
        return actions
    }

    mutating func gatesDidChange(_ gates: Gates) -> [Action] {
        if playing != nil {
            if gates.isClosed, !isVoicePaused {
                isVoicePaused = true
                return [.voicePause]
            }
            if !gates.isClosed, isVoicePaused {
                isVoicePaused = false
                return [.voiceResume]
            }
            return []
        }
        return startNextIfPossible(gates: gates)
    }

    mutating func voiceDidFinish(gates: Gates) -> [Action] {
        playing = nil
        isVoicePaused = false
        return startNextIfPossible(gates: gates)
    }

    private mutating func startNextIfPossible(gates: Gates) -> [Action] {
        guard playing == nil, !gates.isClosed, !queue.isEmpty else { return [] }
        let next = queue.removeFirst()
        playing = next
        return [.voiceStart(next)]
    }

    private func place(of moment: WayMoment) -> CLLocation {
        if let at = moment.at { return CLLocation(latitude: at.lat, longitude: at.lon) }
        let c = geometry.coordinate(atFrac: moment.frac)
        return CLLocation(latitude: c.latitude, longitude: c.longitude)
    }
}
```

- [ ] **Step 4: Register, run both engine suites**

```bash
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Models/Honor/HonorMomentTracker.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/HonorMomentTrackerTests -only-testing:UnitTests/HonorEngineTests 2>&1 | grep -E "error:|Executed"
```
Expected: `Executed 7 tests, with 0 failures` and `Executed 6 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(honor): moment triggers, voice queue, pause-and-resume, drop rule"
```

---

### Task 9: `WayVoicePlayer` and the whisper hold

**Files:**
- Create: `Pilgrim/Models/Honor/WayVoicePlayer.swift`
- Modify: `Pilgrim/Models/Audio/AudioPriorityQueue.swift:30-37`
- Test: `UnitTests/Honor/WayVoicePlayerTests.swift`

**Interfaces:**
- Produces: `protocol WayVoicePlaying: AnyObject { var onFinished: (() -> Void)? { get set }; func play(url: URL); func pause(); func resume(); func stop() }` and `final class WayVoicePlayer: NSObject, WayVoicePlaying, AVAudioPlayerDelegate` with `static let shared`, `@Published private(set) var isPlayingWayVoice`, `@Published private(set) var elapsedSeconds: TimeInterval`. `AudioPriorityQueue.playWhisper` defers while a Way voice plays and resumes the whisper when it ends. Consumer name `"honor-voice"`.

- [ ] **Step 1: Write the failing test (the seam, not the hardware)**

```swift
import XCTest
@testable import Pilgrim

final class WayVoicePlayerTests: XCTestCase {

    func testMissingFileReportsFinishedAndReleasesTheSession() {
        let player = WayVoicePlayer()
        let finished = expectation(description: "finished")
        player.onFinished = { finished.fulfill() }
        player.play(url: URL(fileURLWithPath: "/nonexistent/voice.m4a"))
        wait(for: [finished], timeout: 1)
        XCTAssertFalse(player.isPlayingWayVoice)
    }

    func testPlaysABundledTestFileAndPausesResumes() throws {
        let url = try TestAudioFile.url()
        let player = WayVoicePlayer()
        player.play(url: url)
        XCTAssertTrue(player.isPlayingWayVoice)
        player.pause()
        XCTAssertTrue(player.isPlayingWayVoice, "paused is still 'in flight' for the queue")
        player.resume()
        player.stop()
        XCTAssertFalse(player.isPlayingWayVoice)
    }
}
```

Read `UnitTests/Helpers/TestAudioFile.swift` first and use its actual accessor name if it is not `url()`.

- [ ] **Step 2: Register and run to verify it fails**

```bash
ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/WayVoicePlayerTests.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/WayVoicePlayerTests 2>&1 | grep -E "error:|Executed"
```

- [ ] **Step 3: Create `WayVoicePlayer.swift`**

```swift
import AVFoundation
import Combine
import Foundation

protocol WayVoicePlaying: AnyObject {
    var onFinished: (() -> Void)? { get set }
    func play(url: URL)
    func pause()
    func resume()
    func stop()
}

/// Plays one Way voice at a time. Modeled on AudioPriorityQueue, not on the
/// settings preview player: it ducks the soundscape, waits for a guide
/// prompt to finish before starting, and holds community whispers while
/// it plays. Consumer "honor-voice"; deactivated in every exit path.
final class WayVoicePlayer: NSObject, ObservableObject, WayVoicePlaying, AVAudioPlayerDelegate {

    static let shared = WayVoicePlayer()

    @Published private(set) var isPlayingWayVoice = false
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    var onFinished: (() -> Void)?

    private var player: AVAudioPlayer?
    private var pendingURL: URL?
    private var preDuckVolume: Float?
    private var elapsedTimer: Timer?
    private var cancellables: [AnyCancellable] = []
    private let coordinator = AudioSessionCoordinator.shared
    private let soundscape = SoundscapePlayer.shared
    private let voiceGuide = VoiceGuidePlayer.shared

    override init() {
        super.init()
        voiceGuide.playbackDidFinish
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.startPendingIfNeeded() }
            .store(in: &cancellables)
    }

    deinit { elapsedTimer?.invalidate() }

    func play(url: URL) {
        if voiceGuide.isPlaying {
            pendingURL = url
            return
        }
        start(url: url)
    }

    func pause() {
        player?.pause()
        elapsedTimer?.invalidate()
    }

    func resume() {
        guard let player else { return }
        player.play()
        startElapsedTimer()
    }

    func stop() {
        pendingURL = nil
        player?.stop()
        finish(notify: false)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in self?.finish(notify: true) }
    }

    // MARK: - Private

    private func start(url: URL) {
        stop()
        let current = soundscape.currentTargetVolume
        preDuckVolume = current
        soundscape.setVolume(current * Float(UserPreferences.voiceGuideDuckLevel.value), animated: true)
        coordinator.activate(for: .playbackOnly, consumer: "honor-voice")
        AudioPriorityQueue.shared.interruptForVoiceGuide()
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.volume = Float(UserPreferences.voiceGuideVolume.value)
            p.prepareToPlay()
            p.play()
            player = p
            isPlayingWayVoice = true
            elapsedSeconds = 0
            startElapsedTimer()
        } catch {
            print("[WayVoicePlayer] playback error: \(error)")
            finish(notify: true)
        }
    }

    private func startPendingIfNeeded() {
        guard let url = pendingURL else { return }
        pendingURL = nil
        start(url: url)
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            self.elapsedSeconds = player.currentTime
        }
    }

    private func finish(notify: Bool) {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        player = nil
        let wasPlaying = isPlayingWayVoice
        isPlayingWayVoice = false
        if let volume = preDuckVolume {
            soundscape.setVolume(volume, animated: true)
            preDuckVolume = nil
        }
        coordinator.deactivate(consumer: "honor-voice")
        if notify, wasPlaying || player == nil { onFinished?() }
    }
}
```

- [ ] **Step 4: Hold whispers while a Way voice plays**

In `AudioPriorityQueue.swift` change `playWhisper`:

```swift
    func playWhisper(url: URL, volume: Float = 0.8) {
        if voiceGuidePlayer.isPlaying || WayVoicePlayer.shared.isPlayingWayVoice {
            pendingWhisperURL = url
            return
        }
        startWhisperPlayback(url: url, volume: volume)
    }
```

and in `init`, after the existing sink, add:

```swift
        WayVoicePlayer.shared.$isPlayingWayVoice
            .removeDuplicates()
            .filter { !$0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.playPendingWhisperIfNeeded() }
            .store(in: &cancellables)
```

- [ ] **Step 5: Register, test**

```bash
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Models/Honor/WayVoicePlayer.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/WayVoicePlayerTests -only-testing:UnitTests/AudioConsumerLifecycleTests 2>&1 | grep -E "error:|Executed"
```
Expected: both green.

- [ ] **Step 6: Commit**

```bash
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(honor): WayVoicePlayer ducks, defers to guide prompts, holds whispers"
```

---

### Task 10: `WayStore`: folders, index, replies, sweep, backup exclusion

**Files:**
- Create: `Pilgrim/Models/Honor/WayStore.swift`
- Test: `UnitTests/Honor/WayStoreTests.swift`

**Interfaces:**
- Produces: `final class WayStore` with `static let shared`, `init(baseDirectory: URL)`, `save(_ way: Way) throws`, `load(id:) -> Way?`, `list() -> [Way]` (accepted shares and persisted own-walk Ways, newest `acceptedAt` first), `acceptedAt(id:) -> Date?`, `mediaDirectory(for:) -> URL`, `mediaURL(for:relative:) -> URL`, `replies(for:) -> [Int: String]`, `setReply(wayId:originN:relativePath:) throws`, `link(walkUUID:to:) throws`, `wayId(forWalk:) -> String?`, `way(forWalk:) -> Way?`, `diskUsage(id:) -> Int`, `totalDiskUsage() -> Int`, `delete(id:)`, `deleteMedia(id:)`, `sweepExpired(now:) -> [String]`, `hasMedia(id:) -> Bool`.
- Layout: `Ways/index.json` (`[walkUUID: wayId]`), `Ways/{id}/way.json`, `Ways/{id}/accepted.json` (`{"acceptedAt": Date}`), `Ways/{id}/replies.json`, `Ways/{id}/media/`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Pilgrim

final class WayStoreTests: XCTestCase {

    private var dir: URL!
    private var store: WayStore!
    private let now = Date(timeIntervalSince1970: 2_000_000)

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = WayStore(baseDirectory: dir)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func way(id: String, expires: Date?) -> Way {
        Way(id: id, source: .share(id: "abc", pageURL: URL(string: "https://walk.pilgrimapp.org/abc")!),
            title: id, departedAt: now, tzIdentifier: nil, expires: expires,
            route: [WayPoint(lat: 0, lon: 0, alt: nil, t: 0), WayPoint(lat: 0, lon: 0.001, alt: nil, t: 60)],
            totalDistanceMeters: 111, theirActiveSeconds: 60, moments: [], weather: nil)
    }

    func testSaveLoadListAndBackupExclusion() throws {
        try store.save(way(id: "share:a", expires: nil))
        XCTAssertEqual(store.load(id: "share:a")?.title, "share:a")
        XCTAssertEqual(store.list().map(\.id), ["share:a"])
        let values = try dir.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testLinkAndRepliesSurviveMediaDeletion() throws {
        try store.save(way(id: "share:a", expires: nil))
        let walk = UUID()
        try store.link(walkUUID: walk, to: "share:a")
        try store.setReply(wayId: "share:a", originN: 3, relativePath: "Recordings/x/y.m4a")
        let media = store.mediaURL(for: "share:a", relative: "audio/1.m4a")
        try FileManager.default.createDirectory(at: media.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 1024).write(to: media)
        XCTAssertGreaterThanOrEqual(store.diskUsage(id: "share:a"), 1024)
        XCTAssertTrue(store.hasMedia(id: "share:a"))
        store.deleteMedia(id: "share:a")
        XCTAssertFalse(store.hasMedia(id: "share:a"))
        XCTAssertEqual(store.wayId(forWalk: walk), "share:a")
        XCTAssertEqual(store.replies(for: "share:a"), [3: "Recordings/x/y.m4a"])
        XCTAssertEqual(store.way(forWalk: walk)?.id, "share:a")
    }

    func testSweepFollowsTheThreeRowTable() throws {
        let past = now.addingTimeInterval(-1), future = now.addingTimeInterval(86_400)
        try store.save(way(id: "share:unwalked-expired", expires: past))
        try store.save(way(id: "share:walked-expired", expires: past))
        try store.save(way(id: "share:live", expires: future))
        try store.save(Way(id: "walk:own", source: .ownWalk(UUID()), title: "own", departedAt: now, tzIdentifier: nil,
                           expires: nil, route: [], totalDistanceMeters: 0, theirActiveSeconds: 0, moments: [], weather: nil))
        try store.link(walkUUID: UUID(), to: "share:walked-expired")
        for id in ["share:unwalked-expired", "share:walked-expired", "share:live"] {
            let media = store.mediaURL(for: id, relative: "audio/1.m4a")
            try FileManager.default.createDirectory(at: media.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: media)
        }
        let swept = store.sweepExpired(now: now)
        XCTAssertEqual(Set(swept), ["share:unwalked-expired", "share:walked-expired"])
        XCTAssertNil(store.load(id: "share:unwalked-expired"), "whole folder gone")
        XCTAssertNotNil(store.load(id: "share:walked-expired"), "way.json kept")
        XCTAssertFalse(store.hasMedia(id: "share:walked-expired"), "media gone")
        XCTAssertTrue(store.hasMedia(id: "share:live"))
        XCTAssertNotNil(store.load(id: "walk:own"))
    }

    func testDeleteRemovesEverythingAndTheIndexLink() throws {
        try store.save(way(id: "share:a", expires: nil))
        let walk = UUID()
        try store.link(walkUUID: walk, to: "share:a")
        store.delete(id: "share:a")
        XCTAssertNil(store.load(id: "share:a"))
        XCTAssertNil(store.wayId(forWalk: walk))
        XCTAssertEqual(store.totalDiskUsage(), 0)
    }
}
```

- [ ] **Step 2: Register and run to verify it fails**

```bash
ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/WayStoreTests.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/WayStoreTests 2>&1 | grep -E "error:|Executed"
```

- [ ] **Step 3: Create `WayStore.swift`**

```swift
import Foundation

/// Application Support/Ways: one folder per Way, an index from walk UUID to
/// Way id, and the sharer's-promise sweep. The whole tree is excluded from
/// iCloud backup so a restore can never resurrect swept voices.
final class WayStore {

    static let shared: WayStore = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return WayStore(baseDirectory: appSupport.appendingPathComponent("Ways", isDirectory: true))
    }()

    private let fileManager = FileManager.default
    private let base: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private struct Accepted: Codable { let acceptedAt: Date }

    init(baseDirectory: URL) {
        base = baseDirectory
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        var url = base
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    // MARK: - Ways

    func save(_ way: Way) throws {
        let dir = directory(for: way.id)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        try encoder.encode(way).write(to: dir.appendingPathComponent("way.json"), options: .atomic)
        let accepted = dir.appendingPathComponent("accepted.json")
        if !fileManager.fileExists(atPath: accepted.path) {
            try encoder.encode(Accepted(acceptedAt: Date())).write(to: accepted, options: .atomic)
        }
    }

    func load(id: String) -> Way? {
        guard let data = try? Data(contentsOf: directory(for: id).appendingPathComponent("way.json")) else { return nil }
        return try? decoder.decode(Way.self, from: data)
    }

    func acceptedAt(id: String) -> Date? {
        guard let data = try? Data(contentsOf: directory(for: id).appendingPathComponent("accepted.json")),
              let accepted = try? decoder.decode(Accepted.self, from: data) else { return nil }
        return accepted.acceptedAt
    }

    func list() -> [Way] {
        let ids = (try? fileManager.contentsOfDirectory(atPath: base.path)) ?? []
        return ids.compactMap { load(id: $0) }
            .sorted { (acceptedAt(id: $0.id) ?? .distantPast) > (acceptedAt(id: $1.id) ?? .distantPast) }
    }

    func delete(id: String) {
        try? fileManager.removeItem(at: directory(for: id))
        var index = loadIndex()
        index = index.filter { $0.value != id }
        saveIndex(index)
    }

    // MARK: - Media

    func mediaDirectory(for id: String) -> URL {
        directory(for: id).appendingPathComponent("media", isDirectory: true)
    }

    func mediaURL(for id: String, relative: String) -> URL {
        mediaDirectory(for: id).appendingPathComponent(relative)
    }

    func hasMedia(id: String) -> Bool {
        let contents = (try? fileManager.contentsOfDirectory(atPath: mediaDirectory(for: id).path)) ?? []
        return !contents.isEmpty
    }

    func deleteMedia(id: String) {
        try? fileManager.removeItem(at: mediaDirectory(for: id))
    }

    func diskUsage(id: String) -> Int {
        fileManager.sizeOfDirectory(at: directory(for: id)) ?? 0
    }

    func totalDiskUsage() -> Int {
        list().reduce(0) { $0 + diskUsage(id: $1.id) }
    }

    // MARK: - Replies and the walk index

    func replies(for id: String) -> [Int: String] {
        guard let data = try? Data(contentsOf: directory(for: id).appendingPathComponent("replies.json")),
              let map = try? decoder.decode([String: String].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: map.compactMap { key, value in Int(key).map { ($0, value) } })
    }

    func setReply(wayId: String, originN: Int, relativePath: String) throws {
        var map = replies(for: wayId)
        map[originN] = relativePath
        let encodable = Dictionary(uniqueKeysWithValues: map.map { (String($0.key), $0.value) })
        try encoder.encode(encodable).write(to: directory(for: wayId).appendingPathComponent("replies.json"), options: .atomic)
    }

    func link(walkUUID: UUID, to wayId: String) throws {
        var index = loadIndex()
        index[walkUUID.uuidString] = wayId
        saveIndex(index)
    }

    func wayId(forWalk uuid: UUID) -> String? { loadIndex()[uuid.uuidString] }

    func way(forWalk uuid: UUID) -> Way? { wayId(forWalk: uuid).flatMap(load(id:)) }

    private var walkedIds: Set<String> { Set(loadIndex().values) }

    // MARK: - Sweep

    /// Share Ways past their expiry: unwalked → whole folder; walked → media
    /// only. Own-walk Ways never expire. Returns the ids touched.
    @discardableResult
    func sweepExpired(now: Date) -> [String] {
        let walked = walkedIds
        var touched: [String] = []
        for way in list() {
            guard let expires = way.expires, expires <= now else { continue }
            if walked.contains(way.id) {
                deleteMedia(id: way.id)
            } else {
                try? fileManager.removeItem(at: directory(for: way.id))
            }
            touched.append(way.id)
        }
        return touched
    }

    // MARK: - Private

    private func directory(for id: String) -> URL {
        base.appendingPathComponent(id, isDirectory: true)
    }

    private var indexURL: URL { base.appendingPathComponent("index.json") }

    private func loadIndex() -> [String: String] {
        guard let data = try? Data(contentsOf: indexURL) else { return [:] }
        return (try? decoder.decode([String: String].self, from: data)) ?? [:]
    }

    private func saveIndex(_ index: [String: String]) {
        try? encoder.encode(index).write(to: indexURL, options: .atomic)
    }
}
```

`list()` must skip `index.json`: `load(id:)` returns nil for it because there is no `way.json` inside a file, which is the intended behavior.

- [ ] **Step 4: Register, test**

```bash
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Models/Honor/WayStore.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/WayStoreTests 2>&1 | grep -E "error:|Executed"
```
Expected: `Executed 4 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(honor): WayStore with index, replies, expiry sweep, and backup exclusion"
```

---

### Task 11: `ActiveWalkViewModel+Honor`: lifecycle, events, persistence, replies

**Files:**
- Modify: `Pilgrim/Scenes/ActiveWalk/ActiveWalkViewModel.swift:10` (add `way`), `:77-88` (honor state beside seek state), `:124-163` (init), `:297-304` (`startRecording`), `:310-333` (`stop`/`cancel`)
- Create: `Pilgrim/Scenes/ActiveWalk/ActiveWalkViewModel+Honor.swift`
- Modify: `Pilgrim/Models/Haptics/HapticManager.swift:85-96`, `:145-147`
- Modify: `Pilgrim/Models/Preferences/UserPreferences.swift:75`
- Test: `UnitTests/Honor/ActiveWalkHonorTests.swift`

**Interfaces:**
- Consumes: `HonorEngine`, `WayVoicePlaying`, `WayStore`, `HonorPersistence`.
- Produces: `ActiveWalkViewModel.init(mode:way:seekAccuracy:seekSenses:honorSenses:)`; `let way: Way?`; `@Published honorEngine: HonorEngine?`, `honorCards: [WayMoment]` (pending, trigger order), `activeVoice: WayMoment?`, `isVoicePaused: Bool`, `honorArrival: HonorArrivalCard?`; `struct HonorSenses { makeVoicePlayer, isAppActive, resolveMediaURL }`; `func dismissTopCard()`, `func showCard(for moment: WayMoment)`, `func replyHere(to voice: WayMoment)`, `func mediaURL(for media: WayMedia) -> URL?`, `func startMeditation(minutes:)` (wraps `startMeditation()` and sets the timer preset), `writeHonorMarkerEventIfNeeded()`, `handleHonorEvent(_:)`, `teardownHonor()`, `var honorGlance: HonorGlanceState?` (Task 16 wires it).
- `UserPreferences.honorVoicesEnabled` (Bool, default true), `honorSoftTapEnabled` (Bool, default false). `HapticPattern.honorOffWay`, `.honorArrival`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import Combine
import CoreLocation
@testable import Pilgrim

final class ActiveWalkHonorTests: XCTestCase {

    private final class SpyVoicePlayer: WayVoicePlaying {
        var onFinished: (() -> Void)?
        var played: [URL] = []
        var pauses = 0, resumes = 0, stops = 0
        func play(url: URL) { played.append(url) }
        func pause() { pauses += 1 }
        func resume() { resumes += 1 }
        func stop() { stops += 1 }
    }

    private var player: SpyVoicePlayer!
    private var vm: ActiveWalkViewModel!

    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func way() -> Way {
        let route = (0...10).map { i in WayPoint(lat: 0, lon: Double(i) * 0.000898, alt: nil, t: Double(i) * 60) }
        let voice = WayMoment(id: "voice-1", frac: 0.3, at: WayCoordinate(lat: 0, lon: 300 / 111_320),
                              kind: .voice(endFrac: 0.35, duration: 20, kind: .spoken, media: .recording(relativePath: "Recordings/x.m4a")))
        let sit = WayMoment(id: "sit-1", frac: 0.5, at: WayCoordinate(lat: 0, lon: 500 / 111_320),
                            kind: .meditation(minutes: 7, isEstimate: false))
        return Way(id: "walk:test", source: .ownWalk(UUID()), title: "Test way", departedAt: start, tzIdentifier: nil,
                   expires: nil, route: route, totalDistanceMeters: 1000, theirActiveSeconds: 600,
                   moments: [voice, sit], weather: nil)
    }

    override func setUp() {
        player = SpyVoicePlayer()
        var senses = HonorSenses()
        senses.makeVoicePlayer = { [player] in player! }
        senses.isAppActive = { false }
        vm = ActiveWalkViewModel(mode: .honor, way: way(), honorSenses: senses)
        settleCombineSchedulers()
    }

    override func tearDown() {
        vm.cancel()
        vm = nil
    }

    private func fix(lon: Double, seconds: Double) -> TempRouteDataSample {
        TempRouteDataSample(uuid: nil, timestamp: start.addingTimeInterval(seconds), latitude: 0, longitude: lon,
                            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, speed: 1.4, direction: 90)
    }

    func testEngineBootsOnRecordingStartAndWritesTheMarkerEvent() {
        vm.startRecording()
        XCTAssertNotNil(vm.honorEngine)
        XCTAssertTrue(vm.builder.workoutEvents.contains { $0.eventType == .honorMode })
    }

    func testVoicePlaysWhereItWasSpokenAndSitOffersACard() {
        vm.startRecording()
        vm.currentLocation = fix(lon: 0, seconds: 0)
        vm.currentLocation = fix(lon: 300 / 111_320, seconds: 200)
        XCTAssertEqual(player.played.count, 1)
        XCTAssertEqual(vm.activeVoice?.id, "voice-1")
        vm.currentLocation = fix(lon: 500 / 111_320, seconds: 400)
        XCTAssertEqual(vm.honorCards.first?.id, "sit-1")
        vm.dismissTopCard()
        XCTAssertTrue(vm.honorCards.isEmpty)
    }

    func testMeditationPausesTheVoiceAndResumesAfter() {
        vm.startRecording()
        vm.currentLocation = fix(lon: 0, seconds: 0)
        vm.currentLocation = fix(lon: 300 / 111_320, seconds: 200)
        vm.startMeditation()
        XCTAssertEqual(player.pauses, 1)
        XCTAssertTrue(vm.isVoicePaused)
        vm.endMeditationSilently()
        XCTAssertEqual(player.resumes, 1)
        XCTAssertFalse(vm.isVoicePaused)
    }

    func testArrivalWritesEventAndReservedWaypoint() {
        vm.startRecording()
        vm.honorEngine?.updateActiveDuration(500)
        for i in 0...10 { vm.currentLocation = fix(lon: Double(i) * 0.000898, seconds: Double(i) * 60) }
        for i in 0..<3 { vm.currentLocation = fix(lon: 10 * 0.000898, seconds: 700 + Double(i)) }
        XCTAssertTrue(vm.builder.workoutEvents.contains { $0.eventType == .honorArrival })
        XCTAssertEqual(vm.waypoints.filter(HonorPersistence.isArrivalWaypoint).count, 1)
        XCTAssertEqual(vm.waypoints.first?.label, HonorPersistence.arrivalWaypointLabel(wayTitle: "Test way"))
        XCTAssertNotNil(vm.honorArrival)
    }

    func testStopTearsDownThePlayer() {
        vm.startRecording()
        vm.stop()
        XCTAssertGreaterThanOrEqual(player.stops, 1)
        XCTAssertNil(vm.honorEngine)
    }
}
```

`builder.workoutEvents` must be readable; check `WalkBuilder` for its events accessor name (`grep -n "workoutEvents" Pilgrim/Models/Walk/WalkBuilder/WalkBuilder.swift`) and use it. The seek tests in `UnitTests/Seek/ActiveWalkSeekTests.swift` show how they assert on the `.seekMode` event; copy that access path.

- [ ] **Step 2: Register and run to verify it fails**

```bash
ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/ActiveWalkHonorTests.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/ActiveWalkHonorTests 2>&1 | grep -E "error:|Executed"
```

- [ ] **Step 3: Preferences and haptics**

`UserPreferences.swift`, after the seek block:
```swift
    static let honorVoicesEnabled = UserPreference.Required<Bool>(key: "honorVoicesEnabled", defaultValue: true)
    static let honorSoftTapEnabled = UserPreference.Required<Bool>(key: "honorSoftTapEnabled", defaultValue: false)
```

`HapticManager.swift`: add `case honorOffWay` and `case honorArrival` to `HapticPattern`, and in `fire()` add:
```swift
        case .honorOffWay:
            let generator = UIImpactFeedbackGenerator(style: .soft)
            generator.prepare()
            generator.impactOccurred()

        case .honorArrival:
            if !Self.playSeekArrival() {
                let generator = UINotificationFeedbackGenerator()
                generator.prepare()
                generator.notificationOccurred(.success)
            }
```
(the arrival shares Seek's Core Haptics arrival pattern deliberately; the bowl is the same bowl.)

- [ ] **Step 4: View model stored state and init**

In `ActiveWalkViewModel.swift` add after `let mode: WalkMode`:
```swift
    /// The Way an honor walk follows; nil for every other mode.
    let way: Way?
```
Add after the seek state block (`:88`):
```swift
    // Honor lifecycle lives in ActiveWalkViewModel+Honor.swift.
    @Published var honorEngine: HonorEngine?
    @Published var honorCards: [WayMoment] = []
    @Published var activeVoice: WayMoment?
    @Published var isVoicePaused = false
    @Published var honorArrival: HonorArrivalCard?
    @Published var heardVoiceIDs: Set<String> = []
    var pendingReplyOrigin: WayMoment?
    let honorSenses: HonorSenses
    var wayVoicePlayer: WayVoicePlaying?
    var honorGeneration = 0
    var honorCancellables: [AnyCancellable] = []
```
Change the initializer signature to:
```swift
    init(
        mode: WalkMode = .wander,
        way: Way? = nil,
        seekAccuracy: SeekAccuracyProviding = SeekLocationAccuracyProvider(),
        seekSenses: SeekSenses = SeekSenses(),
        honorSenses: HonorSenses = HonorSenses()
    ) {
        self.mode = mode
        self.way = way
        self.honorSenses = honorSenses
```
and after `if mode == .seek { bindSeekLifecycle() }` add nothing; the honor engine boots from `startRecording`. In `startRecording()` add `writeHonorMarkerEventIfNeeded()` and `startHonorEngineIfNeeded()` right after `writeSeekMarkerEventIfNeeded()`. In `stop()` and `cancel()` add `teardownHonor()` right after `teardownSeek()`. In `startMeditation()` nothing changes: the engine reads `$isMeditating`.

- [ ] **Step 5: Create `ActiveWalkViewModel+Honor.swift`**

```swift
import Combine
import CoreLocation
import Foundation
import UIKit

/// Injectable honor side effects, like SeekSenses.
struct HonorSenses {
    var makeVoicePlayer: () -> WayVoicePlaying = { WayVoicePlayer.shared }
    var isAppActive: () -> Bool = { UIApplication.shared.applicationState == .active }
    var store: () -> WayStore = { WayStore.shared }
}

struct HonorArrivalCard: Equatable {
    let wayTitle: String
    let voicesHeard: Int
    let placesPassed: Int
}

extension ActiveWalkViewModel {

    func writeHonorMarkerEventIfNeeded() {
        guard mode == .honor, way != nil else { return }
        builder.addWorkoutEvent(TempWalkEvent(uuid: nil, eventType: .honorMode, timestamp: Date()))
    }

    func startHonorEngineIfNeeded() {
        guard mode == .honor, let way, honorEngine == nil else { return }
        honorGeneration += 1
        let engine = HonorEngine(
            way: way,
            softTapEnabled: UserPreferences.honorSoftTapEnabled.value,
            voicesEnabled: UserPreferences.honorVoicesEnabled.value && UserPreferences.soundsEnabled.value
        )
        let player = honorSenses.makeVoicePlayer()
        player.onFinished = { [weak self] in self?.honorEngine?.voiceDidFinish() }
        wayVoicePlayer = player

        engine.bind(
            locations: honorLocationFixes,
            activeDuration: $activeDurationSeconds.eraseToAnyPublisher(),
            isPaused: $status.map { $0 != .recording }.eraseToAnyPublisher(),
            isMeditating: $isMeditating.eraseToAnyPublisher(),
            isRecordingVoice: $isRecordingVoice.eraseToAnyPublisher(),
            externalAudio: AudioPriorityQueue.shared.$isPlayingWhisper.eraseToAnyPublisher()
        )
        engine.events
            .sink { [weak self] event in self?.handleHonorEvent(event) }
            .store(in: &honorCancellables)
        honorEngine = engine
    }

    func teardownHonor() {
        honorGeneration += 1
        honorCancellables.removeAll()
        honorEngine?.stop()
        honorEngine = nil
        wayVoicePlayer?.stop()
        wayVoicePlayer = nil
        activeVoice = nil
        isVoicePaused = false
    }

    // MARK: - Events

    func handleHonorEvent(_ event: HonorEngineEvent) {
        switch event {
        case .momentReached(let moment):
            if !honorCards.contains(moment) { honorCards.append(moment) }
            fireHonorHaptic(.waypointDropped)

        case .voiceStart(let moment):
            guard case .voice(_, _, _, let media) = moment.kind, let url = mediaURL(for: media) else {
                honorEngine?.voiceDidFinish()
                return
            }
            activeVoice = moment
            isVoicePaused = false
            heardVoiceIDs.insert(moment.id)
            wayVoicePlayer?.play(url: url)

        case .voicePause:
            isVoicePaused = true
            wayVoicePlayer?.pause()

        case .voiceResume:
            isVoicePaused = false
            wayVoicePlayer?.resume()

        case .voiceDropped(let moment):
            if activeVoice == moment {
                wayVoicePlayer?.stop()
                activeVoice = nil
                isVoicePaused = false
            }

        case .softTap:
            fireHonorHaptic(.honorOffWay)

        case .arrived:
            recordHonorArrival()
            fireHonorHaptic(.honorArrival)
        }
    }

    /// The persistence commit happens before any ritual effect, as in Seek.
    private func recordHonorArrival() {
        guard let way else { return }
        builder.addWorkoutEvent(TempWalkEvent(uuid: nil, eventType: .honorArrival, timestamp: Date()))
        addWaypoint(label: HonorPersistence.arrivalWaypointLabel(wayTitle: way.title),
                    icon: HonorPersistence.arrivalWaypointIcon)
        honorArrival = HonorArrivalCard(wayTitle: way.title, voicesHeard: heardVoiceIDs.count,
                                        placesPassed: way.moments.count - way.voiceCount)
    }

    // MARK: - Cards, media, replies

    func dismissTopCard() {
        if !honorCards.isEmpty { honorCards.removeFirst() }
    }

    /// A tapped pin jumps the queue; pending cards resume after it.
    func showCard(for moment: WayMoment) {
        honorCards.removeAll { $0 == moment }
        honorCards.insert(moment, at: 0)
    }

    func mediaURL(for media: WayMedia) -> URL? {
        switch media {
        case .recording(let relativePath):
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            return docs.appendingPathComponent(relativePath)
        case .file(let relative):
            guard let way else { return nil }
            let url = honorSenses.store().mediaURL(for: way.id, relative: relative)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        case .photoAsset:
            return nil
        }
    }

    /// Starts a recording answering `voice`. When that recording completes,
    /// `bindCompletedRecordings` (ActiveWalkViewModel.swift) has it; the
    /// mapping is written by `recordReplyIfPending()` from the completed list.
    func replyHere(to voice: WayMoment) {
        pendingReplyOrigin = voice
        if !isRecordingVoice { toggleVoiceRecording() }
    }

    func recordReplyIfPending(latestRecording: TempVoiceRecording) {
        guard let way, let origin = pendingReplyOrigin,
              let n = Int(origin.id.replacingOccurrences(of: "voice-", with: "")) else { return }
        pendingReplyOrigin = nil
        try? honorSenses.store().setReply(wayId: way.id, originN: n, relativePath: latestRecording.fileRelativePath)
    }

    func startMeditation(minutes: Int) {
        UserPreferences.meditationTimerMinutes.value = minutes
        startMeditation()
    }

    // MARK: - Private

    private func fireHonorHaptic(_ pattern: HapticPattern) {
        guard honorSenses.isAppActive() else { return }
        pattern.fire()
    }

    private var honorLocationFixes: AnyPublisher<CLLocation, Never> {
        $currentLocation
            .compactMap { sample -> CLLocation? in
                guard let sample else { return nil }
                return CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude),
                    altitude: sample.altitude, horizontalAccuracy: sample.horizontalAccuracy,
                    verticalAccuracy: sample.verticalAccuracy, course: sample.direction,
                    speed: sample.speed, timestamp: sample.timestamp)
            }
            .eraseToAnyPublisher()
    }
}
```

One thing this extension needs from the main file: a meditation timer preference. Check `grep -rn "meditationTimerMinutes\|timerMinutes\|meditationDuration" Pilgrim/Models/Preferences/UserPreferences.swift Pilgrim/Scenes/ActiveWalk/MeditationView.swift`. If the app has no preset preference (the timer is open-ended), replace `startMeditation(minutes:)` with a stored `var suggestedMeditationMinutes: Int?` set before `startMeditation()`, and let `MeditationView` show it as the countdown target when present. Also wire replies: in `bindCompletedRecordings` (main file `:490-497`) call `self?.recordReplyIfPending(latestRecording:)` with `recordings.last` when the count grew.

- [ ] **Step 6: Run the tests**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/ActiveWalkHonorTests -only-testing:UnitTests/ActiveWalkSeekTests 2>&1 | grep -E "error:|Executed"
```
Expected: `Executed 5 tests, with 0 failures`; the Seek VM suite still green.

- [ ] **Step 7: Commit**

```bash
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(honor): engine lifecycle, voices at places, cards, arrival persistence in the view model"
```

---

### Task 12: Map rendering: ghost line, companion dot, way pins

**Files:**
- Create: `Pilgrim/Views/PilgrimMapView+HonorWay.swift`
- Modify: `Pilgrim/Models/Walk/MapManagement/PilgrimAnnotation.swift:9-23`
- Modify: `Pilgrim/Views/PilgrimMapView.swift:26-27` (inputs), `:54-93` (init), `:161-163` (style reload), `:207-208` (updateUIView), `:394` and `:437-489` (`buildCircles`/`buildPoints`), `:687` (tap), `:673-675` (foreground flush)
- Modify: `Pilgrim/Views/MapGlyphImageBuilder.swift` (add `.wayVoice`, `.wayPhoto`, `.wayRest`, `.waySit`, `.companion` glyphs)
- Test: `UnitTests/Honor/HonorWayRenderingTests.swift`

**Interfaces:**
- Produces: `PilgrimMapView` inputs `honorWay: HonorWayState?` and `companion: CLLocationCoordinate2D?`; `struct HonorWayState: Equatable { let routeCoordinates: [CLLocationCoordinate2D]; let id: String }`; `PilgrimAnnotation.Kind` cases `.wayVoice(id: String, heard: Bool)`, `.wayPhoto(id: String)`, `.wayRest(id: String, minutes: Int)`, `.waySit(id: String, minutes: Int)`, `.wayWaypoint(id: String, label: String, icon: String)`; `HonorWayRendering.lineLayerID == "honor-way-line"`, `sourceID == "honor-way-source"`, `companionLayerID == "honor-companion"`, `companionSourceID == "honor-companion-source"`; `static func wayPins(for way: Way, heardVoiceIDs: Set<String>) -> [PilgrimAnnotation]`.

- [ ] **Step 1: Write the failing test (pure pin mapping; Mapbox is verified on device)**

```swift
import XCTest
@testable import Pilgrim

final class HonorWayRenderingTests: XCTestCase {

    func testWayPinsMapEveryMomentKindAndUseTrueCoordinates() {
        let at = WayCoordinate(lat: 42.1, lon: -8.2)
        let moments = [
            WayMoment(id: "voice-1", frac: 0.1, at: at, kind: .voice(endFrac: 0.2, duration: 5, kind: .spoken, media: .file("audio/1.m4a"))),
            WayMoment(id: "photo-1", frac: 0.2, at: at, kind: .photo(media: .file("photos/1.jpg"))),
            WayMoment(id: "rest-1", frac: 0.3, at: at, kind: .rest(minutes: 4)),
            WayMoment(id: "sit-1", frac: 0.4, at: at, kind: .meditation(minutes: 9, isEstimate: true)),
            WayMoment(id: "waypoint-1", frac: 0.5, at: nil, kind: .waypoint(label: "Oak", icon: "leaf")),
        ]
        let route = [WayPoint(lat: 0, lon: 0, alt: nil, t: 0), WayPoint(lat: 0, lon: 0.001, alt: nil, t: 60)]
        let way = Way(id: "walk:t", source: .ownWalk(UUID()), title: "t", departedAt: Date(), tzIdentifier: nil, expires: nil,
                      route: route, totalDistanceMeters: 111, theirActiveSeconds: 60, moments: moments, weather: nil)
        let pins = PilgrimMapView.wayPins(for: way, heardVoiceIDs: ["voice-1"])
        XCTAssertEqual(pins.count, 5)
        XCTAssertEqual(pins[0].kind, .wayVoice(id: "voice-1", heard: true))
        XCTAssertEqual(pins[0].coordinate.latitude, 42.1)
        XCTAssertEqual(pins[1].kind, .wayPhoto(id: "photo-1"))
        XCTAssertEqual(pins[2].kind, .wayRest(id: "rest-1", minutes: 4))
        XCTAssertEqual(pins[3].kind, .waySit(id: "sit-1", minutes: 9))
        XCTAssertEqual(pins[4].kind, .wayWaypoint(id: "waypoint-1", label: "Oak", icon: "leaf"))
        XCTAssertEqual(pins[4].coordinate.longitude, 0.0005, accuracy: 0.00001, "frac fallback when `at` is nil")
    }
}
```

- [ ] **Step 2: Register and run to verify it fails**

```bash
ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/HonorWayRenderingTests.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/HonorWayRenderingTests 2>&1 | grep -E "error:|Executed"
```

- [ ] **Step 3: Annotation kinds and glyphs**

`PilgrimAnnotation.Kind` gains:
```swift
        /// Moments of a Way being honored: faded versions of the walker's own marks.
        case wayVoice(id: String, heard: Bool)
        case wayPhoto(id: String)
        case wayRest(id: String, minutes: Int)
        case waySit(id: String, minutes: Int)
        case wayWaypoint(id: String, label: String, icon: String)
```

`MapGlyphImageBuilder.swift`: read the file, then add `case wayMark(symbol: String, tint: UIColor)` to `MapGlyph` and a `case companion` that draws a 12 pt stone disc at 0.6 alpha with a 1.5 pt white stroke; `cacheKey` includes the symbol name and tint hex. `wayMark` renders the SF Symbol `symbol` at the given size in `tint` at 0.55 alpha inside a 0.9-alpha parchment disc, so way pins read as faded next to live pins.

- [ ] **Step 4: Create `PilgrimMapView+HonorWay.swift`**

```swift
import CoreLocation
import MapboxMaps
import UIKit

struct HonorWayState: Equatable {
    let id: String
    let routeCoordinates: [CLLocationCoordinate2D]

    static func == (lhs: HonorWayState, rhs: HonorWayState) -> Bool {
        lhs.id == rhs.id && lhs.routeCoordinates.count == rhs.routeCoordinates.count
    }
}

/// Coordinator-owned bookkeeping for the ghost line and companion.
final class HonorWayRenderer {
    var pendingWay: HonorWayState?
    var pendingCompanion: CLLocationCoordinate2D?
    var appliedWayID: String?
    var companionInstalled = false
    var lastCompanionUpdate: TimeInterval = 0

    func resetForStyleReload() {
        appliedWayID = nil
        companionInstalled = false
    }
}

extension PilgrimMapView {

    enum HonorWayRendering {
        static let sourceID = "honor-way-source"
        static let lineLayerID = "honor-way-line"
        static let companionSourceID = "honor-companion-source"
        static let companionLayerID = "honor-companion"
        static let lineColor = UIColor(hex: "#8A8175")
        static let lineOpacity = 0.35
        static let lineWidth = 4.0
        static let companionRadius = 6.0
        static let companionOpacity = 0.6
        static let companionUpdateInterval: TimeInterval = 2
    }

    static func wayPins(for way: Way, heardVoiceIDs: Set<String>) -> [PilgrimAnnotation] {
        let geometry = WayGeometry(route: way.route)
        return way.moments.map { moment in
            let coordinate = moment.at.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                ?? geometry.coordinate(atFrac: moment.frac)
            let kind: PilgrimAnnotation.Kind
            switch moment.kind {
            case .voice: kind = .wayVoice(id: moment.id, heard: heardVoiceIDs.contains(moment.id))
            case .photo: kind = .wayPhoto(id: moment.id)
            case .rest(let minutes): kind = .wayRest(id: moment.id, minutes: minutes)
            case .meditation(let minutes, _): kind = .waySit(id: moment.id, minutes: minutes)
            case .waypoint(let label, let icon): kind = .wayWaypoint(id: moment.id, label: label, icon: icon)
            }
            return PilgrimAnnotation(coordinate: coordinate, kind: kind)
        }
    }

    static func applyHonorWay(
        _ way: HonorWayState?,
        companion: CLLocationCoordinate2D?,
        on mapView: MBMapView,
        coordinator: Coordinator
    ) {
        let renderer = coordinator.honorWayRenderer
        renderer.pendingWay = way
        renderer.pendingCompanion = companion
        guard coordinator.shouldRender, mapView.mapboxMap.isStyleLoaded else { return }
        applyGhostLine(way, on: mapView, renderer: renderer)
        applyCompanion(companion, on: mapView, renderer: renderer)
    }

    /// Called from `onStyleLoaded` and the foreground flush: layers are gone, reinstall from pending state.
    static func reinstallHonorWay(on mapView: MBMapView, coordinator: Coordinator) {
        let renderer = coordinator.honorWayRenderer
        renderer.resetForStyleReload()
        applyHonorWay(renderer.pendingWay, companion: renderer.pendingCompanion, on: mapView, coordinator: coordinator)
    }

    private static func applyGhostLine(_ way: HonorWayState?, on mapView: MBMapView, renderer: HonorWayRenderer) {
        // Self-heal: a lock/unlock can strip runtime layers without a style event.
        if renderer.appliedWayID != nil, !mapView.mapboxMap.layerExists(withId: HonorWayRendering.lineLayerID) {
            renderer.appliedWayID = nil
        }
        guard let way else {
            removeGhostLine(from: mapView)
            renderer.appliedWayID = nil
            return
        }
        guard renderer.appliedWayID != way.id else { return }
        removeGhostLine(from: mapView)
        do {
            var source = GeoJSONSource(id: HonorWayRendering.sourceID)
            source.data = .feature(Feature(geometry: .lineString(LineString(way.routeCoordinates))))
            try mapView.mapboxMap.addSource(source)
            var layer = LineLayer(id: HonorWayRendering.lineLayerID, source: HonorWayRendering.sourceID)
            layer.lineWidth = .constant(HonorWayRendering.lineWidth)
            layer.lineCap = .constant(.round)
            layer.lineJoin = .constant(.round)
            layer.lineOpacity = .constant(HonorWayRendering.lineOpacity)
            layer.lineColor = .constant(StyleColor(HonorWayRendering.lineColor))
            let position: LayerPosition? = mapView.mapboxMap.layerExists(withId: "pilgrim-route-casing")
                ? .below("pilgrim-route-casing") : nil
            try mapView.mapboxMap.addLayer(layer, layerPosition: position)
            renderer.appliedWayID = way.id
        } catch {
            print("[PilgrimMapView] honor way install failed: \(error)")
        }
    }

    private static func applyCompanion(_ companion: CLLocationCoordinate2D?, on mapView: MBMapView, renderer: HonorWayRenderer) {
        guard let companion else {
            removeCompanion(from: mapView)
            renderer.companionInstalled = false
            return
        }
        let feature = Feature(geometry: .point(Point(companion)))
        if renderer.companionInstalled, mapView.mapboxMap.layerExists(withId: HonorWayRendering.companionLayerID) {
            let now = CACurrentMediaTime()
            guard now - renderer.lastCompanionUpdate >= HonorWayRendering.companionUpdateInterval else { return }
            renderer.lastCompanionUpdate = now
            mapView.mapboxMap.updateGeoJSONSource(withId: HonorWayRendering.companionSourceID, geoJSON: .feature(feature))
            return
        }
        removeCompanion(from: mapView)
        do {
            var source = GeoJSONSource(id: HonorWayRendering.companionSourceID)
            source.data = .feature(feature)
            try mapView.mapboxMap.addSource(source)
            var layer = CircleLayer(id: HonorWayRendering.companionLayerID, source: HonorWayRendering.companionSourceID)
            layer.circleRadius = .constant(HonorWayRendering.companionRadius)
            layer.circleColor = .constant(StyleColor(HonorWayRendering.lineColor))
            layer.circleOpacity = .constant(HonorWayRendering.companionOpacity)
            layer.circleStrokeColor = .constant(StyleColor(.white))
            layer.circleStrokeWidth = .constant(1.5)
            layer.circlePitchAlignment = .constant(.map)
            let position: LayerPosition? = mapView.mapboxMap.layerExists(withId: "pilgrim-route-layer")
                ? .above("pilgrim-route-layer") : nil
            try mapView.mapboxMap.addLayer(layer, layerPosition: position)
            renderer.companionInstalled = true
            renderer.lastCompanionUpdate = CACurrentMediaTime()
        } catch {
            print("[PilgrimMapView] companion install failed: \(error)")
        }
    }

    private static func removeGhostLine(from mapView: MBMapView) {
        try? mapView.mapboxMap.removeLayer(withId: HonorWayRendering.lineLayerID)
        try? mapView.mapboxMap.removeSource(withId: HonorWayRendering.sourceID)
    }

    private static func removeCompanion(from mapView: MBMapView) {
        try? mapView.mapboxMap.removeLayer(withId: HonorWayRendering.companionLayerID)
        try? mapView.mapboxMap.removeSource(withId: HonorWayRendering.companionSourceID)
    }
}
```

`try?` on `removeLayer` of a missing layer throws harmlessly; guard with `layerExists` if the SDK logs noisily.

- [ ] **Step 5: Wire `PilgrimMapView`**

- Inputs after `seekPulse`: `var honorWay: HonorWayState? = nil` and `var companion: CLLocationCoordinate2D? = nil`; add both as the LAST two parameters of the explicit `init` with `nil` defaults, so every existing call site compiles unchanged and new call sites pass them as trailing arguments (Swift requires argument order to match the declaration).
- `Coordinator` gains `let honorWayRenderer = HonorWayRenderer()`.
- In `onStyleLoaded` after `Self.reinstallSeekFog(...)`: `Self.reinstallHonorWay(on: mapView, coordinator: coordinator)`.
- In `updateUIView` after `Self.applySeekFog(...)`: `Self.applyHonorWay(honorWay, companion: companion, on: mapView, coordinator: context.coordinator)`.
- In `refreshRenderState` next to `flushDeferredSeekFog`: `PilgrimMapView.reinstallHonorWay(on: mapView, coordinator: self)`.
- `buildCircles`: add the five `way*` cases to the `continue` list at `:394`.
- `buildPoints`: add
```swift
            case .wayVoice(_, let heard):
                points.append(wayPoint(pin, symbol: "waveform", tint: heard ? .stone : .fog, coordinator: coordinator))
            case .wayPhoto:
                points.append(wayPoint(pin, symbol: "photo", tint: .stone, coordinator: coordinator))
            case .wayRest:
                points.append(wayPoint(pin, symbol: "cup.and.saucer", tint: .stone, coordinator: coordinator))
            case .waySit:
                points.append(wayPoint(pin, symbol: "circle.circle", tint: .dawn, coordinator: coordinator))
            case .wayWaypoint(_, _, let icon):
                points.append(wayPoint(pin, symbol: icon, tint: .stone, coordinator: coordinator))
```
and a helper:
```swift
    private static func wayPoint(_ pin: PilgrimAnnotation, symbol: String, tint: UIColor, coordinator: Coordinator) -> PointAnnotation {
        var point = PointAnnotation(coordinate: pin.coordinate)
        let glyph = MapGlyph.wayMark(symbol: symbol, tint: tint)
        if let image = MapGlyphImageBuilder.image(for: glyph, size: 22) {
            point.image = .init(image: image, name: MapGlyphImageBuilder.cacheKey(for: glyph))
        }
        point.iconSize = 1.0
        return point
    }
```
- `handleMapTap`: extend the `case .whisper, .cairn, .photo:` list with `.wayVoice, .wayPhoto, .wayRest, .waySit, .wayWaypoint`.

- [ ] **Step 6: Build, test, commit**

```bash
xcodebuild build -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator 2>&1 | grep -E "error:|BUILD"
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/HonorWayRenderingTests 2>&1 | grep -E "error:|Executed"
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(honor): ghost line, companion dot, and way pins on the map"
```

---

### Task 13: Choosing a Way: sheet, overview, coordinator, "walk this again"

**Files:**
- Create: `Pilgrim/Scenes/Honor/HonorWaysSheet.swift`
- Create: `Pilgrim/Scenes/Honor/HonorOverviewView.swift`
- Modify: `Pilgrim/Scenes/Root/MainCoordinatorView.swift:7-19`, `:55-93`, `:178-185`
- Modify: `Pilgrim/Scenes/Root/MainTabView.swift:21-25`, `:45-50`
- Modify: `Pilgrim/Scenes/Home/HomeView.swift:4-7`, `:54-56`
- Modify: `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift:21`, wherever `WalkSharingButtons` is placed (grep `WalkSharingButtons(` in the file)
- Test: `UnitTests/Honor/HonorOverviewModelTests.swift`

**Interfaces:**
- Produces: `MainCoordinator.honorWaysPresented: Bool`, `honorOverviewWay: Way?`, `pendingHonorWay: Way?`, `func chooseWay()`, `func openOverview(for way: Way)`, `func startHonor(way: Way)`, `func walkAgain(_ walk: WalkInterface)`, `func promotePendingHonorWay()`.
- `HonorOverviewModel.statusLine(distanceToStartMeters: Double?) -> String?` ("2.3 km from the start" / "you're on the way" / nil when unknown), `HonorOverviewModel.weatherLine(theirs: WayWeather?, today: String?) -> String?`, `HonorOverviewModel.countsLine(way:) -> String` ("9 voices · 4 photos").
- `WalkSummaryView(walk:onWalkAgain:)`, `HomeView(viewModel:onWalkAgain:)`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Pilgrim

final class HonorOverviewModelTests: XCTestCase {

    private func way(voices: Int, photos: Int, weather: WayWeather?) -> Way {
        var moments: [WayMoment] = []
        for n in 0..<voices {
            moments.append(WayMoment(id: "voice-\(n + 1)", frac: 0.1, at: nil,
                                     kind: .voice(endFrac: 0.2, duration: 5, kind: .spoken, media: .file("a"))))
        }
        for n in 0..<photos {
            moments.append(WayMoment(id: "photo-\(n + 1)", frac: 0.3, at: nil, kind: .photo(media: .file("p"))))
        }
        return Way(id: "w", source: .ownWalk(UUID()), title: "t", departedAt: Date(), tzIdentifier: nil, expires: nil,
                   route: [], totalDistanceMeters: 0, theirActiveSeconds: 0, moments: moments, weather: weather)
    }

    func testCountsLine() {
        XCTAssertEqual(HonorOverviewModel.countsLine(way: way(voices: 9, photos: 4, weather: nil)), "9 voices · 4 photos")
        XCTAssertEqual(HonorOverviewModel.countsLine(way: way(voices: 1, photos: 0, weather: nil)), "1 voice")
        XCTAssertEqual(HonorOverviewModel.countsLine(way: way(voices: 0, photos: 0, weather: nil)), "a quiet way")
    }

    func testStatusLine() {
        XCTAssertEqual(HonorOverviewModel.statusLine(distanceToStartMeters: 40), "you're on the way")
        XCTAssertEqual(HonorOverviewModel.statusLine(distanceToStartMeters: 2300), "2.3 km from the start")
        XCTAssertEqual(HonorOverviewModel.statusLine(distanceToStartMeters: 650), "650 m from the start")
        XCTAssertNil(HonorOverviewModel.statusLine(distanceToStartMeters: nil))
    }

    func testWeatherLine() {
        let theirs = WayWeather(condition: "rain", temperatureC: 9)
        XCTAssertEqual(HonorOverviewModel.weatherLine(theirs: theirs, today: "clear"),
                       "they walked this in rain at 9°. Today is clear.")
        XCTAssertEqual(HonorOverviewModel.weatherLine(theirs: theirs, today: nil), "they walked this in rain at 9°.")
        XCTAssertNil(HonorOverviewModel.weatherLine(theirs: nil, today: "clear"))
    }
}
```

`statusLine` follows the user's distance unit; the test assumes metric, so set `UserPreferences.distanceMeasurementType` to kilometers in `setUp` if the factory default differs (see how `ComputationTests` does it).

- [ ] **Step 2: Register and run to verify it fails**

```bash
ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/HonorOverviewModelTests.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/HonorOverviewModelTests 2>&1 | grep -E "error:|Executed"
```

- [ ] **Step 3: Create `HonorOverviewView.swift`**

```swift
import CoreLocation
import SwiftUI

enum HonorOverviewModel {

    static func countsLine(way: Way) -> String {
        var parts: [String] = []
        if way.voiceCount > 0 { parts.append(way.voiceCount == 1 ? "1 voice" : "\(way.voiceCount) voices") }
        if way.photoCount > 0 { parts.append(way.photoCount == 1 ? "1 photo" : "\(way.photoCount) photos") }
        return parts.isEmpty ? "a quiet way" : parts.joined(separator: " · ")
    }

    static func statusLine(distanceToStartMeters: Double?) -> String? {
        guard let meters = distanceToStartMeters else { return nil }
        if meters <= HonorTuning.onWayMeters { return "you're on the way" }
        let imperial = UserPreferences.distanceMeasurementType.safeValue == .miles
        if imperial {
            let miles = meters / 1609.344
            return miles < 0.2 ? "\(Int(meters * 3.28084)) ft from the start"
                : String(format: "%.1f mi from the start", miles)
        }
        return meters < 1000 ? "\(Int(meters)) m from the start" : String(format: "%.1f km from the start", meters / 1000)
    }

    static func weatherLine(theirs: WayWeather?, today: String?) -> String? {
        guard let theirs else { return nil }
        var line = "they walked this in \(theirs.condition)"
        if let t = theirs.temperatureC { line += " at \(Int(t.rounded()))°" }
        line += "."
        if let today { line += " Today is \(today)." }
        return line
    }

    static func bounds(of way: Way) -> MapCameraBounds? {
        let lats = way.route.map(\.lat), lons = way.route.map(\.lon)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else { return nil }
        return MapCameraBounds(sw: CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
                               ne: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon))
    }
}

/// The map fit to the whole Way, a card, and Begin. The camera never follows the puck here.
struct HonorOverviewView: View {

    let way: Way
    let onBegin: () -> Void
    let onClose: () -> Void

    @State private var cameraCenter: CLLocationCoordinate2D?
    @State private var cameraZoom: CGFloat = 14
    @State private var isMeditating = false
    @State private var distanceToStart: Double?
    @State private var voicesEnabled = UserPreferences.honorVoicesEnabled.value
    private let locationProbe = CLLocationManager()

    private var wayState: HonorWayState {
        HonorWayState(id: way.id, routeCoordinates: way.route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) })
    }

    var body: some View {
        VStack(spacing: 0) {
            PilgrimMapView(
                isInteractive: true,
                showsUserLocation: true,
                followsUserLocation: false,
                pinAnnotations: PilgrimMapView.wayPins(for: way, heardVoiceIDs: []),
                cameraCenter: $cameraCenter,
                cameraZoom: $cameraZoom,
                cameraBounds: HonorOverviewModel.bounds(of: way),
                isMeditating: $isMeditating,
                honorWay: wayState
            )
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
                Text(way.title).font(Constants.Typography.heading).foregroundColor(.ink)
                Text(DateFormatter.localizedString(from: way.departedAt, dateStyle: .long, timeStyle: .short))
                    .font(Constants.Typography.caption).foregroundColor(.fog)
                HStack {
                    Text(StatsHelper.string(for: way.totalDistanceMeters, unit: UnitLength.meters, type: .distance))
                    Text("·")
                    Text(durationText(way.theirActiveSeconds))
                    Text("·")
                    Text(HonorOverviewModel.countsLine(way: way))
                }
                .font(Constants.Typography.body).foregroundColor(.ink)
                if let line = HonorOverviewModel.weatherLine(theirs: way.weather, today: nil) {
                    Text(line).font(Constants.Typography.caption).foregroundColor(.fog)
                }
                if let status = HonorOverviewModel.statusLine(distanceToStartMeters: distanceToStart) {
                    Text(status).font(Constants.Typography.caption).foregroundColor(.fog)
                }
                Toggle(isOn: $voicesEnabled) {
                    Text("walk with their voice").font(Constants.Typography.body).foregroundColor(.ink)
                }
                .tint(.stone)
                .onChange(of: voicesEnabled) { _, on in UserPreferences.honorVoicesEnabled.value = on }
                .disabled(way.voiceCount == 0)

                Button(action: onBegin) {
                    Text("Begin")
                        .font(Constants.Typography.button).foregroundColor(.parchment)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color.stone).cornerRadius(Constants.UI.CornerRadius.normal)
                }
                .accessibilityLabel("Begin honoring this way")
            }
            .padding(Constants.UI.Padding.normal)
            .background(Color.parchment)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close", action: onClose) }
        }
        .onAppear { probeDistance() }
    }

    private func durationText(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600, m = (Int(seconds) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func probeDistance() {
        guard let first = way.route.first, let here = locationProbe.location else { return }
        distanceToStart = here.distance(from: CLLocation(latitude: first.lat, longitude: first.lon))
    }
}
```

`StatsHelper.string(for:unit:type:)` is the existing distance formatter used by `ActiveWalkViewModel.ascent`; confirm the `.distance` case name by reading `StatsHelper`.

- [ ] **Step 4: Create `HonorWaysSheet.swift`**

```swift
import SwiftUI

/// "Choose a way": accepted shares, one of your own walks again, or a pasted link.
struct HonorWaysSheet: View {

    let ownWalks: [Walk]
    let onChoose: (Way) -> Void
    let onPaste: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pasted = ""
    @State private var showOwnWalks = false
    @State private var acceptedWays: [Way] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if acceptedWays.isEmpty {
                        Text("no ways yet. Accept a shared walk, or walk one of yours again.")
                            .font(Constants.Typography.caption).foregroundColor(.fog)
                    }
                    ForEach(acceptedWays, id: \.id) { way in
                        Button { onChoose(way) } label: { wayRow(way) }
                    }
                } header: { Text("Shared with you").font(Constants.Typography.caption) }

                Section {
                    Button { showOwnWalks = true } label: {
                        settingNavRow(label: "Walk one of yours again")
                    }
                } header: { Text("Your own walks").font(Constants.Typography.caption) }

                Section {
                    TextField("paste a walk link", text: $pasted)
                        .font(Constants.Typography.body)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Open") { onPaste(pasted) }
                        .font(Constants.Typography.button)
                        .disabled(HonorLinkPreview.shareId(in: pasted) == nil)
                } header: { Text("From a shared walk").font(Constants.Typography.caption) }
                footer: { Text("Any Walk with me page has a \"walk it there\" button.").font(Constants.Typography.caption) }
            }
            .navigationTitle("Choose a way")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(isPresented: $showOwnWalks) {
                OwnWalkPicker(walks: ownWalks) { walk in
                    guard let way = OwnWalkWayBuilder.make(from: walk) else { return }
                    showOwnWalks = false
                    onChoose(way)
                }
            }
            .onAppear {
                WayStore.shared.sweepExpired(now: Date())
                acceptedWays = WayStore.shared.list().filter { if case .share = $0.source { return true } else { return false } }
            }
        }
    }

    @ViewBuilder
    private func wayRow(_ way: Way) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(way.title).font(Constants.Typography.body).foregroundColor(.ink)
            HStack {
                Text(DateFormatter.localizedString(from: way.departedAt, dateStyle: .medium, timeStyle: .none))
                Text("·")
                Text(WayStore.shared.hasMedia(id: way.id) || way.voiceCount + way.photoCount == 0
                     ? HonorOverviewModel.countsLine(way: way) : "voices returned to the trail")
            }
            .font(Constants.Typography.caption).foregroundColor(.fog)
        }
    }
}

struct OwnWalkPicker: View {
    let walks: [Walk]
    let onPick: (Walk) -> Void

    private var eligible: [Walk] { walks.filter { $0.routeData.count >= 2 } }

    var body: some View {
        NavigationStack {
            List {
                if eligible.isEmpty {
                    Text("walk somewhere first. Any walk with a route can be walked again.")
                        .font(Constants.Typography.caption).foregroundColor(.fog)
                }
                ForEach(eligible, id: \.id) { walk in
                    Button { onPick(walk) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(walk.comment?.isEmpty == false ? walk.comment! :
                                 DateFormatter.localizedString(from: walk.startDate, dateStyle: .medium, timeStyle: .none))
                                .font(Constants.Typography.body).foregroundColor(.ink)
                            Text(StatsHelper.string(for: walk.distance, unit: UnitLength.meters, type: .distance))
                                .font(Constants.Typography.caption).foregroundColor(.fog)
                        }
                    }
                }
            }
            .navigationTitle("Walk again")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Phase B replaces this with `HonorLink.parse`; until then the paste field
/// only recognizes a bare ten-character id or a walk.pilgrimapp.org URL.
enum HonorLinkPreview {
    static func shareId(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        let pattern = "^[A-Za-z0-9_-]{10}$"
        return candidate.range(of: pattern, options: .regularExpression) != nil ? candidate : nil
    }
}
```

- [ ] **Step 5: Coordinator and presentation**

`MainCoordinator` gains:
```swift
    @Published var honorWaysPresented = false
    @Published var honorOverviewWay: Way?
    var pendingHonorWay: Way?

    func chooseWay() { honorWaysPresented = true }

    func openOverview(for way: Way) {
        honorWaysPresented = false
        honorOverviewWay = way
    }

    /// Called from a summary's "walk this again": hold the Way, let the
    /// summary sheet close, then present (AF60: never two sheets at once).
    func walkAgain(_ walk: WalkInterface) {
        pendingHonorWay = OwnWalkWayBuilder.make(from: walk)
    }

    func promotePendingHonorWay() {
        if let way = pendingHonorWay {
            pendingHonorWay = nil
            honorOverviewWay = way
        }
    }

    func startHonor(way: Way) {
        honorOverviewWay = nil
        startWalk(mode: .honor, way: way)
    }
```
Change `startWalk(mode:)` to `startWalk(mode: WalkMode = .wander, way: Way? = nil)` and construct `ActiveWalkViewModel(mode: mode, way: way)`. In the save-success branch, after `snapshot.uuid = walk?.uuid`, add:
```swift
                    if let way, let uuid = walk?.uuid {
                        try? WayStore.shared.save(way)
                        try? WayStore.shared.link(walkUUID: uuid, to: way.id)
                    }
```
(`save` is idempotent; for an own-walk Way this is the moment `way.json` is first written.) `handleSummaryDismiss()` additionally calls `promotePendingHonorWay()`.

`MainTabView`: the Path tab's closure becomes
```swift
                WalkStartView(onStartWalk: { mode in
                    if mode == .honor { coordinator.chooseWay() } else { coordinator.startWalk(mode: mode) }
                })
```
Add two sheets after the summary sheet:
```swift
        .sheet(isPresented: $coordinator.honorWaysPresented) {
            HonorWaysSheet(
                ownWalks: coordinator.homeViewModel.walks,
                onChoose: { coordinator.openOverview(for: $0) },
                onPaste: { _ in }   // Phase B, Task 19
            )
        }
        .sheet(item: $coordinator.honorOverviewWay) { way in
            NavigationStack {
                HonorOverviewView(way: way, onBegin: { coordinator.startHonor(way: way) },
                                  onClose: { coordinator.honorOverviewWay = nil })
            }
        }
```
`Way` must be `Identifiable`: add `extension Way: Identifiable {}` in `Way.swift` (its `id` is already a `String`). Pass `onWalkAgain: { coordinator.walkAgain($0) }` to the summary sheet in `MainTabView`, and `MainCoordinatorView` passes `HomeView(viewModel:, onWalkAgain: coordinator.walkAgain)`; `HomeView` forwards it to its `WalkSummaryView` and calls `onWalkAgainPromote` on the sheet's `onDismiss`. Concretely `HomeView` gains `let onWalkAgain: (WalkInterface) -> Void` and `let onSummaryDismiss: () -> Void`, and `MainCoordinatorView` passes `coordinator.walkAgain` and `coordinator.promotePendingHonorWay`.

`WalkSummaryView`: add `var onWalkAgain: ((WalkInterface) -> Void)? = nil` and, next to the sharing buttons, when `walk.routeData.count >= 2 && onWalkAgain != nil`:
```swift
                    Button {
                        onWalkAgain?(walk)
                        dismiss()
                    } label: {
                        Label("walk this again", systemImage: "signpost.right")
                            .font(Constants.Typography.button).foregroundColor(.stone)
                    }
```

- [ ] **Step 6: Register, build, test, commit**

```bash
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Scenes/Honor/HonorOverviewView.swift
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Scenes/Honor/HonorWaysSheet.swift
xcodebuild build -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator 2>&1 | grep -E "error:|BUILD"
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/HonorOverviewModelTests 2>&1 | grep -E "error:|Executed"
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(honor): choose a way, overview with camera on the Way, walk this again"
```

---

### Task 14: Active walk UI: place cards, listening chip, arrival card

**Files:**
- Create: `Pilgrim/Scenes/ActiveWalk/WayPlaceCard.swift`
- Modify: `Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift:599-624` (map inputs, tap routing), the sheet composition near `:340-370`
- Modify: `Pilgrim/Scenes/ActiveWalk/WalkStatsSheet.swift:325-357` (minimized bar hosts the listening chip and the off-way caption)

**Interfaces:**
- Produces: `WayPlaceCard(moment:way:mediaURL:isPlaying:isPaused:elapsed:onPlayPause:onReply:onSit:onDismiss:pendingCount:)`; `HonorListeningChip(voice:elapsed:isPaused:onPauseResume:onSkip:)`; `HonorArrivalCardView(card:onDismiss:)`.

- [ ] **Step 1: Create `WayPlaceCard.swift`**

```swift
import Photos
import SwiftUI

/// One card, four bodies. Lives in the bottom sheet; never a modal.
struct WayPlaceCard: View {
    let moment: WayMoment
    let way: Way
    let mediaURL: URL?
    let isPlaying: Bool
    let isPaused: Bool
    let elapsed: TimeInterval
    let pendingCount: Int
    let onPlayPause: () -> Void
    let onReply: () -> Void
    let onSit: (Int) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            HStack {
                Text(kicker).font(Constants.Typography.caption).foregroundColor(.fog)
                Spacer()
                if pendingCount > 0 {
                    Text("+\(pendingCount) more").font(Constants.Typography.caption).foregroundColor(.fog)
                }
                Button(action: onDismiss) { Image(systemName: "xmark").foregroundColor(.fog) }
                    .accessibilityLabel("Dismiss")
            }
            body(for: moment.kind)
        }
        .padding(Constants.UI.Padding.normal)
        .background(RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.normal).fill(Color.parchmentSecondary))
    }

    private var kicker: String {
        switch moment.kind {
        case .voice: return "spoken here"
        case .photo: return "what they saw here"
        case .rest(let m): return "they rested here \(m) minutes"
        case .meditation(let m, let est): return est ? "they sat here about \(m) minutes" : "they sat here for \(m) minutes"
        case .waypoint(let label, _): return label
        }
    }

    @ViewBuilder
    private func body(for kind: WayMomentKind) -> some View {
        switch kind {
        case .voice(_, let duration, _, _):
            HStack(spacing: Constants.UI.Padding.normal) {
                Button(action: onPlayPause) {
                    Image(systemName: isPlaying && !isPaused ? "pause.circle" : "play.circle")
                        .font(.title).foregroundColor(.stone)
                }
                .accessibilityLabel(isPlaying && !isPaused ? "Pause their voice" : "Play their voice")
                Text("\(Int(elapsed) / 60):\(String(format: "%02d", Int(elapsed) % 60)) / \(Int(duration) / 60):\(String(format: "%02d", Int(duration) % 60))")
                    .font(Constants.Typography.timer).foregroundColor(.ink)
                Spacer()
                Button(action: onReply) {
                    Label("reply here", systemImage: "mic").font(Constants.Typography.button).foregroundColor(.stone)
                }
                .accessibilityLabel("Record a reply at this spot")
            }
        case .photo(let media):
            WayPhotoPlate(media: media, fileURL: mediaURL)
        case .rest:
            EmptyView()
        case .meditation(let minutes, _):
            Button { onSit(minutes) } label: {
                Text("Sit?").font(Constants.Typography.button).foregroundColor(.parchment)
                    .padding(.horizontal, Constants.UI.Padding.big).padding(.vertical, Constants.UI.Padding.small)
                    .background(Color.stone).cornerRadius(Constants.UI.CornerRadius.normal)
            }
            .accessibilityLabel("Sit here for \(minutes) minutes")
        case .waypoint:
            EmptyView()
        }
    }
}

/// Small parchment-matted image; tap to enlarge is a plain fullScreenCover.
struct WayPhotoPlate: View {
    let media: WayMedia
    let fileURL: URL?
    @State private var image: UIImage?
    @State private var enlarged = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxHeight: 160).cornerRadius(4)
                    .padding(6).background(Color.parchment).cornerRadius(6)
                    .onTapGesture { enlarged = true }
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Color.parchment).frame(height: 120)
            }
        }
        .onAppear(perform: load)
        .fullScreenCover(isPresented: $enlarged) {
            ZStack { Color.black.ignoresSafeArea(); if let image { Image(uiImage: image).resizable().scaledToFit() } }
                .onTapGesture { enlarged = false }
        }
    }

    private func load() {
        switch media {
        case .file:
            if let fileURL, let data = try? Data(contentsOf: fileURL) { image = UIImage(data: data) }
        case .photoAsset(let id):
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
            guard let asset = assets.firstObject else { return }
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = false
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 600, height: 600),
                                                  contentMode: .aspectFit, options: options) { result, _ in
                if let result { image = result }
            }
        case .recording:
            break
        }
    }
}

struct HonorListeningChip: View {
    let voice: WayMoment
    let elapsed: TimeInterval
    let isPaused: Bool
    let onPauseResume: () -> Void
    let onSkip: () -> Void

    var body: some View {
        HStack(spacing: Constants.UI.Padding.small) {
            Image(systemName: "waveform").foregroundColor(.stone)
            Text(isPaused ? "paused" : "listening").font(Constants.Typography.caption).foregroundColor(.fog)
            Text("\(Int(elapsed) / 60):\(String(format: "%02d", Int(elapsed) % 60))")
                .font(Constants.Typography.caption).foregroundColor(.ink)
            Button(action: onPauseResume) { Image(systemName: isPaused ? "play.fill" : "pause.fill") }
                .accessibilityLabel(isPaused ? "Resume their voice" : "Pause their voice")
            Button(action: onSkip) { Image(systemName: "forward.end.fill") }
                .accessibilityLabel("Skip this voice")
        }
        .foregroundColor(.stone)
        .padding(.horizontal, Constants.UI.Padding.normal).padding(.vertical, 6)
        .background(Capsule().fill(Color.parchmentSecondary))
    }
}

struct HonorArrivalCardView: View {
    let card: HonorArrivalCard
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            Text("you walked their way").font(Constants.Typography.heading).foregroundColor(.ink)
            Text(card.wayTitle).font(Constants.Typography.body).foregroundColor(.fog)
            Text(line).font(Constants.Typography.caption).foregroundColor(.fog)
            Button("continue", action: onDismiss).font(Constants.Typography.button).foregroundColor(.stone)
        }
        .padding(Constants.UI.Padding.normal)
        .background(RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.normal).fill(Color.parchmentSecondary))
    }

    private var line: String {
        var parts: [String] = []
        if card.voicesHeard > 0 { parts.append(card.voicesHeard == 1 ? "one voice heard" : "\(card.voicesHeard) voices heard") }
        if card.placesPassed > 0 { parts.append(card.placesPassed == 1 ? "one place passed" : "\(card.placesPassed) places passed") }
        return parts.isEmpty ? "the whole way, in their steps" : parts.joined(separator: " · ")
    }
}
```

- [ ] **Step 2: Wire `ActiveWalkView`**

In `mapSection()`:
- `pinAnnotations:` becomes `waypointPins + viewModel.proximityPins + honorPins`, where
```swift
        let honorPins: [PilgrimAnnotation] = viewModel.way.map {
            PilgrimMapView.wayPins(for: $0, heardVoiceIDs: viewModel.heardVoiceIDs)
        } ?? []
```
(`heardVoiceIDs` is filled by `handleHonorEvent(.voiceStart)`, Task 11).
- add `honorWay:` built from `viewModel.way` as in `HonorOverviewView.wayState`, and `companion:` = `viewModel.honorEngine.map { $0.geometry.coordinate(atFrac: $0.companionFrac) }`. Both nil for other modes, so wander and seek render exactly as before.
- In `handleAnnotationTap`, route the five `way*` kinds to `viewModel.showCard(for:)` by finding the moment with that id in `viewModel.way?.moments`.

Card host: in the view that composes the stats sheet, above the sheet content and only when `viewModel.mode == .honor`, add:
```swift
            if let card = viewModel.honorArrival {
                HonorArrivalCardView(card: card) { viewModel.honorArrival = nil }
            } else if let moment = viewModel.honorCards.first, let way = viewModel.way {
                WayPlaceCard(
                    moment: moment, way: way,
                    mediaURL: mediaURL(for: moment),
                    isPlaying: viewModel.activeVoice == moment,
                    isPaused: viewModel.isVoicePaused,
                    elapsed: WayVoicePlayer.shared.elapsedSeconds,
                    pendingCount: max(0, viewModel.honorCards.count - 1),
                    onPlayPause: { viewModel.togglePlayback(of: moment) },
                    onReply: { viewModel.replyHere(to: moment) },
                    onSit: { minutes in viewModel.startMeditation(minutes: minutes) },
                    onDismiss: { viewModel.dismissTopCard() }
                )
                .padding(.horizontal, Constants.UI.Padding.normal)
            }
```
Re-reply: `WayPlaceCard` also takes `existingReply: URL?` (from `WayStore.shared.replies(for: way.id)` keyed by the voice's `n`, resolved through the Documents directory). When present, the voice body shows a second row, "your reply" with its own play button, and the reply control reads "record again" and asks "Replace your earlier reply?" before calling `onReply`; the earlier recording stays in the earlier walk's record either way.

Add `togglePlayback(of:)` to the view model extension: if the moment is the active voice, pause or resume the player and flip `isVoicePaused`; otherwise stop the current voice, set `activeVoice`, and play its media URL (a replay from the card, outside the engine's queue). `mediaURL(for:)` unwraps the moment's media through `viewModel.mediaURL(for:)`.

Listening chip: in `WalkStatsSheet.minimizedContent`, when `activeVoice != nil`, show `HonorListeningChip` in place of the intention mantra; pass the view model's `activeVoice`, `WayVoicePlayer.shared.elapsedSeconds`, `isVoicePaused`, and closures that call `togglePlayback(of:)` and a new `skipVoice()` (stop the player and call `honorEngine?.voiceDidFinish()`). When `viewModel.honorEngine?.isOnWay == false` and `offWayMeters > 100`, the minimized bar's third stat reads "off the way · 240 m"; otherwise the third stat is the distance remaining when honoring.

- [ ] **Step 3: Build and commit**

```bash
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Scenes/ActiveWalk/WayPlaceCard.swift
xcodebuild build -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator 2>&1 | grep -E "error:|BUILD"
swiftlint lint --quiet Pilgrim/Scenes/ActiveWalk | head
git add -A Pilgrim Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(honor): place cards, listening chip, and the arrival card in the walk sheet"
```
If `ActiveWalkView` crosses 700 lines, move the card host into `ActiveWalkView+Honor.swift` as an extension before committing.

---

### Task 15: Summary, journal, seal, scenery, prompts

**Files:**
- Create: `Pilgrim/Scenes/WalkSummary/HonorSummarySection.swift`
- Create: `Pilgrim/Views/Scenery/StaffsShape.swift`
- Modify: `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift:24`, `:81-83`, `:711-754` (`computeAnnotations`), `WalkSummaryView+Map.swift:52-64` (pass `honorWay`)
- Modify: `Pilgrim/Scenes/Home/HomeViewModel.swift:17-20`, `:85-149`
- Modify: `Pilgrim/Scenes/Home/InkScrollView.swift:354-357`, `:694`
- Modify: `Pilgrim/Views/WalkModeFootprints.swift`
- Modify: `Pilgrim/Models/SceneryGenerator.swift:8-53`, `:105-112`
- Modify: `Pilgrim/Scenes/Goshuin/GoshuinMilestones.swift:5-20`, `:33-41`, `:143-160`, `:218-231`, `:233-243`
- Modify: `Pilgrim/Models/Seal/SealInput.swift`, `SealGenerator.swift:73`, `SealRenderer.swift:15`, `:111-149`
- Modify: `Pilgrim/Models/Prompt/ActivityContext.swift:5-34`, `PromptAssembler.swift:154-171`
- Test: `UnitTests/Honor/HonorJournalTests.swift`

**Interfaces:**
- Produces: `HonorSummaryData { wayTitle, arrivedBeforeTheirsSeconds: Double?, voicesHeard, repliesMade }`, `HonorSummaryModel.summaryData(for walk: WalkInterface, way: Way?, replies: [Int: String]) -> HonorSummaryData?` (nil unless the walk has a `.honorMode` event); `WalkSnapshot.isHonor`, `.honorArrivals`; `WalkModeFootprints(mode: WalkModeGlyph, color:)` with `enum WalkModeGlyph { wander, honor, seek }`; `SceneryType.staffs`; `GoshuinMilestones.Milestone.firstHonor`, `.honorsWalked(Int)`, `honorThresholds == [10, 25, 50, 100]`, `honorMilestones(arrivalsInWalk:arrivalsBefore:)`; `SealInput.honorArrivalCount`, `SealInput.wayPoints: [(lat: Double, lon: Double)]?`; `PracticeMode.honor`, `HonorStoryContext { wayTitle: String?, arrived: Bool }`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Pilgrim

final class HonorJournalTests: XCTestCase {

    func testPracticeModelReadsHonorEvents() {
        let now = Date()
        let practice = WalkPracticeModel.practice(events: [(.honorMode, now), (.honorArrival, now.addingTimeInterval(60))])
        XCTAssertEqual(practice.mode, .honor)
        XCTAssertEqual(practice.honorStory?.arrived, true)
        let plain = WalkPracticeModel.practice(events: [(.honorMode, now)])
        XCTAssertEqual(plain.honorStory?.arrived, false)
    }

    func testHonorMilestonesMirrorSeeking() {
        XCTAssertEqual(GoshuinMilestones.honorMilestones(arrivalsInWalk: 1, arrivalsBefore: 0), [.firstHonor])
        XCTAssertEqual(GoshuinMilestones.honorMilestones(arrivalsInWalk: 1, arrivalsBefore: 9), [.honorsWalked(10)])
        XCTAssertEqual(GoshuinMilestones.honorMilestones(arrivalsInWalk: 0, arrivalsBefore: 9), [])
        XCTAssertEqual(GoshuinMilestones.label(for: .firstHonor), "First Honor")
        XCTAssertEqual(GoshuinMilestones.label(for: .honorsWalked(25)), "25 Ways Walked")
    }

    func testSceneryRaisesStaffsForAnHonorArrival() {
        let snapshot = WalkSnapshot(
            id: UUID(), startDate: Date(), distance: 3000, duration: 1800, averagePace: 10, cumulativeDistance: 3000,
            talkDuration: 0, meditateDuration: 0, favicon: nil, isShared: false, weatherCondition: nil,
            isSeek: false, foundPlaces: 0, threshold: nil, isHonor: true, honorArrivals: 1)
        XCTAssertEqual(SceneryGenerator.scenery(for: snapshot)?.type, .staffs)
    }

    func testSummaryDataNeedsTheHonorEvent() {
        let way = Way(id: "walk:x", source: .ownWalk(UUID()), title: "Old walk", departedAt: Date(), tzIdentifier: nil,
                      expires: nil, route: [], totalDistanceMeters: 0, theirActiveSeconds: 600, moments: [], weather: nil)
        let plain = WalkDataFactory.makeWalk()
        XCTAssertNil(HonorSummaryModel.summaryData(for: plain, way: way, replies: [:]))
        let honored = WalkDataFactory.makeWalk(
            activeDuration: 540,
            workoutEvents: [TempWalkEvent(uuid: nil, eventType: .honorMode, timestamp: Date()),
                            TempWalkEvent(uuid: nil, eventType: .honorArrival, timestamp: Date())])
        let data = HonorSummaryModel.summaryData(for: honored, way: way, replies: [2: "r"])
        XCTAssertEqual(data?.wayTitle, "Old walk")
        XCTAssertEqual(data?.repliesMade, 1)
        XCTAssertEqual(data?.arrivedBeforeTheirsSeconds, 60)
    }
}
```

- [ ] **Step 2: Register and run to verify it fails**

```bash
ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/HonorJournalTests.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/HonorJournalTests 2>&1 | grep -E "error:|Executed"
```

- [ ] **Step 3: Prompts**

`ActivityContext.swift`: add `case honor` to `PracticeMode`; add
```swift
struct HonorStoryContext {
    let wayTitle: String?
    let arrived: Bool
}
```
change `practice(events:)` to return `(mode: PracticeMode, seekStory: SeekStoryContext?, honorStory: HonorStoryContext?)`: if events contain `.honorMode` return `(.honor, nil, HonorStoryContext(wayTitle: nil, arrived: events.contains { $0.type == .honorArrival }))`; the seek branch returns `(.seek, story, nil)`; wander `(.wander, nil, nil)`. Add `let honorStory: HonorStoryContext?` to `ActivityContext` and the `make` factory (default nil). Update the one call site that destructures the tuple (`grep -rn "WalkPracticeModel.practice" Pilgrim`).

`PromptAssembler.practiceLexicon`: add
```swift
        case .honor:
            var text = "**About this practice:** This walk was an Honor. The walker followed a Way another walker laid down, hearing their voices where they were spoken. Two traveling together; the line was traced, not raced."
            if let story = context.honorStory {
                if let title = story.wayTitle { text += " The Way: \(title)." }
                text += story.arrived ? " The end of the Way was reached." : " The Way was left before its end, which the practice honors too."
            }
            return text
```

- [ ] **Step 4: Milestones and seal input**

`GoshuinMilestones.swift`: add `case firstHonor` and `case honorsWalked(Int)` to `Milestone`; `static let honorThresholds = [10, 25, 50, 100]`; display priorities `firstHonor: 1`, `honorsWalked: 2` (same tier as seeking); `intraPriority` includes `.honorsWalked(let n)`; add
```swift
    static func honorMilestones(arrivalsInWalk: Int, arrivalsBefore: Int) -> Set<Milestone> {
        guard arrivalsInWalk > 0 else { return [] }
        var milestones: Set<Milestone> = []
        if arrivalsBefore == 0 { milestones.insert(.firstHonor) }
        let total = arrivalsBefore + arrivalsInWalk
        for threshold in honorThresholds where arrivalsBefore < threshold && total >= threshold {
            milestones.insert(.honorsWalked(threshold))
        }
        return milestones
    }

    static func honorArrivalCounts(for walks: [WalkInterface]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for walk in walks {
            guard let uuid = walk.uuid else { continue }
            let count = walk.waypoints.filter(HonorPersistence.isArrivalWaypoint).count
            if count > 0 { counts[uuid] = count }
        }
        return counts
    }
```
labels: `.firstHonor: "First Honor"`, `.honorsWalked(let n): "\(n) Ways Walked"`. In `detect(walkCount:walkIndex:input:allInputs:)` mirror the seeking block using `input.honorArrivalCount` and `honorMilestones`. `SealInput` gains `let honorArrivalCount: Int` (`walk.waypoints.filter(HonorPersistence.isArrivalWaypoint).count`) and `let wayPoints: [(lat: Double, lon: Double)]?` filled from `WayStore.shared.way(forWalk:)?.route` when the walk has an honor event, else nil. `SealGenerator` passes `wayPoints` into `SealRenderer.Input`, and `drawGhostRoute` draws `wayPoints` first at alpha 0.03 with the same fit, then the walk's own route as today, both fitted to the union of the two point sets.

- [ ] **Step 5: Journal snapshot, footprints, scenery**

`WalkSnapshot` gains `let isHonor: Bool` and `let honorArrivals: Int`. `HomeViewModel.buildSnapshots` fetches honor walk ids with the same bulk query as seek (`\._eventType == .honorMode`) and honor arrival counts via `GoshuinMilestones.honorArrivalCounts(for:)`; the threshold computation adds `honorMilestones(...)` to the seeking branch so an honor milestone stands at a seeking-tinted gate.

`WalkModeFootprints`: replace `let isSeek: Bool` with `let mode: WalkModeGlyph` (`enum WalkModeGlyph { case wander, honor, seek }`); the honor case draws one footprint plus `StaffGlyph()` stroked at 1 pt in `color`, 8×14. `InkScrollView:354` passes `mode: snapshot.isHonor ? .honor : (snapshot.isSeek ? .seek : .wander)`. Update every other `WalkModeFootprints(isSeek:` call site (`grep -rn "WalkModeFootprints(" Pilgrim`).

`StaffsShape.swift`:
```swift
import SwiftUI

/// Two staffs leaning together: dōgyō ninin, the ink-scroll mark of a walk
/// that honored a Way to its end.
struct StaffsShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: rect.minX + w * 0.20, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.55, y: rect.minY + h * 0.08))
        path.move(to: CGPoint(x: rect.minX + w * 0.80, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.45, y: rect.minY + h * 0.08))
        path.addEllipse(in: CGRect(x: rect.minX + w * 0.42, y: rect.minY, width: w * 0.16, height: h * 0.10))
        return path.strokedPath(StrokeStyle(lineWidth: max(1, w * 0.08), lineCap: .round))
    }
}
```
`SceneryType` gains `case staffs` with shape `AnyShape(StaffsShape())`, tint `"stone"`, parallax weight 9. In `SceneryGenerator.scenery(for:)`, after the cairn branch:
```swift
        if snapshot.isHonor && snapshot.honorArrivals > 0 {
            return SceneryPlacement(type: .staffs, side: side, offset: offset)
        }
```
`InkScrollView:694` haptic kinds: `if snap.isHonor && snap.honorArrivals > 0 { return .cairn }` (same weight as a cairn).

- [ ] **Step 6: Summary section**

`HonorSummarySection.swift`:
```swift
import SwiftUI

struct HonorSummaryData: Equatable {
    let wayTitle: String
    /// Positive when the honoring walker arrived before the companion.
    let arrivedBeforeTheirsSeconds: Double?
    let voicesHeard: Int
    let repliesMade: Int
}

enum HonorSummaryModel {
    static func summaryData(for walk: WalkInterface, way: Way?, replies: [Int: String]) -> HonorSummaryData? {
        let types = walk.workoutEvents.map(\.eventType)
        guard types.contains(.honorMode) else { return nil }
        let arrived = types.contains(.honorArrival)
        let delta: Double? = (arrived && way != nil) ? (way!.theirActiveSeconds - walk.activeDuration) : nil
        return HonorSummaryData(
            wayTitle: way?.title ?? "a way that has been removed",
            arrivedBeforeTheirsSeconds: delta,
            voicesHeard: way?.voiceCount ?? 0,
            repliesMade: replies.count)
    }
}

struct HonorSummarySection: View {
    let data: HonorSummaryData

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            Text("in their steps").font(Constants.Typography.caption).foregroundColor(.fog)
            Text(data.wayTitle).font(Constants.Typography.heading).foregroundColor(.ink)
            if let delta = data.arrivedBeforeTheirsSeconds {
                Text(deltaLine(delta)).font(Constants.Typography.caption).foregroundColor(.fog)
            }
            HStack {
                if data.voicesHeard > 0 { Text("\(data.voicesHeard) voices along the way") }
                if data.repliesMade > 0 { Text("· \(data.repliesMade) replies") }
            }
            .font(Constants.Typography.caption).foregroundColor(.fog)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Constants.UI.Padding.normal)
        .background(RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.big).fill(Color.parchmentSecondary))
    }

    private func deltaLine(_ delta: Double) -> String {
        let minutes = Int(abs(delta) / 60)
        if minutes == 0 { return "you arrived together" }
        return delta > 0 ? "they arrived \(minutes) minutes after you" : "they arrived \(minutes) minutes before you"
    }
}
```
`WalkSummaryView`: cache `cachedHonorSummary` in `init` via `HonorSummaryModel.summaryData(for: walk, way: walk.uuid.flatMap(WayStore.shared.way(forWalk:)), replies: ...)`, render it after the seek section, and in `computeAnnotations` treat `HonorPersistence.isArrivalWaypoint` waypoints as `.waypoint(label:icon:)` with their reserved icon (they already render as a stone symbol). `WalkSummaryView+Map.swift` passes `honorWay:` built from the cached Way so the ghost sits under the ink.

- [ ] **Step 7: Register, test, commit**

```bash
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Scenes/WalkSummary/HonorSummarySection.swift
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Views/Scenery/StaffsShape.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/HonorJournalTests -only-testing:UnitTests/GoshuinMilestonesTests -only-testing:UnitTests/SeekSummaryTests 2>&1 | grep -E "error:|Executed"
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(honor): summary section, staffs on the ink scroll, honor seals, prompt lexicon"
```

---

### Task 16: Debug simulation export, demo seed, Live Activity glance

**Files:**
- Create: `Pilgrim/Models/Honor/WayGPXExporter.swift`
- Create: `docs/honor-simulation.md`
- Modify: `Pilgrim/Scenes/Honor/HonorOverviewView.swift` (DEBUG menu)
- Modify: `Pilgrim/Models/ScreenshotDataSeeder.swift:138-168`, `:185-209`
- Modify: `Pilgrim/Models/Walk/Seek/SeekGlance.swift` (add `HonorGlanceState`), `WalkActivityAttributes.swift:22`, `WalkActivityManager.swift:78-131`, `PilgrimWidget/PilgrimWidgetLiveActivity.swift:186-188`, `ActiveWalkViewModel.swift:484`
- Test: `UnitTests/Honor/WayGPXExporterTests.swift`

**Interfaces:**
- Produces: `WayGPXExporter.gpx(for: Way) -> Data` (DEBUG only); `HonorGlanceState: Codable, Hashable { distanceRemainingBucketMeters: Int; isOnWay: Bool; isArrived: Bool }`; `WalkActivityAttributes.ContentState.honor: HonorGlanceState?`; `ActiveWalkViewModel.currentHonorGlance() -> HonorGlanceState?`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Pilgrim

final class WayGPXExporterTests: XCTestCase {

    func testEmitsTimedWaypointsAndNoTrack() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let route = [WayPoint(lat: 42.1, lon: -8.2, alt: 300, t: 0), WayPoint(lat: 42.2, lon: -8.3, alt: nil, t: 90)]
        let sit = WayMoment(id: "sit-1", frac: 1, at: nil, kind: .meditation(minutes: 5, isEstimate: false))
        let way = Way(id: "walk:x", source: .ownWalk(UUID()), title: "x", departedAt: start, tzIdentifier: nil, expires: nil,
                      route: route, totalDistanceMeters: 13_000, theirActiveSeconds: 90, moments: [sit], weather: nil)
        let xml = String(decoding: WayGPXExporter.gpx(for: way), as: UTF8.self)
        XCTAssertFalse(xml.contains("<trk>"))
        XCTAssertEqual(xml.components(separatedBy: "<wpt ").count - 1, 2)
        XCTAssertTrue(xml.contains("<time>2023-11-14T22:13:20Z</time>"))
        XCTAssertTrue(xml.contains("<time>2023-11-14T22:14:50Z</time>"))
        XCTAssertTrue(xml.contains("<ele>300</ele>"))
        XCTAssertTrue(xml.contains("<name>sit-1</name>"), "moment kinds ride on the nearest route waypoint")
    }
}
```

- [ ] **Step 2: Register and run to verify it fails**

```bash
ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/WayGPXExporterTests.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/WayGPXExporterTests 2>&1 | grep -E "error:|Executed"
```

- [ ] **Step 3: Create `WayGPXExporter.swift`**

```swift
#if DEBUG
import Foundation

/// Xcode's Core Location simulation reads only <wpt> elements and paces
/// timed waypoints at the speed their timestamps dictate. One <wpt> per
/// route point, in order; moment ids ride on the nearest route point's
/// <name> so nothing hops the simulator off the Way.
enum WayGPXExporter {

    static func gpx(for way: Way) -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var names: [Int: [String]] = [:]
        for moment in way.moments {
            let target = moment.frac * Double(max(way.route.count - 1, 0))
            names[Int(target.rounded()), default: []].append(moment.id)
        }
        var lines = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<gpx version=\"1.1\" creator=\"Pilgrim\" xmlns=\"http://www.topografix.com/GPX/1/1\">",
        ]
        for (index, point) in way.route.enumerated() {
            lines.append("  <wpt lat=\"\(point.lat)\" lon=\"\(point.lon)\">")
            if let alt = point.alt { lines.append("    <ele>\(Int(alt.rounded()))</ele>") }
            lines.append("    <time>\(formatter.string(from: way.departedAt.addingTimeInterval(point.t)))</time>")
            if let ids = names[index] { lines.append("    <name>\(ids.joined(separator: " "))</name>") }
            lines.append("  </wpt>")
        }
        lines.append("</gpx>")
        return Data(lines.joined(separator: "\n").utf8)
    }
}
#endif
```

- [ ] **Step 4: Debug menu, how-to, demo seed**

In `HonorOverviewView`, inside `#if DEBUG`, add a toolbar `Menu` with "Export simulation GPX" that writes `WayGPXExporter.gpx(for: way)` to `FileManager.default.temporaryDirectory.appendingPathComponent("\(way.id.replacingOccurrences(of: ":", with: "-")).gpx")` and presents `ShareSheet(items: [url])`.

`docs/honor-simulation.md`:
```markdown
# Simulating an honor walk

1. Open any Way's overview in a DEBUG build, tap the ladybug menu, "Export simulation GPX", AirDrop the file to your Mac.
2. Xcode → Product → Scheme → Edit Scheme → Run → Options → Core Location → Default Location → Add GPX File to Project.
3. Run on the simulator, choose Honor, choose the same Way, Begin. The simulator walks the route at the recorded pace: voices fire, cards rise, the companion moves.
4. Airplane mode does not affect Phase A. For Phase B, accept the Way online first, then toggle airplane mode before Begin to prove the media is local.
```

`ScreenshotDataSeeder`: add a seventh `ScreenshotWalk` after the seek walk, `daysAgo: 3`, six route points near Santiago, `talkMinutes: 5`, with `events: [(WalkEvent.EventType.honorMode.rawValue, 0), (WalkEvent.EventType.honorArrival.rawValue, 40)]` and a waypoint `(HonorPersistence.arrivalWaypointLabel(wayTitle: "A morning in the old town"), HonorPersistence.arrivalWaypointIcon, <last lat>, <last lon>, 40)`. In `seed(completion:)`, after that walk saves, build `OwnWalkWayBuilder.make(from:)` from the saved `Walk` (the completion hands it back), give it title "A morning in the old town", `WayStore.shared.save(way)` and `link(walkUUID:to:)`, so the demo summary shows the ghost.

- [ ] **Step 5: Live Activity glance**

`SeekGlance.swift` (widget-shared, Foundation only) gains:
```swift
struct HonorGlanceState: Codable, Hashable {
    let distanceRemainingBucketMeters: Int
    let isOnWay: Bool
    let isArrived: Bool
}
```
`ContentState` gains `var honor: HonorGlanceState?` (nil for other modes; synthesized Codable omits it). `WalkActivityManager.update` gains `honor: HonorGlanceState? = nil`, includes `honor != lastHonorGlance` in `shouldPush`'s flags-changed term, stores `lastHonorGlance`, and passes it into the state. `ActiveWalkViewModel.swift:484` passes `honor: self.currentHonorGlance()`, implemented in the honor extension:
```swift
    func currentHonorGlance() -> HonorGlanceState? {
        guard let engine = honorEngine else { return nil }
        return HonorGlanceState(
            distanceRemainingBucketMeters: SeekGlanceModel.distanceBucket(forMeters: engine.distanceRemainingMeters),
            isOnWay: engine.isOnWay, isArrived: engine.phase == .arrived)
    }
```
Widget lock screen, after the seek glance bar:
```swift
            if let honor = context.state.honor {
                HStack(spacing: 6) {
                    Image(systemName: "signpost.right").font(.caption).foregroundColor(Self.stone)
                    Text(honor.isArrived ? "their way, walked"
                         : honor.isOnWay ? "\(seekDistanceText(bucket: honor.distanceRemainingBucketMeters, imperial: context.attributes.isImperial)) to go"
                         : "off the way")
                        .font(.system(.caption, design: .serif)).foregroundColor(Self.ink)
                    Spacer()
                }
            }
```

- [ ] **Step 6: Register, test, commit**

```bash
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Models/Honor/WayGPXExporter.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/WayGPXExporterTests -only-testing:UnitTests/SeekLiveActivityTests -only-testing:UnitTests/SeekDemoSeedTests 2>&1 | grep -E "error:|Executed"
git add -A Pilgrim PilgrimWidget UnitTests docs Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(honor): simulation GPX export, demo honor walk, lock-screen glance"
```

**Phase A gate.** Run the whole suite and the lint before opening the PR:
```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "Executed|error:" | tail -3
swiftlint lint --quiet | head
```
Then the simulator pass from `docs/honor-simulation.md`, then a real walk-it-again on the developer's phone. The open question in the spec (ship 1a alone) is decided here.

---

## Phase B: shared walks

### Task 17: `TourManifest` and `WayImporter`

**Files:**
- Create: `Pilgrim/Models/Honor/TourManifest.swift`
- Create: `Pilgrim/Models/Honor/WayImporter.swift`
- Create: `UnitTests/Honor/Fixtures/tour-sample.json` (copy of `../pilgrim-worker/scripts/fixtures/` output shape; register with the UnitTests target's resources phase via a one-line variant of `xcode-add.rb` that uses `resources_build_phase`)
- Test: `UnitTests/Honor/WayImporterTests.swift`

**Interfaces:**
- Produces: `struct TourManifest: Decodable` mirroring `pilgrim-worker/src/types.ts:118-142` (`v`, `place_start`, `place_end`, `weather_condition`, `weather_temperature`, `start_date`, `tz_identifier`, `expires`, `route: [RoutePoint {lat, lon, alt, ts}]`, `encounters: [Encounter {type, frac, end_frac?, n?, duration?, label?, icon?, minutes?, lat?, lon?}]`, `meditation: [{start_frac, end_frac, duration?}]`, `stats {active_duration?}`); `enum WayError: Error, Equatable { case notFound, returnedToTrail, unavailable }`; `WayImporter(session: URLSession = .shared, store: WayStore = .shared, now: () -> Date = Date.init)`, `func importShare(id: String) async throws -> Way`, `static func way(from manifest: TourManifest, shareId: String, now: Date) throws -> Way`; `WayImporter.maxRoutePoints == 2000`, `maxEncounters == 200`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Pilgrim

final class WayImporterTests: XCTestCase {

    private func manifest(expires: String = "2099-01-01T00:00:00Z", extraEncounter: String = "") throws -> TourManifest {
        let json = """
        {"v":1,"theme":"light","time_bucket":"morning","place_start":"Rúa do Franco","place_end":"Obradoiro",
         "weather_condition":"rain","weather_temperature":9,"units":"metric","start_date":"2026-08-01T07:00:00Z",
         "tz_identifier":"Europe/Madrid","expires":"\(expires)",
         "route":[{"lat":42.88,"lon":-8.545,"alt":250,"ts":1000},{"lat":42.88,"lon":-8.540,"alt":250,"ts":1400},{"lat":42.88,"lon":-8.535,"alt":250,"ts":1600}],
         "total_distance_m":820,
         "encounters":[{"type":"departure","frac":0},
           {"type":"voice","frac":0.5,"end_frac":0.6,"n":1,"duration":40,"dwell":30,"lat":42.8801,"lon":-8.5401},
           {"type":"ambience","frac":0.7,"end_frac":0.75,"n":2,"duration":20,"dwell":20},
           {"type":"photo","frac":0.8,"n":1,"dwell":5},
           {"type":"rest","frac":0.9,"minutes":4,"dwell":4}\(extraEncounter),
           {"type":"arrival","frac":1}],
         "meditation":[{"start_frac":0.5,"end_frac":0.5,"duration":720},{"start_frac":0.5,"end_frac":0.5}],
         "activity_segments":[],"stats":{"active_duration":540}}
        """
        return try JSONDecoder().decode(TourManifest.self, from: Data(json.utf8))
    }

    func testBuildsAWayFromTheManifest() throws {
        let way = try WayImporter.way(from: manifest(), shareId: "Qoi4YmPHLN", now: Date())
        XCTAssertEqual(way.id, "share:Qoi4YmPHLN")
        XCTAssertEqual(way.title, "Rúa do Franco → Obradoiro")
        XCTAssertEqual(way.route.map(\.t), [0, 400, 600])
        XCTAssertEqual(way.theirActiveSeconds, 540)
        XCTAssertEqual(way.weather, WayWeather(condition: "rain", temperatureC: 9))
        let voice = try XCTUnwrap(way.moments.first { $0.id == "voice-1" })
        XCTAssertEqual(voice.at, WayCoordinate(lat: 42.8801, lon: -8.5401))
        guard case .voice(_, _, let kind, let media) = voice.kind else { return XCTFail() }
        XCTAssertEqual(kind, .spoken)
        XCTAssertEqual(media, .file("audio/1.m4a"))
        let ambience = try XCTUnwrap(way.moments.first { $0.id == "voice-2" })
        XCTAssertNil(ambience.at, "older shares carry no coordinate")
        guard case .voice(_, _, .ambient, .file("audio/2.m4a")) = ambience.kind else { return XCTFail() }
        XCTAssertEqual(way.moments.first { $0.id == "photo-1" }?.kind, .photo(media: .file("photos/1.jpg")))
        let sits = way.moments.filter { if case .meditation = $0.kind { return true }; return false }
        XCTAssertEqual(sits.map(\.kind), [.meditation(minutes: 12, isEstimate: false),
                                          .meditation(minutes: 7, isEstimate: true)],
                       "second sitting has no duration: estimated from the 400 s gap around frac 0.5")
    }

    func testExpiredManifestIsReturnedToTrail() throws {
        XCTAssertThrowsError(try WayImporter.way(from: manifest(expires: "2000-01-01T00:00:00Z"), shareId: "x", now: Date())) {
            XCTAssertEqual($0 as? WayError, .returnedToTrail)
        }
    }

    func testOversizedManifestIsUnavailable() throws {
        let many = (0..<300).map { _ in ",{\"type\":\"waypoint\",\"frac\":0.5,\"label\":\"x\",\"icon\":\"leaf\",\"dwell\":3}" }.joined()
        XCTAssertThrowsError(try WayImporter.way(from: manifest(extraEncounter: many), shareId: "x", now: Date())) {
            XCTAssertEqual($0 as? WayError, .unavailable)
        }
    }
}
```

- [ ] **Step 2: Register and run to verify it fails**

```bash
ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/WayImporterTests.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/WayImporterTests 2>&1 | grep -E "error:|Executed"
```

- [ ] **Step 3: Create `TourManifest.swift` and `WayImporter.swift`**

`TourManifest.swift`: a `Decodable` struct with snake_case `CodingKeys` for exactly the fields listed in Interfaces; every field the spec calls optional is `Optional`. `Encounter` decodes `type` as a `String` so unknown future kinds decode and are skipped.

`WayImporter.swift`:
```swift
import Foundation

enum WayError: Error, Equatable { case notFound, returnedToTrail, unavailable }

struct WayImporter {

    static let maxRoutePoints = 2000
    static let maxEncounters = 200
    static let baseURL = URL(string: "https://walk.pilgrimapp.org")!

    let session: URLSession
    let store: WayStore
    let now: () -> Date

    init(session: URLSession = .shared, store: WayStore = .shared, now: @escaping () -> Date = { Date() }) {
        self.session = session; self.store = store; self.now = now
    }

    func importShare(id: String) async throws -> Way {
        let url = Self.baseURL.appendingPathComponent(id).appendingPathComponent("tour.json")
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(from: url) } catch { throw WayError.unavailable }
        guard let http = response as? HTTPURLResponse else { throw WayError.unavailable }
        if http.statusCode == 404 { throw WayError.notFound }
        guard http.statusCode == 200 else { throw WayError.unavailable }
        let decoder = JSONDecoder()
        guard let manifest = try? decoder.decode(TourManifest.self, from: data) else { throw WayError.unavailable }
        let way = try Self.way(from: manifest, shareId: id, now: now())
        try store.save(way)
        return way
    }

    static func way(from m: TourManifest, shareId: String, now: Date) throws -> Way {
        let iso = ISO8601DateFormatter()
        guard let expires = iso.date(from: m.expires), let departed = iso.date(from: m.start_date) else { throw WayError.unavailable }
        guard expires > now else { throw WayError.returnedToTrail }
        guard m.route.count >= 2, m.route.count <= maxRoutePoints, m.encounters.count <= maxEncounters else { throw WayError.unavailable }
        let ts0 = m.route[0].ts
        let route = m.route.map { WayPoint(lat: $0.lat, lon: $0.lon, alt: $0.alt, t: Double($0.ts - ts0)) }
        let geometry = WayGeometry(route: route)

        var moments: [WayMoment] = []
        var voiceN = 0, photoN = 0, waypointN = 0, restN = 0
        for e in m.encounters {
            let at = (e.lat != nil && e.lon != nil) ? WayCoordinate(lat: e.lat!, lon: e.lon!) : nil
            switch e.type {
            case "voice", "ambience":
                guard let n = e.n else { continue }
                voiceN += 1
                moments.append(WayMoment(id: "voice-\(voiceN)", frac: e.frac, at: at,
                    kind: .voice(endFrac: e.end_frac ?? e.frac, duration: e.duration ?? 0,
                                 kind: e.type == "voice" ? .spoken : .ambient, media: .file("audio/\(n).m4a"))))
            case "photo":
                guard let n = e.n else { continue }
                photoN += 1
                moments.append(WayMoment(id: "photo-\(photoN)", frac: e.frac, at: at, kind: .photo(media: .file("photos/\(n).jpg"))))
            case "waypoint":
                waypointN += 1
                moments.append(WayMoment(id: "waypoint-\(waypointN)", frac: e.frac, at: at,
                                         kind: .waypoint(label: e.label ?? "", icon: e.icon ?? "mappin")))
            case "rest":
                restN += 1
                moments.append(WayMoment(id: "rest-\(restN)", frac: e.frac, at: at, kind: .rest(minutes: e.minutes ?? 0)))
            default:
                continue
            }
        }
        for (index, sit) in m.meditation.enumerated() {
            let minutes: Int
            let isEstimate: Bool
            if let seconds = sit.duration {
                minutes = Int((seconds / 60).rounded()); isEstimate = false
            } else {
                minutes = Int((gapSeconds(around: sit.start_frac, geometry: geometry) / 60).rounded()); isEstimate = true
            }
            moments.append(WayMoment(id: "sit-\(index + 1)", frac: sit.start_frac, at: nil,
                                     kind: .meditation(minutes: minutes, isEstimate: isEstimate)))
        }
        moments.sort { $0.frac < $1.frac }

        let places = [m.place_start, m.place_end].compactMap { $0 }
        let title = places.isEmpty ? DateFormatter.localizedString(from: departed, dateStyle: .medium, timeStyle: .none)
            : places.joined(separator: " → ")
        return Way(
            id: "share:\(shareId)",
            source: .share(id: shareId, pageURL: baseURL.appendingPathComponent(shareId)),
            title: title, departedAt: departed, tzIdentifier: m.tz_identifier, expires: expires,
            route: route, totalDistanceMeters: geometry.totalMeters,
            theirActiveSeconds: m.stats?.active_duration ?? geometry.totalSeconds,
            moments: moments,
            weather: m.weather_condition.map { WayWeather(condition: $0, temperatureC: m.weather_temperature) })
    }

    /// Time between the two route points bracketing `frac`: a sitting collapses
    /// to a single frac on a downsampled route, so the gap holds the sit plus
    /// whatever walking the RDP pass folded into that segment. Rendered "about".
    static func gapSeconds(around frac: Double, geometry: WayGeometry) -> Double {
        let points = geometry.points
        guard points.count > 1, geometry.totalMeters > 0 else { return 0 }
        let target = frac * geometry.totalMeters
        for i in 0..<(points.count - 1) where geometry.cumulative[i] <= target && target <= geometry.cumulative[i + 1] {
            return points[i + 1].t - points[i].t
        }
        return 0
    }
}
```

- [ ] **Step 4: Register, test, commit**

```bash
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Models/Honor/TourManifest.swift
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Models/Honor/WayImporter.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/WayImporterTests 2>&1 | grep -E "error:|Executed"
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(honor): import a shared walk's manifest as a Way"
```

---

### Task 18: `WayMediaDownloader` on a background session

**Files:**
- Create: `Pilgrim/Models/Honor/WayMediaDownloader.swift`
- Modify: `Pilgrim/AppDelegate.swift` (add `handleEventsForBackgroundURLSession`)
- Test: `UnitTests/Honor/WayMediaDownloaderTests.swift`

**Interfaces:**
- Produces: `@MainActor final class WayMediaDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate` with `static let shared`, `init(store: WayStore, sessionIdentifier: String)`, `@Published progress: [String: Double]` (wayId → 0...1), `@Published failures: [String: [String]]` (wayId → relative files), `@Published active: Set<String>`, `func download(_ way: Way)`, `func retry(_ way: Way)`, `func cancel(wayId:)`, `static func mediaFiles(for way: Way) -> [String]` (relative paths, e.g. `audio/1.m4a`, `photos/2.jpg`, deduplicated, in order), `var backgroundCompletionHandler: (() -> Void)?`. Per-file byte caps: audio 15 MB, photos 2 MB; a response larger than its cap is discarded and counted as a failure.

- [ ] **Step 1: Write the failing test (pure parts)**

```swift
import XCTest
@testable import Pilgrim

final class WayMediaDownloaderTests: XCTestCase {

    func testMediaFilesListsEveryFileOnce() {
        let moments = [
            WayMoment(id: "voice-1", frac: 0.1, at: nil, kind: .voice(endFrac: 0.2, duration: 1, kind: .spoken, media: .file("audio/1.m4a"))),
            WayMoment(id: "voice-2", frac: 0.3, at: nil, kind: .voice(endFrac: 0.4, duration: 1, kind: .ambient, media: .file("audio/2.m4a"))),
            WayMoment(id: "photo-1", frac: 0.5, at: nil, kind: .photo(media: .file("photos/1.jpg"))),
            WayMoment(id: "rest-1", frac: 0.6, at: nil, kind: .rest(minutes: 3)),
        ]
        let way = Way(id: "share:a", source: .share(id: "a", pageURL: URL(string: "https://walk.pilgrimapp.org/a")!), title: "t",
                      departedAt: Date(), tzIdentifier: nil, expires: nil, route: [], totalDistanceMeters: 0,
                      theirActiveSeconds: 0, moments: moments, weather: nil)
        XCTAssertEqual(WayMediaDownloader.mediaFiles(for: way), ["audio/1.m4a", "audio/2.m4a", "photos/1.jpg"])
        XCTAssertEqual(WayMediaDownloader.remoteURL(shareId: "a", relative: "audio/1.m4a").absoluteString,
                       "https://walk.pilgrimapp.org/a/audio/1.m4a")
        XCTAssertEqual(WayMediaDownloader.byteCap(for: "audio/1.m4a"), 15 * 1024 * 1024)
        XCTAssertEqual(WayMediaDownloader.byteCap(for: "photos/1.jpg"), 2 * 1024 * 1024)
    }
}
```

- [ ] **Step 2: Register and run to verify it fails**

```bash
ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/WayMediaDownloaderTests.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/WayMediaDownloaderTests 2>&1 | grep -E "error:|Executed"
```

- [ ] **Step 3: Create `WayMediaDownloader.swift`**

```swift
import Combine
import Foundation

/// Downloads a Way's voices and photos on a background URLSession so a
/// locked phone finishes the job. Delegate-based by necessity: background
/// sessions reject async and completion-handler task APIs. Task ids map to
/// (wayId, relative file); the delivered temp file is moved atomically.
@MainActor
final class WayMediaDownloader: NSObject, ObservableObject {

    static let shared = WayMediaDownloader(store: .shared, sessionIdentifier: "org.walktalkmeditate.pilgrim.ways")

    @Published private(set) var progress: [String: Double] = [:]
    @Published private(set) var failures: [String: [String]] = [:]
    @Published private(set) var active: Set<String> = []
    var backgroundCompletionHandler: (() -> Void)?

    private let store: WayStore
    private var session: URLSession!
    private var tasks: [Int: (wayId: String, relative: String, expected: Int)] = [:]
    private var pending: [String: Set<String>] = [:]
    private var retried: [String: Set<String>] = [:]

    init(store: WayStore, sessionIdentifier: String) {
        self.store = store
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    static func mediaFiles(for way: Way) -> [String] {
        var seen: Set<String> = []
        var files: [String] = []
        for moment in way.moments {
            let media: WayMedia?
            switch moment.kind {
            case .voice(_, _, _, let m): media = m
            case .photo(let m): media = m
            default: media = nil
            }
            if case .file(let relative)? = media, !seen.contains(relative) {
                seen.insert(relative)
                files.append(relative)
            }
        }
        return files
    }

    static func remoteURL(shareId: String, relative: String) -> URL {
        WayImporter.baseURL.appendingPathComponent(shareId).appendingPathComponent(relative)
    }

    static func byteCap(for relative: String) -> Int {
        relative.hasPrefix("photos/") ? 2 * 1024 * 1024 : 15 * 1024 * 1024
    }

    func download(_ way: Way) {
        guard case .share(let shareId, _) = way.source else { return }
        let files = Self.mediaFiles(for: way).filter {
            !FileManager.default.fileExists(atPath: store.mediaURL(for: way.id, relative: $0).path)
        }
        failures[way.id] = nil
        guard !files.isEmpty else { progress[way.id] = 1; return }
        active.insert(way.id)
        pending[way.id] = Set(files)
        progress[way.id] = 0
        for relative in files { enqueue(wayId: way.id, shareId: shareId, relative: relative) }
    }

    func retry(_ way: Way) {
        retried[way.id] = nil
        download(way)
    }

    func cancel(wayId: String) {
        session.getAllTasks { tasks in
            for task in tasks where self.tasks[task.taskIdentifier]?.wayId == wayId { task.cancel() }
        }
        active.remove(wayId)
        pending[wayId] = nil
        progress[wayId] = nil
    }

    private func enqueue(wayId: String, shareId: String, relative: String) {
        let task = session.downloadTask(with: Self.remoteURL(shareId: shareId, relative: relative))
        tasks[task.taskIdentifier] = (wayId, relative, Self.byteCap(for: relative))
        task.resume()
    }

    private func finish(taskId: Int, success: Bool) {
        guard let entry = tasks.removeValue(forKey: taskId) else { return }
        if !success {
            let shareId = store.load(id: entry.wayId).flatMap { way -> String? in
                if case .share(let id, _) = way.source { return id } else { return nil }
            }
            if let shareId, !(retried[entry.wayId]?.contains(entry.relative) ?? false) {
                retried[entry.wayId, default: []].insert(entry.relative)
                enqueue(wayId: entry.wayId, shareId: shareId, relative: entry.relative)
                return
            }
            failures[entry.wayId, default: []].append(entry.relative)
        }
        pending[entry.wayId]?.remove(entry.relative)
        let total = Double(Self.mediaFiles(for: store.load(id: entry.wayId) ?? placeholder).count)
        let left = Double(pending[entry.wayId]?.count ?? 0)
        progress[entry.wayId] = total > 0 ? 1 - left / total : 1
        if left == 0 { active.remove(entry.wayId) }
    }

    private var placeholder: Way {
        Way(id: "", source: .ownWalk(UUID()), title: "", departedAt: Date(), tzIdentifier: nil, expires: nil,
            route: [], totalDistanceMeters: 0, theirActiveSeconds: 0, moments: [], weather: nil)
    }
}

extension WayMediaDownloader: URLSessionDownloadDelegate {

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temp file is deleted when this returns: move it synchronously, then hop to main for bookkeeping.
        let taskId = downloadTask.taskIdentifier
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        let size = (try? FileManager.default.attributesOfItem(atPath: location.path)[.size] as? Int) ?? 0
        let moved = MainActor.assumeIsolated { () -> Bool in
            guard let entry = self.tasks[taskId], status == 200, size <= entry.expected else { return false }
            let dest = self.store.mediaURL(for: entry.wayId, relative: entry.relative)
            try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: dest)
            return (try? FileManager.default.moveItem(at: location, to: dest)) != nil
        }
        Task { @MainActor in self.finish(taskId: taskId, success: moved) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard error != nil else { return }
        let taskId = task.taskIdentifier
        Task { @MainActor in self.finish(taskId: taskId, success: false) }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}
```

`MainActor.assumeIsolated` inside a delegate callback on the session's queue is a deliberate trade: the session is created with `delegateQueue: nil` so callbacks arrive on a serial background queue, and the bookkeeping dictionary is only touched from main. If Swift 6 strict checking rejects it, replace `tasks` access with a lock-protected dictionary and keep the move synchronous.

`AppDelegate.swift`: in `runPostDoneLaunchTasks()` add `WayStore.shared.sweepExpired(now: Date())` (the spec's launch sweep), and add:
```swift
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == "org.walktalkmeditate.pilgrim.ways" else { completionHandler(); return }
        Task { @MainActor in WayMediaDownloader.shared.backgroundCompletionHandler = completionHandler }
    }
```

- [ ] **Step 4: Register, test, commit**

```bash
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Models/Honor/WayMediaDownloader.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/WayMediaDownloaderTests 2>&1 | grep -E "error:|Executed"
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(honor): background media download for shared Ways"
```

---

### Task 19: The link: `HonorLink`, entitlement, `onOpenURL`, paste, gathering on the overview

**Files:**
- Create: `Pilgrim/Models/Honor/HonorLink.swift`
- Modify: `Pilgrim/Pilgrim.entitlements`
- Modify: `Pilgrim/PilgrimApp.swift:31-41`
- Modify: `Pilgrim/Scenes/Root/RootCoordinatorView.swift`, `RootCoordinatorViewModel.swift`
- Modify: `Pilgrim/Scenes/Root/MainCoordinatorView.swift` (`openWay(shareId:)`), `MainTabView.swift` (paste closure, overview gathering state)
- Modify: `Pilgrim/Scenes/Honor/HonorOverviewView.swift` (gathering / failure states), `HonorWaysSheet.swift` (use `HonorLink.parse`, delete `HonorLinkPreview`)
- Test: `UnitTests/Honor/HonorLinkTests.swift`

**Interfaces:**
- Produces: `enum HonorLink { static func parse(_ url: URL) -> String?; static func parse(text: String) -> String? }`; `MainCoordinator.openWay(shareId:)`, `@Published var honorImportState: HonorImportState` (`.idle`, `.fetching`, `.gathering(progress: Double)`, `.ready`, `.failed(WayError)`, `.mediaMissing([String])`), `@Published var pendingLinkToast: String?`.
- `NotificationCenter` name `.pilgrimOpenWay` with `userInfo["shareId"]`, posted by `PilgrimApp`, observed by `MainTabView`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Pilgrim

final class HonorLinkTests: XCTestCase {

    func testAcceptedForms() {
        for s in ["https://honor.pilgrimapp.org/Qoi4YmPHLN", "https://honor.pilgrimapp.org/Qoi4YmPHLN/",
                  "https://honor.pilgrimapp.org/Qoi4YmPHLN?utm=x#m3", "https://walk.pilgrimapp.org/Qoi4YmPHLN",
                  "walk.pilgrimapp.org/Qoi4YmPHLN", "Qoi4YmPHLN", "  Qoi4YmPHLN\n"] {
            XCTAssertEqual(HonorLink.parse(text: s), "Qoi4YmPHLN", s)
        }
        XCTAssertEqual(HonorLink.parse(URL(string: "https://honor.pilgrimapp.org/Qoi4YmPHLN")!), "Qoi4YmPHLN")
    }

    func testRejections() {
        for s in ["https://example.com/Qoi4YmPHLN", "https://walk.pilgrimapp.org/", "https://walk.pilgrimapp.org/short",
                  "https://walk.pilgrimapp.org/Qoi4YmPHLN/audio/1.m4a", "Qoi4YmPHL", "Qoi4YmPHLN1", ""] {
            XCTAssertNil(HonorLink.parse(text: s), s)
        }
    }
}
```

- [ ] **Step 2: Register and run to verify it fails**

```bash
ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/HonorLinkTests.swift
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/HonorLinkTests 2>&1 | grep -E "error:|Executed"
```

- [ ] **Step 3: Create `HonorLink.swift`**

```swift
import Foundation

enum HonorLink {

    static let hosts: Set<String> = ["honor.pilgrimapp.org", "walk.pilgrimapp.org"]
    private static let idPattern = "^[A-Za-z0-9_-]{10}$"

    static func parse(_ url: URL) -> String? {
        guard let host = url.host?.lowercased(), hosts.contains(host) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1, isID(parts[0]) else { return nil }
        return parts[0]
    }

    static func parse(text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isID(trimmed) { return trimmed }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme) else { return nil }
        return parse(url)
    }

    private static func isID(_ s: String) -> Bool {
        s.range(of: idPattern, options: .regularExpression) != nil
    }
}

extension Notification.Name {
    static let pilgrimOpenWay = Notification.Name("pilgrimOpenWay")
}
```

- [ ] **Step 4: Entitlement and app entry**

`Pilgrim/Pilgrim.entitlements`: add
```xml
	<key>com.apple.developer.associated-domains</key>
	<array>
		<string>applinks:honor.pilgrimapp.org</string>
	</array>
```
Regenerate the provisioning profile in the developer portal before the first archive; the GHA TestFlight workflow signs with it.

`PilgrimApp.swift`: on the `ZStack`, add
```swift
            .onOpenURL { url in Self.route(url) }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL { Self.route(url) }
            }
```
and
```swift
    private static func route(_ url: URL) {
        guard let id = HonorLink.parse(url) else { return }
        NotificationCenter.default.post(name: .pilgrimOpenWay, object: nil, userInfo: ["shareId": id])
    }
```
`MainTabView` observes it: `.onReceive(NotificationCenter.default.publisher(for: .pilgrimOpenWay)) { note in if let id = note.userInfo?["shareId"] as? String { selectedTab = .path; coordinator.openWay(shareId: id) } }`. Setup-incomplete launches never mount `MainTabView`, so the link is dropped there by construction.

- [ ] **Step 5: Coordinator import flow**

`MainCoordinator`:
```swift
    enum HonorImportState: Equatable {
        case idle, fetching, gathering(progress: Double), ready, mediaMissing([String]), failed(WayError)
    }
    @Published var honorImportState: HonorImportState = .idle
    @Published var pendingLinkToast: String?
    private var importTask: Task<Void, Never>?
    private var gatheringCancellable: AnyCancellable?

    func openWay(shareId: String) {
        guard activeWalkViewModel == nil else { pendingLinkToast = "finish this walk first"; return }
        honorWaysPresented = false
        importTask?.cancel()
        honorImportState = .fetching
        importTask = Task { @MainActor in
            do {
                let way = try await WayImporter().importShare(id: shareId)
                honorOverviewWay = way
                gather(way)
            } catch let error as WayError {
                honorImportState = .failed(error)
            } catch {
                honorImportState = .failed(.unavailable)
            }
        }
    }

    func gather(_ way: Way) {
        let downloader = WayMediaDownloader.shared
        downloader.download(way)
        honorImportState = .gathering(progress: downloader.progress[way.id] ?? 0)
        gatheringCancellable = downloader.$progress.combineLatest(downloader.$active, downloader.$failures)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress, active, failures in
                guard let self else { return }
                if active.contains(way.id) {
                    self.honorImportState = .gathering(progress: progress[way.id] ?? 0)
                } else if let missing = failures[way.id], !missing.isEmpty {
                    self.honorImportState = .mediaMissing(missing)
                } else {
                    self.honorImportState = .ready
                }
            }
    }
```
`HonorWaysSheet`'s `onPaste` closure in `MainTabView` becomes `{ text in if let id = HonorLink.parse(text: text) { coordinator.openWay(shareId: id) } }`; replace `HonorLinkPreview.shareId(in:)` with `HonorLink.parse(text:)` and delete `HonorLinkPreview`. The overview sheet now presents while `honorImportState` is not `.idle` as well as when `honorOverviewWay` is set: while `.fetching` it shows a parchment card "reaching for the walk…"; `.failed(.notFound)` shows "couldn't find that walk. Check the link, or it may have returned to the trail."; `.failed(.returnedToTrail)` shows the tombstone line "This walk has returned to the trail"; `.failed(.unavailable)` shows "couldn't reach the walk" with a retry that calls `openWay` again. `HonorOverviewView` gains `importState: MainCoordinator.HonorImportState` and `onRetryMedia: () -> Void`: Begin is disabled during `.fetching` and `.gathering`, the card shows "gathering their voices · N%" under the counts, and `.mediaMissing` shows "try again" and "walk without the missing voices" (which sets the state to `.ready`). Own-walk Ways skip gathering: `openOverview(for:)` sets `.ready` when the source is `.ownWalk`.

Share-sheet copy: in the share flow's interactive section (`Scenes/WalkShare/`), add the caption "Anyone with the link can walk it there." under the Interactive toggle.

- [ ] **Step 6: Register, build, test, commit**

```bash
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Models/Honor/HonorLink.swift
xcodebuild build -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator 2>&1 | grep -E "error:|BUILD"
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/HonorLinkTests 2>&1 | grep -E "error:|Executed"
git add -A Pilgrim UnitTests Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(honor): walk it there — universal link, paste, gathering their voices"
```

---

### Task 20: Ways in Settings

**Files:**
- Create: `Pilgrim/Scenes/Settings/WaysListView.swift`
- Modify: `Pilgrim/Scenes/Settings/SettingsCards/DataCard.swift`

**Interfaces:**
- Produces: `WaysListView` (list of `WayStore.shared.list()` with title, date, size, "voices returned to the trail" when media is gone, swipe-to-delete calling `WayStore.shared.delete(id:)`, and a confirmed "Delete all Ways"); a `DataCard` row "Ways" with detail "N ways · X.X MB".

- [ ] **Step 1: Create `WaysListView.swift`**

```swift
import SwiftUI

struct WaysListView: View {
    @State private var ways: [Way] = []
    @State private var confirmDeleteAll = false

    var body: some View {
        List {
            if ways.isEmpty {
                Text("no ways yet").font(Constants.Typography.caption).foregroundColor(.fog)
            }
            ForEach(ways, id: \.id) { way in
                VStack(alignment: .leading, spacing: 2) {
                    Text(way.title).font(Constants.Typography.body).foregroundColor(.ink)
                    Text(detail(for: way)).font(Constants.Typography.caption).foregroundColor(.fog)
                }
            }
            .onDelete { offsets in
                for index in offsets { WayStore.shared.delete(id: ways[index].id) }
                reload()
            }
            if !ways.isEmpty {
                Button("Delete all Ways", role: .destructive) { confirmDeleteAll = true }
                    .font(Constants.Typography.button)
            }
        }
        .navigationTitle("Ways")
        .onAppear(perform: reload)
        .alert("Delete all Ways?", isPresented: $confirmDeleteAll) {
            Button("Delete", role: .destructive) {
                ways.forEach { WayStore.shared.delete(id: $0.id) }
                reload()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their voices and photos leave this phone. Your own walks are untouched.")
        }
    }

    private func reload() {
        WayStore.shared.sweepExpired(now: Date())
        ways = WayStore.shared.list()
    }

    private func detail(for way: Way) -> String {
        let date = DateFormatter.localizedString(from: way.departedAt, dateStyle: .medium, timeStyle: .none)
        let mb = String(format: "%.1f MB", Double(WayStore.shared.diskUsage(id: way.id)) / 1_000_000)
        if way.voiceCount + way.photoCount > 0, !WayStore.shared.hasMedia(id: way.id) {
            return "\(date) · voices returned to the trail"
        }
        return "\(date) · \(mb)"
    }
}
```

`DataCard.swift`: add under the existing row
```swift
            NavigationLink { WaysListView() } label: {
                settingNavRow(label: "Ways", detail: waysDetail)
            }
```
with `@State private var waysDetail: String = ""` computed in `.onAppear` as `"\(count) ways · \(String(format: "%.1f MB", mb))"` from `WayStore.shared.list().count` and `totalDiskUsage()`.

- [ ] **Step 2: Register, build, commit**

```bash
ruby scripts/xcode-add.rb Pilgrim Pilgrim/Scenes/Settings/WaysListView.swift
xcodebuild build -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator 2>&1 | grep -E "error:|BUILD"
git add -A Pilgrim Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(honor): Ways storage row in Settings"
```

---

### Task 21: Recording coordinates in the share payload

**Files:**
- Modify: `Pilgrim/Models/Share/SharePayload.swift:103-119`
- Modify: `Pilgrim/Models/Share/TourBuilder.swift:5-20`, `:43-79`, `:111-130`
- Modify: `Pilgrim/Scenes/WalkShare/WalkShareViewModel.swift` (the `tourCandidates` construction; grep `TourBuilder.candidates(`)
- Test: `UnitTests/TourBuilderTests.swift` (existing; add one test)

**Interfaces:**
- Produces: `SharePayload.TourRecording.lat: Double?`, `.lon: Double?` (encoded as `lat`/`lon`); `TourRecordingCandidate.lat/lon`; `TourBuilder.candidates(for walk:)` fills them from the full-resolution route sample nearest each recording's `startDate`, before any downsampling.

- [ ] **Step 1: Write the failing test**

Append to `UnitTests/TourBuilderTests.swift` (read the file for its walk fixture helper and mirror it):
```swift
    func testCandidatesCarryTheRecordingCoordinate() {
        let start = DateFactory.makeDate(2026, 5, 1, 8, 0, 0)
        let route = (0..<5).map { i in
            TempRouteDataSample(uuid: nil, timestamp: start.addingTimeInterval(Double(i) * 60), latitude: 42.0 + Double(i) * 0.001,
                                longitude: -8.0, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, speed: 1, direction: 0)
        }
        let rec = TempVoiceRecording(uuid: nil, startDate: start.addingTimeInterval(125), endDate: start.addingTimeInterval(160),
                                     duration: 35, fileRelativePath: "Recordings/x.m4a", transcription: nil)
        let walk = WalkDataFactory.makeWalk(startDate: start, routeData: route, voiceRecordings: [rec])
        let candidate = TourBuilder.candidates(for: walk).first
        XCTAssertEqual(candidate?.lat ?? 0, 42.002, accuracy: 0.0001)
        XCTAssertEqual(candidate?.lon ?? 0, -8.0, accuracy: 0.0001)
        let items = TourBuilder.tourItems(candidates: TourBuilder.candidates(for: walk).map { var c = $0; c.fileURL = URL(fileURLWithPath: "/tmp/x"); return c }, trimM: 0)
        XCTAssertEqual(items.tour.recordings.first?.lat ?? 0, 42.002, accuracy: 0.0001)
    }
```

- [ ] **Step 2: Implement**

`SharePayload.TourRecording`: add `let lat: Double?` and `let lon: Double?`, and `case lat, lon` to its `CodingKeys`. `TourRecordingCandidate`: add `let lat: Double?`, `let lon: Double?`. In `TourBuilder.candidates(for:)`, before the `return sorted.enumerated()...`, compute `let samples = walk.routeData`, and inside the closure:
```swift
            let nearest = samples.min { abs($0.timestamp.timeIntervalSince(rec.startDate)) < abs($1.timestamp.timeIntervalSince(rec.startDate)) }
```
passing `lat: nearest?.latitude, lon: nearest?.longitude` into the candidate. In `tourItems`, pass `lat: c.lat, lon: c.lon` into `SharePayload.TourRecording`. Fix every other `TourRecordingCandidate(` and `TourRecording(` initializer call the compiler flags (tests included) by adding `lat: nil, lon: nil`.

- [ ] **Step 3: Test, commit**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/TourBuilderTests 2>&1 | grep -E "error:|Executed"
git add -A Pilgrim UnitTests
git commit -m "feat(share): recordings carry the coordinate they were spoken at"
```

The worker must accept the new fields before this ships (spec, worker contract item 4); until then the worker's validator ignores unknown keys, so the field is harmless on old workers. Verify with `grep -n "lat\|unknown" ../pilgrim-worker/src/handlers/validate-share.ts` before merging.

---

### Task 22: Phase B gate, PR

- [ ] **Step 1: Full suite and lint**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "Executed|error:" | tail -3
swiftlint lint --quiet | head
```
Expected: `0 failures`, no lint errors.

- [ ] **Step 2: Device checklist (record results in the PR body)**

1. Tap "walk it there" on a live share in Safari on a phone with the app: the app opens on the overview. If Safari stays, the sibling subdomain is not treated as cross-domain; fall back to the paste field and record the finding for the worker plan.
2. Verify `https://app-site-association.cdn-apple.com/a/v1/honor.pilgrimapp.org` returns the JSON.
3. Airplane mode after gathering: Begin, walk, voices play from disk.
4. Reply here on a voice, finish the walk, share it: the summary shows one reply; the share payload carries no `honor` field (slice four).
5. Delete the Way in Settings: the honor walk's summary shows "a way that has been removed" and no ghost.

- [ ] **Step 3: Open the PR**

```bash
git push -u origin feat/honor-mode
gh pr create --title "feat: Honor — walk in their steps (slice one)" --body-file docs/superpowers/plans/2026-09-01-honor-mode-slice-one.md
```
Per the house rule, no TestFlight dispatch without the user's explicit go.
