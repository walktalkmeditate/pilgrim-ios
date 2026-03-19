# Guided Meditation Voice Guide Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the voice guide system to play periodic prompts during meditation, with concentric voice ring visuals and a combined options sheet.

**Architecture:** Add optional `meditationPrompts` and `meditationScheduling` to `VoiceGuidePack`. Refactor `VoiceGuideScheduler` with context mode and configurable thresholds. Create `MeditationGuideManagement` to orchestrate meditation-context playback. Modify `MeditationView` for combined options sheet, voice ring overlay, and slow/soften breathing.

**Tech Stack:** Swift, SwiftUI, Combine, AVFoundation

**Spec:** `docs/superpowers/specs/2026-03-19-guided-meditation-voice-design.md`

**Deferred:** The spec's "WalkOptionsSheet Enhancement (Bonus)" — adding download-in-context to the walk guide's options sheet — is deferred to a follow-up. This plan covers meditation voice guide only.

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `Pilgrim/Models/Audio/VoiceGuide/VoiceGuideManifest.swift` | Add `meditationPrompts`, `meditationScheduling`, `hasMeditationGuide` to `VoiceGuidePack` |
| Modify | `Pilgrim/Models/Audio/VoiceGuide/VoiceGuideScheduler.swift` | Add `SchedulerContext` enum, configurable phase thresholds, prompts array init |
| Modify | `Pilgrim/Models/Audio/VoiceGuide/VoiceGuideDownloadManager.swift` | Include meditation prompts in download queue |
| Modify | `Pilgrim/Models/Audio/VoiceGuide/VoiceGuideFileStore.swift` | Check meditation prompts in `isPackDownloaded` |
| Create | `Pilgrim/Models/Audio/VoiceGuide/MeditationGuideManagement.swift` | Orchestrate meditation voice guidance with `isVoicePlaying` publisher |
| Modify | `Pilgrim/Scenes/ActiveWalk/MeditationView.swift` | Combined options sheet, voice ring overlay, slow/soften breathing |
| Modify | `UnitTests/VoiceGuideManifestTests.swift` | Test meditation prompt decoding, `hasMeditationGuide` |
| Modify | `UnitTests/VoiceGuideSchedulerTests.swift` | Test meditation context mode, configurable thresholds |
| Create | `UnitTests/MeditationGuideManagementTests.swift` | Test start/stop lifecycle, `isVoicePlaying`, generation counter |

---

### Task 1: Extend VoiceGuidePack Data Model

**Files:**
- Modify: `Pilgrim/Models/Audio/VoiceGuide/VoiceGuideManifest.swift`
- Modify: `UnitTests/VoiceGuideManifestTests.swift`

- [ ] **Step 1: Write failing test for meditation fields decoding**

Add to `UnitTests/VoiceGuideManifestTests.swift`:

```swift
private let meditationJSON = """
{
  "version": "1",
  "packs": [
    {
      "id": "test",
      "version": "1",
      "name": "Test",
      "tagline": "t",
      "description": "d",
      "theme": "t",
      "iconName": "star",
      "type": "voiceGuide",
      "walkTypes": ["wander"],
      "scheduling": {
        "densityMinSec": 180,
        "densityMaxSec": 420,
        "minSpacingSec": 120,
        "initialDelaySec": 60,
        "walkEndBufferSec": 300
      },
      "totalDurationSec": 100,
      "totalSizeBytes": 50000,
      "prompts": [
        {"id": "w01", "seq": 1, "durationSec": 10, "fileSizeBytes": 5000, "r2Key": "voiceguide/test/w01.aac"}
      ],
      "meditationScheduling": {
        "densityMinSec": 90,
        "densityMaxSec": 180,
        "minSpacingSec": 60,
        "initialDelaySec": 30,
        "walkEndBufferSec": 0
      },
      "meditationPrompts": [
        {"id": "m01", "seq": 1, "durationSec": 15, "fileSizeBytes": 7000, "r2Key": "voiceguide/test/m01.aac", "phase": "settling"}
      ]
    }
  ]
}
""".data(using: .utf8)!

func testDecodeMeditationPrompts() throws {
    let manifest = try JSONDecoder().decode(VoiceGuideManifest.self, from: meditationJSON)
    let pack = manifest.packs[0]

    XCTAssertNotNil(pack.meditationPrompts)
    XCTAssertEqual(pack.meditationPrompts?.count, 1)
    XCTAssertEqual(pack.meditationPrompts?[0].id, "m01")
    XCTAssertEqual(pack.meditationPrompts?[0].phase, "settling")
    XCTAssertNotNil(pack.meditationScheduling)
    XCTAssertEqual(pack.meditationScheduling?.densityMinSec, 90)
    XCTAssertEqual(pack.meditationScheduling?.initialDelaySec, 30)
}

func testHasMeditationGuide() throws {
    let manifest = try JSONDecoder().decode(VoiceGuideManifest.self, from: meditationJSON)
    XCTAssertTrue(manifest.packs[0].hasMeditationGuide)

    let noMeditation = try JSONDecoder().decode(VoiceGuideManifest.self, from: sampleJSON)
    XCTAssertFalse(noMeditation.packs[0].hasMeditationGuide)
}

func testMeditationFieldsOptional_existingJSONStillDecodes() throws {
    let manifest = try JSONDecoder().decode(VoiceGuideManifest.self, from: sampleJSON)
    let pack = manifest.packs[0]
    XCTAssertNil(pack.meditationPrompts)
    XCTAssertNil(pack.meditationScheduling)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/VoiceGuideManifestTests 2>&1 | tail -20`

Expected: Compilation errors — `meditationPrompts`, `meditationScheduling`, `hasMeditationGuide` don't exist on `VoiceGuidePack`.

- [ ] **Step 3: Add fields to VoiceGuidePack**

In `Pilgrim/Models/Audio/VoiceGuide/VoiceGuideManifest.swift`, add to `VoiceGuidePack`:

```swift
struct VoiceGuidePack: Codable, Identifiable {
    let id: String
    let version: String
    let name: String
    let tagline: String
    let description: String
    let theme: String
    let iconName: String
    let type: String
    let walkTypes: [String]
    let scheduling: PromptDensity
    let totalDurationSec: Double
    let totalSizeBytes: Int
    let prompts: [VoiceGuidePrompt]
    let meditationScheduling: PromptDensity?
    let meditationPrompts: [VoiceGuidePrompt]?

    var hasMeditationGuide: Bool {
        !(meditationPrompts ?? []).isEmpty
    }
}
```

Also update the `makePack` helper in `VoiceGuideSchedulerTests.swift` to include the new optional fields (pass `nil` for both):

```swift
return VoiceGuidePack(
    // ... existing fields ...
    prompts: prompts,
    meditationScheduling: nil,
    meditationPrompts: nil
)
```

And update `sampleJSON` test fixture in `VoiceGuideManifestTests.swift` — it should still decode without the new fields (they're optional). No change needed if `Codable` synthesis handles optionals correctly.

- [ ] **Step 4: Run tests to verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/VoiceGuideManifestTests 2>&1 | tail -20`

Expected: All tests pass including the 3 new ones.

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Audio/VoiceGuide/VoiceGuideManifest.swift UnitTests/VoiceGuideManifestTests.swift UnitTests/VoiceGuideSchedulerTests.swift
git commit -m "feat: add meditationPrompts and meditationScheduling to VoiceGuidePack"
```

---

### Task 2: Refactor VoiceGuideScheduler for Meditation Context

**Files:**
- Modify: `Pilgrim/Models/Audio/VoiceGuide/VoiceGuideScheduler.swift`
- Modify: `Pilgrim/Models/Audio/VoiceGuide/VoiceGuideManagement.swift` (update init call)
- Modify: `UnitTests/VoiceGuideSchedulerTests.swift`

- [ ] **Step 1: Write failing tests for meditation context**

Add to `UnitTests/VoiceGuideSchedulerTests.swift`:

```swift
// MARK: - Meditation Context

func testMeditationContext_firesWithoutWalkStatus() {
    let pack = makePack(densityMin: 0, densityMax: 0, initialDelay: 0)
    let prompts = pack.prompts
    let scheduler = VoiceGuideScheduler(
        prompts: prompts,
        scheduling: pack.scheduling,
        context: .meditation,
        startDate: Date().addingTimeInterval(-100)
    )

    var firedPrompt: VoiceGuidePrompt?
    scheduler.onShouldPlay = { firedPrompt = $0 }

    scheduler.testTick()
    XCTAssertNotNil(firedPrompt, "Meditation context should fire without walk status")
}

func testMeditationContext_notBlockedByMeditatingFlag() {
    let pack = makePack(densityMin: 0, densityMax: 0, initialDelay: 0)
    let scheduler = VoiceGuideScheduler(
        prompts: pack.prompts,
        scheduling: pack.scheduling,
        context: .meditation,
        startDate: Date().addingTimeInterval(-100)
    )

    var firedCount = 0
    scheduler.onShouldPlay = { _ in firedCount += 1 }

    scheduler.updateIsMeditating(true)
    scheduler.testTick()
    XCTAssertEqual(firedCount, 1, "Meditation context should ignore isMeditating flag")
}

func testMeditationContext_usesCustomPhaseThresholds() {
    let pack = makePack(promptCount: 3, densityMin: 0, densityMax: 0, initialDelay: 0)
    let prompts = [
        VoiceGuidePrompt(id: "s1", seq: 1, durationSec: 5, fileSizeBytes: 1000, r2Key: "x", phase: "settling"),
        VoiceGuidePrompt(id: "d1", seq: 2, durationSec: 5, fileSizeBytes: 1000, r2Key: "x", phase: "deepening"),
        VoiceGuidePrompt(id: "c1", seq: 3, durationSec: 5, fileSizeBytes: 1000, r2Key: "x", phase: "closing"),
    ]
    let scheduler = VoiceGuideScheduler(
        prompts: prompts,
        scheduling: pack.scheduling,
        context: .meditation,
        startDate: Date().addingTimeInterval(-120),
        settlingThresholdSec: 60,
        closingThresholdSec: 180
    )

    var firedId: String?
    scheduler.onShouldPlay = { firedId = $0.id }

    scheduler.testTick()
    XCTAssertEqual(firedId, "d1", "At 120s with settling=60, closing=180, should be in deepening phase")
}

func testWalkContext_backwardCompatible() {
    let pack = makePack(densityMin: 0, densityMax: 0, initialDelay: 0)
    let scheduler = VoiceGuideScheduler(
        prompts: pack.prompts,
        scheduling: pack.scheduling,
        context: .walk
    )

    var firedCount = 0
    scheduler.onShouldPlay = { _ in firedCount += 1 }

    scheduler.updateWalkStartDate(Date().addingTimeInterval(-100))
    scheduler.updateStatus(.waiting)
    scheduler.testTick()
    XCTAssertEqual(firedCount, 0, "Walk context still requires recording status")

    scheduler.updateStatus(.recording)
    scheduler.testTick()
    XCTAssertEqual(firedCount, 1)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/VoiceGuideSchedulerTests 2>&1 | tail -20`

Expected: Compilation errors — `SchedulerContext`, new `init` signature don't exist.

- [ ] **Step 3: Refactor VoiceGuideScheduler**

In `Pilgrim/Models/Audio/VoiceGuide/VoiceGuideScheduler.swift`:

1. Add `SchedulerContext` enum at the top of the file:

```swift
enum SchedulerContext {
    case walk
    case meditation
}
```

2. Replace the static thresholds with instance properties and update the init:

```swift
final class VoiceGuideScheduler {

    struct WalkState {
        var status: WalkBuilder.Status = .waiting
        var isRecordingVoice = false
        var isMeditating = false
        var walkStartDate: Date?
    }

    private let prompts: [VoiceGuidePrompt]
    private let scheduling: PromptDensity
    private let context: SchedulerContext
    private let settlingThresholdSec: TimeInterval
    private let closingThresholdSec: TimeInterval
    private var startDate: Date?
    private var cancellables: [AnyCancellable] = []

    private var walkState = WalkState()
    private var isPaused = false
    private var isPlaying = false
    private var lastPromptTime: Date?
    private var nextIntervalSec: TimeInterval = 0
    private(set) var playedPromptIds: Set<String> = []
    private var silenceUntil: Date?

    var onShouldPlay: ((VoiceGuidePrompt) -> Void)?

    init(
        prompts: [VoiceGuidePrompt],
        scheduling: PromptDensity,
        context: SchedulerContext = .walk,
        startDate: Date? = nil,
        settlingThresholdSec: TimeInterval = 20 * 60,
        closingThresholdSec: TimeInterval = 45 * 60
    ) {
        self.prompts = prompts
        self.scheduling = scheduling
        self.context = context
        self.startDate = startDate
        self.settlingThresholdSec = settlingThresholdSec
        self.closingThresholdSec = closingThresholdSec
        drawNextInterval()
    }
```

3. Update `tick()` for context mode:

```swift
private func tick() {
    switch context {
    case .walk:
        guard walkState.status == .recording,
              !walkState.isRecordingVoice,
              !walkState.isMeditating,
              !isPaused,
              !isPlaying else { return }
    case .meditation:
        guard !isPaused, !isPlaying else { return }
    }

    if let silenceUntil, Date() < silenceUntil { return }

    let effectiveStartDate: Date?
    switch context {
    case .walk: effectiveStartDate = walkState.walkStartDate
    case .meditation: effectiveStartDate = startDate
    }

    guard let startDate = effectiveStartDate else { return }

    let elapsed = Date().timeIntervalSince(startDate)
    guard elapsed >= TimeInterval(scheduling.initialDelaySec) else { return }

    if let lastTime = lastPromptTime {
        let sinceLast = Date().timeIntervalSince(lastTime)
        guard sinceLast >= nextIntervalSec else { return }
    }

    guard let prompt = nextPrompt(elapsed: elapsed) else { return }

    markPlaybackStarted()
    onShouldPlay?(prompt)
}
```

4. Update `nextPrompt` to use `self.prompts` instead of `pack.prompts`:

```swift
private func nextPrompt(elapsed: TimeInterval) -> VoiceGuidePrompt? {
    let currentPhase = phase(for: elapsed)
    let sorted = prompts.sorted { $0.seq < $1.seq }
    // ... rest unchanged ...
}
```

5. Update `phase(for:)` to use instance thresholds:

```swift
private func phase(for elapsed: TimeInterval) -> PromptPhase {
    if elapsed < settlingThresholdSec {
        return .settling
    } else if elapsed >= closingThresholdSec {
        return .closing
    }
    return .deepening
}
```

6. Update `drawNextInterval` to use `scheduling`:

```swift
private func drawNextInterval() {
    let min = scheduling.densityMinSec
    let max = scheduling.densityMaxSec
    nextIntervalSec = TimeInterval(Int.random(in: min...max))
}
```

7. Remove the `pack` stored property entirely.

8. **Also update VoiceGuideManagement** (must happen in the same step to keep the project compilable). In `Pilgrim/Models/Audio/VoiceGuide/VoiceGuideManagement.swift`, update `startGuiding`:

```swift
func startGuiding(pack: VoiceGuidePack) {
    stopGuiding()

    generation += 1
    let capturedGeneration = generation
    currentPackId = pack.id

    let sched = VoiceGuideScheduler(
        prompts: pack.prompts,
        scheduling: pack.scheduling,
        context: .walk
    )
    // ... rest unchanged ...
}
```

- [ ] **Step 4: Update existing tests to new init**

In `UnitTests/VoiceGuideSchedulerTests.swift`, update all existing tests that use `VoiceGuideScheduler(pack: pack)` to the new init:

```swift
let scheduler = VoiceGuideScheduler(
    prompts: pack.prompts,
    scheduling: pack.scheduling,
    context: .walk
)
```

Each existing test that calls `scheduler.updateWalkStartDate(...)` and `scheduler.updateStatus(.recording)` continues working unchanged in `.walk` context.

- [ ] **Step 5: Run all tests to verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/VoiceGuideSchedulerTests 2>&1 | tail -20`

Expected: All tests pass (existing + new).

- [ ] **Step 6: Commit**

```bash
git add Pilgrim/Models/Audio/VoiceGuide/VoiceGuideScheduler.swift Pilgrim/Models/Audio/VoiceGuide/VoiceGuideManagement.swift UnitTests/VoiceGuideSchedulerTests.swift
git commit -m "refactor: add SchedulerContext and configurable phase thresholds to VoiceGuideScheduler"
```

---

### Task 3: Update Download Manager and File Store

**Files:**
- Modify: `Pilgrim/Models/Audio/VoiceGuide/VoiceGuideDownloadManager.swift:28`
- Modify: `Pilgrim/Models/Audio/VoiceGuide/VoiceGuideFileStore.swift:24-26`

- [ ] **Step 1: Update VoiceGuideDownloadManager**

In `Pilgrim/Models/Audio/VoiceGuide/VoiceGuideDownloadManager.swift`, change line 28 from:

```swift
let missing = pack.prompts.filter { !fileStore.isAvailable($0, packId: pack.id) }
```

to:

```swift
let allPrompts = pack.prompts + (pack.meditationPrompts ?? [])
let missing = allPrompts.filter { !fileStore.isAvailable($0, packId: pack.id) }
```

- [ ] **Step 2: Update VoiceGuideFileStore**

In `Pilgrim/Models/Audio/VoiceGuide/VoiceGuideFileStore.swift`, change `isPackDownloaded` from:

```swift
func isPackDownloaded(_ pack: VoiceGuidePack) -> Bool {
    pack.prompts.allSatisfy { isAvailable($0, packId: pack.id) }
}
```

to:

```swift
func isPackDownloaded(_ pack: VoiceGuidePack) -> Bool {
    let allPrompts = pack.prompts + (pack.meditationPrompts ?? [])
    return allPrompts.allSatisfy { isAvailable($0, packId: pack.id) }
}
```

- [ ] **Step 3: Build to verify compilation**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Run full test suite**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20`

Expected: All tests pass. No regressions.

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Audio/VoiceGuide/VoiceGuideDownloadManager.swift Pilgrim/Models/Audio/VoiceGuide/VoiceGuideFileStore.swift
git commit -m "fix: include meditation prompts in download queue and pack status check"
```

---

### Task 4: Create MeditationGuideManagement

**Files:**
- Create: `Pilgrim/Models/Audio/VoiceGuide/MeditationGuideManagement.swift`
- Create: `UnitTests/MeditationGuideManagementTests.swift`

- [ ] **Step 1: Write failing tests**

Create `UnitTests/MeditationGuideManagementTests.swift`:

```swift
import XCTest
@testable import Pilgrim

final class MeditationGuideManagementTests: XCTestCase {

    private func makePack() -> VoiceGuidePack {
        let walkPrompts = [
            VoiceGuidePrompt(id: "w01", seq: 1, durationSec: 5, fileSizeBytes: 1000, r2Key: "x")
        ]
        let medPrompts = [
            VoiceGuidePrompt(id: "m01", seq: 1, durationSec: 5, fileSizeBytes: 1000, r2Key: "x"),
            VoiceGuidePrompt(id: "m02", seq: 2, durationSec: 5, fileSizeBytes: 1000, r2Key: "x"),
        ]
        return VoiceGuidePack(
            id: "test",
            version: "1",
            name: "Test",
            tagline: "t",
            description: "d",
            theme: "t",
            iconName: "star",
            type: "voiceGuide",
            walkTypes: ["wander"],
            scheduling: PromptDensity(densityMinSec: 180, densityMaxSec: 420, minSpacingSec: 120, initialDelaySec: 60, walkEndBufferSec: 300),
            totalDurationSec: 15,
            totalSizeBytes: 3000,
            prompts: walkPrompts,
            meditationScheduling: PromptDensity(densityMinSec: 0, densityMaxSec: 0, minSpacingSec: 0, initialDelaySec: 0, walkEndBufferSec: 0),
            meditationPrompts: medPrompts
        )
    }

    func testStartGuiding_setsIsActive() {
        let mgmt = MeditationGuideManagement()
        XCTAssertFalse(mgmt.isActive)

        mgmt.startGuiding(pack: makePack())
        XCTAssertTrue(mgmt.isActive)
    }

    func testStopGuiding_resetsState() {
        let mgmt = MeditationGuideManagement()
        mgmt.startGuiding(pack: makePack())
        mgmt.stopGuiding()

        XCTAssertFalse(mgmt.isActive)
        XCTAssertFalse(mgmt.isVoicePlaying)
    }

    func testStopGuiding_resetsIsVoicePlaying() {
        let mgmt = MeditationGuideManagement()
        mgmt.startGuiding(pack: makePack())

        mgmt.stopGuiding()
        XCTAssertFalse(mgmt.isVoicePlaying)
    }

    func testRestartGuiding_resetsIsVoicePlaying() {
        let mgmt = MeditationGuideManagement()
        mgmt.startGuiding(pack: makePack())

        mgmt.startGuiding(pack: makePack())
        XCTAssertTrue(mgmt.isActive)
        XCTAssertFalse(mgmt.isVoicePlaying, "Restarting should reset voice playing state")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/MeditationGuideManagementTests 2>&1 | tail -20`

Expected: Compilation error — `MeditationGuideManagement` doesn't exist.

- [ ] **Step 3: Implement MeditationGuideManagement**

Create `Pilgrim/Models/Audio/VoiceGuide/MeditationGuideManagement.swift`:

```swift
import Foundation
import Combine

final class MeditationGuideManagement: ObservableObject {

    @Published private(set) var isActive = false
    @Published private(set) var isVoicePlaying = false

    private var scheduler: VoiceGuideScheduler?
    private let player = VoiceGuidePlayer.shared
    private var generation = 0
    private var currentPackId: String?

    func startGuiding(pack: VoiceGuidePack) {
        stopGuiding()

        guard let medPrompts = pack.meditationPrompts,
              let medScheduling = pack.meditationScheduling,
              !medPrompts.isEmpty else { return }

        generation += 1
        let capturedGeneration = generation
        currentPackId = pack.id

        player.stop()

        let sched = VoiceGuideScheduler(
            prompts: medPrompts,
            scheduling: medScheduling,
            context: .meditation,
            startDate: Date(),
            settlingThresholdSec: 5 * 60,
            closingThresholdSec: 15 * 60
        )
        sched.onShouldPlay = { [weak self] prompt in
            self?.playPrompt(prompt, packId: pack.id, generation: capturedGeneration)
        }
        scheduler = sched
        isActive = true

        sched.start()
    }

    func stopGuiding() {
        scheduler?.stop()
        player.stop()
        scheduler = nil
        isActive = false
        isVoicePlaying = false
        currentPackId = nil
    }

    private func playPrompt(_ prompt: VoiceGuidePrompt, packId: String, generation: Int) {
        guard VoiceGuideFileStore.shared.isAvailable(prompt, packId: packId) else {
            scheduler?.markPlayed(prompt.id)
            return
        }
        isVoicePlaying = true
        player.play(prompt: prompt, packId: packId) { [weak self] in
            guard let self, self.generation == generation else { return }
            self.isVoicePlaying = false
            self.scheduler?.markPlayed(prompt.id)
        }
    }
}
```

- [ ] **Step 4: Add to Xcode project**

The new file must be added to the Pilgrim target in the Xcode project. Also add the test file to the UnitTests target. Check the `.pbxproj` for existing patterns — the voice guide files should be grouped together.

- [ ] **Step 5: Run tests to verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/MeditationGuideManagementTests 2>&1 | tail -20`

Expected: All 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Pilgrim/Models/Audio/VoiceGuide/MeditationGuideManagement.swift UnitTests/MeditationGuideManagementTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat: add MeditationGuideManagement for meditation voice guidance"
```

---

### Task 5: Combined Options Sheet in MeditationView

**Files:**
- Modify: `Pilgrim/Scenes/ActiveWalk/MeditationView.swift`

This task replaces the `showBreathPicker` sheet with a combined `showMeditationOptions` sheet that includes voice guide selection above breath rhythm.

- [ ] **Step 1: Add state properties**

In `MeditationView.swift`, add these state properties alongside existing ones:

```swift
@State private var showMeditationOptions = false
@State private var meditationGuide: MeditationGuideManagement?
@State private var selectedGuidePackId: String?
@ObservedObject private var manifestService = VoiceGuideManifestService.shared
@ObservedObject private var downloadManager = VoiceGuideDownloadManager.shared
```

Replace `showBreathPicker` with `showMeditationOptions` in the long-press gesture (line 48-51):

```swift
.onLongPressGesture(minimumDuration: 1.0) {
    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    showMeditationOptions = true
}
```

Update the `.sheet` binding (line 89-94) from `showBreathPicker` to `showMeditationOptions` and reference `meditationOptionsSheet` instead of `breathPickerSheet`.

- [ ] **Step 2: Build the combined options sheet view**

Replace the `breathPickerSheet` computed property with `meditationOptionsSheet`:

```swift
private var meditationOptionsSheet: some View {
    VStack(spacing: 16) {
        Text(showsVoiceGuideSection ? "Meditation Options" : "Breath Rhythm")
            .font(Constants.Typography.heading)
            .foregroundColor(Color.ink.opacity(0.8))
            .padding(.top, 12)

        ScrollView {
            VStack(spacing: 6) {
                if showsVoiceGuideSection {
                    voiceGuideSection
                    Divider()
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                }
                breathRhythmSection
            }
            .padding(.horizontal, 16)
        }
    }
}

private var showsVoiceGuideSection: Bool {
    UserPreferences.voiceGuideEnabled.value &&
    manifestService.packs.contains(where: \.hasMeditationGuide)
}
```

- [ ] **Step 3: Build voice guide section**

```swift
private var voiceGuideSection: some View {
    VStack(alignment: .leading, spacing: 6) {
        Text("VOICE GUIDE")
            .font(Constants.Typography.caption)
            .foregroundColor(Color.fog.opacity(0.4))
            .tracking(1)
            .padding(.leading, 4)

        Button {
            selectedGuidePackId = nil
            meditationGuide?.stopGuiding()
            meditationGuide = nil
            voicePlayingCancellable?.cancel()
            voicePlayingCancellable = nil
        } label: {
            guideRow(name: "Off", subtitle: "Meditate in silence", isSelected: selectedGuidePackId == nil)
        }

        ForEach(manifestService.packs.filter(\.hasMeditationGuide)) { pack in
            let isDownloaded = VoiceGuideFileStore.shared.isPackDownloaded(pack)
            let isDownloading = downloadManager.activeDownloads.contains(pack.id)

            Button {
                if isDownloaded {
                    selectGuidePack(pack)
                } else if !isDownloading {
                    downloadManager.downloadPack(pack)
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pack.name)
                            .font(Constants.Typography.body)
                            .foregroundColor(Color.ink.opacity(isDownloaded ? 0.9 : 0.4))
                        if !isDownloaded {
                            if isDownloading, let progress = downloadManager.downloadProgress[pack.id] {
                                SwiftUI.ProgressView(value: progress)
                                    .tint(.moss)
                            } else {
                                Text("Not downloaded")
                                    .font(Constants.Typography.caption)
                                    .foregroundColor(Color.fog.opacity(0.35))
                            }
                        } else {
                            Text(pack.tagline)
                                .font(Constants.Typography.caption)
                                .foregroundColor(Color.fog.opacity(0.35))
                        }
                    }
                    Spacer()
                    if selectedGuidePackId == pack.id {
                        Image(systemName: "checkmark")
                            .font(.caption)
                            .foregroundColor(.moss)
                    } else if !isDownloaded && !isDownloading {
                        Image(systemName: "arrow.down.circle")
                            .font(.caption)
                            .foregroundColor(Color.fog.opacity(0.3))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    selectedGuidePackId == pack.id
                        ? Color.moss.opacity(0.08)
                        : Color.clear
                )
                .cornerRadius(10)
            }
        }
    }
}

private func guideRow(name: String, subtitle: String, isSelected: Bool) -> some View {
    HStack {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(Constants.Typography.body)
                .foregroundColor(Color.ink.opacity(0.9))
            Text(subtitle)
                .font(Constants.Typography.caption)
                .foregroundColor(Color.fog.opacity(0.35))
        }
        Spacer()
        if isSelected {
            Image(systemName: "checkmark")
                .font(.caption)
                .foregroundColor(.moss)
        }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
    .background(isSelected ? Color.moss.opacity(0.08) : Color.clear)
    .cornerRadius(10)
}

private func selectGuidePack(_ pack: VoiceGuidePack) {
    selectedGuidePackId = pack.id
    let mgmt = MeditationGuideManagement()
    mgmt.startGuiding(pack: pack)
    meditationGuide = mgmt
}
```

- [ ] **Step 4: Extract breath rhythm section**

Move the existing `ForEach(BreathRhythm.all)` content into a `breathRhythmSection` computed property. Change `showBreathPicker = false` to `showMeditationOptions = false`:

```swift
private var breathRhythmSection: some View {
    VStack(alignment: .leading, spacing: 6) {
        if showsVoiceGuideSection {
            Text("BREATH RHYTHM")
                .font(Constants.Typography.caption)
                .foregroundColor(Color.fog.opacity(0.4))
                .tracking(1)
                .padding(.leading, 4)
        }
        ForEach(BreathRhythm.all) { r in
            Button {
                selectedRhythmId = r.id
                UserPreferences.breathRhythm.value = r.id
                isActive = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isActive = true
                    startBreathCycle()
                }
                showMeditationOptions = false
            } label: {
                // ... existing row layout unchanged ...
            }
        }
    }
}
```

- [ ] **Step 5: Remove old `showBreathPicker` state and `breathPickerSheet`**

Delete the `@State private var showBreathPicker` declaration and the `breathPickerSheet` computed property. They're fully replaced.

- [ ] **Step 6: Update closing ceremony to stop voice guide**

In `beginClosingCeremony()`, add voice guide cleanup as the first step:

```swift
private func beginClosingCeremony() {
    guard !isClosing else { return }
    meditationGuide?.stopGuiding()
    meditationGuide = nil
    voicePlayingCancellable?.cancel()
    voicePlayingCancellable = nil

    isClosing = true
    isActive = false
    clock.stop()
    // ... rest unchanged ...
}
```

- [ ] **Step 7: Build to verify compilation**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
git add Pilgrim/Scenes/ActiveWalk/MeditationView.swift
git commit -m "feat: add combined options sheet with voice guide picker to meditation"
```

---

### Task 6: Voice Ring Overlay and Slow/Soften Breathing

**Files:**
- Modify: `Pilgrim/Scenes/ActiveWalk/MeditationView.swift`

- [ ] **Step 1: Add voice-related state**

Add alongside existing state properties:

```swift
@State private var voiceRings: [VoiceRing] = []
@State private var breathSpeedMultiplier: Double = 1.0
@State private var voiceSoften: Double = 0
```

Add the `VoiceRing` struct alongside the existing `RippleRing`:

```swift
struct VoiceRing: Identifiable {
    let id: UUID
    var size: CGFloat
    var opacity: Double
    var irregularity: CGFloat
}
```

- [ ] **Step 2: Add voice ring layer**

Add a `voiceRingLayer` similar to the existing `rippleLayer`:

```swift
private var voiceRingLayer: some View {
    GeometryReader { geo in
        let center = CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.35)
        ForEach(voiceRings) { ring in
            Circle()
                .stroke(Color.moss.opacity(ring.opacity), lineWidth: 1)
                .frame(width: ring.size, height: ring.size)
                .scaleEffect(x: 1.0 + ring.irregularity * 0.04, y: 1.0 - ring.irregularity * 0.02)
                .position(center)
        }
    }
    .allowsHitTesting(false)
}
```

Add it to the ZStack in `body`, between `rippleLayer` and the VStack:

```swift
ZStack {
    background
    particleLayer
    rippleLayer
    voiceRingLayer    // <-- new

    VStack(spacing: 0) {
```

- [ ] **Step 3: Modify breathing circle for voice softening**

Update the breathing circle's outer gradient opacity to respond to `voiceSoften`:

```swift
private var breathingCircle: some View {
    ZStack {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.moss.opacity(0.5 - voiceSoften * 0.15),
                        Color.moss.opacity(0.15 - voiceSoften * 0.05),
                        Color.moss.opacity(0.0)
                    ],
                    // ... rest unchanged
                )
            )
            .frame(width: 320, height: 320)
            .scaleEffect(circleScale)
        // ... inner circles unchanged ...
    }
}
```

- [ ] **Step 4: Add voice playing state observer via Combine**

`@State` on a reference type does not observe `@Published` properties. Use a Combine subscription instead. Add a cancellable state:

```swift
@State private var voicePlayingCancellable: AnyCancellable?
```

When a guide is created in `selectGuidePack`, subscribe to its publisher:

```swift
private func selectGuidePack(_ pack: VoiceGuidePack) {
    selectedGuidePackId = pack.id
    let mgmt = MeditationGuideManagement()
    mgmt.startGuiding(pack: pack)
    meditationGuide = mgmt
    voicePlayingCancellable = mgmt.$isVoicePlaying
        .receive(on: DispatchQueue.main)
        .sink { [self] playing in
            if playing { onVoiceStart() } else { onVoiceEnd() }
        }
}
```

Cancel when guide stops (in the "Off" selection and `beginClosingCeremony`):

```swift
voicePlayingCancellable?.cancel()
voicePlayingCancellable = nil
```

Implement the handlers:

```swift
private func onVoiceStart() {
    withAnimation(.easeInOut(duration: 2.0)) {
        voiceSoften = 1.0
    }
    emitVoiceRings()
}

private func onVoiceEnd() {
    withAnimation(.easeInOut(duration: 1.5)) {
        voiceSoften = 0
    }
    fadeOutVoiceRings()
}

private func emitVoiceRings() {
    voiceRings.removeAll()
    for i in 0..<4 {
        let ring = VoiceRing(
            id: UUID(),
            size: CGFloat(180 + i * 40) * circleScale,
            opacity: 0.15 - Double(i) * 0.03,
            irregularity: CGFloat.random(in: -1...1)
        )
        voiceRings.append(ring)
    }
}

private func fadeOutVoiceRings() {
    withAnimation(.easeOut(duration: 1.5)) {
        for i in voiceRings.indices {
            voiceRings[i].opacity = 0
        }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        voiceRings.removeAll()
    }
}
```

- [ ] **Step 5: Modify breath cycle timing for slow/soften**

In the breath animation functions (`breathIn`, `breathOut`, etc.), multiply durations by `breathSpeedMultiplier`. Connect the multiplier to `voiceSoften`:

The simplest approach: in `onVoiceStart`, set `breathSpeedMultiplier = 2.0` (halves the speed). In `onVoiceEnd`, set it back to `1.0`. But since the breath cycle uses `DispatchQueue.asyncAfter` with pre-calculated delays, the speed change will take effect at the next breath phase transition — which is natural and non-jarring.

Update `onVoiceStart`/`onVoiceEnd`:

```swift
private func onVoiceStart() {
    withAnimation(.easeInOut(duration: 2.0)) {
        voiceSoften = 1.0
        breathSpeedMultiplier = 2.0
    }
    emitVoiceRings()
}

private func onVoiceEnd() {
    withAnimation(.easeInOut(duration: 3.0)) {
        voiceSoften = 0
        breathSpeedMultiplier = 1.0
    }
    fadeOutVoiceRings()
}
```

In `breathIn()`, `breathOut()`, `holdAfterInhale()`, `holdAfterExhale()`, multiply the animation duration and the async-after delay by `breathSpeedMultiplier`. For example in `breathIn()`:

```swift
private func breathIn() {
    guard isActive else { return }
    let gen = breathGeneration
    // ...
    phase = .inhale
    let duration = rhythm.inhale * breathSpeedMultiplier
    withAnimation(.easeInOut(duration: duration)) {
        circleScale = 1.0
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
        guard self.isActive, self.breathGeneration == gen else { return }
        // ...
    }
}
```

Apply the same pattern to `breathOut`, `holdAfterInhale`, `holdAfterExhale`.

- [ ] **Step 6: Build to verify compilation**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 7: Run full test suite for regressions**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20`

Expected: All tests pass.

- [ ] **Step 8: Commit**

```bash
git add Pilgrim/Scenes/ActiveWalk/MeditationView.swift
git commit -m "feat: add voice ring overlay and slow/soften breathing during voice prompts"
```

---

### Task 7: Final Integration Test

- [ ] **Step 1: Build the full project**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 2: Run the full test suite**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -30`

Expected: All tests pass. Zero failures, zero regressions.

- [ ] **Step 3: Commit any remaining changes**

If any fixups were needed, commit them.
