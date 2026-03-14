import SwiftUI

struct SoundSettingsView: View {

    @StateObject private var manifestService = AudioManifestService.shared
    @StateObject private var downloadManager = AudioDownloadManager.shared
    @State private var soundsEnabled = UserPreferences.soundsEnabled.value
    @State private var bellVolume = UserPreferences.bellVolume.value
    @State private var soundscapeVolume = UserPreferences.soundscapeVolume.value
    @State private var selectedStartBellId = UserPreferences.selectedStartBellId.value ?? "echo-chime"
    @State private var selectedEndBellId = UserPreferences.selectedEndBellId.value ?? "gentle-harp"
    @State private var selectedSoundscapeId = UserPreferences.selectedSoundscapeId.value ?? "gentle-stream"

    private let bellPlayer = BellPlayer.shared
    private let soundscapePlayer = SoundscapePlayer.shared
    private let fileStore = AudioFileStore.shared

    var body: some View {
        List {
            masterToggle
            if soundsEnabled {
                bellSection
                soundscapeSection
                cacheSection
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
        .onDisappear {
            bellPlayer.stop()
            soundscapePlayer.stop()
        }
    }

    private var masterToggle: some View {
        Section {
            Toggle(isOn: $soundsEnabled) {
                Text("Sounds")
                    .font(Constants.Typography.body)
            }
            .tint(.stone)
            .onChange(of: soundsEnabled) { _, newValue in
                UserPreferences.soundsEnabled.value = newValue
            }
        }
    }

    private var bellSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
                Text("Volume")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                Slider(value: $bellVolume, in: 0...1)
                    .tint(.stone)
                    .onChange(of: bellVolume) { _, newValue in
                        UserPreferences.bellVolume.value = newValue
                    }
            }

            bellPicker(title: "Start Bell", selectedId: $selectedStartBellId) { id in
                UserPreferences.selectedStartBellId.value = id
            }

            bellPicker(title: "End Bell", selectedId: $selectedEndBellId) { id in
                UserPreferences.selectedEndBellId.value = id
            }
        } header: {
            Text("Bells")
                .font(Constants.Typography.caption)
        }
    }

    private func bellPicker(title: String, selectedId: Binding<String>, onSelect: @escaping (String) -> Void) -> some View {
        let bells = manifestService.bells()
        return VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            Text(title)
                .font(Constants.Typography.body)
                .foregroundColor(.ink)

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

                    if selectedId.wrappedValue == bell.id {
                        Image(systemName: "checkmark")
                            .foregroundColor(.stone)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedId.wrappedValue = bell.id
                    onSelect(bell.id)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var soundscapeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
                Text("Volume")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                Slider(value: $soundscapeVolume, in: 0...1)
                    .tint(.stone)
                    .onChange(of: soundscapeVolume) { _, newValue in
                        UserPreferences.soundscapeVolume.value = newValue
                    }
            }

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
                .padding(.vertical, 2)
            }
        } header: {
            Text("Soundscapes")
                .font(Constants.Typography.caption)
        }
    }

    private var cacheSection: some View {
        Section {
            HStack {
                let count = (manifestService.manifest?.assets.count) ?? 0
                let sizeBytes = fileStore.totalDiskUsage()
                let sizeMB = Double(sizeBytes) / 1_000_000.0
                Text("\(count) sounds")
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink)
                Spacer()
                Text(String(format: "%.1f MB", sizeMB))
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }

            if downloadManager.isDownloading {
                HStack {
                    SwiftUI.ProgressView(value: downloadManager.downloadProgress)
                        .tint(.stone)
                    Text("Downloading...")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
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
}
