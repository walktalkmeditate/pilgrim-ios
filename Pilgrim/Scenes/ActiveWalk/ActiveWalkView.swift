import SwiftUI
import CoreLocation

struct ActiveWalkView: View {

    @ObservedObject var viewModel: ActiveWalkViewModel
    var onCancel: (() -> Void)?
    @StateObject private var intentionHistory = IntentionHistoryStore()
    @State private var showStopConfirmation = false
    @State private var showMeditation = false
    @State private var showOptions = false
    @State private var showIntention = false
    @State private var showWaypoint = false
    @State private var showBackConfirmation = false
    @State private var showWaypointFailed = false
    @State private var showWhisperSheet = false
    @State private var showStoneSheet = false
    @State private var tappedCairn: CachedCairn?
    @State private var proximityNotification: ProximityNotificationEvent?
    @State private var hasCheckedAutoIntention = false
    @State private var weatherGreeting: String?
    @State private var celestialGreeting: String?
    @State private var greetingGeneration = 0
    @State private var celestialGreetingGeneration = 0
    @State private var celestialSnapshot: CelestialSnapshot?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isLargeText: Bool {
        dynamicTypeSize >= .accessibility2
    }

    private var mapHeightFraction: CGFloat {
        isLargeText ? 0.35 : 0.6
    }

    private var selectedSoundscapeName: String? {
        guard UserPreferences.soundsEnabled.value,
              let id = UserPreferences.selectedSoundscapeId.value else { return nil }
        return AudioManifestService.shared.asset(byId: id)?.displayName
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                WeatherOverlayView(condition: viewModel.weatherSnapshot?.condition)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    ZStack(alignment: .bottom) {
                        mapSection(height: geometry.size.height * mapHeightFraction)
                        LinearGradient(
                            colors: [.clear, .parchment],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 40)

                        HStack {
                            HStack(spacing: 6) {
                                if SoundscapePlayer.shared.isPlaying || SoundscapePlayer.shared.isMuted {
                                    audioIndicator(
                                        icon: SoundscapePlayer.shared.isMuted ? "speaker.slash" : "speaker.wave.2"
                                    ) {
                                        SoundscapePlayer.shared.toggleMute()
                                    }
                                }
                                if viewModel.voiceGuidePackName != nil {
                                    audioIndicator(
                                        icon: viewModel.voiceGuideManagement.isPaused ? "play.circle" : "pause.circle"
                                    ) {
                                        if viewModel.voiceGuideManagement.isPaused {
                                            viewModel.voiceGuideManagement.resumeGuide()
                                        } else {
                                            viewModel.voiceGuideManagement.pauseGuide()
                                        }
                                    }
                                }
                            }

                            Spacer()

                            HStack(spacing: 6) {
                                if let celestialSnapshot, UserPreferences.celestialAwarenessEnabled.value {
                                    CelestialVignetteView(snapshot: celestialSnapshot)
                                }
                                WeatherVignetteView(
                                    snapshot: viewModel.weatherSnapshot,
                                    imperial: UserPreferences.distanceMeasurementType.safeValue == .miles
                                )
                            }
                        }
                        .padding(.horizontal, Constants.UI.Padding.normal)
                        .padding(.bottom, 48)

                        if viewModel.paceHistory.filter({ $0 > 0 }).count > 10 {
                            LivePaceSparklineView(values: viewModel.paceHistory)
                                .frame(height: 28)
                                .padding(.horizontal, Constants.UI.Padding.big)
                                .transition(.opacity)
                        }

                        VStack(spacing: 4) {
                            if let weatherGreeting {
                                Text(weatherGreeting)
                                    .font(Constants.Typography.body.italic())
                                    .foregroundColor(.ink.opacity(0.5))
                                    .multilineTextAlignment(.center)
                                    .transition(.opacity)
                                    .allowsHitTesting(false)
                            }
                            if let celestialGreeting {
                                Text(celestialGreeting)
                                    .font(Constants.Typography.body.italic())
                                    .foregroundColor(.ink.opacity(0.5))
                                    .multilineTextAlignment(.center)
                                    .transition(.opacity)
                                    .allowsHitTesting(false)
                            }
                        }
                    }

                    statsSection
                    Spacer(minLength: 0)
                    controlsSection
                }

                mapOverlayButtons
            }
        }
        .background(Color.parchment)
        .ignoresSafeArea(edges: .top)
        .onChange(of: viewModel.weatherSnapshot?.condition) { _, condition in
            guard let condition, weatherGreeting == nil,
                  viewModel.status == .recording else { return }
            let greeting: String
            switch condition {
            case .clear: greeting = "A clear day for wandering"
            case .partlyCloudy: greeting = "Walking under shifting skies"
            case .overcast: greeting = "Soft light on the path"
            case .lightRain: greeting = "Walking into the rain"
            case .heavyRain: greeting = "The sky walks with you"
            case .thunderstorm: greeting = "Thunder on the horizon"
            case .snow: greeting = "Snow on the path"
            case .fog: greeting = "Walking into the mist"
            case .wind: greeting = "The wind at your back"
            case .haze: greeting = "A hazy veil over the world"
            }
            greetingGeneration += 1
            let gen = greetingGeneration
            withAnimation(.easeIn(duration: 0.8)) { weatherGreeting = greeting }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                guard greetingGeneration == gen else { return }
                withAnimation(.easeOut(duration: 1.0)) { weatherGreeting = nil }
            }
        }
        .onChange(of: viewModel.status) { _, newStatus in
            guard newStatus == .recording else { return }
            if let condition = viewModel.weatherSnapshot?.condition, weatherGreeting == nil {
                let greeting: String
                switch condition {
                case .clear: greeting = "A clear day for wandering"
                case .partlyCloudy: greeting = "Walking under shifting skies"
                case .overcast: greeting = "Soft light on the path"
                case .lightRain: greeting = "Walking into the rain"
                case .heavyRain: greeting = "The sky walks with you"
                case .thunderstorm: greeting = "Thunder on the horizon"
                case .snow: greeting = "Snow on the path"
                case .fog: greeting = "Walking into the mist"
                case .wind: greeting = "The wind at your back"
                case .haze: greeting = "A hazy veil over the world"
                }
                greetingGeneration += 1
                let gen = greetingGeneration
                withAnimation(.easeIn(duration: 0.8)) { weatherGreeting = greeting }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                    guard greetingGeneration == gen else { return }
                    withAnimation(.easeOut(duration: 1.0)) { weatherGreeting = nil }
                }
            }
            if let snapshot = celestialSnapshot {
                showCelestialGreeting(snapshot: snapshot)
            }
        }
        .alert("End Walk?", isPresented: $showStopConfirmation) {
            Button("End Walk", role: .destructive) { viewModel.stop() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will save your walk and show the summary.")
        }
        .alert("Leave Walk?", isPresented: $showBackConfirmation) {
            Button("Leave", role: .destructive) { onCancel?() }
            Button("Stay", role: .cancel) {}
        } message: {
            Text("This walk will not be saved.")
        }
        .fullScreenCover(isPresented: $showMeditation) {
            MeditationView(soundManagement: viewModel.soundManagement) {
                viewModel.endMeditationSilently()
                showMeditation = false
            }
        }
        .sheet(isPresented: $showOptions) {
            WalkOptionsSheet(
                isRecording: viewModel.status.isActiveStatus,
                onSetIntention: {
                    showOptions = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showIntention = true
                    }
                },
                onDropWaypoint: {
                    showOptions = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showWaypoint = true
                    }
                },
                currentIntention: viewModel.intention,
                waypointCount: viewModel.waypoints.count,
                canPlaceWhisper: viewModel.canPlaceWhisper,
                isWhisperUnlocked: viewModel.isWhisperUnlocked,
                whispersRemaining: 7 - viewModel.whispersPlacedThisWalk,
                onLeaveWhisper: {
                    showOptions = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showWhisperSheet = true
                    }
                },
                canPlaceStone: viewModel.canPlaceStone,
                isStoneUnlocked: viewModel.isStoneUnlocked,
                onPlaceStone: {
                    showOptions = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showStoneSheet = true
                    }
                },
                soundscapeName: selectedSoundscapeName,
                isSoundscapePlaying: SoundscapePlayer.shared.isPlaying,
                onToggleSoundscape: { viewModel.soundManagement.toggleSoundscape() },
                onSelectSoundscape: { scapeId in
                    UserPreferences.selectedSoundscapeId.value = scapeId
                    if let asset = AudioManifestService.shared.asset(byId: scapeId),
                       AudioFileStore.shared.isAvailable(asset) {
                        SoundscapePlayer.shared.play(asset, volume: Float(UserPreferences.soundscapeVolume.value))
                    }
                },
                voiceGuidePackName: viewModel.voiceGuidePackName,
                isVoiceGuidePaused: viewModel.isVoiceGuidePaused,
                hasLastPrompt: viewModel.voiceGuideManagement.hasLastPrompt,
                onToggleVoiceGuide: {
                    if viewModel.voiceGuideManagement.isPaused {
                        viewModel.voiceGuideManagement.resumeGuide()
                    } else {
                        viewModel.voiceGuideManagement.pauseGuide()
                    }
                },
                onSelectVoiceGuide: { packId in
                    UserPreferences.selectedVoiceGuidePackId.value = packId
                    if let pack = VoiceGuideManifestService.shared.pack(byId: packId),
                       VoiceGuideFileStore.shared.isPackDownloaded(pack) {
                        viewModel.voiceGuideManagement.startGuiding(pack: pack)
                    }
                },
                onReplayPrompt: { viewModel.voiceGuideManagement.replayLastPrompt() }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.parchment.opacity(0.95))
        }
        .sheet(isPresented: $showIntention) {
            IntentionSettingView(
                historyStore: intentionHistory,
                onSet: { intention in
                    viewModel.intention = intention
                    showIntention = false
                },
                onDismiss: { showIntention = false }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.parchment.opacity(0.95))
        }
        .sheet(isPresented: $showWaypoint) {
            WaypointMarkingSheet(
                onMark: { label, icon in
                    let success = viewModel.addWaypoint(label: label, icon: icon)
                    showWaypoint = false
                    if !success {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showWaypointFailed = true
                        }
                    }
                },
                onDismiss: { showWaypoint = false }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.parchment.opacity(0.95))
        }
        .sheet(isPresented: $showWhisperSheet) {
            WhisperPlacementSheet(
                currentLocation: viewModel.currentLocation,
                onPlace: { whisper, expiry in
                    showWhisperSheet = false
                    placeWhisper(whisper: whisper, expiry: expiry)
                },
                onDismiss: { showWhisperSheet = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.parchment.opacity(0.95))
        }
        .sheet(isPresented: $showStoneSheet) {
            StonePlacementSheet(
                currentLocation: viewModel.currentLocation,
                nearbyCairn: nearestCachedCairn(),
                onPlace: {
                    showStoneSheet = false
                    placeStone()
                },
                onDismiss: { showStoneSheet = false }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.parchment.opacity(0.95))
        }
        .sheet(item: $tappedCairn) { cairn in
            VStack(spacing: Constants.UI.Padding.normal) {
                CairnDetailView(cairn: cairn, canPlaceStone: false, onPlaceStone: nil)
            }
            .padding(Constants.UI.Padding.big)
            .presentationDetents([.fraction(0.35)])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.parchment.opacity(0.95))
        }
        .proximityNotification(event: $proximityNotification)
        .onReceive(viewModel.proximityService.proximityEvents) { event in
            handleProximityEvent(event)
        }
        .alert("Location Unavailable", isPresented: $showWaypointFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Waiting for a GPS fix. Try again in a moment.")
        }
        .alert("Microphone Required", isPresented: $viewModel.showMicrophonePermissionNeeded) {
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pilgrim needs microphone access to record reflections. Please enable it in Settings.")
        }
        .onAppear {
            guard !hasCheckedAutoIntention else { return }
            hasCheckedAutoIntention = true
            if UserPreferences.beginWithIntention.value && viewModel.intention == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showIntention = true
                }
            }
            if UserPreferences.celestialAwarenessEnabled.value {
                let system = ZodiacSystem(rawValue: UserPreferences.zodiacSystem.value) ?? .tropical
                celestialSnapshot = CelestialCalculator.snapshot(for: Date(), system: system)
            }
            if !WhisperPlayer.shared.allDownloaded {
                WhisperPlayer.shared.downloadAll()
            }
        }
    }

    // MARK: - Map Overlay Buttons

    private var mapOverlayButtons: some View {
        HStack {
            Button { showOptions = true } label: {
                ZStack {
                    Circle()
                        .fill(Color.stone.opacity(0.15))
                        .frame(width: 36, height: 36)
                        .phaseAnimator([false, true]) { content, phase in
                            content
                                .scaleEffect(phase ? 1.8 : 1.0)
                                .opacity(phase ? 0 : 0.5)
                        } animation: { _ in .easeInOut(duration: 2.0) }

                    Image(systemName: "ellipsis")
                        .font(.body.weight(.medium))
                        .foregroundColor(.ink)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
            }

            Spacer()

            Button { showBackConfirmation = true } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.ink)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, Constants.UI.Padding.normal)
        .padding(.top, 56)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let mapVisibilityRadius: CLLocationDistance = 2000
    private static let maxVisiblePins = 30
    private static let minPinSeparation: CLLocationDistance = 15

    private func mapSection(height: CGFloat) -> some View {
        let waypointPins = viewModel.waypoints.map { wp in
            PilgrimAnnotation(
                coordinate: CLLocationCoordinate2D(latitude: wp.latitude, longitude: wp.longitude),
                kind: .waypoint(label: wp.label, icon: wp.icon)
            )
        }
        return PilgrimMapView(
            showsUserLocation: true,
            followsUserLocation: true,
            routeSegments: viewModel.routeSegments,
            pinAnnotations: waypointPins + proximityAnnotations(),
            onAnnotationTap: { annotation in
                handleAnnotationTap(annotation)
            }
        )
        .frame(height: height)
    }

    private func proximityAnnotations() -> [PilgrimAnnotation] {
        guard let loc = viewModel.currentLocation else { return [] }
        let userLoc = CLLocation(latitude: loc.latitude, longitude: loc.longitude)

        struct Candidate {
            let annotation: PilgrimAnnotation
            let distance: CLLocationDistance
        }

        var candidates: [Candidate] = []

        for whisper in GeoCacheService.shared.cachedWhispers {
            let dist = userLoc.distance(from: CLLocation(latitude: whisper.latitude, longitude: whisper.longitude))
            guard dist <= Self.mapVisibilityRadius else { continue }
            guard let cat = whisper.resolvedCategory else { continue }
            let isNearby = dist <= ProximityDetectionService.whisperRadius
            let annotation = PilgrimAnnotation(
                coordinate: CLLocationCoordinate2D(latitude: whisper.latitude, longitude: whisper.longitude),
                kind: .whisper(categoryColor: cat.borderColor, isNearby: isNearby)
            )
            candidates.append(Candidate(annotation: annotation, distance: dist))
        }

        for cairn in GeoCacheService.shared.cachedCairns {
            let dist = userLoc.distance(from: CLLocation(latitude: cairn.latitude, longitude: cairn.longitude))
            guard dist <= Self.mapVisibilityRadius else { continue }
            let annotation = PilgrimAnnotation(
                coordinate: CLLocationCoordinate2D(latitude: cairn.latitude, longitude: cairn.longitude),
                kind: .cairn(stoneCount: cairn.stoneCount, tier: cairn.tier)
            )
            candidates.append(Candidate(annotation: annotation, distance: dist))
        }

        candidates.sort { $0.distance < $1.distance }

        var accepted: [(annotation: PilgrimAnnotation, lat: Double, lon: Double)] = []
        for candidate in candidates {
            guard accepted.count < Self.maxVisiblePins else { break }
            let cLat = candidate.annotation.coordinate.latitude
            let cLon = candidate.annotation.coordinate.longitude
            let tooClose = accepted.contains { a in
                let dLat = (a.lat - cLat) * 111_000
                let dLon = (a.lon - cLon) * 111_000 * cos(cLat * .pi / 180)
                return (dLat * dLat + dLon * dLon) < Self.minPinSeparation * Self.minPinSeparation
            }
            if !tooClose {
                accepted.append((candidate.annotation, cLat, cLon))
            }
        }

        return accepted.map(\.annotation)
    }

    private var statsSection: some View {
        VStack(spacing: isLargeText ? Constants.UI.Padding.small : Constants.UI.Padding.normal) {
            VStack(spacing: 4) {
                Text(viewModel.duration)
                    .font(Constants.Typography.timer)
                    .foregroundColor(.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text(viewModel.intention ?? "every step is enough")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog.opacity(0.6))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
            }
            .animation(.easeInOut(duration: 0.5), value: viewModel.currentSoundscapeName)

            HStack(spacing: Constants.UI.Padding.big) {
                StatItem(label: "Distance", value: viewModel.distance)
                StatItem(label: "Steps", value: viewModel.steps)
                StatItem(label: "Ascent", value: viewModel.ascent)
            }
            .minimumScaleFactor(0.6)

            HStack(spacing: isLargeText ? Constants.UI.Padding.small : Constants.UI.Padding.big) {
                TimeMetricItem(label: "Walk", value: viewModel.walkTime, icon: "figure.walk",
                               isActive: !viewModel.isRecordingVoice && !viewModel.isMeditating)
                TimeMetricItem(label: "Talk", value: viewModel.talkTime, icon: "waveform",
                               isActive: viewModel.isRecordingVoice)
                TimeMetricItem(label: "Meditate", value: viewModel.meditateTime, icon: "brain.head.profile",
                               isActive: viewModel.isMeditating)
            }
            .minimumScaleFactor(0.5)
        }
        .padding(.vertical, isLargeText ? Constants.UI.Padding.small : Constants.UI.Padding.normal)
        .padding(.horizontal, Constants.UI.Padding.normal)
    }

    private var micButton: some View {
        let isActive = viewModel.isRecordingVoice
        let size: CGFloat = isLargeText ? 80 : 72
        return Button(action: { viewModel.toggleVoiceRecording() }) {
            VStack(spacing: isLargeText ? 2 : 6) {
                if isActive {
                    AudioWaveformView(level: viewModel.audioLevel)
                        .frame(width: 36, height: 24)
                } else {
                    Image(systemName: "mic")
                        .font(isLargeText ? .body : .title2)
                        .frame(height: isLargeText ? 20 : 24)
                }
                Text(isActive ? "Stop" : "Record")
                    .font(Constants.Typography.caption)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .foregroundColor(.rust)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(Color.rust.opacity(isActive ? 0.15 : 0.06))
            )
            .background(
                Circle()
                    .stroke(Color.rust, lineWidth: isActive ? 2.5 : 1.5)
            )
        }
        .animation(.easeInOut(duration: 0.3), value: isActive)
    }

    private var controlsSection: some View {
        HStack(spacing: Constants.UI.Padding.big) {
            switch viewModel.status {
            case .waiting:
                SwiftUI.ProgressView()
                    .tint(.stone)
                    .frame(maxWidth: .infinity)
            case .ready:
                actionButton("Start", systemImage: "play.fill", color: .moss, isFilled: true) {
                    viewModel.startRecording()
                }
            case .recording, .paused, .autoPaused:
                actionButton("Meditate", systemImage: "brain.head.profile", color: .dawn) {
                    viewModel.startMeditation()
                    showMeditation = true
                }
                micButton
                actionButton("End", systemImage: "stop.fill", color: .fog) {
                    showStopConfirmation = true
                }
            }
        }
        .padding(Constants.UI.Padding.normal)
        .padding(.bottom, Constants.UI.Padding.normal)
    }

    private func showCelestialGreeting(snapshot: CelestialSnapshot) {
        var greeting: String?

        if let marker = snapshot.seasonalMarker {
            if let sunPos = snapshot.position(for: .sun) {
                let sign = snapshot.system == .tropical ? sunPos.tropical.sign : sunPos.sidereal.sign
                greeting = "The Sun enters \(sign.name) today \u{2014} \(marker.name)"
            }
        } else if let planet = snapshot.retrogradePlanets.first {
            greeting = "\(planet.name) turns inward"
        } else if let moonPos = snapshot.position(for: .moon) {
            let sign = snapshot.system == .tropical ? moonPos.tropical.sign : moonPos.sidereal.sign
            greeting = "The Moon moves through \(sign.name)"
        }

        let hourGreeting = "Walking in the Hour of \(snapshot.planetaryHour.planet.name)"

        let chosen = greeting ?? hourGreeting

        celestialGreetingGeneration += 1
        let gen = celestialGreetingGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            guard celestialGreetingGeneration == gen else { return }
            withAnimation(.easeIn(duration: 0.8)) { celestialGreeting = chosen }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                guard celestialGreetingGeneration == gen else { return }
                withAnimation(.easeOut(duration: 1.0)) { celestialGreeting = nil }
            }
        }
    }

    private func audioIndicator(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(.ink)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.parchmentSecondary)
                        .shadow(color: .ink.opacity(0.08), radius: 4, y: 2)
                )
        }
    }

    private func actionButton(_ title: String, systemImage: String, color: Color, isFilled: Bool = false, action: @escaping () -> Void) -> some View {
        let size: CGFloat = isLargeText ? 80 : 72
        return Button(action: action) {
            VStack(spacing: isLargeText ? 2 : 6) {
                Image(systemName: systemImage)
                    .font(isLargeText ? .body : .title2)
                    .frame(height: isLargeText ? 20 : 24)
                Text(title)
                    .font(Constants.Typography.caption)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .foregroundColor(color)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(color.opacity(isFilled ? 0.12 : 0.06))
            )
            .background(
                Circle()
                    .stroke(color, lineWidth: 1.5)
            )
        }
    }
}

struct TimeMetricItem: View {
    let label: String
    let value: String
    let icon: String
    var isActive: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(isActive ? .rust : .stone)
            Text(value)
                .font(Constants.Typography.statValue)
                .foregroundColor(.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(Constants.Typography.statLabel)
                .foregroundColor(.fog)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

struct LivePaceSparklineView: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let filtered = values.filter { $0 > 0 }
            if filtered.count > 1 {
                let maxVal = filtered.max() ?? 1
                let minVal = filtered.min() ?? 0
                let range = max(maxVal - minVal, 0.5)

                Path { path in
                    for (i, val) in filtered.enumerated() {
                        let x = geo.size.width * CGFloat(i) / CGFloat(filtered.count - 1)
                        let normalized = (val - minVal) / range
                        let y = geo.size.height * (1 - CGFloat(normalized))
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.stone.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

struct StatItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Constants.Typography.statValue)
                .foregroundColor(.ink)
            Text(label)
                .font(Constants.Typography.statLabel)
                .foregroundColor(.fog)
        }
        .frame(maxWidth: .infinity)
    }
}

struct AudioWaveformView: View {

    let level: Float

    private let barCount = 5
    private let barWeights: [Float] = [0.6, 0.8, 1.0, 0.8, 0.6]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.rust)
                    .frame(width: 4, height: barHeight(for: index))
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let weight = CGFloat(barWeights[index])
        let amplitude = CGFloat(level) * weight
        let minHeight: CGFloat = 4
        let maxHeight: CGFloat = 24
        return minHeight + amplitude * (maxHeight - minHeight)
    }
}

// MARK: - Whisper & Stone Actions

extension ActiveWalkView {

    private func placeWhisper(whisper: WhisperDefinition, expiry: KanjiExpiryPicker.ExpiryDuration) {
        guard let location = viewModel.currentLocation else { return }

        HapticPattern.whisperPlaced.fire()

        Task {
            do {
                _ = try await WhisperService.placeWhisper(
                    latitude: location.latitude,
                    longitude: location.longitude,
                    whisperId: whisper.id,
                    category: whisper.category.rawValue,
                    expiryOption: expiry.apiValue
                )
                await MainActor.run {
                    viewModel.whispersPlacedThisWalk += 1
                    let expiryDate = Self.isoFormatter.string(from: Date().addingTimeInterval(TimeInterval(expiry.days * 86400)))
                    GeoCacheService.shared.cachedWhispers.append(CachedWhisper(
                        id: UUID().uuidString,
                        latitude: location.latitude,
                        longitude: location.longitude,
                        whisperId: whisper.id,
                        category: whisper.category.rawValue,
                        expiresAt: expiryDate
                    ))
                }
            } catch {
                print("[ActiveWalk] Whisper placement failed: \(error)")
            }
        }
    }

    private func placeStone() {
        guard let location = viewModel.currentLocation else { return }

        let cairn = nearestCachedCairn()
        let tier = cairn?.tier.soundTier ?? 1
        HapticPattern.stonePlaced(tier: tier).fire()

        Task {
            do {
                let result = try await CairnService.placeStone(
                    latitude: location.latitude,
                    longitude: location.longitude
                )
                await MainActor.run {
                    viewModel.stonePlacedThisWalk = true
                    StonePlayer.shared.playForCount(result.stoneCount)
                    if let idx = GeoCacheService.shared.cachedCairns.firstIndex(where: { $0.id == result.id }) {
                        let old = GeoCacheService.shared.cachedCairns[idx]
                        GeoCacheService.shared.cachedCairns[idx] = CachedCairn(
                            id: old.id,
                            latitude: old.latitude,
                            longitude: old.longitude,
                            stoneCount: result.stoneCount,
                            lastPlacedAt: old.lastPlacedAt
                        )
                    }
                }
            } catch {
                print("[ActiveWalk] Stone placement failed: \(error)")
            }
        }
    }

    private func nearestCachedCairn() -> CachedCairn? {
        guard let location = viewModel.currentLocation else { return nil }
        let userLoc = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let maxMergeDistance: CLLocationDistance = 50
        return GeoCacheService.shared.cachedCairns
            .compactMap { cairn -> (CachedCairn, CLLocationDistance)? in
                let dist = userLoc.distance(from: CLLocation(latitude: cairn.latitude, longitude: cairn.longitude))
                return dist <= maxMergeDistance ? (cairn, dist) : nil
            }
            .min(by: { $0.1 < $1.1 })
            .map(\.0)
    }

    private func handleAnnotationTap(_ annotation: PilgrimAnnotation) {
        switch annotation.kind {
        case .whisper:
            let coord = annotation.coordinate
            if let cached = GeoCacheService.shared.cachedWhispers.first(where: {
                abs($0.latitude - coord.latitude) < 0.0001 && abs($0.longitude - coord.longitude) < 0.0001
            }),
               let definition = WhisperCatalog.whisper(byId: cached.whisperId) {
                WhisperPlayer.shared.play(definition)
                HapticPattern.whisperProximity.fire()
            }
        case .cairn:
            let coord = annotation.coordinate
            if let cached = GeoCacheService.shared.cachedCairns.first(where: {
                abs($0.latitude - coord.latitude) < 0.0001 && abs($0.longitude - coord.longitude) < 0.0001
            }) {
                tappedCairn = cached
            }
        default:
            break
        }
    }

    private func handleProximityEvent(_ event: ProximityEvent) {
        guard event.direction == .entered else { return }

        switch event.target.type {
        case .whisper:
            let whisperId = event.target.id.replacingOccurrences(of: "whisper-", with: "")
            viewModel.encounteredWhisperIDs.insert(whisperId)
            proximityNotification = .whisper()
            HapticPattern.whisperProximity.fire()

            if UserPreferences.autoPlayWhisperOnProximity.value,
               UserPreferences.soundsEnabled.value {
                if let cached = GeoCacheService.shared.cachedWhispers.first(where: { $0.id == whisperId }),
                   let definition = WhisperCatalog.whisper(byId: cached.whisperId) {
                    WhisperPlayer.shared.play(definition)
                }
            }

        case .cairn:
            let cairnId = event.target.id.replacingOccurrences(of: "cairn-", with: "")
            viewModel.encounteredCairnIDs.insert(cairnId)
            if let cached = GeoCacheService.shared.cachedCairns.first(where: { $0.id == cairnId }) {
                proximityNotification = .cairn(stoneCount: cached.stoneCount)
            } else {
                proximityNotification = .cairn(stoneCount: 1)
            }
            HapticPattern.cairnProximity.fire()
        }
    }
}

