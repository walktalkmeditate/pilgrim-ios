import SwiftUI

/// Voice-recordings section of the walk summary, extracted from
/// `WalkSummaryView` (AF17).
///
/// Owning the `AudioPlayerModel` HERE is the load-bearing part: its progress
/// timer publishes at 10 Hz during playback, and when the whole summary
/// observed it, every tick re-evaluated the entire summary body — including
/// the Mapbox representable. Scoped to this subview, playback ticks
/// re-render only the recording rows. The `@StateObject` + `.onDisappear`
/// stop pairing preserves the AF15/AF16 lifecycle fixes (deinit is the
/// belt-and-suspenders for paths where onDisappear doesn't fire).
struct WalkSummaryRecordingsSection: View {

    let walk: WalkInterface
    /// Owned by the parent — `PromptListView` and the prompts button read
    /// transcriptions outside this section.
    @Binding var transcriptions: [UUID: String]

    @StateObject private var audioPlayer = AudioPlayerModel()
    @ObservedObject private var transcriptionService = TranscriptionService.shared
    @State private var waveforms: [UUID: [Float]] = [:]
    @State private var deletedPaths: Set<String> = []
    @State private var pathToDelete: String?
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            recordingsHeader
            transcriptionStatusBanner
            autoTranscriptionBanner

            ForEach(Array(walk.voiceRecordings.enumerated()), id: \.element.uuid) { index, recording in
                recordingRow(index: index, recording: recording)
            }
        }
        .padding(Constants.UI.Padding.normal)
        .background(Color.parchmentSecondary)
        .cornerRadius(Constants.UI.CornerRadius.normal)
        .onDisappear {
            audioPlayer.stop()
        }
        .alert(
            "Delete this recording file? The transcription will be kept.",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                guard let path = pathToDelete else { return }
                if audioPlayer.currentPath == path {
                    audioPlayer.stop()
                }
                DataManager.deleteRecordingFile(relativePath: path)
                deletedPaths.insert(path)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func recordingRow(index: Int, recording: VoiceRecordingInterface) -> some View {
        let isActive = audioPlayer.currentPath == recording.fileRelativePath
        let fileAvailable = isFileAvailable(recording.fileRelativePath)
        return VoiceRecordingRow(
            index: index + 1,
            recording: recording,
            transcription: recording.uuid.flatMap { transcriptions[$0] },
            fileAvailable: fileAvailable,
            isActive: isActive && fileAvailable,
            isPlaying: isActive && audioPlayer.isPlaying,
            progress: isActive ? audioPlayer.progress : 0,
            currentTime: isActive ? audioPlayer.currentTime : 0,
            audioDuration: isActive ? audioPlayer.totalDuration : recording.duration,
            playbackSpeed: audioPlayer.playbackSpeed,
            onTogglePlay: {
                audioPlayer.toggle(relativePath: recording.fileRelativePath)
            },
            onSeek: { fraction in
                audioPlayer.seek(to: fraction)
            },
            onCycleSpeed: {
                audioPlayer.cycleSpeed()
            },
            onRetranscribe: {
                Task { await retranscribeSingle(recording) }
            },
            onDelete: {
                pathToDelete = recording.fileRelativePath
                showDeleteConfirmation = true
            },
            onTranscriptionSave: { newText in
                guard let uuid = recording.uuid else { return }
                transcriptions[uuid] = newText
                DataManager.updateVoiceRecordingTranscription(uuid: uuid, transcription: newText)
            },
            waveformSamples: recording.uuid.flatMap { waveforms[$0] }
        )
        .task {
            await loadWaveformIfNeeded(for: recording)
        }
    }

    private func loadWaveformIfNeeded(for recording: VoiceRecordingInterface) async {
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
        } else {
            await WaveformCache.shared.clearInFlight(uuid)
        }
    }

    private var recordingsHeader: some View {
        HStack {
            Image(systemName: "waveform")
                .foregroundColor(.stone)
            Text("Voice Recordings")
                .font(Constants.Typography.heading)
                .foregroundColor(.ink)
                .minimumScaleFactor(0.7)
            Spacer()

            if hasUntranscribedRecordings && !isTranscribing {
                Button(action: { Task { await transcribeAll() } }) {
                    Label("Transcribe", systemImage: "text.badge.plus")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.stone)
                        .minimumScaleFactor(0.7)
                }
            }

            Text("\(walk.voiceRecordings.count)")
                .font(Constants.Typography.statLabel)
                .foregroundColor(.fog)
        }
    }

    @ViewBuilder
    private var transcriptionStatusBanner: some View {
        switch transcriptionService.state {
        case .downloadingModel(let progress):
            HStack(spacing: 8) {
                SwiftUI.ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.stone)
                Text("Downloading model \(Int(progress * 100))%")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
            .padding(.vertical, 4)
        case .transcribing(let current, let total):
            HStack(spacing: 8) {
                SwiftUI.ProgressView()
                    .tint(.stone)
                Text("Transcribing \(current)/\(total)")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
            .padding(.vertical, 4)
        case .failed(let message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.dawn)
                Text(message)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                Spacer()
                if hasUntranscribedRecordings {
                    Button(action: { Task { await transcribeAll() } }) {
                        Text("Retry")
                            .font(Constants.Typography.button)
                            .foregroundColor(.stone)
                    }
                }
            }
            .padding(.vertical, 4)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var autoTranscriptionBanner: some View {
        if transcriptionService.autoTranscriptionSkippedReason == .lowBattery {
            HStack(spacing: 8) {
                Image(systemName: "battery.25")
                    .foregroundColor(.dawn)
                Text("Auto-transcription skipped — battery below 20%")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
            .padding(.vertical, 4)
        }
    }

    private var isTranscribing: Bool {
        switch transcriptionService.state {
        case .downloadingModel, .transcribing: return true
        default: return false
        }
    }

    private var hasUntranscribedRecordings: Bool {
        walk.voiceRecordings.contains { recording in
            guard let uuid = recording.uuid else { return false }
            return transcriptions[uuid] == nil && isFileAvailable(recording.fileRelativePath)
        }
    }

    private func transcribeAll() async {
        let untranscribed = walk.voiceRecordings.filter { recording in
            guard let uuid = recording.uuid else { return false }
            return transcriptions[uuid] == nil && isFileAvailable(recording.fileRelativePath)
        }
        let results = await transcriptionService.transcribeRecordings(untranscribed)
        for (uuid, text) in results {
            transcriptions[uuid] = text
        }
        if !results.isEmpty {
            transcriptionService.autoTranscriptionSkippedReason = nil
        }
    }

    private func retranscribeSingle(_ recording: VoiceRecordingInterface) async {
        if let text = await transcriptionService.transcribeSingle(recording),
           let uuid = recording.uuid {
            transcriptions[uuid] = text
        }
    }

    private func isFileAvailable(_ relativePath: String) -> Bool {
        guard !relativePath.isEmpty else { return false }
        guard !deletedPaths.contains(relativePath) else { return false }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return FileManager.default.fileExists(atPath: docs.appendingPathComponent(relativePath).path)
    }
}
