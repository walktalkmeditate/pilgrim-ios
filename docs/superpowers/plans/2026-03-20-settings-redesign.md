# Settings Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat List settings page with a card-based continuous scroll organized by intent — The Practice, Atmosphere, Voice, Permissions, Your Data — with inline controls, descriptions, and a seasonal practice summary.

**Architecture:** Rewrite `SettingsView.swift` as a `ScrollView` containing card components. Each card is a separate SwiftUI file. Simple toggles are inline (no sub-pages). Complex settings (bell pickers, voice packs, recordings) keep existing sub-pages. `GeneralSettingsView` and `TalkSettingsView` are eliminated — their settings move inline to cards.

**Tech Stack:** SwiftUI, UserPreferences, PermissionStatusViewModel, HomeViewModel, TranscriptionService

**Spec:** `docs/superpowers/specs/2026-03-20-settings-redesign-design.md`

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `Pilgrim/Scenes/Settings/SettingsCards/PracticeCard.swift` | Intention, celestial, units — inline toggles |
| `Pilgrim/Scenes/Settings/SettingsCards/AtmosphereCard.swift` | Appearance, sounds toggle, links to bell/soundscape sub-pages |
| `Pilgrim/Scenes/Settings/SettingsCards/VoiceCard.swift` | Voice guide, dynamic voice, auto-transcribe, recordings link |
| `Pilgrim/Scenes/Settings/SettingsCards/PermissionsCard.swift` | Location, microphone, motion with status dots |
| `Pilgrim/Scenes/Settings/SettingsCards/DataCard.swift` | Export, import, trail note |
| `Pilgrim/Scenes/Settings/PracticeSummaryHeader.swift` | Seasonal vignette + walk/distance/meditation stats |
| `Pilgrim/Scenes/Settings/SettingsCards/SettingsCardStyle.swift` | Shared card modifier (background, corner radius, padding) |

### Rewritten
| File | Change |
|------|--------|
| `Pilgrim/Scenes/Settings/SettingsView.swift` | Complete rewrite — ScrollView with cards |

### Removed (settings moved inline)
| File | Reason |
|------|--------|
| `Pilgrim/Scenes/Settings/GeneralSettingsView.swift` | All settings moved to PracticeCard, AtmosphereCard, PermissionsCard |
| `Pilgrim/Scenes/Settings/TalkSettingsView.swift` | Settings moved to VoiceCard |

### Unchanged (kept as sub-pages)
- `SoundSettingsView.swift` — bell/soundscape pickers
- `VoiceGuideSettingsView.swift` — voice pack management
- `RecordingsListView.swift` — recording management
- `DataSettingsView.swift` — export/import with progress
- `FeedbackView.swift` — trail note form
- `AboutView.swift` — narrative about page

---

## Task 1: Card Style + Practice Summary Header

**Files:**
- Create: `Pilgrim/Scenes/Settings/SettingsCards/SettingsCardStyle.swift`
- Create: `Pilgrim/Scenes/Settings/PracticeSummaryHeader.swift`

- [ ] **Step 1: Create SettingsCardStyle**

A reusable ViewModifier for card styling:

```swift
import SwiftUI

struct SettingsCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Constants.UI.Padding.normal)
            .background(Color.parchmentSecondary)
            .cornerRadius(Constants.UI.CornerRadius.normal)
    }
}

extension View {
    func settingsCard() -> some View {
        modifier(SettingsCardStyle())
    }
}
```

- [ ] **Step 2: Create PracticeSummaryHeader**

```swift
import SwiftUI

struct PracticeSummaryHeader: View {
    let walkCount: Int
    let totalDistanceMeters: Double
    let totalMeditationSeconds: TimeInterval

    var body: some View {
        VStack(spacing: Constants.UI.Padding.small) {
            Text(seasonLabel)
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)

            Text(statsLine)
                .font(Constants.Typography.body)
                .foregroundColor(.stone)

            if totalMeditationSeconds > 60 {
                Text(meditationLine)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Constants.UI.Padding.big)
    }

    private var seasonLabel: String {
        let season = SealTimeHelpers.season(for: Date(), latitude: 0)
        let year = Calendar.current.component(.year, from: Date())
        return "\(season) \(year)"
    }

    private var statsLine: String {
        let isImperial = UserPreferences.distanceMeasurementType.safeValue == .miles
        let distKm = totalDistanceMeters / 1000
        let dist = isImperial ? distKm * 0.621371 : distKm
        let unit = isImperial ? "mi" : "km"
        return "\(walkCount) walks · \(String(format: "%.0f", dist)) \(unit)"
    }

    private var meditationLine: String {
        let hours = Int(totalMeditationSeconds) / 3600
        let minutes = (Int(totalMeditationSeconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m meditated"
        }
        return "\(minutes) min meditated"
    }
}
```

- [ ] **Step 3: Add to Xcode project, build**
- [ ] **Step 4: Commit**

```
feat(settings): add SettingsCardStyle modifier and PracticeSummaryHeader
```

---

## Task 2: Practice Card

**Files:**
- Create: `Pilgrim/Scenes/Settings/SettingsCards/PracticeCard.swift`

Port settings from `GeneralSettingsView`: intention toggle, celestial toggle + zodiac picker, units picker.

- [ ] **Step 1: Create PracticeCard**

```swift
import SwiftUI

struct PracticeCard: View {

    @State private var beginWithIntention = UserPreferences.beginWithIntention.value
    @State private var celestialAwareness = UserPreferences.celestialAwarenessEnabled.value
    @State private var zodiacSystem = UserPreferences.zodiacSystem.value
    @State private var isMetric = UserPreferences.distanceMeasurementType.safeValue == .kilometers

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.normal) {
            cardHeader(title: "The Practice", subtitle: "How you walk")

            settingToggle(
                label: "Begin with intention",
                description: "Set an intention before each walk",
                isOn: $beginWithIntention
            ) { UserPreferences.beginWithIntention.value = $0 }

            settingToggle(
                label: "Celestial awareness",
                description: "Moon phases, planetary hours, and zodiac during walks",
                isOn: $celestialAwareness
            ) { UserPreferences.celestialAwarenessEnabled.value = $0 }

            if celestialAwareness {
                settingPicker(
                    label: "Zodiac system",
                    selection: $zodiacSystem,
                    options: [("Tropical", "tropical"), ("Sidereal", "sidereal")]
                ) { UserPreferences.zodiacSystem.value = $0 }
            }

            VStack(alignment: .leading, spacing: 6) {
                settingPicker(
                    label: "Units",
                    selection: $isMetric,
                    options: [("Metric", true), ("Imperial", false)]
                ) { UserPreferences.applyUnitSystem(metric: $0) }

                Text(isMetric ? "km · min/km · m · °C" : "mi · min/mi · ft · °F")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
        }
        .settingsCard()
        .animation(.easeInOut(duration: 0.2), value: celestialAwareness)
    }
}
```

Note: `cardHeader`, `settingToggle`, and `settingPicker` are shared helper views. Add them to `SettingsCardStyle.swift` or create as standalone:

```swift
func cardHeader(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title)
            .font(Constants.Typography.heading)
            .foregroundColor(.ink)
        Text(subtitle)
            .font(Constants.Typography.caption)
            .foregroundColor(.fog)
    }
    .padding(.bottom, Constants.UI.Padding.small)
}

func settingToggle(
    label: String,
    description: String,
    isOn: Binding<Bool>,
    onChange: @escaping (Bool) -> Void
) -> some View {
    Toggle(isOn: isOn) {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Constants.Typography.body)
                .foregroundColor(.ink)
            Text(description)
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
        }
    }
    .tint(.stone)
    .onChange(of: isOn.wrappedValue) { _, newValue in onChange(newValue) }
}

func settingPicker<T: Hashable>(
    label: String,
    selection: Binding<T>,
    options: [(String, T)],
    onChange: @escaping (T) -> Void
) -> some View {
    HStack {
        Text(label)
            .font(Constants.Typography.body)
            .foregroundColor(.ink)
        Spacer()
        Picker("", selection: selection) {
            ForEach(options, id: \.1) { option in
                Text(option.0).tag(option.1)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 180)
        .onChange(of: selection.wrappedValue) { _, newValue in onChange(newValue) }
    }
}
```

- [ ] **Step 2: Add to Xcode project, build**
- [ ] **Step 3: Commit**

```
feat(settings): add PracticeCard with inline intention, celestial, units controls
```

---

## Task 3: Atmosphere Card

**Files:**
- Create: `Pilgrim/Scenes/Settings/SettingsCards/AtmosphereCard.swift`

- [ ] **Step 1: Create AtmosphereCard**

Appearance segmented control + sounds toggle inline. Bell/soundscape/volume as NavigationLinks to existing sub-pages.

```swift
import SwiftUI

struct AtmosphereCard: View {

    @State private var appearanceMode = UserPreferences.appearanceMode.value
    @State private var soundsEnabled = UserPreferences.soundsEnabled.value

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.normal) {
            cardHeader(title: "Atmosphere", subtitle: "How it feels")

            settingPicker(
                label: "Appearance",
                selection: $appearanceMode,
                options: [("Auto", "system"), ("Light", "light"), ("Dark", "dark")]
            ) { UserPreferences.appearanceMode.value = $0 }

            settingToggle(
                label: "Sounds",
                description: "Bells, haptics, and ambient soundscapes",
                isOn: $soundsEnabled
            ) { UserPreferences.soundsEnabled.value = $0 }

            if soundsEnabled {
                NavigationLink {
                    SoundSettingsView()
                } label: {
                    settingNavRow(label: "Bells & Soundscapes")
                }

                NavigationLink {
                    // Volume sub-page — reuse volume section from SoundSettingsView
                    // or create a simple VolumeSettingsView
                    SoundSettingsView()
                } label: {
                    settingNavRow(label: "Volume")
                }
            }
        }
        .settingsCard()
        .animation(.easeInOut(duration: 0.2), value: soundsEnabled)
    }
}
```

**IMPORTANT:** Before implementing, read `SoundSettingsView.swift` to understand how bell/soundscape pickers work. The NavigationLinks here should go to the existing `SoundSettingsView` (which already has all the sub-settings). We don't need separate sub-pages for bells vs volume — just link to `SoundSettingsView` with a single NavigationLink "Bells & Soundscapes" that covers everything.

Add `settingNavRow` helper:
```swift
func settingNavRow(label: String, detail: String? = nil) -> some View {
    HStack {
        Text(label)
            .font(Constants.Typography.body)
            .foregroundColor(.ink)
        Spacer()
        if let detail {
            Text(detail)
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
        }
        Image(systemName: "chevron.right")
            .font(Constants.Typography.caption)
            .foregroundColor(.fog)
    }
}
```

- [ ] **Step 2: Add to Xcode project, build**
- [ ] **Step 3: Commit**

```
feat(settings): add AtmosphereCard with appearance, sounds, and sub-page links
```

---

## Task 4: Voice Card

**Files:**
- Create: `Pilgrim/Scenes/Settings/SettingsCards/VoiceCard.swift`

Port settings from `TalkSettingsView` + voice guide toggle. Important: the auto-transcribe toggle has model download logic that must be preserved.

- [ ] **Step 1: Read `TalkSettingsView.swift` carefully**

Note the `TranscriptionService` integration for model downloading when auto-transcribe is enabled. This logic must be ported exactly.

- [ ] **Step 2: Create VoiceCard**

```swift
import SwiftUI

struct VoiceCard: View {

    @State private var voiceGuideEnabled = UserPreferences.voiceGuideEnabled.value
    @State private var dynamicVoice = UserPreferences.dynamicVoiceEnabled.value
    @State private var autoTranscribe = UserPreferences.autoTranscribe.value
    @State private var recordingCount = 0
    @State private var recordingSizeMB: Double = 0
    @ObservedObject private var transcriptionService = TranscriptionService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.normal) {
            cardHeader(title: "Voice", subtitle: "What you hear and say")

            settingToggle(
                label: "Voice Guide",
                description: "Spoken prompts during walks and meditation",
                isOn: $voiceGuideEnabled
            ) { UserPreferences.voiceGuideEnabled.value = $0 }

            if voiceGuideEnabled {
                NavigationLink {
                    VoiceGuideSettingsView()
                } label: {
                    settingNavRow(label: "Guide Packs")
                }
            }

            settingToggle(
                label: "Dynamic Voice",
                description: "Enhance clarity of your voice recordings",
                isOn: $dynamicVoice
            ) { UserPreferences.dynamicVoiceEnabled.value = $0 }

            // Auto-transcribe with model download logic
            autoTranscribeSection

            NavigationLink {
                RecordingsListView()
            } label: {
                settingNavRow(
                    label: "Recordings",
                    detail: recordingCount > 0
                        ? "\(recordingCount) · \(String(format: "%.1f MB", recordingSizeMB))"
                        : nil
                )
            }
        }
        .settingsCard()
        .animation(.easeInOut(duration: 0.2), value: voiceGuideEnabled)
        .onAppear { refreshRecordingStats() }
    }

    // Port the auto-transcribe toggle + model download from TalkSettingsView exactly
    private var autoTranscribeSection: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            Toggle(isOn: $autoTranscribe) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-transcribe")
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)
                    Text("Convert recordings to text after each walk")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
            }
            .tint(.stone)
            .onChange(of: autoTranscribe) { _, val in
                handleAutoTranscribeChange(val)
            }

            if case .downloadingModel(let progress) = transcriptionService.state {
                HStack(spacing: 8) {
                    SwiftUI.ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.stone)
                    Text("Downloading model \(Int(progress * 100))%")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
            }
        }
    }

    private func handleAutoTranscribeChange(_ enabled: Bool) {
        // Exact logic from TalkSettingsView
        if enabled {
            if transcriptionService.isModelDownloaded {
                UserPreferences.autoTranscribe.value = true
            } else {
                Task {
                    do {
                        try await transcriptionService.ensureModelReady()
                        if autoTranscribe {
                            UserPreferences.autoTranscribe.value = true
                        }
                    } catch {
                        autoTranscribe = false
                    }
                }
            }
        } else {
            UserPreferences.autoTranscribe.value = false
        }
    }

    private func refreshRecordingStats() {
        recordingCount = DataManager.recordingFileCount()
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsDir = docs.appendingPathComponent("Recordings")
        recordingSizeMB = Double(FileManager.default.sizeOfDirectory(at: recordingsDir) ?? 0) / 1_000_000.0
    }
}
```

- [ ] **Step 3: Add to Xcode project, build**
- [ ] **Step 4: Commit**

```
feat(settings): add VoiceCard with guide, dynamic voice, auto-transcribe, recordings
```

---

## Task 5: Permissions Card + Data Card

**Files:**
- Create: `Pilgrim/Scenes/Settings/SettingsCards/PermissionsCard.swift`
- Create: `Pilgrim/Scenes/Settings/SettingsCards/DataCard.swift`

- [ ] **Step 1: Create PermissionsCard**

Port the permission rows from `GeneralSettingsView` with status dots:

```swift
import SwiftUI

struct PermissionsCard: View {

    @ObservedObject var permissionVM: PermissionStatusViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.normal) {
            cardHeader(title: "Permissions", subtitle: "What the app needs")

            permissionRow(
                title: "Location",
                description: "Route tracking during walks",
                state: permissionVM.locationState,
                onGrant: permissionVM.requestLocation
            )
            permissionRow(
                title: "Microphone",
                description: "Voice recording and transcription",
                state: permissionVM.microphoneState,
                onGrant: permissionVM.requestMicrophone
            )
            permissionRow(
                title: "Motion",
                description: "Step counting and activity detection",
                state: permissionVM.motionState,
                onGrant: permissionVM.requestMotion
            )
        }
        .settingsCard()
    }

    private func permissionRow(
        title: String, description: String,
        state: PermissionState, onGrant: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Constants.UI.Padding.small) {
            Circle()
                .fill(dotColor(for: state))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink)
                Text(description)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }

            Spacer()

            permissionAction(state: state, onGrant: onGrant)
        }
    }

    private func dotColor(for state: PermissionState) -> Color {
        switch state {
        case .granted: return .moss
        case .notDetermined: return .dawn
        case .denied: return .rust
        case .restricted: return .fog
        }
    }

    @ViewBuilder
    private func permissionAction(state: PermissionState, onGrant: @escaping () -> Void) -> some View {
        switch state {
        case .granted:
            Image(systemName: "checkmark")
                .foregroundColor(.moss)
                .font(Constants.Typography.caption)
        case .notDetermined:
            Button("Grant", action: onGrant)
                .font(Constants.Typography.button)
                .foregroundColor(.stone)
        case .denied:
            Button("Settings", action: permissionVM.openSettings)
                .font(Constants.Typography.button)
                .foregroundColor(.stone)
        case .restricted:
            Text("Restricted")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
        }
    }
}
```

- [ ] **Step 2: Create DataCard**

```swift
import SwiftUI

struct DataCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.normal) {
            cardHeader(title: "Your Data", subtitle: "Your pilgrimage archive")

            NavigationLink {
                DataSettingsView()
            } label: {
                settingNavRow(label: "Export & Import")
            }

            NavigationLink {
                FeedbackView()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    settingNavRow(label: "Leave a Trail Note")
                    Text("Share a thought, report a bug, or suggest a feature")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
            }
        }
        .settingsCard()
    }
}
```

- [ ] **Step 3: Add both to Xcode project, build**
- [ ] **Step 4: Commit**

```
feat(settings): add PermissionsCard with status dots and DataCard
```

---

## Task 6: Rewrite SettingsView + Remove Old Files

**Files:**
- Rewrite: `Pilgrim/Scenes/Settings/SettingsView.swift`
- Remove: `Pilgrim/Scenes/Settings/GeneralSettingsView.swift`
- Remove: `Pilgrim/Scenes/Settings/TalkSettingsView.swift`

- [ ] **Step 1: Read existing SettingsView.swift**

- [ ] **Step 2: Rewrite SettingsView**

```swift
import SwiftUI

struct SettingsView: View {

    @StateObject private var permissionVM = PermissionStatusViewModel()
    @State private var walkCount = 0
    @State private var totalDistance: Double = 0
    @State private var totalMeditation: TimeInterval = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Constants.UI.Padding.big) {
                    PracticeSummaryHeader(
                        walkCount: walkCount,
                        totalDistanceMeters: totalDistance,
                        totalMeditationSeconds: totalMeditation
                    )

                    PracticeCard()
                    AtmosphereCard()
                    VoiceCard()
                    PermissionsCard(permissionVM: permissionVM)
                    DataCard()

                    NavigationLink {
                        AboutView()
                    } label: {
                        HStack {
                            Text("About Pilgrim")
                                .font(Constants.Typography.body)
                                .foregroundColor(.ink)
                            Spacer()
                            Text(appVersion)
                                .font(Constants.Typography.caption)
                                .foregroundColor(.fog)
                            Image(systemName: "chevron.right")
                                .font(Constants.Typography.caption)
                                .foregroundColor(.fog)
                        }
                        .settingsCard()
                    }
                }
                .padding(.horizontal, Constants.UI.Padding.normal)
                .padding(.bottom, Constants.UI.Padding.breathingRoom)
            }
            .background(Color.parchment)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(Constants.Typography.heading)
                        .foregroundColor(.ink)
                }
            }
            .onAppear {
                permissionVM.refresh()
                loadStats()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                permissionVM.refresh()
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private func loadStats() {
        let walks = DataManager.allWalks()
        walkCount = walks.count
        totalDistance = walks.reduce(0) { $0 + $1.distance }
        totalMeditation = walks.reduce(0) { $0 + $1.meditateDuration }
    }
}
```

**IMPORTANT:** `DataManager.allWalks()` may not exist. Read `DataManager.swift` to find the correct method for fetching all walks (likely `DataManager.fetchAll()` or similar). The `HomeViewModel.loadWalks()` shows the pattern. Alternatively, accept `HomeViewModel` as an environment object from `MainTabView`.

- [ ] **Step 3: Remove GeneralSettingsView.swift and TalkSettingsView.swift**

Delete both files and remove their references from `project.pbxproj`.

- [ ] **Step 4: Build and run all tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

- [ ] **Step 5: Commit**

```
feat(settings): rewrite SettingsView with card-based scroll, remove GeneralSettingsView and TalkSettingsView
```

---

## Completion Checklist

- [ ] All existing settings accessible from the new UI (nothing lost)
- [ ] Intention, celestial, units, appearance — inline, no sub-page
- [ ] Sounds, voice guide — toggle inline, sub-pages for complex settings
- [ ] Auto-transcribe model download logic preserved exactly
- [ ] Permissions show status dots (green/amber/red) with action buttons
- [ ] Practice summary shows walk count, distance, meditation time
- [ ] Season label at top
- [ ] Every setting has a one-line description
- [ ] Cards styled with parchmentSecondary background, proper corner radius
- [ ] GeneralSettingsView and TalkSettingsView removed
- [ ] All existing tests pass
- [ ] Build succeeds
