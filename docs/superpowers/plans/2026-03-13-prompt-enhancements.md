# Prompt Enhancements Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enrich prompt generation with reverse geocoding, pace context, walk threading, AI deep links, custom styles, and speaking pace metadata.

**Architecture:** Layer new context formatters onto existing PromptGenerator using the same nil-return optional section pattern. One schema migration (PilgrimV3) for wordsPerMinute. Custom styles in UserDefaults. UI changes to PromptDetailView for deep links and PromptListView for custom styles.

**Tech Stack:** SwiftUI, CoreStore, CoreLocation (CLGeocoder), WhisperKit, UserDefaults

**Spec:** `docs/superpowers/specs/2026-03-13-prompt-enhancements-design.md`

---

## Chunk 1: PilgrimV3 Schema + Speaking Pace Data Layer

### Task 1: PilgrimV3 Schema

**Files:**
- Create: `Pilgrim/Models/Data/DataModels/Versions/PilgrimV3.swift`
- Reference: `Pilgrim/Models/Data/DataModels/Versions/PilgrimV2.swift`

- [ ] **Step 1: Create PilgrimV3.swift**

Copy PilgrimV2.swift as the starting template. Change all internal references from `PilgrimV2` to `PilgrimV3`. Set `static let identifier = "PilgrimV3"`. Add one new field to the VoiceRecording entity:

```swift
let _wordsPerMinute = Value.Optional<Double>("wordsPerMinute")
```

Add this after `_transcription` (line 176 in PilgrimV2). Keep all other entities identical.

- [ ] **Step 2: Write migration provider**

In PilgrimV3's `migrationProvider`, migrate from PilgrimV2:
- `.transformEntity` for VoiceRecording (new attribute changes version hash)
- `.copyEntity` for all other entities (Workout, WorkoutPause, WorkoutEvent, RouteDataSample, HeartRateDataSample, Event, ActivityInterval)

Pattern — follow PilgrimV2.swift lines 20-44, replacing source `PilgrimV1` → `PilgrimV2`.

The transformEntity for VoiceRecording:
```swift
.transformEntity(
    sourceEntity: PilgrimV2.VoiceRecording.self,
    destinationEntity: PilgrimV3.VoiceRecording.self,
    transformer: { source, dest in
        dest[\.._uuid] = source[\.._uuid]
        dest[\.._startDate] = source[\.._startDate]
        dest[\.._endDate] = source[\.._endDate]
        dest[\.._duration] = source[\.._duration]
        dest[\.._fileRelativePath] = source[\.._fileRelativePath]
        dest[\.._transcription] = source[\.._transcription]
    }
)
```

- [ ] **Step 3: Verify project compiles**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Pilgrim/Models/Data/DataModels/Versions/PilgrimV3.swift
git commit -m "feat: add PilgrimV3 schema with wordsPerMinute on VoiceRecording"
```

---

### Task 2: VoiceRecording Type Alias + Interface + Temp Layer

**Files:**
- Modify: `Pilgrim/Models/Data/DataModels/VoiceRecording.swift:4` (type alias)
- Modify: `Pilgrim/Protocols/DataInterfaces/VoiceRecordingInterface.swift:3-11` (protocol)
- Modify: `Pilgrim/Models/Data/Temp/Versions/TempV4.swift:179-200` (TempV4.VoiceRecording)
- Modify: `Pilgrim/Models/Data/Temp/Temp.swift:155-168` (TempVoiceRecording)

- [ ] **Step 1: Update type alias**

In `VoiceRecording.swift` line 4, change:
```swift
typealias VoiceRecording = PilgrimV2.VoiceRecording
```
to:
```swift
typealias VoiceRecording = PilgrimV3.VoiceRecording
```

Add `wordsPerMinute` to the VoiceRecordingInterface conformance extension (after `transcription`):
```swift
var wordsPerMinute: Double? { threadSafeSyncReturn { self._wordsPerMinute.value } }
```

- [ ] **Step 2: Update VoiceRecordingInterface protocol**

In `VoiceRecordingInterface.swift`, add to the protocol (after `transcription`):
```swift
var wordsPerMinute: Double? { get }
```

Add default implementation in the extension:
```swift
var wordsPerMinute: Double? { throwOnAccess() }
```

- [ ] **Step 3: Update TempV4.VoiceRecording**

In `TempV4.swift` VoiceRecording class (line 179), add property:
```swift
var wordsPerMinute: Double?
```

Update the initializer to accept the new parameter (default nil):
```swift
init(uuid: UUID?, startDate: Date, endDate: Date, duration: Double,
     fileRelativePath: String, transcription: String? = nil, wordsPerMinute: Double? = nil) {
    // ... existing assignments ...
    self.wordsPerMinute = wordsPerMinute
}
```

- [ ] **Step 4: Update Temp.swift TempVoiceRecording**

In `Temp.swift` line 155-168, update the VoiceRecordingInterface conformance extension's convenience init to pass `wordsPerMinute`:
```swift
convenience init(from interface: VoiceRecordingInterface) {
    self.init(
        uuid: interface.uuid,
        startDate: interface.startDate,
        endDate: interface.endDate,
        duration: interface.duration,
        fileRelativePath: interface.fileRelativePath,
        transcription: interface.transcription,
        wordsPerMinute: interface.wordsPerMinute
    )
}
```

- [ ] **Step 5: Update VoiceRecording.asTemp conversion**

In `VoiceRecording.swift` lines 18-31 (TempValueConvertible extension), update the TempVoiceRecording init call to include `wordsPerMinute`:
```swift
TempVoiceRecording(
    uuid: uuid,
    startDate: startDate,
    endDate: endDate,
    duration: duration,
    fileRelativePath: fileRelativePath,
    transcription: transcription,
    wordsPerMinute: wordsPerMinute
)
```

- [ ] **Step 6: Verify project compiles**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add Pilgrim/Models/Data/DataModels/VoiceRecording.swift \
        Pilgrim/Protocols/DataInterfaces/VoiceRecordingInterface.swift \
        Pilgrim/Models/Data/Temp/Versions/TempV4.swift \
        Pilgrim/Models/Data/Temp/Temp.swift
git commit -m "feat: add wordsPerMinute to VoiceRecording type alias, interface, and temp layer"
```

---

### Task 3: DataManager Updates

**Files:**
- Modify: `Pilgrim/Models/Data/DataManager.swift:55` (setup default parameter)
- Modify: `Pilgrim/Models/Data/DataManager.swift:255-265` (saveWalks voiceRecordings section)
- Modify: `Pilgrim/Models/Data/DataManager.swift:464-476` (add updateWordsPerMinute near updateTranscription)

- [ ] **Step 1: Update setup default parameter**

Line 55, change default `dataModel` from `PilgrimV2.self` to `PilgrimV3.self`.

- [ ] **Step 2: Update saveWalks voiceRecordings persistence**

In the saveWalks method (lines 255-265), after the existing field assignments for each voice recording, add:
```swift
recording._wordsPerMinute.value = tempRecording.wordsPerMinute
```

- [ ] **Step 3: Add updateVoiceRecordingWordsPerMinute method**

Add near `updateVoiceRecordingTranscription` (line 464), following the same pattern:

```swift
static func updateVoiceRecordingWordsPerMinute(uuid: UUID, wordsPerMinute: Double) {
    dataStack.perform(asynchronous: { transaction in
        guard let recording = try transaction.fetchOne(
            From<VoiceRecording>().where(\._uuid == uuid)
        ) else { return }
        recording._wordsPerMinute.value = wordsPerMinute
    }, completion: { result in
        if case .failure(let error) = result {
            print("[DataManager] Failed to update WPM for \(uuid): \(error)")
        }
    })
}
```

- [ ] **Step 4: Verify project compiles**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Data/DataManager.swift
git commit -m "feat: update DataManager for PilgrimV3 migration and WPM persistence"
```

---

### Task 4: TranscriptionService WPM Computation

**Files:**
- Modify: `Pilgrim/Models/TranscriptionService.swift:130-137` (transcribeRecordings inner loop)
- Modify: `Pilgrim/Models/TranscriptionService.swift:178-186` (transcribeSingle)

- [ ] **Step 1: Add WPM computation helper**

Add a private method to TranscriptionService:

```swift
private func computeWordsPerMinute(from results: [TranscriptionResult]) -> Double? {
    let segments = results.flatMap { $0.segments }
    guard let first = segments.first, let last = segments.last,
          last.end > first.start else { return nil }
    let words = segments.flatMap { $0.words }
    let wordCount: Int
    if !words.isEmpty {
        wordCount = words.count
    } else {
        wordCount = segments.flatMap { $0.text.split(separator: " ") }.count
    }
    guard wordCount > 0 else { return nil }
    let durationMinutes = (last.end - first.start) / 60.0
    guard durationMinutes > 0 else { return nil }
    return Double(wordCount) / durationMinutes
}
```

- [ ] **Step 2: Integrate into transcribeRecordings**

In the `transcribeRecordings` method (line 130-137), after extracting text and before `DataManager.updateVoiceRecordingTranscription`, add WPM computation:

```swift
let transcriptionResults = try await pipe.transcribe(audioPath: audioURL.path)
let text = transcriptionResults.map(\.text).joined(separator: " ")
    .trimmingCharacters(in: .whitespacesAndNewlines)
if !text.isEmpty {
    results[uuid] = text
    DataManager.updateVoiceRecordingTranscription(uuid: uuid, transcription: text)
    if let wpm = computeWordsPerMinute(from: transcriptionResults) {
        DataManager.updateVoiceRecordingWordsPerMinute(uuid: uuid, wordsPerMinute: wpm)
    }
}
```

- [ ] **Step 3: Integrate into transcribeSingle**

Same pattern in `transcribeSingle` (line 178-186):

```swift
let results = try await pipe.transcribe(audioPath: audioURL.path)
let text = results.map(\.text).joined(separator: " ")
    .trimmingCharacters(in: .whitespacesAndNewlines)
await MainActor.run { state = .completed; isTranscribing = false }
if !text.isEmpty {
    DataManager.updateVoiceRecordingTranscription(uuid: uuid, transcription: text)
    if let wpm = computeWordsPerMinute(from: results) {
        DataManager.updateVoiceRecordingWordsPerMinute(uuid: uuid, wordsPerMinute: wpm)
    }
    return text
}
```

- [ ] **Step 4: Verify project compiles**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/TranscriptionService.swift
git commit -m "feat: compute and store words-per-minute during transcription"
```

---

## Chunk 2: PromptGenerator Enhancements

### Task 5: GeneratedPrompt Model Update

**Files:**
- Modify: `Pilgrim/Models/PromptGenerator.swift:47-51` (GeneratedPrompt struct)

- [ ] **Step 1: Write failing test for custom style support**

In `UnitTests/PromptGeneratorTests.swift`, add:

```swift
func testGeneratedPrompt_builtInStyle_titleFromStyle() {
    let prompt = GeneratedPrompt(style: .reflective, customStyle: nil, text: "test")
    XCTAssertEqual(prompt.title, "Reflective")
    XCTAssertEqual(prompt.icon, "eye.fill")
    XCTAssertEqual(prompt.subtitle, "Identify patterns and emotional undercurrents")
}

func testGeneratedPrompt_customStyle_titleFromCustom() {
    let custom = CustomPromptStyle(id: UUID(), title: "My Style", icon: "star.fill", instruction: "Do something creative")
    let prompt = GeneratedPrompt(style: nil, customStyle: custom, text: "test")
    XCTAssertEqual(prompt.title, "My Style")
    XCTAssertEqual(prompt.icon, "star.fill")
    XCTAssertEqual(prompt.subtitle, "Do something creative")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E '(Test Case|BUILD|error:)'`
Expected: FAIL — GeneratedPrompt doesn't have these initializer parameters yet

- [ ] **Step 3: Update GeneratedPrompt struct**

Replace the struct at lines 47-51:

```swift
struct GeneratedPrompt: Identifiable {
    let id = UUID()
    let style: PromptStyle?
    let customStyle: CustomPromptStyle?
    let text: String

    var title: String { customStyle?.title ?? style!.title }
    var icon: String { customStyle?.icon ?? style!.icon }
    var subtitle: String { customStyle?.instruction ?? style!.description }
}
```

- [ ] **Step 4: Create CustomPromptStyle struct**

Create `Pilgrim/Models/CustomPromptStyleStore.swift` with just the struct for now (store comes in Task 11):

```swift
import Foundation

struct CustomPromptStyle: Codable, Identifiable {
    let id: UUID
    var title: String
    var icon: String
    var instruction: String
}
```

- [ ] **Step 5: Fix existing code that uses GeneratedPrompt**

Update `PromptGenerator.generate()` return at line 80:
```swift
return GeneratedPrompt(style: style, customStyle: nil, text: prompt)
```

Update `PromptDetailView.swift` lines 16 and 19:
```swift
Image(systemName: prompt.icon)
// ...
Text(prompt.title)
```

Update `PromptStyleRow` lines 78, 84, 87:
```swift
Image(systemName: prompt.icon)
// ...
Text(prompt.title)
// ...
Text(prompt.subtitle)
```

Fix existing test `testGenerateAll_returnsOnePerStyle` — the `Set(prompts.map { $0.style })` line needs updating since `style` is now optional:
```swift
let styles = Set(prompts.compactMap { $0.style })
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E '(Test Case|BUILD|Executed)'`
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
git add Pilgrim/Models/PromptGenerator.swift \
        Pilgrim/Models/CustomPromptStyleStore.swift \
        Pilgrim/Scenes/Prompts/PromptDetailView.swift \
        Pilgrim/Scenes/Prompts/PromptListView.swift \
        UnitTests/PromptGeneratorTests.swift
git commit -m "feat: update GeneratedPrompt to support custom styles"
```

---

### Task 6: RecordingContext WPM + WPM Formatting

**Files:**
- Modify: `Pilgrim/Models/PromptGenerator.swift:55-60` (RecordingContext)
- Modify: `Pilgrim/Models/PromptGenerator.swift:115-127` (formatRecordings)
- Test: `UnitTests/PromptGeneratorTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
func testGenerate_recordingWithWPM_containsPaceLabel() {
    let recording = PromptGenerator.RecordingContext(
        text: "Quick excited thoughts",
        timestamp: DateFactory.makeDate(2024, 6, 15, 9, 5, 0),
        startCoordinate: nil,
        endCoordinate: nil,
        wordsPerMinute: 85
    )
    let prompt = PromptGenerator.generate(
        style: .reflective,
        recordings: [recording],
        meditations: [],
        duration: 1800,
        distance: 2000,
        startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
    )
    XCTAssertTrue(prompt.text.contains("~85 wpm"))
    XCTAssertTrue(prompt.text.contains("slow/thoughtful"))
}

func testGenerate_recordingWithoutWPM_omitsPaceLabel() {
    let recording = PromptGenerator.RecordingContext(
        text: "Just walking",
        timestamp: DateFactory.makeDate(2024, 6, 15, 9, 5, 0),
        startCoordinate: nil,
        endCoordinate: nil,
        wordsPerMinute: nil
    )
    let prompt = PromptGenerator.generate(
        style: .reflective,
        recordings: [recording],
        meditations: [],
        duration: 1800,
        distance: 2000,
        startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
    )
    XCTAssertFalse(prompt.text.contains("wpm"))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — RecordingContext doesn't have `wordsPerMinute` parameter yet

- [ ] **Step 3: Add wordsPerMinute to RecordingContext**

At line 55-60, add the field:
```swift
struct RecordingContext {
    let text: String
    let timestamp: Date
    let startCoordinate: (lat: Double, lon: Double)?
    let endCoordinate: (lat: Double, lon: Double)?
    let wordsPerMinute: Double?
}
```

- [ ] **Step 4: Fix existing call sites**

Update `PromptListView.generatePrompts()` RecordingContext creation (line 39-44) to include `wordsPerMinute`:
```swift
return PromptGenerator.RecordingContext(
    text: text,
    timestamp: recording.startDate,
    startCoordinate: startCoord,
    endCoordinate: endCoord,
    wordsPerMinute: recording.wordsPerMinute
)
```

Update all existing test RecordingContext creations in `PromptGeneratorTests.swift` to add `wordsPerMinute: nil`.

- [ ] **Step 5: Add WPM label helper and update formatRecordings**

Add to PromptGenerator:
```swift
private static func speakingPaceLabel(_ wpm: Double) -> String {
    switch wpm {
    case ..<100: return "slow/thoughtful"
    case 100..<140: return "measured"
    case 140..<170: return "conversational"
    default: return "rapid/energized"
    }
}
```

In `formatRecordings` (line 115-127), after the GPS header, add WPM:
```swift
if let wpm = item.wordsPerMinute {
    header += " [~\(Int(wpm)) wpm, \(speakingPaceLabel(wpm))]"
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E '(Test Case|BUILD|Executed)'`
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
git add Pilgrim/Models/PromptGenerator.swift \
        Pilgrim/Scenes/Prompts/PromptListView.swift \
        UnitTests/PromptGeneratorTests.swift
git commit -m "feat: add speaking pace labels to prompt recording headers"
```

---

### Task 7: Reverse Geocoding Formatter

**Files:**
- Modify: `Pilgrim/Models/PromptGenerator.swift` (add PlaceContext, PlaceRole, formatPlaceNames)
- Test: `UnitTests/PromptGeneratorTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
func testFormatPlaceNames_startOnly_containsNear() {
    let prompt = PromptGenerator.generate(
        style: .reflective,
        recordings: [],
        meditations: [],
        duration: 1800,
        distance: 2000,
        startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
        placeNames: [
            PromptGenerator.PlaceContext(name: "Riverside Park, Manhattan", coordinate: (lat: 40.8, lon: -73.97), role: .start)
        ]
    )
    XCTAssertTrue(prompt.text.contains("Near Riverside Park, Manhattan"))
}

func testFormatPlaceNames_startAndEnd_containsArrow() {
    let prompt = PromptGenerator.generate(
        style: .reflective,
        recordings: [],
        meditations: [],
        duration: 1800,
        distance: 2000,
        startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
        placeNames: [
            PromptGenerator.PlaceContext(name: "Riverside Park", coordinate: (lat: 40.8, lon: -73.97), role: .start),
            PromptGenerator.PlaceContext(name: "Central Park", coordinate: (lat: 40.78, lon: -73.96), role: .end)
        ]
    )
    XCTAssertTrue(prompt.text.contains("Started near Riverside Park"))
    XCTAssertTrue(prompt.text.contains("Central Park"))
}

func testFormatPlaceNames_empty_omitsLocationSection() {
    let prompt = PromptGenerator.generate(
        style: .reflective,
        recordings: [],
        meditations: [],
        duration: 1800,
        distance: 2000,
        startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
        placeNames: []
    )
    XCTAssertFalse(prompt.text.contains("Location"))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — `placeNames` parameter doesn't exist yet

- [ ] **Step 3: Add types and formatter**

Add to PromptGenerator:

```swift
enum PlaceRole { case start, end, midpoint }

struct PlaceContext {
    let name: String
    let coordinate: (lat: Double, lon: Double)
    let role: PlaceRole
}
```

Add formatter:
```swift
private static func formatPlaceNames(_ places: [PlaceContext]) -> String? {
    guard !places.isEmpty else { return nil }
    let start = places.first { $0.role == .start }
    let end = places.first { $0.role == .end }
    if let start = start, let end = end {
        return "**Location:** Started near \(start.name) → ended near \(end.name)"
    } else if let start = start {
        return "**Location:** Near \(start.name)"
    }
    return nil
}
```

- [ ] **Step 4: Update generate() signature**

Add `placeNames: [PlaceContext] = []` parameter. Pass it through to `buildPrompt`. Update `buildPrompt` to accept and insert location section after metadata.

- [ ] **Step 5: Update buildPrompt to include location**

Add `location: String?` parameter to `buildPrompt`. Insert after the metadata Context line:
```swift
if let location = location {
    sections += "\n\n\(location)"
}
```

- [ ] **Step 6: Run tests to verify they pass**

Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
git add Pilgrim/Models/PromptGenerator.swift UnitTests/PromptGeneratorTests.swift
git commit -m "feat: add reverse geocoding place names to prompts"
```

---

### Task 8: Pace Context Formatter

**Files:**
- Modify: `Pilgrim/Models/PromptGenerator.swift` (add formatPaceContext)
- Test: `UnitTests/PromptGeneratorTests.swift`
- Reference: `Pilgrim/Protocols/DataInterfaces/RouteDataSampleInterface.swift`

- [ ] **Step 1: Write failing tests**

```swift
func testFormatPaceContext_withSpeedData_containsAveragePace() {
    let prompt = PromptGenerator.generate(
        style: .reflective,
        recordings: [],
        meditations: [],
        duration: 1800,
        distance: 2000,
        startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
        routeSpeeds: [1.5, 1.6, 1.4, 1.5, 1.3, 1.7, 1.5, 1.4, 1.6, 1.5, 1.5]
    )
    XCTAssertTrue(prompt.text.contains("Pace"))
    XCTAssertTrue(prompt.text.contains("min/"))
}

func testFormatPaceContext_sparseData_omitsPaceSection() {
    let prompt = PromptGenerator.generate(
        style: .reflective,
        recordings: [],
        meditations: [],
        duration: 1800,
        distance: 2000,
        startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
        routeSpeeds: [1.5, 1.6]
    )
    XCTAssertFalse(prompt.text.contains("Pace"))
}

func testFormatPaceContext_empty_omitsPaceSection() {
    let prompt = PromptGenerator.generate(
        style: .reflective,
        recordings: [],
        meditations: [],
        duration: 1800,
        distance: 2000,
        startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
        routeSpeeds: []
    )
    XCTAssertFalse(prompt.text.contains("Pace"))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — `routeSpeeds` parameter doesn't exist

- [ ] **Step 3: Add pace formatter**

For testability, accept two parameters: `routeSpeeds: [Double]` (m/s values for overall pace) and `routeSpeedTimestamps: [(Date, Double)]` (timestamp + speed pairs for per-recording analysis). The call site in PromptListView extracts these from route samples.

Add `routeSpeeds: [Double] = []` and `routeSpeedTimestamps: [(Date, Double)] = []` parameters to `generate()`.

```swift
private static func formatPaceContext(speeds: [Double], speedTimestamps: [(Date, Double)], recordings: [RecordingContext]) -> String? {
    let moving = speeds.filter { $0 >= 0.3 }
    guard moving.count >= 10 else { return nil }
    let avgSpeed = moving.reduce(0, +) / Double(moving.count)
    let minSpeed = moving.min()!
    let maxSpeed = moving.max()!
    let avgPace = formatPace(metersPerSecond: avgSpeed)
    let slowPace = formatPace(metersPerSecond: minSpeed)
    let fastPace = formatPace(metersPerSecond: maxSpeed)
    var result = "**Pace:** Average \(avgPace) (range: \(fastPace)–\(slowPace))"

    for recording in recordings {
        let windowBefore = speedTimestamps.filter {
            $0.0 >= recording.timestamp.addingTimeInterval(-30) &&
            $0.0 <= recording.timestamp && $0.1 >= 0.3
        }
        let windowAfter = speedTimestamps.filter {
            $0.0 >= recording.timestamp &&
            $0.0 <= recording.timestamp.addingTimeInterval(30) && $0.1 >= 0.3
        }
        guard !windowBefore.isEmpty || !windowAfter.isEmpty else { continue }
        let beforeAvg = windowBefore.isEmpty ? nil : windowBefore.map(\.1).reduce(0, +) / Double(windowBefore.count)
        let afterAvg = windowAfter.isEmpty ? nil : windowAfter.map(\.1).reduce(0, +) / Double(windowAfter.count)
        let timeStr = timeFormatter.string(from: recording.timestamp)
        if let before = beforeAvg, let after = afterAvg {
            let beforePace = formatPace(metersPerSecond: before)
            let afterPace = formatPace(metersPerSecond: after)
            if abs(before - after) / before > 0.15 {
                result += "\n[\(timeStr)] pace changed from \(beforePace) to \(afterPace)"
            } else {
                result += "\n[\(timeStr)] steady at \(formatPace(metersPerSecond: (before + after) / 2))"
            }
        } else if let speed = beforeAvg ?? afterAvg {
            result += "\n[\(timeStr)] at \(formatPace(metersPerSecond: speed))"
        }
    }
    return result
}

private static func formatPace(metersPerSecond: Double) -> String {
    guard metersPerSecond > 0 else { return "—" }
    let usesMiles = Locale.current.measurementSystem == .us
    let metersPerUnit: Double = usesMiles ? 1609.34 : 1000.0
    let label = usesMiles ? "min/mi" : "min/km"
    let secondsPerUnit = metersPerUnit / metersPerSecond
    let minutes = Int(secondsPerUnit) / 60
    let seconds = Int(secondsPerUnit) % 60
    return String(format: "%d:%02d %@", minutes, seconds, label)
}
```

Pass through to `buildPrompt` and insert after location section.

- [ ] **Step 4: Run tests to verify they pass**

Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/PromptGenerator.swift UnitTests/PromptGeneratorTests.swift
git commit -m "feat: add pace context to prompts"
```

---

### Task 9: Walk-to-Walk Threading Formatter

**Files:**
- Modify: `Pilgrim/Models/PromptGenerator.swift` (add WalkSnippet, formatRecentWalks)
- Test: `UnitTests/PromptGeneratorTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
func testFormatRecentWalks_withSnippets_containsContinuitySection() {
    let snippets = [
        PromptGenerator.WalkSnippet(
            date: DateFactory.makeDate(2024, 6, 12, 9, 0, 0),
            placeName: nil,
            transcriptionPreview: "I keep thinking about how the river reminds me of home"
        ),
        PromptGenerator.WalkSnippet(
            date: DateFactory.makeDate(2024, 6, 10, 9, 0, 0),
            placeName: nil,
            transcriptionPreview: "Today I noticed I was walking faster than usual"
        )
    ]
    let prompt = PromptGenerator.generate(
        style: .reflective,
        recordings: [],
        meditations: [],
        duration: 1800,
        distance: 2000,
        startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
        recentWalkSnippets: snippets
    )
    XCTAssertTrue(prompt.text.contains("Recent Walk Context"))
    XCTAssertTrue(prompt.text.contains("river reminds me of home"))
}

func testFormatRecentWalks_empty_omitsSection() {
    let prompt = PromptGenerator.generate(
        style: .reflective,
        recordings: [],
        meditations: [],
        duration: 1800,
        distance: 2000,
        startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
        recentWalkSnippets: []
    )
    XCTAssertFalse(prompt.text.contains("Recent Walk Context"))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — `recentWalkSnippets` parameter doesn't exist

- [ ] **Step 3: Add WalkSnippet and formatter**

```swift
struct WalkSnippet {
    let date: Date
    let placeName: String?
    let transcriptionPreview: String
}

private static let shortDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d"
    return f
}()

private static func formatRecentWalks(_ snippets: [WalkSnippet]) -> String? {
    guard !snippets.isEmpty else { return nil }
    let lines = snippets.map { snippet in
        let dateStr = shortDateFormatter.string(from: snippet.date)
        if let place = snippet.placeName {
            return "[\(dateStr) – \(place)] \"\(snippet.transcriptionPreview)\""
        }
        return "[\(dateStr)] \"\(snippet.transcriptionPreview)\""
    }
    return "**Recent Walk Context (for continuity):**\n\n" + lines.joined(separator: "\n\n")
}
```

Add `recentWalkSnippets: [WalkSnippet] = []` to `generate()`. Pass through to `buildPrompt` and insert after meditation sessions, before the `---` divider.

- [ ] **Step 4: Run tests to verify they pass**

Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/PromptGenerator.swift UnitTests/PromptGeneratorTests.swift
git commit -m "feat: add walk-to-walk threading context to prompts"
```

---

### Task 10: Custom Prompt Generation + generateAll Update

**Files:**
- Modify: `Pilgrim/Models/PromptGenerator.swift` (add generateCustom, update generateAll)
- Test: `UnitTests/PromptGeneratorTests.swift`

- [ ] **Step 1: Write failing test**

```swift
func testGenerateCustom_usesCustomInstruction() {
    let custom = CustomPromptStyle(id: UUID(), title: "Letter", icon: "envelope.fill", instruction: "Write this as a letter to my future self")
    let prompt = PromptGenerator.generateCustom(
        customStyle: custom,
        recordings: [],
        meditations: [],
        duration: 1800,
        distance: 2000,
        startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
    )
    XCTAssertTrue(prompt.text.contains("letter to my future self"))
    XCTAssertNil(prompt.style)
    XCTAssertEqual(prompt.customStyle?.title, "Letter")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — `generateCustom` doesn't exist

- [ ] **Step 3: Add generateCustom method**

```swift
static func generateCustom(
    customStyle: CustomPromptStyle,
    recordings: [RecordingContext],
    meditations: [MeditationContext],
    duration: Double,
    distance: Double,
    startDate: Date,
    placeNames: [PlaceContext] = [],
    routeSpeeds: [Double] = [],
    recentWalkSnippets: [WalkSnippet] = []
) -> GeneratedPrompt {
    let combinedText = formatRecordings(recordings)
    let meditationText = formatMeditations(meditations)
    let metadata = formatMetadata(duration: duration, distance: distance, startDate: startDate)
    let location = formatPlaceNames(placeNames)
    let pace = formatPaceContext(speeds: routeSpeeds)
    let recentWalks = formatRecentWalks(recentWalkSnippets)

    let preamble = "These are voice recordings captured during a walk, transcribed as spoken. They represent unfiltered thoughts, observations, and feelings that surfaced while moving."

    let prompt = buildPrompt(
        preamble: preamble,
        instruction: customStyle.instruction,
        transcription: combinedText,
        meditations: meditationText,
        metadata: metadata,
        location: location,
        pace: pace,
        recentWalks: recentWalks
    )
    return GeneratedPrompt(style: nil, customStyle: customStyle, text: prompt)
}
```

This requires refactoring `buildPrompt` to accept `preamble` and `instruction` as strings instead of deriving them from `PromptStyle`. Extract the style switch into the caller (`generate`), and have `buildPrompt` be purely about assembling sections.

- [ ] **Step 4: Refactor buildPrompt signature**

Change `buildPrompt` from:
```swift
private static func buildPrompt(style: PromptStyle, transcription: String, meditations: String?, metadata: String) -> String
```
to:
```swift
private static func buildPrompt(preamble: String, instruction: String, transcription: String, meditations: String?, metadata: String, location: String?, pace: String?, recentWalks: String?) -> String
```

Move the style switch (preamble/instruction lookup) into `generate()`, then call `buildPrompt` with extracted strings.

- [ ] **Step 5: Update generateAll to forward new parameters**

Update `generateAll` to accept and forward all new parameters:
```swift
static func generateAll(
    recordings: [RecordingContext],
    meditations: [MeditationContext],
    duration: Double,
    distance: Double,
    startDate: Date,
    placeNames: [PlaceContext] = [],
    routeSpeeds: [Double] = [],
    recentWalkSnippets: [WalkSnippet] = []
) -> [GeneratedPrompt] {
    PromptStyle.allCases.map { style in
        generate(
            style: style,
            recordings: recordings,
            meditations: meditations,
            duration: duration,
            distance: distance,
            startDate: startDate,
            placeNames: placeNames,
            routeSpeeds: routeSpeeds,
            recentWalkSnippets: recentWalkSnippets
        )
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
git add Pilgrim/Models/PromptGenerator.swift UnitTests/PromptGeneratorTests.swift
git commit -m "feat: add custom prompt generation and refactor buildPrompt"
```

---

## Chunk 3: Custom Prompt Styles UI

### Task 11: CustomPromptStyleStore

**Files:**
- Modify: `Pilgrim/Models/CustomPromptStyleStore.swift` (add store class)
- Test: `UnitTests/CustomPromptStyleStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Create `UnitTests/CustomPromptStyleStoreTests.swift`:

```swift
import XCTest
@testable import Pilgrim

final class CustomPromptStyleStoreTests: XCTestCase {

    private var store: CustomPromptStyleStore!
    private let testKey = "TestCustomPromptStyles"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: testKey)
        store = CustomPromptStyleStore(userDefaultsKey: testKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: testKey)
        super.tearDown()
    }

    func testInitialState_empty() {
        XCTAssertTrue(store.styles.isEmpty)
        XCTAssertTrue(store.canAddMore)
    }

    func testSave_addsStyle() {
        let style = CustomPromptStyle(id: UUID(), title: "Test", icon: "star", instruction: "Do a thing")
        store.save(style)
        XCTAssertEqual(store.styles.count, 1)
        XCTAssertEqual(store.styles.first?.title, "Test")
    }

    func testSave_persistsToUserDefaults() {
        let style = CustomPromptStyle(id: UUID(), title: "Persisted", icon: "star", instruction: "Persist")
        store.save(style)
        let reloaded = CustomPromptStyleStore(userDefaultsKey: testKey)
        XCTAssertEqual(reloaded.styles.count, 1)
        XCTAssertEqual(reloaded.styles.first?.title, "Persisted")
    }

    func testCanAddMore_falseAtMax() {
        for i in 0..<CustomPromptStyleStore.maxStyles {
            store.save(CustomPromptStyle(id: UUID(), title: "Style \(i)", icon: "star", instruction: "Inst"))
        }
        XCTAssertFalse(store.canAddMore)
    }

    func testDelete_removesStyle() {
        let style = CustomPromptStyle(id: UUID(), title: "Delete Me", icon: "star", instruction: "Inst")
        store.save(style)
        store.delete(style)
        XCTAssertTrue(store.styles.isEmpty)
    }

    func testSave_existingId_updatesInPlace() {
        let id = UUID()
        store.save(CustomPromptStyle(id: id, title: "Original", icon: "star", instruction: "V1"))
        store.save(CustomPromptStyle(id: id, title: "Updated", icon: "star", instruction: "V2"))
        XCTAssertEqual(store.styles.count, 1)
        XCTAssertEqual(store.styles.first?.title, "Updated")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — CustomPromptStyleStore class doesn't exist

- [ ] **Step 3: Implement CustomPromptStyleStore**

In `Pilgrim/Models/CustomPromptStyleStore.swift`, add below the existing struct:

```swift
final class CustomPromptStyleStore: ObservableObject {
    static let maxStyles = 3

    @Published private(set) var styles: [CustomPromptStyle]

    private let userDefaultsKey: String

    init(userDefaultsKey: String = "CustomPromptStyles") {
        self.userDefaultsKey = userDefaultsKey
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([CustomPromptStyle].self, from: data) {
            styles = decoded
        } else {
            styles = []
        }
    }

    var canAddMore: Bool { styles.count < Self.maxStyles }

    func save(_ style: CustomPromptStyle) {
        if let index = styles.firstIndex(where: { $0.id == style.id }) {
            styles[index] = style
        } else {
            guard canAddMore else { return }
            styles.append(style)
        }
        persist()
    }

    func delete(_ style: CustomPromptStyle) {
        styles.removeAll { $0.id == style.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(styles) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/CustomPromptStyleStore.swift UnitTests/CustomPromptStyleStoreTests.swift
git commit -m "feat: add CustomPromptStyleStore with UserDefaults persistence"
```

---

### Task 12: CustomPromptEditorView

**Files:**
- Create: `Pilgrim/Scenes/Prompts/CustomPromptEditorView.swift`

- [ ] **Step 1: Create the editor view**

```swift
import SwiftUI

struct CustomPromptEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: CustomPromptStyleStore

    var editingStyle: CustomPromptStyle?

    @State private var title: String = ""
    @State private var selectedIcon: String = "pencil.line"
    @State private var instruction: String = ""

    private let iconOptions = [
        "pencil.line", "text.quote", "envelope.fill", "lightbulb.fill",
        "flame.fill", "leaf.fill", "wind", "drop.fill",
        "sun.max.fill", "moon.fill", "star.fill", "sparkles",
        "figure.walk", "mountain.2.fill", "water.waves", "bird.fill",
        "hands.clap.fill", "brain.head.profile", "book.fill", "music.note"
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Constants.UI.Padding.big) {
                    titleSection
                    iconSection
                    instructionSection
                }
                .padding(Constants.UI.Padding.normal)
            }
            .background(Color.parchment)
            .navigationTitle(editingStyle == nil ? "New Prompt Style" : "Edit Prompt Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.stone)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveAndDismiss() }
                        .foregroundColor(.stone)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty ||
                                  instruction.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            if let editing = editingStyle {
                title = editing.title
                selectedIcon = editing.icon
                instruction = editing.instruction
            }
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            Text("Title")
                .font(Constants.Typography.heading)
                .foregroundColor(.ink)
            TextField("e.g., Letter to Future Self", text: $title)
                .font(Constants.Typography.body)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            Text("Icon")
                .font(Constants.Typography.heading)
                .foregroundColor(.ink)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                ForEach(iconOptions, id: \.self) { icon in
                    Button {
                        selectedIcon = icon
                    } label: {
                        Image(systemName: icon)
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .foregroundColor(selectedIcon == icon ? .parchment : .stone)
                            .background(selectedIcon == icon ? Color.stone : Color.parchmentSecondary)
                            .cornerRadius(Constants.UI.CornerRadius.small)
                    }
                }
            }
        }
    }

    private var instructionSection: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            Text("Instruction")
                .font(Constants.Typography.heading)
                .foregroundColor(.ink)
            TextEditor(text: $instruction)
                .font(Constants.Typography.body)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(Constants.UI.Padding.small)
                .background(Color.parchmentSecondary)
                .cornerRadius(Constants.UI.CornerRadius.small)
                .overlay(
                    Group {
                        if instruction.isEmpty {
                            Text("Tell the AI what to do with your walking thoughts...")
                                .font(Constants.Typography.body)
                                .foregroundColor(.fog)
                                .padding(Constants.UI.Padding.small + 4)
                        }
                    },
                    alignment: .topLeading
                )

            Text("\(store.styles.count + (editingStyle == nil ? 1 : 0)) of \(CustomPromptStyleStore.maxStyles)")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func saveAndDismiss() {
        let style = CustomPromptStyle(
            id: editingStyle?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespaces),
            icon: selectedIcon,
            instruction: instruction.trimmingCharacters(in: .whitespaces)
        )
        store.save(style)
        dismiss()
    }
}
```

- [ ] **Step 2: Verify project compiles**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Pilgrim/Scenes/Prompts/CustomPromptEditorView.swift
git commit -m "feat: add CustomPromptEditorView with icon picker and instruction editor"
```

---

### Task 13: PromptListView — Custom Styles + Async Geocoding + Threading

**Files:**
- Modify: `Pilgrim/Scenes/Prompts/PromptListView.swift`
- Modify: `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift:55-59` (pass recentWalkSnippets)

- [ ] **Step 1: Update PromptListView to accept recentWalkSnippets and add custom style support**

Add new properties:
```swift
let recentWalkSnippets: [PromptGenerator.WalkSnippet]
@StateObject private var customStyleStore = CustomPromptStyleStore()
@State private var showEditor = false
@State private var editingStyle: CustomPromptStyle?
@State private var geocodedPlaces: [PromptGenerator.PlaceContext] = []
```

- [ ] **Step 2: Update List body to show custom styles + create row**

Replace the List body:
```swift
List {
    Section {
        ForEach(prompts) { prompt in
            Button { selectedPrompt = prompt } label: {
                PromptStyleRow(prompt: prompt)
            }
            .listRowBackground(Color.parchment)
        }
    }

    if !customStyleStore.styles.isEmpty {
        Section {
            ForEach(customPrompts) { prompt in
                Button { selectedPrompt = prompt } label: {
                    PromptStyleRow(prompt: prompt)
                }
                .listRowBackground(Color.parchment)
            }
            .onDelete { offsets in
                for index in offsets {
                    customStyleStore.delete(customStyleStore.styles[index])
                }
                regenerateCustomPrompts()
            }
        }
    }

    Section {
        createYourOwnRow
            .listRowBackground(Color.parchment)
    }
}
```

- [ ] **Step 3: Add createYourOwnRow and custom prompts state**

```swift
@State private var customPrompts: [GeneratedPrompt] = []

private var createYourOwnRow: some View {
    Button {
        guard customStyleStore.canAddMore else { return }
        editingStyle = nil
        showEditor = true
    } label: {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundColor(customStyleStore.canAddMore ? .stone : .fog)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text("Create Your Own")
                    .font(Constants.Typography.heading)
                    .foregroundColor(customStyleStore.canAddMore ? .ink : .fog)
                Text("\(customStyleStore.styles.count) of \(CustomPromptStyleStore.maxStyles) custom styles")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
            Spacer()
        }
        .padding(.vertical, Constants.UI.Padding.small)
    }
    .disabled(!customStyleStore.canAddMore)
}
```

- [ ] **Step 4: Make generatePrompts async with geocoding**

Convert `generatePrompts()` to async. Add geocoding:

```swift
private func generatePrompts() {
    guard prompts.isEmpty else { return }
    Task {
        let routeSamples = walk.routeData
        let placeNames = await geocodeWalkRoute(routeSamples)
        geocodedPlaces = placeNames
        let routeSpeeds = routeSamples.map { $0.speed }

        let recordings = walk.voiceRecordings.compactMap { recording -> PromptGenerator.RecordingContext? in
            guard let uuid = recording.uuid,
                  let text = transcriptions[uuid] else { return nil }
            let startCoord = closestCoordinate(to: recording.startDate, in: routeSamples)
            let endCoord = closestCoordinate(to: recording.endDate, in: routeSamples)
            return PromptGenerator.RecordingContext(
                text: text,
                timestamp: recording.startDate,
                startCoordinate: startCoord,
                endCoordinate: endCoord,
                wordsPerMinute: recording.wordsPerMinute
            )
        }.sorted { $0.timestamp < $1.timestamp }

        let meditations = walk.activityIntervals
            .filter { $0.activityType == .meditation }
            .sorted { $0.startDate < $1.startDate }
            .map { PromptGenerator.MeditationContext(startDate: $0.startDate, endDate: $0.endDate, duration: $0.duration) }

        prompts = PromptGenerator.generateAll(
            recordings: recordings,
            meditations: meditations,
            duration: walk.activeDuration,
            distance: walk.distance,
            startDate: walk.startDate,
            placeNames: placeNames,
            routeSpeeds: routeSpeeds,
            recentWalkSnippets: recentWalkSnippets
        )
        regenerateCustomPrompts()
    }
}
```

- [ ] **Step 5: Add geocoding helper**

```swift
private func geocodeWalkRoute(_ samples: [RouteDataSampleInterface]) async -> [PromptGenerator.PlaceContext] {
    guard let first = samples.first, let last = samples.last else { return [] }
    let geocoder = CLGeocoder()
    var places: [PromptGenerator.PlaceContext] = []

    if let name = await reverseGeocode(geocoder: geocoder, lat: first.latitude, lon: first.longitude, delay: false) {
        places.append(PromptGenerator.PlaceContext(name: name, coordinate: (lat: first.latitude, lon: first.longitude), role: .start))
    }

    let distance = CLLocation(latitude: first.latitude, longitude: first.longitude)
        .distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude))
    if distance > 500, let name = await reverseGeocode(geocoder: geocoder, lat: last.latitude, lon: last.longitude) {
        places.append(PromptGenerator.PlaceContext(name: name, coordinate: (lat: last.latitude, lon: last.longitude), role: .end))
    }

    if walk.distance > 2000 {
        let midIndex = samples.count / 2
        let mid = samples[midIndex]
        if let name = await reverseGeocode(geocoder: geocoder, lat: mid.latitude, lon: mid.longitude) {
            places.append(PromptGenerator.PlaceContext(name: name, coordinate: (lat: mid.latitude, lon: mid.longitude), role: .midpoint))
        }
    }

    return places
}

private func reverseGeocode(geocoder: CLGeocoder, lat: Double, lon: Double, delay: Bool = true) async -> String? {
    do {
        if delay {
            try await Task.sleep(nanoseconds: 1_100_000_000)
        }
        let placemarks = try await geocoder.reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon))
        guard let pm = placemarks.first else { return nil }
        let parts = [pm.name, pm.locality].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    } catch {
        return nil
    }
}
```

Add `import CoreLocation` at top of file.

- [ ] **Step 6: Add regenerateCustomPrompts helper and sheet for editor**

```swift
private func regenerateCustomPrompts() {
    // Uses same context as built-in prompts but with custom styles
    let routeSamples = walk.routeData
    let routeSpeeds = routeSamples.map { $0.speed }
    let recordings = walk.voiceRecordings.compactMap { recording -> PromptGenerator.RecordingContext? in
        guard let uuid = recording.uuid,
              let text = transcriptions[uuid] else { return nil }
        return PromptGenerator.RecordingContext(
            text: text,
            timestamp: recording.startDate,
            startCoordinate: closestCoordinate(to: recording.startDate, in: routeSamples),
            endCoordinate: closestCoordinate(to: recording.endDate, in: routeSamples),
            wordsPerMinute: recording.wordsPerMinute
        )
    }.sorted { $0.timestamp < $1.timestamp }
    let meditations = walk.activityIntervals
        .filter { $0.activityType == .meditation }
        .sorted { $0.startDate < $1.startDate }
        .map { PromptGenerator.MeditationContext(startDate: $0.startDate, endDate: $0.endDate, duration: $0.duration) }

    customPrompts = customStyleStore.styles.map { customStyle in
        PromptGenerator.generateCustom(
            customStyle: customStyle,
            recordings: recordings,
            meditations: meditations,
            duration: walk.activeDuration,
            distance: walk.distance,
            startDate: walk.startDate,
            placeNames: geocodedPlaces,
            routeSpeeds: routeSpeeds,
            recentWalkSnippets: recentWalkSnippets
        )
    }
}
```

Add `.sheet(isPresented: $showEditor)` for the editor:
```swift
.sheet(isPresented: $showEditor) {
    CustomPromptEditorView(store: customStyleStore, editingStyle: editingStyle)
}
.onChange(of: showEditor) { showing in
    if !showing { regenerateCustomPrompts() }
}
```

- [ ] **Step 7: Update WalkSummaryView to pass recentWalkSnippets**

In `WalkSummaryView.swift` (lines 55-59), update the PromptListView call to fetch and pass recent walk snippets:

Add a computed property or method that queries recent walks:
```swift
private var recentWalkSnippets: [PromptGenerator.WalkSnippet] {
    guard let walks = try? DataManager.dataStack.fetchAll(
        From<Walk>()
            .where(\._startDate < walk.startDate)
            .orderBy(.descending(\._startDate))
    ) else { return [] }

    let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    return walks
        .filter { w in w.voiceRecordings.contains { $0.transcription != nil } }
        .prefix(3)
        .map { w in
            let allText = w.voiceRecordings
                .compactMap { $0.transcription }
                .joined(separator: " ")
            let preview = String(allText.prefix(200)).truncatedAtWordBoundary()
            return PromptGenerator.WalkSnippet(date: w.startDate, placeName: nil, transcriptionPreview: preview)
        }
}
```

Add a String extension for word-boundary truncation (in PromptGenerator.swift or as a small extension):
```swift
extension String {
    func truncatedAtWordBoundary(maxLength: Int = 200) -> String {
        guard count > maxLength else { return self }
        let truncated = prefix(maxLength)
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }
        return String(truncated) + "..."
    }
}
```

Update the sheet:
```swift
PromptListView(walk: walk, transcriptions: transcriptions, recentWalkSnippets: recentWalkSnippets)
```

Add `import CoreStore` to WalkSummaryView if not already present.

- [ ] **Step 8: Verify project compiles**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 9: Run all tests**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E '(Test Case|BUILD|Executed)'`
Expected: All tests PASS

- [ ] **Step 10: Commit**

```bash
git add Pilgrim/Scenes/Prompts/PromptListView.swift \
        Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift \
        Pilgrim/Models/PromptGenerator.swift
git commit -m "feat: add custom styles, geocoding, and walk threading to PromptListView"
```

---

## Chunk 4: Deep Links UI

### Task 14: PromptDetailView — AI Deep Link Pills

**Files:**
- Modify: `Pilgrim/Scenes/Prompts/PromptDetailView.swift`

- [ ] **Step 1: Add state for AI pills**

Add to PromptDetailView state:
```swift
@State private var showAIPills = false
```

- [ ] **Step 2: Update copy button action**

Replace the copy button action (lines 49-56) to use 8-second unified timer:

```swift
Button {
    UIPasteboard.general.string = prompt.text
    withAnimation(.easeOut(duration: 0.15)) { copyScale = 0.95 }
    withAnimation(.easeOut(duration: 0.15).delay(0.15)) { copyScale = 1.0 }
    showCopiedFeedback = true
    withAnimation(.easeOut(duration: 0.3)) { showAIPills = true }
    DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
        withAnimation {
            showCopiedFeedback = false
            showAIPills = false
        }
    }
}
```

- [ ] **Step 3: Add AI pills view below action buttons**

Replace `actionButtons` with a VStack that includes the pills:

```swift
private var actionButtons: some View {
    VStack(spacing: Constants.UI.Padding.small) {
        HStack(spacing: Constants.UI.Padding.normal) {
            // ... existing copy button ...
            // ... existing share button ...
        }

        if showAIPills {
            VStack(spacing: Constants.UI.Padding.small) {
                Text("Paste in your favorite AI")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)

                HStack(spacing: Constants.UI.Padding.small) {
                    aiPill(name: "ChatGPT", url: "https://chat.openai.com/")
                    aiPill(name: "Claude", url: "https://claude.ai/new")
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

private func aiPill(name: String, url: String) -> some View {
    Button {
        if let url = URL(string: url) {
            UIApplication.shared.open(url)
        }
    } label: {
        HStack(spacing: 4) {
            Text(name)
                .font(Constants.Typography.caption)
                .fontWeight(.semibold)
            Image(systemName: "arrow.up.right")
                .font(.caption2)
        }
        .foregroundColor(.stone)
        .padding(.horizontal, Constants.UI.Padding.normal)
        .padding(.vertical, Constants.UI.Padding.small)
        .background(Color.parchmentSecondary)
        .clipShape(Capsule())
    }
}
```

- [ ] **Step 4: Verify project compiles**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Run all tests**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E '(Test Case|BUILD|Executed)'`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add Pilgrim/Scenes/Prompts/PromptDetailView.swift
git commit -m "feat: add AI deep link pills to PromptDetailView"
```

---

### Task 15: Final Integration Test

- [ ] **Step 1: Run full test suite**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E '(Test Case|BUILD|Executed)'`
Expected: All tests PASS, BUILD SUCCEEDED

- [ ] **Step 2: Run SwiftLint**

Run: `Pods/SwiftLint/swiftlint lint --config .swiftlint.yml 2>&1 | tail -10`
Expected: No errors (warnings acceptable)

- [ ] **Step 3: Commit any lint fixes if needed**

Stage only the specific files that were modified for lint fixes, then commit:
```bash
git commit -m "chore: fix lint warnings"
```
