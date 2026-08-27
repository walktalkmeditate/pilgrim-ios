import XCTest
@testable import Pilgrim

/// Every generated prompt must end with a response contract: the downstream
/// LLM is told how to answer (voice-specific form constraints) and what it
/// may never do (invent details, ignore the walker's language, flatten a
/// two-voice recording into a monologue).
final class PromptResponseContractTests: XCTestCase {

    private let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)

    private func spokenContext() -> ActivityContext {
        ActivityContext.make(
            recordings: [
                RecordingContext(
                    text: "The fog is lifting off the river",
                    timestamp: start.addingTimeInterval(300),
                    startCoordinate: nil,
                    endCoordinate: nil,
                    wordsPerMinute: nil
                )
            ],
            startDate: start
        )
    }

    private func silentContext() -> ActivityContext {
        ActivityContext.make(startDate: start)
    }

    func testEveryStyle_includesContractSection() {
        for prompt in PromptGenerator.generateAll(context: spokenContext()) {
            XCTAssertTrue(prompt.text.contains("**How to respond:**"),
                          "\(prompt.title) must carry a response contract")
        }
    }

    func testAntiFabricationLine_presentEvenOnSilentWalks() {
        for prompt in PromptGenerator.generateAll(context: silentContext()) {
            XCTAssertTrue(prompt.text.contains("never invent"),
                          "\(prompt.title) must forbid fabricated details")
        }
    }

    func testLanguageLine_presentWithSpeech() {
        let prompt = PromptGenerator.generate(style: .reflective, context: spokenContext())
        XCTAssertTrue(prompt.text.contains("in the language"))
    }

    func testLanguageLine_absentWithoutSpeech() {
        let prompt = PromptGenerator.generate(style: .reflective, context: silentContext())
        XCTAssertFalse(prompt.text.contains("in the language"),
                       "no transcript means no language to mirror")
    }

    func testMultiVoiceLine_presentWithSpeech_absentWithout() {
        let spoken = PromptGenerator.generate(style: .contemplative, context: spokenContext())
        XCTAssertTrue(spoken.text.contains("more than one voice"))

        let silent = PromptGenerator.generate(style: .contemplative, context: silentContext())
        XCTAssertFalse(silent.text.contains("more than one voice"))
    }

    func testContemplative_limitsQuestions() {
        let prompt = PromptGenerator.generate(style: .contemplative, context: spokenContext())
        XCTAssertTrue(prompt.text.contains("at most one question"))
    }

    func testCreative_repliesWithThePieceItself() {
        let prompt = PromptGenerator.generate(style: .creative, context: spokenContext())
        XCTAssertTrue(prompt.text.contains("no introduction"))
    }

    func testCustomStyle_carriesSharedContract() {
        let custom = CustomPromptStyle(
            id: UUID(),
            title: "Letters",
            icon: "envelope",
            instruction: "Write me a letter about this walk."
        )
        let prompt = PromptGenerator.generateCustom(customStyle: custom, context: spokenContext())
        XCTAssertTrue(prompt.text.contains("**How to respond:**"))
        XCTAssertTrue(prompt.text.contains("never invent"))
    }

    // MARK: - Interpretive key
    //
    // The key is only honest about signals the dossier actually printed. A
    // non-English recording prints "Markers unavailable"; a recording under
    // `densityFloorWords` prints raw counts, not shares; and the modal-lean
    // clause is silent unless it clears three thresholds. Teaching a
    // taxonomy the dossier withheld invites the model to back-fill it.

    /// The richest shape: shares over the density floor plus a modal lean.
    private func fullDossier() -> String {
        "**Thought threads (on-device linguistic analysis):**"
            + "\nRecording 1: absolutist words 2.4% over 320 words; self-focus 6.1%; "
            + "insight 4, causation 2, discrepancy 1; temporal lean: past (coarse heuristic)"
            + "\nmodal lean: obligation — 'should' ×14 (your usual ~5 per walk)"
    }

    private func sharesOnlyDossier() -> String {
        "**Thought threads (on-device linguistic analysis):**"
            + "\nRecording 1: absolutist words 2.4% over 320 words; self-focus 6.1%; "
            + "insight 4, causation 2, discrepancy 1; temporal lean: past (coarse heuristic)"
    }

    private func nonEnglishDossier() -> String {
        "**Thought threads (on-device linguistic analysis):**"
            + "\nRecording 1: Markers unavailable (non-English recording)."
    }

    private func smallSampleDossier() -> String {
        "**Thought threads (on-device linguistic analysis):**"
            + "\nRecording 1: 40 words — small sample, raw counts only: 2 absolutist, 5 self-focus; "
            + "insight 1, causation 0, discrepancy 0; temporal lean: present (coarse heuristic)"
    }

    func testResponseContract_withThreadsDossier_carriesInterpretiveKey() {
        let contract = PromptAssembler.responseContract(
            voice: ReflectiveVoice(), hasSpeech: true, threadsDossier: fullDossier()
        )
        XCTAssertTrue(contract.contains("absolutist-word share"))
        XCTAssertTrue(contract.contains("self-focus"))
        XCTAssertTrue(contract.contains("modal lean"))
        XCTAssertTrue(contract.contains("obligation"))
        XCTAssertTrue(contract.contains("counterfactual"))
    }

    /// The interpretive key must name every modal family the model can
    /// encounter in a dossier — a family named in the enum but not here
    /// invites the model to back-fit an unnamed family onto the nearest
    /// named one. Reading straight from `ModalFamily.allCases` means a
    /// future family added without updating the contract line fails this
    /// test automatically, rather than relying on someone remembering to
    /// keep a hardcoded list in sync. Naming is not enough on its own,
    /// though: a scrambled term-to-definition mapping would still name all
    /// six, so each pair is asserted as a unit.
    func testResponseContract_withThreadsDossier_namesEveryModalFamily() {
        let contract = PromptAssembler.responseContract(
            voice: ReflectiveVoice(), hasSpeech: true, threadsDossier: fullDossier()
        )
        for family in MarkerLexicons.ModalFamily.allCases {
            XCTAssertTrue(contract.contains(family.rawValue),
                          "interpretive key omits modal family '\(family.rawValue)'")
        }
        for pair in [
            "obligation means the frame constrained them",
            "counterfactual means they were already replaying alternatives",
            "possibility and tentative mean it was still open",
            "intention means they had settled on a course",
            "desire means they were naming a want rather than a plan"
        ] {
            XCTAssertTrue(contract.contains(pair),
                          "interpretive key does not bind '\(pair)' as a unit")
        }
    }

    func testResponseContract_withThreadsDossier_retainsClinicalGuard() {
        for dossier in [fullDossier(), nonEnglishDossier(), smallSampleDossier()] {
            let contract = PromptAssembler.responseContract(
                voice: ReflectiveVoice(), hasSpeech: true, threadsDossier: dossier
            )
            XCTAssertTrue(contract.contains("never produce clinical or diagnostic language"),
                          "the safety line is unconditional on the dossier's presence")
        }
    }

    func testResponseContract_withoutThreadsDossier_hasNoInterpretiveKey() {
        let contract = PromptAssembler.responseContract(
            voice: ReflectiveVoice(), hasSpeech: true, threadsDossier: nil
        )
        XCTAssertFalse(contract.contains("absolutist-word share"))
    }

    func testResponseContract_nonEnglishDossier_teachesNoTaxonomyAtAll() {
        let contract = PromptAssembler.responseContract(
            voice: ReflectiveVoice(), hasSpeech: true, threadsDossier: nonEnglishDossier()
        )
        XCTAssertFalse(contract.contains("absolutist-word share"),
                       "the dossier printed no markers, so there is no share to read")
        XCTAssertFalse(contract.contains("modal lean"),
                       "the dossier printed no modal lean, so there is no frame to read")
    }

    func testResponseContract_smallSampleDossier_readsCountsNotShares() {
        let contract = PromptAssembler.responseContract(
            voice: ReflectiveVoice(), hasSpeech: true, threadsDossier: smallSampleDossier()
        )
        XCTAssertFalse(contract.contains("absolutist-word share"),
                       "under the density floor the dossier prints raw counts, never a share")
        XCTAssertTrue(contract.contains("too few words to read as a rate"))
    }

    func testResponseContract_dossierWithoutModalLean_omitsTheModalTaxonomy() {
        let contract = PromptAssembler.responseContract(
            voice: ReflectiveVoice(), hasSpeech: true, threadsDossier: sharesOnlyDossier()
        )
        XCTAssertTrue(contract.contains("absolutist-word share"))
        XCTAssertFalse(contract.contains("modal lean"),
                       "the modal clause is silent behind three thresholds; the key must follow it")
    }

    /// The key's probes read `ThreadsDossierFormatter`'s own output, so this
    /// runs the real formatter rather than a hand-written fixture — if the
    /// formatter's phrasing moves, this fails rather than silently
    /// suppressing the key on every walk.
    func testResponseContract_againstRealFormatterOutput_adaptsToWhatWasPrinted() {
        let markers = MarkerPack(
            wordCount: 320, absolutistCount: 8, firstPersonCount: 20,
            insightCount: 2, causationCount: 1, discrepancyCount: 1,
            futureCount: 4, pastCount: 1, sentiment: -0.2, modalCounts: [:]
        )
        let dense = TranscriptContext(
            schemaVersion: TranscriptContext.currentSchemaVersion, recordingUUID: UUID(),
            transcriptHash: "h", languageCode: "en", wordCount: 320, themes: [], markers: markers
        )
        let denseLine = ThreadsDossierFormatter.markerLine(for: dense, baseline: nil)
        XCTAssertTrue(
            PromptAssembler.responseContract(
                voice: ReflectiveVoice(), hasSpeech: true, threadsDossier: denseLine
            ).contains("absolutist-word share")
        )

        let sparse = TranscriptContext(
            schemaVersion: TranscriptContext.currentSchemaVersion, recordingUUID: UUID(),
            transcriptHash: "h", languageCode: "en", wordCount: 40, themes: [],
            markers: MarkerPack(
                wordCount: 40, absolutistCount: 2, firstPersonCount: 5,
                insightCount: 1, causationCount: 0, discrepancyCount: 0,
                futureCount: 1, pastCount: 0, sentiment: nil, modalCounts: [:]
            )
        )
        let sparseContract = PromptAssembler.responseContract(
            voice: ReflectiveVoice(), hasSpeech: true,
            threadsDossier: ThreadsDossierFormatter.markerLine(for: sparse, baseline: nil)
        )
        XCTAssertFalse(sparseContract.contains("absolutist-word share"))
        XCTAssertTrue(sparseContract.contains("too few words to read as a rate"))

        let absent = TranscriptContext(
            schemaVersion: TranscriptContext.currentSchemaVersion, recordingUUID: UUID(),
            transcriptHash: "h", languageCode: "es", wordCount: 320, themes: [], markers: nil
        )
        let absentContract = PromptAssembler.responseContract(
            voice: ReflectiveVoice(), hasSpeech: true,
            threadsDossier: ThreadsDossierFormatter.markerLine(for: absent, baseline: nil)
        )
        XCTAssertFalse(absentContract.contains("absolutist-word share"))
        XCTAssertFalse(absentContract.contains("too few words to read as a rate"))
    }

    /// The accretion budget: a dossier may add the clinical guard plus at
    /// most one interpretive line, never more. When the dossier withheld
    /// every referent the key shrinks to the guard alone.
    func testResponseContract_withThreadsDossier_neverAddsMoreThanTwoLines() {
        let without = PromptAssembler.responseContract(
            voice: ReflectiveVoice(), hasSpeech: true, threadsDossier: nil
        )
        let baseline = without.components(separatedBy: "\n- ").count

        for (dossier, expected) in [
            (fullDossier(), 2), (sharesOnlyDossier(), 2),
            (smallSampleDossier(), 2), (nonEnglishDossier(), 1)
        ] {
            let with = PromptAssembler.responseContract(
                voice: ReflectiveVoice(), hasSpeech: true, threadsDossier: dossier
            )
            XCTAssertEqual(with.components(separatedBy: "\n- ").count - baseline, expected,
                           "clinical guard + at most one interpretive line")
        }
    }
}
