# Recordings Library Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the TalkSettingsView storage section with a browsable Recordings library featuring waveform visualization, search, per-recording management, and walk-linked sections.

**Architecture:** New RecordingsListView pushed from TalkSettingsView via NavigationLink. Data loaded from CoreStore Walk→VoiceRecording relationships. Waveform extraction via AVAudioFile, cached in a singleton actor. Schema migration PilgrimV5 adds `isEnhanced` to VoiceRecording.

**Tech Stack:** SwiftUI, CoreStore, AVFoundation, Swift Concurrency (actor for cache)

**Spec:** `docs/superpowers/specs/2026-03-15-recordings-library-design.md`

---

## Chunk 1: Schema Migration + Data Layer

### Task 1: PilgrimV5 Migration + isEnhanced Data Layer

**Files:**
- Create: `Pilgrim/Models/Data/DataModels/Versions/PilgrimV5.swift`
- Modify: `Pilgrim/Protocols/DataInterfaces/VoiceRecordingInterface.swift`
- Modify: `Pilgrim/Models/Data/DataModels/VoiceRecording.swift`
- Modify: `Pilgrim/Models/Data/Temp/Versions/TempV4.swift`
- Modify: `Pilgrim/Models/Data/Temp/Temp.swift`
- Modify: `Pilgrim/Models/Data/DataManager.swift`

PilgrimV5 is a copy of PilgrimV4 with one change: VoiceRecording gains `_isEnhanced`. All other entities are identical but must be redefined in the PilgrimV5 namespace (CoreStore requires a complete schema per version).

- [ ] **Step 1: Create PilgrimV5.swift**

Copy `Pilgrim/Models/Data/DataModels/Versions/PilgrimV4.swift` entirely. Then make these changes:

1. Rename enum to `PilgrimV5`, identifier to `"PilgrimV5"`
2. Schema references: change all `PilgrimV4.` to `PilgrimV5.` in Entity declarations, Relationship types, and class definitions
3. Mapping provider: change `from: PilgrimV3.identifier` → `from: PilgrimV4.identifier`, `to: PilgrimV4.identifier` → `to: PilgrimV5.identifier`. Change all source entity references to `PilgrimV4.X.identifier` and destination to `PilgrimV5.X.identifier`
4. **Keep `.transformEntity` with `enumerateAttributes` for ALL entities including VoiceRecording** — do NOT switch any to `.copyEntity`. The `enumerateAttributes` pattern handles the new `isEnhanced` attribute automatically: `sourceAttribute` will be `nil` for it, the branch is skipped, and CoreStore applies the `initial: false` default.
5. Migration chain: append `PilgrimV5.self` at the end
6. Add to VoiceRecording class (after `_wordsPerMinute`):

```swift
let _isEnhanced = Value.Required<Bool>("isEnhanced", initial: false)
```

- [ ] **Step 2: Add PilgrimV5.swift to Xcode project**

Add to the Versions group in pbxproj (PBXFileReference, PBXGroup, PBXSourcesBuildPhase), same pattern as PilgrimV4.swift.

- [ ] **Step 3: Add isEnhanced to VoiceRecordingInterface**

In `VoiceRecordingInterface.swift`, add to the protocol:

```swift
var isEnhanced: Bool { get }
```

And to the default implementation extension:

```swift
var isEnhanced: Bool { throwOnAccess() }
```

- [ ] **Step 4: Update VoiceRecording typealias and extension**

In `VoiceRecording.swift`, change the typealias:

```swift
public typealias VoiceRecording = PilgrimV5.VoiceRecording
```

Add to the `VoiceRecordingInterface` extension:

```swift
public var isEnhanced: Bool { threadSafeSyncReturn { self._isEnhanced.value } }
```

Update `asTemp` (in the `TempValueConvertible` extension) to include `isEnhanced`:

```swift
public var asTemp: TempVoiceRecording {
    TempVoiceRecording(
        uuid: uuid,
        startDate: startDate,
        endDate: endDate,
        duration: duration,
        fileRelativePath: fileRelativePath,
        transcription: transcription,
        wordsPerMinute: wordsPerMinute,
        isEnhanced: isEnhanced
    )
}
```

- [ ] **Step 5: Add isEnhanced to TempV4.VoiceRecording**

In `TempV4.swift`, find the `VoiceRecording` class (~line 189). Add property:

```swift
public var isEnhanced: Bool
```

Update the init to add the parameter (with default `false`):

```swift
public init(uuid: UUID?, startDate: Date, endDate: Date, duration: Double,
            fileRelativePath: String, transcription: String? = nil,
            wordsPerMinute: Double? = nil, isEnhanced: Bool = false) {
    // ... existing assignments ...
    self.isEnhanced = isEnhanced
}
```

Note: `TempV4.VoiceRecording` is `Codable`. Adding a new property with a default value is backward-compatible — `Codable` synthesis will use `false` if the key is missing in existing encoded data.

- [ ] **Step 6: Update Temp.swift conformance**

In `Temp.swift`, find the `TempVoiceRecording: VoiceRecordingInterface` extension (~line 157). Update the convenience init:

```swift
convenience init(from object: VoiceRecordingInterface) {
    self.init(
        uuid: object.uuid,
        startDate: object.startDate,
        endDate: object.endDate,
        duration: object.duration,
        fileRelativePath: object.fileRelativePath,
        transcription: object.transcription,
        wordsPerMinute: object.wordsPerMinute,
        isEnhanced: object.isEnhanced
    )
}
```

- [ ] **Step 7: Update DataManager persistence and setup**

In `DataManager.swift`:

1. Find `persistRelatedEntities` (~line 286). Add after `recording._wordsPerMinute .= tempRecording.wordsPerMinute`:

```swift
recording._isEnhanced .= tempRecording.isEnhanced
```

2. Find `updateWalk` voice recording block (~line 403). Add the same line after `recording._wordsPerMinute .= tempRecording.wordsPerMinute`:

```swift
recording._isEnhanced .= tempRecording.isEnhanced
```

3. Find the `setup` method signature (~line 55). Change default parameter:

```swift
public static func setup(dataModel: DataModelProtocol.Type = PilgrimV5.self, ...
```

- [ ] **Step 8: Build**

```bash
xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build
```

Expected: BUILD SUCCEEDED

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: PilgrimV5 migration with isEnhanced on VoiceRecording, wired through data layer"
```

### Task 2: VoiceRecordingManagement Enhancement Tracking

**Files:**
- Modify: `Pilgrim/Models/Walk/WalkBuilder/Components/VoiceRecordingManagement.swift`

- [ ] **Step 1: Update finalizeRecording and commitRecording**

In `VoiceRecordingManagement.swift`, update `finalizeRecording` to accept `isEnhanced`:

```swift
private func finalizeRecording(start: Date, end: Date, relativePath: String, isEnhanced: Bool = false) {
    let recording = TempVoiceRecording(
        uuid: UUID(),
        startDate: start,
        endDate: end,
        duration: end.timeIntervalSince(start),
        fileRelativePath: relativePath,
        isEnhanced: isEnhanced
    )
    voiceRecordingsRelay.accept(voiceRecordingsRelay.value + [recording])
}
```

Update `commitRecording` — replace the block after `let end = Date()`:

```swift
let end = Date()
let enhanced = !skipEnhancement && UserPreferences.dynamicVoiceEnabled.value
finalizeRecording(start: start, end: end, relativePath: relativePath, isEnhanced: enhanced)

if enhanced {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let fileURL = docs.appendingPathComponent(relativePath)
    VoiceEnhancer.shared.enhance(fileURL) { _ in }
}
```

- [ ] **Step 2: Build**

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Pilgrim/Models/Walk/WalkBuilder/Components/VoiceRecordingManagement.swift
git commit -m "feat: track isEnhanced in voice recording pipeline"
```

## Chunk 2: Waveform Infrastructure

### Task 3: WaveformGenerator

**Files:**
- Create: `Pilgrim/Models/Audio/WaveformGenerator.swift`

- [ ] **Step 1: Create WaveformGenerator**

```swift
import AVFoundation

struct WaveformGenerator {

    static func generateSamples(from url: URL, count: Int = 150) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return nil }

        do {
            try file.read(into: buffer)
        } catch {
            return nil
        }

        guard let channelData = buffer.floatChannelData?[0] else { return nil }
        let totalFrames = Int(buffer.frameLength)
        let samplesPerBin = max(1, totalFrames / count)
        var samples: [Float] = []
        samples.reserveCapacity(count)

        for bin in 0..<count {
            let start = bin * samplesPerBin
            let end = min(start + samplesPerBin, totalFrames)
            guard start < totalFrames else {
                samples.append(0)
                continue
            }
            var maxAmp: Float = 0
            for i in start..<end {
                maxAmp = max(maxAmp, abs(channelData[i]))
            }
            samples.append(maxAmp)
        }

        let peak = samples.max() ?? 1
        if peak > 0 {
            samples = samples.map { $0 / peak }
        }
        return samples
    }
}
```

- [ ] **Step 2: Add to Xcode project and build**

Add to the Audio group in pbxproj, same pattern as VoiceEnhancer.swift. Build to verify.

- [ ] **Step 3: Commit**

```bash
git add Pilgrim/Models/Audio/WaveformGenerator.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat: add WaveformGenerator for audio amplitude extraction"
```

### Task 4: WaveformCache

**Files:**
- Create: `Pilgrim/Models/Audio/WaveformCache.swift`

- [ ] **Step 1: Create WaveformCache actor**

```swift
import Foundation

actor WaveformCache {

    static let shared = WaveformCache()

    private var cache: [UUID: [Float]] = [:]
    private var inFlight: Set<UUID> = []

    func samples(for id: UUID) -> [Float]? {
        cache[id]
    }

    func store(_ samples: [Float], for id: UUID) {
        cache[id] = samples
        inFlight.remove(id)
    }

    func markInFlight(_ id: UUID) -> Bool {
        guard !inFlight.contains(id), cache[id] == nil else { return false }
        inFlight.insert(id)
        return true
    }
}
```

- [ ] **Step 2: Add to Xcode project and build**

Add to the Audio group in pbxproj. Build to verify.

- [ ] **Step 3: Commit**

```bash
git add Pilgrim/Models/Audio/WaveformCache.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat: add WaveformCache actor for in-memory waveform storage"
```

## Chunk 3: RecordingsListView

### Task 5: RecordingsListView

**Files:**
- Create: `Pilgrim/Scenes/Settings/RecordingsListView.swift`

This is the main new screen. `AudioPlayerModel` is already defined at file scope in `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift` (line 939) and is accessible from any file — no need to create a new class.

- [ ] **Step 1: Create RecordingsListView with data model and state**

Define the local data model and all state properties:

```swift
import SwiftUI
import CoreStore

struct RecordingsListView: View {

    private struct WalkSection: Identifiable {
        let walk: Walk
        let recordings: [VoiceRecordingInterface]
        var id: UUID? { walk.uuid }
    }

    @StateObject private var audioPlayer = AudioPlayerModel()
    @ObservedObject private var transcriptionService = TranscriptionService.shared
    @State private var walkSections: [WalkSection] = []
    @State private var deletedPaths: Set<String> = []
    @State private var transcriptionOverrides: [UUID: String] = [:]
    @State private var waveforms: [UUID: [Float]] = [:]
    @State private var fileSizes: [UUID: Int] = [:]
    @State private var searchText = ""
    @State private var selectedWalk: Walk?
    @State private var showDeleteAllConfirmation = false
    @State private var pathToDelete: String?
    @State private var showDeleteConfirmation = false
    // ...
}
```

Data loading (follows `computeRecentWalkSnippets` pattern in WalkSummaryView):

```swift
private func loadWalks() {
    guard let walks = try? DataManager.dataStack.fetchAll(
        From<Walk>()
            .orderBy(.descending(\._startDate))
    ) else { return }
    walkSections = walks
        .filter { !$0.voiceRecordings.isEmpty }
        .map { walk in
            WalkSection(
                walk: walk,
                recordings: walk.voiceRecordings.sorted { $0.startDate < $1.startDate }
            )
        }
}
```

Search filtering computed property:

```swift
private var filteredSections: [WalkSection] {
    guard !searchText.isEmpty else { return walkSections }
    return walkSections.compactMap { section in
        let matching = section.recordings.filter { recording in
            guard let uuid = recording.uuid,
                  let text = transcriptionOverrides[uuid] ?? recording.transcription
            else { return false }
            return text.localizedCaseInsensitiveContains(searchText)
        }
        guard !matching.isEmpty else { return nil }
        return WalkSection(walk: section.walk, recordings: matching)
    }
}
```

- [ ] **Step 2: Implement body structure**

```swift
var body: some View {
    List {
        if filteredSections.isEmpty {
            if walkSections.isEmpty {
                emptyState
            } else {
                noMatchState
            }
        } else {
            ForEach(filteredSections) { section in
                Section {
                    ForEach(Array(section.recordings.enumerated()), id: \.element.uuid) { index, recording in
                        recordingRow(index: index + 1, recording: recording)
                            .swipeActions(edge: .trailing) { deleteSwipeAction(recording) }
                            .swipeActions(edge: .leading) { retranscribeSwipeAction(recording) }
                    }
                } header: {
                    sectionHeader(section)
                }
            }
            deleteAllButton
        }
    }
    .searchable(text: $searchText, prompt: "Search transcriptions")
    .scrollContentBackground(.hidden)
    .background(Color.parchment)
    .navigationTitle("Recordings")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
        ToolbarItem(placement: .principal) {
            Text("Recordings")
                .font(Constants.Typography.heading)
                .foregroundColor(.ink)
        }
    }
    .onAppear { loadWalks() }
    .sheet(item: $selectedWalk) { walk in
        NavigationView { WalkSummaryView(walk: walk) }
    }
    .confirmationDialog(
        "Delete this recording file? The transcription will be kept.",
        isPresented: $showDeleteConfirmation,
        titleVisibility: .visible
    ) {
        Button("Delete Recording", role: .destructive) {
            guard let path = pathToDelete else { return }
            if audioPlayer.currentPath == path { audioPlayer.stop() }
            DataManager.deleteRecordingFile(relativePath: path)
            deletedPaths.insert(path)
        }
    }
    .confirmationDialog(
        "Delete all recording files? Transcriptions will be kept.",
        isPresented: $showDeleteAllConfirmation,
        titleVisibility: .visible
    ) {
        Button("Delete All", role: .destructive) {
            audioPlayer.stop()
            for section in walkSections {
                for recording in section.recordings {
                    deletedPaths.insert(recording.fileRelativePath)
                }
            }
            DataManager.deleteAllRecordingFiles()
        }
    }
}
```

- [ ] **Step 3: Implement WaveformBarView**

Custom view rendering amplitude samples as vertical bars with playback progress overlay and seek gesture:

```swift
struct WaveformBarView: View {
    let samples: [Float]
    var progress: Double = 0
    var isPlaying: Bool = false
    var onSeek: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geo in
            let barWidth = max(1, geo.size.width / CGFloat(samples.count) - 0.5)
            ZStack(alignment: .leading) {
                HStack(alignment: .center, spacing: 0.5) {
                    ForEach(Array(samples.enumerated()), id: \.offset) { _, amp in
                        RoundedRectangle(cornerRadius: barWidth / 2)
                            .fill(Color.fog.opacity(0.4))
                            .frame(width: barWidth, height: max(2, geo.size.height * CGFloat(amp)))
                    }
                }

                HStack(alignment: .center, spacing: 0.5) {
                    ForEach(Array(samples.enumerated()), id: \.offset) { _, amp in
                        RoundedRectangle(cornerRadius: barWidth / 2)
                            .fill(Color.stone)
                            .frame(width: barWidth, height: max(2, geo.size.height * CGFloat(amp)))
                    }
                }
                .mask(alignment: .leading) {
                    Rectangle()
                        .frame(width: geo.size.width * CGFloat(progress))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = max(0, min(1, Double(value.location.x / geo.size.width)))
                        onSeek?(fraction)
                    }
            )
        }
        .frame(height: 32)
    }
}
```

- [ ] **Step 4: Implement recording row**

```swift
private func recordingRow(index: Int, recording: VoiceRecordingInterface) -> some View {
    let fileAvailable = isFileAvailable(recording.fileRelativePath)
    let isActive = audioPlayer.currentPath == recording.fileRelativePath && fileAvailable
    let uuid = recording.uuid

    return VStack(alignment: .leading, spacing: 6) {
        if fileAvailable {
            if let samples = uuid.flatMap({ waveforms[$0] }) {
                WaveformBarView(
                    samples: samples,
                    progress: isActive ? audioPlayer.progress : 0,
                    isPlaying: isActive && audioPlayer.isPlaying,
                    onSeek: isActive ? { audioPlayer.seek(to: $0) } : nil
                )
                .onTapGesture {
                    audioPlayer.toggle(relativePath: recording.fileRelativePath)
                }
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.fog.opacity(0.2))
                    .frame(height: 32)
            }

            HStack {
                Text("Recording \(index)")
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)

                Text(formatDuration(recording.duration))
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)

                if let size = uuid.flatMap({ fileSizes[$0] }) {
                    Text(formatFileSize(size))
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }

                if recording.isEnhanced {
                    Text("Enhanced")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.stone)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.stone.opacity(0.15))
                        .cornerRadius(4)
                }

                Spacer()

                if isActive {
                    Button { audioPlayer.toggle(relativePath: recording.fileRelativePath) } label: {
                        Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                            .foregroundColor(.stone)
                    }
                }
            }

            if isActive {
                HStack {
                    Text(formatSeconds(audioPlayer.currentTime))
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                        .monospacedDigit()
                    Spacer()
                    Text(formatSeconds(audioPlayer.totalDuration))
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                        .monospacedDigit()
                }
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

        if let text = uuid.flatMap({ transcriptionOverrides[$0] }) ?? recording.transcription {
            Text(text)
                .font(Constants.Typography.body)
                .foregroundColor(.ink)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.parchmentTertiary)
                .cornerRadius(8)
        }
    }
    .padding(.vertical, 4)
    .task {
        guard let uuid, fileAvailable else { return }
        guard await WaveformCache.shared.markInFlight(uuid) else {
            if let cached = await WaveformCache.shared.samples(for: uuid) {
                waveforms[uuid] = cached
            }
            return
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent(recording.fileRelativePath)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if let samples = WaveformGenerator.generateSamples(from: url) {
            await WaveformCache.shared.store(samples, for: uuid)
            waveforms[uuid] = samples
        }
        fileSizes[uuid] = fileSize
    }
}
```

- [ ] **Step 5: Implement section headers with walk link**

```swift
private static let sectionDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMMM d, h:mm a"
    return f
}()

private func sectionHeader(_ section: WalkSection) -> some View {
    let totalDuration = section.recordings.reduce(0.0) { $0 + $1.duration }
    return Button {
        selectedWalk = section.walk
    } label: {
        Text("\(Self.sectionDateFormatter.string(from: section.walk.startDate)) — \(formatDuration(totalDuration)) of recordings")
            .font(Constants.Typography.caption)
            .foregroundColor(.fog)
    }
}
```

- [ ] **Step 6: Implement swipe actions**

```swift
@ViewBuilder
private func deleteSwipeAction(_ recording: VoiceRecordingInterface) -> some View {
    if isFileAvailable(recording.fileRelativePath) {
        Button(role: .destructive) {
            pathToDelete = recording.fileRelativePath
            showDeleteConfirmation = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

@ViewBuilder
private func retranscribeSwipeAction(_ recording: VoiceRecordingInterface) -> some View {
    if isFileAvailable(recording.fileRelativePath) {
        Button {
            Task {
                if let text = await transcriptionService.transcribeSingle(recording),
                   let uuid = recording.uuid {
                    transcriptionOverrides[uuid] = text
                }
            }
        } label: {
            Label("Retranscribe", systemImage: "arrow.clockwise")
        }
        .tint(.stone)
    }
}
```

- [ ] **Step 7: Implement empty states, delete all button, and helpers**

```swift
private var emptyState: some View {
    VStack(spacing: Constants.UI.Padding.normal) {
        Image(systemName: "waveform")
            .font(.largeTitle)
            .foregroundColor(.fog)
        Text("Your voice recordings will appear here")
            .font(Constants.Typography.caption)
            .foregroundColor(.fog)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Constants.UI.Padding.breathingRoom)
    .listRowBackground(Color.clear)
}

private var noMatchState: some View {
    Text("No recordings match")
        .font(Constants.Typography.body)
        .foregroundColor(.fog)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Constants.UI.Padding.big)
        .listRowBackground(Color.clear)
}

private var deleteAllButton: some View {
    Button(role: .destructive) {
        showDeleteAllConfirmation = true
    } label: {
        Text("Delete All Recording Files")
            .font(Constants.Typography.body)
    }
}

private func isFileAvailable(_ relativePath: String) -> Bool {
    guard !deletedPaths.contains(relativePath) else { return false }
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    return FileManager.default.fileExists(atPath: docs.appendingPathComponent(relativePath).path)
}

private func formatDuration(_ seconds: Double) -> String {
    let total = Int(seconds)
    let m = total / 60
    let s = total % 60
    return String(format: "%d:%02d", m, s)
}

private func formatSeconds(_ seconds: TimeInterval) -> String {
    let total = Int(max(0, seconds))
    let m = total / 60
    let s = total % 60
    return String(format: "%d:%02d", m, s)
}

private func formatFileSize(_ bytes: Int) -> String {
    String(format: "%.1f MB", Double(bytes) / 1_000_000.0)
}
```

- [ ] **Step 8: Add RecordingsListView to Xcode project and build**

Add to the Settings scene group in pbxproj. Build to verify.

Expected: BUILD SUCCEEDED

- [ ] **Step 9: Commit**

```bash
git add Pilgrim/Scenes/Settings/RecordingsListView.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat: add RecordingsListView with waveform, search, playback, and management"
```

## Chunk 4: TalkSettingsView + Cleanup

### Task 6: Simplify TalkSettingsView

**Files:**
- Modify: `Pilgrim/Scenes/Settings/TalkSettingsView.swift`

- [ ] **Step 1: Replace storage section with recordings NavigationLink**

State vars to **remove**: `modelSizeMB`, `isModelDownloaded`, `showDeleteRecordingsConfirmation`.
State vars to **keep**: `recordingCount`, `recordingSizeMB` (these power the NavigationLink detail label).
Remove: `@ObservedObject private var transcriptionService` — no longer needed for storage section (keep if needed for download progress in transcription section — check if `transcriptionSection` still references it. Yes it does — keep it).

Remove the entire `storageSection` computed property. Replace with `recordingsSection`:

```swift
private var recordingsSection: some View {
    Section {
        NavigationLink {
            RecordingsListView()
        } label: {
            HStack {
                Text("Recordings")
                    .font(Constants.Typography.body)
                Spacer()
                Text("\(recordingCount) recording\(recordingCount == 1 ? "" : "s") \u{2022} \(String(format: "%.1f MB", recordingSizeMB))")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
        }
    } header: {
        Text("Recordings")
            .font(Constants.Typography.caption)
    }
}
```

Update `body` to use `recordingsSection` instead of `storageSection`.

Simplify `refreshStats` to only compute recordings (remove model stats):

```swift
private func refreshStats() {
    recordingCount = DataManager.recordingFileCount()
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let recordingsDir = docs.appendingPathComponent("Recordings")
    recordingSizeMB = Double(FileManager.default.sizeOfDirectory(at: recordingsDir) ?? 0) / 1_000_000.0
}
```

In the auto-transcribe toggle `onChange`, remove `refreshStats()` from the download success path (no longer relevant). Keep the `autoTranscribe = false` in catch.

- [ ] **Step 2: Build**

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Pilgrim/Scenes/Settings/TalkSettingsView.swift
git commit -m "feat: simplify TalkSettingsView with recordings NavigationLink"
```

### Task 7: TranscriptionService Cleanup

**Files:**
- Modify: `Pilgrim/Models/TranscriptionService.swift`

- [ ] **Step 1: Remove deleteModel and modelDiskSize**

Remove the `deleteModel()` method and `modelDiskSize` computed property. Keep `isModelDownloaded`, `savedModelPath`, `ensureModelReady()`, and `unloadModel()`.

- [ ] **Step 2: Build**

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Pilgrim/Models/TranscriptionService.swift
git commit -m "refactor: remove unused deleteModel and modelDiskSize from TranscriptionService"
```

### Task 8: Localizable.strings

**Files:**
- Modify: `Pilgrim/Support Files/Base.lproj/Localizable.strings`

- [ ] **Step 1: Add recording library strings**

Add under the existing "Talks & Recordings" comment:

```
"Recordings.Empty" = "Your voice recordings will appear here";
"Recordings.NoMatch" = "No recordings match";
"Recordings.DeleteAll" = "Delete All Recording Files";
"Recordings.DeleteAll.Confirm" = "Delete all recording files? Transcriptions will be kept.";
"Recordings.Enhanced" = "Enhanced";
"Recordings.Unavailable" = "Recording unavailable";
"Recordings.Retranscribe" = "Retranscribe";
```

- [ ] **Step 2: Commit**

```bash
git add Pilgrim/Support\ Files/Base.lproj/Localizable.strings
git commit -m "feat: add recordings library localization strings"
```

### Task 9: Final Build Verification

- [ ] **Step 1: Full build**

```bash
xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build
```

Expected: BUILD SUCCEEDED

- [ ] **Step 2: Run on simulator — manual verification**

1. Settings → Talks → simplified view with Recordings NavigationLink showing count + size
2. Tap Recordings → grouped by walk, newest first
3. Waveform bars render for each recording
4. Tap waveform → playback starts, progress fills across bars
5. Drag on waveform → seeks to position
6. Swipe left → delete with confirmation → row shows unavailable, transcription remains
7. Swipe right → retranscribe → transcription text updates
8. Search bar → filters recordings by transcription text → "No recordings match" for no results
9. Tap section header → walk summary opens as sheet
10. Enhanced badge visible on recordings made with Dynamic Voice
11. Scroll to bottom → Delete All with confirmation
12. Empty state when no recordings exist (waveform icon + message)
