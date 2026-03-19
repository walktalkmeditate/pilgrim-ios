import XCTest
@testable import Pilgrim

final class VoiceGuideSchedulerTests: XCTestCase {

    private func makePack(
        promptCount: Int = 5,
        densityMin: Int = 60,
        densityMax: Int = 120,
        initialDelay: Int = 30,
        walkEndBuffer: Int = 30
    ) -> VoiceGuidePack {
        let prompts = (1...promptCount).map { (i: Int) -> VoiceGuidePrompt in
            VoiceGuidePrompt(
                id: "test_\(String(format: "%02d", i))",
                seq: i,
                durationSec: 5.0,
                fileSizeBytes: 1000,
                r2Key: "voiceguide/test/test_\(String(format: "%02d", i)).aac"
            )
        }
        return VoiceGuidePack(
            id: "test",
            version: "1",
            name: "Test",
            tagline: "Test pack",
            description: "A test pack",
            theme: "test",
            iconName: "star",
            type: "voiceGuide",
            walkTypes: ["wander"],
            scheduling: PromptDensity(
                densityMinSec: densityMin,
                densityMaxSec: densityMax,
                minSpacingSec: 60,
                initialDelaySec: initialDelay,
                walkEndBufferSec: walkEndBuffer
            ),
            totalDurationSec: Double(promptCount) * 5.0,
            totalSizeBytes: promptCount * 1000,
            prompts: prompts,
            meditationScheduling: nil,
            meditationPrompts: nil
        )
    }

    // MARK: - Condition Checks

    func testTick_requiresRecordingStatus() {
        let pack = makePack(densityMin: 0, densityMax: 0, initialDelay: 0)
        let scheduler = VoiceGuideScheduler(
            prompts: pack.prompts,
            scheduling: pack.scheduling,
            context: .walk
        )

        var firedPrompt: VoiceGuidePrompt?
        scheduler.onShouldPlay = { (prompt: VoiceGuidePrompt) in firedPrompt = prompt }

        scheduler.updateWalkStartDate(Date().addingTimeInterval(-100))
        scheduler.updateStatus(.waiting)
        scheduler.testTick()
        XCTAssertNil(firedPrompt)

        scheduler.updateStatus(.paused)
        scheduler.testTick()
        XCTAssertNil(firedPrompt)

        scheduler.updateStatus(.recording)
        scheduler.testTick()
        XCTAssertNotNil(firedPrompt)
    }

    func testTick_blockedByVoiceRecording() {
        let pack = makePack(densityMin: 0, densityMax: 0, initialDelay: 0)
        let scheduler = VoiceGuideScheduler(
            prompts: pack.prompts,
            scheduling: pack.scheduling,
            context: .walk
        )

        var firedCount = 0
        scheduler.onShouldPlay = { (_: VoiceGuidePrompt) in firedCount += 1 }

        scheduler.updateWalkStartDate(Date().addingTimeInterval(-100))
        scheduler.updateStatus(.recording)
        scheduler.updateIsRecordingVoice(true)
        scheduler.testTick()
        XCTAssertEqual(firedCount, 0)

        scheduler.updateIsRecordingVoice(false)
        scheduler.testTick()
        XCTAssertEqual(firedCount, 1)
    }

    func testTick_blockedByMeditation() {
        let pack = makePack(densityMin: 0, densityMax: 0, initialDelay: 0)
        let scheduler = VoiceGuideScheduler(
            prompts: pack.prompts,
            scheduling: pack.scheduling,
            context: .walk
        )

        var firedCount = 0
        scheduler.onShouldPlay = { (_: VoiceGuidePrompt) in firedCount += 1 }

        scheduler.updateWalkStartDate(Date().addingTimeInterval(-100))
        scheduler.updateStatus(.recording)
        scheduler.updateIsMeditating(true)
        scheduler.testTick()
        XCTAssertEqual(firedCount, 0)
    }

    func testTick_blockedByPause() {
        let pack = makePack(densityMin: 0, densityMax: 0, initialDelay: 0)
        let scheduler = VoiceGuideScheduler(
            prompts: pack.prompts,
            scheduling: pack.scheduling,
            context: .walk
        )

        var firedCount = 0
        scheduler.onShouldPlay = { (_: VoiceGuidePrompt) in firedCount += 1 }

        scheduler.updateWalkStartDate(Date().addingTimeInterval(-100))
        scheduler.updateStatus(.recording)
        scheduler.pause()
        scheduler.testTick()
        XCTAssertEqual(firedCount, 0)

        scheduler.resume()
        scheduler.testTick()
        XCTAssertEqual(firedCount, 1)
    }

    func testTick_respectsInitialDelay() {
        let pack = makePack(densityMin: 0, densityMax: 0, initialDelay: 300)
        let scheduler = VoiceGuideScheduler(
            prompts: pack.prompts,
            scheduling: pack.scheduling,
            context: .walk
        )

        var firedCount = 0
        scheduler.onShouldPlay = { (_: VoiceGuidePrompt) in firedCount += 1 }

        scheduler.updateStatus(.recording)
        scheduler.updateWalkStartDate(Date().addingTimeInterval(-60))
        scheduler.testTick()
        XCTAssertEqual(firedCount, 0, "Should not fire before initial delay")

        scheduler.updateWalkStartDate(Date().addingTimeInterval(-301))
        scheduler.testTick()
        XCTAssertEqual(firedCount, 1, "Should fire after initial delay")
    }

    // MARK: - Prompt Ordering

    func testNextPrompt_playsInSequentialOrder() {
        let pack = makePack(promptCount: 3, densityMin: 0, densityMax: 0, initialDelay: 0)
        let scheduler = VoiceGuideScheduler(
            prompts: pack.prompts,
            scheduling: pack.scheduling,
            context: .walk
        )

        var playedIds: [String] = []
        scheduler.onShouldPlay = { (prompt: VoiceGuidePrompt) in playedIds.append(prompt.id) }

        scheduler.updateWalkStartDate(Date().addingTimeInterval(-100))
        scheduler.updateStatus(.recording)

        scheduler.testTick()
        scheduler.markPlayed(playedIds.last!)
        scheduler.testTick()
        scheduler.markPlayed(playedIds.last!)
        scheduler.testTick()

        XCTAssertEqual(playedIds, ["test_01", "test_02", "test_03"])
    }

    func testNextPrompt_wrapsAround() {
        let pack = makePack(promptCount: 2, densityMin: 0, densityMax: 0, initialDelay: 0)
        let scheduler = VoiceGuideScheduler(
            prompts: pack.prompts,
            scheduling: pack.scheduling,
            context: .walk
        )

        var playedIds: [String] = []
        scheduler.onShouldPlay = { (prompt: VoiceGuidePrompt) in playedIds.append(prompt.id) }

        scheduler.updateWalkStartDate(Date().addingTimeInterval(-100))
        scheduler.updateStatus(.recording)

        scheduler.testTick()
        scheduler.markPlayed(playedIds.last!)
        scheduler.testTick()
        scheduler.markPlayed(playedIds.last!)
        scheduler.testTick()

        XCTAssertEqual(playedIds, ["test_01", "test_02", "test_01"])
    }

    func testSetPlayedHistory_skipsAlreadyPlayed() {
        let pack = makePack(promptCount: 3, densityMin: 0, densityMax: 0, initialDelay: 0)
        let scheduler = VoiceGuideScheduler(
            prompts: pack.prompts,
            scheduling: pack.scheduling,
            context: .walk
        )
        scheduler.setPlayedHistory(Set(["test_01", "test_02"]))

        var firedId: String?
        scheduler.onShouldPlay = { (p: VoiceGuidePrompt) in firedId = p.id }

        scheduler.updateWalkStartDate(Date().addingTimeInterval(-100))
        scheduler.updateStatus(.recording)
        scheduler.testTick()

        XCTAssertEqual(firedId, "test_03")
    }

    // MARK: - Playback State

    func testIsPlaying_blocksNextTick() {
        let pack = makePack(densityMin: 0, densityMax: 0, initialDelay: 0)
        let scheduler = VoiceGuideScheduler(
            prompts: pack.prompts,
            scheduling: pack.scheduling,
            context: .walk
        )

        var firedCount = 0
        scheduler.onShouldPlay = { (_: VoiceGuidePrompt) in firedCount += 1 }

        scheduler.updateWalkStartDate(Date().addingTimeInterval(-100))
        scheduler.updateStatus(.recording)

        scheduler.testTick()
        XCTAssertEqual(firedCount, 1)

        scheduler.testTick()
        XCTAssertEqual(firedCount, 1, "Should not fire while previous is playing")

        scheduler.markPlayed("test_01")
        scheduler.testTick()
        XCTAssertEqual(firedCount, 2)
    }

    // MARK: - Meditation Context

    func testMeditationContext_firesWithoutWalkStatus() {
        let pack = makePack(densityMin: 0, densityMax: 0, initialDelay: 0)
        let scheduler = VoiceGuideScheduler(
            prompts: pack.prompts,
            scheduling: pack.scheduling,
            context: .meditation,
            startDate: Date().addingTimeInterval(-100)
        )

        var firedPrompt: VoiceGuidePrompt?
        scheduler.onShouldPlay = { firedPrompt = $0 }
        scheduler.testTick()
        XCTAssertNotNil(firedPrompt, "Meditation context should fire without walk status")
    }

    func testMeditationContext_notBlockedByMeditatingFlag() {
        let pack = makePack(densityMin: 0, densityMax: 0, initialDelay: 0)
        let scheduler = VoiceGuideScheduler(
            prompts: pack.prompts,
            scheduling: pack.scheduling,
            context: .meditation,
            startDate: Date().addingTimeInterval(-100)
        )

        var firedCount = 0
        scheduler.onShouldPlay = { _ in firedCount += 1 }
        scheduler.updateIsMeditating(true)
        scheduler.testTick()
        XCTAssertEqual(firedCount, 1, "Meditation context should ignore isMeditating flag")
    }

    func testMeditationContext_usesCustomPhaseThresholds() {
        let pack = makePack(promptCount: 3, densityMin: 0, densityMax: 0, initialDelay: 0)
        let prompts = [
            VoiceGuidePrompt(id: "s1", seq: 1, durationSec: 5, fileSizeBytes: 1000, r2Key: "x", phase: "settling"),
            VoiceGuidePrompt(id: "d1", seq: 2, durationSec: 5, fileSizeBytes: 1000, r2Key: "x", phase: "deepening"),
            VoiceGuidePrompt(id: "c1", seq: 3, durationSec: 5, fileSizeBytes: 1000, r2Key: "x", phase: "closing"),
        ]
        let scheduler = VoiceGuideScheduler(
            prompts: prompts,
            scheduling: pack.scheduling,
            context: .meditation,
            startDate: Date().addingTimeInterval(-120),
            settlingThresholdSec: 60,
            closingThresholdSec: 180
        )

        var firedId: String?
        scheduler.onShouldPlay = { firedId = $0.id }
        scheduler.testTick()
        XCTAssertEqual(firedId, "d1", "At 120s with settling=60, closing=180, should be in deepening phase")
    }

    func testWalkContext_backwardCompatible() {
        let pack = makePack(densityMin: 0, densityMax: 0, initialDelay: 0)
        let scheduler = VoiceGuideScheduler(
            prompts: pack.prompts,
            scheduling: pack.scheduling,
            context: .walk
        )

        var firedCount = 0
        scheduler.onShouldPlay = { _ in firedCount += 1 }
        scheduler.updateWalkStartDate(Date().addingTimeInterval(-100))
        scheduler.updateStatus(.waiting)
        scheduler.testTick()
        XCTAssertEqual(firedCount, 0, "Walk context still requires recording status")

        scheduler.updateStatus(.recording)
        scheduler.testTick()
        XCTAssertEqual(firedCount, 1)
    }
}
