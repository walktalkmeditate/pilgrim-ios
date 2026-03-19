import XCTest
@testable import Pilgrim

final class MeditationGuideManagementTests: XCTestCase {

    private func makePack() -> VoiceGuidePack {
        let walkPrompts = [
            VoiceGuidePrompt(id: "w01", seq: 1, durationSec: 5, fileSizeBytes: 1000, r2Key: "x")
        ]
        let medPrompts = [
            VoiceGuidePrompt(id: "m01", seq: 1, durationSec: 5, fileSizeBytes: 1000, r2Key: "x"),
            VoiceGuidePrompt(id: "m02", seq: 2, durationSec: 5, fileSizeBytes: 1000, r2Key: "x"),
        ]
        return VoiceGuidePack(
            id: "test",
            version: "1",
            name: "Test",
            tagline: "t",
            description: "d",
            theme: "t",
            iconName: "star",
            type: "voiceGuide",
            walkTypes: ["wander"],
            scheduling: PromptDensity(densityMinSec: 180, densityMaxSec: 420, minSpacingSec: 120, initialDelaySec: 60, walkEndBufferSec: 300),
            totalDurationSec: 15,
            totalSizeBytes: 3000,
            prompts: walkPrompts,
            meditationScheduling: PromptDensity(densityMinSec: 0, densityMaxSec: 0, minSpacingSec: 0, initialDelaySec: 0, walkEndBufferSec: 0),
            meditationPrompts: medPrompts
        )
    }

    func testStartGuiding_setsIsActive() {
        let mgmt = MeditationGuideManagement()
        XCTAssertFalse(mgmt.isActive)

        mgmt.startGuiding(pack: makePack())
        XCTAssertTrue(mgmt.isActive)
    }

    func testStopGuiding_resetsState() {
        let mgmt = MeditationGuideManagement()
        mgmt.startGuiding(pack: makePack())
        mgmt.stopGuiding()

        XCTAssertFalse(mgmt.isActive)
        XCTAssertFalse(mgmt.isVoicePlaying)
    }

    func testStopGuiding_resetsIsVoicePlaying() {
        let mgmt = MeditationGuideManagement()
        mgmt.startGuiding(pack: makePack())

        mgmt.stopGuiding()
        XCTAssertFalse(mgmt.isVoicePlaying)
    }

    func testRestartGuiding_resetsIsVoicePlaying() {
        let mgmt = MeditationGuideManagement()
        mgmt.startGuiding(pack: makePack())

        mgmt.startGuiding(pack: makePack())
        XCTAssertTrue(mgmt.isActive)
        XCTAssertFalse(mgmt.isVoicePlaying, "Restarting should reset voice playing state")
    }
}
