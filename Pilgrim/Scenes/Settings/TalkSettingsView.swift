import SwiftUI

struct TalkSettingsView: View {

    @State private var dynamicVoiceEnabled = UserPreferences.dynamicVoiceEnabled.value
    @State private var autoTranscribe = UserPreferences.autoTranscribe.value
    @State private var recordingCount = 0
    @State private var recordingSizeMB: Double = 0
    @ObservedObject private var transcriptionService = TranscriptionService.shared

    var body: some View {
        List {
            enhancementSection
            transcriptionSection
            recordingsSection
        }
        .scrollContentBackground(.hidden)
        .background(Color.parchment)
        .navigationTitle("Talks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Talks")
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
            }
        }
        .onAppear { refreshStats() }
    }

    // MARK: - Sections

    private var enhancementSection: some View {
        Section {
            Toggle(isOn: $dynamicVoiceEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dynamic Voice")
                        .font(Constants.Typography.body)
                    Text("Enhances voice recordings for clarity")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
            }
            .tint(.stone)
            .onChange(of: dynamicVoiceEnabled) { _, val in
                UserPreferences.dynamicVoiceEnabled.value = val
            }
        } header: {
            Text("Enhancement")
                .font(Constants.Typography.caption)
        }
    }

    private var transcriptionSection: some View {
        Section {
            Toggle(isOn: $autoTranscribe) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-transcribe")
                        .font(Constants.Typography.body)
                    Text("Transcribe recordings after each walk")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
            }
            .tint(.stone)
            .onChange(of: autoTranscribe) { _, val in
                if val {
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
        } header: {
            Text("Transcription")
                .font(Constants.Typography.caption)
        }
    }

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

    // MARK: - Helpers

    private func refreshStats() {
        recordingCount = DataManager.recordingFileCount()
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsDir = docs.appendingPathComponent("Recordings")
        recordingSizeMB = Double(FileManager.default.sizeOfDirectory(at: recordingsDir) ?? 0) / 1_000_000.0
    }
}
