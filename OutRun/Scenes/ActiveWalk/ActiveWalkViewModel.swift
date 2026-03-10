import Foundation
import Combine
import CombineExt
import MapKit

class ActiveWalkViewModel: ObservableObject, Identifiable {

    let id = UUID()
    let builder: WorkoutBuilder
    private let locationManagement: LocationManagement
    private let altitudeManagement: AltitudeManagement
    private let stepCounter: StepCounter
    private let liveStats: LiveStats
    let voiceRecordingManagement: VoiceRecordingManagement

    @Published var status: WorkoutBuilder.Status = .waiting
    @Published var duration: String = "0:00"
    @Published var distance: String = "0.00 km"
    @Published var steps: String = "0"
    @Published var speed: String = "0.0 km/h"
    @Published var currentLocation: TempWorkoutRouteDataSample?
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published private(set) var routeOverlay: MKPolyline?
    @Published var isRecordingVoice = false
    @Published var audioLevel: Float = 0
    @Published var isMeditating = false
    @Published var walkTime: String = "0:00"
    @Published var talkTime: String = "0:00"
    @Published var meditateTime: String = "0:00"

    private var meditationStartDate: Date?
    private var accumulatedMeditateDuration: TimeInterval = 0

    var onWalkCompleted: ((TempWorkout) -> Void)?

    private var cancellables: [AnyCancellable] = []

    init() {
        self.builder = WorkoutBuilder()
        self.locationManagement = LocationManagement(builder: builder)
        self.altitudeManagement = AltitudeManagement(builder: builder)
        self.stepCounter = StepCounter(builder: builder)
        self.liveStats = LiveStats(builder: builder)
        self.voiceRecordingManagement = VoiceRecordingManagement(builder: builder)

        builder.registerPreSnapshotFlush { [weak self] in
            guard let self else { return }
            self.finalizeMeditation()
            self.builder.flushMeditateDuration(self.accumulatedMeditateDuration)
        }

        builder.onSnapshotCreated = { [weak self] snapshot in
            DispatchQueue.main.async {
                self?.onWalkCompleted?(snapshot)
            }
        }

        bindLiveStats()
        bindTimers()
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
            .map { $0.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } }
            .sink { [weak self] coords in
                guard let self else { return }
                let countChanged = coords.count != self.routeCoordinates.count
                self.routeCoordinates = coords
                if countChanged && coords.count > 1 {
                    self.routeOverlay = MKPolyline(coordinates: coords, count: coords.count)
                }
            }
            .store(in: &cancellables)
    }

    func startRecording() {
        builder.setStatus(.recording)
    }

    func resume() {
        builder.setStatus(.recording)
    }

    func stop() {
        finalizeMeditation()
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
    }

    func endMeditation() {
        finalizeMeditation()
        isMeditating = false
    }

    private func finalizeMeditation() {
        guard let start = meditationStartDate else { return }
        accumulatedMeditateDuration += Date().timeIntervalSince(start)
        meditationStartDate = nil
    }

    private var currentMeditateDuration: TimeInterval {
        var total = accumulatedMeditateDuration
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

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
