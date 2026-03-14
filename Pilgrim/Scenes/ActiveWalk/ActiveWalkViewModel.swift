import Foundation
import Combine
import CombineExt
import MapKit

class ActiveWalkViewModel: ObservableObject, Identifiable {

    let id = UUID()
    let builder: WalkBuilder
    private let locationManagement: LocationManagement
    private let altitudeManagement: AltitudeManagement
    private let stepCounter: StepCounter
    private let liveStats: LiveStats
    let voiceRecordingManagement: VoiceRecordingManagement
    let soundManagement = SoundManagement()

    @Published var status: WalkBuilder.Status = .waiting
    @Published var duration: String = "0:00"
    @Published var distance: String = "0.00 km"
    @Published var steps: String = "0"
    @Published var speed: String = "0.0 km/h"
    @Published var currentLocation: TempRouteDataSample?
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published private(set) var routeOverlays: [MKPolyline] = []
    @Published var isRecordingVoice = false
    @Published var audioLevel: Float = 0
    @Published var isMeditating = false
    @Published var walkTime: String = "0:00"
    @Published var talkTime: String = "0:00"
    @Published var meditateTime: String = "0:00"
    @Published var paceHistory: [Double] = []
    @Published var currentSoundscapeName: String?

    private var meditationStartDate: Date?
    private var meditationIntervals: [TempActivityInterval] = []

    var onWalkCompleted: ((TempWalk) -> Void)?

    private var cancellables: [AnyCancellable] = []

    init() {
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

        liveStats.steps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.steps = $0 }
            .store(in: &cancellables)

        liveStats.speed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.speed = $0 }
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
                    self.routeOverlays = self.buildActivityPolylines(from: samples)
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
        builder.setStatus(.recording)
        soundManagement.onWalkStart()
    }

    func resume() {
        builder.setStatus(.recording)
    }

    func stop() {
        finalizeMeditation()
        soundManagement.onWalkEnd()
        builder.setStatus(.ready)
    }

    func toggleVoiceRecording() {
        voiceRecordingManagement.toggleRecording()
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
    }

    func endMeditation() {
        finalizeMeditation()
        isMeditating = false
        soundManagement.onMeditationEnd()
    }

    private func finalizeMeditation() {
        guard let start = meditationStartDate else { return }
        let interval = TempActivityInterval(
            uuid: nil,
            activityType: .meditation,
            startDate: start,
            endDate: Date()
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

    private func activityType(at timestamp: Date) -> String {
        for interval in meditationIntervals {
            if timestamp >= interval.startDate && timestamp <= interval.endDate {
                return "meditating"
            }
        }
        if let start = meditationStartDate, timestamp >= start {
            return "meditating"
        }
        if voiceRecordingManagement.isRecording,
           let recStart = voiceRecordingManagement.recordingStartDate,
           timestamp >= recStart {
            return "talking"
        }
        return "walking"
    }

    private func buildActivityPolylines(from samples: [TempRouteDataSample]) -> [MKPolyline] {
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
            let polyline = MKPolyline(coordinates: coords, count: coords.count)
            polyline.title = segment.type
            return polyline
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
