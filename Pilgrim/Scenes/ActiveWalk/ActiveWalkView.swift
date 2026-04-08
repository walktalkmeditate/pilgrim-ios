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
    @State private var sheetState: SheetState = .expanded
    @State private var hasInitializedSheetState = false
    @State private var pauseExpandGeneration = 0
    /// Incremented on walk-start transitions to trigger the sheet's
    /// one-time "wink" hint animation teaching the swipe-to-expand
    /// affordance. Observed by `WalkStatsSheet` via `peekHintTrigger`.
    @State private var sheetPeekHintTrigger: Int = 0
    /// Measured height of the minimized sheet, captured via GeometryReader.
    /// Used as the reservation amount for the ambient overlay's bottom
    /// padding so the weather chip / sparkline sit exactly above the sheet
    /// top regardless of content width variations or dynamic type. Seeded
    /// to a sensible default so first-frame layout isn't jarring.
    @State private var measuredMinimizedSheetHeight: CGFloat = 90

    /// Measured height of the expanded sheet, captured via GeometryReader.
    /// Passed to Mapbox as the bottom camera inset so the user's location
    /// puck stays visible above the expanded sheet. Seeded to a sensible
    /// default so the first frame before measurement has a reasonable
    /// camera offset.
    @State private var measuredExpandedSheetHeight: CGFloat = 340

    /// Bottom padding the ambient overlay uses to sit just above the
    /// minimized sheet. Driven by the measured sheet height (not an
    /// estimate) so it's always accurate.
    private var minimizedSheetHeight: CGFloat {
        measuredMinimizedSheetHeight
    }

    /// Bottom padding the map should reserve for the overlay sheet so the
    /// user's location puck doesn't hide underneath it. Driven by the
    /// measured sheet height in both states — no estimates.
    private var mapBottomInset: CGFloat {
        sheetState == .minimized ? measuredMinimizedSheetHeight : measuredExpandedSheetHeight
    }

    private var selectedSoundscapeName: String? {
        guard UserPreferences.soundsEnabled.value,
              let id = UserPreferences.selectedSoundscapeId.value else { return nil }
        return AudioManifestService.shared.asset(byId: id)?.displayName
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full-screen map background (ignores safe area to fill entire screen)
            mapSection()
                .ignoresSafeArea()

            // Weather overlay (full screen, non-interactive, hidden from VO)
            WeatherOverlayView(condition: viewModel.weatherSnapshot?.condition)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            // Top overlay: map option buttons (ellipsis / close)
            topOverlay
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Floating greeting text (anchored to upper third, non-interactive)
            floatingGreetings
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 140)
                .allowsHitTesting(false)

            // Ambient overlay: audio indicators, vignettes, sparkline, gradient.
            // Anchored above the MINIMIZED sheet position. When the sheet is
            // expanded, these elements are covered by the sheet — that's fine,
            // the expanded sheet is the user's focus. When minimized, these
            // elements become visible above it.
            // Hit testing is enabled when the sheet is minimized AND the walk
            // is in an active status (recording or paused). We use
            // `isActiveStatus` here (not `== .recording`) so that during the
            // 800ms pause-debounce window, the audio indicators remain tappable.
            ambientOverlay
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, minimizedSheetHeight)
                .allowsHitTesting(viewModel.status.isActiveStatus && sheetState == .minimized)

            // Bottom sheet with stats and controls
            bottomSheet
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .onPreferenceChange(MinimizedSheetHeightKey.self) { newHeight in
            // Capture the measured height of the minimized sheet chrome
            // (drag handle + stat row). Guarded on current sheetState
            // so a transition-time default-value emission from the
            // preference key doesn't clobber a valid measurement.
            guard sheetState == .minimized else { return }
            measuredMinimizedSheetHeight = newHeight
        }
        .onPreferenceChange(ExpandedSheetHeightKey.self) { newHeight in
            // Capture the expanded sheet's actual rendered height so the
            // Mapbox camera inset matches reality in the expanded state.
            // Same transition-safety guard as above.
            guard sheetState == .expanded else { return }
            measuredExpandedSheetHeight = newHeight
        }
        .onChange(of: viewModel.weatherSnapshot?.condition) { _, condition in
            guard let condition, viewModel.status == .recording else { return }
            triggerWeatherGreeting(for: condition)
        }
        .onChange(of: viewModel.status) { oldStatus, newStatus in
            updateSheetStateForStatus(from: oldStatus, to: newStatus)
            triggerGreetingsIfRecording(newStatus)
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
            .presentationDetents([.medium, .large])
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
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.parchment.opacity(0.95))
        }
        .sheet(isPresented: $showWaypoint) {
            WaypointMarkingSheet(
                onMark: { label, icon in
                    let success = viewModel.addWaypoint(label: label, icon: icon)
                    if success { HapticPattern.waypointDropped.fire() }
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
            CairnDetailView(cairn: cairn, canPlaceStone: false, onPlaceStone: nil)
                .presentationDetents([.medium])
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
            // Seed sheet state from current walk status on FIRST mount only.
            // Guarded so that navigating away (meditation, walk summary) and
            // back doesn't overwrite user manual expansion/collapse.
            // Handles state restoration after app relaunch — .onChange only
            // fires on changes, not on initial values.
            if !hasInitializedSheetState {
                sheetState = (viewModel.status == .recording) ? .minimized : .expanded
                hasInitializedSheetState = true
            }

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

    // MARK: - Body Layers

    /// Top overlay: map option buttons (ellipsis / close).
    /// Pinned to the top safe area.
    private var topOverlay: some View {
        mapOverlayButtons
    }

    /// Floating greeting text, anchored to the middle of the screen.
    /// Non-interactive passthrough. Hidden from VoiceOver — ambient text.
    private var floatingGreetings: some View {
        VStack(spacing: Constants.UI.Padding.small) {
            if let weatherGreeting {
                Text(weatherGreeting)
                    .font(Constants.Typography.body.italic())
                    .foregroundColor(.ink.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
            if let celestialGreeting {
                Text(celestialGreeting)
                    .font(Constants.Typography.body.italic())
                    .foregroundColor(.ink.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .accessibilityHidden(true)
    }

    /// Ambient elements above the sheet: audio indicators, vignettes,
    /// sparkline, gradient fade. Positioned at a fixed offset from the bottom
    /// (above the minimized sheet height). When the sheet expands, these
    /// elements are covered — not moved.
    private var ambientOverlay: some View {
        VStack(spacing: 0) {
            // Audio indicators and weather/celestial vignettes row
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
            .padding(.bottom, Constants.UI.Padding.xs)

            // Pace sparkline slot — reserved height prevents layout jump
            // (hidden from VoiceOver — ambient visual)
            Group {
                if viewModel.paceHistory.filter({ $0 > 0 }).count > 10 {
                    LivePaceSparklineView(values: viewModel.paceHistory)
                        .padding(.horizontal, Constants.UI.Padding.big)
                        .transition(.opacity)
                }
            }
            .frame(height: 24)
            .padding(.bottom, Constants.UI.Padding.xs)
            .accessibilityHidden(true)

            // Gradient fade into the parchment sheet (only visible when sheet
            // is minimized — when expanded, sheet covers the gradient).
            // Kept small so the ambient content sits close to the sheet top
            // instead of floating high up the map.
            LinearGradient(
                colors: [.clear, .parchment],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 20)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// The stats sheet itself — collapsible state-aware. Visually a floating
    /// card with rounded top corners and a soft shadow above. The parchment
    /// background extends through the bottom safe area so the sheet reads
    /// as attached to the bottom edge.
    private var bottomSheet: some View {
        WalkStatsSheet(
            state: $sheetState,
            viewModel: viewModel,
            onStartMeditation: {
                viewModel.startMeditation()
                showMeditation = true
            },
            onRequestEndWalk: {
                showStopConfirmation = true
            },
            peekHintTrigger: sheetPeekHintTrigger
        )
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 20,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 20,
                style: .continuous
            )
            .fill(Color.parchment)
            // .compositingGroup() ensures the shadow is computed from the
            // composed shape once, preventing a "pop" during sheet resize
            // animations where the shape geometry changes frame-by-frame.
            .compositingGroup()
            .shadow(color: .ink.opacity(0.15), radius: 12, y: -4)
            .ignoresSafeArea(edges: .bottom)
        )
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
        .padding(.top, Constants.UI.Padding.small)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let mapVisibilityRadius: CLLocationDistance = 2000
    private static let maxVisiblePins = 30
    private static let minPinSeparation: CLLocationDistance = 15

    private func mapSection() -> some View {
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
            },
            bottomInset: mapBottomInset
        )
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
            let isSameType: (PilgrimAnnotation.Kind, PilgrimAnnotation.Kind) -> Bool = { a, b in
                switch (a, b) {
                case (.whisper, .whisper), (.cairn, .cairn): return true
                default: return false
                }
            }
            let tooClose = accepted.contains { a in
                guard isSameType(a.annotation.kind, candidate.annotation.kind) else { return false }
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

    // MARK: - Status Change Handlers

    /// Updates the sheet state in response to walk status changes.
    /// Pause/autoPause auto-expand is debounced ~800ms to avoid thrashing
    /// during brief GPS flaps that cause rapid .recording ↔ .autoPaused cycles.
    /// Fires a soft handoff haptic when the walk first begins (.ready → .recording)
    /// but not on pause-resume, so GPS flaps don't buzz the wrist every few seconds.
    private func updateSheetStateForStatus(from oldStatus: WalkBuilder.Status, to newStatus: WalkBuilder.Status) {
        switch newStatus {
        case .recording:
            // Cancel any pending auto-expand from a previous pause
            pauseExpandGeneration += 1
            sheetState = .minimized
            // Handoff haptic + peek hint — only on the initial walk-start
            // transition, not on resume-from-pause or GPS-flap recovery.
            // The peek teaches the swipe-to-expand affordance once per
            // walk start, tied to the same moment as the haptic.
            if oldStatus == .ready || oldStatus == .waiting {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                sheetPeekHintTrigger += 1
            }
        case .paused, .autoPaused:
            // Debounce: only auto-expand if the pause persists for 800ms.
            pauseExpandGeneration += 1
            let gen = pauseExpandGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard pauseExpandGeneration == gen else { return }
                // Check status hasn't flipped back to recording in the meantime
                guard viewModel.status == .paused || viewModel.status == .autoPaused else { return }
                sheetState = .expanded
            }
        case .waiting, .ready:
            pauseExpandGeneration += 1
            sheetState = .expanded
        }
    }

    /// Triggers weather and celestial greetings when walk enters recording state.
    private func triggerGreetingsIfRecording(_ newStatus: WalkBuilder.Status) {
        guard newStatus == .recording else { return }
        if let condition = viewModel.weatherSnapshot?.condition {
            triggerWeatherGreeting(for: condition)
        }
        if let snapshot = celestialSnapshot {
            showCelestialGreeting(snapshot: snapshot)
        }
    }

    /// Fades in a brief weather greeting text and auto-dismisses after ~3.5s.
    /// Guarded to only fire when a greeting isn't already showing.
    private func triggerWeatherGreeting(for condition: WeatherCondition) {
        guard weatherGreeting == nil else { return }
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
                    WhisperPlayer.shared.play(whisper)
                    let localId = UUID().uuidString
                    let expiryDate = Self.isoFormatter.string(from: Date().addingTimeInterval(TimeInterval(expiry.days * 86400)))
                    GeoCacheService.shared.cachedWhispers.append(CachedWhisper(
                        id: localId,
                        latitude: location.latitude,
                        longitude: location.longitude,
                        whisperId: whisper.id,
                        category: whisper.category.rawValue,
                        expiresAt: expiryDate
                    ))
                    viewModel.proximityService.suppressTarget(id: "whisper-\(localId)")
                    GeoCacheService.shared.persistCurrentWhispers()
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
                    } else {
                        GeoCacheService.shared.cachedCairns.append(CachedCairn(
                            id: result.id,
                            latitude: location.latitude,
                            longitude: location.longitude,
                            stoneCount: result.stoneCount,
                            lastPlacedAt: Self.isoFormatter.string(from: Date())
                        ))
                    }
                    viewModel.proximityService.suppressTarget(id: "cairn-\(result.id)")
                    GeoCacheService.shared.persistCurrentCairns()
                }
            } catch {
                print("[ActiveWalk] Stone placement failed: \(error)")
            }
        }
    }

    private func nearestCachedCairn() -> CachedCairn? {
        guard let location = viewModel.currentLocation else { return nil }
        let userLoc = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let maxMergeDistance: CLLocationDistance = 42
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
        guard event.direction == .entered,
              viewModel.status.isActiveStatus else { return }

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
