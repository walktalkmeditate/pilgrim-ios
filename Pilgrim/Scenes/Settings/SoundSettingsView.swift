import SwiftUI

struct SoundSettingsView: View {

    @ObservedObject private var manifestService = AudioManifestService.shared
    @ObservedObject private var downloadManager = AudioDownloadManager.shared
    @State private var soundsEnabled = UserPreferences.soundsEnabled.value
    @State private var hapticEnabled = UserPreferences.bellHapticEnabled.value
    @State private var bellVolume = UserPreferences.bellVolume.value
    @State private var soundscapeVolume = UserPreferences.soundscapeVolume.value

    @State private var walkStartBellId = UserPreferences.walkStartBellId.value
    @State private var walkEndBellId = UserPreferences.walkEndBellId.value
    @State private var meditationStartBellId = UserPreferences.meditationStartBellId.value
    @State private var meditationEndBellId = UserPreferences.meditationEndBellId.value
    @State private var selectedSoundscapeId = UserPreferences.selectedSoundscapeId.value

    @State private var breathRhythm = UserPreferences.breathRhythm.value
    @State private var activePicker: PickerType?

    private let bellPlayer = BellPlayer.shared
    private let soundscapePlayer = SoundscapePlayer.shared
    private let fileStore = AudioFileStore.shared

    var body: some View {
        List {
            mainToggleSection
            if soundsEnabled {
                walkSection
                meditationSection
                volumeSection
                storageSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.parchment)
        .navigationTitle("Sounds")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Sounds")
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
            }
        }
        .sheet(item: $activePicker) { picker in
            pickerSheet(for: picker)
        }
        .onDisappear {
            bellPlayer.stop()
            soundscapePlayer.stop()
        }
    }

    // MARK: - Sections

    private var mainToggleSection: some View {
        Section {
            Toggle(isOn: $soundsEnabled) {
                Text("Sounds")
                    .font(Constants.Typography.body)
            }
            .tint(.stone)
            .onChange(of: soundsEnabled) { _, val in
                UserPreferences.soundsEnabled.value = val
            }

            if soundsEnabled {
                Toggle(isOn: $hapticEnabled) {
                    Text("Haptic with bells")
                        .font(Constants.Typography.body)
                }
                .tint(.stone)
                .onChange(of: hapticEnabled) { _, val in
                    UserPreferences.bellHapticEnabled.value = val
                }
            }
        }
    }

    private var walkSection: some View {
        Section {
            bellRow(label: "Start bell", bellId: walkStartBellId) {
                activePicker = .walkStartBell
            }
            bellRow(label: "End bell", bellId: walkEndBellId) {
                activePicker = .walkEndBell
            }
        } header: {
            Text("Walk")
                .font(Constants.Typography.caption)
        }
    }

    private var meditationSection: some View {
        Section {
            bellRow(label: "Start bell", bellId: meditationStartBellId) {
                activePicker = .meditationStartBell
            }
            bellRow(label: "End bell", bellId: meditationEndBellId) {
                activePicker = .meditationEndBell
            }
            soundscapeRow

            Button {
                activePicker = .breathRhythm
            } label: {
                HStack {
                    Text("Breath rhythm")
                        .font(Constants.Typography.body)
                        .foregroundColor(.fog)
                    Spacer()
                    Text(breathRhythm < BreathRhythm.all.count ? BreathRhythm.all[breathRhythm].name : "Calm")
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.fog)
                }
            }
        } header: {
            Text("Meditation")
                .font(Constants.Typography.caption)
        }
    }

    private var volumeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Bells")
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)
                    Spacer()
                    Text("\(Int(bellVolume * 100))%")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
                Slider(value: $bellVolume, in: 0...1)
                    .tint(.stone)
                    .onChange(of: bellVolume) { _, val in
                        UserPreferences.bellVolume.value = val
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Soundscape")
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)
                    Spacer()
                    Text("\(Int(soundscapeVolume * 100))%")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
                Slider(value: $soundscapeVolume, in: 0...1)
                    .tint(.stone)
                    .onChange(of: soundscapeVolume) { _, val in
                        UserPreferences.soundscapeVolume.value = val
                    }
            }
        } header: {
            Text("Volume")
                .font(Constants.Typography.caption)
        }
    }

    private var storageSection: some View {
        Section {
            if downloadManager.isDownloading {
                HStack {
                    SwiftUI.ProgressView(value: downloadManager.downloadProgress)
                        .tint(.stone)
                    Text("Downloading...")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
            }

            HStack {
                let count = manifestService.manifest?.assets.count ?? 0
                let sizeMB = Double(fileStore.totalDiskUsage()) / 1_000_000.0
                Text("\(count) sounds")
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink)
                Spacer()
                Text(String(format: "%.1f MB", sizeMB))
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }

            Button(role: .destructive) {
                fileStore.clearAll()
                AudioManifestService.shared.syncIfNeeded()
            } label: {
                Text("Clear Downloaded Sounds")
                    .font(Constants.Typography.body)
            }
        } header: {
            Text("Storage")
                .font(Constants.Typography.caption)
        }
    }

    // MARK: - Rows

    private func bellRow(label: String, bellId: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(Constants.Typography.body)
                    .foregroundColor(.fog)
                Spacer()
                Text(bellDisplayName(for: bellId))
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.fog)
            }
        }
    }

    private var soundscapeRow: some View {
        Button {
            activePicker = .soundscape
        } label: {
            HStack {
                Text("Soundscape")
                    .font(Constants.Typography.body)
                    .foregroundColor(.fog)
                Spacer()
                Text(soundscapeDisplayName)
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.fog)
            }
        }
    }

    // MARK: - Picker Sheet

    @ViewBuilder
    private func pickerSheet(for picker: PickerType) -> some View {
        NavigationStack {
            List {
                if picker == .soundscape {
                    soundscapePickerContent
                } else if picker == .breathRhythm {
                    breathRhythmPickerContent
                } else {
                    bellPickerContent(for: picker)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.parchment)
            .navigationTitle(picker.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(picker.title)
                            .font(Constants.Typography.heading)
                            .foregroundColor(.ink)
                        Text(picker.subtitle)
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { activePicker = nil }
                        .foregroundColor(.stone)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func bellPickerContent(for picker: PickerType) -> some View {
        let currentId = currentBellId(for: picker)
        let bells = manifestService.bells()
        return Section {
            ForEach(bells) { bell in
                HStack {
                    Button {
                        if fileStore.isAvailable(bell) {
                            bellPlayer.play(bell, volume: Float(bellVolume))
                        }
                    } label: {
                        Image(systemName: "play.circle")
                            .foregroundColor(fileStore.isAvailable(bell) ? .stone : .fog)
                    }
                    .buttonStyle(.plain)

                    Text(bell.displayName)
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)

                    Spacer()

                    if currentId == bell.id {
                        Image(systemName: "checkmark")
                            .foregroundColor(.stone)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    setBellId(bell.id, for: picker)
                }
            }

            Button {
                setBellId(nil, for: picker)
            } label: {
                HStack {
                    Text("None")
                        .font(Constants.Typography.body)
                        .foregroundColor(.fog)
                    Spacer()
                    if currentId == nil {
                        Image(systemName: "checkmark")
                            .foregroundColor(.stone)
                    }
                }
            }
        }
    }

    private var soundscapePickerContent: some View {
        Section {
            ForEach(manifestService.soundscapes) { scape in
                HStack {
                    Button {
                        if fileStore.isAvailable(scape) {
                            if soundscapePlayer.currentAsset?.id == scape.id && soundscapePlayer.isPlaying {
                                soundscapePlayer.stop()
                            } else {
                                soundscapePlayer.play(scape, volume: Float(soundscapeVolume))
                            }
                        }
                    } label: {
                        Image(systemName: soundscapePlayer.currentAsset?.id == scape.id && soundscapePlayer.isPlaying
                              ? "stop.circle" : "play.circle")
                            .foregroundColor(fileStore.isAvailable(scape) ? .stone : .fog)
                    }
                    .buttonStyle(.plain)

                    Text(scape.displayName)
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)

                    Spacer()

                    if selectedSoundscapeId == scape.id {
                        Image(systemName: "checkmark")
                            .foregroundColor(.stone)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedSoundscapeId = scape.id
                    UserPreferences.selectedSoundscapeId.value = scape.id
                }
            }

            Button {
                soundscapePlayer.stop()
                selectedSoundscapeId = nil
                UserPreferences.selectedSoundscapeId.value = nil
            } label: {
                HStack {
                    Text("None")
                        .font(Constants.Typography.body)
                        .foregroundColor(.fog)
                    Spacer()
                    if selectedSoundscapeId == nil {
                        Image(systemName: "checkmark")
                            .foregroundColor(.stone)
                    }
                }
            }
        }
    }

    private var breathRhythmPickerContent: some View {
        Section {
            ForEach(BreathRhythm.all) { r in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(r.name)
                                .font(Constants.Typography.body)
                                .foregroundColor(.ink)
                            if !r.isNone {
                                Text(r.label)
                                    .font(Constants.Typography.caption)
                                    .foregroundColor(.fog)
                            }
                        }
                        Text(r.description)
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                    }
                    Spacer()
                    if breathRhythm == r.id {
                        Image(systemName: "checkmark")
                            .foregroundColor(.stone)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    breathRhythm = r.id
                    UserPreferences.breathRhythm.value = r.id
                }
            }
        }
    }

    // MARK: - Helpers

    private func bellDisplayName(for id: String?) -> String {
        guard let id else { return "None" }
        return manifestService.asset(byId: id)?.displayName ?? id
    }

    private var soundscapeDisplayName: String {
        guard let id = selectedSoundscapeId else { return "None" }
        return manifestService.asset(byId: id)?.displayName ?? id
    }

    private func currentBellId(for picker: PickerType) -> String? {
        switch picker {
        case .walkStartBell: return walkStartBellId
        case .walkEndBell: return walkEndBellId
        case .meditationStartBell: return meditationStartBellId
        case .meditationEndBell: return meditationEndBellId
        case .soundscape, .breathRhythm: return nil
        }
    }

    private func setBellId(_ id: String?, for picker: PickerType) {
        switch picker {
        case .walkStartBell:
            walkStartBellId = id
            UserPreferences.walkStartBellId.value = id
        case .walkEndBell:
            walkEndBellId = id
            UserPreferences.walkEndBellId.value = id
        case .meditationStartBell:
            meditationStartBellId = id
            UserPreferences.meditationStartBellId.value = id
        case .meditationEndBell:
            meditationEndBellId = id
            UserPreferences.meditationEndBellId.value = id
        case .soundscape, .breathRhythm:
            break
        }
    }
}

enum PickerType: String, Identifiable {
    case walkStartBell, walkEndBell, meditationStartBell, meditationEndBell, soundscape, breathRhythm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walkStartBell: return "Start Bell"
        case .walkEndBell: return "End Bell"
        case .meditationStartBell: return "Start Bell"
        case .meditationEndBell: return "End Bell"
        case .soundscape: return "Soundscape"
        case .breathRhythm: return "Breath Rhythm"
        }
    }

    var subtitle: String {
        switch self {
        case .walkStartBell, .walkEndBell: return "for walk"
        case .meditationStartBell, .meditationEndBell: return "for meditation"
        case .soundscape: return "during meditation"
        case .breathRhythm: return "for meditation"
        }
    }
}
