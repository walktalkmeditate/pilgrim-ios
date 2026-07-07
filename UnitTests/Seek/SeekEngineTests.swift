import XCTest
import Combine
import CoreLocation
@testable import Pilgrim

final class SeekEngineTests: XCTestCase {

    private final class TestClock {
        var now = Date(timeIntervalSinceReferenceDate: 10_000)
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    private let home = SeekPoint(latitude: 42.8782, longitude: -8.5448)
    private var clock: TestClock!
    private var motion: FakeMotionActivityProvider!
    private var events: [SeekEngineEvent] = []
    private var cancellables: [AnyCancellable] = []

    override func setUp() {
        super.setUp()
        clock = TestClock()
        motion = FakeMotionActivityProvider()
        events = []
        cancellables = []
    }

    // MARK: - Helpers

    private func makeChain(count: Int, spacingMeters: Double = 1000) -> SeekChain {
        let clearings = (1...count).map { index in
            SeekClearing(
                center: SeekChainGenerator.destination(
                    from: home, bearingDegrees: 0, distanceMeters: spacingMeters * Double(index)
                ),
                radiusMeters: 50
            )
        }
        return SeekChain(clearings: clearings, budgetMeters: 5000)
    }

    private func makeEngine(clearingCount: Int = 1, window: TimeInterval = 60) -> SeekEngine {
        let clock = self.clock!
        let engine = SeekEngine(
            chain: makeChain(count: clearingCount),
            home: home,
            now: { clock.now },
            motionProvider: motion,
            stillnessWindowOverride: window
        )
        engine.events.sink { [weak self] in self?.events.append($0) }.store(in: &cancellables)
        return engine
    }

    private func bind(
        _ engine: SeekEngine,
        status: PassthroughSubject<WalkBuilder.Status, Never> = .init(),
        tier: PassthroughSubject<WalkSessionGuard.PowerTier, Never> = .init()
    ) {
        engine.bind(
            locations: Empty<CLLocation, Never>().eraseToAnyPublisher(),
            stepCounts: Empty<Int, Never>().eraseToAnyPublisher(),
            builderStatus: status.eraseToAnyPublisher(),
            powerTier: tier.eraseToAnyPublisher()
        )
    }

    private func fix(at point: SeekPoint, accuracy: Double = 10, course: Double = -1) -> CLLocation {
        CLLocation(
            coordinate: point.coordinate, altitude: 0,
            horizontalAccuracy: accuracy, verticalAccuracy: 10,
            course: course, speed: 1.4, timestamp: clock.now
        )
    }

    private func point(metersNorthOfHome meters: Double) -> SeekPoint {
        SeekChainGenerator.destination(from: home, bearingDegrees: 0, distanceMeters: meters)
    }

    private func arrive(_ engine: SeekEngine, at center: SeekPoint) {
        for _ in 0..<SeekEngineTuning.arrivalFixCount {
            engine.processLocation(fix(at: center))
            clock.advance(1)
        }
    }

    private func pulses() -> [(aligned: Bool, distance: Double)] {
        events.compactMap {
            if case .pulse(let aligned, let distance) = $0 { return (aligned, distance) }
            return nil
        }
    }

    private func count(of event: SeekEngineEvent) -> Int {
        events.filter { $0 == event }.count
    }

    private func stillnessBeganCount() -> Int {
        events.filter {
            if case .stillnessBegan = $0 { return true }
            return false
        }.count
    }

    private func drainMain() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }

    // MARK: - AE2: misalignment is positive-only

    func testWalkingDirectlyAway_pulsesUnalignedAndNothingElse() {
        let engine = makeEngine()
        var position = home
        for _ in 0..<6 {
            position = SeekChainGenerator.destination(
                from: position, bearingDegrees: 180, distanceMeters: 30
            )
            engine.processLocation(fix(at: position, course: 180))
            clock.advance(2)
            engine.emitPulse()
        }
        XCTAssertEqual(events.count, 6, "walking away produces pulses and nothing else")
        XCTAssertEqual(pulses().count, 6)
        XCTAssertTrue(pulses().allSatisfy { !$0.aligned })
    }

    // MARK: - Pulse cadence

    func testPulseInterval_mapsDistanceLinearlyAndClampsAtEnds() {
        XCTAssertEqual(SeekEngine.pulseInterval(forDistance: 3000, tier: .normal), 60, accuracy: 0.001)
        XCTAssertEqual(SeekEngine.pulseInterval(forDistance: 2000, tier: .normal), 60, accuracy: 0.001)
        XCTAssertEqual(SeekEngine.pulseInterval(forDistance: 100, tier: .normal), 10, accuracy: 0.001)
        XCTAssertEqual(SeekEngine.pulseInterval(forDistance: 40, tier: .normal), 10, accuracy: 0.001)

        var previous = Double.infinity
        for distance in stride(from: 2200.0, through: 80.0, by: -40) {
            let interval = SeekEngine.pulseInterval(forDistance: distance, tier: .normal)
            XCTAssertLessThanOrEqual(interval, previous, "cadence must shorten monotonically")
            previous = interval
        }
    }

    func testPulseInterval_lowAndCriticalTiersRaiseFloor() {
        XCTAssertEqual(SeekEngine.pulseInterval(forDistance: 100, tier: .low), 30, accuracy: 0.001)
        XCTAssertEqual(SeekEngine.pulseInterval(forDistance: 100, tier: .critical), 30, accuracy: 0.001)
        XCTAssertEqual(SeekEngine.pulseInterval(forDistance: 2000, tier: .low), 60, accuracy: 0.001)
        XCTAssertEqual(SeekEngine.pulseInterval(forDistance: 100, tier: .meditation), 10, accuracy: 0.001)
    }

    // MARK: - Arrival debounce

    func testSingleStrayFixInside_doesNotArrive() {
        let engine = makeEngine()
        let center = point(metersNorthOfHome: 1000)
        engine.processLocation(fix(at: center))
        clock.advance(1)
        engine.processLocation(fix(at: point(metersNorthOfHome: 800)))
        clock.advance(1)
        engine.processLocation(fix(at: center))
        clock.advance(1)
        engine.processLocation(fix(at: center))
        XCTAssertEqual(engine.phase, .guiding)
        XCTAssertEqual(count(of: .arrived(clearingIndex: 0)), 0)
    }

    func testThreeConsecutiveGatedFixes_arriveAndPausePulseClock() {
        let engine = makeEngine()
        arrive(engine, at: point(metersNorthOfHome: 1000))
        XCTAssertEqual(engine.phase, .arrived)
        XCTAssertEqual(count(of: .arrived(clearingIndex: 0)), 1)

        engine.emitPulse()
        XCTAssertTrue(pulses().isEmpty, "no pulses while arrived")
    }

    func testLowAccuracyFixes_neitherAdvanceNorResetDebounce() {
        let engine = makeEngine()
        let center = point(metersNorthOfHome: 1000)
        engine.processLocation(fix(at: center))
        clock.advance(1)
        engine.processLocation(fix(at: point(metersNorthOfHome: 700), accuracy: 80))
        clock.advance(1)
        engine.processLocation(fix(at: center, accuracy: 80))
        clock.advance(1)
        engine.processLocation(fix(at: center))
        clock.advance(1)
        XCTAssertEqual(engine.phase, .guiding, "only two good fixes so far")
        engine.processLocation(fix(at: center))
        XCTAssertEqual(engine.phase, .arrived)
    }

    // MARK: - Alignment smoothing

    func testCourseFlapping_withinSmoothingWindow_doesNotFlipAlignment() {
        let engine = makeEngine()
        for course in [355.0, 5, 0, 90, 2, 358] {
            engine.processLocation(fix(at: home, course: course))
            clock.advance(2)
            engine.emitPulse()
        }
        XCTAssertEqual(pulses().count, 6)
        XCTAssertTrue(
            pulses().allSatisfy(\.aligned),
            "one corner flap inside the smoothing window must not flip alignment"
        )
    }

    func testStaleCourseSamples_agePastSmoothingWindow() {
        let engine = makeEngine()
        for _ in 0..<3 {
            engine.processLocation(fix(at: home, course: 0))
            clock.advance(2)
        }
        clock.advance(SeekEngineTuning.headingWindowSeconds + 5)
        engine.processLocation(fix(at: home, course: 180))
        engine.emitPulse()
        XCTAssertEqual(pulses().last?.aligned, false, "only the fresh reversed course remains")
    }

    // MARK: - Stillness reveal

    func testStillness_beginsThenRevealsNextClearing() {
        let engine = makeEngine(clearingCount: 2)
        arrive(engine, at: point(metersNorthOfHome: 1000))

        engine.processSteps(100)
        motion.sendStationary(true)
        engine.processLocation(fix(at: point(metersNorthOfHome: 1000)))
        engine.processLocation(fix(at: point(metersNorthOfHome: 1003)))
        XCTAssertEqual(stillnessBeganCount(), 1)

        let beganAt = clock.now
        engine.evaluateStillness(at: beganAt.addingTimeInterval(59))
        XCTAssertEqual(engine.phase, .arrived)
        engine.evaluateStillness(at: beganAt.addingTimeInterval(60))
        XCTAssertEqual(count(of: .revealedNext(activeIndex: 1)), 1)
        XCTAssertEqual(engine.phase, .guiding)
        XCTAssertEqual(engine.activeIndex, 1)
    }

    // MARK: - AE4: grace fallback

    func testGrace_revealsQuietlyWithoutStillness() {
        let engine = makeEngine(clearingCount: 2)
        arrive(engine, at: point(metersNorthOfHome: 1000))
        clock.advance(SeekEngineTuning.graceSeconds + 1)
        engine.evaluateStillness(at: clock.now)
        XCTAssertEqual(count(of: .revealedNext(activeIndex: 1)), 1)
        XCTAssertEqual(stillnessBeganCount(), 0, "grace reveal is quiet — no stillness ever began")
        XCTAssertEqual(engine.phase, .guiding)
        XCTAssertEqual(engine.activeIndex, 1)
    }

    // MARK: - Pause suspension (origin R15)

    func testPauseDuringStillness_freezes_resumeKeepsActiveClearing() {
        let engine = makeEngine(clearingCount: 2)
        let status = PassthroughSubject<WalkBuilder.Status, Never>()
        bind(engine, status: status)

        arrive(engine, at: point(metersNorthOfHome: 1000))
        engine.processSteps(100)
        motion.sendStationary(true)
        engine.processLocation(fix(at: point(metersNorthOfHome: 1000)))
        XCTAssertEqual(stillnessBeganCount(), 1)

        status.send(.paused)
        drainMain()
        clock.advance(600)
        engine.evaluateStillness(at: clock.now)
        XCTAssertEqual(engine.phase, .arrived, "suspension freezes the ritual")
        XCTAssertEqual(count(of: .revealedNext(activeIndex: 1)), 0)

        status.send(.recording)
        drainMain()
        XCTAssertEqual(engine.activeIndex, 0, "resume keeps the same active clearing")
        XCTAssertEqual(engine.phase, .arrived)

        engine.processSteps(100)
        motion.sendStationary(true)
        engine.processLocation(fix(at: point(metersNorthOfHome: 1000)))
        engine.processLocation(fix(at: point(metersNorthOfHome: 1002)))
        XCTAssertEqual(stillnessBeganCount(), 2, "stillness window restarted after resume")
        engine.evaluateStillness(at: clock.now.addingTimeInterval(60))
        XCTAssertEqual(count(of: .revealedNext(activeIndex: 1)), 1)
    }

    // MARK: - Completion

    func testFinalReveal_emitsSeekCompleteOnce_thenEngineGoesQuiet() {
        let engine = makeEngine(clearingCount: 1)
        arrive(engine, at: point(metersNorthOfHome: 1000))
        clock.advance(SeekEngineTuning.graceSeconds)
        engine.evaluateStillness(at: clock.now)
        XCTAssertEqual(count(of: .seekComplete), 1)
        XCTAssertEqual(engine.phase, .complete)

        let countAfterComplete = events.count
        engine.processLocation(fix(at: home))
        engine.emitPulse()
        engine.processSteps(500)
        engine.evaluateStillness(at: clock.now.addingTimeInterval(600))
        XCTAssertEqual(events.count, countAfterComplete, "complete engine must stay silent")
    }

    // MARK: - Seek anew (R17)

    func testSeekAnew_swapsRemainder_keepsPrefixAndActiveIndex_stalePulsesNoOp() {
        let engine = makeEngine(clearingCount: 3)
        arrive(engine, at: point(metersNorthOfHome: 1000))
        clock.advance(SeekEngineTuning.graceSeconds + 1)
        engine.evaluateStillness(at: clock.now)
        XCTAssertEqual(engine.activeIndex, 1)

        let before = engine.chain
        let staleGeneration = engine.pulseGeneration
        engine.seekAnew(currentLocation: point(metersNorthOfHome: 1100))

        XCTAssertEqual(engine.chain.clearings.count, 3)
        XCTAssertEqual(engine.chain.clearings[0], before.clearings[0], "reached prefix is kept")
        XCTAssertNotEqual(engine.chain.clearings[1], before.clearings[1], "active clearing rerolled")
        XCTAssertEqual(engine.activeIndex, 1)
        XCTAssertEqual(engine.phase, .guiding)
        XCTAssertGreaterThan(engine.pulseGeneration, staleGeneration)

        let eventCount = events.count
        engine.pulseTimerFired(generation: staleGeneration)
        XCTAssertEqual(events.count, eventCount, "stale pulse generation must no-op")
    }

    func testSeekAnew_withPriorDistance_pulsesBeforeNextFix() {
        let engine = makeEngine(clearingCount: 2)
        engine.processLocation(fix(at: home))
        XCTAssertNotNil(engine.distanceToActiveMeters)

        engine.seekAnew(currentLocation: home)
        XCTAssertNil(engine.distanceToActiveMeters, "the published distance resets until the next fix")

        engine.pulseTimerFired(generation: engine.pulseGeneration)
        XCTAssertEqual(pulses().count, 1, "the heartbeat continues across the reroll on the stale distance")
    }

    // MARK: - Teardown

    func testStop_silencesPulseTimer() {
        let engine = makeEngine()
        engine._test_pulseIntervalOverride = 0.05
        engine.processLocation(fix(at: home))
        engine.stop()

        let silent = expectation(description: "no pulse after stop")
        silent.isInverted = true
        engine.events.sink { _ in silent.fulfill() }.store(in: &cancellables)
        wait(for: [silent], timeout: 0.3)
    }

    func testDeinit_engineReleasesDespiteScheduledTimer() {
        weak var released: SeekEngine?
        autoreleasepool {
            let engine = SeekEngine(chain: makeChain(count: 1), home: home)
            engine.processLocation(fix(at: home))
            released = engine
        }
        XCTAssertNil(released, "pulse timer must not retain the engine")
    }

    // MARK: - Motion permission denied

    func testMotionDenied_displacementOnlyMode_revealsAfterLengthenedWindow() {
        motion.denied = true
        let engine = makeEngine(clearingCount: 2, window: 60)
        arrive(engine, at: point(metersNorthOfHome: 1000))

        engine.processLocation(fix(at: point(metersNorthOfHome: 1000)))
        engine.processLocation(fix(at: point(metersNorthOfHome: 1003)))
        XCTAssertEqual(stillnessBeganCount(), 1)

        let began = clock.now
        engine.evaluateStillness(at: began.addingTimeInterval(60))
        XCTAssertEqual(
            count(of: .revealedNext(activeIndex: 1)), 0,
            "base window is not enough when motion is denied"
        )
        engine.evaluateStillness(at: began.addingTimeInterval(90))
        XCTAssertEqual(count(of: .revealedNext(activeIndex: 1)), 1)
    }

    // MARK: - Power tier

    func testTierPublisher_reachesEngineAndWidensFloor() {
        let engine = makeEngine()
        let tier = PassthroughSubject<WalkSessionGuard.PowerTier, Never>()
        bind(engine, tier: tier)
        XCTAssertEqual(engine.currentTier, .normal)

        tier.send(.low)
        drainMain()
        XCTAssertEqual(engine.currentTier, .low)
        XCTAssertEqual(
            SeekEngine.pulseInterval(
                forDistance: SeekEngineTuning.nearDistanceMeters, tier: engine.currentTier
            ),
            30, accuracy: 0.001
        )
    }

    func testWalkSessionGuard_exposesCurrentTierPublisher() {
        let sessionGuard = WalkSessionGuard()
        var tiers: [WalkSessionGuard.PowerTier] = []
        let subscription = sessionGuard.powerTierPublisher.sink { tiers.append($0) }
        XCTAssertEqual(tiers, [.normal])

        sessionGuard._test_batteryLevelOverride = 0.10
        sessionGuard.start()
        XCTAssertEqual(tiers.last, .low)

        sessionGuard.stop()
        subscription.cancel()
    }
}
