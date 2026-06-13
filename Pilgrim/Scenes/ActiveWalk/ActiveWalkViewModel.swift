import Foundation
import Combine
import CombineExt
import CoreLocation
import AVFoundation

class ActiveWalkViewModel: ObservableObject, Identifiable {

    let id = UUID()
    let builder: WalkBuilder
    let locationManagement: LocationManagement
    private let altitudeManagement: AltitudeManagement
    private let stepCounter: StepCounter
    private let liveStats: LiveStats
    let voiceRecordingManagement: VoiceRecordingManagement
    let soundManagement = SoundManagement()
    let voiceGuideManagement = VoiceGuideManagement()
    private var sessionGuard: WalkSessionGuard?

    /// Bumped before each weather-retry chain to invalidate stale closures.
    /// CLAUDE.md resource-safety policy: long walks must not leak GCD timers
    /// past viewmodel deinit. Without this generation gate, a 10s retry timer
    /// kept the ViewModel weakly referenced and fired no-ops well after the
    /// walk ended.
    private var weatherRetryGeneration: Int = 0

    @Published var status: WalkBuilder.Status = .waiting
    @Published var duration: String = "0:00"
    @Published var distance: String = UserPreferences.distanceMeasurementType.safeValue == .miles ? "0.00 mi" : "0.00 km"
    @Published var steps: String = "0"
    @Published var ascent: String = StatsHelper.string(for: 0, unit: UnitLength.meters, type: .altitude)
    @Published var currentLocation: TempRouteDataSample?
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published private(set) var routeSegments: [RouteSegment] = []
    @Published var isRecordingVoice = false
    // The 20 Hz metering level deliberately has NO mirror here (AF10):
    // republishing it through this view model made objectWillChange fire
    // 20×/s for every view observing it — including the Mapbox
    // representable — for the duration of every voice recording. The
    // waveform leaf observes `voiceRecordingManagement.$audioLevel`
    // directly via `RecordingLevelMeter`.
    @Published var showMicrophonePermissionNeeded = false
    /// AF45: LocationManagement/StepCounter publish a localized permission
    /// error into the builder's insufficientPermission relay, but nothing
    /// consumed it — a declined location prompt left the walk screen spinning
    /// with no explanation. Surfaced here and rendered as a Settings-linked
    /// alert in `ActiveWalkView`, mirroring the Microphone-Required alert.
    @Published var permissionErrorMessage: String?
    var showPermissionError: Bool {
        get { permissionErrorMessage != nil }
        set { if !newValue { permissionErrorMessage = nil } }
    }
    @Published var isMeditating = false
    private var rawDistanceMeters: Double = 0
    @Published var walkTime: String = "0:00"
    @Published var talkTime: String = "0:00"
    @Published var meditateTime: String = "0:00"
    @Published var paceHistory: [Double] = []
    @Published var currentSoundscapeName: String?
    @Published var voiceGuidePackName: String?
    @Published var isVoiceGuidePaused = false
    @Published var intention: String?
    @Published var waypoints: [TempWaypoint] = []
    @Published var weatherSnapshot: WeatherSnapshot?

    @Published var whispersPlacedThisWalk = 0
    @Published var stonePlacedThisWalk = false
    @Published var encounteredWhisperIDs: Set<String> = []
    @Published var encounteredCairnIDs: Set<String> = []
    @Published private(set) var activeDurationSeconds: TimeInterval = 0

    /// Visible whisper/cairn pins near the user, memoized on its inputs
    /// (AF43): recomputed only when the user moves more than
    /// `pinRefreshDistance` or the geo cache changes — not on every
    /// `ActiveWalkView` body evaluation.
    @Published private(set) var proximityPins: [PilgrimAnnotation] = []
    private var proximityPinsOrigin: CLLocation?

    var isWhisperUnlocked: Bool { activeDurationSeconds >= 7 * 60 }
    var isStoneUnlocked: Bool { activeDurationSeconds >= 12 * 60 }
    var canPlaceWhisper: Bool { isWhisperUnlocked && whispersPlacedThisWalk < 7 }
    var canPlaceStone: Bool { isStoneUnlocked && !stonePlacedThisWalk }

    let proximityService = ProximityDetectionService()

    private var meditationStartDate: Date?
    private var meditationIntervals: [TempActivityInterval] = []
    private var completedRecordings: [TempVoiceRecording] = []

    var onWalkCompleted: ((TempWalk) -> Void)?

    /// Best-available starting camera for the live walk map, computed once
    /// at walk start so every re-render of `ActiveWalkView.mapSection` uses
    /// the same seed. Avoids re-querying CoreLocation and CoreStore on
    /// every SwiftUI body evaluation.
    let mapCameraSeed: MapCameraSeed.Seed?

    private var cancellables: [AnyCancellable] = []

    init() {
        self.mapCameraSeed = MapCameraSeed.forActiveWalk()
        self.builder = WalkBuilder()
        self.locationManagement = LocationManagement(builder: builder)
        self.altitudeManagement = AltitudeManagement(builder: builder)
        self.stepCounter = StepCounter(builder: builder)
        self.liveStats = LiveStats(builder: builder)
        self.voiceRecordingManagement = VoiceRecordingManagement(builder: builder)

        builder.registerPreSnapshotFlush { [weak self] in
            guard let self else { return }
            self.finalizeMeditation()
            self.builder.flushActivityIntervals(self.meditationIntervals)
        }

        builder.onSnapshotCreated = { [weak self] snapshot in
            DispatchQueue.main.async {
                self?.onWalkCompleted?(snapshot)
            }
        }

        bindLiveStats()
        bindTimers()
        bindSoundscape()
        bindVoiceGuide()
        bindCompletedRecordings()
        bindProximity()

        let guard_ = WalkSessionGuard()
        guard_.builder = builder
        guard_.locationManagement = locationManagement
        guard_.viewModel = self
        guard_.start()
        self.sessionGuard = guard_

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.fetchWeather(retryOnFailure: true)
        }
    }

    func fetchWeather(retryOnFailure: Bool = false) {
        weatherRetryGeneration += 1
        let generation = weatherRetryGeneration

        let clLocation: CLLocation?
        if let sample = currentLocation {
            clLocation = CLLocation(latitude: sample.latitude, longitude: sample.longitude)
        } else if let coord = routeCoordinates.last {
            clLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        } else {
            clLocation = nil
        }

        guard let location = clLocation else {
            if retryOnFailure {
                scheduleWeatherRetry(generation: generation)
            }
            return
        }

        Task { [weak self] in
            let snapshot = await WeatherService.shared.fetchCurrent(for: location)
            await MainActor.run { [weak self] in
                guard let self, self.weatherRetryGeneration == generation else { return }
                if let snapshot {
                    self.weatherSnapshot = snapshot
                    self.builder.weatherSnapshot = snapshot
                } else if retryOnFailure {
                    self.scheduleWeatherRetry(generation: generation)
                }
            }
        }
    }

    /// Generation-gated 10s retry. Closure becomes a no-op if any caller
    /// invokes `fetchWeather` again or the viewmodel deallocs — preventing
    /// the GCD timer from holding state past walk-end.
    private func scheduleWeatherRetry(generation: Int) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.weatherRetryGeneration == generation else { return }
            self.fetchWeather(retryOnFailure: false)
        }
    }

    private func bindLiveStats() {
        liveStats.status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.status = $0 }
            .store(in: &cancellables)

        liveStats.distance
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.distance = $0 }
            .store(in: &cancellables)

        liveStats.rawDistance
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.rawDistanceMeters = $0 }
            .store(in: &cancellables)

        liveStats.steps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.steps = $0 }
            .store(in: &cancellables)

        liveStats.ascent
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.ascent = $0 }
            .store(in: &cancellables)

        // AF45: a declined location/motion prompt during setup must explain
        // itself instead of dead-ending into a permanent spinner.
        liveStats.insufficientPermission
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in self?.permissionErrorMessage = message }
            .store(in: &cancellables)

        liveStats.currentLocation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.currentLocation = $0 }
            .store(in: &cancellables)

        // Full-array route events only: builder reset and recovery/continue
        // seeding. Per-sample growth arrives through sampleAppendedPublisher
        // below; when the counts already match, this is an echo of a
        // checkpoint sync (`syncRouteToBuilder`) — skip the O(n) rebuild
        // (AF9/AF46).
        liveStats.locations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] samples in
                guard let self, samples.count != self.routeCoordinates.count else { return }
                self.rebuildRoute(from: samples)
            }
            .store(in: &cancellables)

        locationManagement.sampleAppendedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sample, totalCount in
                guard let self else { return }
                if totalCount == self.routeCoordinates.count + 1 {
                    self.appendRouteSample(sample)
                } else if totalCount > self.routeCoordinates.count {
                    // A full-array event and this append interleaved out of
                    // order — resync from the canonical route once.
                    self.rebuildRoute(from: self.locationManagement.recordedSamples)
                }
                // totalCount <= count: stale echo, already covered by a
                // full-array rebuild.
            }
            .store(in: &cancellables)
    }

    func startRecording() {
        proximityService.resetSession()
        builder.setStatus(.recording)
        soundManagement.onWalkStart()
        startVoiceGuideIfEnabled()
        WalkActivityManager.shared.start(walkStartDate: Date(), intention: intention)
    }

    func resume() {
        builder.setStatus(.recording)
    }

    func stop() {
        cancellables.removeAll()
        proximityService.stopListening()
        // Checkpoint deletion happens in MainCoordinator's saveWalk success
        // callback (AF1) — a failed save must leave the checkpoint on disk
        // so launch recovery can restore the walk.
        sessionGuard?.stop()
        finalizeMeditation()
        soundManagement.onWalkEnd()
        voiceGuideManagement.stopGuiding()
        WalkActivityManager.shared.end()
        builder.setStatus(.ready)
    }

    func cancel() {
        cancellables.removeAll()
        proximityService.stopListening()
        sessionGuard?.stopAndCleanup()
        soundManagement.onWalkEnd()
        voiceGuideManagement.stopGuiding()
        WalkActivityManager.shared.end()
    }

    func toggleVoiceRecording() {
        if !voiceRecordingManagement.isRecording
            && AVAudioApplication.shared.recordPermission == .denied {
            showMicrophonePermissionNeeded = true
            return
        }
        voiceRecordingManagement.toggleRecording()
    }

    // MARK: - Waypoints

    @discardableResult
    func addWaypoint(label: String, icon: String) -> Bool {
        let lat: Double
        let lon: Double
        if let location = currentLocation {
            lat = location.latitude
            lon = location.longitude
        } else if let last = routeCoordinates.last {
            lat = last.latitude
            lon = last.longitude
        } else {
            return false
        }
        let waypoint = TempWaypoint(
            uuid: nil,
            latitude: lat,
            longitude: lon,
            label: label,
            icon: icon,
            timestamp: Date()
        )
        builder.addWaypoint(waypoint)
        waypoints.append(waypoint)
        return true
    }

    // MARK: - Meditation

    // GPS power is owned exclusively by WalkSessionGuard's tier system,
    // which reacts to `$isMeditating` (AF14). Driving the location manager
    // directly from here used to restore full-power GPS at meditation end
    // even on low battery — and the guard's tier never re-applied because
    // the tier value itself hadn't changed.
    func startMeditation() {
        guard !isMeditating else { return }
        if isRecordingVoice {
            voiceRecordingManagement.stopRecording()
        }
        meditationStartDate = Date()
        isMeditating = true
        soundManagement.onMeditationStart()
    }

    func endMeditationSilently(endDate: Date = Date()) {
        finalizeMeditation(endDate: endDate)
        isMeditating = false
    }

    func checkpointActivityIntervals() -> [TempActivityInterval] {
        var intervals = meditationIntervals
        if let start = meditationStartDate {
            let provisional = TempActivityInterval(
                uuid: nil,
                activityType: .meditation,
                startDate: start,
                endDate: Date()
            )
            intervals.append(provisional)
        }
        return intervals
    }

    private func finalizeMeditation(endDate: Date = Date()) {
        guard let start = meditationStartDate else { return }
        let interval = TempActivityInterval(
            uuid: nil,
            activityType: .meditation,
            startDate: start,
            endDate: endDate
        )
        meditationIntervals.append(interval)
        meditationStartDate = nil
    }

    private var currentMeditateDuration: TimeInterval {
        var total = meditationIntervals.reduce(0) { $0 + $1.duration }
        if let start = meditationStartDate {
            total += Date().timeIntervalSince(start)
        }
        return total
    }

    // MARK: - Timers

    private func bindTimers() {
        voiceRecordingManagement.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isRecordingVoice = $0 }
            .store(in: &cancellables)

        let voiceRecordings = builder.voiceRecordingsPublisher
        let startDate = builder.startDatePublisher
        let pauses = builder.pausesPublisher

        Timer.TimerPublisher(interval: 1, runLoop: .main, mode: .default)
            .autoconnect()
            .combineLatest(startDate, pauses)
            .combineLatest(voiceRecordings)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] timerPauses, recordings in
                guard let self else { return }
                let (_, start, pauseList) = timerPauses
                guard let start else { return }
                let pauseDuration = pauseList.map { $0.duration }.reduce(0, +)
                let activeDuration = max(0, start.distance(to: Date()) - pauseDuration)
                self.activeDurationSeconds = activeDuration

                self.duration = self.formatTime(activeDuration)

                var talk = recordings.reduce(0.0) { $0 + $1.duration }
                if let recordingStart = self.voiceRecordingManagement.recordingStartDate {
                    talk += Date().timeIntervalSince(recordingStart)
                }
                let meditate = self.currentMeditateDuration
                let walk = max(0, activeDuration - meditate)

                self.talkTime = self.formatTime(talk)
                self.meditateTime = self.formatTime(meditate)
                self.walkTime = self.formatTime(walk)

                let isPaused = self.status == .paused || self.status == .autoPaused
                let walkTimerStart: Date? = isPaused ? nil : start.addingTimeInterval(pauseDuration)

                let previousMeditationDuration = self.meditationIntervals.reduce(0) { $0 + $1.duration }
                let meditationTimerStart: Date? = self.meditationStartDate?.addingTimeInterval(-previousMeditationDuration)

                let previousTalkDuration = recordings.reduce(0.0) { $0 + $1.duration }
                let talkTimerStart: Date? = self.voiceRecordingManagement.recordingStartDate?.addingTimeInterval(-previousTalkDuration)

                WalkActivityManager.shared.update(
                    activeDuration: activeDuration,
                    walkTimerStart: walkTimerStart,
                    distanceMeters: self.rawDistanceMeters,
                    meditationTimerStart: meditationTimerStart,
                    talkTimerStart: talkTimerStart,
                    isPaused: isPaused,
                    isMeditating: self.isMeditating,
                    isRecordingVoice: self.isRecordingVoice
                )
            }
            .store(in: &cancellables)
    }

    private func bindCompletedRecordings() {
        builder.voiceRecordingsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recordings in
                self?.completedRecordings = recordings
            }
            .store(in: &cancellables)
    }

    private func bindProximity() {
        proximityService.bindToLocation(
            liveStats.currentLocation
        )
        proximityService.resetSession()
        GeoCacheService.shared.invalidateLastFetch()

        liveStats.currentLocation
            .compactMap { $0 }
            .throttle(for: .seconds(300), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] sample in
                guard let self else { return }
                Task {
                    await GeoCacheService.shared.fetchIfNeeded(
                        near: CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude)
                    )
                    await MainActor.run {
                        self.proximityService.updateTargets(GeoCacheService.shared.proximityTargets())
                    }
                }
            }
            .store(in: &cancellables)

        GeoCacheService.shared.$cachedWhispers
            .combineLatest(GeoCacheService.shared.$cachedCairns)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                guard let self else { return }
                self.proximityService.updateTargets(GeoCacheService.shared.proximityTargets())
                if let origin = self.proximityPinsOrigin {
                    self.refreshProximityPins(around: origin)
                }
            }
            .store(in: &cancellables)

        liveStats.currentLocation
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sample in
                guard let self else { return }
                let location = CLLocation(latitude: sample.latitude, longitude: sample.longitude)
                if let origin = self.proximityPinsOrigin,
                   location.distance(from: origin) < Self.pinRefreshDistance {
                    return
                }
                self.refreshProximityPins(around: location)
            }
            .store(in: &cancellables)
    }

    private func bindSoundscape() {
        SoundscapePlayer.shared.$currentAsset
            .receive(on: DispatchQueue.main)
            .map { $0?.displayName }
            .sink { [weak self] in self?.currentSoundscapeName = $0 }
            .store(in: &cancellables)
    }

    private func bindVoiceGuide() {
        voiceGuideManagement.bindWalkState(
            statusPublisher: builder.statusPublisher,
            startDatePublisher: builder.startDatePublisher,
            isRecordingVoicePublisher: voiceRecordingManagement.$isRecording.eraseToAnyPublisher(),
            isMeditatingPublisher: $isMeditating.eraseToAnyPublisher()
        )

        voiceGuideManagement.$isActive
            .combineLatest(voiceGuideManagement.$isPaused)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive, isPaused in
                self?.voiceGuidePackName = isActive ? self?.voiceGuideManagement.packName : nil
                self?.isVoiceGuidePaused = isPaused
            }
            .store(in: &cancellables)
    }

    private func startVoiceGuideIfEnabled() {
        guard UserPreferences.voiceGuideEnabled.value,
              let packId = UserPreferences.selectedVoiceGuidePackId.value,
              let pack = VoiceGuideManifestService.shared.pack(byId: packId),
              VoiceGuideFileStore.shared.isPackDownloaded(pack) else { return }
        voiceGuideManagement.startGuiding(pack: pack)
    }

    private func activityType(at timestamp: Date) -> String {
        for interval in meditationIntervals {
            if timestamp >= interval.startDate && timestamp <= interval.endDate {
                return "meditating"
            }
        }
        if let start = meditationStartDate, timestamp >= start {
            return "meditating"
        }
        for recording in completedRecordings {
            if timestamp >= recording.startDate && timestamp <= recording.endDate {
                return "talking"
            }
        }
        if voiceRecordingManagement.isRecording,
           let recStart = voiceRecordingManagement.recordingStartDate,
           timestamp >= recStart {
            return "talking"
        }
        return "walking"
    }

    private func buildActivitySegments(from samples: [TempRouteDataSample]) -> [RouteSegment] {
        guard samples.count > 1 else { return [] }

        var segments: [(type: String, indices: [Int])] = []
        var currentType = activityType(at: samples[0].timestamp)
        var currentIndices = [0]

        for i in 1..<samples.count {
            let type = activityType(at: samples[i].timestamp)
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

    // MARK: - Test Hooks

    #if DEBUG
    /// Fires whenever the O(n) full-route rebuild runs, so the route
    /// pipeline tests can prove per-sample work stays incremental (AF9/AF46).
    var _test_onFullRouteRebuild: (() -> Void)?
    /// Exposes the session guard so tests can drive battery-tier
    /// recalculation (AF14).
    var _test_sessionGuard: WalkSessionGuard? { sessionGuard }
    /// Opens a meditation interval without the audio side effects of
    /// `startMeditation()`, for segment-boundary tests.
    func _test_setMeditationStart(_ date: Date?) {
        meditationStartDate = date
    }
    #endif

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Route Building (AF9/AF46)

extension ActiveWalkViewModel {

    /// O(n) rebuild from a full sample array. Reserved for rare full-array
    /// events (reset, recovery seed, resync) — steady-state growth goes
    /// through `appendRouteSample`.
    fileprivate func rebuildRoute(from samples: [TempRouteDataSample]) {
        #if DEBUG
        _test_onFullRouteRebuild?()
        #endif
        routeCoordinates = samples.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        routeSegments = samples.count > 1 ? buildActivitySegments(from: samples) : []
        appendPace(from: samples.last)
    }

    /// Amortized O(1) per-sample route growth: appends the coordinate and
    /// extends (or opens) the last activity segment instead of remapping the
    /// whole array per GPS fix.
    fileprivate func appendRouteSample(_ sample: TempRouteDataSample) {
        let coord = CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude)
        routeCoordinates.append(coord)

        if routeSegments.isEmpty {
            // First segment needs the initial sample's timestamp to classify
            // its activity — build from the canonical route (tiny n: this
            // only happens within the first samples of a walk). Prefixed to
            // the coordinates we track so a batched delegate delivery can't
            // double-count samples still in flight.
            if routeCoordinates.count > 1 {
                let samples = Array(locationManagement.recordedSamples.prefix(routeCoordinates.count))
                routeSegments = buildActivitySegments(from: samples)
            }
        } else {
            let type = activityType(at: sample.timestamp)
            let lastIndex = routeSegments.count - 1
            // Mirrors buildActivitySegments: an activity boundary sample
            // belongs to both the closing and the opening segment so the
            // rendered line stays continuous.
            routeSegments[lastIndex].coordinates.append(coord)
            if routeSegments[lastIndex].activityType != type {
                routeSegments.append(RouteSegment(coordinates: [coord], activityType: type))
            }
        }

        appendPace(from: sample)
    }

    private func appendPace(from sample: TempRouteDataSample?) {
        guard let sample else { return }
        let speedMps = max(0, sample.speed)
        let paceMinKm = speedMps > 0.3 ? (1000.0 / speedMps) / 60.0 : 0
        paceHistory.append(paceMinKm)
        if paceHistory.count > 60 {
            paceHistory.removeFirst(paceHistory.count - 60)
        }
    }
}

// MARK: - Proximity Pins (AF43)

extension ActiveWalkViewModel {

    private static let pinVisibilityRadius: CLLocationDistance = 2000
    private static let maxVisiblePins = 30
    private static let minPinSeparation: CLLocationDistance = 15
    /// How far the user must move before the visible-pin set is recomputed.
    static let pinRefreshDistance: CLLocationDistance = 15

    fileprivate func refreshProximityPins(around location: CLLocation) {
        proximityPinsOrigin = location
        let pins = Self.computeProximityPins(
            around: location,
            whispers: GeoCacheService.shared.cachedWhispers,
            cairns: GeoCacheService.shared.cachedCairns
        )
        if pins != proximityPins {
            proximityPins = pins
        }
    }

    /// Pure visible-pin computation: whispers and cairns within
    /// `pinVisibilityRadius`, nearest first, capped at `maxVisiblePins`,
    /// with a same-kind minimum separation so dense clusters don't smear.
    static func computeProximityPins(
        around userLoc: CLLocation,
        whispers: [CachedWhisper],
        cairns: [CachedCairn]
    ) -> [PilgrimAnnotation] {
        var candidates: [PinCandidate] = []

        for whisper in whispers {
            let dist = userLoc.distance(from: CLLocation(latitude: whisper.latitude, longitude: whisper.longitude))
            guard dist <= Self.pinVisibilityRadius else { continue }
            guard let cat = whisper.resolvedCategory else { continue }
            let isNearby = dist <= ProximityDetectionService.whisperRadius
            let annotation = PilgrimAnnotation(
                coordinate: CLLocationCoordinate2D(latitude: whisper.latitude, longitude: whisper.longitude),
                kind: .whisper(categoryColor: cat.borderColor, isNearby: isNearby)
            )
            candidates.append(PinCandidate(annotation: annotation, distance: dist))
        }

        for cairn in cairns {
            let dist = userLoc.distance(from: CLLocation(latitude: cairn.latitude, longitude: cairn.longitude))
            guard dist <= Self.pinVisibilityRadius else { continue }
            let annotation = PilgrimAnnotation(
                coordinate: CLLocationCoordinate2D(latitude: cairn.latitude, longitude: cairn.longitude),
                kind: .cairn(stoneCount: cairn.stoneCount, tier: cairn.tier)
            )
            candidates.append(PinCandidate(annotation: annotation, distance: dist))
        }

        candidates.sort { $0.distance < $1.distance }
        return filterBySeparation(candidates)
    }

    private struct PinCandidate {
        let annotation: PilgrimAnnotation
        let distance: CLLocationDistance
    }

    private static func filterBySeparation(_ candidates: [PinCandidate]) -> [PilgrimAnnotation] {
        let isSameType: (PilgrimAnnotation.Kind, PilgrimAnnotation.Kind) -> Bool = { a, b in
            switch (a, b) {
            case (.whisper, .whisper), (.cairn, .cairn): return true
            default: return false
            }
        }

        var accepted: [(annotation: PilgrimAnnotation, lat: Double, lon: Double)] = []
        for candidate in candidates {
            guard accepted.count < Self.maxVisiblePins else { break }
            let cLat = candidate.annotation.coordinate.latitude
            let cLon = candidate.annotation.coordinate.longitude
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
}
