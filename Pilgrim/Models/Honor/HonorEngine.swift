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
    /// Along-Way credit toward arrival: progress earned on the Way through
    /// windowed fixes, plus a re-acquire's jump capped at the Way's own
    /// pace. GPS jitter is credited once, never cumulatively.
    var distanceWalkedMeters: Double {
        walkedFrac * geometry.totalMeters
    }
    /// Whether the walker ever actually joined the Way. Begin's frac-0
    /// fallback (nothing within 60 m) is an approach, not a joining, and a
    /// stage the walker never joined earns no ledger entry.
    var isAnchoredOnWay: Bool { startFrac != nil && !anchoredByFallback }
    /// Position high-water mark, the baseline that credit is measured
    /// against. A re-acquire may move it beyond what was credited.
    private var progressHighWater: Double = 0
    /// Arrival credit in frac: increments of the high-water mark from
    /// on-Way fixes, plus pace-bounded credit for a re-acquire. Reset at
    /// anchor and re-anchor.
    private var walkedFrac: Double = 0

    private let now: () -> Date
    private let softTapEnabled: Bool
    private let subject = PassthroughSubject<HonorEngineEvent, Never>()
    private var cancellables: [AnyCancellable] = []
    private var arrival: ArrivalDebounce
    private var moments: HonorMomentTracker
    private var gates = HonorMomentTracker.Gates()
    private var activeDuration: TimeInterval = 0
    /// Begin found nothing within 60 m and fell back to frac 0; the first
    /// on-Way fix becomes the real anchor.
    private var anchoredByFallback = false
    /// The walk's active duration at the moment the Way was (re-)anchored.
    /// Both the companion's clock and `yourSeconds` are measured from here,
    /// so an approach walk to the trailhead neither puts the companion
    /// hundreds of metres ahead nor counts toward the walker's own time.
    private var anchorActiveDuration: TimeInterval = 0
    private var offWaySince: Date?
    /// Active duration when the walker went off the Way, so a re-acquire's
    /// pace credit is earned on walking time — not on time spent paused.
    private var offWayActiveDuration: TimeInterval = 0
    private var lastReacquireAttempt: Date?
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
        // While the fallback anchor (Begin found no Way within 60 m) is
        // still in effect, the companion has nowhere real to walk to yet —
        // it waits at the start until the first on-Way fix re-anchors it.
        guard startFrac != nil, !anchoredByFallback else { return }
        companionFrac = geometry.frac(atElapsed: companionT0 + sinceAnchorSeconds)
    }

    /// Walking time since the Way was anchored. Never negative: the walk's
    /// active duration is monotonic, but a re-anchor could otherwise race a
    /// stale emission.
    private var sinceAnchorSeconds: TimeInterval { max(0, activeDuration - anchorActiveDuration) }

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
        let hit = geometry.lowestFrac(within: HonorTuning.onWayMeters, of: coordinate)?.frac
        anchoredByFallback = hit == nil
        let frac = hit ?? 0
        startFrac = frac
        progressFrac = frac
        progressHighWater = frac
        walkedFrac = 0
        anchorActiveDuration = activeDuration
        companionT0 = geometry.elapsed(atFrac: frac)
        companionFrac = geometry.frac(atElapsed: companionT0)
    }

    private func reanchor(at frac: Double) {
        anchoredByFallback = false
        startFrac = frac
        progressHighWater = frac
        walkedFrac = 0
        anchorActiveDuration = activeDuration
        companionT0 = geometry.elapsed(atFrac: frac)
        companionFrac = geometry.frac(atElapsed: companionT0)
    }

    private func track(_ coordinate: CLLocationCoordinate2D) {
        let windowSpan = geometry.totalMeters > 0 ? HonorTuning.windowMeters / geometry.totalMeters : 1
        let lower = max(0, progressFrac - HonorTuning.backwardTolerance)
        let upper = min(1, progressFrac + windowSpan)
        let local = geometry.nearest(to: coordinate, within: lower...upper)
        // `nearest` returns .infinity when the window holds no segment (a
        // degenerate Way); clamped so the value stays printable and never
        // reaches `Int(_:)` as an infinity.
        offWayMeters = Self.clampedMeters(local.meters)
        if local.meters <= HonorTuning.onWayMeters {
            isOnWay = true
            offWaySince = nil
            lastReacquireAttempt = nil
            progressFrac = local.frac   // nearest already clamps into the window
            if anchoredByFallback {
                reanchor(at: progressFrac)
            } else {
                walkedFrac += max(0, progressFrac - progressHighWater)
                progressHighWater = max(progressHighWater, progressFrac)
            }
            return
        }
        isOnWay = false
        let time = now()
        if offWaySince == nil {
            offWaySince = time
            offWayActiveDuration = activeDuration
        }
        let dueForRetry = lastReacquireAttempt
            .map { time.timeIntervalSince($0) >= HonorTuning.reacquireRetrySeconds } ?? true
        if let since = offWaySince, time.timeIntervalSince(since) >= HonorTuning.reacquireSeconds, dueForRetry {
            lastReacquireAttempt = time
            // Forward first: on an out-and-back the return leg shares the
            // outbound leg's pavement, and the global lowest frac would drag
            // progress back to the outbound leg with arrival then impossible.
            let ahead = geometry.lowestFrac(within: HonorTuning.onWayMeters, of: coordinate, from: lower)
            if let found = ahead ?? geometry.lowestFrac(within: HonorTuning.onWayMeters, of: coordinate) {
                // Credit the jump, but no faster than the Way was walked:
                // an honest walker off-signal through a corner earns the
                // stretch; a car cannot outrun the Way's own pace. When
                // Begin fell back to frac 0, the re-anchor that follows
                // resets the credit: the walk had not really begun.
                if geometry.totalSeconds > 0 {
                    let jump = max(0, found.frac - progressHighWater)
                    // Walking time off the Way, not wall clock: a walk paused
                    // for an hour off-Way must not convert that hour into
                    // arrival credit.
                    let offWayWalking = max(0, activeDuration - offWayActiveDuration)
                    let paceFrac = offWayWalking / geometry.totalSeconds
                    walkedFrac += max(0, min(jump, paceFrac))
                }
                progressFrac = found.frac
                progressHighWater = max(progressHighWater, progressFrac)
                offWayMeters = Self.clampedMeters(found.meters)
                isOnWay = true
                offWaySince = nil
                lastReacquireAttempt = nil
                if anchoredByFallback { reanchor(at: found.frac) }
            }
            // A failed re-acquire retries every 10 s, not on every fix:
            // lowestFrac is a linear scan of the whole Way (up to 4,000 points).
        }
    }

    // MARK: - Soft tap

    /// A Way is at most a few hundred kilometres; anything past this is a
    /// sentinel or a bad fix, and every consumer formats it as a number.
    private static let maxReportedOffWayMeters: Double = 100_000

    private static func clampedMeters(_ meters: Double) -> Double {
        meters.isFinite ? min(meters, maxReportedOffWayMeters) : maxReportedOffWayMeters
    }

    private func evaluateSoftTap() {
        // Nothing has been joined yet: Begin found no Way within 60 m and
        // fell back to frac 0, so the walker is still approaching. Tapping
        // them on the shoulder for being "off the way" they have not
        // started is the wrong word at the wrong time.
        guard !anchoredByFallback else { return }
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
        guard phase == .walking, let last = geometry.points.last, let start = startFrac else { return }
        // Half of the Way that lay ahead at Begin, along the Way: blocks an
        // arrival at Begin on a loop while letting a mid-Way start finish.
        // The credit is walkedFrac: progress on the Way, plus a
        // re-acquire's jump capped at the Way's pace, so neither a loop's
        // trailhead nor a car ride satisfies it.
        let aheadAtBegin = max(0, 1 - start)
        guard progressFrac >= HonorTuning.arrivalMinFrac,
              walkedFrac >= HonorTuning.arrivalMinDistanceRatio * aheadAtBegin else {
            arrival.reset()
            return
        }
        let end = CLLocation(latitude: last.lat, longitude: last.lon)
        let distance = location.distance(from: end)
        if arrival.register(distance: distance, radius: HonorTuning.arrivalRadiusMeters,
                            accuracy: location.horizontalAccuracy) {
            phase = .arrived
            subject.send(.arrived(theirSeconds: geometry.totalSeconds - companionT0, yourSeconds: sinceAnchorSeconds))
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
