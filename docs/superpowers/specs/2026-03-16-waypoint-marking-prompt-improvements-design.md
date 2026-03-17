# Waypoint Marking + Prompt Improvements

## Overview

Two additions to the walk experience:

1. **Waypoint marking** — drop labeled pins at meaningful spots during a walk. Pins appear on the summary map and flow into AI prompts as emotional/sensory context.
2. **Prompt improvements** — make intention more central in AI prompts, and generate prompts for all walks (not just those with voice recordings).

## Waypoint Marking

### User Flow

1. During a walk, tap Options (ellipsis button, top-left of map)
2. Tap "Drop Waypoint" row in WalkOptionsSheet
3. Half-sheet appears with predefined chips and a custom text field
4. Tap a chip or type custom text (50 char max) + tap "Mark"
5. Current GPS + timestamp captured, sheet dismisses
6. Multiple waypoints per walk allowed
7. "Drop Waypoint" row shows count subtitle when waypoints exist (e.g., "2 marked")

### Predefined Chips

| Chip | SF Symbol |
|------|-----------|
| Peaceful | `leaf` |
| Beautiful | `eye` |
| Grateful | `heart` |
| Resting | `figure.seated` |
| Inspired | `sparkles` |
| Custom (text) | `mappin` |

### Walk Summary Display

- Waypoint icons appear on the route map as small annotation dots using the chip's SF Symbol
- Tapping a pin shows the label as a callout
- No separate list section — keeps the summary clean

### Data Model — PilgrimV6 Migration

New `Waypoint` entity:

| Field | Type | Notes |
|-------|------|-------|
| `uuid` | `UUID?` | Assigned on save |
| `latitude` | `Double` | GPS lat at time of marking |
| `longitude` | `Double` | GPS lon at time of marking |
| `label` | `String` | Chip label or custom text |
| `icon` | `String` | SF Symbol name |
| `timestamp` | `Date` | When the waypoint was marked |
| `workout` | Relationship | Back-reference to parent Walk |

Migration: `PilgrimV6 → PilgrimV6` using `CustomSchemaMappingProvider`. All existing entities pass through with `enumerateAttributes`. `Waypoint` uses `.insertEntity`. The migration chain lives on `PilgrimV6` (not patched onto PilgrimV5). `DataManager.setup`'s default `dataModel` parameter must be updated from `PilgrimV5.self` to `PilgrimV6.self`.

### In-Memory Layer

- New `TempV4.Waypoint` class with matching fields (no CoreStore dependency), `Codable` conformance
- New `WaypointInterface` protocol following `WalkEventInterface` pattern
- `TempV4.Waypoint` conforms to `WaypointInterface`
- `TempV4.Workout` gains `var _waypoints: [TempV4.Waypoint]` field, defaulting to `[]` for backward compatibility with existing `Codable` decoding (backup restore)
- `WalkInterface.waypoints` default implementation returns `[]` (not `throwOnAccess()`) — safe for pre-V6 walks and backup restore

### Data Flow

1. `WalkBuilder` gets `waypointsRelay: CurrentValueRelay<[TempWaypoint]>`, `waypointsPublisher`, `flushWaypoints()`, reset clears it
2. `ActiveWalkViewModel` gets `@Published var waypoints: [TempWaypoint]` and `addWaypoint(label:icon:)` which reads current location from `locationManagement` and appends to builder's relay
3. `NewWalk` accepts `waypoints:` parameter, passes to `super.init`
4. `WalkBuilder.createSnapshot()` passes `waypointsRelay.value` to `NewWalk`
5. `WalkBuilder.createCheckpointSnapshot()` also passes `waypointsRelay.value` to `NewWalk` (checkpoint resumes must not lose waypoints)
6. `DataManager.persistRelatedEntities` creates `PilgrimV6.Waypoint` rows
7. `DataManager.deleteAll` includes `try transaction.deleteAll(From<Waypoint>())`
8. `WalkInterface` gets `var waypoints: [WaypointInterface] { get }`

### Map Integration

- `PilgrimAnnotation.Kind` gets `.waypoint(label: String, icon: String)`
- `WalkSummaryView` gets `waypointPinAnnotations` computed property matching `voicePinAnnotations` pattern
- `PilgrimMapView` annotation rendering handles the new kind with the chip's SF Symbol

### AI Prompt Integration

Waypoints added as context section in `buildPrompt`:

```
**Waypoints marked during walk:**
[10:23 AM, near start] Peaceful
[10:41 AM, 1.2km in] "The old oak tree"
```

Added to `PromptGenerator.generate/generateCustom/generateAll` as `waypoints: [WaypointContext]` parameter (defaulting to `[]`). `PromptListView` constructs `WaypointContext` from `walk.waypoints`.

### UI Files

| File | Purpose |
|------|---------|
| `WaypointMarkingSheet.swift` (new) | Half-sheet with chips + custom text field |
| `WalkOptionsSheet.swift` (modify) | Add "Drop Waypoint" row with count subtitle |
| `ActiveWalkView.swift` (modify) | Wire waypoint sheet presentation |
| `ActiveWalkViewModel.swift` (modify) | `addWaypoint()`, `@Published waypoints` |

## Prompt Improvements

### Intention Prominence

**Current behavior:** Intention is added as a one-line context entry and a sentence appended to the instruction.

**New behavior:** Intention gets a dedicated framing section in `buildPrompt`, placed immediately after the Context line:

```
**The walker's intention:** "{intention}"
This intention was set deliberately before the walk began. It represents what the walker chose to carry with them. Let it be the lens through which you interpret everything below.
```

The instruction append changes from the generic "Let this purpose guide your response" to: "Ground your response in the walker's stated intention. Return to it. Help them see how their walk — its pace, its pauses, its moments — spoke to this purpose."

**Note:** Intention is stored in `walk.comment` (the DB field `_comment`). No new DB field is needed — all intention reads go through `walk.comment`.

### Prompts for All Walks

**Current behavior:** The "Generate AI Prompts" button in `WalkSummaryView` only appears when `!transcriptions.isEmpty`.

**New behavior:** The button always appears. The prompt content adapts based on available data:

- **With transcriptions:** Current behavior unchanged — voice recordings are the primary material.
- **Without transcriptions:** Preamble adapts to "This walk was taken in silence — no words were spoken, only movement." The instruction shifts from analyzing reflections to interpreting the walk's shape: its rhythm, pace changes, pauses, meditation sessions, waypoints, and intention. The walking transcription section is omitted; metadata, waypoints, meditation, and intention become the primary material.
- **Button subtitle adapts:** When transcriptions exist, shows count as before. When no transcriptions, shows context-appropriate text (e.g., "Reflect on your walk").

**Files to modify:**
- `WalkSummaryView.swift` — remove `!transcriptions.isEmpty` gate on `promptsButton`, adapt subtitle
- `PromptGenerator.swift` — adapt `buildPrompt` preamble and instruction when transcription is empty. Add silent-walk variants for each `PromptStyle`.

## Files Summary

### New Files

| File | Purpose |
|------|---------|
| `Pilgrim/Models/Data/DataModels/Versions/PilgrimV6.swift` | New schema version with Waypoint entity, migration chain |
| `Pilgrim/Models/Data/DataModels/Waypoint.swift` | CoreStore Waypoint type forwarding (like VoiceRecording.swift) |
| `Pilgrim/Models/Data/Temp/Versions/TempWaypoint.swift` | In-memory waypoint class |
| `Pilgrim/Protocols/DataInterfaces/WaypointInterface.swift` | Protocol for waypoint data |
| `Pilgrim/Scenes/ActiveWalk/WaypointMarkingSheet.swift` | Chip selection + custom text UI |

### Modified Files

| File | Changes |
|------|---------|
| `DataManager.swift` | Update default `dataModel` to `PilgrimV6.self`, persist/read/deleteAll for waypoints |
| `TempV4.swift` | Add `_waypoints` field to `TempV4.Workout`, default `[]` for Codable backward compat |
| `Temp.swift` | Add `TempWaypoint` type alias, update `TempWalk(from:)` copy init |
| `Walk.swift` | Expose `waypoints` relationship from CoreStore entity |
| `WalkInterface.swift` | Add `waypoints` property with `{ [] }` default |
| `WalkBuilder.swift` | Add waypoints relay, publisher, flush; pass to both `createSnapshot` and `createCheckpointSnapshot` |
| `NewWalk.swift` | Accept waypoints parameter |
| `PilgrimAnnotation.swift` | Add `.waypoint` kind |
| `ActiveWalkView.swift` | Wire waypoint sheet |
| `ActiveWalkViewModel.swift` | Add waypoint management |
| `WalkOptionsSheet.swift` | Add "Drop Waypoint" row with count subtitle |
| `WalkSummaryView.swift` | Waypoint map pins, always show prompts button with adaptive subtitle |
| `PromptGenerator.swift` | Waypoint context, intention prominence, silent-walk preambles |
| `PromptListView.swift` | Pass waypoints to PromptGenerator |

## Verification

1. **Build:** `xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build`
2. **Tests:** `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
3. **Migration test:** Install previous build, upgrade to new build, verify existing walks load correctly
4. **Manual flow:**
   - Drop 2-3 waypoints during walk → verify they appear on summary map → verify in AI prompts
   - Walk without recordings → verify prompts button appears → verify silent-walk prompt text
   - Set intention → verify prominent framing in generated prompt text
   - Walk with no intention, no recordings, no waypoints → verify prompts still generate from metadata alone
   - Checkpoint recovery: drop waypoints, force-kill app, relaunch → verify waypoints survive
