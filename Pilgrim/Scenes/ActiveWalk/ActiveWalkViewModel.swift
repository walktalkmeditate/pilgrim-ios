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

    @Published var status: WalkBuilder.Status = .waiting
    @Published var duration: String = "0:00"
    @Published var distance: String = UserPreferences.distanceMeasurementType.safeValue == .miles ? "0.00 mi" : "0.00 km"
    @Published var steps: String = "0"
    @Published var ascent: String = StatsHelper.string(for: 0, unit: UnitLength.meters, type: .altitude)
    @Published var currentLocation: TempRouteDataSample?
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published private(set) var routeSegments: [RouteSegment] = []
    @Published var isRecordingVoice = false
    @Published var audioLevel: Float = 0
    @Published var showMicrophonePermissionNeeded = false
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                    self?.fetchWeather(retryOnFailure: false)
                }
            }
            return
        }

        Task { [weak self] in
            let snapshot = await WeatherService.shared.fetchCurrent(for: location)
            await MainActor.run {
                if let snapshot {
                    self?.weatherSnapshot = snapshot
                    self?.builder.weatherSnapshot = snapshot
                } else if retryOnFailure {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                        self?.fetchWeather(retryOnFailure: false)
                    }
                }
            }
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

        liveStats.currentLocation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.currentLocation = $0 }
            .store(in: &cancellables)

        liveStats.locations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] samples in
                guard let self else { return }
                let coords = samples.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                let countChanged = coords.count != self.routeCoordinates.count
                self.routeCoordinates = coords
                if countChanged && coords.count > 1 {
                    self.routeSegments = self.buildActivitySegments(from: samples)
                }
                if countChanged, let last = samples.last {
                    let speedMps = max(0, last.speed)
                    let paceMinKm = speedMps > 0.3 ? (1000.0 / speedMps) / 60.0 : 0
                    self.paceHistory.append(paceMinKm)
                    if self.paceHistory.count > 60 {
                        self.paceHistory.removeFirst(self.paceHistory.count - 60)
                    }
                }
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
        sessionGuard?.stopAndCleanup()
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
            && AVAudioSession.sharedInstance().recordPermission == .denied {
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

    func startMeditation() {
        guard !isMeditating else { return }
        if isRecordingVoice {
            voiceRecordingManagement.stopRecording()
        }
        meditationStartDate = Date()
        isMeditating = true
        soundManagement.onMeditationStart()
        locationManagement.adjustPower(
            accuracy: kCLLocationAccuracyHundredMeters,
            distanceFilter: 50
        )
    }

    func endMeditationSilently(endDate: Date = Date()) {
        finalizeMeditation(endDate: endDate)
        isMeditating = false
        locationManagement.restoreDefaultPower()
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

        voiceRecordingManagement.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.audioLevel = $0 }
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
                self?.proximityService.updateTargets(GeoCacheService.shared.proximityTargets())
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

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
