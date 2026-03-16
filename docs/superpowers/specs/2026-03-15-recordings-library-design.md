# Recordings Library Design

## Context

The TalkSettingsView storage section currently shows a static "N recording(s) / X.X MB" row with a nuclear "Delete All" button. Users cannot browse, play, or manage individual recordings from settings. The transcription model management UI (delete model, show size) adds complexity for a ~40MB asset that isn't worth managing.

This design replaces the storage section with a dedicated Recordings screen — a browsable library with playback, per-recording deletion, search, and waveform visualization.

## Design

### TalkSettingsView Changes

The Storage section is replaced with a Recordings section containing a single NavigationLink. Model management UI (size display, delete button, "Not downloaded" state) is removed entirely — the ~40MB WhisperKit model is too small to warrant user-facing management.

```
Section "Enhancement"
└─ Toggle: Dynamic Voice

Section "Transcription"
└─ Toggle: Auto-transcribe
   (download progress bar when downloading)

Section "Recordings"
└─ NavigationLink → RecordingsListView
   Label: "Recordings"
   Detail: "3 recordings • 1.2 MB"
```

### RecordingsListView Structure

```
NavigationStack "Recordings"
├─ Search bar (filters by transcription text)
├─ Sections grouped by walk (reverse-chronological)
│   Header: "March 12, 9:15 AM — 4:32 of recordings"
│   │        ↑ tappable, opens walk summary as sheet
│   ├─ RecordingRow
│   ├─ RecordingRow ...
│   └─ ...
├─ More walk sections ...
├─ "Delete All Recording Files" button (destructive, confirmation dialog)
└─ Empty state: waveform icon + "Your voice recordings will appear here"
```

Sections are reverse-chronological (newest walk first). Recordings within a walk are chronological (first recording at top). Same-day walks are differentiated by start time in the section header.

### Recording Row States

**Idle (file available):** Static waveform bar in stone color. Label: "Recording 1 / 0:42 / 0.3 MB". Optional "Enhanced" badge. Optional transcription text below. Swipe left to delete, swipe right to retranscribe.

**Playing (file available):** Waveform bar fills with progress overlay tracking playback position. Play/pause button, current time / total time labels. User can tap or drag on waveform to seek. Same inline expansion pattern as WalkSummaryView.

**Unavailable (file deleted, transcription kept):** `waveform.slash` icon, "Recording unavailable" in fog color. Transcription text still visible. No swipe actions.

**No search results:** "No recordings match" centered in fog text.

### Waveform Visualization

A static bar of ~150 amplitude samples rendered as vertical lines. Computed lazily on a background queue when the row first appears (~50-100ms per recording). Cached in a singleton `WaveformCache` actor keyed by recording UUID — survives view re-creation across navigation pushes/pops to avoid recomputing on every settings visit. The cache is in-memory only, cleared on app termination.

During playback, a fill overlay animates across the waveform tracking position. The waveform doubles as the seek control — tap or drag to scrub.

### Search

Search bar at the top filters recordings by transcription text (case-insensitive substring match). Done in-memory — recording counts in the low hundreds at most. When active, sections with no matching recordings are hidden. Empty results show "No recordings match".

### Enhanced Badge

A small visual indicator on recordings processed with Dynamic Voice. Requires tracking whether enhancement was applied per recording — see Schema Change below.

### Walk Link

Section headers (walk date + start time) are tappable. Tapping fetches the parent Walk entity and presents WalkSummaryView as a sheet.

### Delete Behavior

**Single recording (swipe left):** Confirmation dialog: "Delete this recording file? The transcription will be kept." Deletes .m4a file only. DB entity preserved with transcription and WPM. Row transitions to "unavailable" state. Stops playback if that recording was playing.

**All recordings (bottom button):** Confirmation dialog: "Delete all recording files? Transcriptions will be kept." Calls `DataManager.deleteAllRecordingFiles()`. All rows transition to "unavailable" state. This button is intentionally moved from TalkSettingsView (not duplicated) — TalkSettingsView's existing button is removed.

Note: Deleting an entire walk (via existing `DataManager.deleteObject`) cascade-deletes all its VoiceRecording entities from the DB. The "unavailable" state only applies to file-deleted-but-entity-kept recordings.

### Retranscription (Swipe Right)

Swipe right on a recording triggers retranscription via `TranscriptionService.shared.transcribeSingle(_:)`. RecordingsListView maintains a local `@State var transcriptionOverrides: [UUID: String]` that merges with the persisted transcription value for display, matching the pattern in WalkSummaryView. After the async call completes, the override is set and the row updates immediately.

### Audio Playback

RecordingsListView owns a single `@StateObject var audioPlayer = AudioPlayerModel()` — the same class used in WalkSummaryView. One-player-at-a-time behavior is enforced by AudioPlayerModel's existing `stopPlayer()` before playing a new path. This works across sections (playing a recording from Walk A stops when playing from Walk B).

### Schema Change

New field on `VoiceRecording` entity: `isEnhanced` (Bool, default `false`).

- Set to `true` in `VoiceRecordingManagement.finalizeRecording` when Dynamic Voice was enabled and enhancement was dispatched.
- Old recordings default to `false` — accurate since they were never enhanced.
- Flushed recordings (walk-end sync path with `skipEnhancement: true`) stay `false`.
- `TempVoiceRecording` also gets `isEnhanced` to carry it through the builder pipeline.
- `VoiceRecordingInterface` gets `var isEnhanced: Bool { get }` with a default implementation returning `false`.

### Migration: PilgrimV5

New migration version using `CustomSchemaMappingProvider` — consistent with all previous versions (the project never uses lightweight/inferred migrations; `localStorageOptions: .none`).

```
CustomSchemaMappingProvider(
    from: PilgrimV4.identifier,
    to: PilgrimV5.identifier,
    entityMappings: [
        .copyEntity(sourceEntity: "Workout"),
        .copyEntity(sourceEntity: "WorkoutPause"),
        .copyEntity(sourceEntity: "WorkoutEvent"),
        .copyEntity(sourceEntity: "RouteDataSample"),
        .copyEntity(sourceEntity: "HeartRateDataSample"),
        .copyEntity(sourceEntity: "ActivityInterval"),
        .copyEntity(sourceEntity: "Event"),
        .transformEntity(
            sourceEntity: "VoiceRecording",
            destinationEntity: "VoiceRecording",
            // copy all existing attributes, isEnhanced defaults to false via initial value
        )
    ]
)
```

**Migration chain activation:**
- `PilgrimV5.migrationChain` must include the full chain ending in `PilgrimV5.self`.
- `DataManager.setup(dataModel:)` default parameter must be updated from `PilgrimV4.self` to `PilgrimV5.self`.

### Data Flow

**Data source:** Fetch `Walk` entities ordered by `_startDate` descending, filtered to only walks with at least one VoiceRecording. Iterate each walk's `.voiceRecordings` relationship. This matches existing query patterns in the codebase (e.g., `computeRecentWalkSnippets`).

**Waveform generation:** `WaveformGenerator` utility reads an AVAudioFile, downsamples amplitude data to ~150 points, returns `[Float]`. Runs on a background queue. Results cached in `WaveformCache` singleton actor.

**Per-recording file size:** Computed on a background queue alongside waveform generation (not on main thread during `body` evaluation). Stored in view state dictionary keyed by recording UUID.

### TranscriptionService Cleanup

Remove `deleteModel()` method and `modelDiskSize` computed property — no longer exposed in UI. The `isModelDownloaded` property, `savedModelPath`, and `ensureModelReady()` remain for the auto-transcribe toggle flow.

## File Changes

| File | Action | Purpose |
|------|--------|---------|
| `Pilgrim/Scenes/Settings/RecordingsListView.swift` | Create | Recordings library screen |
| `Pilgrim/Models/Audio/WaveformGenerator.swift` | Create | Extract amplitude samples from audio files |
| `Pilgrim/Models/Audio/WaveformCache.swift` | Create | Singleton actor caching waveform data by recording UUID |
| `Pilgrim/Models/Data/DataModels/Versions/PilgrimV5.swift` | Create | Migration adding `isEnhanced` to VoiceRecording |
| `Pilgrim/Scenes/Settings/TalkSettingsView.swift` | Modify | Replace storage section with NavigationLink, remove model management |
| `Pilgrim/Models/Walk/WalkBuilder/Components/VoiceRecordingManagement.swift` | Modify | Pass `isEnhanced` through finalizeRecording |
| `Pilgrim/Models/Data/Temp/Versions/TempV4.swift` | Modify | Add `isEnhanced` to TempVoiceRecording |
| `Pilgrim/Protocols/DataInterfaces/VoiceRecordingInterface.swift` | Modify | Add `isEnhanced: Bool` to protocol with default `false` |
| `Pilgrim/Models/Data/DataManager.swift` | Modify | Persist `isEnhanced` in `persistRelatedEntities` and `updateWalk`, update `setup()` default to `PilgrimV5.self`, add grouped recordings query |
| `Pilgrim/Models/TranscriptionService.swift` | Modify | Remove `deleteModel()` and `modelDiskSize` |
| `Pilgrim/Support Files/Base.lproj/Localizable.strings` | Modify | Add new recording library strings |
