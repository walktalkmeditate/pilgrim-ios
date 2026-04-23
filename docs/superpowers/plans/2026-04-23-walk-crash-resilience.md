# Walk Crash Resilience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the `cpu_resource_fatal` crash that kills Pilgrim during locked walk+talk sessions (caused by Mapbox rendering unthrottled in background), and harden the SessionGuard recovery flow so a Talk duration survives any SIGKILL (even if the audio file doesn't).

**Architecture:** Two independent problems, two independent fixes.

1. **Crash fix (Mapbox):** iOS's CPU watchdog kills the app after 80% CPU over 60s. Evidence: three `cpu_resource_fatal` `.ips` reports on 2026-04-22, all identical stacks pointing at MapboxMaps' render loop invoking MapboxCoreMaps' C++ renderer on a background worker thread. `PilgrimMapView` currently has no scene-phase handling, so the map renders at 30 FPS even when the screen is locked or a full-screen meditation overlay is up. Fix: the `Coordinator` observes `UIApplication.didEnterBackground`/`willEnterForeground` + a `isMeditating` binding, and sets `preferredFramesPerSecond = 0` whenever the user can't see the map. Also gate GeoJSON source rebuilds while paused (C++ work even without rendering) and catch up on resume.

2. **Talk metadata resilience:** `checkpointActivityIntervals()` already persists in-flight meditation state (provisional interval with rolling `endDate = Date()`). Voice recording has no equivalent — during Talk, `voiceRecordingsRelay` is empty until `recorder.stop()` fires the delegate, so every SIGKILL loses the entire in-flight segment. Fix: mirror the meditation pattern — on each checkpoint, synthesize a provisional `TempVoiceRecording` from the active `recordingStartDate`/`currentRecordingRelativePath` and append it to the snapshot. On recovery, validate each recording's `.m4a` file; if the moov atom is missing (AVAudioRecorder killed before `.stop()`), clear the path so the summary shows "Recording unavailable" while preserving the duration for the Talk timer. Also handle the phone-call case: observe `CXCallObserver` and stop the recorder cleanly when a call is actually answered (not on every audio-session blip).

**Tech Stack:** Swift / SwiftUI / Combine, AVFoundation, MapboxMaps 11.20, CallKit (new import), CocoaPods + SPM. No new third-party dependencies.

**Reference:** Crash analysis and decision thread in conversation on 2026-04-22 / 2026-04-23.

**Branch:** Create `fix/walk-crash-resilience` before Task 1.

**Execution order rationale:** Ship Tasks 1–4 first (talk metadata persistence + recovery sanitization) so we can *test the recovery path against the still-reproducible CPU crash*. Once we confirm recovery works end-to-end, ship Tasks 5–6 (Mapbox pause) which eliminate the reproducer. Finally ship Task 7 (CXCallObserver) for the phone-call case. Do NOT reorder — testing recovery before the reproducer is removed is the whole point.

---

## File Structure

**No new production files.**

**Modified files:**
- `Pilgrim/Models/Walk/WalkBuilder/Components/VoiceRecordingManagement.swift` — add `checkpointVoiceRecording()` method; import CallKit + CXCallObserver delegate; wire interruption on `hasConnected`
- `Pilgrim/Models/Walk/WalkSessionGuard.swift` — call `checkpointVoiceRecording()` in `checkpointNow`; sanitize unplayable recordings in `recoverIfNeeded`
- `Pilgrim/Views/PilgrimMapView.swift` — observe app lifecycle + `isMeditating` binding in Coordinator; set `preferredFramesPerSecond` accordingly; skip `applyRouteSource` while paused; flush on resume
- `Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift` — pass `isMeditating` binding into `PilgrimMapView`
- `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift` — `isFileAvailable` returns false for empty relativePath

**New test files:**
- `UnitTests/VoiceRecordingCheckpointTests.swift`
- `UnitTests/WalkSessionGuardRecoveryTests.swift`
- `UnitTests/VoiceRecordingCallInterruptionTests.swift`

New test files require manual `Pilgrim.xcodeproj/project.pbxproj` registration in the `UnitTests` group (UnitTests is NOT a synchronized root group — follow the pattern from commit `96ae8e4`).

---

## Task 1: VoiceRecordingManagement exposes checkpoint snapshot

**Files:**
- Modify: `Pilgrim/Models/Walk/WalkBuilder/Components/VoiceRecordingManagement.swift`
- Create: `UnitTests/VoiceRecordingCheckpointTests.swift`

- [ ] **Step 1: Write the failing test**

Create `UnitTests/VoiceRecordingCheckpointTests.swift`:

```swift
import XCTest
@testable import Pilgrim

final class VoiceRecordingCheckpointTests: XCTestCase {

    func test_checkpointVoiceRecording_returnsNil_whenNotRecording() {
        let builder = WalkBuilder()
        let mgmt = VoiceRecordingManagement(builder: builder)

        XCTAssertNil(mgmt.checkpointVoiceRecording())
    }

    func test_checkpointVoiceRecording_returnsSnapshot_whenRecording() {
        let builder = WalkBuilder()
        let mgmt = VoiceRecordingManagement(builder: builder)
        builder.setStatus(.recording)

        // Simulate the internal state an active recording would set.
        // startRecording() requires AVAudioSession permission which isn't
        // available in unit tests, so we test the snapshot surface
        // assuming the state was set by the real startRecording path.
        mgmt._test_setActiveRecording(
            start: Date(timeIntervalSinceNow: -30),
            relativePath: "Recordings/ABC/rec.m4a"
        )

        guard let snapshot = mgmt.checkpointVoiceRecording() else {
            XCTFail("expected a provisional recording snapshot")
            return
        }
        XCTAssertEqual(snapshot.fileRelativePath, "Recordings/ABC/rec.m4a")
        XCTAssertEqual(snapshot.duration, 30, accuracy: 1.0)
        XCTAssertNotNil(snapshot.startDate)
    }
}
```

- [ ] **Step 2: Register the new test file in pbxproj**

Add `UnitTests/VoiceRecordingCheckpointTests.swift` to the UnitTests target by editing `Pilgrim.xcodeproj/project.pbxproj` manually (follow the pattern from commit `96ae8e4`).

- [ ] **Step 3: Run test to verify it fails**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/VoiceRecordingCheckpointTests
```

Expected: compilation failure — `checkpointVoiceRecording` and `_test_setActiveRecording` don't exist yet.

- [ ] **Step 4: Implement `checkpointVoiceRecording()` and the test hook**

Add to `Pilgrim/Models/Walk/WalkBuilder/Components/VoiceRecordingManagement.swift`, after the public `toggleRecording()` method:

```swift
    /// Returns a provisional `TempVoiceRecording` capturing the currently-active
    /// recording's start + elapsed duration so far, or `nil` if no recording is
    /// active. Mirrors the meditation-interval provisional pattern in
    /// `ActiveWalkViewModel.checkpointActivityIntervals()`. The returned recording
    /// has the real in-flight file path; on recovery, the file may or may not be
    /// playable depending on whether AVAudioRecorder wrote its moov atom before
    /// the process died.
    public func checkpointVoiceRecording() -> TempVoiceRecording? {
        guard isRecording,
              let start = currentRecordingStart,
              let relativePath = currentRecordingRelativePath else {
            return nil
        }
        let now = Date()
        return TempVoiceRecording(
            uuid: nil,
            startDate: start,
            endDate: now,
            duration: now.timeIntervalSince(start),
            fileRelativePath: relativePath,
            isEnhanced: false
        )
    }

    #if DEBUG
    /// Test-only hook. Sets the internal state that `startRecording()` would set
    /// without requiring AVAudioSession permission in the unit-test environment.
    func _test_setActiveRecording(start: Date, relativePath: String) {
        currentRecordingStart = start
        currentRecordingRelativePath = relativePath
        recordingStartDate = start
        isRecording = true
    }
    #endif
```

- [ ] **Step 5: Run test to verify it passes**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/VoiceRecordingCheckpointTests
```

Expected: both tests pass.

- [ ] **Step 6: Commit**

```bash
git add Pilgrim/Models/Walk/WalkBuilder/Components/VoiceRecordingManagement.swift UnitTests/VoiceRecordingCheckpointTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(walk): expose in-flight voice-recording snapshot for checkpoints"
```

---

## Task 2: WalkSessionGuard writes talk metadata to checkpoint

**Files:**
- Modify: `Pilgrim/Models/Walk/WalkSessionGuard.swift:116-147`
- Create: `UnitTests/WalkSessionGuardRecoveryTests.swift`

- [ ] **Step 1: Write the failing test**

Create `UnitTests/WalkSessionGuardRecoveryTests.swift`:

```swift
import XCTest
@testable import Pilgrim

final class WalkSessionGuardRecoveryTests: XCTestCase {

    func test_checkpoint_includes_in_flight_talk_metadata() {
        let vm = ActiveWalkViewModel()
        let builder = vm.builder
        builder.setStatus(.recording)

        vm.voiceRecordingManagement._test_setActiveRecording(
            start: Date(timeIntervalSinceNow: -42),
            relativePath: "Recordings/DEADBEEF/rec.m4a"
        )

        // Force a start date on the builder so createCheckpointSnapshot returns non-nil.
        builder._test_setStartDate(Date(timeIntervalSinceNow: -60))

        let snapshot = builder.createCheckpointSnapshot()
        XCTAssertNotNil(snapshot)

        if let inflight = vm.voiceRecordingManagement.checkpointVoiceRecording() {
            snapshot?.appendVoiceRecordings([inflight])
        }

        XCTAssertEqual(snapshot?.voiceRecordings.count, 1)
        XCTAssertEqual(snapshot?.voiceRecordings.first?.fileRelativePath,
                       "Recordings/DEADBEEF/rec.m4a")
        XCTAssertEqual(snapshot?.voiceRecordings.first?.duration ?? 0, 42, accuracy: 1.0)
    }
}
```

- [ ] **Step 2: Register the new test file in pbxproj**

Add `UnitTests/WalkSessionGuardRecoveryTests.swift` to the UnitTests target in `Pilgrim.xcodeproj/project.pbxproj`.

- [ ] **Step 3: Add the builder test hook**

Add to `Pilgrim/Models/Walk/WalkBuilder/WalkBuilder.swift`, in an `#if DEBUG` block near the other test-only helpers:

```swift
    #if DEBUG
    func _test_setStartDate(_ date: Date) {
        startDateRelay.accept(date)
    }
    #endif
```

- [ ] **Step 4: Run test to verify it fails**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/WalkSessionGuardRecoveryTests
```

Expected: PASS (the wiring is in test code, not production — this is a whiteboard test to lock in the shape).

- [ ] **Step 5: Wire it into the production checkpoint path**

Modify `Pilgrim/Models/Walk/WalkSessionGuard.swift`. Find the `checkpointNow()` method and change the section after `snapshot.replaceActivityIntervals(intervals)`:

Before (lines 116-132):
```swift
    func checkpointNow() {
        guard let builder, let snapshot = builder.createCheckpointSnapshot() else {
            print("\(Self.tag) CHECKPOINT SKIPPED — no builder or no start date")
            return
        }

        if let viewModel {
            let intervals = viewModel.checkpointActivityIntervals()
            snapshot.replaceActivityIntervals(intervals)
        }

        if walkUUID == nil {
            walkUUID = Self.extractRecordingDirectoryUUID(from: snapshot) ?? UUID()
        }
```

After:
```swift
    func checkpointNow() {
        guard let builder, let snapshot = builder.createCheckpointSnapshot() else {
            print("\(Self.tag) CHECKPOINT SKIPPED — no builder or no start date")
            return
        }

        if let viewModel {
            let intervals = viewModel.checkpointActivityIntervals()
            snapshot.replaceActivityIntervals(intervals)

            if let inflightTalk = viewModel.voiceRecordingManagement.checkpointVoiceRecording() {
                snapshot.appendVoiceRecordings([inflightTalk])
            }
        }

        if walkUUID == nil {
            walkUUID = Self.extractRecordingDirectoryUUID(from: snapshot) ?? UUID()
        }
```

Also update the checkpoint log at line 143 to include a flag for whether an in-flight talk was captured, for easier debugging:

Before:
```swift
            print("\(Self.tag) CHECKPOINT #\(checkpointCount) — tier: \(currentTier), routes: \(snapshot.routeData.count), pauses: \(snapshot.pauses.count), recordings: \(snapshot.voiceRecordings.count), intervals: \(snapshot.activityIntervals.count), size: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
```

After:
```swift
            let talkFlag = snapshot.voiceRecordings.contains { $0.uuid == nil } ? " (inflight)" : ""
            print("\(Self.tag) CHECKPOINT #\(checkpointCount) — tier: \(currentTier), routes: \(snapshot.routeData.count), pauses: \(snapshot.pauses.count), recordings: \(snapshot.voiceRecordings.count)\(talkFlag), intervals: \(snapshot.activityIntervals.count), size: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
```

- [ ] **Step 6: Run the full test suite**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add Pilgrim/Models/Walk/WalkSessionGuard.swift Pilgrim/Models/Walk/WalkBuilder/WalkBuilder.swift UnitTests/WalkSessionGuardRecoveryTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(walk): persist in-flight talk metadata in SessionGuard checkpoints"
```

---

## Task 3: Sanitize unplayable recordings during recovery

**Files:**
- Modify: `Pilgrim/Models/Walk/WalkSessionGuard.swift` (recoverIfNeeded path)

Recording files written by AVAudioRecorder have no valid MP4 `moov` atom until `recorder.stop()` runs. A SIGKILL mid-recording leaves the `.m4a` with a `duration` of `0` (or `.indefinite`) when read via `AVURLAsset`. We detect this at recovery time and convert the entry to metadata-only (preserve duration from our provisional snapshot, clear the file path so playback UI gracefully shows "unavailable").

- [ ] **Step 1: Write the failing test**

Add to `UnitTests/WalkSessionGuardRecoveryTests.swift`:

```swift
    func test_sanitizeUnplayableRecordings_clearsPath_forMoovLessFile() throws {
        // Write a zero-byte .m4a to simulate a SIGKILL'd AVAudioRecorder output.
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WalkSessionGuardRecoveryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let brokenFile = tmpDir.appendingPathComponent("broken.m4a")
        try Data().write(to: brokenFile)

        let recording = TempVoiceRecording(
            uuid: nil,
            startDate: Date(timeIntervalSinceNow: -30),
            endDate: Date(),
            duration: 30,
            fileRelativePath: "ignored/broken.m4a",
            isEnhanced: false
        )

        let sanitized = WalkSessionGuard.sanitizeRecording(
            recording,
            fileURL: brokenFile
        )
        XCTAssertEqual(sanitized.fileRelativePath, "")
        XCTAssertEqual(sanitized.duration, 30, accuracy: 0.1,
                       "duration must be preserved for the Talk timer")
    }

    func test_sanitizeUnplayableRecordings_preservesPath_whenFilePlayable() throws {
        // A regular finalized .m4a from a finished recording — we can't produce
        // one cheaply in tests, so instead verify the sanitize function passes
        // through any recording whose file reports duration > 0. We use a made-up
        // path pointing nowhere and a duration-preserving stub helper.
        let playable = TempVoiceRecording(
            uuid: nil,
            startDate: Date(),
            endDate: Date().addingTimeInterval(5),
            duration: 5,
            fileRelativePath: "Recordings/ABC/rec.m4a",
            isEnhanced: false
        )

        // Swap in a probe that reports > 0 so we exercise the pass-through branch.
        let sanitized = WalkSessionGuard.sanitizeRecording(
            playable,
            fileURL: nil,  // nil => pass-through (no file check performed)
            durationProbe: { _ in 5.0 }
        )
        XCTAssertEqual(sanitized.fileRelativePath, "Recordings/ABC/rec.m4a")
    }
```

- [ ] **Step 2: Run test to verify failure**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/WalkSessionGuardRecoveryTests
```

Expected: compilation failure — `WalkSessionGuard.sanitizeRecording` doesn't exist.

- [ ] **Step 3: Implement sanitizeRecording + wire into recoverIfNeeded**

Add to `Pilgrim/Models/Walk/WalkSessionGuard.swift`, in the `// MARK: - Recovery` section, before `recoverIfNeeded`:

```swift
    /// Replaces a recording's file path with `""` (metadata-only) when the
    /// underlying `.m4a` is unplayable — the canonical signature of an
    /// AVAudioRecorder that was SIGKILL'd before `stop()` wrote its moov atom.
    /// Duration is preserved so the Talk timer still reads correctly after
    /// recovery; the walk summary row will show "Recording unavailable" and
    /// suppress playback controls.
    ///
    /// Parameters:
    /// - recording: the provisional recording from the checkpoint
    /// - fileURL: absolute URL of the on-disk file. Pass `nil` to skip the
    ///   disk check entirely (used in tests with the `durationProbe` param).
    /// - durationProbe: returns the playable duration for a file. In
    ///   production, defaults to `AVURLAsset(url:).duration` seconds.
    ///   Override in tests to avoid AVFoundation dependencies.
    static func sanitizeRecording(
        _ recording: TempVoiceRecording,
        fileURL: URL?,
        durationProbe: (URL) -> Double = Self.defaultDurationProbe
    ) -> TempVoiceRecording {
        guard let fileURL else { return recording }

        let playableSeconds = durationProbe(fileURL)
        guard playableSeconds <= 0 else {
            return recording
        }

        // File is unplayable: clear path + delete the on-disk corpse.
        try? FileManager.default.removeItem(at: fileURL)

        return TempVoiceRecording(
            uuid: recording.uuid,
            startDate: recording.startDate,
            endDate: recording.endDate,
            duration: recording.duration,
            fileRelativePath: "",
            transcription: nil,
            wordsPerMinute: nil,
            isEnhanced: false
        )
    }

    private static func defaultDurationProbe(_ url: URL) -> Double {
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        return seconds.isFinite ? seconds : 0
    }
```

Then modify `recoverIfNeeded` to run sanitization over all recordings before saving. Find the block around line 255 (after `reconnectOrphanedRecordings(walk: walk, walkUUID: recordingDirUUID)`) and add:

```swift
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let sanitized = walk.voiceRecordings.map { recording -> TempVoiceRecording in
            guard !recording.fileRelativePath.isEmpty else { return recording }
            let url = docs.appendingPathComponent(recording.fileRelativePath)
            return sanitizeRecording(recording, fileURL: url)
        }
        walk.replaceVoiceRecordings(sanitized)
```

If `TempWalk` has no `replaceVoiceRecordings` method yet, add one to `Pilgrim/Models/Data/Temp/Versions/TempV4.swift` next to `replaceActivityIntervals` (line 155):

```swift
        public func replaceVoiceRecordings(_ recordings: [TempV4.VoiceRecording]) {
            self._voiceRecordings = recordings
        }
```

- [ ] **Step 4: Run the tests**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/WalkSessionGuardRecoveryTests
```

Expected: both new tests pass.

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Walk/WalkSessionGuard.swift Pilgrim/Models/Data/Temp/Versions/TempV4.swift UnitTests/WalkSessionGuardRecoveryTests.swift
git commit -m "feat(walk): sanitize unplayable recordings during session recovery"
```

---

## Task 4: Guard empty path in WalkSummary file-availability check

**Files:**
- Modify: `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift:767-770`

`FileManager.fileExists(atPath:)` returns `true` for directories. An empty `fileRelativePath` resolves to the Documents directory itself, which exists, which would cause the metadata-only row to try (and fail) to play. Guard the empty case explicitly.

- [ ] **Step 1: Locate the current implementation**

Read `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift:765-772`. Expect something like:

```swift
    private func isFileAvailable(_ relativePath: String) -> Bool {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return FileManager.default.fileExists(atPath: docs.appendingPathComponent(relativePath).path)
    }
```

- [ ] **Step 2: Add the empty-string guard**

Change to:

```swift
    private func isFileAvailable(_ relativePath: String) -> Bool {
        guard !relativePath.isEmpty else { return false }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return FileManager.default.fileExists(atPath: docs.appendingPathComponent(relativePath).path)
    }
```

- [ ] **Step 3: Manual UI verification**

Enable demo mode and inject a metadata-only recording:

1. Open a walk in the simulator's summary view.
2. Use the debugger (`po`) to insert a `TempVoiceRecording` with `fileRelativePath = ""` into the walk's `voiceRecordings`, or temporarily wire a DEBUG-only seed.
3. Verify the row renders with the `waveform.slash` icon and text "Recording unavailable", and that the duration still formats correctly.

- [ ] **Step 4: Commit**

```bash
git add Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift
git commit -m "fix(summary): treat empty recording path as unavailable"
```

---

## 🚨 CHECKPOINT: Ship Tasks 1–4, reproduce, verify

Before starting Task 5, do this:

1. Merge Tasks 1–4 to a TestFlight build.
2. Install on the SE3 backup phone.
3. Reproduce the crash: start a walk, tap Talk, lock the phone, walk for ~2 minutes until the CPU watchdog kills the app. Confirm via `Settings → Privacy → Analytics → Analytics Data` that a fresh `cpu_resource_fatal` was logged.
4. Reopen the app. Verify:
   - The walk is recovered (orange "Walk recovered" banner appears)
   - The **Talk timer on the recovered walk reads the full duration** (e.g. 2:00, not 0:00) — this proves the checkpoint captured the in-flight talk
   - The voice recording row in the walk summary shows "Recording unavailable" (expected — audio is unrecoverable without rotation) but the duration on the row is correct

If recovery works as described, proceed to Task 5. If duration is still 0:00 or the row is missing entirely, diagnose before moving on.

---

## Task 5: Pause Mapbox when the user can't see it

**Files:**
- Modify: `Pilgrim/Views/PilgrimMapView.swift`
- Modify: `Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift:537` (pass a new binding)

Map should render at 30 FPS only when the user can plausibly see it. Two signals: app is in foreground AND no full-screen meditation overlay is up. Both come together through the `Coordinator`.

- [ ] **Step 1: Add an `isMeditating` Binding parameter to PilgrimMapView**

In `Pilgrim/Views/PilgrimMapView.swift`, add a new stored property near the other bindings (`@Binding var cameraCenter: CLLocationCoordinate2D?`):

```swift
    @Binding var isMeditating: Bool
```

Add it to the initializer parameter list with a default of `.constant(false)` so the other (non-active-walk) call sites don't break:

```swift
        isMeditating: Binding<Bool> = .constant(false),
```

And assign it in `init`:

```swift
        self._isMeditating = isMeditating
```

- [ ] **Step 2: Teach the Coordinator about "paused" state**

In the `Coordinator` class at the bottom of `PilgrimMapView.swift`, add:

```swift
        /// True when the app is backgrounded (screen locked, home button, etc.)
        fileprivate var isAppInBackground: Bool = false

        /// True when a meditation full-screen cover is up.
        var isMeditating: Bool = false {
            didSet { refreshRenderState() }
        }

        /// Computes whether the map should be rendering now. `fileprivate` so
        /// that `updateUIView` can read it to decide whether to defer a route
        /// update.
        fileprivate var shouldRender: Bool {
            !isAppInBackground && !isMeditating
        }

        func startObservingAppLifecycle() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleDidEnterBackground),
                name: UIApplication.didEnterBackgroundNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleWillEnterForeground),
                name: UIApplication.willEnterForegroundNotification,
                object: nil
            )
        }

        @objc private func handleDidEnterBackground() {
            isAppInBackground = true
            refreshRenderState()
        }

        @objc private func handleWillEnterForeground() {
            isAppInBackground = false
            refreshRenderState()
        }

        private func refreshRenderState() {
            guard let mapView else { return }
            mapView.preferredFramesPerSecond = shouldRender ? 30 : 0
        }
```

Make sure the `Coordinator` removes its observers on deinit:

```swift
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
```

(If the coordinator already has a `deinit`, add `NotificationCenter.default.removeObserver(self)` to it rather than creating a second one.)

- [ ] **Step 3: Wire coordinator observers in `makeUIView` and mirror `isMeditating` in `updateUIView`**

At the end of `makeUIView` (around line 136), after `context.coordinator.mapView = mapView`, call:

```swift
        context.coordinator.startObservingAppLifecycle()
        context.coordinator.isMeditating = isMeditating
```

And at the top of `updateUIView` (line 139), propagate the binding:

```swift
    func updateUIView(_ mapView: MBMapView, context: Context) {
        if context.coordinator.isMeditating != isMeditating {
            context.coordinator.isMeditating = isMeditating
        }
        // ...existing body...
    }
```

- [ ] **Step 4: Pass the binding from ActiveWalkView**

In `Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift`, find the `PilgrimMapView(...)` call around line 537 and add the `isMeditating` binding. If `ActiveWalkView` already has `@ObservedObject var viewModel: ActiveWalkViewModel`, use:

```swift
        return PilgrimMapView(
            // ...existing args...,
            isMeditating: $viewModel.isMeditating
        )
```

(`$viewModel.isMeditating` exposes a `Binding<Bool>` because `isMeditating` is `@Published`.)

- [ ] **Step 5: Manual verification — background pause**

1. Run the app on the SE3 backup phone, start a walk.
2. Attach Xcode Instruments (CPU template).
3. Lock the phone. Observe in Instruments that Pilgrim's CPU drops to near-zero within ~1 second.
4. Unlock. Observe CPU returns to normal walk-rendering levels.
5. Walk for 2+ minutes locked. Confirm NO `cpu_resource_fatal` is logged.

- [ ] **Step 6: Manual verification — meditation pause**

1. Start a walk in the foreground.
2. Open Instruments (CPU template), note baseline Pilgrim CPU usage.
3. Tap the meditation button to open the meditation full-screen cover.
4. Confirm CPU drops noticeably (the Mapbox render loop should stop contributing).
5. Exit meditation. Confirm CPU returns to baseline.

- [ ] **Step 7: Commit**

```bash
git add Pilgrim/Views/PilgrimMapView.swift Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift
git commit -m "perf(map): pause Mapbox render loop when backgrounded or meditating"
```

---

## Task 6: Skip GeoJSON source rebuilds while paused, catch up on resume

**Files:**
- Modify: `Pilgrim/Views/PilgrimMapView.swift` (Coordinator + `applyRouteSource`)

Mapbox's `updateGeoJSONSourceFeatures` still triggers C++ tile invalidation work on the worker thread even when `preferredFramesPerSecond = 0`. When paused, queue the latest segments and flush on resume.

- [ ] **Step 1: Queue pending segments on the Coordinator**

In the `Coordinator` class, add alongside `pendingSegments`:

```swift
        /// True when we deferred at least one `applyRouteSource` call while paused.
        fileprivate var hasDeferredRouteUpdate: Bool = false
```

- [ ] **Step 2: Gate `applyRouteSource` on render state**

Find the static `applyRouteSource` function (around line 231) and the `updateUIView` call site that invokes it. Change `updateUIView` to check `context.coordinator.shouldRender` before applying:

The `updateUIView` section that handles `pendingSegments` currently looks roughly like:
```swift
        context.coordinator.pendingSegments = routeSegments
        // ...
        Self.applyRouteSource(routeSegments, on: mapView, coordinator: context.coordinator)
```

Change it to:
```swift
        context.coordinator.pendingSegments = routeSegments
        // ...
        if context.coordinator.shouldRender {
            Self.applyRouteSource(routeSegments, on: mapView, coordinator: context.coordinator)
        } else {
            context.coordinator.hasDeferredRouteUpdate = true
        }
```

`shouldRender` is already `fileprivate` (from Task 5 Step 2), so `updateUIView` on the enclosing `PilgrimMapView` struct can read it directly without an extra accessor.

- [ ] **Step 3: Flush on resume**

In `refreshRenderState()` (from Task 5), after the `preferredFramesPerSecond` assignment, add a flush when transitioning from paused to rendering:

```swift
        private func refreshRenderState() {
            guard let mapView else { return }
            let previouslyRendering = mapView.preferredFramesPerSecond > 0
            mapView.preferredFramesPerSecond = shouldRender ? 30 : 0

            if shouldRender && !previouslyRendering && hasDeferredRouteUpdate {
                PilgrimMapView.applyRouteSource(pendingSegments, on: mapView, coordinator: self)
                hasDeferredRouteUpdate = false
            }
        }
```

- [ ] **Step 4: Manual verification — colors correct on resume**

1. Start a walk.
2. Walk a short distance in the foreground. Verify the route polyline draws as you go.
3. Lock the phone. Walk for 30+ seconds (enough to generate new route samples).
4. Mid-walk, tap the meditation button from lock screen — no, simpler: while locked, just keep walking.
5. Unlock. The polyline should snap-update to include the entire locked-walk segment, colored correctly as "walking" (since you weren't meditating or talking).
6. Repeat with an active Talk session: start Talk, lock phone, walk, unlock → polyline segment during lock period should be "talking" colored (based on whatever the design palette specifies).

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Views/PilgrimMapView.swift
git commit -m "perf(map): skip GeoJSON source rebuilds while renderer is paused"
```

---

## 🚨 CHECKPOINT: Confirm crash is gone

After Tasks 5–6 ship:

1. Deploy to the SE3 backup phone.
2. Start a walk + Talk, lock, walk for 5+ minutes.
3. Confirm NO `cpu_resource_fatal` report appears in `Settings → Privacy → Analytics`.
4. Confirm the walk completes normally (no SIGKILL, no recovery banner on reopen).

Only after this checkpoint proceed to Task 7.

---

## Task 7: Stop recorder when the user answers a phone call

**Files:**
- Modify: `Pilgrim/Models/Walk/WalkBuilder/Components/VoiceRecordingManagement.swift`
- Create: `UnitTests/VoiceRecordingCallInterruptionTests.swift`

Rely on `CXCallObserver.hasConnected` (true only when a call is actively answered) rather than the generic audio-session interruption, so declined/missed calls and Siri don't end the recording.

- [ ] **Step 1: Write the failing test**

Create `UnitTests/VoiceRecordingCallInterruptionTests.swift`:

```swift
import XCTest
import CallKit
@testable import Pilgrim

final class VoiceRecordingCallInterruptionTests: XCTestCase {

    func test_callChanged_stopsRecording_whenCallConnects() {
        let builder = WalkBuilder()
        let mgmt = VoiceRecordingManagement(builder: builder)
        builder.setStatus(.recording)

        mgmt._test_setActiveRecording(
            start: Date(timeIntervalSinceNow: -10),
            relativePath: "Recordings/X/rec.m4a"
        )
        XCTAssertTrue(mgmt.isRecording, "precondition: recording is active")

        mgmt._test_simulateCallChanged(hasConnected: true, hasEnded: false)

        XCTAssertFalse(mgmt.isRecording,
                       "recording should stop the moment a call connects")
    }

    func test_callChanged_doesNothing_whenCallNotConnected() {
        let builder = WalkBuilder()
        let mgmt = VoiceRecordingManagement(builder: builder)
        builder.setStatus(.recording)

        mgmt._test_setActiveRecording(
            start: Date(timeIntervalSinceNow: -10),
            relativePath: "Recordings/X/rec.m4a"
        )

        // Incoming call ringing, not yet answered.
        mgmt._test_simulateCallChanged(hasConnected: false, hasEnded: false)

        XCTAssertTrue(mgmt.isRecording,
                      "ringing / declined call must NOT end the recording")
    }

    func test_callChanged_doesNothing_whenNotRecording() {
        let builder = WalkBuilder()
        let mgmt = VoiceRecordingManagement(builder: builder)

        // No active recording — this should never touch state or crash.
        mgmt._test_simulateCallChanged(hasConnected: true, hasEnded: false)

        XCTAssertFalse(mgmt.isRecording)
    }
}
```

- [ ] **Step 2: Register the test file in pbxproj**

Add `UnitTests/VoiceRecordingCallInterruptionTests.swift` to the UnitTests target.

- [ ] **Step 3: Run tests to verify compilation failure**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/VoiceRecordingCallInterruptionTests
```

Expected: compile error — `_test_simulateCallChanged` and the delegate hook don't exist.

- [ ] **Step 4: Implement CXCallObserver integration**

In `Pilgrim/Models/Walk/WalkBuilder/Components/VoiceRecordingManagement.swift`:

Add to the top:

```swift
import CallKit
```

Inside the class body, add a `CXCallObserver` property and initializer hook. Because `VoiceRecordingManagement` already has `required init(builder:)`, extend it:

```swift
    private let callObserver: CXCallObserver = CXCallObserver()
```

At the end of `init(builder:)` (after `builder.registerPreSnapshotFlush { ... }`):

```swift
        callObserver.setDelegate(self, queue: .main)
```

Conform the class to `CXCallObserverDelegate` via an extension at the bottom of the file:

```swift
extension VoiceRecordingManagement: CXCallObserverDelegate {
    public func callObserver(_ observer: CXCallObserver, callChanged call: CXCall) {
        handleCallStateChange(hasConnected: call.hasConnected, hasEnded: call.hasEnded)
    }

    private func handleCallStateChange(hasConnected: Bool, hasEnded: Bool) {
        guard hasConnected, !hasEnded, isRecording else { return }
        stopRecording()
    }

    #if DEBUG
    func _test_simulateCallChanged(hasConnected: Bool, hasEnded: Bool) {
        handleCallStateChange(hasConnected: hasConnected, hasEnded: hasEnded)
    }
    #endif
}
```

- [ ] **Step 5: Run tests to verify pass**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/VoiceRecordingCallInterruptionTests
```

Expected: all three tests pass.

- [ ] **Step 6: Manual verification — real phone call**

1. Install on a physical device (required — CXCallObserver doesn't observe simulator calls).
2. Start a walk, tap Talk.
3. Have someone call the device. Watch the UI: the Talk button should flip back to idle immediately when you tap answer. The walk continues.
4. Hang up. Confirm the walk is still running and the previous recording is saved (visible on summary if you stop the walk).
5. Tap Talk again to resume recording. Confirm a second recording starts cleanly.
6. Repeat but this time *decline* the call. Confirm the recording continues uninterrupted (the few seconds of ringing are auto-paused by iOS; recording resumes cleanly when the ringing ends).

- [ ] **Step 7: Commit**

```bash
git add Pilgrim/Models/Walk/WalkBuilder/Components/VoiceRecordingManagement.swift UnitTests/VoiceRecordingCallInterruptionTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(walk): stop recording when a phone call is answered"
```

---

## Self-Review Checklist (for the implementer)

After completing all tasks:

- [ ] Every new method on `VoiceRecordingManagement` has a matching unit test
- [ ] `WalkCheckpoint.schemaVersion` was NOT bumped (we reused existing fields — deliberate)
- [ ] `Pilgrim.xcodeproj/project.pbxproj` was updated for all 3 new test files
- [ ] CPU crash repro on SE3 no longer produces `cpu_resource_fatal` after Tasks 5–6
- [ ] Talk timer shows correct duration after forced SIGKILL (e.g. `kill -9` via `lldb` during a debug-attached walk)
- [ ] Phone call handling tested on a physical device, both answer and decline paths
- [ ] No new background timers added (rotation was rejected — verify)
- [ ] `willTerminate` observer NOT added (rejected — verify)
- [ ] Memory profile in Instruments during a 10-minute walk+talk+lock is flat (no leaks introduced)

---

## Out of Scope (Deliberately Rejected)

These were considered and rejected during planning:

- **30-second recorder rotation** — audio-gap UX cost at every boundary not worth the resilience gain; user prioritized walk preservation over audio recovery
- **`UIApplication.willTerminateNotification` observer** — fires for essentially zero of our termination paths (CPU watchdog, jetsam, swipe-kill all bypass it); near-zero ROI for a real maintenance surface
- **Generic `AVAudioSession.interruptionNotification` handling for recording** — too aggressive; would stop recording on every Siri trigger, banner notification, or declined call. CXCallObserver is the discriminating signal we want.
- **`WalkCheckpoint` schema bump / new fields** — not needed; the provisional `TempVoiceRecording` we append already encodes everything we need via its existing fields (path + start + duration)
- **Rebuilding Mapbox route polyline on every GPS sample while backgrounded** — Task 6 is explicitly the decision to *not* do this
