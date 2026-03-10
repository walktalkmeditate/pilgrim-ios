## Stage 1: Foundation — Rebrand & Walking-Only Shell
**Goal**: Pilgrim launches, tracks a walk with GPS, saves it, shows it in a list.
**Status**: Complete

### Tasks
1. [x] Rebrand: Info.plist display name, WelcomeViewModel, LS system
2. [x] Strip WorkoutType to .walking only
3. [x] Remove HealthKit integration (HealthStoreManager, health setup step, health preferences)
4. [x] Remove AutoPauseDetection component
5. [x] Remove Charts and SnapKit pods (replaced SnapKit constraints with native Auto Layout)
6. [x] Replace RootCoordinatorView placeholder with Home/ActiveWalk/WalkSummary
7. [x] Update onboarding: rebrand, remove health step, add microphone permission
8. [x] Clean UserPreferences (removed health sync, workout type, rolling speed)
9. [x] Strip localization to English only (removed 17 non-English .lproj dirs)

## Stage 2: Voice Recording During Walks
**Goal**: Record voice clips during a walk, timestamped to GPS coordinates.
**Status**: Complete

### Tasks
1. [x] Data model PilgrimV1: VoiceRecording entity, weather/talk/meditate fields on Workout, migration from OutRunV4
2. [x] Update type aliases from OutRunV4 to PilgrimV1 (Workout, WorkoutPause, WorkoutEvent, etc.)
3. [x] TempVoiceRecording codable model + ORVoiceRecordingInterface protocol
4. [x] Add voiceRecordings to ORWorkoutInterface, TempV4.Workout, NewWorkout
5. [x] Update DataManager: PilgrimV1 as default model, persist voice recordings in saveWorkouts
6. [x] VoiceRecordingManagement WorkoutBuilder component (AVAudioRecorder, .m4a, Documents/Recordings/)
7. [x] Voice recording relay on WorkoutBuilder Input/Output
8. [x] VoiceRecording.swift type alias + ORVoiceRecordingInterface + TempValueConvertible conformance
9. [x] Mic button on ActiveWalkView (tap to record/stop, pulsing indicator)
10. [x] Voice recording list with playback on WalkSummaryView
11. [x] Voice pin map: MKPointAnnotation pins at GPS locations of recordings
12. [x] All new files added to Xcode project, clean build (0 errors, 0 warnings)

## Stage 3: Walk / Talk / Meditate Time Tracking
**Goal**: Three distinct time metrics tracked live and shown in summary.
**Status**: Complete

### Tasks
1. [x] MeditateDetection WorkoutBuilder component (speed < 0.2 m/s for 60+ sec)
2. [x] meditateDuration relay on WorkoutBuilder Input/Output
3. [x] talkDuration + meditateDuration fields on TempV4.Workout, ORWorkoutInterface, Workout conformance
4. [x] NewWorkout computes talkDuration from voice recordings, accepts meditateDuration
5. [x] DataManager persists talkDuration/meditateDuration on save and update
6. [x] Three live time counters (walk/talk/meditate) on ActiveWalkView with TimeMetricItem
7. [x] Three time summary cards on WalkSummaryView (walk = active - talk - meditate)
8. [x] Clean build (0 errors, 0 warnings)

## Stage 4: Whisper Transcription (WhisperKit)
**Goal**: Offline transcription of voice recordings after walk ends.
**Status**: Complete

### Tasks
1. [x] Add WhisperKit via Swift Package Manager (0.16.0, coexists with CocoaPods)
2. [x] Bump deployment target to iOS 16.0 (WhisperKit requirement)
3. [x] TranscriptionService: download Whisper tiny model on first use, transcribe .m4a → text
4. [x] DataManager.updateVoiceRecordingTranscription: persist transcription text to CoreStore
5. [x] WalkSummaryView: "Transcribe" button, download progress, per-recording transcription text
6. [x] WalkSummaryView: re-transcribe button per recording, load existing transcriptions on appear
7. [x] TranscriptionService.swift added to Xcode project
8. [x] Clean build (0 errors, 0 warnings in app code)

## Stage 5: AI Prompt Generation
**Goal**: Generate themed prompts from transcriptions for use with any AI.
**Status**: Complete

### Tasks
1. [x] PromptGenerator service: template-based prompts from transcription + walk metadata
2. [x] PromptStyle enum: 6 styles (Contemplative, Reflective, Creative, Gratitude, Philosophical, Journaling)
3. [x] PromptListView: shows all 6 styles with previews, tap to view full prompt
4. [x] PromptDetailView: full prompt text, copy to clipboard, share sheet
5. [x] "Generate AI Prompts" button in WalkSummaryView (shown when transcriptions exist)
6. [x] Chronological transcription ordering with timestamps as context
7. [x] All files added to Xcode project, clean build (0 errors, 0 warnings in app code)

## Stage 6: Wabi-Sabi Design Overhaul
**Goal**: Transform Pilgrim from fitness-tracker aesthetic to contemplative walking tool.
**Status**: Complete

### Tasks
1. [x] Rebrand: OutRunApp → PilgrimApp, bundle ID, entitlements rename, HealthKit removal
2. [x] Localization: All "OutRun" user-facing strings → "Pilgrim"
3. [x] GPX export creator → "Pilgrim", IDETemplateMacros → "Pilgrim"
4. [x] Design system: 9-color adaptive palette (stone, ink, parchment variants, moss, rust, fog, dawn)
5. [x] Typography system: serif (New York) for display/headings/timer/stats, rounded for labels
6. [x] Constants expanded: spacing (xs, breathingRoom), motion (gentle, breath, appear), opacity tokens
7. [x] Accent color asset updated to stone (#8B7355 light, #B8976E dark)
8. [x] PilgrimLogoShape + PilgrimLogoView (P-ensō mark with stem + arc)
9. [x] LaunchScreen: "Pilgrim" in stone on parchment background
10. [x] ActionButton, RoundedButton: stone bg, parchment text, button font
11. [x] CardView: parchmentSecondary bg
12. [x] FeatureView: stone icons, serif titles, parchmentSecondary bg
13. [x] PermissionView: moss for granted, fog for pending
14. [x] ProgressView: stone fill, parchmentTertiary track, 2pt
15. [x] MapView: muted map, stone polyline (3pt), moss voice pins with waveform glyph
16. [x] HomeView: serif header, ensō empty state, pill-shaped "Begin" button, parchment bg
17. [x] WalkRowView: stone left border accent, removed redundant walk icon
18. [x] ActiveWalkView: 60% map, gradient fade, thin serif timer, outlined control buttons
19. [x] WalkSummaryView: date title, hero duration, serif stats, text.quote prompts icon
20. [x] PromptListView/DetailView: stone icons, serif text, stone fill/outline buttons
21. [x] WelcomeView/SetupView/SetupStepBaseView: serif display text, stone accent
22. [x] Clean build verified (BUILD SUCCEEDED)
