import XCTest
import AVFoundation
import Combine
@testable import Pilgrim

// MARK: - VoiceGuidePlayer (AF6)

final class VoiceGuidePlayerStopTests: XCTestCase {

    func testStop_invokesPendingOnFinished() throws {
        let avPlayer = try TestAudioFile.makePlayer(duration: 5)
        avPlayer.play()
        var finished = false
        VoiceGuidePlayer.shared._test_install(player: avPlayer, onFinished: { finished = true })

        VoiceGuidePlayer.shared.stop()

        XCTAssertTrue(finished, "stop() must hand the pending callback its completion or the scheduler latch wedges")
        XCTAssertFalse(VoiceGuidePlayer.shared.isPlaying)
    }

    func testStop_invokesCallbackExactlyOnce() throws {
        let avPlayer = try TestAudioFile.makePlayer(duration: 5)
        avPlayer.play()
        var callCount = 0
        VoiceGuidePlayer.shared._test_install(player: avPlayer, onFinished: { callCount += 1 })

        VoiceGuidePlayer.shared.stop()
        VoiceGuidePlayer.shared.stop()

        XCTAssertEqual(callCount, 1)
    }
}

// MARK: - AudioPlayerModel (AF15/AF16)

final class AudioPlayerModelLifecycleTests: XCTestCase {

    func testDeinitMidPlayback_releasesAudioSessionConsumer() throws {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let relativePath = "test-audio-player-\(UUID().uuidString).wav"
        let fileURL = docs.appendingPathComponent(relativePath)
        try TestAudioFile.writeSilentAudioFile(to: fileURL, duration: 5)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var model: AudioPlayerModel? = AudioPlayerModel()
        model?.play(relativePath: relativePath)
        XCTAssertEqual(model?.isPlaying, true, "precondition: playback started")
        XCTAssertTrue(AudioSessionCoordinator.shared._test_isConsumerActive("audioPlayer"))

        weak var weakModel = model
        model = nil

        XCTAssertNil(weakModel)
        XCTAssertFalse(AudioSessionCoordinator.shared._test_isConsumerActive("audioPlayer"),
                       "dismissing the summary mid-playback must not wedge the coordinator")
    }

    func testDeinitWithoutPlayback_isHarmless() {
        var model: AudioPlayerModel? = AudioPlayerModel()
        weak var weakModel = model

        model = nil

        XCTAssertNil(weakModel)
        XCTAssertFalse(AudioSessionCoordinator.shared._test_isConsumerActive("audioPlayer"))
    }
}

// MARK: - VoiceGuideManagement (AF24 + scheduler latch)

final class VoiceGuideManagementResumeTests: XCTestCase {

    private var management: VoiceGuideManagement!
    private var status: CurrentValueSubject<WalkBuilder.Status, Never>!
    private var startDate: CurrentValueSubject<Date?, Never>!
    private var recordingVoice: CurrentValueSubject<Bool, Never>!
    private var meditating: CurrentValueSubject<Bool, Never>!

    override func setUp() {
        super.setUp()
        management = VoiceGuideManagement()
        status = CurrentValueSubject(.recording)
        startDate = CurrentValueSubject(Date().addingTimeInterval(-100))
        recordingVoice = CurrentValueSubject(false)
        meditating = CurrentValueSubject(false)
        management.bindWalkState(
            statusPublisher: status.eraseToAnyPublisher(),
            startDatePublisher: startDate.eraseToAnyPublisher(),
            isRecordingVoicePublisher: recordingVoice.eraseToAnyPublisher(),
            isMeditatingPublisher: meditating.eraseToAnyPublisher()
        )
        pumpMainQueue()
    }

    override func tearDown() {
        management.stopGuiding()
        management = nil
        super.tearDown()
    }

    private func pumpMainQueue() {
        let exp = expectation(description: "main queue pump")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
    }

    private func makePack(id: String = "resume-test-\(UUID().uuidString)") -> VoiceGuidePack {
        let prompts = (1...3).map { (i: Int) -> VoiceGuidePrompt in
            VoiceGuidePrompt(
                id: "prompt_\(String(format: "%02d", i))",
                seq: i,
                durationSec: 5.0,
                fileSizeBytes: 1000,
                r2Key: "voiceguide/\(id)/prompt_\(String(format: "%02d", i)).aac"
            )
        }
        return VoiceGuidePack(
            id: id,
            version: "1",
            name: "Test",
            tagline: "Test pack",
            description: "A test pack",
            theme: "test",
            iconName: "star",
            type: "voiceGuide",
            walkTypes: ["wander"],
            scheduling: PromptDensity(
                densityMinSec: 0,
                densityMaxSec: 0,
                minSpacingSec: 0,
                initialDelaySec: 0,
                walkEndBufferSec: 0
            ),
            totalDurationSec: 15,
            totalSizeBytes: 3000,
            prompts: prompts,
            meditationScheduling: nil,
            meditationPrompts: nil
        )
    }

    func testMeditationEnd_resumesGuideItPaused() {
        management.startGuiding(pack: makePack())
        XCTAssertFalse(management.isPaused)

        meditating.send(true)
        pumpMainQueue()
        XCTAssertTrue(management.isPaused)

        meditating.send(false)
        pumpMainQueue()
        XCTAssertFalse(management.isPaused)
    }

    func testMeditationEnd_doesNotResumeUserPausedGuide() {
        management.startGuiding(pack: makePack())
        management.pauseGuide()
        XCTAssertTrue(management.isPaused)

        meditating.send(true)
        pumpMainQueue()
        meditating.send(false)
        pumpMainQueue()

        XCTAssertTrue(management.isPaused,
                      "ending meditation must not override the user's explicit pause")
    }

    func testUnavailablePrompt_clearsSchedulerLatch_guideKeepsTicking() {
        // No prompt files exist on disk, so every onShouldPlay hits the
        // unavailable path — before the fix that wedged the scheduler's
        // isPlaying latch after the first tick.
        management.startGuiding(pack: makePack())

        management._test_tick()
        XCTAssertEqual(management._test_playedPromptIds.count, 1)

        management._test_tick()
        XCTAssertEqual(management._test_playedPromptIds.count, 2,
                       "a skipped prompt must not silence the guide forever")
    }
}
