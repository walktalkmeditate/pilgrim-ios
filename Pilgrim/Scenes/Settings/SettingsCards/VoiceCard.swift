import SwiftUI

struct VoiceCard: View {

    @State private var voiceGuideEnabled = UserPreferences.voiceGuideEnabled.value
    @State private var dynamicVoiceEnabled = UserPreferences.dynamicVoiceEnabled.value
    @State private var autoTranscribe = UserPreferences.autoTranscribe.value
    @State private var recordingCount = 0
    @State private var recordingSizeMB: Double = 0
    @ObservedObject private var transcriptionService = TranscriptionService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            cardHeader(title: "Voice", subtitle: "Speaking and listening")

            settingToggle(
                label: "Voice Guide",
                description: "Spoken prompts during walks and meditation",
                isOn: $voiceGuideEnabled
            ) { newValue in
                UserPreferences.voiceGuideEnabled.value = newValue
            }

            if voiceGuideEnabled {
                NavigationLink {
                    VoiceGuideSettingsView()
                } label: {
                    settingNavRow(label: "Guide Packs")
                }
            }

            Divider()

            settingToggle(
                label: "Dynamic Voice",
                description: "Enhance clarity of your voice recordings",
                isOn: $dynamicVoiceEnabled
            ) { newValue in
                UserPreferences.dynamicVoiceEnabled.value = newValue
            }

            settingToggle(
                label: "Auto-transcribe",
                description: "Convert recordings to text after each walk",
                isOn: $autoTranscribe
            ) { newValue in
                handleAutoTranscribeChange(newValue)
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

            Divider()

            NavigationLink {
                RecordingsListView()
            } label: {
                settingNavRow(
                    label: "Recordings",
                    detail: "\(recordingCount) recording\(recordingCount == 1 ? "" : "s") \u{2022} \(String(format: "%.1f MB", recordingSizeMB))"
                )
            }
        }
        .settingsCard()
        .animation(.easeInOut(duration: 0.2), value: voiceGuideEnabled)
        .onAppear { refreshStats() }
    }

    // MARK: - Auto-Transcribe

    private func handleAutoTranscribeChange(_ enabled: Bool) {
        if enabled {
            if transcriptionService.isModelDownloaded {
                UserPreferences.autoTranscribe.value = true
            } else {
                let userIntent = enabled
                Task {
                    do {
                        try await transcriptionService.ensureModelReady()
                        if userIntent {
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

    // MARK: - Recording Stats

    private func refreshStats() {
        recordingCount = DataManager.recordingFileCount()
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsDir = docs.appendingPathComponent("Recordings")
        recordingSizeMB = Double(FileManager.default.sizeOfDirectory(at: recordingsDir) ?? 0) / 1_000_000.0
    }
}
