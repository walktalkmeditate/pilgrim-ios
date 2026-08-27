# Prompt Relevance Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix three defects in the existing prompt system — raw signals the model has to guess at, an unbounded connection-hunt that manufactures insight, and a directive that presupposes its own conclusion.

**Architecture:** Three independent changes to three files. No new types, no new computation beyond two bounded lemma passes, no schema change. Each task is self-contained and separately revertible.

**Tech Stack:** Swift 5, SwiftUI, XCTest. Build via `Pilgrim.xcworkspace`, scheme `Pilgrim`.

**Spec:** `docs/superpowers/specs/2026-08-27-oblique-and-prompt-relevance-design.md` (Workstreams 2, 3, 4)

## Global Constraints

- This plan ships independently of the Oblique voice. Do not create `PromptStyle.oblique`, `DossierSensesInvariance`, or any context policy here — those belong to `2026-08-27-oblique-voice.md`.
- **Accretion budget:** Task 1 adds exactly one response-contract line. Task 3 removes one always-on firing rule. Net +0. Do not add contract lines beyond the one specified.
- Do not bump `TranscriptContext.currentSchemaVersion` (currently `4`). No change here alters how context is derived, so no stored file becomes stale.
- Do not change `MarkerAnalyzer`, `ThemeExtractor`, `ThreadStore`, or anything under `Pilgrim/Models/Threads/`.
- Preserve the single-NLP-pass property established by PR #65: `AttentionDirectives.detect` lemmatizes the joined transcript **once**. Task 3 may add at most two additional bounded passes (first and last recording only) and must never lemmatize all N recordings.
- Typography, colors, and UI are untouched — this plan changes prompt text only.
- Run the full suite before each commit. Baseline is 1388 tests; expect growth, never reduction.
- Never use `--no-verify`.

**Build:**
```bash
xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build
```

**Test:**
```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

**Single test class:**
```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnitTests/PromptResponseContractTests
```

> **Note on test counts:** `xcodebuild` summary lines are unreliable under the macos-26 simulator flake. Reconcile by counting `Test Case '-[...]' started` lines rather than trusting the summary.

---

## Task 1: Interpretive keys for marker and modal data

**Why:** `ThreadsDossierFormatter` ships `absolutist words 2.3%`, `self-focus 9.1%`, and `modal lean: obligation — 'should' ×31` as raw numbers. A model's default read of "should ×31" is *this person is being hard on themselves*. The correct read is that obligation names the **shape of the frame they were thinking inside**. One line converts three already-shipping signals from guessed-at to readable.

**Files:**
- Modify: `Pilgrim/Models/Prompt/PromptAssembler.swift` (the `hasThreadsDossier` branch of `responseContract`, around line 183)
- Test: `UnitTests/PromptResponseContractTests.swift`

**Interfaces:**
- Consumes: `PromptAssembler.responseContract(voice:hasSpeech:hasThreadsDossier:) -> String` (existing signature, unchanged)
- Produces: nothing new. This task changes string content only.

- [ ] **Step 1: Write the failing tests**

Add to `UnitTests/PromptResponseContractTests.swift`:

```swift
func testResponseContract_withThreadsDossier_carriesInterpretiveKey() {
    let contract = PromptAssembler.responseContract(
        voice: ReflectiveVoice(), hasSpeech: true, hasThreadsDossier: true
    )
    XCTAssertTrue(contract.contains("absolutist density"))
    XCTAssertTrue(contract.contains("first-person density"))
    XCTAssertTrue(contract.contains("modal lean"))
    XCTAssertTrue(contract.contains("obligation"))
    XCTAssertTrue(contract.contains("counterfactual"))
}

func testResponseContract_withThreadsDossier_retainsClinicalGuard() {
    let contract = PromptAssembler.responseContract(
        voice: ReflectiveVoice(), hasSpeech: true, hasThreadsDossier: true
    )
    XCTAssertTrue(contract.contains("never produce clinical or diagnostic language"))
}

func testResponseContract_withoutThreadsDossier_hasNoInterpretiveKey() {
    let contract = PromptAssembler.responseContract(
        voice: ReflectiveVoice(), hasSpeech: true, hasThreadsDossier: false
    )
    XCTAssertFalse(contract.contains("absolutist density"))
}

func testResponseContract_withThreadsDossier_addsExactlyOneLine() {
    let with = PromptAssembler.responseContract(
        voice: ReflectiveVoice(), hasSpeech: true, hasThreadsDossier: true
    )
    let without = PromptAssembler.responseContract(
        voice: ReflectiveVoice(), hasSpeech: true, hasThreadsDossier: false
    )
    let withLines = with.components(separatedBy: "\n- ").count
    let withoutLines = without.components(separatedBy: "\n- ").count
    XCTAssertEqual(withLines - withoutLines, 2, "clinical guard + interpretive key, no more")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnitTests/PromptResponseContractTests
```

Expected: `testResponseContract_withThreadsDossier_carriesInterpretiveKey` FAILS (contract does not contain "absolutist density"). `testResponseContract_withThreadsDossier_addsExactlyOneLine` FAILS (difference is 1, not 2). The other two PASS already.

- [ ] **Step 3: Add the interpretive key line**

In `Pilgrim/Models/Prompt/PromptAssembler.swift`, find this block inside `responseContract`:

```swift
        if hasThreadsDossier {
            lines.append("The thought-thread marker profiles are descriptive on-device linguistic signals, not assessments — interpret them gently, never produce clinical or diagnostic language, and never treat a single walk's numbers as meaningful on their own.")
        }
```

Replace with:

```swift
        if hasThreadsDossier {
            lines.append("The thought-thread marker profiles are descriptive on-device linguistic signals, not assessments — interpret them gently, never produce clinical or diagnostic language, and never treat a single walk's numbers as meaningful on their own.")
            lines.append("Read absolutist density as how fixed the walker's framing was, first-person density as how far they placed themselves at the centre of it, and the modal lean as the frame they were working inside — obligation means the frame constrained them, counterfactual means they were already replaying alternatives, possibility and tentative mean it was still open. None of these has a fixed meaning; read each through this walk's intention and practice.")
        }
```

Keep the existing clinical-language guard **exactly as it is** — it is the safety line and the new line is an interpretive one. They do different jobs.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnitTests/PromptResponseContractTests
```

Expected: all four PASS.

- [ ] **Step 5: Run the full suite**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: no failures. Some snapshot-style tests in `PromptAssemblerLanguageTests` or `PromptGeneratorTests` may assert on full prompt text — if any fail, update the expected string to include the new line. Do **not** weaken an assertion to make it pass.

- [ ] **Step 6: Commit**

```bash
git add Pilgrim/Models/Prompt/PromptAssembler.swift UnitTests/PromptResponseContractTests.swift
git commit -m "feat(prompts): give the model the key to the marker numbers

The dossier has been shipping absolutist density, first-person density and
the modal lean as bare figures, leaving the model to guess. Its default
guess for 'should x31' is that the walker is being hard on themselves. The
reading that is actually true is different: obligation names the shape of
the frame they were thinking inside, and counterfactual means they were
already replaying alternatives.

One contract line, no new computation. The clinical-language guard stays
exactly as it was; that line keeps the reading safe, this one makes it
possible.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Bound Reflective's connection-hunting to the walk's own evidence

**Why:** `ReflectiveVoice.instruction` asks *"What connections do you see between the different moments?"* and *"What contradictions or tensions are present?"* Both are unbounded. Goodman 1972: any two things share indefinitely many true properties — a lawn mower and a plum both have rounded edges, contain carbon, and weigh more than a paperclip. So the model will always find connections, they will always sound insightful, and they will be arbitrary. Similarity only does work once relevance is supplied from outside it.

**Files:**
- Modify: `Pilgrim/Models/Prompt/WalkPromptVoices.swift:32-36` (`ReflectiveVoice.instruction`)
- Test: `UnitTests/PromptGeneratorTests.swift`

**Interfaces:**
- Consumes: `PromptVoice.instruction(hasSpeech: Bool) -> String` (existing protocol member, unchanged)
- Produces: nothing new. String content only.

- [ ] **Step 1: Write the failing tests**

Add to `UnitTests/PromptGeneratorTests.swift`:

```swift
func testReflectiveVoice_spoken_bindsConnectionsToTheRecord() {
    let instruction = ReflectiveVoice().instruction(hasSpeech: true)
    XCTAssertTrue(instruction.contains("Where the walk's own record supports it"))
    XCTAssertTrue(instruction.contains("say less rather than reaching"))
    XCTAssertTrue(instruction.contains("do not manufacture one"))
}

func testReflectiveVoice_silent_bindsPatternsToTheRecord() {
    let instruction = ReflectiveVoice().instruction(hasSpeech: false)
    XCTAssertTrue(instruction.contains("Where the walk's own record supports it"))
    XCTAssertTrue(instruction.contains("say less rather than reaching"))
}

func testReflectiveVoice_bothModes_keepSelfUnderstandingGoal() {
    XCTAssertTrue(ReflectiveVoice().instruction(hasSpeech: true).contains("understand"))
    XCTAssertTrue(ReflectiveVoice().instruction(hasSpeech: false).contains("understand"))
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnitTests/PromptGeneratorTests
```

Expected: the first two FAIL (instruction does not contain "Where the walk's own record supports it"). The third PASSES already.

- [ ] **Step 3: Rewrite both instruction branches**

In `Pilgrim/Models/Prompt/WalkPromptVoices.swift`, replace `ReflectiveVoice.instruction` entirely:

```swift
    func instruction(hasSpeech: Bool) -> String {
        hasSpeech
            ? "Please analyze these walking reflections for patterns, recurring themes, and emotional undercurrents. Where the walk's own record supports it — the stated intention, a word that recurs, a shift in pace or marker profile — name what connects the moments; where it does not, say less rather than reaching. Note any genuine tension the record shows, and do not manufacture one. Offer observations that help me understand myself better."
            : "Read the shape of this walk — its pace, its pauses, its waypoints — as you would read a text. Where the walk's own record supports it, name the patterns you find; where it does not, say less rather than reaching. What might the walker have been processing? What does the choice of silence itself suggest? Offer observations that help them understand themselves."
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnitTests/PromptGeneratorTests
```

Expected: all three PASS.

- [ ] **Step 5: Run the full suite**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: no failures. Update any full-prompt snapshot assertions to the new text if they break; do not weaken them.

- [ ] **Step 6: Commit**

```bash
git add Pilgrim/Models/Prompt/WalkPromptVoices.swift UnitTests/PromptGeneratorTests.swift
git commit -m "fix(prompts): stop Reflective asking for connections that always exist

'What connections do you see between the different moments' is unbounded,
and Goodman settled what happens next: any two things share indefinitely
many true properties, so a model asked to connect will always connect, it
will always sound insightful, and it will be arbitrary. Asking for
contradictions the same way manufactures tension on walks that had none.

Similarity only does work once relevance is supplied from outside it. Both
branches now bind to the walk's own record - the intention, a recurring
word, a shift in pace - and are told to say less rather than reach.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Gate `firstVersusLast` on a delta that actually moved

**Why:** The directive currently fires on every walk with ≥2 recordings and **presupposes its conclusion** — told to measure what changed, the model finds change, including on walks where nothing did. This is the defect that killed `questionDensity` at the 2026-08-25 gate, just quieter: it fires plausibly and is wrong.

**Note on available data:** `ActivityContext` carries no structured marker data — only `threadsDossier` as a pre-formatted string. Sentiment and absolutist deltas are therefore **not reachable here**, and computing them would mean fresh `MarkerAnalyzer` passes per recording, undoing PR #65's single-pass work. The gate below uses `RecordingContext.wordsPerMinute` (already populated, free) plus exactly two bounded `TranscriptNLP.contentLemmas(in:)` passes on the first and last recording only.

**Files:**
- Modify: `Pilgrim/Models/Prompt/AttentionDirectives.swift` (the `firstVersusLast` detector and its two new constants)
- Test: `UnitTests/AttentionDirectivesTests.swift` (create if absent)

**Interfaces:**
- Consumes: `RecordingContext.wordsPerMinute: Double?`, `RecordingContext.text: String`, `TranscriptNLP.contentLemmas(in:) -> [String]`
- Produces: `AttentionDirectives.detect(context:detectedLanguageCode:) -> [String]` (existing signature, unchanged). Behaviour change only: `firstVersusLast` may now return `nil`.

- [ ] **Step 1: Write the failing tests**

Create `UnitTests/AttentionDirectivesTests.swift` if it does not exist; otherwise append. Use `ActivityContext.make` and `DateFactory.makeDate`, matching the fixture style in `DossierSensesTests`.

```swift
import XCTest
@testable import Pilgrim

final class AttentionDirectivesFirstVersusLastTests: XCTestCase {

    private static let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)

    private func recording(_ text: String, wpm: Double?, minutesIn: Int) -> RecordingContext {
        RecordingContext(
            text: text,
            timestamp: Self.start.addingTimeInterval(TimeInterval(minutesIn * 60)),
            startCoordinate: nil,
            endCoordinate: nil,
            wordsPerMinute: wpm,
            recordingUUID: UUID(),
            endTimestamp: nil
        )
    }

    private func directives(_ recordings: [RecordingContext]) -> [String] {
        AttentionDirectives.detect(
            context: .make(recordings: recordings, startDate: Self.start),
            detectedLanguageCode: "en"
        )
    }

    private func isFirstVersusLast(_ line: String) -> Bool {
        line.contains("attend to what moved between them")
    }

    func testFirstVersusLast_sameSubjectSamePace_staysSilent() {
        let text = "the garden hedge grows beside the stone wall near the orchard gate"
        let lines = directives([
            recording(text, wpm: 100, minutesIn: 0),
            recording(text, wpm: 102, minutesIn: 20)
        ])
        XCTAssertFalse(lines.contains(where: isFirstVersusLast))
    }

    func testFirstVersusLast_paceShift_fires() {
        let text = "the garden hedge grows beside the stone wall near the orchard gate"
        let lines = directives([
            recording(text, wpm: 100, minutesIn: 0),
            recording(text, wpm: 140, minutesIn: 20)
        ])
        XCTAssertTrue(lines.contains { isFirstVersusLast($0) && $0.contains("faster") })
    }

    func testFirstVersusLast_paceSlowed_namesSlower() {
        let text = "the garden hedge grows beside the stone wall near the orchard gate"
        let lines = directives([
            recording(text, wpm: 140, minutesIn: 0),
            recording(text, wpm: 100, minutesIn: 20)
        ])
        XCTAssertTrue(lines.contains { isFirstVersusLast($0) && $0.contains("more slowly") })
    }

    func testFirstVersusLast_subjectDiverged_fires() {
        let lines = directives([
            recording("the garden hedge grows beside the stone wall near the orchard gate",
                      wpm: 100, minutesIn: 0),
            recording("my brother telephoned about the mortgage payment and the lawyer's invoice",
                      wpm: 101, minutesIn: 20)
        ])
        XCTAssertTrue(lines.contains { isFirstVersusLast($0) && $0.contains("shares little vocabulary") })
    }

    func testFirstVersusLast_tooFewLemmasToJudge_staysSilent() {
        let lines = directives([
            recording("yes", wpm: 100, minutesIn: 0),
            recording("no", wpm: 101, minutesIn: 20)
        ])
        XCTAssertFalse(lines.contains(where: isFirstVersusLast))
    }

    func testFirstVersusLast_missingPace_fallsBackToSubjectOnly() {
        let text = "the garden hedge grows beside the stone wall near the orchard gate"
        let lines = directives([
            recording(text, wpm: nil, minutesIn: 0),
            recording(text, wpm: nil, minutesIn: 20)
        ])
        XCTAssertFalse(lines.contains(where: isFirstVersusLast))
    }

    func testFirstVersusLast_singleRecording_staysSilent() {
        let lines = directives([
            recording("the garden hedge grows beside the stone wall", wpm: 100, minutesIn: 0)
        ])
        XCTAssertFalse(lines.contains(where: isFirstVersusLast))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnitTests/AttentionDirectivesFirstVersusLastTests
```

Expected: `sameSubjectSamePace_staysSilent`, `tooFewLemmasToJudge_staysSilent`, and `missingPace_fallsBackToSubjectOnly` FAIL — the current unconditional directive fires. The two "fires" tests also FAIL, because the current text is "Compare the first recording with the last — measure what changed in the walker between them" and contains none of the new phrases. `singleRecording_staysSilent` PASSES already.

- [ ] **Step 3: Replace the detector**

In `Pilgrim/Models/Prompt/AttentionDirectives.swift`, add these constants beside `movingThreshold` and `maxDirectives`:

```swift
    private static let paceShiftThreshold = 0.15
    private static let subjectOverlapCeiling = 0.20
    private static let minimumLemmasToJudgeSubject = 5
```

Then replace `firstVersusLast` entirely:

```swift
    /// Fires only when something measurably moved between the first
    /// recording and the last. The previous version fired on every walk
    /// with two recordings and presupposed its own conclusion — told to
    /// measure what changed, the model finds change, including on walks
    /// where nothing did (the `questionDensity` failure mode, quieter).
    ///
    /// Marker and sentiment deltas are deliberately NOT used: they are
    /// unreachable from `ActivityContext`, and computing them here would
    /// mean a fresh analyzer pass per recording. Pace is free
    /// (`wordsPerMinute` is already populated); subject costs exactly two
    /// lemma passes, never N.
    private static func firstVersusLast(_ context: ActivityContext) -> String? {
        guard let first = context.recordings.first,
              let last = context.recordings.last,
              context.recordings.count >= 2 else { return nil }

        if let firstPace = first.wordsPerMinute, let lastPace = last.wordsPerMinute, firstPace > 0 {
            let change = (lastPace - firstPace) / firstPace
            if change >= paceShiftThreshold {
                return "The walker spoke faster by the last recording than the first — attend to what moved between them."
            }
            if change <= -paceShiftThreshold {
                return "The walker spoke more slowly by the last recording than the first — attend to what moved between them."
            }
        }

        let firstLemmas = Set(TranscriptNLP.contentLemmas(in: first.text))
        let lastLemmas = Set(TranscriptNLP.contentLemmas(in: last.text))
        guard firstLemmas.count >= minimumLemmasToJudgeSubject,
              lastLemmas.count >= minimumLemmasToJudgeSubject else { return nil }

        let union = firstLemmas.union(lastLemmas).count
        guard union > 0 else { return nil }
        let jaccard = Double(firstLemmas.intersection(lastLemmas).count) / Double(union)
        guard jaccard <= subjectOverlapCeiling else { return nil }

        return "The walker's last recording shares little vocabulary with the first — attend to what moved between them."
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnitTests/AttentionDirectivesFirstVersusLastTests
```

Expected: all seven PASS.

If `subjectDiverged_fires` does not pass, print the two lemma sets and check the actual Jaccard value before touching `subjectOverlapCeiling` — `contentLemmas` applies its own stoplist, so the sets may be smaller than the raw text suggests. Adjust the **fixture text** to be more clearly divergent rather than loosening the threshold; the threshold is a spec value subject to the field gate, not a knob to make a test green.

- [ ] **Step 5: Run the full suite**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: no failures. Any existing test asserting the old "Compare the first recording with the last" string must be updated to the new behaviour — including, if present, one that assumed four directives always fire.

- [ ] **Step 6: Commit**

```bash
git add Pilgrim/Models/Prompt/AttentionDirectives.swift UnitTests/AttentionDirectivesTests.swift
git commit -m "fix(prompts): stop firstVersusLast presupposing its own conclusion

The directive fired on every walk with two recordings and told the model to
measure what changed. Told that, the model finds change - including on the
walks where nothing did. Same disease that killed questionDensity at the
gate, only quieter: it fires plausibly and it is wrong.

Now it fires only when something moved. Pace comes free from
wordsPerMinute; subject costs two bounded lemma passes on the first and
last recording, never all N. Marker and sentiment deltas would have been
the better signals and are deliberately absent - they are unreachable from
ActivityContext, and reaching them would undo the single-pass work from
PR #65.

When nothing moved the directive is silent and the budget goes to a
detector with something to say.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Verify on device and record the readback

**Why:** All three changes alter what the downstream model receives. The spec's field gate requires a harm check, because firing rate measures only the upside — the no-free-lunch theorem guarantees a matching downside that firing rate is structurally blind to.

**Files:**
- Modify: `docs/superpowers/specs/2026-08-27-oblique-and-prompt-relevance-design.md` (Deferred section — record outcomes)

**Interfaces:**
- Consumes: nothing. Manual QA task.
- Produces: recorded outcomes that gate external release.

- [ ] **Step 1: Build and install a DEBUG build on the test device**

```bash
xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build
```

Then run on the team device from Xcode. A simulator is acceptable for Tasks 1 and 2; Task 3's pace gate needs real `wordsPerMinute` values, so use a device with real walk history.

- [ ] **Step 2: Collect three real prompts**

Open a walk with ≥2 voice recordings and a threads dossier. Copy the generated prompt for Reflective, Journaling, and Contemplative.

- [ ] **Step 3: Harm check — with and without the interpretive key**

For each of the three prompts, produce two variants: one as generated, one with the new interpretive-key line deleted by hand. Paste both into ChatGPT or Claude and human-rate which reflection is better.

Record: does the key make the reflection read *less* clinical, or does naming the modal families make the model reach for framing language it would not otherwise have used? A signal that fires often and makes reflections worse is exactly what firing rate cannot see.

- [ ] **Step 4: Confirm `firstVersusLast` silence is correct, not broken**

Find a walk where the walker spoke about the same thing at the same pace throughout. Confirm the directive is absent. Then find a walk where the subject clearly shifted and confirm it fires and names the right signal.

If it fires on nearly every walk, the thresholds are too loose. If it never fires across the whole history, they are too tight. Record the observed rate.

- [ ] **Step 5: Record outcomes in the spec**

Append findings to the Deferred / open questions section of `docs/superpowers/specs/2026-08-27-oblique-and-prompt-relevance-design.md`, including the observed `firstVersusLast` firing rate and the harm-check verdict on the interpretive key.

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/specs/2026-08-27-oblique-and-prompt-relevance-design.md
git commit -m "docs(prompts): record the field-gate readback for the relevance fixes

Firing rates and the with/without harm check for the interpretive key.
Firing rate alone measures the upside; no free lunch guarantees a matching
downside it cannot see, so both halves are recorded here.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Done when

- [ ] Task 1: interpretive key ships, clinical guard retained, contract grew by exactly one line
- [ ] Task 2: Reflective binds connections and tension to the walk's record in both branches
- [ ] Task 3: `firstVersusLast` fires only on a measured pace or subject shift and names which
- [ ] Task 4: device readback done, harm check recorded, firing rate recorded in the spec
- [ ] Full suite green, no reductions from the 1388 baseline
- [ ] Lint clean against `main`'s current baseline, zero new warnings
- [ ] No `PromptStyle` case added, no Threads module file touched
