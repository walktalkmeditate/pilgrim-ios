import XCTest
import Combine
import CoreLocation
@testable import Pilgrim

final class ActiveWalkSeekTests: XCTestCase {

    private final class FakeAccuracyProvider: SeekAccuracyProviding {
        var hasFullAccuracy = true
        func requestTemporaryFullAccuracy(completion: @escaping (Bool) -> Void) {
            completion(hasFullAccuracy)
        }
    }

    private final class SpySeekSound: SeekSoundPlaying {
        private(set) var prepareCount = 0
        private(set) var pings: [Bool] = []
        private(set) var pingClosenesses: [Double] = []
        private(set) var bowlCount = 0
        private(set) var stopCount = 0
        func prepare() { prepareCount += 1 }
        func playPing(aligned: Bool, closeness: Double) {
            pings.append(aligned)
            pingClosenesses.append(closeness)
        }
        func playBowl() { bowlCount += 1 }
        func stop() { stopCount += 1 }
    }

    private var sound: SpySeekSound!
    private var playedWhispers: [WhisperDefinition] = []

    override func setUp() {
        super.setUp()
        sound = SpySeekSound()
        playedWhispers = []
    }

    override func tearDown() {
        UserPreferences.seekSonarEnabled.delete()
        UserPreferences.seekSonarVolume.delete()
        UserPreferences.seekLastDurationMinutes.delete()
        UserPreferences.seekSafetyShown.delete()
        UserPreferences.soundsEnabled.delete()
        sound = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private var stubWhisper: WhisperDefinition {
        WhisperDefinition(
            id: "test-whisper", title: "Test", category: .presence,
            audioFileName: "test-whisper", durationSec: 1, retiredAt: nil
        )
    }

    private func makeSenses(whisper: WhisperDefinition? = nil) -> SeekSenses {
        var senses = SeekSenses()
        senses.makeSoundPlayer = { [sound] in sound! }
        senses.pickRevealWhisper = { whisper }
        senses.playWhisper = { [weak self] in self?.playedWhispers.append($0) }
        senses.isAppActive = { false }
        senses.revealWhisperDelay = 0.05
        senses.seekCompleteSoundStopDelay = 0.05
        return senses
    }

    private func makeSeekVM(whisper: WhisperDefinition? = nil) -> ActiveWalkViewModel {
        let vm = ActiveWalkViewModel(
            mode: .seek,
            seekAccuracy: FakeAccuracyProvider(),
            seekSenses: makeSenses(whisper: whisper)
        )
        settleCombineSchedulers()
        return vm
    }

    private func routeSample(accuracy: Double = 10) -> TempRouteDataSample {
        TempRouteDataSample(
            uuid: nil, timestamp: Date(),
            latitude: 42.8782, longitude: -8.5448, altitude: 0,
            horizontalAccuracy: accuracy, verticalAccuracy: 10,
            speed: 1.4, direction: 0
        )
    }

    /// Walks the setup stage machine to `.transition` and delivers the first
    /// accurate fix, which boots the engine synchronously.
    private func installEngine(
        on vm: ActiveWalkViewModel,
        durationMinutes: Int = 30,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        vm.beginSeekSetup()
        vm.advanceSeekSetup(durationMinutes: durationMinutes)
        vm.advanceSeekSetupIntentionSet()
        vm.currentLocation = routeSample()
        XCTAssertNotNil(vm.seekEngine, "accurate fix must boot the engine", file: file, line: line)
    }

    private func fix(at point: SeekPoint) -> CLLocation {
        CLLocation(
            coordinate: point.coordinate, altitude: 0,
            horizontalAccuracy: 10, verticalAccuracy: 10,
            course: 0, speed: 1.4, timestamp: Date()
        )
    }

    private func driveArrival(of engine: SeekEngine) {
        let center = engine.chain.clearings[engine.activeIndex].center
        for _ in 0..<SeekEngineTuning.arrivalFixCount {
            engine.processLocation(fix(at: center))
        }
    }

    private func recordedEvents(of vm: ActiveWalkViewModel) throws -> [TempWalkEvent] {
        try awaitPublisher(vm.builder.workoutEventsPublisher)
    }

    private func waitForWhisperWindow(_ seconds: TimeInterval = 0.3) {
        let exp = expectation(description: "reveal whisper window elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 1.0)
    }

    // MARK: - Engine lifecycle

    func testEngineStartsOnFirstAccurateFix_ignoresPoorFixes() {
        let vm = makeSeekVM()
        vm.beginSeekSetup()
        vm.advanceSeekSetup(durationMinutes: 30)
        vm.advanceSeekSetupIntentionSet()

        vm.currentLocation = routeSample(accuracy: 80)
        XCTAssertNil(vm.seekEngine, "a poor fix must not seed the chain")

        vm.currentLocation = routeSample(accuracy: 10)
        let engine = vm.seekEngine
        XCTAssertNotNil(engine)
        XCTAssertEqual(engine?.chain.clearings.count, 1, "30-minute seek generates one clearing (AE1)")
        XCTAssertEqual(sound.prepareCount, 1)
        XCTAssertEqual(vm.seekFogState?.circles.count, 1, "only the active clearing is fogged (R6)")
        XCTAssertEqual(vm.seekFogState?.circles.first?.isHalo, false)
    }

    func testGPSLockFailure_cancelsOnlyFromTransition() {
        let vm = makeSeekVM()
        vm.beginSeekSetup()
        vm.advanceSeekSetup(durationMinutes: 30)
        vm.advanceSeekSetupIntentionSet()

        vm.failSeekSetupGPSLock()
        XCTAssertEqual(vm.seekSetupStage, .cancelled(.gpsTimeout))
    }

    func testGPSLockFailure_isSilentOnceReadyOrEngineExists() {
        let ready = makeSeekVM()
        ready.beginSeekSetup()
        ready.advanceSeekSetup(durationMinutes: 30)
        ready.advanceSeekSetupIntentionSet()
        ready.advanceSeekSetupTransitionComplete()
        ready.failSeekSetupGPSLock()
        XCTAssertEqual(ready.seekSetupStage, .ready, "a recording walk must not be yanked home")

        let engined = makeSeekVM()
        installEngine(on: engined)
        engined.failSeekSetupGPSLock()
        XCTAssertEqual(engined.seekSetupStage, .transition)
    }

    func testGPSTimeout_lateAccurateFix_doesNotBootEngine() {
        let vm = makeSeekVM()
        vm.beginSeekSetup()
        vm.advanceSeekSetup(durationMinutes: 30)
        vm.advanceSeekSetupIntentionSet()

        vm.failSeekSetupGPSLock()
        vm.currentLocation = routeSample()

        XCTAssertNil(vm.seekEngine, "a fix arriving after timeout cancellation must stay a no-op")
        XCTAssertEqual(vm.seekSetupStage, .cancelled(.gpsTimeout))
    }

    // MARK: - Arrival persistence (R13, R18)

    func testArrival_recordsExactlyOneWaypointAndOneArrivalEvent() throws {
        let vm = makeSeekVM()
        installEngine(on: vm)
        let engine = try XCTUnwrap(vm.seekEngine)

        driveArrival(of: engine)

        XCTAssertEqual(engine.phase, .arrived)
        XCTAssertEqual(vm.waypoints.count, 1, "exactly one waypoint per arrival")
        XCTAssertEqual(vm.waypoints.first?.icon, SeekPersistence.arrivalWaypointIcon)
        XCTAssertEqual(vm.waypoints.first?.label, SeekPersistence.arrivalWaypointLabel(clearingOrdinal: 1))
        XCTAssertEqual(try recordedEvents(of: vm).map(\.eventType), [.seekArrival])
    }

    // MARK: - Seek marker event (R18)

    func testSeekMarker_writtenOnceAtRecordingStart() throws {
        UserPreferences.soundsEnabled.value = false
        let vm = makeSeekVM()

        vm.startRecording()

        XCTAssertEqual(try recordedEvents(of: vm).map(\.eventType), [.seekMode])
        vm.stop()
    }

    func testWander_writesZeroEventsAtRecordingStart() throws {
        UserPreferences.soundsEnabled.value = false
        let vm = ActiveWalkViewModel(mode: .wander)
        settleCombineSchedulers()

        vm.startRecording()

        XCTAssertEqual(try recordedEvents(of: vm).count, 0)
        vm.stop()
    }

    // MARK: - Seek anew (R17)

    func testSeekAnew_whileArrived_recordsSequentialOrdinals() throws {
        let vm = makeSeekVM()
        installEngine(on: vm, durationMinutes: 180)
        let engine = try XCTUnwrap(vm.seekEngine)

        driveArrival(of: engine)
        XCTAssertEqual(engine.phase, .arrived)

        vm.seekAnewRequested()
        XCTAssertEqual(engine.phase, .guiding, "reroll from an unrevealed clearing returns to guiding")

        engine.evaluateStillness(at: Date().addingTimeInterval(SeekEngineTuning.graceSeconds + 1))
        XCTAssertEqual(engine.activeIndex, 0, "the stale grace window must not reveal after the reroll")
        XCTAssertEqual(engine.phase, .guiding)

        driveArrival(of: engine)

        XCTAssertEqual(
            vm.waypoints.map(\.label),
            [
                SeekPersistence.arrivalWaypointLabel(clearingOrdinal: 1),
                SeekPersistence.arrivalWaypointLabel(clearingOrdinal: 2)
            ],
            "ordinals count persisted arrivals, not the replayed clearing index"
        )
        XCTAssertEqual(try recordedEvents(of: vm).map(\.eventType), [.seekArrival, .seekArrival])
    }

    func testSeekAnew_regeneratesRemainder_prefixStable() throws {
        let vm = makeSeekVM()
        installEngine(on: vm, durationMinutes: 180)
        let engine = try XCTUnwrap(vm.seekEngine)
        XCTAssertGreaterThanOrEqual(engine.chain.clearings.count, 2)

        driveArrival(of: engine)
        engine.evaluateStillness(at: Date().addingTimeInterval(SeekEngineTuning.graceSeconds + 1))
        XCTAssertEqual(engine.activeIndex, 1)

        let before = engine.chain
        vm.seekAnewRequested()

        XCTAssertEqual(engine.chain.clearings.count, before.clearings.count)
        XCTAssertEqual(engine.chain.clearings[0], before.clearings[0], "reached prefix is kept")
        XCTAssertNotEqual(engine.chain.clearings[1], before.clearings[1], "active clearing rerolled")
        XCTAssertEqual(engine.activeIndex, 1)
        XCTAssertEqual(vm.waypoints.count, 1, "reroll never touches recorded arrivals")
    }

    // MARK: - Event routing

    func testPulseEvent_incrementsTokenAndPlaysPing() {
        let vm = makeSeekVM()
        vm.seekSound = sound

        vm.handleSeekEvent(.pulse(aligned: true, distanceMeters: 250))
        vm.handleSeekEvent(.pulse(aligned: false, distanceMeters: 250))

        XCTAssertEqual(vm.seekPulse.token, 2)
        XCTAssertFalse(vm.seekPulse.aligned, "the last pulse's alignment rides along to the map")
        XCTAssertEqual(
            vm.seekPulse.closeness,
            SeekEngine.closeness(forDistanceMeters: 250),
            accuracy: 0.0001,
            "closeness shapes the wisp flare like it shapes ping and haptic"
        )
        XCTAssertEqual(sound.pings, [true, false])
    }

    // MARK: - Reveal ritual (R15)

    func testRevealedNext_playsBowlThenWhisperAfterDelay() {
        let vm = makeSeekVM(whisper: stubWhisper)
        vm.seekSound = sound

        vm.handleSeekEvent(.revealedNext(activeIndex: 1))

        XCTAssertEqual(sound.bowlCount, 1)
        XCTAssertTrue(playedWhispers.isEmpty, "the whisper waits for the bowl to ring")

        waitForWhisperWindow()
        XCTAssertEqual(playedWhispers.map(\.id), ["test-whisper"])
    }

    func testRevealedNext_zeroDownloadedWhispers_bowlOnly() {
        let vm = makeSeekVM(whisper: nil)
        vm.seekSound = sound

        vm.handleSeekEvent(.revealedNext(activeIndex: 1))
        waitForWhisperWindow()

        XCTAssertEqual(sound.bowlCount, 1, "the ritual proceeds without a whisper")
        XCTAssertTrue(playedWhispers.isEmpty)
    }

    func testSeekComplete_playsBowlWithoutWhisper() {
        let vm = makeSeekVM(whisper: stubWhisper)
        vm.seekSound = sound

        vm.handleSeekEvent(.seekComplete)
        waitForWhisperWindow()

        XCTAssertEqual(sound.bowlCount, 1)
        XCTAssertTrue(playedWhispers.isEmpty, "the final bowl closes the seeking quietly")
    }

    func testSeekComplete_releasesSoundOnceBowlHasRung() {
        let vm = makeSeekVM()
        vm.seekSound = sound

        vm.handleSeekEvent(.seekComplete)
        XCTAssertEqual(sound.stopCount, 0, "the bowl must ring before the consumer is released")

        waitForWhisperWindow()
        XCTAssertEqual(sound.stopCount, 1, "a post-stop bowl cleans up after itself")
    }

    /// The whisper half of the master-toggle gate lives here; the audible
    /// half — playPing/playBowl producing zero play attempts — is pinned in
    /// SeekSoundPlayerTests, because the view model routes events
    /// unconditionally and the player owns the master Sounds gate.
    func testRevealedNext_soundsDisabled_suppressesWhisperAndPing() {
        UserPreferences.soundsEnabled.value = false
        let vm = makeSeekVM(whisper: stubWhisper)
        vm.seekSound = sound

        vm.handleSeekEvent(.revealedNext(activeIndex: 1))
        waitForWhisperWindow()

        XCTAssertTrue(playedWhispers.isEmpty, "master Sounds off suppresses the reveal whisper")
    }

    // MARK: - Teardown

    func testStop_stopsEngineAndSound_cancelsPendingWhisper_noEventsAfter() throws {
        UserPreferences.soundsEnabled.value = true
        let vm = makeSeekVM(whisper: stubWhisper)
        installEngine(on: vm)
        let engine = try XCTUnwrap(vm.seekEngine)
        engine.processLocation(fix(at: SeekPoint(latitude: 42.8782, longitude: -8.5448)))

        vm.handleSeekEvent(.revealedNext(activeIndex: 0))
        UserPreferences.soundsEnabled.value = false
        vm.stop()

        XCTAssertGreaterThanOrEqual(sound.stopCount, 1)
        let tokenAfterStop = vm.seekPulse.token
        engine.emitPulse()
        XCTAssertEqual(vm.seekPulse.token, tokenAfterStop, "no seek events may flow after stop")

        waitForWhisperWindow()
        XCTAssertTrue(playedWhispers.isEmpty, "teardown cancels the pending reveal whisper")
    }

    func testDeinit_releasesViewModelAndEngine() {
        weak var weakVM: ActiveWalkViewModel?
        weak var weakEngine: SeekEngine?
        autoreleasepool {
            let vm = makeSeekVM()
            installEngine(on: vm)
            weakVM = vm
            weakEngine = vm.seekEngine
        }
        XCTAssertNil(weakVM, "the view model must not outlive the walk")
        XCTAssertNil(weakEngine, "the engine must not outlive the view model")
    }

    // MARK: - Wander regression

    func testWander_neverGrowsSeekState() {
        let vm = ActiveWalkViewModel(mode: .wander)
        settleCombineSchedulers()

        vm.beginSeekSetup()
        vm.advanceSeekSetup(durationMinutes: 60)
        vm.advanceSeekSetupIntentionSet()
        vm.currentLocation = routeSample()
        vm.seekAnewRequested()

        XCTAssertNil(vm.seekEngine)
        XCTAssertNil(vm.seekFogState)
        XCTAssertEqual(vm.seekPulse, .none)
        XCTAssertFalse(vm.isSeekComplete)
    }
}
