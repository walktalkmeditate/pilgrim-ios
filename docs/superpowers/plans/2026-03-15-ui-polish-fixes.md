# UI Polish Fixes Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three UI fixes: waveform in WalkSummaryView, truncated transcriptions with expand, and confirmation dialog positioning.

**Architecture:** Modify existing VoiceRecordingRow to use WaveformBarView (already defined in RecordingsListView.swift, accessible at file scope). Add lineLimit + tap-to-expand for transcriptions. Move confirmationDialog attachment point.

**Tech Stack:** SwiftUI, WaveformBarView, WaveformCache, WaveformGenerator

---

## Task 1: Add Waveform to VoiceRecordingRow in WalkSummaryView

**Files:**
- Modify: `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift`

VoiceRecordingRow currently uses a `Slider` for seek when active. Replace with `WaveformBarView` that's always visible (showing amplitude when idle, progress fill when playing). `WaveformBarView` is already defined at file scope in `RecordingsListView.swift` and accessible from any file.

- [ ] **Step 1: Add waveform state and loading to WalkSummaryView**

Add `@State` for waveforms after the existing state vars (near line 17):

```swift
@State private var waveforms: [UUID: [Float]] = [:]
```

- [ ] **Step 2: Add waveformSamples parameter to VoiceRecordingRow**

Add after the existing `onDelete` parameter (line 806):

```swift
let waveformSamples: [Float]?
```

- [ ] **Step 3: Replace VoiceRecordingRow body to use waveform**

Replace the current body (lines 808-862). The new structure:
- When `fileAvailable`: show waveform bar at top (always visible), then compact info below. When active, show play/pause button + time labels instead of compact info.
- When unavailable: unchanged (waveform.slash + text).
- Remove the old `playerControls` computed property (Slider-based).

New body:

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 6) {
        if fileAvailable {
            if let samples = waveformSamples {
                WaveformBarView(
                    samples: samples,
                    progress: isActive ? progress : 0,
                    isPlaying: isPlaying
                ) { fraction in
                    if isActive {
                        onSeek(fraction)
                    } else {
                        onTogglePlay()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            onSeek(fraction)
                        }
                    }
                }
                .onTapGesture { onTogglePlay() }
            }

            if isActive {
                HStack {
                    Button(action: onTogglePlay) {
                        Image(systemName: playIcon)
                            .font(.title2)
                            .foregroundColor(.stone)
                    }
                    Text(formatSeconds(currentTime))
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                        .monospacedDigit()
                    Spacer()
                    Text(formatSeconds(audioDuration))
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                        .monospacedDigit()
                }
            } else {
                compactInfo
            }
        } else {
            HStack {
                Image(systemName: "waveform.slash")
                    .font(.title2)
                    .foregroundColor(.fog)
                Text("Recording unavailable")
                    .font(Constants.Typography.body)
                    .foregroundColor(.fog)
                Spacer()
            }
        }

        // transcription section unchanged
    }
    .padding(.vertical, 4)
    .contextMenu { /* unchanged */ }
}
```

Delete the `playerControls` computed property (lines 871-893) — no longer needed.

- [ ] **Step 4: Pass waveformSamples in WalkSummaryView's recordingsSection ForEach**

In the `recordingsSection` ForEach (line 442), add the new parameter:

```swift
waveformSamples: recording.uuid.flatMap { waveforms[$0] },
```

- [ ] **Step 5: Add .task for waveform loading on each row**

After the VoiceRecordingRow closing paren in the ForEach, add a `.task` modifier to load waveforms lazily:

```swift
.task {
    guard let uuid = recording.uuid,
          waveforms[uuid] == nil,
          isFileAvailable(recording.fileRelativePath)
    else { return }
    guard await WaveformCache.shared.markInFlight(uuid) else {
        if let cached = await WaveformCache.shared.samples(for: uuid) {
            waveforms[uuid] = cached
        }
        return
    }
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let url = docs.appendingPathComponent(recording.fileRelativePath)
    if let samples = await Task.detached(priority: .utility, operation: {
        WaveformGenerator.generateSamples(from: url)
    }).value {
        await WaveformCache.shared.store(samples, for: uuid)
        waveforms[uuid] = samples
    }
}
```

- [ ] **Step 6: Build and verify**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build
```

- [ ] **Step 7: Commit**

```bash
git add Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift
git commit -m "feat: replace Slider with waveform visualization in VoiceRecordingRow"
```

## Task 2: Truncate Long Transcriptions with "Show More"

**Files:**
- Modify: `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift` (VoiceRecordingRow)
- Modify: `Pilgrim/Scenes/Settings/RecordingsListView.swift` (recordingRow)

### WalkSummaryView (VoiceRecordingRow)

- [ ] **Step 1: Add expansion state to VoiceRecordingRow**

Add `@State` inside VoiceRecordingRow:

```swift
@State private var isTranscriptionExpanded = false
```

- [ ] **Step 2: Apply lineLimit and tap-to-expand**

In the transcription section of VoiceRecordingRow's body, modify the `Text(transcription)`:

```swift
if let transcription = transcription {
    HStack(alignment: .top) {
        Text(transcription)
            .font(Constants.Typography.body)
            .foregroundColor(.ink)
            .lineLimit(isTranscriptionExpanded ? nil : 3)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.parchmentTertiary)
            .cornerRadius(8)
            .onTapGesture { isTranscriptionExpanded.toggle() }

        if fileAvailable {
            Button(action: onRetranscribe) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .foregroundColor(.fog)
            }
        }
    }
}
```

### RecordingsListView (recordingRow)

- [ ] **Step 3: Add expansion tracking state**

Add to RecordingsListView's state vars:

```swift
@State private var expandedTranscriptions: Set<UUID> = []
```

- [ ] **Step 4: Apply lineLimit and tap-to-expand in recordingRow**

In `recordingRow`, modify the transcription text block (around line 185):

```swift
if let text = transcriptionText, !text.isEmpty {
    let expanded = recUUID.map { expandedTranscriptions.contains($0) } ?? false
    Text(text)
        .font(Constants.Typography.body)
        .foregroundColor(.ink)
        .lineLimit(expanded ? nil : 3)
        .padding(Constants.UI.Padding.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.parchmentTertiary)
        .cornerRadius(Constants.UI.CornerRadius.small)
        .onTapGesture {
            if let uuid = recUUID {
                if expandedTranscriptions.contains(uuid) {
                    expandedTranscriptions.remove(uuid)
                } else {
                    expandedTranscriptions.insert(uuid)
                }
            }
        }
}
```

- [ ] **Step 5: Build and verify**

- [ ] **Step 6: Commit**

```bash
git add Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift Pilgrim/Scenes/Settings/RecordingsListView.swift
git commit -m "feat: truncate long transcriptions to 3 lines with tap to expand"
```

## Task 3: Fix Delete All Confirmation Dialog Positioning

**Files:**
- Modify: `Pilgrim/Scenes/Settings/RecordingsListView.swift`

The `.confirmationDialog` for "Delete All" is attached to the outer `Group` in `body`, which causes it to anchor at the top of the screen. Move it to be attached to the delete button's Section so it anchors near the button.

- [ ] **Step 1: Move delete-all confirmationDialog from body to the delete button**

Remove the `.confirmationDialog` for delete-all from the outer `Group` (lines 57-69).

Attach it to the delete button `Section` inside `recordingsList`:

```swift
Section {
    Button(role: .destructive) {
        showDeleteAllConfirmation = true
    } label: {
        Text("Delete All Recording Files")
            .font(Constants.Typography.body)
    }
    .confirmationDialog(
        "Delete all recording files? Transcriptions will be kept.",
        isPresented: $showDeleteAllConfirmation,
        titleVisibility: .visible
    ) {
        Button("Delete All", role: .destructive) {
            audioPlayer.stop()
            DataManager.deleteAllRecordingFiles()
            deletedPaths.formUnion(
                walkSections.flatMap { $0.recordings.map { $0.fileRelativePath } }
            )
        }
    }
}
```

- [ ] **Step 2: Build and verify**

- [ ] **Step 3: Commit**

```bash
git add Pilgrim/Scenes/Settings/RecordingsListView.swift
git commit -m "fix: move delete-all confirmation dialog to anchor near button"
```
