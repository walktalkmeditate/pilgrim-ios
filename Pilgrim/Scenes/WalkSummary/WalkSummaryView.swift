import SwiftUI
import MapKit
import AVFoundation
import CoreStore

struct WalkSummaryView: View {

    let walk: WalkInterface
    @Environment(\.dismiss) private var dismiss
    @StateObject private var audioPlayer = AudioPlayerModel()
    @ObservedObject private var transcriptionService = TranscriptionService.shared
    @State private var transcriptions: [UUID: String] = [:]
    @State private var showPrompts = false
    @State private var mapRegion: MKCoordinateRegion?
    @State private var recentWalkSnippets: [PromptGenerator.WalkSnippet] = []

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Constants.UI.Padding.normal) {
                    mapSection
                    durationHero
                    statsRow
                    timeBreakdown
                    activityTimelineBar
                    activityInsights
                    activityList
                    if !walk.voiceRecordings.isEmpty {
                        recordingsSection
                    }
                    if !transcriptions.isEmpty {
                        promptsButton
                    }
                    detailsSection
                }
                .padding(Constants.UI.Padding.normal)
            }
            .background(Color.parchment)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(dateTitle)
                        .font(Constants.Typography.heading)
                        .foregroundColor(.ink)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.stone)
                }
            }
            .onAppear {
                loadExistingTranscriptions()
                loadRecentWalkSnippets()
                if routeCoordinates.count > 1 {
                    mapRegion = regionForRoute(routeCoordinates)
                }
            }
            .sheet(isPresented: $showPrompts) {
                NavigationView {
                    PromptListView(walk: walk, transcriptions: transcriptions, recentWalkSnippets: recentWalkSnippets)
                }
            }
        }
    }

    private static let dateTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        return f
    }()

    private var dateTitle: String {
        Self.dateTitleFormatter.string(from: walk.startDate)
    }

    private var promptsButton: some View {
        Button {
            showPrompts = true
        } label: {
            HStack {
                Image(systemName: "text.quote")
                    .font(.title2)
                    .foregroundColor(.stone)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Generate AI Prompts")
                        .font(Constants.Typography.heading)
                        .foregroundColor(.ink)
                    Text("\(transcriptions.count) transcription\(transcriptions.count == 1 ? "" : "s") available")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.fog)
            }
            .padding(Constants.UI.Padding.normal)
            .background(Color.parchmentSecondary)
            .cornerRadius(Constants.UI.CornerRadius.normal)
        }
    }

    private func loadRecentWalkSnippets() {
        guard let walks = try? DataManager.dataStack.fetchAll(
            From<Walk>()
                .where(\._startDate < walk.startDate)
                .orderBy(.descending(\._startDate))
                .tweak { $0.fetchLimit = 20 }
        ) else { return }

        recentWalkSnippets = walks
            .filter { w in w.voiceRecordings.contains { $0.transcription != nil } }
            .prefix(3)
            .map { w in
                let allText = w.voiceRecordings
                    .compactMap { $0.transcription }
                    .joined(separator: " ")
                let preview = allText.truncatedAtWordBoundary()
                return PromptGenerator.WalkSnippet(date: w.startDate, placeName: nil, transcriptionPreview: preview)
            }
    }

    private func loadExistingTranscriptions() {
        for recording in walk.voiceRecordings {
            if let uuid = recording.uuid, let text = recording.transcription {
                transcriptions[uuid] = text
            }
        }
    }

    private var mapSection: some View {
        Group {
            if routeCoordinates.count > 1 {
                let polylines = activityColoredPolylines
                let annotations = allPinAnnotations
                ZStack(alignment: .bottom) {
                    MapView(
                        region: $mapRegion,
                        isZoomEnabled: .constant(true),
                        isScrollEnabled: .constant(true),
                        showsUserLocation: .constant(false),
                        userTrackingMode: .constant(.none),
                        annotations: .constant(annotations as [MKAnnotation]),
                        overlays: .constant(polylines)
                    )
                    .frame(height: 280)
                    .cornerRadius(Constants.UI.CornerRadius.big)

                    LinearGradient(
                        colors: [.clear, .parchment.opacity(0.4)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .frame(height: 60)
                    .cornerRadius(Constants.UI.CornerRadius.big)
                }
            } else {
                RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.big)
                    .fill(Color.parchmentSecondary)
                    .frame(height: 280)
                    .overlay(
                        Text("No route data")
                            .font(Constants.Typography.body)
                            .foregroundColor(.fog)
                    )
            }
        }
    }

    private var durationHero: some View {
        Text(formatDuration(walk.activeDuration))
            .font(Constants.Typography.timer)
            .foregroundColor(.ink)
            .padding(.top, Constants.UI.Padding.small)
    }

    private var statsRow: some View {
        HStack(spacing: Constants.UI.Padding.big) {
            miniStat(label: "Distance", value: formatDistance(walk.distance))
            miniStat(label: "Steps", value: formatSteps(walk.steps))
            miniStat(label: "Elevation", value: formatElevation(walk.ascend))
        }
        .padding(.bottom, Constants.UI.Padding.small)
    }

    private func miniStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Constants.Typography.statValue)
                .foregroundColor(.ink)
            Text(label)
                .font(Constants.Typography.statLabel)
                .foregroundColor(.fog)
        }
        .frame(maxWidth: .infinity)
    }

    private var timeBreakdown: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: Constants.UI.Padding.normal) {
            SummaryCard(title: "Walk", value: formatDuration(walkDuration), icon: "figure.walk")
            SummaryCard(title: "Talk", value: formatDuration(walk.talkDuration), icon: "waveform")
            SummaryCard(title: "Meditate", value: formatDuration(walk.meditateDuration), icon: "brain.head.profile")
        }
    }

    private var walkDuration: Double {
        max(0, walk.activeDuration - walk.meditateDuration)
    }

    private var activityTimelineBar: some View {
        ActivityTimelineBar(
            startDate: walk.startDate,
            endDate: walk.endDate,
            activeDuration: walk.activeDuration,
            voiceRecordings: walk.voiceRecordings,
            activityIntervals: walk.activityIntervals,
            routeData: walk.routeData,
            onSegmentTapped: { start, end in
                if let region = regionForTimeRange(start: start, end: end) {
                    withAnimation { mapRegion = region }
                }
            },
            onSegmentDeselected: {
                if routeCoordinates.count > 1 {
                    withAnimation { mapRegion = regionForRoute(routeCoordinates) }
                }
            }
        )
    }

    @ViewBuilder
    private var activityInsights: some View {
        if walk.talkDuration > 0 || walk.meditateDuration > 0 {
            ActivityInsightsView(
                talkDuration: walk.talkDuration,
                activeDuration: walk.activeDuration,
                activityIntervals: walk.activityIntervals
            )
        }
    }

    @ViewBuilder
    private var activityList: some View {
        if !walk.activityIntervals.isEmpty || !walk.voiceRecordings.isEmpty {
            ActivityListView(
                startDate: walk.startDate,
                endDate: walk.endDate,
                voiceRecordings: walk.voiceRecordings,
                activityIntervals: walk.activityIntervals
            )
        }
    }

    private var recordingsSection: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            recordingsHeader
            transcriptionStatusBanner

            ForEach(Array(walk.voiceRecordings.enumerated()), id: \.element.uuid) { index, recording in
                let isActive = audioPlayer.currentPath == recording.fileRelativePath
                VoiceRecordingRow(
                    index: index + 1,
                    recording: recording,
                    transcription: recording.uuid.flatMap { transcriptions[$0] },
                    isActive: isActive,
                    isPlaying: isActive && audioPlayer.isPlaying,
                    progress: isActive ? audioPlayer.progress : 0,
                    currentTime: isActive ? audioPlayer.currentTime : 0,
                    audioDuration: isActive ? audioPlayer.totalDuration : recording.duration,
                    onTogglePlay: {
                        audioPlayer.toggle(relativePath: recording.fileRelativePath)
                    },
                    onSeek: { fraction in
                        audioPlayer.seek(to: fraction)
                    },
                    onRetranscribe: {
                        Task { await retranscribeSingle(recording) }
                    }
                )
            }
        }
        .padding(Constants.UI.Padding.normal)
        .background(Color.parchmentSecondary)
        .cornerRadius(Constants.UI.CornerRadius.normal)
    }

    private var recordingsHeader: some View {
        HStack {
            Image(systemName: "waveform")
                .foregroundColor(.stone)
            Text("Voice Recordings")
                .font(Constants.Typography.heading)
                .foregroundColor(.ink)
            Spacer()

            if hasUntranscribedRecordings && !isTranscribing {
                Button(action: { Task { await transcribeAll() } }) {
                    Label("Transcribe", systemImage: "text.badge.plus")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.stone)
                }
            }

            Text("\(walk.voiceRecordings.count)")
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
            }
            .padding(.vertical, 4)
        default:
            EmptyView()
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
            return transcriptions[uuid] == nil
        }
    }

    private func transcribeAll() async {
        let untranscribed = walk.voiceRecordings.filter { recording in
            guard let uuid = recording.uuid else { return false }
            return transcriptions[uuid] == nil
        }
        let results = await transcriptionService.transcribeRecordings(untranscribed)
        for (uuid, text) in results {
            transcriptions[uuid] = text
        }
    }

    private func retranscribeSingle(_ recording: VoiceRecordingInterface) async {
        if let text = await transcriptionService.transcribeSingle(recording),
           let uuid = recording.uuid {
            transcriptions[uuid] = text
        }
    }

    @ViewBuilder
    private var detailsSection: some View {
        if walk.pauseDuration > 0 {
            HStack {
                Text("Paused")
                    .foregroundColor(.fog)
                Spacer()
                Text(formatDuration(walk.pauseDuration))
                    .foregroundColor(.ink)
            }
            .font(Constants.Typography.body)
            .padding(Constants.UI.Padding.normal)
            .background(Color.parchmentSecondary)
            .cornerRadius(Constants.UI.CornerRadius.normal)
        }
    }

    // MARK: - Activity-Colored Polylines

    private var activityColoredPolylines: [MKPolyline] {
        let samples = walk.routeData
        guard samples.count > 1 else { return [] }

        var segments: [(type: String, indices: [Int])] = []
        var currentType = activityTypeForSample(samples[0])
        var currentIndices = [0]

        for i in 1..<samples.count {
            let type = activityTypeForSample(samples[i])
            if type == currentType {
                currentIndices.append(i)
            } else {
                currentIndices.append(i)
                segments.append((type: currentType, indices: currentIndices))
                currentType = type
                currentIndices = [i]
            }
        }
        segments.append((type: currentType, indices: currentIndices))

        return segments.map { segment in
            let coords = segment.indices.map { i in
                CLLocationCoordinate2D(latitude: samples[i].latitude, longitude: samples[i].longitude)
            }
            let polyline = MKPolyline(coordinates: coords, count: coords.count)
            polyline.title = segment.type
            return polyline
        }
    }

    private func activityTypeForSample(_ sample: RouteDataSampleInterface) -> String {
        let timestamp = sample.timestamp

        for interval in walk.activityIntervals where interval.activityType == .meditation {
            if timestamp >= interval.startDate && timestamp <= interval.endDate {
                return "meditating"
            }
        }

        for recording in walk.voiceRecordings {
            if timestamp >= recording.startDate && timestamp <= recording.endDate {
                return "talking"
            }
        }

        return "walking"
    }

    // MARK: - Pin Annotations

    private var allPinAnnotations: [MKAnnotation] {
        voicePinAnnotations + meditationPinAnnotations
    }

    private var meditationPinAnnotations: [MKPointAnnotation] {
        let routeSamples = walk.routeData
        return walk.activityIntervals
            .filter { $0.activityType == .meditation }
            .compactMap { interval in
                guard let closest = routeSamples.min(by: {
                    abs($0.timestamp.timeIntervalSince(interval.startDate)) <
                    abs($1.timestamp.timeIntervalSince(interval.startDate))
                }) else { return nil }

                let annotation = MKPointAnnotation()
                annotation.coordinate = CLLocationCoordinate2D(latitude: closest.latitude, longitude: closest.longitude)
                annotation.title = "meditation"
                return annotation
            }
    }

    private var voicePinAnnotations: [MKPointAnnotation] {
        let routeSamples = walk.routeData
        return walk.voiceRecordings.compactMap { recording in
            guard let closest = routeSamples.min(by: {
                abs($0.timestamp.timeIntervalSince(recording.startDate)) <
                abs($1.timestamp.timeIntervalSince(recording.startDate))
            }) else { return nil }

            let annotation = MKPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(latitude: closest.latitude, longitude: closest.longitude)
            annotation.title = "Recording \(formatDuration(recording.duration))"
            return annotation
        }
    }

    // MARK: - Helpers

    private var routeCoordinates: [CLLocationCoordinate2D] {
        walk.routeData.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    private func regionForTimeRange(start: Date, end: Date) -> MKCoordinateRegion? {
        let samples = walk.routeData.filter { $0.timestamp >= start && $0.timestamp <= end }
        let coords = samples.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        guard !coords.isEmpty else { return nil }
        return regionForRoute(coords)
    }

    private func regionForRoute(_ coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let lats = coords.map { $0.latitude }
        let lons = coords.map { $0.longitude }
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            return MKCoordinateRegion()
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.3 + 0.002,
            longitudeDelta: (maxLon - minLon) * 1.3 + 0.002
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private func formatDistance(_ meters: Double) -> String {
        let pref = UserPreferences.distanceMeasurementType.safeValue
        if pref == .miles {
            let miles = meters / 1609.344
            return String(format: "%.2f mi", miles)
        }
        return String(format: "%.2f km", meters / 1000.0)
    }

    private func formatSteps(_ steps: Int?) -> String {
        guard let steps = steps else { return "--" }
        return "\(steps)"
    }

    private func formatElevation(_ meters: Double) -> String {
        let pref = UserPreferences.altitudeMeasurementType.safeValue
        if pref == .feet {
            return String(format: "%.0f ft", meters * 3.28084)
        }
        return String(format: "%.0f m", meters)
    }

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private func formatDate(_ date: Date) -> String {
        Self.shortDateFormatter.string(from: date)
    }
}

// MARK: - Voice Recording Row

struct VoiceRecordingRow: View {
    let index: Int
    let recording: VoiceRecordingInterface
    let transcription: String?
    let isActive: Bool
    let isPlaying: Bool
    let progress: Double
    let currentTime: TimeInterval
    let audioDuration: TimeInterval
    let onTogglePlay: () -> Void
    let onSeek: (Double) -> Void
    let onRetranscribe: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(action: onTogglePlay) {
                    Image(systemName: playIcon)
                        .font(.title2)
                        .foregroundColor(.stone)
                }

                if isActive {
                    playerControls
                } else {
                    compactInfo
                }
            }

            if let transcription = transcription {
                HStack(alignment: .top) {
                    Text(transcription)
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.parchmentTertiary)
                        .cornerRadius(8)

                    Button(action: onRetranscribe) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundColor(.fog)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var playIcon: String {
        if isActive && isPlaying {
            return "pause.circle.fill"
        }
        return "play.circle.fill"
    }

    private var playerControls: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { progress },
                    set: { onSeek($0) }
                ),
                in: 0...1
            )
            .tint(.stone)

            HStack {
                Text(formatSeconds(currentTime))
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                    .monospacedDigit()
                Spacer()
                Text(formatSeconds(audioDuration))
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                    .monospacedDigit()
            }
        }
    }

    private var compactInfo: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Recording \(index)")
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
                Text(formattedDuration)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }

            Spacer()

            Text(formattedTime)
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
        }
    }

    private func formatSeconds(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private var formattedDuration: String {
        formatSeconds(recording.duration)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private var formattedTime: String {
        Self.timeFormatter.string(from: recording.startDate)
    }
}

// MARK: - Audio Player Model

class AudioPlayerModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var currentPath: String?
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var currentTime: TimeInterval = 0
    @Published var totalDuration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?

    func toggle(relativePath: String) {
        if currentPath == relativePath {
            if isPlaying {
                pause()
            } else if player != nil {
                resume()
            }
        } else {
            play(relativePath: relativePath)
        }
    }

    func play(relativePath: String) {
        stopPlayer()

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent(relativePath)

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[AudioPlayerModel] File not found: \(url.path)")
            return
        }

        do {
            AudioSessionCoordinator.shared.activate(for: .playbackOnly, consumer: "audioPlayer")
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.volume = 1.0
            p.prepareToPlay()
            guard p.play() else {
                print("[AudioPlayerModel] play() returned false")
                AudioSessionCoordinator.shared.deactivate(consumer: "audioPlayer")
                return
            }
            player = p
            currentPath = relativePath
            totalDuration = p.duration
            isPlaying = true
            startProgressTimer()
        } catch {
            print("[AudioPlayerModel] Playback error: \(error)")
            AudioSessionCoordinator.shared.deactivate(consumer: "audioPlayer")
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopProgressTimer()
    }

    func resume() {
        guard let p = player else { return }
        p.play()
        isPlaying = true
        startProgressTimer()
    }

    func seek(to fraction: Double) {
        guard let p = player else { return }
        p.currentTime = fraction * p.duration
        updateProgress()
    }

    func stop() {
        stopPlayer()
        AudioSessionCoordinator.shared.deactivate(consumer: "audioPlayer")
    }

    private func stopPlayer() {
        stopProgressTimer()
        player?.delegate = nil
        player?.stop()
        player = nil
        currentPath = nil
        isPlaying = false
        progress = 0
        currentTime = 0
        totalDuration = 0
    }

    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func updateProgress() {
        guard let p = player else { return }
        currentTime = p.currentTime
        totalDuration = p.duration
        progress = p.duration > 0 ? p.currentTime / p.duration : 0
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.stopPlayer()
            AudioSessionCoordinator.shared.deactivate(consumer: "audioPlayer")
        }
    }
}

// MARK: - Summary Card

struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: Constants.UI.Padding.small) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.stone)
            Text(value)
                .font(Constants.Typography.statValue)
                .foregroundColor(.ink)
            Text(title)
                .font(Constants.Typography.statLabel)
                .foregroundColor(.fog)
        }
        .frame(maxWidth: .infinity)
        .padding(Constants.UI.Padding.normal)
        .background(Color.parchmentSecondary)
        .cornerRadius(Constants.UI.CornerRadius.normal)
    }
}
