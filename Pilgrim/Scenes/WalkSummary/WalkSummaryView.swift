import SwiftUI
import AVFoundation
import CoreStore
import CoreLocation

struct WalkSummaryView: View {

    let walk: WalkInterface
    @Environment(\.dismiss) private var dismiss
    @StateObject private var audioPlayer = AudioPlayerModel()
    @ObservedObject private var transcriptionService = TranscriptionService.shared
    @State private var transcriptions: [UUID: String] = [:]
    @State private var selectedFavicon: WalkFavicon?
    @State private var showPrompts = false
    @State private var deletedPaths: Set<String> = []
    @State private var pathToDelete: String?
    @State private var showDeleteConfirmation = false
    @State private var waveforms: [UUID: [Float]] = [:]
    init(walk: WalkInterface) {
        self.walk = walk
        _selectedFavicon = State(initialValue: walk.favicon.flatMap { WalkFavicon(rawValue: $0) })
        _cachedSegments = State(initialValue: Self.computeSegments(for: walk))
        _cachedAnnotations = State(initialValue: Self.computeAnnotations(for: walk))
    }
    @State private var cameraBounds: MapCameraBounds?
    @State private var cameraCenter: CLLocationCoordinate2D?
    @State private var cameraZoom: CGFloat = 16
    @State private var cameraDuration: TimeInterval = 0.4
    @State private var cachedSegments: [RouteSegment] = []
    @State private var cachedAnnotations: [PilgrimAnnotation] = []
    @State private var recentWalkSnippets: [WalkSnippet] = []
    @State private var revealPhase: RevealPhase = .hidden
    @State private var milestone: String?
    @State private var cachedCelestialSnapshot: CelestialSnapshot?

    private enum RevealPhase {
        case hidden, zoomed, revealed
    }

    @State private var animatedDistance: Double = 0

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Constants.UI.Padding.normal) {
                    mapSection
                    intentionCard
                    elevationProfile
                    journeyQuote
                    durationHero
                    if let milestone {
                        milestoneCallout(milestone)
                    }
                    statsRow
                    weatherLine
                    celestialLine
                    timeBreakdown
                    FaviconSelectorView(selection: $selectedFavicon)
                        .onChange(of: selectedFavicon) { _, newValue in
                            guard let uuid = walk.uuid else { return }
                            DataManager.setFavicon(walkID: uuid, favicon: newValue)
                        }
                    activityTimelineBar
                    activityInsights
                    activityList
                    if !walk.voiceRecordings.isEmpty {
                        recordingsSection
                    }
                    promptsButton
                    detailsSection
                    shareCard
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
                recentWalkSnippets = computeRecentWalkSnippets()
                milestone = computeMilestone()
                if UserPreferences.celestialAwarenessEnabled.value {
                    let system = ZodiacSystem(rawValue: UserPreferences.zodiacSystem.value) ?? .tropical
                    cachedCelestialSnapshot = CelestialCalculator.snapshot(for: walk.startDate, system: system)
                }
                startRevealSequence()
                if UserPreferences.autoTranscribe.value && transcriptions.isEmpty {
                    pollForAutoTranscription()
                }
            }
            .onDisappear {
                pollingTask?.cancel()
                pollingTask = nil
            }
            .onChange(of: transcriptionService.state) { _, newState in
                if newState == .completed {
                    reloadTranscriptionsFromDatabase()
                }
            }
            .sheet(isPresented: $showPrompts) {
                NavigationView {
                    PromptListView(walk: walk, transcriptions: transcriptions, recentWalkSnippets: recentWalkSnippets, intention: walk.comment)
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
                    if transcriptions.isEmpty {
                        Text("Reflect on your walk")
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                    } else {
                        Text("\(transcriptions.count) transcription\(transcriptions.count == 1 ? "" : "s") available")
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                    }
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

    private func computeRecentWalkSnippets() -> [WalkSnippet] {
        guard let walks = try? DataManager.dataStack.fetchAll(
            From<Walk>()
                .where(\._startDate < walk.startDate)
                .orderBy(.descending(\._startDate))
                .tweak { $0.fetchLimit = 20 }
        ) else { return [] }

        return walks
            .filter { w in w.voiceRecordings.contains { $0.transcription != nil } }
            .prefix(3)
            .map { w in
                let allText = w.voiceRecordings
                    .compactMap { $0.transcription }
                    .joined(separator: " ")
                let preview = allText.truncatedAtWordBoundary()
                var celestialSummary: String?
                if UserPreferences.celestialAwarenessEnabled.value {
                    let system = ZodiacSystem(rawValue: UserPreferences.zodiacSystem.value) ?? .tropical
                    let snap = CelestialCalculator.snapshot(for: w.startDate, system: system)
                    let sunSign = (system == .tropical ? snap.position(for: .sun)?.tropical : snap.position(for: .sun)?.sidereal)?.sign.name ?? ""
                    let moonSign = (system == .tropical ? snap.position(for: .moon)?.tropical : snap.position(for: .moon)?.sidereal)?.sign.name ?? ""
                    celestialSummary = "Sun in \(sunSign), Moon in \(moonSign)"
                }
                return WalkSnippet(date: w.startDate, placeName: nil, transcriptionPreview: preview, weatherCondition: w.weatherCondition, celestialSummary: celestialSummary)
            }
    }

    private func loadExistingTranscriptions() {
        for recording in walk.voiceRecordings {
            if let uuid = recording.uuid, let text = recording.transcription {
                transcriptions[uuid] = text
            }
        }
    }

    @State private var pollingTask: Task<Void, Never>?

    private func pollForAutoTranscription() {
        pollingTask?.cancel()
        pollingTask = Task {
            for _ in 0..<30 {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                await MainActor.run { reloadTranscriptionsFromDatabase() }
                if !transcriptions.isEmpty { return }
            }
        }
    }

    private func reloadTranscriptionsFromDatabase() {
        guard let walkUUID = walk.uuid else { return }
        guard let dbWalk = try? DataManager.dataStack.fetchOne(
            From<Walk>().where(\._uuid == walkUUID)
        ) else { return }
        for recording in dbWalk.voiceRecordings {
            if let uuid = recording.uuid, let text = recording.transcription {
                transcriptions[uuid] = text
            }
        }
    }

    private var mapSection: some View {
        Group {
            if !routeCoordinates.isEmpty {
                PilgrimMapView(
                    isInteractive: revealPhase == .revealed,
                    showsUserLocation: false,
                    routeSegments: cachedSegments,
                    pinAnnotations: cachedAnnotations,
                    cameraCenter: $cameraCenter,
                    cameraZoom: $cameraZoom,
                    cameraBounds: cameraBounds,
                    cameraDuration: cameraDuration
                )
                .frame(height: 320)
                .mask(
                    RadialGradient(
                        gradient: Gradient(colors: [.white, .white, .white.opacity(0)]),
                        center: .center,
                        startRadius: 80,
                        endRadius: 180
                    )
                )
                .padding(.horizontal, -Constants.UI.Padding.normal)
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

    @ViewBuilder
    private var elevationProfile: some View {
        let samples = walk.routeData
        let altitudes = samples.map { $0.altitude }
        if altitudes.count > 5, let minAlt = altitudes.min(), let maxAlt = altitudes.max(), maxAlt - minAlt > 1 {
            ElevationProfileView(altitudes: altitudes, minAlt: minAlt, maxAlt: maxAlt)
                .frame(height: 48)
                .padding(.horizontal, Constants.UI.Padding.small)
        }
    }

    @ViewBuilder
    private var intentionCard: some View {
        if let intention = walk.comment, !intention.isEmpty {
            VStack(spacing: Constants.UI.Padding.small) {
                Image(systemName: "leaf")
                    .font(.caption)
                    .foregroundColor(.moss)
                Text(intention)
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink)
                    .multilineTextAlignment(.center)
            }
            .padding(Constants.UI.Padding.normal)
            .frame(maxWidth: .infinity)
            .background(Color.moss.opacity(0.06))
            .cornerRadius(Constants.UI.CornerRadius.normal)
        }
    }

    private var journeyQuote: some View {
        Text(generateJourneyQuote())
            .font(Constants.Typography.body)
            .foregroundColor(.fog)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Constants.UI.Padding.big)
            .opacity(revealPhase == .revealed ? 1 : 0)
            .animation(.easeIn(duration: 0.8), value: revealPhase)
    }

    private var durationHero: some View {
        Text(formatDuration(walk.activeDuration))
            .font(Constants.Typography.timer)
            .foregroundColor(.ink)
            .opacity(revealPhase == .hidden ? 0 : 1)
            .animation(.easeIn(duration: 0.6), value: revealPhase)
    }

    private func milestoneCallout(_ text: String) -> some View {
        HStack(spacing: Constants.UI.Padding.small) {
            Image(systemName: "sparkles")
                .foregroundColor(.dawn)
            Text(text)
                .font(Constants.Typography.caption)
                .foregroundColor(.ink)
        }
        .padding(.horizontal, Constants.UI.Padding.normal)
        .padding(.vertical, Constants.UI.Padding.small)
        .background(Color.dawn.opacity(0.1))
        .cornerRadius(Constants.UI.CornerRadius.normal)
        .opacity(revealPhase == .revealed ? 1 : 0)
        .animation(.easeIn(duration: 0.8).delay(0.3), value: revealPhase)
    }

    // MARK: - Reveal Sequence

    private func startRevealSequence() {
        let coords = routeCoordinates
        guard !coords.isEmpty else {
            revealPhase = .revealed
            animatedDistance = walk.distance
            return
        }

        cameraCenter = coords.first
        cameraZoom = 16
        cameraDuration = 0.1
        revealPhase = .zoomed

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            cameraDuration = 2.5
            cameraCenter = nil
            cameraBounds = boundsForRoute(coords)
            withAnimation(.easeInOut(duration: 0.6)) {
                revealPhase = .revealed
            }
            animateDistanceCountUp()
        }
    }

    @State private var distanceAnimationGeneration = 0

    private func animateDistanceCountUp() {
        let target = walk.distance
        let steps = 30
        let interval = 2.0 / Double(steps)
        distanceAnimationGeneration += 1
        let generation = distanceAnimationGeneration
        for i in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(i)) {
                guard generation == distanceAnimationGeneration else { return }
                let progress = Double(i) / Double(steps)
                let eased = progress * progress * (3 - 2 * progress)
                animatedDistance = target * eased
            }
        }
    }

    // MARK: - Journey Quote

    private func generateJourneyQuote() -> String {
        let hasTalk = walk.talkDuration > 0
        let hasMeditation = walk.meditateDuration > 0
        let distanceKm = walk.distance / 1000

        if hasTalk && hasMeditation {
            return "You walked, spoke your mind, and found stillness."
        } else if hasMeditation {
            if distanceKm < 0.1 {
                return "A moment of stillness, right where you are."
            }
            return "A journey inward, \(formatDistance(walk.distance)) along the way."
        } else if hasTalk {
            return "You walked and gave voice to your thoughts."
        } else if distanceKm > 5 {
            return "A long road, well traveled."
        } else if distanceKm > 1 {
            return "Every step, a small arrival."
        } else {
            return "A quiet walk, a gentle return."
        }
    }

    // MARK: - Milestones

    private func computeMilestone() -> String? {
        if UserPreferences.celestialAwarenessEnabled.value {
            let sunLon = CelestialCalculator.solarLongitude(
                T: CelestialCalculator.julianCenturies(from: CelestialCalculator.julianDayNumber(from: walk.startDate)))
            if let marker = CelestialCalculator.seasonalMarker(sunLongitude: sunLon) {
                return "You walked on the \(marker.name)"
            }
        }

        guard let walks = try? DataManager.dataStack.fetchAll(
            From<Walk>()
                .where(\._startDate < walk.startDate)
                .orderBy(.descending(\._startDate))
                .tweak { $0.fetchLimit = 100 }
        ) else { return nil }

        if walk.meditateDuration > 0 {
            let longestPast = walks.map { $0.meditateDuration }.max() ?? 0
            if walk.meditateDuration > longestPast && longestPast > 0 {
                return "Your longest meditation yet"
            }
        }

        if walk.distance > 0 {
            let longestPast = walks.map { $0.distance }.max() ?? 0
            if walk.distance > longestPast && longestPast > 0 {
                return "Your longest walk yet"
            }
        }

        let totalDistance = walks.reduce(0.0) { $0 + $1.distance } + walk.distance
        let isMiles = UserPreferences.distanceMeasurementType.safeValue == .miles
        let totalUnits = Int(totalDistance / (isMiles ? 1609.344 : 1000))
        let pastUnits = Int((totalDistance - walk.distance) / (isMiles ? 1609.344 : 1000))
        let unit = isMiles ? "mi" : "km"
        let milestones = [10, 25, 50, 100, 250, 500, 1000]
        for m in milestones where totalUnits >= m && pastUnits < m {
            return "You've now walked \(m) \(unit) total"
        }
        return nil
    }

    private var statsRow: some View {
        HStack(spacing: Constants.UI.Padding.big) {
            miniStat(label: "Distance", value: formatDistance(animatedDistance))
            if let steps = walk.steps, steps > 0 {
                miniStat(label: "Steps", value: "\(steps)")
            }
            if walk.ascend > 1 {
                miniStat(label: "Elevation", value: formatElevation(walk.ascend))
            }
        }
        .opacity(revealPhase == .revealed ? 1 : 0)
        .animation(.easeIn(duration: 0.6).delay(0.2), value: revealPhase)
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

    @ViewBuilder
    private var weatherLine: some View {
        if let condStr = walk.weatherCondition,
           let cond = WeatherCondition(rawValue: condStr),
           let temp = walk.weatherTemperature {
            let imperial = UserPreferences.distanceMeasurementType.safeValue == .miles
            HStack(spacing: Constants.UI.Padding.xs) {
                Image(systemName: cond.icon)
                    .font(Constants.Typography.caption)
                Text("\(cond.label), \(WeatherSnapshot.formatTemperature(temp, imperial: imperial))")
                    .font(Constants.Typography.caption)
            }
            .foregroundColor(.fog)
            .opacity(revealPhase == .revealed ? 1 : 0)
            .animation(.easeIn(duration: 0.6).delay(0.2), value: revealPhase)
        }
    }

    @ViewBuilder
    private var celestialLine: some View {
        if let snapshot = cachedCelestialSnapshot {
            let moonPos = snapshot.position(for: .moon)
            let zodiac = snapshot.system == .tropical ? moonPos?.tropical : moonPos?.sidereal
            HStack(spacing: Constants.UI.Padding.xs) {
                if let zodiac {
                    Text("Moon in \(zodiac.sign.name)")
                        .font(Constants.Typography.caption)
                }
                Text("Hour of \(snapshot.planetaryHour.planet.name)")
                    .font(Constants.Typography.caption)
                if let dominant = snapshot.elementBalance.dominant {
                    Text("\(dominant.rawValue.capitalized) predominates")
                        .font(Constants.Typography.caption)
                }
            }
            .foregroundColor(.fog)
            .opacity(revealPhase == .revealed ? 1 : 0)
            .animation(.easeIn(duration: 0.6).delay(0.3), value: revealPhase)
        }
    }

    private var timeBreakdown: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: Constants.UI.Padding.normal) {
            SummaryCard(title: "Walk", value: formatDuration(walkDuration), icon: "figure.walk")
            SummaryCard(title: "Talk", value: formatDuration(walk.talkDuration), icon: "waveform")
            SummaryCard(title: "Meditate", value: formatDuration(walk.meditateDuration), icon: "brain.head.profile")
        }
        .opacity(revealPhase == .revealed ? 1 : 0)
        .animation(.easeIn(duration: 0.6).delay(0.4), value: revealPhase)
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
                if let bounds = boundsForTimeRange(start: start, end: end) {
                    withAnimation { cameraBounds = bounds }
                }
            },
            onSegmentDeselected: {
                if routeCoordinates.count > 1 {
                    withAnimation { cameraBounds = boundsForRoute(routeCoordinates) }
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
            autoTranscriptionBanner

            ForEach(Array(walk.voiceRecordings.enumerated()), id: \.element.uuid) { index, recording in
                let isActive = audioPlayer.currentPath == recording.fileRelativePath
                let fileAvailable = isFileAvailable(recording.fileRelativePath)
                VoiceRecordingRow(
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
                    waveformSamples: recording.uuid.flatMap { waveforms[$0] }
                )
                .task {
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
            }
        }
        .padding(Constants.UI.Padding.normal)
        .background(Color.parchmentSecondary)
        .cornerRadius(Constants.UI.CornerRadius.normal)
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
        guard !deletedPaths.contains(relativePath) else { return false }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return FileManager.default.fileExists(atPath: docs.appendingPathComponent(relativePath).path)
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

    private var shareCard: some View {
        WalkSharingButtons(walk: walk)
    }

}

// MARK: - Route Segments & Annotations

extension WalkSummaryView {

    static func computeSegments(for walk: WalkInterface) -> [RouteSegment] {
        let samples = walk.routeData
        guard samples.count > 1 else { return [] }

        var segments: [(type: String, indices: [Int])] = []
        var currentType = activityType(for: samples[0], in: walk)
        var currentIndices = [0]

        for i in 1..<samples.count {
            let type = activityType(for: samples[i], in: walk)
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
            return RouteSegment(coordinates: coords, activityType: segment.type)
        }
    }

    static func computeAnnotations(for walk: WalkInterface) -> [PilgrimAnnotation] {
        var pins: [PilgrimAnnotation] = []

        if let first = walk.routeData.first {
            pins.append(PilgrimAnnotation(coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude), kind: .startPoint))
        }
        if let last = walk.routeData.last, walk.routeData.count > 1 {
            pins.append(PilgrimAnnotation(coordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude), kind: .endPoint))
        }

        let routeSamples = walk.routeData
        for interval in walk.activityIntervals where interval.activityType == .meditation {
            if let closest = routeSamples.min(by: { abs($0.timestamp.timeIntervalSince(interval.startDate)) < abs($1.timestamp.timeIntervalSince(interval.startDate)) }) {
                pins.append(PilgrimAnnotation(coordinate: CLLocationCoordinate2D(latitude: closest.latitude, longitude: closest.longitude), kind: .meditation(duration: interval.duration)))
            }
        }

        for recording in walk.voiceRecordings {
            if let closest = routeSamples.min(by: { abs($0.timestamp.timeIntervalSince(recording.startDate)) < abs($1.timestamp.timeIntervalSince(recording.startDate)) }) {
                pins.append(PilgrimAnnotation(coordinate: CLLocationCoordinate2D(latitude: closest.latitude, longitude: closest.longitude), kind: .voiceRecording(label: "Recording")))
            }
        }

        for waypoint in walk.waypoints {
            pins.append(PilgrimAnnotation(coordinate: CLLocationCoordinate2D(latitude: waypoint.latitude, longitude: waypoint.longitude), kind: .waypoint(label: waypoint.label, icon: waypoint.icon)))
        }

        return pins
    }

    private static func activityType(for sample: RouteDataSampleInterface, in walk: WalkInterface) -> String {
        let timestamp = sample.timestamp
        for interval in walk.activityIntervals where interval.activityType == .meditation {
            if timestamp >= interval.startDate && timestamp <= interval.endDate { return "meditating" }
        }
        for recording in walk.voiceRecordings {
            if timestamp >= recording.startDate && timestamp <= recording.endDate { return "talking" }
        }
        return "walking"
    }


    var routeCoordinates: [CLLocationCoordinate2D] {
        walk.routeData.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    func boundsForTimeRange(start: Date, end: Date) -> MapCameraBounds? {
        let samples = walk.routeData.filter { $0.timestamp >= start && $0.timestamp <= end }
        let coords = samples.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        guard !coords.isEmpty else { return nil }
        return boundsForRoute(coords)
    }

    func boundsForRoute(_ coords: [CLLocationCoordinate2D]) -> MapCameraBounds {
        let lats = coords.map { $0.latitude }
        let lons = coords.map { $0.longitude }
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 0
        let latPad = (maxLat - minLat) * 0.15 + 0.001
        let lonPad = (maxLon - minLon) * 0.15 + 0.001
        return MapCameraBounds(
            sw: CLLocationCoordinate2D(latitude: minLat - latPad, longitude: minLon - lonPad),
            ne: CLLocationCoordinate2D(latitude: maxLat + latPad, longitude: maxLon + lonPad)
        )
    }

    func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    func formatDistance(_ meters: Double) -> String {
        let pref = UserPreferences.distanceMeasurementType.safeValue
        if pref == .miles {
            let miles = meters / 1609.344
            return String(format: "%.2f mi", miles)
        }
        return String(format: "%.2f km", meters / 1000.0)
    }

    func formatSteps(_ steps: Int?) -> String {
        guard let steps = steps else { return "--" }
        return "\(steps)"
    }

    func formatElevation(_ meters: Double) -> String {
        let pref = UserPreferences.altitudeMeasurementType.safeValue
        if pref == .feet {
            return String(format: "%.0f ft", meters * 3.28084)
        }
        return String(format: "%.0f m", meters)
    }

    static var shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    func formatDate(_ date: Date) -> String {
        Self.shortDateFormatter.string(from: date)
    }
}
