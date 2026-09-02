import Combine
import CoreLocation
import Foundation

enum HonorPhase: Equatable { case walking, arrived }

enum HonorEngineEvent: Equatable {
    case momentReached(WayMoment)
    case voiceStart(WayMoment)
    case voicePause
    case voiceResume
    case voiceDropped(WayMoment)
    case softTap(offWayMeters: Double)
    case arrived(theirSeconds: Double, yourSeconds: Double)
}

/// Session engine for an honor walk: consumes the walk's streams, keeps
/// position along the Way, moves the companion on the walker's active
/// clock, triggers moments, and detects arrival. Persists nothing.
final class HonorEngine: ObservableObject {

    let way: Way
    let geometry: WayGeometry
    let events: AnyPublisher<HonorEngineEvent, Never>

    @Published private(set) var progressFrac: Double = 0
    @Published private(set) var distanceRemainingMeters: Double
    @Published private(set) var offWayMeters: Double = 0
    @Published private(set) var isOnWay = false
    @Published private(set) var companionFrac: Double = 0
    @Published private(set) var phase: HonorPhase = .walking

    private(set) var startFrac: Double?
    private(set) var companionT0: Double = 0
    private(set) var distanceWalkedMeters: Double = 0

    private let now: () -> Date
    private let softTapEnabled: Bool
    private let subject = PassthroughSubject<HonorEngineEvent, Never>()
    private var cancellables: [AnyCancellable] = []
    private var arrival: ArrivalDebounce
    private var moments: HonorMomentTracker
    private var gates = HonorMomentTracker.Gates()
    private var activeDuration: TimeInterval = 0
    private var lastAcceptedCoordinate: CLLocationCoordinate2D?
    /// Begin found nothing within 60 m and fell back to frac 0; the first
    /// on-Way fix becomes the real anchor.
    private var anchoredByFallback = false
    private var offWaySince: Date?
    private var softTapSince: Date?
    private var softTapArmed = true

    init(way: Way, softTapEnabled: Bool, voicesEnabled: Bool, now: @escaping () -> Date = { Date() }) {
        self.way = way
        self.geometry = WayGeometry(route: way.route)
        self.now = now
        self.softTapEnabled = softTapEnabled
        self.events = subject.eraseToAnyPublisher()
        self.distanceRemainingMeters = geometry.totalMeters
        self.arrival = ArrivalDebounce(requiredFixes: HonorTuning.arrivalFixCount,
                                       accuracyMeters: HonorTuning.arrivalAccuracyMeters)
        self.moments = HonorMomentTracker(moments: way.moments, geometry: geometry, voicesEnabled: voicesEnabled)
    }

    // MARK: - Binding

    func bind(
        locations: AnyPublisher<CLLocation, Never>,
        activeDuration: AnyPublisher<TimeInterval, Never>,
        isPaused: AnyPublisher<Bool, Never>,
        isMeditating: AnyPublisher<Bool, Never>,
        isRecordingVoice: AnyPublisher<Bool, Never>,
        externalAudio: AnyPublisher<Bool, Never>
    ) {
        cancellables.removeAll()
        locations.receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.processLocation($0) }.store(in: &cancellables)
        activeDuration.receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateActiveDuration($0) }.store(in: &cancellables)
        // combineLatest waits for all four inputs; callers bind @Published
        // projections, which emit on subscribe, so the gates are live at once.
        isPaused.combineLatest(isMeditating, isRecordingVoice, externalAudio)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] paused, meditating, recording, audio in
                self?.setGates(paused: paused, meditating: meditating, recording: recording, externalAudio: audio)
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
    }

    // MARK: - Inputs

    func updateActiveDuration(_ seconds: TimeInterval) {
        activeDuration = seconds
        guard startFrac != nil else { return }
        companionFrac = geometry.frac(atElapsed: companionT0 + seconds)
    }

    func setGates(paused: Bool, meditating: Bool, recording: Bool, externalAudio: Bool) {
        gates = HonorMomentTracker.Gates(paused: paused, meditating: meditating,
                                         recording: recording, externalAudio: externalAudio)
        emit(moments.gatesDidChange(gates))
    }

    func voiceDidFinish() {
        emit(moments.voiceDidFinish(gates: gates))
    }

    func processLocation(_ location: CLLocation) {
        let accuracy = location.horizontalAccuracy
        guard accuracy >= 0, accuracy <= HonorTuning.fixAccuracyMeters else { return }
        let coordinate = location.coordinate
        // Only moving fixes count toward the arrival distance gate: a
        // stationary phone's 30-50 m jitter would otherwise fabricate
        // kilometres during a long sitting. Teleports are ignored too.
        if let last = lastAcceptedCoordinate, location.speed >= HonorTuning.stationarySpeed {
            let step = CLLocation(latitude: last.latitude, longitude: last.longitude).distance(from: location)
            if step <= HonorTuning.maxStepMeters { distanceWalkedMeters += step }
        }
        lastAcceptedCoordinate = coordinate

        if startFrac == nil { anchor(at: coordinate) }
        track(coordinate)
        distanceRemainingMeters = (1 - progressFrac) * geometry.totalMeters
        evaluateSoftTap()
        evaluateArrival(location)

        let stationary = location.speed >= 0 && location.speed < HonorTuning.stationarySpeed
        emit(moments.update(location: coordinate, progressFrac: progressFrac, gates: gates, isStationary: stationary))
    }

    // MARK: - Position

    private func anchor(at coordinate: CLLocationCoordinate2D) {
        let hit = geometry.lowestFrac(within: HonorTuning.onWayMeters, of: coordinate)
        anchoredByFallback = hit == nil
        let frac = hit ?? 0
        startFrac = frac
        progressFrac = frac
        companionT0 = geometry.elapsed(atFrac: frac)
        companionFrac = geometry.frac(atElapsed: companionT0 + activeDuration)
    }

    private func reanchor(at frac: Double) {
        anchoredByFallback = false
        startFrac = frac
        companionT0 = geometry.elapsed(atFrac: frac)
        companionFrac = geometry.frac(atElapsed: companionT0 + activeDuration)
    }

    private func track(_ coordinate: CLLocationCoordinate2D) {
        let windowSpan = geometry.totalMeters > 0 ? HonorTuning.windowMeters / geometry.totalMeters : 1
        let lower = max(0, progressFrac - HonorTuning.backwardTolerance)
        let upper = min(1, progressFrac + windowSpan)
        let local = geometry.nearest(to: coordinate, within: lower...upper)
        offWayMeters = local.meters
        if local.meters <= HonorTuning.onWayMeters {
            isOnWay = true
            offWaySince = nil
            progressFrac = max(lower, local.frac)
            if anchoredByFallback { reanchor(at: progressFrac) }
            return
        }
        isOnWay = false
        let time = now()
        if offWaySince == nil { offWaySince = time }
        if let since = offWaySince, time.timeIntervalSince(since) >= HonorTuning.reacquireSeconds {
            // Forward first: on an out-and-back the return leg shares the
            // outbound leg's pavement, and the global lowest frac would drag
            // progress back to the outbound leg with arrival then impossible.
            let ahead = geometry.lowestFrac(within: HonorTuning.onWayMeters, of: coordinate, from: lower)
            if let found = ahead ?? geometry.lowestFrac(within: HonorTuning.onWayMeters, of: coordinate) {
                progressFrac = found
                offWayMeters = geometry.nearest(to: coordinate, within: found...found).meters
                isOnWay = true
                offWaySince = nil
                if anchoredByFallback { reanchor(at: found) }
            }
        }
    }

    // MARK: - Soft tap

    private func evaluateSoftTap() {
        guard phase == .walking, softTapEnabled else { return }
        if offWayMeters <= HonorTuning.onWayMeters {
            softTapSince = nil
            softTapArmed = true
            return
        }
        guard softTapArmed, offWayMeters > HonorTuning.softTapMeters else {
            if offWayMeters <= HonorTuning.softTapMeters { softTapSince = nil }
            return
        }
        let time = now()
        if softTapSince == nil { softTapSince = time }
        if let since = softTapSince, time.timeIntervalSince(since) >= HonorTuning.softTapSeconds {
            softTapArmed = false
            softTapSince = nil
            subject.send(.softTap(offWayMeters: offWayMeters))
        }
    }

    // MARK: - Arrival

    private func evaluateArrival(_ location: CLLocation) {
        guard phase == .walking, let last = geometry.points.last else { return }
        guard progressFrac >= HonorTuning.arrivalMinFrac,
              distanceWalkedMeters >= HonorTuning.arrivalMinDistanceRatio * geometry.totalMeters else {
            arrival.reset()
            return
        }
        let end = CLLocation(latitude: last.lat, longitude: last.lon)
        let distance = location.distance(from: end)
        if arrival.register(distance: distance, radius: HonorTuning.arrivalRadiusMeters,
                            accuracy: location.horizontalAccuracy) {
            phase = .arrived
            subject.send(.arrived(theirSeconds: geometry.totalSeconds - companionT0, yourSeconds: activeDuration))
        }
    }

    private func emit(_ actions: [HonorMomentTracker.Action]) {
        for action in actions {
            switch action {
            case .reached(let moment): subject.send(.momentReached(moment))
            case .voiceStart(let moment): subject.send(.voiceStart(moment))
            case .voicePause: subject.send(.voicePause)
            case .voiceResume: subject.send(.voiceResume)
            case .voiceDropped(let moment): subject.send(.voiceDropped(moment))
            }
        }
    }
}

// PLACEHOLDER: replaced by Pilgrim/Models/Honor/HonorMomentTracker.swift in
// Task 8. Every method is a no-op until then, so no moment fires and no
// voice plays. Delete this stub when the real tracker lands.
struct HonorMomentTracker {
    enum Action: Equatable {
        case reached(WayMoment), voiceStart(WayMoment), voicePause, voiceResume, voiceDropped(WayMoment)
    }
    struct Gates: Equatable {
        var paused = false, meditating = false, recording = false, externalAudio = false
        var isClosed: Bool { paused || meditating || recording || externalAudio }
    }
    init(moments: [WayMoment], geometry: WayGeometry, voicesEnabled: Bool) {}
    mutating func update(location: CLLocationCoordinate2D, progressFrac: Double, gates: Gates, isStationary: Bool) -> [Action] { [] }
    mutating func gatesDidChange(_ gates: Gates) -> [Action] { [] }
    mutating func voiceDidFinish(gates: Gates) -> [Action] { [] }
}
