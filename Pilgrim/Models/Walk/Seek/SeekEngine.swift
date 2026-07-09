import Combine
import CoreLocation
import Foundation

// SeekEnginePhase lives in SeekGlance.swift — the widget-shared file — so
// the Live Activity glance model can consume it without importing the engine.

enum SeekEngineEvent: Equatable {
    case pulse(aligned: Bool, distanceMeters: Double)
    case arrived(clearingIndex: Int)
    case stillnessBegan(clearingIndex: Int)
    /// Fired for both stillness and grace reveals.
    case revealedNext(activeIndex: Int)
    case seekComplete
}

/// Starting values from the plan — cadence curve, cone width, smoothing
/// window, and debounce are on-device tuning candidates, not commitments.
enum SeekEngineTuning {
    static let farDistanceMeters = 2000.0
    static let nearDistanceMeters = 100.0
    static let farPulseInterval: TimeInterval = 60
    static let nearPulseInterval: TimeInterval = 10
    static let lowPowerPulseFloor: TimeInterval = 30
    static let alignmentConeDegrees = 60.0
    static let headingWindowSeconds: TimeInterval = 15
    static let arrivalFixCount = 3
    static let arrivalAccuracyMeters = 50.0
    static let graceSeconds: TimeInterval = 240
    static let stillnessWindowRange = 45.0...90.0
    static let stillnessCheckInterval: TimeInterval = 5
    /// Floor for a rerolled remainder budget (R17) so a regenerated chain is
    /// never degenerate — the single source for both the engine's estimate
    /// and `SeekChain.regeneratingRemainder`'s clamp.
    static let rerollMinBudgetMeters = SeekTuning.minStartDistanceMeters * 2.5
}

/// Session engine for a seek: consumes the ordered clearing chain, binds to
/// the existing walk streams, and publishes pulse/arrival/reveal events.
/// View-model-level service like ProximityDetectionService — it persists
/// nothing and never touches GPS power; the tier arrives as an input (AF14).
final class SeekEngine: ObservableObject {

    @Published private(set) var chain: SeekChain
    @Published private(set) var activeIndex: Int
    @Published private(set) var phase: SeekEnginePhase
    @Published private(set) var distanceToActiveMeters: Double?

    let events: AnyPublisher<SeekEngineEvent, Never>

    private(set) var currentTier: WalkSessionGuard.PowerTier = .normal
    private(set) var pulseGeneration = 0

    private let now: () -> Date
    private let motionProvider: SeekMotionActivityProviding
    private let stillnessWindowOverride: TimeInterval?
    private let eventsSubject: PassthroughSubject<SeekEngineEvent, Never>

    private var cancellables: [AnyCancellable] = []
    private var pulseTimer: Timer?
    private var stillnessCheckTimer: Timer?
    private var stillnessDetector: SeekStillnessDetector?
    private var graceDeadline: Date?
    private var suspendedGraceRemaining: TimeInterval?
    private var isSuspended = false
    private var consecutiveInsideCount = 0
    private var lastCoordinate: CLLocationCoordinate2D?
    private var courseSamples: [(timestamp: Date, course: Double)] = []
    /// Deliberately stale: carries the pre-reroll distance so the sonar
    /// heartbeat keeps pulsing across `seekAnew` until the next fix supplies
    /// the true distance to the replacement clearing.
    private var rerollPulseDistance: Double?

    #if DEBUG
    var _test_pulseIntervalOverride: TimeInterval?
    #endif

    init(
        chain: SeekChain,
        now: @escaping () -> Date = { Date() },
        motionProvider: SeekMotionActivityProviding = SeekMotionActivityProvider(),
        stillnessWindowOverride: TimeInterval? = nil
    ) {
        let subject = PassthroughSubject<SeekEngineEvent, Never>()
        self.eventsSubject = subject
        self.events = subject.eraseToAnyPublisher()
        self.chain = chain
        self.now = now
        self.motionProvider = motionProvider
        self.stillnessWindowOverride = stillnessWindowOverride
        self.activeIndex = 0
        self.phase = chain.clearings.isEmpty ? .complete : .guiding
    }

    deinit {
        pulseTimer?.invalidate()
        stillnessCheckTimer?.invalidate()
    }

    // MARK: - Public surface

    func bind(
        locations: AnyPublisher<CLLocation, Never>,
        stepCounts: AnyPublisher<Int, Never>,
        builderStatus: AnyPublisher<WalkBuilder.Status, Never>,
        powerTier: AnyPublisher<WalkSessionGuard.PowerTier, Never>
    ) {
        cancellables.removeAll()
        locations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in self?.processLocation(location) }
            .store(in: &cancellables)
        stepCounts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in self?.processSteps(count) }
            .store(in: &cancellables)
        builderStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.handleStatus(status) }
            .store(in: &cancellables)
        powerTier
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tier in self?.handleTier(tier) }
            .store(in: &cancellables)
    }

    /// R17 reroll. The remaining budget is a v1 estimate — distance walked
    /// is not tracked here, so the budget scales by the fraction of
    /// clearings still ahead, clamped so the regenerated remainder is never
    /// degenerate. Callers may pass a SeekSeed so the reroll carries the
    /// same provenance as the original generation; nil falls back to OS
    /// entropy (tests, callers without an intention in reach).
    func seekAnew(currentLocation: SeekPoint, seed: UInt64? = nil) {
        guard phase == .guiding || phase == .arrived else { return }
        if phase == .arrived {
            stopStillnessMachinery()
            phase = .guiding
        }
        let fractionAhead = 1 - Double(activeIndex) / Double(max(chain.clearings.count, 1))
        let remainingBudget = max(
            chain.budgetMeters * fractionAhead,
            SeekEngineTuning.rerollMinBudgetMeters
        )
        if var seeded = seed.map(SeekSeededGenerator.init(seed:)) {
            chain = chain.regeneratingRemainder(
                fromActiveIndex: activeIndex,
                current: currentLocation,
                remainingBudgetMeters: remainingBudget,
                using: &seeded
            )
        } else {
            var rng = SystemRandomNumberGenerator()
            chain = chain.regeneratingRemainder(
                fromActiveIndex: activeIndex,
                current: currentLocation,
                remainingBudgetMeters: remainingBudget,
                using: &rng
            )
        }
        consecutiveInsideCount = 0
        rerollPulseDistance = distanceToActiveMeters
        distanceToActiveMeters = nil
        invalidatePulseTimer()
        if rerollPulseDistance != nil {
            schedulePulse()
            // The immediate pulse IS the reroll's feedback: one ping, one
            // haptic, one ring the moment the new clearing exists.
            emitPulse()
        }
    }

    func stop() {
        invalidatePulseTimer()
        stopStillnessMachinery()
        cancellables.removeAll()
    }

    // MARK: - Pulse clock

    /// 0 far → 1 near, on the same clamp the cadence uses — ping volume and
    /// haptic intensity share this curve so ear and skin agree.
    static func closeness(forDistanceMeters meters: Double) -> Double {
        let near = SeekEngineTuning.nearDistanceMeters
        let far = SeekEngineTuning.farDistanceMeters
        let clamped = min(max(meters, near), far)
        return 1 - (clamped - near) / (far - near)
    }

    static func pulseInterval(
        forDistance meters: Double,
        tier: WalkSessionGuard.PowerTier
    ) -> TimeInterval {
        let near = SeekEngineTuning.nearDistanceMeters
        let far = SeekEngineTuning.farDistanceMeters
        let clamped = min(max(meters, near), far)
        let fraction = (clamped - near) / (far - near)
        let interval = SeekEngineTuning.nearPulseInterval
            + fraction * (SeekEngineTuning.farPulseInterval - SeekEngineTuning.nearPulseInterval)
        switch tier {
        case .low, .critical:
            return max(interval, SeekEngineTuning.lowPowerPulseFloor)
        case .normal, .meditation:
            return interval
        }
    }

    /// Internal so tests can drive timer events directly without waiting
    /// for a RunLoop timer.
    func pulseTimerFired(generation: Int) {
        guard generation == pulseGeneration else { return }
        emitPulse()
        schedulePulse()
    }

    /// Internal so tests can drive timer events directly without waiting
    /// for a RunLoop timer.
    func emitPulse() {
        guard phase == .guiding, !isSuspended,
              let distance = distanceToActiveMeters ?? rerollPulseDistance else { return }
        eventsSubject.send(.pulse(aligned: isAligned, distanceMeters: distance))
    }

    private func ensurePulseScheduled() {
        guard pulseTimer?.isValid != true else { return }
        schedulePulse()
    }

    private func schedulePulse() {
        pulseGeneration += 1
        let generation = pulseGeneration
        pulseTimer?.invalidate()
        pulseTimer = nil
        guard phase == .guiding, !isSuspended,
              let distance = distanceToActiveMeters ?? rerollPulseDistance else { return }
        var interval = Self.pulseInterval(forDistance: distance, tier: currentTier)
        #if DEBUG
        if let override = _test_pulseIntervalOverride { interval = override }
        #endif
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.pulseTimerFired(generation: generation)
        }
        RunLoop.main.add(timer, forMode: .common)
        pulseTimer = timer
    }

    private func invalidatePulseTimer() {
        pulseGeneration += 1
        pulseTimer?.invalidate()
        pulseTimer = nil
    }

    // MARK: - Location intake

    func processLocation(_ location: CLLocation) {
        guard !isSuspended, phase == .guiding || phase == .arrived else { return }
        lastCoordinate = location.coordinate
        recordCourse(of: location)
        guard let active = activeClearing else { return }
        let center = CLLocation(latitude: active.center.latitude, longitude: active.center.longitude)
        let distance = location.distance(from: center)
        distanceToActiveMeters = distance
        rerollPulseDistance = nil

        switch phase {
        case .guiding:
            updateArrivalDebounce(location: location, distance: distance, radius: active.radiusMeters)
        case .arrived:
            stillnessDetector?.recordLocation(location)
            evaluateStillness(at: now())
        case .revealing, .complete:
            break
        }
    }

    func processSteps(_ count: Int) {
        guard phase == .arrived, !isSuspended else { return }
        stillnessDetector?.recordSteps(count)
        evaluateStillness(at: now())
    }

    /// Fixes worse than the accuracy gate neither advance nor reset the
    /// consecutive count — a momentary multipath fix must not erase honest
    /// progress toward arrival, and must never fake it either.
    private func updateArrivalDebounce(location: CLLocation, distance: Double, radius: Double) {
        let accuracy = location.horizontalAccuracy
        guard accuracy >= 0, accuracy <= SeekEngineTuning.arrivalAccuracyMeters else {
            ensurePulseScheduled()
            return
        }
        consecutiveInsideCount = distance <= radius ? consecutiveInsideCount + 1 : 0
        if consecutiveInsideCount >= SeekEngineTuning.arrivalFixCount {
            transitionToArrived()
        } else {
            ensurePulseScheduled()
        }
    }

    private func transitionToArrived() {
        phase = .arrived
        consecutiveInsideCount = 0
        invalidatePulseTimer()
        let baseWindow = stillnessWindowOverride
            ?? Double.random(in: SeekEngineTuning.stillnessWindowRange)
        let detector = SeekStillnessDetector(motion: motionProvider, windowDuration: baseWindow)
        detector.start()
        stillnessDetector = detector
        graceDeadline = now().addingTimeInterval(SeekEngineTuning.graceSeconds)
        startStillnessCheckTimer()
        eventsSubject.send(.arrived(clearingIndex: activeIndex))
    }

    // MARK: - Stillness and reveal

    func evaluateStillness(at date: Date) {
        guard phase == .arrived, !isSuspended, let detector = stillnessDetector else { return }
        switch detector.evaluate(at: date) {
        case .began:
            eventsSubject.send(.stillnessBegan(clearingIndex: activeIndex))
        case .completed:
            reveal()
            return
        case .none:
            break
        }
        if let graceDeadline, date >= graceDeadline {
            reveal()
        }
    }

    private func reveal() {
        stopStillnessMachinery()
        let nextIndex = activeIndex + 1
        guard nextIndex < chain.clearings.count else {
            phase = .complete
            stop()
            eventsSubject.send(.seekComplete)
            return
        }
        activeIndex = nextIndex
        phase = .guiding
        distanceToActiveMeters = nil
        rerollPulseDistance = nil
        consecutiveInsideCount = 0
        eventsSubject.send(.revealedNext(activeIndex: nextIndex))
    }

    private func stopStillnessMachinery() {
        stillnessDetector?.stop()
        stillnessDetector = nil
        stillnessCheckTimer?.invalidate()
        stillnessCheckTimer = nil
        graceDeadline = nil
        suspendedGraceRemaining = nil
    }

    private func startStillnessCheckTimer() {
        stillnessCheckTimer?.invalidate()
        let timer = Timer(
            timeInterval: SeekEngineTuning.stillnessCheckInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            self.evaluateStillness(at: self.now())
        }
        RunLoop.main.add(timer, forMode: .common)
        stillnessCheckTimer = timer
    }

    // MARK: - Suspension (origin R15)

    private func handleStatus(_ status: WalkBuilder.Status) {
        if status.isPausedStatus {
            suspend()
        } else if status == .recording {
            resumeFromSuspension()
        }
    }

    private func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        invalidatePulseTimer()
        stillnessCheckTimer?.invalidate()
        stillnessCheckTimer = nil
        if let deadline = graceDeadline {
            suspendedGraceRemaining = max(0, deadline.timeIntervalSince(now()))
            graceDeadline = nil
        }
        stillnessDetector?.suspend()
    }

    private func resumeFromSuspension() {
        guard isSuspended else { return }
        isSuspended = false
        if let remaining = suspendedGraceRemaining {
            graceDeadline = now().addingTimeInterval(remaining)
            suspendedGraceRemaining = nil
        }
        stillnessDetector?.resume()
        if phase == .arrived {
            startStillnessCheckTimer()
        } else if phase == .guiding {
            ensurePulseScheduled()
        }
    }

    private func handleTier(_ tier: WalkSessionGuard.PowerTier) {
        currentTier = tier
        if pulseTimer?.isValid == true {
            schedulePulse()
        }
    }

    // MARK: - Alignment

    private var activeClearing: SeekClearing? {
        guard chain.clearings.indices.contains(activeIndex) else { return nil }
        return chain.clearings[activeIndex]
    }

    private var isAligned: Bool {
        guard let coordinate = lastCoordinate,
              let active = activeClearing,
              let heading = Self.smoothedHeading(of: courseSamples.map { $0.course }) else {
            return false
        }
        let bearing = SeekChainGenerator.bearingDegrees(
            from: SeekPoint(latitude: coordinate.latitude, longitude: coordinate.longitude),
            to: active.center
        )
        return abs(Self.angleDelta(heading, bearing)) <= SeekEngineTuning.alignmentConeDegrees
    }

    private func recordCourse(of location: CLLocation) {
        if location.course >= 0 {
            courseSamples.append((timestamp: location.timestamp, course: location.course))
        }
        guard let newest = courseSamples.last?.timestamp else { return }
        let cutoff = newest.addingTimeInterval(-SeekEngineTuning.headingWindowSeconds)
        courseSamples.removeAll { $0.timestamp < cutoff }
    }

    /// Circular mean over the smoothing window — a single corner flap
    /// cannot flip alignment the way per-fix comparison would.
    static func smoothedHeading(of courses: [Double]) -> Double? {
        guard !courses.isEmpty else { return nil }
        var x = 0.0
        var y = 0.0
        for course in courses {
            let radians = course * .pi / 180
            x += cos(radians)
            y += sin(radians)
        }
        guard x != 0 || y != 0 else { return nil }
        return atan2(y, x) * 180 / .pi
    }

    static func angleDelta(_ a: Double, _ b: Double) -> Double {
        ((a - b + 540).truncatingRemainder(dividingBy: 360)) - 180
    }
}
