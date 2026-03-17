# Waypoint Marking + Prompt Improvements Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add waypoint marking during walks (drop labeled pins at meaningful spots) and improve AI prompts (deeper intention framing, prompts for all walks including silent ones).

**Architecture:** New PilgrimV6 CoreStore migration adds a Waypoint entity. Waypoints flow through the existing WalkBuilder relay pattern → NewWalk snapshot → DataManager persist. The WaypointMarkingSheet presents predefined chips (Peaceful, Beautiful, etc.) with icons. PromptGenerator adapts preambles and instructions for silent walks and gives intention a more prominent framing.

**Tech Stack:** SwiftUI, CoreStore (CoreData ORM), Combine/CombineExt (CurrentValueRelay), MapboxMaps

**Spec:** `docs/superpowers/specs/2026-03-16-waypoint-marking-prompt-improvements-design.md`

---

## Chunk 1: Data Layer (Migration + In-Memory + Persistence)

### Task 1: WaypointInterface Protocol

**Files:**
- Create: `Pilgrim/Protocols/DataInterfaces/WaypointInterface.swift`

- [ ] **Step 1: Create WaypointInterface**

Follow the pattern from `WalkEventInterface.swift`. The protocol inherits from `DataInterface` (not `SampleInterface` — waypoints aren't time-range samples, they're point-in-time markers).

```swift
import Foundation

public protocol WaypointInterface: DataInterface {
    var latitude: Double { get }
    var longitude: Double { get }
    var label: String { get }
    var icon: String { get }
    var timestamp: Date { get }
}

public extension WaypointInterface {
    var latitude: Double { throwOnAccess() }
    var longitude: Double { throwOnAccess() }
    var label: String { throwOnAccess() }
    var icon: String { throwOnAccess() }
    var timestamp: Date { throwOnAccess() }
}
```

- [ ] **Step 2: Add to Xcode project and commit**

Add the file to the Pilgrim target in the DataInterfaces group. Commit.

```
git add Pilgrim/Protocols/DataInterfaces/WaypointInterface.swift
git commit -m "feat: add WaypointInterface protocol"
```

### Task 2: TempV4.Waypoint In-Memory Class

**Files:**
- Create: `Pilgrim/Models/Data/Temp/Versions/TempWaypoint.swift`
- Modify: `Pilgrim/Models/Data/Temp/Temp.swift`
- Modify: `Pilgrim/Models/Data/Temp/Versions/TempV4.swift`

- [ ] **Step 1: Create TempV4.Waypoint class**

Follow the pattern from `TempV4.WorkoutEvent` (TempV4.swift:126-141). Must be `Codable` for backup compatibility.

```swift
import Foundation

extension TempV4 {
    public class Waypoint: Codable, TempValueConvertible {
        public var uuid: UUID?
        public var latitude: Double
        public var longitude: Double
        public var label: String
        public var icon: String
        public var timestamp: Date

        public init(uuid: UUID?, latitude: Double, longitude: Double, label: String, icon: String, timestamp: Date) {
            self.uuid = uuid
            self.latitude = latitude
            self.longitude = longitude
            self.label = label
            self.icon = icon
            self.timestamp = timestamp
        }

        public var asTemp: TempWaypoint { return self }
    }
}

extension TempV4.Waypoint: WaypointInterface {}
```

- [ ] **Step 2: Add `_waypoints` to TempV4.Workout**

In `TempV4.swift`, add the field to `TempV4.Workout` (after `activityIntervals` around line 48):

```swift
public var waypoints: [TempV4.Waypoint]
```

Update the `init` (line 65) to accept `waypoints: [TempV4.Waypoint] = []` and assign it.

For `Codable` backward compatibility (existing backups won't have this key), add:

```swift
private enum CodingKeys: String, CodingKey {
    // all existing fields...
    case waypoints
}

public required init(from decoder: Decoder) throws {
    // decode all existing fields...
    waypoints = (try? container.decodeIfPresent([TempV4.Waypoint].self, forKey: .waypoints)) ?? []
}
```

If `TempV4.Workout` currently relies on synthesized Codable, you'll need to check whether adding a default-valued field breaks decoding. If it uses synthesized Codable, `decodeIfPresent` with `?? []` in a custom `init(from:)` is the safe path.

- [ ] **Step 3: Add TempWaypoint type alias and update copy init in Temp.swift**

In `Temp.swift`, add the type alias (after the other aliases around line 156):

```swift
typealias TempWaypoint = TempV4.Waypoint
```

Update `TempWalk.init(from:)` (around line 30-60) to include waypoints. Add to the `super.init` call:

```swift
waypoints: object.waypoints.map { TempV4.Waypoint(uuid: $0.uuid, latitude: $0.latitude, longitude: $0.longitude, label: $0.label, icon: $0.icon, timestamp: $0.timestamp) }
```

- [ ] **Step 4: Add to Xcode project and commit**

Add `TempWaypoint.swift` to the Pilgrim target. Commit all three files.

```
git commit -m "feat: add TempV4.Waypoint in-memory class and type alias"
```

### Task 3: WalkInterface + Walk.swift Waypoints Property

**Files:**
- Modify: `Pilgrim/Protocols/DataInterfaces/WalkInterface.swift`
- Modify: `Pilgrim/Models/Data/DataModels/Walk.swift`

- [ ] **Step 1: Add waypoints to WalkInterface**

In `WalkInterface.swift`, add to the protocol (around line 78, after `activityIntervals`):

```swift
var waypoints: [WaypointInterface] { get }
```

In the default extension (around line 110, near `activityIntervals` default), add:

```swift
var waypoints: [WaypointInterface] { [] }
```

Use `[]` not `throwOnAccess()` — pre-V6 walks and backup restores need a safe default.

- [ ] **Step 2: Expose waypoints in Walk.swift**

In `Walk.swift` (around line 147, in the WalkInterface extension), add:

```swift
public var waypoints: [WaypointInterface] {
    threadSafeSyncReturn { Array(self._waypoints.value) as [WaypointInterface] }
}
```

This will compile only after PilgrimV6 adds the `_waypoints` relationship. For now, use:

```swift
public var waypoints: [WaypointInterface] { [] }
```

We'll update this to the real implementation in Task 5 after PilgrimV6 exists.

- [ ] **Step 3: Commit**

```
git commit -m "feat: add waypoints property to WalkInterface and Walk"
```

### Task 4: WalkBuilder Waypoint Relay

**Files:**
- Modify: `Pilgrim/Models/Walk/WalkBuilder/WalkBuilder.swift`
- Modify: `Pilgrim/Models/Data/NewWalk.swift`

- [ ] **Step 1: Add waypoints relay to WalkBuilder**

In WalkBuilder.swift, add the relay (after `activityIntervalsRelay`, around line 210):

```swift
private let waypointsRelay = CurrentValueRelay<[TempWaypoint]>([])
```

Add public publisher (follow the pattern of `voiceRecordingsPublisher`):

```swift
public var waypointsPublisher: AnyPublisher<[TempWaypoint], Never> {
    waypointsRelay.asBackgroundPublisher()
}
```

Add flush method (follow `flushVoiceRecordings` pattern around line 85):

```swift
public func flushWaypoints(_ waypoints: [TempWaypoint]) {
    waypointsRelay.accept(waypoints)
}
```

Add public method to append a single waypoint:

```swift
public func addWaypoint(_ waypoint: TempWaypoint) {
    waypointsRelay.accept(waypointsRelay.value + [waypoint])
}
```

- [ ] **Step 2: Pass waypoints to NewWalk in createSnapshot and createCheckpointSnapshot**

In `createSnapshot()` (around line 406), add `waypoints: waypointsRelay.value` to the `NewWalk` init call.

In `createCheckpointSnapshot()` (around line 370), add `waypoints: waypointsRelay.value` to the `NewWalk` init call.

- [ ] **Step 3: Reset waypoints in reset()**

In `reset()` (around line 425), add:

```swift
waypointsRelay.accept([])
```

- [ ] **Step 4: Update NewWalk init to accept waypoints**

In `NewWalk.swift` (line 26), add `waypoints: [TempV4.Waypoint] = []` parameter. Pass it through to `super.init(... waypoints: waypoints)`.

- [ ] **Step 5: Build to verify compilation**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build
```

- [ ] **Step 6: Commit**

```
git commit -m "feat: add waypoints relay to WalkBuilder and NewWalk"
```

### Task 5: PilgrimV6 Migration + CoreStore Entity

**Files:**
- Create: `Pilgrim/Models/Data/DataModels/Versions/PilgrimV6.swift`
- Create: `Pilgrim/Models/Data/DataModels/Waypoint.swift`
- Modify: `Pilgrim/Models/Data/DataManager.swift`
- Modify: `Pilgrim/Models/Data/DataModels/Walk.swift`

- [ ] **Step 1: Create PilgrimV6.swift**

Follow PilgrimV5.swift as template. Key elements:

```swift
import CoreStore

public enum PilgrimV6: DataModelProtocol {
    static let identifier = "PilgrimV6"

    static let schema = CoreStoreSchema(
        modelVersion: PilgrimV6.identifier,
        entities: [
            Entity<PilgrimV6.Workout>(PilgrimV5.Workout.entityIdentifier),
            Entity<PilgrimV6.WorkoutPause>(PilgrimV5.WorkoutPause.entityIdentifier),
            Entity<PilgrimV6.WorkoutEvent>(PilgrimV5.WorkoutEvent.entityIdentifier),
            Entity<PilgrimV6.WorkoutRouteDataSample>(PilgrimV5.WorkoutRouteDataSample.entityIdentifier),
            Entity<PilgrimV6.WorkoutHeartRateDataSample>(PilgrimV5.WorkoutHeartRateDataSample.entityIdentifier),
            Entity<PilgrimV6.Event>(PilgrimV5.Event.entityIdentifier),
            Entity<PilgrimV6.VoiceRecording>(PilgrimV5.VoiceRecording.entityIdentifier),
            Entity<PilgrimV6.ActivityInterval>(PilgrimV5.ActivityInterval.entityIdentifier),
            Entity<PilgrimV6.Waypoint>("Waypoint")
        ]
    )
}
```

The Waypoint entity class (inside the PilgrimV6 enum):

```swift
class Waypoint: CoreStoreObject {
    @Field.Stored("uuid") var _uuid: UUID?
    @Field.Stored("latitude") var _latitude: Double = 0
    @Field.Stored("longitude") var _longitude: Double = 0
    @Field.Stored("label") var _label: String = ""
    @Field.Stored("icon") var _icon: String = ""
    @Field.Stored("timestamp") var _timestamp: Date = Date()
    @Field.Relationship("workout", inverse: \.$_waypoints) var _workout: PilgrimV6.Workout?
}
```

Add `_waypoints` relationship to Workout (copying all existing PilgrimV5.Workout fields plus):

```swift
@Field.Relationship("waypoints") var _waypoints: Set<PilgrimV6.Waypoint>
```

All other entity classes (WorkoutPause, WorkoutEvent, etc.) are identical to PilgrimV5 versions — they just live under the PilgrimV6 namespace. Use typealiases:

```swift
typealias WorkoutPause = PilgrimV5.WorkoutPause
typealias WorkoutEvent = PilgrimV5.WorkoutEvent
// etc.
```

**Wait** — CoreStore may require distinct classes per schema version. Check how PilgrimV5 handled entities from PilgrimV4. If it reuses via typealias, follow that pattern. If each version re-declares, do the same.

Migration mapping provider from PilgrimV5 → PilgrimV6:

```swift
static let mappingProvider = CustomSchemaMappingProvider(
    from: PilgrimV5.identifier,
    to: PilgrimV6.identifier,
    entityMappings: [
        .transformEntity(sourceEntity: "Workout", destinationEntity: "Workout",
                        transformer: .init(enumerateAttributes)),
        // ... same for all existing entities ...
        .insertEntity(destinationEntity: "Waypoint")
    ]
)
```

Migration chain:

```swift
static let migrationChain: [DataModelProtocol.Type] = [
    OutRunV1.self, OutRunV2.self, OutRunV3.self, OutRunV3to4.self, OutRunV4.self,
    PilgrimV1.self, PilgrimV2.self, PilgrimV3.self, PilgrimV4.self, PilgrimV5.self, PilgrimV6.self
]
```

- [ ] **Step 2: Create Waypoint.swift forwarding file**

Follow VoiceRecording.swift pattern:

```swift
import CoreStore

public typealias Waypoint = PilgrimV6.Waypoint

extension Waypoint: WaypointInterface {
    public var uuid: UUID? { threadSafeSyncReturn { self._uuid.value } }
    public var latitude: Double { threadSafeSyncReturn { self._latitude.value } }
    public var longitude: Double { threadSafeSyncReturn { self._longitude.value } }
    public var label: String { threadSafeSyncReturn { self._label.value } }
    public var icon: String { threadSafeSyncReturn { self._icon.value } }
    public var timestamp: Date { threadSafeSyncReturn { self._timestamp.value } }
}

extension Waypoint: TempValueConvertible {
    public var asTemp: TempWaypoint {
        TempWaypoint(uuid: uuid, latitude: latitude, longitude: longitude, label: label, icon: icon, timestamp: timestamp)
    }
}
```

- [ ] **Step 3: Update Walk.swift to expose real waypoints relationship**

Replace the temporary `{ [] }` from Task 3 with:

```swift
public var waypoints: [WaypointInterface] {
    threadSafeSyncReturn { Array(self._waypoints.value) as [WaypointInterface] }
}
```

- [ ] **Step 4: Update DataManager.swift**

Change default parameter (line 55):
```swift
public static func setup(dataModel: DataModelProtocol.Type = PilgrimV6.self, ...)
```

Add waypoint persistence in `persistRelatedEntities` (after voiceRecordings, around line 295):
```swift
for tempItem in source.waypoints {
    let waypoint = transaction.create(Into<Waypoint>())
    waypoint._uuid .= tempItem.uuid ?? UUID()
    waypoint._latitude .= tempItem.latitude
    waypoint._longitude .= tempItem.longitude
    waypoint._label .= tempItem.label
    waypoint._icon .= tempItem.icon
    waypoint._timestamp .= tempItem.timestamp
    waypoint._workout .= walk
}
```

Same pattern in `persistNewRelatedEntities` (after voiceRecordings, around line 365), with `where tempItem.uuid == nil` guard.

Add to `deleteAll` (around line 800):
```swift
try transaction.deleteAll(From<Waypoint>())
```

- [ ] **Step 5: Update Walk typealias**

In `Walk.swift` (line 26), change:
```swift
public typealias Walk = PilgrimV6.Workout
```

- [ ] **Step 6: Add files to Xcode project, build, and commit**

Add PilgrimV6.swift and Waypoint.swift to Pilgrim target.

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build
git commit -m "feat: add PilgrimV6 migration with Waypoint entity"
```

---

## Chunk 2: UI Layer (Waypoint Marking + Walk Integration)

### Task 6: WaypointMarkingSheet UI

**Files:**
- Create: `Pilgrim/Scenes/ActiveWalk/WaypointMarkingSheet.swift`

- [ ] **Step 1: Create WaypointMarkingSheet**

Half-sheet with predefined chips and custom text input. Follow IntentionSettingView patterns (same project conventions).

```swift
import SwiftUI

struct WaypointChip: Identifiable {
    let id = UUID()
    let label: String
    let icon: String

    static let presets: [WaypointChip] = [
        WaypointChip(label: "Peaceful", icon: "leaf"),
        WaypointChip(label: "Beautiful", icon: "eye"),
        WaypointChip(label: "Grateful", icon: "heart"),
        WaypointChip(label: "Resting", icon: "figure.seated"),
        WaypointChip(label: "Inspired", icon: "sparkles"),
    ]
}

struct WaypointMarkingSheet: View {
    let onMark: (String, String) -> Void  // (label, icon)
    let onDismiss: () -> Void

    @State private var customText = ""
    @FocusState private var isTextFieldFocused: Bool

    private let maxCharacters = 50

    var body: some View {
        VStack(spacing: 0) {
            Text("Mark This Spot")
                .font(Constants.Typography.heading)
                .foregroundColor(Color.ink.opacity(0.8))
                .padding(.top, 12)

            chipsSection
                .padding(.top, Constants.UI.Padding.big)

            customSection
                .padding(.top, Constants.UI.Padding.normal)

            Spacer()

            Button("Cancel") { onDismiss() }
                .font(Constants.Typography.button)
                .foregroundColor(.fog)
                .padding(.bottom, Constants.UI.Padding.big)
        }
        .padding(.horizontal, Constants.UI.Padding.big)
    }

    private var chipsSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: Constants.UI.Padding.small) {
            ForEach(WaypointChip.presets) { chip in
                Button {
                    onMark(chip.label, chip.icon)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: chip.icon)
                            .font(.title3)
                        Text(chip.label)
                            .font(Constants.Typography.caption)
                    }
                    .foregroundColor(.ink.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.normal)
                            .fill(Color.parchmentSecondary.opacity(0.4))
                    )
                }
            }
        }
    }

    private var customSection: some View {
        HStack(spacing: Constants.UI.Padding.small) {
            TextField("Or type your own...", text: $customText)
                .font(Constants.Typography.body)
                .foregroundColor(.ink)
                .focused($isTextFieldFocused)
                .onChange(of: customText) { _, newValue in
                    if newValue.count > maxCharacters {
                        customText = String(newValue.prefix(maxCharacters))
                    }
                }
                .padding(Constants.UI.Padding.small)
                .padding(.horizontal, Constants.UI.Padding.small)
                .background(
                    RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.small)
                        .fill(Color.parchmentSecondary.opacity(0.5))
                )

            Button("Mark") {
                let trimmed = customText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                onMark(trimmed, "mappin")
            }
            .font(Constants.Typography.button)
            .foregroundColor(customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .fog.opacity(0.3) : .stone)
            .disabled(customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}
```

- [ ] **Step 2: Add to Xcode project and commit**

```
git commit -m "feat: add WaypointMarkingSheet UI"
```

### Task 7: ActiveWalkViewModel Waypoint Support

**Files:**
- Modify: `Pilgrim/Scenes/ActiveWalk/ActiveWalkViewModel.swift`

- [ ] **Step 1: Add waypoint state and method**

Add published property (after `intention`, around line 36):

```swift
@Published var waypoints: [TempWaypoint] = []
```

Add method to append a waypoint using current location:

```swift
func addWaypoint(label: String, icon: String) {
    guard let location = currentLocation else { return }
    let waypoint = TempWaypoint(
        uuid: nil,
        latitude: location.latitude,
        longitude: location.longitude,
        label: label,
        icon: icon,
        timestamp: Date()
    )
    builder.addWaypoint(waypoint)
    waypoints.append(waypoint)
}
```

- [ ] **Step 2: Commit**

```
git commit -m "feat: add waypoint management to ActiveWalkViewModel"
```

### Task 8: Wire Waypoint Sheet into ActiveWalkView + WalkOptionsSheet

**Files:**
- Modify: `Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift`
- Modify: `Pilgrim/Scenes/ActiveWalk/WalkOptionsSheet.swift`

- [ ] **Step 1: Add waypoint callbacks to WalkOptionsSheet**

Add new callback and property:

```swift
let onDropWaypoint: () -> Void
let waypointCount: Int
```

Add a new `optionRow` after "Set Intention":

```swift
optionRow(
    icon: "mappin",
    title: "Drop Waypoint",
    subtitle: waypointCount > 0 ? "\(waypointCount) marked" : nil
) {
    onDropWaypoint()
}
```

- [ ] **Step 2: Wire waypoint sheet in ActiveWalkView**

Add state:
```swift
@State private var showWaypoint = false
```

Add sheet modifier (after the intention sheet):
```swift
.sheet(isPresented: $showWaypoint) {
    WaypointMarkingSheet(
        onMark: { label, icon in
            viewModel.addWaypoint(label: label, icon: icon)
            showWaypoint = false
        },
        onDismiss: { showWaypoint = false }
    )
    .presentationDetents([.medium])
    .presentationDragIndicator(.visible)
    .presentationBackground(Color.parchment.opacity(0.95))
}
```

Update the `WalkOptionsSheet` init in the options sheet to pass the new params:
```swift
WalkOptionsSheet(
    onSetIntention: { ... },
    currentIntention: viewModel.intention,
    onDropWaypoint: {
        showOptions = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showWaypoint = true
        }
    },
    waypointCount: viewModel.waypoints.count
)
```

- [ ] **Step 3: Build and commit**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build
git commit -m "feat: wire waypoint marking into walk screen"
```

### Task 9: Waypoint Map Annotations in Summary

**Files:**
- Modify: `Pilgrim/Models/Walk/MapManagement/PilgrimAnnotation.swift`
- Modify: `Pilgrim/Views/PilgrimMapView.swift`
- Modify: `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift`

- [ ] **Step 1: Add .waypoint kind to PilgrimAnnotation**

```swift
case waypoint(label: String, icon: String)
```

- [ ] **Step 2: Handle .waypoint in PilgrimMapView annotation rendering**

In `applyAnnotations()` (around line 240), add a case in the switch:

```swift
case .waypoint:
    annotation.circleRadius = .constant(7)
    annotation.circleColor = .constant(StyleColor(UIColor(.stone)))
    annotation.circleOpacity = .constant(0.8)
    annotation.circleStrokeColor = .constant(StyleColor(UIColor(.parchment)))
    annotation.circleStrokeWidth = .constant(1.5)
```

- [ ] **Step 3: Add waypointPinAnnotations to WalkSummaryView**

Follow the `voicePinAnnotations` pattern (around line 789). Add computed property in the Route Segments extension:

```swift
var waypointPinAnnotations: [PilgrimAnnotation] {
    walk.waypoints.map { waypoint in
        PilgrimAnnotation(
            coordinate: CLLocationCoordinate2D(latitude: waypoint.latitude, longitude: waypoint.longitude),
            kind: .waypoint(label: waypoint.label, icon: waypoint.icon)
        )
    }
}
```

Update `allPinAnnotations` (around line 751) to include waypoints:

```swift
var allPinAnnotations: [PilgrimAnnotation] {
    startEndAnnotations + meditationPinAnnotations + voicePinAnnotations + waypointPinAnnotations
}
```

- [ ] **Step 4: Build and commit**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build
git commit -m "feat: display waypoint pins on walk summary map"
```

---

## Chunk 3: Prompt Improvements

### Task 10: Intention Prominence in Prompts

**Files:**
- Modify: `Pilgrim/Models/PromptGenerator.swift`

- [ ] **Step 1: Upgrade intention framing in buildPrompt**

In `buildPrompt()` (around line 365), replace the current intention block:

```swift
if let intention = intention {
    sections += "\n\n**Intention for this walk:** \"\(intention)\""
}
```

With the deeper framing:

```swift
if let intention = intention {
    sections += "\n\n**The walker's intention:** \"\(intention)\"\nThis intention was set deliberately before the walk began. It represents what the walker chose to carry with them. Let it be the lens through which you interpret everything below."
}
```

Replace the instruction append (around line 408):

```swift
if let intention = intention {
    fullInstruction += " The walker set this intention before walking: '\(intention)'. Let this purpose guide your response."
}
```

With:

```swift
if let intention = intention {
    fullInstruction += " Ground your response in the walker's stated intention: '\(intention)'. Return to it. Help them see how their walk — its pace, its pauses, its moments — spoke to this purpose."
}
```

- [ ] **Step 2: Commit**

```
git commit -m "feat: deepen intention framing in AI prompts"
```

### Task 11: Waypoint Context in Prompts

**Files:**
- Modify: `Pilgrim/Models/PromptGenerator.swift`
- Modify: `Pilgrim/Scenes/Prompts/PromptListView.swift`

- [ ] **Step 1: Add WaypointContext struct and parameter to PromptGenerator**

Add struct (after `WalkSnippet`):

```swift
struct WaypointContext {
    let label: String
    let icon: String
    let timestamp: Date
    let coordinate: (lat: Double, lon: Double)
}
```

Add `waypoints: [WaypointContext] = []` parameter to `generate()`, `generateCustom()`, `generateAll()`, and `buildPrompt()`. Pass through from each caller.

- [ ] **Step 2: Add waypoint section to buildPrompt**

After the pace section (before transcription), add:

```swift
if !waypoints.isEmpty {
    let lines = waypoints.map { wp in
        "[\(timeFormatter.string(from: wp.timestamp))] \(wp.label)"
    }.joined(separator: "\n")
    sections += "\n\n**Waypoints marked during walk:**\n\(lines)"
}
```

- [ ] **Step 3: Pass waypoints from PromptListView**

In `PromptListView`, construct waypoint context in `generatePrompts()` and `regenerateCustomPrompts()`:

```swift
let waypointContexts = walk.waypoints.map { wp in
    PromptGenerator.WaypointContext(
        label: wp.label, icon: wp.icon, timestamp: wp.timestamp,
        coordinate: (lat: wp.latitude, lon: wp.longitude)
    )
}
```

Pass `waypoints: waypointContexts` to all `PromptGenerator` calls.

- [ ] **Step 4: Build and commit**

```
git commit -m "feat: include waypoint context in AI prompts"
```

### Task 12: Prompts for All Walks (Silent Walk Support)

**Files:**
- Modify: `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift`
- Modify: `Pilgrim/Models/PromptGenerator.swift`

- [ ] **Step 1: Remove transcription gate on prompts button**

In `WalkSummaryView.swift`, change (around line 63):

```swift
if !transcriptions.isEmpty {
    promptsButton
}
```

To:

```swift
promptsButton
```

- [ ] **Step 2: Adapt promptsButton subtitle**

In the `promptsButton` computed property, update the subtitle:

```swift
if transcriptions.isEmpty {
    Text("Reflect on your walk")
        .font(Constants.Typography.caption)
        .foregroundColor(.fog)
} else {
    Text("\(transcriptions.count) transcription\(transcriptions.count == 1 ? "" : "s") available")
        .font(Constants.Typography.caption)
        .foregroundColor(.fog)
}
```

- [ ] **Step 3: Add silent-walk preambles and instructions to PromptGenerator**

In `generate()`, add a `hasSpeech` flag:

```swift
let hasSpeech = !recordings.isEmpty
```

For each style, add a silent-walk variant of the preamble and instruction. When `!hasSpeech`, use the silent variant. Example for `.contemplative`:

```swift
if hasSpeech {
    preamble = "During a walking meditation, these words arose naturally..."
    instruction = "Please receive these walking thoughts with gentleness..."
} else {
    preamble = "This walk was taken in silence — no words were spoken, only movement. The walker chose presence over expression, letting the body speak through pace, pauses, and the places it was drawn to."
    instruction = "Reflect on what this silent walk might reveal. What does its rhythm suggest? Its pauses, its waypoints, its duration? Help the walker see what their body and feet were saying when their voice was still. Respond in a contemplative, unhurried tone."
}
```

Do the same for all six styles (reflective, creative, gratitude, philosophical, journaling).

In `buildPrompt()`, make the transcription section conditional:

```swift
if !transcription.isEmpty {
    sections += """

    **Walking Transcription:**

    \(transcription)
    """
}
```

- [ ] **Step 4: Build and run tests**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

- [ ] **Step 5: Commit**

```
git commit -m "feat: generate AI prompts for all walks including silent ones"
```

---

## Chunk 4: Verification + Xcode Project

### Task 13: Add All New Files to Xcode Project

**Files:**
- Modify: `Pilgrim.xcodeproj/project.pbxproj`

- [ ] **Step 1: Verify all new files are in the project**

New files that need Xcode project registration:
- `Pilgrim/Protocols/DataInterfaces/WaypointInterface.swift` → Pilgrim target
- `Pilgrim/Models/Data/Temp/Versions/TempWaypoint.swift` → Pilgrim target
- `Pilgrim/Models/Data/DataModels/Versions/PilgrimV6.swift` → Pilgrim target
- `Pilgrim/Models/Data/DataModels/Waypoint.swift` → Pilgrim target
- `Pilgrim/Scenes/ActiveWalk/WaypointMarkingSheet.swift` → Pilgrim target

Add any missing files to the project by editing `project.pbxproj`.

- [ ] **Step 2: Full build and test**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

- [ ] **Step 3: Final commit if any project file changes needed**

```
git commit -m "chore: register new files in Xcode project"
```
