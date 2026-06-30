import SwiftUI

struct VoiceGuideSettingsView: View {

    @ObservedObject private var manifestService = VoiceGuideManifestService.shared
    @ObservedObject private var downloadManager = VoiceGuideDownloadManager.shared
    @State private var enabled = UserPreferences.voiceGuideEnabled.value
    @State private var selectedPackId = UserPreferences.selectedVoiceGuidePackId.value
    @State private var volume = UserPreferences.voiceGuideVolume.value
    @State private var duckLevel = UserPreferences.voiceGuideDuckLevel.value

    private let fileStore = VoiceGuideFileStore.shared

    var body: some View {
        List {
            enableSection.pilgrimListRow()
            if enabled {
                if manifestService.isSyncing && manifestService.packs.isEmpty {
                    loadingSection.pilgrimListRow()
                } else if manifestService.packs.isEmpty {
                    emptySection.pilgrimListRow()
                } else {
                    packsSection.pilgrimListRow()
                    volumeSection.pilgrimListRow()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .canvasBackground()
        .navigationTitle("Voice Guide")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Voice Guide")
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
            }
        }
        .onAppear {
            enabled = UserPreferences.voiceGuideEnabled.value
            selectedPackId = UserPreferences.selectedVoiceGuidePackId.value
            manifestService.syncIfNeeded()
        }
    }

    // MARK: - Sections

    private var enableSection: some View {
        Section {
            Toggle(isOn: $enabled) {
                Text("Voice Guide")
                    .font(Constants.Typography.body)
            }
            .tint(.stone)
            .onChange(of: enabled) { _, val in
                UserPreferences.voiceGuideEnabled.value = val
            }
        }
    }

    private var loadingSection: some View {
        Section {
            HStack {
                SwiftUI.ProgressView()
                    .tint(.stone)
                Text("Loading packs...")
                    .font(Constants.Typography.body)
                    .foregroundColor(.fog)
            }
        }
    }

    private var emptySection: some View {
        Section {
            Text("Connect to the internet to browse voice guide packs")
                .font(Constants.Typography.body)
                .foregroundColor(.fog)
        }
    }

    private var packsSection: some View {
        Section {
            ForEach(manifestService.packs) { pack in
                packRow(pack)
            }
        } header: {
            Text("Packs")
                .font(Constants.Typography.caption)
        }
    }

    private var volumeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Guide Volume")
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)
                    Spacer()
                    Text("\(Int(volume * 100))%")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
                Slider(value: $volume, in: 0...1)
                    .tint(.stone)
                    .onChange(of: volume) { _, val in
                        UserPreferences.voiceGuideVolume.value = val
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Soundscape during guide")
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)
                    Spacer()
                    Text("\(Int(duckLevel * 100))%")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
                Slider(value: $duckLevel, in: 0...1)
                    .tint(.stone)
                    .onChange(of: duckLevel) { _, val in
                        UserPreferences.voiceGuideDuckLevel.value = val
                    }
            }
        } header: {
            Text("Volume")
                .font(Constants.Typography.caption)
        }
    }

    // MARK: - Rows

    private struct PackDownloadState {
        let isSelected: Bool
        let isDownloaded: Bool
        let isDownloading: Bool
        let didFail: Bool
        let progress: Double
    }

    private func packRow(_ pack: VoiceGuidePack) -> some View {
        let isDownloaded = fileStore.isPackDownloaded(pack)
        let state = PackDownloadState(
            isSelected: selectedPackId == pack.id,
            isDownloaded: isDownloaded,
            isDownloading: downloadManager.activeDownloads.contains(pack.id),
            didFail: downloadManager.downloadErrors.contains(pack.id),
            progress: downloadManager.downloadProgress[pack.id] ?? 0
        )

        return Button {
            if isDownloaded {
                selectedPackId = pack.id
                UserPreferences.selectedVoiceGuidePackId.value = pack.id
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: pack.iconName)
                    .font(.title2)
                    .foregroundColor(.stone)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(pack.name)
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)
                    Text(pack.tagline)
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                        .lineLimit(1)
                }

                Spacer()

                packTrailingContent(pack: pack, state: state)
            }
        }
        .swipeActions(edge: .trailing) {
            if isDownloaded && !state.isSelected {
                Button(role: .destructive) {
                    fileStore.deletePackFiles(pack.id)
                    if selectedPackId == pack.id {
                        selectedPackId = nil
                        UserPreferences.selectedVoiceGuidePackId.value = nil
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private func packTrailingContent(pack: VoiceGuidePack, state: PackDownloadState) -> some View {
        if state.isDownloading {
            SwiftUI.ProgressView(value: state.progress)
                .tint(.stone)
                .frame(width: 40)
        } else if state.didFail && !state.isDownloaded {
            // AF23: a finished-but-failed download must say so, not silently
            // revert to the arrow. The whole label retries on tap.
            Button {
                downloadManager.downloadPack(pack)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Download failed — tap to retry")
                        .font(Constants.Typography.caption)
                        .multilineTextAlignment(.trailing)
                }
                .foregroundColor(.rust)
            }
            .buttonStyle(.plain)
        } else if !state.isDownloaded {
            Button {
                downloadManager.downloadPack(pack)
            } label: {
                Image(systemName: "arrow.down.circle")
                    .foregroundColor(.stone)
            }
            .buttonStyle(.plain)
            .onChange(of: downloadManager.activeDownloads) { _, active in
                if !active.contains(pack.id),
                   fileStore.isPackDownloaded(pack),
                   selectedPackId == nil {
                    selectedPackId = pack.id
                    UserPreferences.selectedVoiceGuidePackId.value = pack.id
                }
            }
        } else if state.isSelected {
            Image(systemName: "checkmark")
                .foregroundColor(.stone)
        }
    }
}
