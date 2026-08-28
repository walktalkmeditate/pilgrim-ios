import XCTest
import SwiftUI
@testable import Pilgrim

final class ObliqueVoiceTests: XCTestCase {

    func testStyle_existsWithTitleAndDescription() {
        XCTAssertTrue(PromptStyle.allCases.contains(.oblique))
        XCTAssertEqual(PromptStyle.oblique.title, "Oblique")
        XCTAssertEqual(PromptStyle.oblique.description, "What has not moved")
    }

    func testPolicy_hoistsUnchangedBlock() {
        XCTAssertTrue(ObliqueVoice().contextPolicy.hoistsUnchangedBlock)
        XCTAssertTrue(ObliqueVoice().contextPolicy.includesMarkerLines)
    }

    func testConstraints_banContentlessReframeInstructions() {
        let joined = ObliqueVoice().responseConstraints(hasSpeech: true).joined(separator: " ")
        XCTAssertTrue(joined.contains("perhaps consider"))
        XCTAssertTrue(joined.contains("outside the box"))
        XCTAssertTrue(joined.contains("never assert a pattern that block does not show"))
    }

    func testConstraints_areExactlyFour() {
        XCTAssertEqual(ObliqueVoice().responseConstraints(hasSpeech: true).count, 4)
    }

    func testAssembler_obliqueHoistsBlockAboveTranscription() {
        let context = ActivityContext.make(
            recordings: [RecordingContext(
                text: "the river was loud today", timestamp: DateFactory.makeDate(2024, 6, 15, 9, 5, 0),
                startCoordinate: nil, endCoordinate: nil, wordsPerMinute: 100,
                recordingUUID: UUID(), endTimestamp: nil
            )],
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            unchangedBlock: "**Unchanged:**\n'river' has returned across 4 walks."
        )
        let prompt = PromptAssembler.assemble(context: context, voice: ObliqueVoice())
        let unchangedIndex = prompt.range(of: "**Unchanged:**")?.lowerBound
        let transcriptionIndex = prompt.range(of: "**Walking Transcription:**")?.lowerBound
        XCTAssertNotNil(unchangedIndex)
        XCTAssertNotNil(transcriptionIndex)
        XCTAssertLessThan(unchangedIndex!, transcriptionIndex!)
    }

    // MARK: - The voice guards itself, not just the picker

    private func contextWithoutBlock(intention: String? = nil) -> ActivityContext {
        .make(
            recordings: [RecordingContext(
                text: "the river was loud today", timestamp: DateFactory.makeDate(2024, 6, 15, 9, 5, 0),
                startCoordinate: nil, endCoordinate: nil, wordsPerMinute: 100,
                recordingUUID: UUID(), endTimestamp: nil
            )],
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            intention: intention,
            threadsDossier: "**Thought threads:**\nRecording 1: absolutist words 2.3%",
            unchangedBlock: nil
        )
    }

    /// The safety property cannot live only in `PromptListView`'s
    /// `if let waiting {…} else { Button {…} }`. Without a block, Oblique's
    /// preamble still says "What follows includes what has not changed
    /// across those returns" and its instruction still says "Work from the
    /// invariants named under Unchanged" — an explicit invitation to invent
    /// one, handed to any future share affordance, copy button, widget, or
    /// second prompt surface that bypasses the picker. The assembler refuses
    /// instead, so every caller inherits the guarantee.
    func testAssembler_obliqueWithoutBlock_producesNothing() {
        XCTAssertEqual(PromptAssembler.assemble(context: contextWithoutBlock(), voice: ObliqueVoice()), "")
    }

    func testAssembler_obliqueWithoutBlock_neverInvitesAnInventedInvariant() {
        let prompt = PromptAssembler.assemble(context: contextWithoutBlock(), voice: ObliqueVoice())
        XCTAssertFalse(prompt.contains("Unchanged"))
        XCTAssertFalse(prompt.contains("what has not changed"))
        XCTAssertFalse(prompt.contains("invariants"))
    }

    func testGenerateAll_withoutBlock_obliqueCarriesNoPromptText() {
        let prompts = PromptGenerator.generateAll(context: contextWithoutBlock())
        let oblique = prompts.first { $0.style == .oblique }
        XCTAssertNotNil(oblique, "the row still exists so the picker can show 'Still listening'")
        XCTAssertEqual(oblique?.text, "")
        for other in prompts where other.style != .oblique {
            XCTAssertFalse(other.text.isEmpty, "no other voice is gated on the block")
        }
    }

    /// The refusal is keyed on the policy, not on the concrete type, so a
    /// future block-reading voice inherits it without remembering to.
    func testAssembler_nonHoistingVoiceWithoutBlock_assemblesNormally() {
        let prompt = PromptAssembler.assemble(context: contextWithoutBlock(), voice: ReflectiveVoice())
        XCTAssertFalse(prompt.isEmpty)
    }

    // MARK: - The intention rider is scoped off Oblique

    private func contextWithBlockAndIntention() -> ActivityContext {
        .make(
            recordings: [RecordingContext(
                text: "the river was loud today", timestamp: DateFactory.makeDate(2024, 6, 15, 9, 5, 0),
                startCoordinate: nil, endCoordinate: nil, wordsPerMinute: 100,
                recordingUUID: UUID(), endTimestamp: nil
            )],
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            intention: "let go of the move",
            unchangedBlock: "**Unchanged:**\n'river' has returned across 4 walks."
        )
    }

    /// The rider was written for six voices that all produce a reading of
    /// THIS walk, and it fires on the common case — deep-history walkers are
    /// exactly the walkers who set intentions. It asks for a resolution
    /// ("how their walk spoke to this purpose") where Oblique's own
    /// constraints say "End on the observation. Do not resolve it", and for
    /// a this-walk summary where Oblique reads cross-walk invariants.
    func testAssembler_obliqueWithIntention_carriesNeitherRiderNorLens() {
        let prompt = PromptAssembler.assemble(context: contextWithBlockAndIntention(), voice: ObliqueVoice())
        XCTAssertFalse(prompt.contains("Ground your response in the walker's stated intention"))
        XCTAssertFalse(prompt.contains("spoke to this purpose"))
        XCTAssertFalse(prompt.contains("Let it be the lens through which you interpret everything below"))
        XCTAssertFalse(prompt.contains("**The walker's intention:**"))
    }

    func testAssembler_obliqueWithIntention_stillCarriesItsOwnConstraints() {
        let prompt = PromptAssembler.assemble(context: contextWithBlockAndIntention(), voice: ObliqueVoice())
        XCTAssertTrue(prompt.contains("**Unchanged:**"))
        XCTAssertTrue(prompt.contains("End on the observation"))
    }

    /// The other six voices keep the rider unchanged — this is a scoping
    /// fix, not a removal.
    func testAssembler_everyOtherVoiceWithIntention_keepsRiderAndLens() {
        for voice: PromptVoice in [
            ContemplativeVoice(), ReflectiveVoice(), CreativeVoice(),
            GratitudeVoice(), PhilosophicalVoice(), JournalingVoice()
        ] {
            let prompt = PromptAssembler.assemble(context: contextWithBlockAndIntention(), voice: voice)
            XCTAssertTrue(prompt.contains("Ground your response in the walker's stated intention"))
            XCTAssertTrue(prompt.contains("Let it be the lens through which you interpret everything below"))
        }
    }

    func testPolicy_obliqueAloneDoesNotGroundInIntention() {
        XCTAssertFalse(ObliqueVoice().contextPolicy.groundsInIntention)
        for voice: PromptVoice in [
            ContemplativeVoice(), ReflectiveVoice(), CreativeVoice(),
            GratitudeVoice(), PhilosophicalVoice(), JournalingVoice()
        ] {
            XCTAssertTrue(voice.contextPolicy.groundsInIntention)
        }
    }

    // MARK: - Picker gate

    /// The gate is the presence of the `Unchanged:` block itself, not a
    /// walk-count threshold — `unchangedBlock` is already nil whenever the
    /// current walk is silent, history is thin, or history is deep but
    /// nothing has held still yet (`DossierSensesInvariance.minimumInvariantWalks`
    /// qualifying walks are required before any signal can fire). Checking
    /// the block directly is the only gate that cannot tell `ObliqueVoice`
    /// to read a block that is not in the prompt.
    func testAvailability_obliqueGatedOnUnchangedBlockPresence() {
        XCTAssertFalse(PromptStyle.oblique.isAvailable(unchangedBlockPresent: false))
        XCTAssertTrue(PromptStyle.oblique.isAvailable(unchangedBlockPresent: true))
    }

    func testAvailability_otherStylesAlwaysAvailable() {
        for style in PromptStyle.allCases where style != .oblique {
            XCTAssertTrue(style.isAvailable(unchangedBlockPresent: false))
        }
    }

    func testWaitingCopy_onlyObliqueHasIt() {
        XCTAssertEqual(PromptStyle.oblique.waitingCopy(threadsEnabled: true),
                       "Still listening. A few more walks with your voice.")
        XCTAssertNil(PromptStyle.reflective.waitingCopy(threadsEnabled: true))
        XCTAssertNil(PromptStyle.reflective.waitingCopy(threadsEnabled: false))
    }

    /// "A few more walks with your voice" is a promise that walking helps.
    /// With Thought Threads off, `ThreadsDossierBuilder.buildResult` returns
    /// all-nil before it reads a single recording, so no amount of walking
    /// will ever produce a block — the row would sit dimmed forever, telling
    /// the walker to keep doing the one thing that cannot change it. The
    /// copy names the setting instead.
    func testWaitingCopy_threadsDisabled_pointsAtTheSettingNotAtMoreWalking() {
        let copy = PromptStyle.oblique.waitingCopy(threadsEnabled: false)
        XCTAssertEqual(copy, "Needs Thought Threads, switched on in Settings → Voice.")
        XCTAssertFalse(copy?.contains("A few more walks") ?? true,
                       "walking cannot satisfy a gate that never reads the walk")
    }

    /// The dimmed row's copy exists to be read. Dimming the whole row to
    /// 0.45 put `.fog` at 1.6:1 and `.ink` at 2.6:1 against `parchment`,
    /// both far under WCAG AA's 4.5:1. The text dim is now 0.7 on `.ink`
    /// (5.4:1 light, 7.8:1 dark) and only the decorative icon keeps the
    /// heavier 0.45.
    func testWaitingRow_textDimStaysAboveTheAccessibleContrastFloor() {
        XCTAssertGreaterThanOrEqual(PromptStyleRow.waitingTextOpacity, 0.7)
        XCTAssertLessThan(PromptStyleRow.waitingIconOpacity, PromptStyleRow.waitingTextOpacity,
                          "the icon is decorative and may carry the heavier dim; the copy may not")
    }

    /// `PromptAssembler.assemble` returns the empty string for a hoisting
    /// voice with no block, and `GeneratedPrompt.text` is non-optional — so
    /// the sentinel is invisible at the type level to every consumer that
    /// copies, shares or renders it. `hasText` is the question they must ask.
    func testGeneratedPrompt_refusedAssembly_reportsNoText() {
        let refused = GeneratedPrompt(style: .oblique, customStyle: nil, text: "")
        XCTAssertFalse(refused.hasText)
        XCTAssertTrue(GeneratedPrompt(style: .oblique, customStyle: nil, text: "x").hasText)
    }

    /// Deliberate symmetry: the gate means Oblique is never assembled with
    /// `hasSpeech: false` (a silent current walk yields no `unchangedBlock`,
    /// which is the gate). The `hasSpeech: false` branch exists only for
    /// protocol conformance and must read identically to the reachable
    /// branch — pinned here so the two can never quietly drift apart.
    func testPreambleAndInstruction_hasSpeechFalseMatchesHasSpeechTrue() {
        let voice = ObliqueVoice()
        XCTAssertEqual(voice.preamble(hasSpeech: false), voice.preamble(hasSpeech: true))
        XCTAssertEqual(voice.instruction(hasSpeech: false), voice.instruction(hasSpeech: true))
    }

    /// Every cue that the waiting row is unselectable was visual — 0.45
    /// opacity and a missing chevron — so VoiceOver announced an ordinary
    /// row and gave no reason it could not be opened. The label carries the
    /// state (a hint alone is skippable, and users can turn hints off) and
    /// the row's hint carries the same "Still listening" reason the sighted
    /// walker reads.
    func testWaitingRow_accessibilityLabelNamesTheStyleAndItsUnavailability() {
        XCTAssertEqual(
            PromptStyleRow.waitingAccessibilityLabel(title: PromptStyle.oblique.title),
            "Oblique, not available yet"
        )
    }
}
