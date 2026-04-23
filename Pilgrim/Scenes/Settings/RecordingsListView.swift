import SwiftUI
import AVFoundation
import CoreStore

struct RecordingsListView: View {

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
    @State private var expandedTranscriptions: Set<UUID> = []
    @State private var editingTranscriptionUUID: UUID?
    @State private var editingTranscriptionText = ""
    @FocusState private var isTranscriptionEditFocused: Bool

    var body: some View {
        Group {
            if walkSections.isEmpty {
                emptyState
            } else {
                recordingsList
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.parchment)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Recordings")
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
            }
        }
        .onAppear { loadWalks() }
        .onDisappear { audioPlayer.stop() }
        .sheet(item: $selectedWalk) { walk in
            WalkSummaryView(walk: walk)
        }
    }

    // MARK: - List

    private var recordingsList: some View {
        List {
            if filteredSections.isEmpty {
                Text("No recordings match")
                    .font(Constants.Typography.body)
                    .foregroundColor(.fog)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Constants.UI.Padding.big)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(filteredSections) { section in
                    Section {
                        ForEach(Array(section.recordings.enumerated()), id: \.element.uuid) { index, recording in
                            recordingRow(recording, index: index + 1, in: section)
                        }
                    } header: {
                        sectionHeader(for: section)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteAllConfirmation = true
                    } label: {
                        Text("Delete All Recording Files")
                            .font(Constants.Typography.body)
                    }
                    .alert(
                        "Delete all recording files? Transcriptions will be kept.",
                        isPresented: $showDeleteAllConfirmation
                    ) {
                        Button("Delete All", role: .destructive) {
                            audioPlayer.stop()
                            DataManager.deleteAllRecordingFiles()
                            deletedPaths.formUnion(
                                walkSections.flatMap { $0.recordings.map { $0.fileRelativePath } }
                            )
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search transcriptions")
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

    // MARK: - Section Header

    private func sectionHeader(for section: WalkSection) -> some View {
        Button {
            selectedWalk = section.walk
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.headerDateFormatter.string(from: section.walk.startDate))
                        .font(Constants.Typography.caption)
                        .foregroundColor(.ink)
                    Text("\(formatDuration(totalDuration(for: section))) of recordings")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.fog)
            }
        }
    }

    // MARK: - Recording Row

    private func recordingRow(_ recording: VoiceRecordingInterface, index: Int, in section: WalkSection) -> some View {
        let recUUID = recording.uuid
        let isActive = audioPlayer.currentPath == recording.fileRelativePath
        let fileAvailable = isFileAvailable(recording.fileRelativePath)
        let transcriptionText = recUUID.flatMap { transcriptionOverrides[$0] } ?? recording.transcription

        return VStack(alignment: .leading, spacing: Constants.UI.Padding.xs) {
            if fileAvailable {
                playerHeader(for: recording, index: index, isActive: isActive)
                waveformContent(for: recording, isActive: isActive)
                if isActive {
                    playbackTimeLabels
                }
            } else {
                unavailableRow
            }

            if let text = transcriptionText, !text.isEmpty {
                transcriptionBlock(text: text, uuid: recUUID)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if fileAvailable {
                Button(role: .destructive) {
                    pathToDelete = recording.fileRelativePath
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if fileAvailable {
                Button {
                    retranscribe(recording)
                } label: {
                    Label("Retranscribe", systemImage: "arrow.clockwise")
                }
                .tint(.stone)
            }
        }
        .task { await loadWaveformAndSize(for: recording) }
    }

    // MARK: - Row Components

    private func playerHeader(for recording: VoiceRecordingInterface, index: Int, isActive: Bool) -> some View {
        let speed = audioPlayer.playbackSpeed
        let speedLabel = speed.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0fx", speed)
            : String(format: "%gx", speed)

        return HStack(spacing: Constants.UI.Padding.small) {
            Button { audioPlayer.toggle(relativePath: recording.fileRelativePath) } label: {
                Image(systemName: isActive && audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(.stone)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("Recording \(index)")
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink)
                HStack(spacing: Constants.UI.Padding.xs) {
                    Text(formatSeconds(recording.duration))
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                    if let uuid = recording.uuid, let size = fileSizes[uuid] {
                        Text(formatFileSize(size))
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                    }
                    if recording.isEnhanced {
                        Text("·")
                            .foregroundColor(.fog)
                        Text("Enhanced")
                            .font(Constants.Typography.caption)
                            .foregroundColor(.stone)
                    }
                }
            }
            Spacer()
            Button { audioPlayer.cycleSpeed() } label: {
                Text(speedLabel)
                    .font(Constants.Typography.caption)
                    .foregroundColor(speed > 1.0 ? .parchment : .stone)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(speed > 1.0 ? Color.stone : Color.stone.opacity(0.12))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
        }
    }

    private var playbackTimeLabels: some View {
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

    private var unavailableRow: some View {
        HStack(spacing: Constants.UI.Padding.xs) {
            Image(systemName: "waveform.slash")
                .foregroundColor(.fog)
            Text("File unavailable")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
        }
        .frame(height: 32)
    }

    @ViewBuilder
    private func transcriptionBlock(text: String, uuid: UUID?) -> some View {
        if let uuid, editingTranscriptionUUID == uuid {
            VStack(alignment: .trailing, spacing: 4) {
                TextEditor(text: $editingTranscriptionText)
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink)
                    .focused($isTranscriptionEditFocused)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 60, maxHeight: 200)
                    .padding(4)
                    .background(Color.parchmentTertiary)
                    .cornerRadius(Constants.UI.CornerRadius.small)
                Button {
                    let trimmed = editingTranscriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        transcriptionOverrides[uuid] = trimmed
                        DataManager.updateVoiceRecordingTranscription(uuid: uuid, transcription: trimmed)
                    }
                    editingTranscriptionUUID = nil
                    isTranscriptionEditFocused = false
                } label: {
                    Text("Done")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.stone)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.stone.opacity(0.12))
                        .cornerRadius(4)
                }
            }
        } else {
            HStack(alignment: .top) {
                Text(text)
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink)
                    .padding(Constants.UI.Padding.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.parchmentTertiary)
                    .cornerRadius(Constants.UI.CornerRadius.small)
                    .onTapGesture {
                        if let uuid {
                            editingTranscriptionText = text
                            editingTranscriptionUUID = uuid
                            isTranscriptionEditFocused = true
                        }
                    }
                Button {
                    UIPasteboard.general.string = text
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(.fog)
                }
            }
        }
    }

    // MARK: - Waveform

    @ViewBuilder
    private func waveformContent(for recording: VoiceRecordingInterface, isActive: Bool) -> some View {
        if let uuid = recording.uuid, let samples = waveforms[uuid] {
            WaveformBarView(
                samples: samples,
                progress: isActive ? audioPlayer.progress : 0,
                isPlaying: isActive && audioPlayer.isPlaying
            ) { fraction in
                if isActive {
                    audioPlayer.seek(to: fraction)
                } else {
                    audioPlayer.toggle(relativePath: recording.fileRelativePath)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        audioPlayer.seek(to: fraction)
                    }
                }
            }
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.fog.opacity(0.15))
                .frame(height: 32)
        }
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: Constants.UI.Padding.normal) {
            Image(systemName: "waveform")
                .font(.largeTitle)
                .foregroundColor(.fog)
            Text("Your voice recordings will appear here")
                .font(Constants.Typography.body)
                .foregroundColor(.fog)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.parchment)
    }

    // MARK: - Data Loading

    private func loadWalks() {
        do {
            let walks = try DataManager.dataStack.fetchAll(
                From<Walk>()
                    .orderBy(.descending(\._startDate))
            )
            walkSections = walks.compactMap { walk in
                guard walk.uuid != nil else { return nil }
                let recordings = walk.voiceRecordings
                    .filter { $0.uuid != nil }
                    .sorted { $0.startDate < $1.startDate }
                guard !recordings.isEmpty else { return nil }
                return WalkSection(walk: walk, recordings: recordings)
            }
        } catch {
            walkSections = []
        }
    }

    private var filteredSections: [WalkSection] {
        guard !searchText.isEmpty else { return walkSections }
        let query = searchText.lowercased()
        return walkSections.compactMap { section in
            let matched = section.recordings.filter { recording in
                let text = recording.uuid.flatMap { transcriptionOverrides[$0] } ?? recording.transcription
                return text?.lowercased().contains(query) == true
            }
            guard !matched.isEmpty else { return nil }
            return WalkSection(walk: section.walk, recordings: matched)
        }
    }

    // MARK: - Waveform & File Size Loading

    private func loadWaveformAndSize(for recording: VoiceRecordingInterface) async {
        guard let uuid = recording.uuid else { return }

        if let cached = await WaveformCache.shared.samples(for: uuid) {
            waveforms[uuid] = cached
        } else if await WaveformCache.shared.markInFlight(uuid) {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let url = docs.appendingPathComponent(recording.fileRelativePath)
            if let samples = await Task.detached(priority: .utility, operation: {
                WaveformGenerator.generateSamples(from: url)
            }).value {
                await WaveformCache.shared.store(samples, for: uuid)
                await MainActor.run { waveforms[uuid] = samples }
            } else {
                await WaveformCache.shared.clearInFlight(uuid)
            }
        }

        if fileSizes[uuid] == nil {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let url = docs.appendingPathComponent(recording.fileRelativePath)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int {
                fileSizes[uuid] = size
            }
        }
    }

    // MARK: - Actions

    private func retranscribe(_ recording: VoiceRecordingInterface) {
        Task {
            if let text = await transcriptionService.transcribeSingle(recording),
               let uuid = recording.uuid {
                transcriptionOverrides[uuid] = text
            }
        }
    }

    private func isFileAvailable(_ relativePath: String) -> Bool {
        guard !relativePath.isEmpty else { return false }
        guard !deletedPaths.contains(relativePath) else { return false }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return FileManager.default.fileExists(atPath: docs.appendingPathComponent(relativePath).path)
    }

    // MARK: - Formatters

    private func totalDuration(for section: WalkSection) -> Int {
        Int(section.recordings.reduce(0) { $0 + $1.duration })
    }

    private func formatDuration(_ totalSeconds: Int) -> String {
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func formatSeconds(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1_000_000.0
        return String(format: "%.1f MB", mb)
    }

    private static let headerDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, h:mm a"
        return f
    }()
}

// MARK: - WalkSection

private struct WalkSection: Identifiable {
    let walk: Walk
    let recordings: [VoiceRecordingInterface]
    var id: UUID { walk.uuid ?? UUID() }
}

// MARK: - WaveformBarView

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
                    Rectangle().frame(width: geo.size.width * CGFloat(progress))
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
