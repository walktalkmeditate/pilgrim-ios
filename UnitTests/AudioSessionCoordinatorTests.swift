import XCTest
import AVFoundation
@testable import Pilgrim

private final class SpyAudioSession: AudioSessionApplying {

    enum Call: Equatable {
        case setCategory(AVAudioSession.Category, AVAudioSession.CategoryOptions)
        case setActive(Bool)
    }

    private(set) var calls: [Call] = []

    var lastCategory: AVAudioSession.Category? {
        for call in calls.reversed() {
            if case .setCategory(let category, _) = call { return category }
        }
        return nil
    }

    var lastOptions: AVAudioSession.CategoryOptions? {
        for call in calls.reversed() {
            if case .setCategory(_, let options) = call { return options }
        }
        return nil
    }

    var isActive: Bool {
        for call in calls.reversed() {
            if case .setActive(let active) = call { return active }
        }
        return false
    }

    var deactivationCount: Int {
        calls.filter { $0 == .setActive(false) }.count
    }

    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws {
        calls.append(.setCategory(category, options))
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        calls.append(.setActive(active))
    }
}

final class AudioSessionCoordinatorTests: XCTestCase {

    private var spy: SpyAudioSession!
    private var coordinator: AudioSessionCoordinator!

    override func setUp() {
        super.setUp()
        spy = SpyAudioSession()
        coordinator = AudioSessionCoordinator(session: spy)
    }

    override func tearDown() {
        coordinator = nil
        spy = nil
        super.tearDown()
    }

    /// Interruption events are delivered async on the main queue; one pump
    /// guarantees enqueued deliveries have run.
    private func pumpMainQueue() {
        let exp = expectation(description: "main queue pump")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - Arbitration table

    func testSinglePlaybackConsumer_appliesPlaybackWithMixing() {
        coordinator.activate(for: .playbackOnly, consumer: "soundscape")

        XCTAssertEqual(spy.lastCategory, .playback)
        XCTAssertEqual(spy.lastOptions, [.mixWithOthers])
        XCTAssertTrue(spy.isActive)
    }

    func testTwoPlaybackConsumers_oneEnds_playbackStaysActive() {
        coordinator.activate(for: .playbackOnly, consumer: "soundscape")
        coordinator.activate(for: .playbackOnly, consumer: "bell")

        coordinator.deactivate(consumer: "bell")

        XCTAssertEqual(spy.lastCategory, .playback)
        XCTAssertTrue(spy.isActive)
        XCTAssertEqual(spy.deactivationCount, 0, "session must not deactivate while a consumer remains")
    }

    func testRecordingJoinsPlayback_promotesToRecordAndPlay() {
        coordinator.activate(for: .playbackOnly, consumer: "soundscape")
        coordinator.activate(for: .recordingOnly, consumer: "voiceRecording")

        XCTAssertEqual(spy.lastCategory, .playAndRecord)
        XCTAssertEqual(spy.lastOptions?.contains(.mixWithOthers), true,
                       "the live playback consumer's mixing requirement must survive the join")
        XCTAssertEqual(spy.lastOptions?.contains(.defaultToSpeaker), true)
    }

    func testRecordingEnds_downgradesToPlaybackOnly_micCategoryReleased() {
        coordinator.activate(for: .playbackOnly, consumer: "soundscape")
        coordinator.activate(for: .recordingOnly, consumer: "voiceRecording")

        coordinator.deactivate(consumer: "voiceRecording")

        XCTAssertEqual(spy.lastCategory, .playback,
                       "an input-capable category must not persist after recording stops")
        XCTAssertEqual(spy.lastOptions, [.mixWithOthers])
        XCTAssertTrue(spy.isActive)
    }

    func testRecordingOnlyAlone_doesNotMixWithOthers() {
        coordinator.activate(for: .recordingOnly, consumer: "intentionRecorder")

        XCTAssertEqual(spy.lastCategory, .playAndRecord)
        XCTAssertEqual(spy.lastOptions?.contains(.mixWithOthers), false)
    }

    func testExplicitRecordAndPlayConsumer_resolvesRecordAndPlay() {
        coordinator.activate(for: .recordAndPlay, consumer: "voiceRecording")

        XCTAssertEqual(spy.lastCategory, .playAndRecord)
        XCTAssertEqual(spy.lastOptions?.contains(.mixWithOthers), true)
    }

    func testLastConsumerLeaves_sessionDeactivates() {
        coordinator.activate(for: .playbackOnly, consumer: "bell")
        coordinator.deactivate(consumer: "bell")

        XCTAssertFalse(spy.isActive)
        XCTAssertEqual(spy.deactivationCount, 1)
    }

    func testDeactivateTwiceOrUnknown_noUnderflowNoSpuriousIdle() {
        coordinator.activate(for: .playbackOnly, consumer: "soundscape")

        coordinator.deactivate(consumer: "never-activated")
        coordinator.deactivate(consumer: "soundscape")
        coordinator.deactivate(consumer: "soundscape")

        XCTAssertEqual(spy.deactivationCount, 1,
                       "double/unknown deactivation must not re-deactivate or disturb state")
        XCTAssertEqual(coordinator.currentMode, .idle)
    }

    func testRedundantActivateSameResolvedMode_doesNotReapplyCategory() {
        coordinator.activate(for: .playbackOnly, consumer: "soundscape")
        let callsAfterFirst = spy.calls.count

        coordinator.activate(for: .playbackOnly, consumer: "bell")

        XCTAssertEqual(spy.calls.count, callsAfterFirst,
                       "an activation that doesn't change the resolved mode must not touch the session")
    }

    // MARK: - Interruption broadcast

    func testInterruptionBegan_broadcastsToObservers() {
        var received: [AudioSessionCoordinator.InterruptionEvent] = []
        coordinator.addInterruptionObserver(id: "test") { received.append($0) }

        coordinator._test_simulateInterruptionBegan()
        pumpMainQueue()

        XCTAssertEqual(received, [.began])
    }

    func testInterruptionEnded_propagatesShouldResumeFlag() {
        var received: [AudioSessionCoordinator.InterruptionEvent] = []
        coordinator.addInterruptionObserver(id: "test") { received.append($0) }

        coordinator._test_simulateInterruptionBegan()
        coordinator._test_simulateInterruptionEnded(shouldResume: true)
        pumpMainQueue()

        XCTAssertEqual(received, [.began, .ended(shouldResume: true)])
    }

    func testInterruptionEnded_withoutResumeFlag_propagatesFalse() {
        var received: [AudioSessionCoordinator.InterruptionEvent] = []
        coordinator.addInterruptionObserver(id: "test") { received.append($0) }

        coordinator._test_simulateInterruptionBegan()
        coordinator._test_simulateInterruptionEnded(shouldResume: false)
        pumpMainQueue()

        XCTAssertEqual(received, [.began, .ended(shouldResume: false)])
    }

    // MARK: - Deferred mode application during interruption

    func testActivateDuringInterruption_deferredUntilEnded() {
        coordinator.activate(for: .playbackOnly, consumer: "soundscape")
        coordinator._test_simulateInterruptionBegan()
        let callsDuringInterruption = spy.calls.count

        coordinator.activate(for: .playbackOnly, consumer: "bell")
        XCTAssertEqual(spy.calls.count, callsDuringInterruption,
                       "setActive must not run while another app holds the session")

        coordinator._test_simulateInterruptionEnded(shouldResume: true)
        XCTAssertEqual(spy.lastCategory, .playback)
        XCTAssertTrue(spy.isActive)
    }

    func testDeactivateBetweenBeganAndEnded_noSessionCalls_survivorsResumeOnEnded() {
        coordinator.activate(for: .playbackOnly, consumer: "soundscape")
        coordinator.activate(for: .recordingOnly, consumer: "voiceRecording")
        coordinator._test_simulateInterruptionBegan()
        let callsDuringInterruption = spy.calls.count

        coordinator.deactivate(consumer: "voiceRecording")
        XCTAssertEqual(spy.calls.count, callsDuringInterruption)

        coordinator._test_simulateInterruptionEnded(shouldResume: true)
        XCTAssertEqual(spy.lastCategory, .playback,
                       "survivor's downgraded mode (mic released) must be what gets reapplied")
        XCTAssertTrue(spy.isActive)
    }

    func testObserverDeactivatesItselfOnBegan_noDeadlock_endedAppliesIdle() {
        coordinator.activate(for: .playbackOnly, consumer: "self-removing")
        coordinator.addInterruptionObserver(id: "self-removing") { [weak coordinator] event in
            if event == .began {
                coordinator?.deactivate(consumer: "self-removing")
            }
        }

        coordinator._test_simulateInterruptionBegan()
        pumpMainQueue()

        XCTAssertFalse(coordinator._test_isConsumerActive("self-removing"))

        coordinator._test_simulateInterruptionEnded(shouldResume: true)
        XCTAssertFalse(spy.isActive, "no consumers remain, so .ended must settle the session idle")
    }

    func testDidBecomeActiveDuringInterruption_recoversWithoutAutoResume() {
        var received: [AudioSessionCoordinator.InterruptionEvent] = []
        coordinator.activate(for: .playbackOnly, consumer: "soundscape")
        coordinator.addInterruptionObserver(id: "test") { received.append($0) }

        coordinator._test_simulateInterruptionBegan()
        coordinator._test_simulateDidBecomeActive()
        pumpMainQueue()

        XCTAssertEqual(received, [.began, .ended(shouldResume: false)],
                       "a missing .ended must be closed out on app activation, without auto-resume")
        XCTAssertEqual(spy.lastCategory, .playback)
        XCTAssertTrue(spy.isActive)
    }

    func testDidBecomeActiveWithoutInterruption_doesNothing() {
        coordinator.activate(for: .playbackOnly, consumer: "soundscape")
        let callsBefore = spy.calls.count

        coordinator._test_simulateDidBecomeActive()
        pumpMainQueue()

        XCTAssertEqual(spy.calls.count, callsBefore)
    }
}
