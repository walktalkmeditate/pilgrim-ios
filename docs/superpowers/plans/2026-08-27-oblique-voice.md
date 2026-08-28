# Oblique Voice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A seventh prompt voice that reads what has **not** moved across a walker's history and names the frame they have been looking through rather than at.

**Architecture:** Two layers. Layer 1 is a pure, deterministic on-device engine (`DossierSensesInvariance`) that computes what is actually invariant across the walker's threads — this is relevance realization, and the model cannot do it because it has no access to history. Layer 2 is the model, which interprets those invariants — aspectualization, which the device cannot do. The engine emits an `**Unchanged:**` block that enters the prompt as context; the model's response is what the walker reads.

**Tech Stack:** Swift 5, SwiftUI, XCTest. Build via `Pilgrim.xcworkspace`, scheme `Pilgrim`.

**Spec:** `docs/superpowers/specs/2026-08-27-oblique-and-prompt-relevance-design.md` (Workstreams 1 and 5)

**Depends on:** nothing. Can land before, after, or alongside `2026-08-27-prompt-relevance-fixes.md`.

## Global Constraints

- **Binding purity contract.** `DossierSensesInvariance` must not reference `DataManager`, `CoreStore`, any singleton, or `Date()`. Every input arrives as an argument. Time arrives as data. This mirrors `DossierSenses` and is what makes every emitted line traceable to enumerable, deterministic inputs.
- **Single-pass property.** `PromptGenerator.generateAll` maps one `ActivityContext` across `PromptStyle.allCases`, and `resolvedDerivations` computes language detection and directives once. The `unchangedBlock` is built **once** with the rest of the dossier and merely *emitted* per voice at assembly time. Never build a per-voice dossier.
- **No new fetches.** `historicalContexts` is wired from the fetch `ThreadsDossierBuilder` already performs for `ThreadsDossierFormatter.dossier(allContexts:)`. If you find yourself adding a `fetchAll`, stop — the plan is wrong, not the constraint.
- Do **not** bump `TranscriptContext.currentSchemaVersion` (currently `4`). Nothing here changes how context is derived, so no stored file becomes stale. Bumping it would force a needless full re-analysis sweep.
- Line cap is **3**, matching `DossierSenses.lineCap` and the working-memory bound.
- All thresholds are **starting values** subject to the field gate, following the `ThemeExtractor.minimumMentions` and `questionDensity` precedents. Never loosen a threshold to make a test pass — fix the fixture.
- Typography: any UI text uses `Constants.Typography.*`. Never `.system()` fonts.
- Run the full suite before each commit. Baseline 1388; expect growth, never reduction.
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

> **Note on test counts:** `xcodebuild` summary lines are unreliable under the macos-26 simulator flake. Count `Test Case '-[...]' started` lines instead.

---

## Task 1: Widen `DossierSenses.Input` with `historicalContexts`

**Why:** Signals 2 and 3 need historical marker data (`markers.modalCounts`, absolutist rate, sentiment) keyed by `recordingUUID`. `Input` currently carries only `currentRecordings`. The builder already fetches `allContexts` for `ThreadsDossierFormatter.dossier` — this is a widened hand-off, not a new query.

**Files:**
- Modify: `Pilgrim/Models/Threads/DossierSenses.swift` (the `Input` struct)
- Modify: `Pilgrim/Models/Threads/ThreadsDossierBuilder.swift` (`makeSensesInput`)
- Modify: `UnitTests/DossierSensesTests.swift` (`makeInput` helper)
- Modify: `UnitTests/DossierSensesCrossWalkTests.swift` (its `Input` construction)
- Modify: `UnitTests/FieldGateReportTests.swift` (its `Input` construction)

**Interfaces:**
- Produces: `DossierSenses.Input.historicalContexts: [TranscriptContext]` — every `TranscriptContext` the builder loaded, including the current walk's. Consumers filter by `recordingUUID`.

- [ ] **Step 1: Write the failing test**

Add to `UnitTests/DossierSensesTests.swift`:

```swift
func testInput_carriesHistoricalContexts() {
    let uuid = UUID()
    let context = TranscriptContext(
        schemaVersion: TranscriptContext.currentSchemaVersion,
        recordingUUID: uuid,
        transcriptHash: "hash",
        languageCode: "en",
        wordCount: 200,
        themes: [],
        markers: nil
    )
    let input = makeInput(historicalContexts: [context])
    XCTAssertEqual(input.historicalContexts.count, 1)
    XCTAssertEqual(input.historicalContexts.first?.recordingUUID, uuid)
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnitTests/DossierSensesTests
```

Expected: COMPILE FAILURE — `makeInput` has no parameter `historicalContexts`.

- [ ] **Step 3: Add the field and update all four construction sites**

In `Pilgrim/Models/Threads/DossierSenses.swift`, add to `Input` after `currentRecordings`:

```swift
        /// Every TranscriptContext the builder loaded, current walk
        /// included, so invariance signals can reach historical marker and
        /// modal data by `recordingUUID`. Wired from the fetch the builder
        /// already performs for ThreadsDossierFormatter — never a new query.
        let historicalContexts: [TranscriptContext]
```

In `ThreadsDossierBuilder.makeSensesInput`, pass the contexts the builder already holds. `state.contextsByUUID` is the loaded map, so:

```swift
            historicalContexts: Array(state.contextsByUUID.values),
```

Place it in the `DossierSenses.Input(...)` call immediately after `currentRecordings:`.

In each of the three test files, add the parameter to the local helper with a default so existing call sites stay unchanged. In `UnitTests/DossierSensesTests.swift`:

```swift
        historicalContexts: [TranscriptContext] = [],
```

as a `makeInput` parameter, and `historicalContexts: historicalContexts,` in the `Input(...)` body. Apply the identical change to `UnitTests/DossierSensesCrossWalkTests.swift` and `UnitTests/FieldGateReportTests.swift`.

- [ ] **Step 4: Run to verify it passes**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: the new test PASSES and the whole suite is green. This task changes no behaviour — if any existing test fails, the wiring is wrong.

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Threads/DossierSenses.swift Pilgrim/Models/Threads/ThreadsDossierBuilder.swift UnitTests/
git commit -m "refactor(threads): widen the senses Input to carry historical contexts

Invariance signals need marker and modal data from past recordings, keyed
by recordingUUID. The builder already loads every TranscriptContext to feed
ThreadsDossierFormatter, so this widens an existing hand-off rather than
adding a query. No behaviour change.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: The invariance engine — cap, priority, dedup

**Why:** The engine shell must exist before any signal, and it must be testable independently via a stub, exactly as `DossierSenses.lines` is.

**Files:**
- Create: `Pilgrim/Models/Threads/DossierSensesInvariance.swift`
- Create: `UnitTests/DossierSensesInvarianceTests.swift`

**Interfaces:**
- Produces:
  - `DossierSenses.Invariant` — `CaseIterable` enum, declaration order IS priority order
  - `DossierSenses.invarianceLines(input:evaluate:) -> [String]`
  - `DossierSenses.evaluateInvariant(_:input:suppressed:) -> SenseLine?`
  - `DossierSensesInvariance.pendingFieldGate: Bool`
  - `DossierSensesInvariance.minimumInvariantWalks: Int`
- Consumes: `DossierSenses.SenseLine` (existing), `DossierSenses.Input` (widened in Task 1)

- [ ] **Step 1: Write the failing tests**

Create `UnitTests/DossierSensesInvarianceTests.swift`:

```swift
import XCTest
@testable import Pilgrim

final class DossierSensesInvarianceTests: XCTestCase {

    private func emptyInput() -> DossierSenses.Input {
        DossierSenses.Input(
            currentWalkUUID: UUID(),
            walkStart: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            walkEnd: DateFactory.makeDate(2024, 6, 15, 10, 30, 0),
            totalAscent: 0, elevationSeries: [], photos: [],
            currentRecordings: [], historicalContexts: [], threads: [],
            backfillComplete: true, walkSnapshots: [], recordingTimestamps: [:],
            fixes: [:], moon: nil
        )
    }

    private func stub(_ firing: [DossierSenses.Invariant: DossierSenses.SenseLine])
        -> (DossierSenses.Invariant, DossierSenses.Input, Set<String>) -> DossierSenses.SenseLine? {
        { invariant, _, _ in firing[invariant] }
    }

    func testEngine_allFiring_capsAtThreeInPriorityOrder() {
        let lines = DossierSenses.invarianceLines(
            input: emptyInput(),
            evaluate: stub([
                .fusedThemes: .init(text: "fused", lemma: "father"),
                .unmovedReturn: .init(text: "unmoved", lemma: "work"),
                .frameConstancy: .init(text: "frame", lemma: "money"),
                .placeFrameLock: .init(text: "place", lemma: "river")
            ])
        )
        XCTAssertEqual(lines, ["fused", "unmoved", "frame"])
    }

    func testEngine_lemmaClaimedByHigherRank_suppressesLowerRank() {
        let lines = DossierSenses.invarianceLines(
            input: emptyInput(),
            evaluate: stub([
                .fusedThemes: .init(text: "fused", lemma: "work"),
                .unmovedReturn: .init(text: "unmoved", lemma: "work"),
                .frameConstancy: .init(text: "frame", lemma: "money")
            ])
        )
        XCTAssertEqual(lines, ["fused", "frame"])
    }

    func testEngine_nilLemmaNeverSuppresses() {
        let lines = DossierSenses.invarianceLines(
            input: emptyInput(),
            evaluate: stub([
                .fusedThemes: .init(text: "a", lemma: nil),
                .unmovedReturn: .init(text: "b", lemma: nil)
            ])
        )
        XCTAssertEqual(lines, ["a", "b"])
    }

    func testEngine_noneFiring_returnsEmpty() {
        XCTAssertTrue(DossierSenses.invarianceLines(input: emptyInput(), evaluate: stub([:])).isEmpty)
    }

    func testInvariantOrder_isTheSpecPriorityOrder() {
        XCTAssertEqual(
            DossierSenses.Invariant.allCases,
            [.fusedThemes, .unmovedReturn, .frameConstancy, .placeFrameLock, .unarrivedIntention]
        )
    }

    func testUnarrivedIntention_isDarkByDefault() {
        XCTAssertTrue(DossierSensesInvariance.pendingFieldGate)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnitTests/DossierSensesInvarianceTests
```

Expected: COMPILE FAILURE — no `Invariant`, no `invarianceLines`, no `DossierSensesInvariance`.

- [ ] **Step 3: Create the engine**

Create `Pilgrim/Models/Threads/DossierSensesInvariance.swift`:

```swift
import Foundation
import CoreLocation

/// Invariance track for the dossier's `Unchanged:` block — the mirror of
/// `Noticed:`. Where the senses report what was distinctive about THIS
/// walk, these report what has never moved across all of them.
///
/// Binding purity contract, identical to `DossierSenses`: no DataManager,
/// no CoreStore, no singleton access, and `Date()` is never called here —
/// time arrives as data. Every line stays traceable to enumerable,
/// deterministic inputs.
///
/// Why invariance at all: escaping a bad problem framing means noticing
/// what stayed the same across your failed attempts and changing THAT
/// (Kaplan & Simon 1990). Nobody keeps that record about themselves.
/// Thought Threads is that record.
enum DossierSensesInvariance {

    /// Signal 5 (unarrived intention) ships dark. It is the most
    /// confronting line the app can produce — it says, in effect, that the
    /// walker deliberately tried and nothing moved. Engine and tests ship;
    /// the flag flips only after the field gate judges it on real history.
    /// Mirrors `ThreadIntentionSuggestions.pendingFieldGate`.
    static let pendingFieldGate = true

    /// Every invariant needs at least this many walks before it may speak.
    /// Below it, a "pattern" is noise wearing a pattern's clothes.
    static let minimumInvariantWalks = 3

    /// Coefficient-of-variation ceiling for calling a marker profile flat.
    static let markerFlatnessCeiling = 0.20

    /// NLTagger sentiment spans -1...1, so a theme whose mean sits near
    /// zero would make raw CV explode. Shift into 0...2 before dividing.
    static let sentimentShift = 1.0
}

extension DossierSenses {

    /// Declaration order IS the spec's binding priority order — reordering
    /// cases reorders the block, exactly as with `Sense`.
    enum Invariant: CaseIterable {
        case fusedThemes, unmovedReturn, frameConstancy, placeFrameLock, unarrivedIntention
    }

    /// `evaluate` is a test seam, same style as `lines(input:evaluate:)`.
    static func invarianceLines(
        input: Input,
        evaluate: (Invariant, Input, Set<String>) -> SenseLine? = {
            DossierSenses.evaluateInvariant($0, input: $1, suppressed: $2)
        }
    ) -> [String] {
        var used = Set<String>()
        var lines: [String] = []
        for invariant in Invariant.allCases {
            guard lines.count < lineCap else { break }
            guard let line = evaluate(invariant, input, used) else { continue }
            if let lemma = line.lemma {
                guard !used.contains(lemma) else { continue }
                used.insert(lemma)
            }
            lines.append(line.text)
        }
        return lines
    }

    static func evaluateInvariant(
        _ invariant: Invariant, input: Input, suppressed: Set<String>
    ) -> SenseLine? {
        switch invariant {
        case .fusedThemes: return nil
        case .unmovedReturn: return nil
        case .frameConstancy: return nil
        case .placeFrameLock: return nil
        case .unarrivedIntention: return nil
        }
    }
}
```

Each `case` returns `nil` for now; Tasks 3–7 fill them in one at a time.

- [ ] **Step 4: Run to verify it passes**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnitTests/DossierSensesInvarianceTests
```

Expected: all six PASS.

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Threads/DossierSensesInvariance.swift UnitTests/DossierSensesInvarianceTests.swift
git commit -m "feat(threads): the invariance engine — cap, priority, dedup

The mirror of Noticed:. Where the senses report what was distinctive about
this walk, these report what has never moved across all of them. Same
purity contract, same three-line cap, same lemma suppression so a theme
named at a higher rank never speaks twice.

Signal 5 ships dark from the first commit — the flag exists before the
signal does, so it can never accidentally ship live.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Signal 1 — fused themes

**Why:** Two themes whose walk-sets are identical or nested are a **structural** invariant the walker cannot see, because it is a grouping they performed pre-categorically. Cheapest signal and the most arresting: *"you have not spoken about your father without also speaking about money."*

**Files:**
- Modify: `Pilgrim/Models/Threads/DossierSensesInvariance.swift`
- Modify: `UnitTests/DossierSensesInvarianceTests.swift`

**Interfaces:**
- Produces: `DossierSensesInvariance.fusedThemes(input:suppressed:) -> DossierSenses.SenseLine?`
- Consumes: `WalkThread.appearances` → `ThreadAppearance.walkUUID`

- [ ] **Step 1: Write the failing tests**

Add to `UnitTests/DossierSensesInvarianceTests.swift`:

```swift
    private func thread(_ lemma: String, walks: [UUID], salience: Double = 0.5) -> WalkThread {
        WalkThread(
            lemma: lemma,
            displayTerm: lemma,
            appearances: walks.map {
                ThreadAppearance(
                    recordingUUID: UUID(), walkUUID: $0,
                    date: DateFactory.makeDate(2024, 6, 1, 9, 0, 0),
                    mentionCount: 3, salience: salience
                )
            }
        )
    }

    private func inputWith(threads: [WalkThread]) -> DossierSenses.Input {
        DossierSenses.Input(
            currentWalkUUID: threads.first?.appearances.first?.walkUUID ?? UUID(),
            walkStart: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            walkEnd: DateFactory.makeDate(2024, 6, 15, 10, 30, 0),
            totalAscent: 0, elevationSeries: [], photos: [],
            currentRecordings: [], historicalContexts: [], threads: threads,
            backfillComplete: true, walkSnapshots: [], recordingTimestamps: [:],
            fixes: [:], moon: nil
        )
    }

    func testFusedThemes_identicalWalkSets_fires() {
        let walks = [UUID(), UUID(), UUID()]
        let input = inputWith(threads: [
            thread("father", walks: walks),
            thread("money", walks: walks)
        ])
        let line = DossierSensesInvariance.fusedThemes(input: input, suppressed: [])
        XCTAssertEqual(
            line?.text,
            "'father' and 'money' have appeared in 3 of 3 walks together, never apart."
        )
        XCTAssertEqual(line?.lemma, "father")
    }

    func testFusedThemes_nestedWalkSet_fires() {
        let subsetWalks = [UUID(), UUID(), UUID()]
        let supersetWalks = subsetWalks + [UUID(), UUID()]
        let input = inputWith(threads: [
            thread("father", walks: subsetWalks),
            thread("money", walks: supersetWalks)
        ])
        let line = DossierSensesInvariance.fusedThemes(input: input, suppressed: [])
        XCTAssertEqual(
            line?.text,
            "'father' has appeared in 3 walks, always alongside 'money' — which walked 5 in all."
        )
        XCTAssertEqual(line?.lemma, "father")
    }

    func testFusedThemes_nestedWalkSet_doesNotClaimSymmetricNeverApart() {
        let subsetWalks = [UUID(), UUID(), UUID()]
        let supersetWalks = subsetWalks + [UUID(), UUID()]
        let input = inputWith(threads: [
            thread("father", walks: subsetWalks),
            thread("money", walks: supersetWalks)
        ])
        let line = DossierSensesInvariance.fusedThemes(input: input, suppressed: [])
        XCTAssertFalse(line?.text.contains("never apart") ?? true)
    }

    func testFusedThemes_belowMinimumWalks_staysSilent() {
        let walks = [UUID(), UUID()]
        let input = inputWith(threads: [
            thread("father", walks: walks),
            thread("money", walks: walks)
        ])
        XCTAssertNil(DossierSensesInvariance.fusedThemes(input: input, suppressed: []))
    }

    func testFusedThemes_partialOverlap_staysSilent() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let input = inputWith(threads: [
            thread("father", walks: [a, b, c]),
            thread("money", walks: [b, c, d])
        ])
        XCTAssertNil(DossierSensesInvariance.fusedThemes(input: input, suppressed: []))
    }

    func testFusedThemes_suppressedLemma_staysSilent() {
        let walks = [UUID(), UUID(), UUID()]
        let input = inputWith(threads: [
            thread("father", walks: walks),
            thread("money", walks: walks)
        ])
        XCTAssertNil(DossierSensesInvariance.fusedThemes(input: input, suppressed: ["father"]))
    }
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnitTests/DossierSensesInvarianceTests
```

Expected: COMPILE FAILURE — no `fusedThemes`.

- [ ] **Step 3: Implement**

Add to `DossierSensesInvariance` in `Pilgrim/Models/Threads/DossierSensesInvariance.swift`:

```swift
extension DossierSensesInvariance {

    /// Two themes whose walk-sets are identical, or where one nests wholly
    /// inside the other, across at least `minimumInvariantWalks` walks.
    ///
    /// This is a grouping the walker performed pre-categorically — they
    /// gathered two things together without ever deciding to, which is
    /// exactly the move that precedes forming a category. Partial overlap
    /// is NOT fusion: two themes sharing some walks is ordinary, and
    /// reporting it would be the Goodman error (everything resembles
    /// everything if you pick the properties afterwards).
    ///
    /// Identical and strictly-nested walk-sets are rendered differently:
    /// "never apart" is a true, symmetric claim only when the sets are
    /// equal. When one theme's walks are a strict subset of the other's,
    /// the superset theme has walks the subset theme took no part in, so
    /// the claim must be anchored — and worded — on the subset theme alone.
    /// That is also why `lemma` is always the subset theme's: `best.subset`
    /// on a strict nest, either theme when the sets are equal.
    ///
    /// Deterministic: threads arrive lemma-sorted from `ThreadStore.build`,
    /// and only a STRICTLY larger shared-walk count replaces the best pair.
    static func fusedThemes(
        input: DossierSenses.Input, suppressed: Set<String>
    ) -> DossierSenses.SenseLine? {
        let candidates = input.threads
            .filter { !suppressed.contains($0.lemma) }
            .map { (thread: $0, walks: Set($0.appearances.map(\.walkUUID))) }
            .filter { $0.walks.count >= minimumInvariantWalks }

        guard candidates.count >= 2 else { return nil }

        var best: (subset: WalkThread, superset: WalkThread, shared: Int, outer: Int)?
        for i in candidates.indices {
            for j in candidates.indices where j > i {
                let (first, second) = (candidates[i], candidates[j])
                let firstIsSubset = first.walks.isSubset(of: second.walks)
                let secondIsSubset = second.walks.isSubset(of: first.walks)
                guard firstIsSubset || secondIsSubset else { continue }
                let shared = first.walks.intersection(second.walks).count
                let outer = max(first.walks.count, second.walks.count)
                guard best == nil || shared > best!.shared else { continue }
                best = firstIsSubset
                    ? (first.thread, second.thread, shared, outer)
                    : (second.thread, first.thread, shared, outer)
            }
        }

        guard let best else { return nil }

        guard best.shared < best.outer else {
            return DossierSenses.SenseLine(
                text: "'\(best.subset.displayTerm)' and '\(best.superset.displayTerm)' have appeared in "
                    + "\(best.shared) of \(best.outer) walks together, never apart.",
                lemma: best.subset.lemma
            )
        }

        return DossierSenses.SenseLine(
            text: "'\(best.subset.displayTerm)' has appeared in \(best.shared) walks, always alongside "
                + "'\(best.superset.displayTerm)' — which walked \(best.outer) in all.",
            lemma: best.subset.lemma
        )
    }
}
```

Then wire the case in `evaluateInvariant`:

```swift
        case .fusedThemes:
            return DossierSensesInvariance.fusedThemes(input: input, suppressed: suppressed)
```

- [ ] **Step 4: Run to verify it passes**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnitTests/DossierSensesInvarianceTests
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Threads/DossierSensesInvariance.swift UnitTests/DossierSensesInvarianceTests.swift
git commit -m "feat(threads): fused themes — the two that never travel apart

Two themes whose walk-sets nest are a grouping the walker made without
deciding to, which is the move that comes before forming a category at all.
They cannot see it, because it is the shape of their looking.

Partial overlap deliberately does not count. Two themes sharing some walks
is ordinary, and calling that fusion would be picking the properties after
the fact - which is how you end up proving a lawn mower resembles a plum.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Signal 2 — the unmoved return

**Why:** A theme that recurs with steady salience *and* a flat marker profile is the invariant across the walker's returns. `ThreadStore.salienceDirection` already computes `.steady` and `ThreadsDossierFormatter` already prints it as a throwaway clause — this gives it the weight it deserves.

**Files:**
- Modify: `Pilgrim/Models/Threads/DossierSensesInvariance.swift`
- Modify: `UnitTests/DossierSensesInvarianceTests.swift`

**Interfaces:**
- Produces: `DossierSensesInvariance.unmovedReturn(input:suppressed:) -> DossierSenses.SenseLine?`
- Consumes: `ThreadStore.salienceDirection(of:)`, `TranscriptContext.markers`, `ThreadsDossierFormatter.densityFloorWords`

- [ ] **Step 1: Write the failing tests**

Add to `UnitTests/DossierSensesInvarianceTests.swift`:

```swift
    private func markerContext(
        _ uuid: UUID, absolutist: Int, firstPerson: Int, sentiment: Double, words: Int = 200
    ) -> TranscriptContext {
        TranscriptContext(
            schemaVersion: TranscriptContext.currentSchemaVersion,
            recordingUUID: uuid, transcriptHash: "h", languageCode: "en",
            wordCount: words, themes: [],
            markers: MarkerPack(
                wordCount: words, absolutistCount: absolutist, firstPersonCount: firstPerson,
                insightCount: 2, causationCount: 2, discrepancyCount: 1,
                futureCount: 3, pastCount: 3, sentiment: sentiment, modalCounts: [:]
            )
        )
    }

    private func steadyThread(_ lemma: String, recordings: [UUID], walks: [UUID]) -> WalkThread {
        WalkThread(
            lemma: lemma, displayTerm: lemma,
            appearances: zip(recordings, walks).map { rec, walk in
                ThreadAppearance(
                    recordingUUID: rec, walkUUID: walk,
                    date: DateFactory.makeDate(2024, 6, 1, 9, 0, 0),
                    mentionCount: 3, salience: 0.5
                )
            }
        )
    }

    func testUnmovedReturn_steadySalienceFlatMarkers_fires() {
        let recs = [UUID(), UUID(), UUID()]
        let input = DossierSenses.Input(
            currentWalkUUID: UUID(),
            walkStart: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            walkEnd: DateFactory.makeDate(2024, 6, 15, 10, 30, 0),
            totalAscent: 0, elevationSeries: [], photos: [], currentRecordings: [],
            historicalContexts: [
                markerContext(recs[0], absolutist: 10, firstPerson: 20, sentiment: -0.2),
                markerContext(recs[1], absolutist: 10, firstPerson: 21, sentiment: -0.2),
                markerContext(recs[2], absolutist: 11, firstPerson: 20, sentiment: -0.21)
            ],
            threads: [steadyThread("work", recordings: recs, walks: [UUID(), UUID(), UUID()])],
            backfillComplete: true, walkSnapshots: [], recordingTimestamps: [:],
            fixes: [:], moon: nil
        )
        let line = DossierSensesInvariance.unmovedReturn(input: input, suppressed: [])
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.text.contains("work"))
        XCTAssertTrue(line!.text.contains("3 walks"))
    }

    func testUnmovedReturn_markersVary_staysSilent() {
        let recs = [UUID(), UUID(), UUID()]
        let input = DossierSenses.Input(
            currentWalkUUID: UUID(),
            walkStart: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            walkEnd: DateFactory.makeDate(2024, 6, 15, 10, 30, 0),
            totalAscent: 0, elevationSeries: [], photos: [], currentRecordings: [],
            historicalContexts: [
                markerContext(recs[0], absolutist: 2, firstPerson: 5, sentiment: -0.8),
                markerContext(recs[1], absolutist: 20, firstPerson: 40, sentiment: 0.7),
                markerContext(recs[2], absolutist: 11, firstPerson: 20, sentiment: 0.0)
            ],
            threads: [steadyThread("work", recordings: recs, walks: [UUID(), UUID(), UUID()])],
            backfillComplete: true, walkSnapshots: [], recordingTimestamps: [:],
            fixes: [:], moon: nil
        )
        XCTAssertNil(DossierSensesInvariance.unmovedReturn(input: input, suppressed: []))
    }

    func testUnmovedReturn_belowDensityFloor_staysSilent() {
        let recs = [UUID(), UUID(), UUID()]
        let input = DossierSenses.Input(
            currentWalkUUID: UUID(),
            walkStart: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            walkEnd: DateFactory.makeDate(2024, 6, 15, 10, 30, 0),
            totalAscent: 0, elevationSeries: [], photos: [], currentRecordings: [],
            historicalContexts: recs.map {
                markerContext($0, absolutist: 1, firstPerson: 2, sentiment: -0.2, words: 40)
            },
            threads: [steadyThread("work", recordings: recs, walks: [UUID(), UUID(), UUID()])],
            backfillComplete: true, walkSnapshots: [], recordingTimestamps: [:],
            fixes: [:], moon: nil
        )
        XCTAssertNil(DossierSensesInvariance.unmovedReturn(input: input, suppressed: []))
    }
```

- [ ] **Step 2: Run to verify it fails**

Expected: COMPILE FAILURE — no `unmovedReturn`.

- [ ] **Step 3: Implement**

Add to `DossierSensesInvariance`:

```swift
extension DossierSensesInvariance {

    /// A theme that recurs with steady salience AND a flat marker profile:
    /// it has come back, and every time it sounds the same. That sameness
    /// across returns is the invariant — the thing that did not budge while
    /// the walker kept working at it.
    ///
    /// Appearances below `densityFloorWords` are EXCLUDED, never counted as
    /// flat: a short recording is not evidence of sameness, it is absence
    /// of evidence. At least `minimumInvariantWalks` must clear the floor.
    static func unmovedReturn(
        input: DossierSenses.Input, suppressed: Set<String>
    ) -> DossierSenses.SenseLine? {
        let byRecording = Dictionary(
            input.historicalContexts.map { ($0.recordingUUID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for thread in input.threads.sorted(by: { $0.lemma < $1.lemma })
        where !suppressed.contains(thread.lemma) {
            guard ThreadStore.salienceDirection(of: thread) == .steady else { continue }

            // Key on distinct WALKS, not qualifying recordings. Counting
            // recordings lets three short bursts on one walk clear a floor
            // named `minimumInvariantWalks`, and lets a sub-floor walk
            // inflate the rendered count — the line would then claim
            // evidence from a walk excluded from the flatness computation.
            // Same walk-keying `fusedThemes` uses, and the precedent
            // `ThreadsDossierFormatter.modalBaselineFloorWalks` documents.
            let qualifying = thread.appearances.compactMap { appearance -> (walkUUID: UUID, markers: MarkerPack)? in
                guard let markers = byRecording[appearance.recordingUUID]?.markers,
                      markers.wordCount >= ThreadsDossierFormatter.densityFloorWords else { return nil }
                return (appearance.walkUUID, markers)
            }
            let walks = Set(qualifying.map(\.walkUUID))
            guard walks.count >= minimumInvariantWalks else { continue }

            let packs = qualifying.map(\.markers)
            let absolutist = packs.map { Double($0.absolutistCount) / Double($0.wordCount) }
            let firstPerson = packs.map { Double($0.firstPersonCount) / Double($0.wordCount) }
            let sentiment = packs.compactMap { $0.sentiment }.map { $0 + sentimentShift }
            guard sentiment.count == packs.count else { continue }

            guard isFlat(absolutist), isFlat(firstPerson), isFlat(sentiment) else { continue }

            return DossierSenses.SenseLine(
                text: "'\(thread.displayTerm)' has returned across \(walks.count) walks; "
                    + "it sounds the same each time.",
                lemma: thread.lemma
            )
        }
        return nil
    }

    /// Coefficient of variation at or under the flatness ceiling. A zero or
    /// negative mean cannot be judged this way, so it is treated as not
    /// flat rather than dividing by it.
    static func isFlat(_ values: [Double]) -> Bool {
        guard values.count >= 2 else { return false }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 0 else { return false }
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return (variance.squareRoot() / mean) <= markerFlatnessCeiling
    }
}
```

Wire the case:

```swift
        case .unmovedReturn:
            return DossierSensesInvariance.unmovedReturn(input: input, suppressed: suppressed)
```

- [ ] **Step 4: Run to verify it passes**

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Threads/DossierSensesInvariance.swift UnitTests/DossierSensesInvarianceTests.swift
git commit -m "feat(threads): the unmoved return — it came back sounding the same

salienceDirection has been computing .steady since Threads shipped and the
dossier printed it as a trailing clause nobody could use. Steady salience
plus a flat marker profile is not a footnote: it is the thing that did not
budge while the walker kept working at it.

Recordings under the density floor are excluded rather than counted flat.
A short recording is absence of evidence, not evidence of sameness.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Signal 3 — frame constancy

**Why:** If every walk where a theme appears is dominated by the same modal family, the walker has been thinking about it inside one fixed frame. Obligation means the frame constrained them; counterfactual means they were already replaying alternatives.

**Files:**
- Modify: `Pilgrim/Models/Threads/DossierSensesInvariance.swift`
- Modify: `UnitTests/DossierSensesInvarianceTests.swift`
- New: `UnitTests/DossierSensesInvarianceFrameConstancyCoverageTests.swift` (split off when the review-fix pass pushed the parent test file toward the `file_length` gate — see Deviation 3)

**Interfaces:**
- Produces: `DossierSensesInvariance.frameConstancy(input:suppressed:) -> DossierSenses.SenseLine?`
- Consumes: `MarkerPack.modalCounts`, `MarkerLexicons.modalFamily(of:)`, `MarkerLexicons.ModalFamily`

**Adjudicated deviations from the draft below** (shipped code differs from the original Step 1/3 draft in three ways; each is intentional, reviewed, and must not be "simplified" back to the draft):

1. **Walk-keying, not appearance-keying.** The draft's `families` mapped one `MarkerLexicons.ModalFamily?` per `thread.appearances` element (i.e. per recording) and gated `families.count >= minimumInvariantWalks` on that — so three recordings on a *single* walk could clear a floor named `minimumInvariantWalks`, contradicting its own name. Shipped code groups by `appearance.walkUUID` first (`modalsByWalk: [UUID: [String: Int]]`, then `allWalks = Set(thread.appearances.map(\.walkUUID))`), matching `fusedThemes` and `unmovedReturn`, which both gate on distinct walk count for the same reason (spelled out in `unmovedReturn`'s doc comment and `ThreadsDossierFormatter.modalBaselineFloorWalks`).
2. **Same-walk summing.** When a walk carries more than one recording and their modal counts individually disagree, shipped code sums `modalCounts` across the walk into one total before picking a dominant family for that walk — mirroring `ThreadsDossierFormatter.modalLeanSummary`'s handling of today's walk. Picking one recording's dominance to stand for the whole walk (or "last recording wins") was rejected as an unprincipled way to resolve a same-walk disagreement. Pinned by `testFrameConstancy_recordingsOnSameWalk_combineByModalCountSum`.
3. **Full walk-coverage requirement (review fix, post-ship).** The rendered line says "Every walk where '_' appears is X-dominant." The draft below computed `families` via `compactMap`, which *silently dropped* any walk whose only recording(s) had `markers == nil` (non-English) or empty `modalCounts` (no modal words spoken) — so a theme appearing in 4 walks, 3 agreeing and 1 with no modal evidence at all, would still render "every walk" while never having looked at the fourth. Shipped code requires **full coverage**: every walk in `allWalks` (not just the ones with evidence) must produce a non-nil dominant family, or the whole signal stays silent — `dominantFamilies.count == allWalks.count` before the `allSatisfy` check. This is the strong option, not the fallback ("bind the text to what was measured, e.g. name the count of walks that carried modal language") — full coverage did not make the signal unfirable on realistic fixtures (three agreeing walks with modal language is common speech, not a corner case), so the fallback wasn't needed. Silence is this feature's correct default when evidence is incomplete, per the type's doc comment. Pinned by `testFrameConstancy_oneWalkNonEnglish_holdsSignalSilent` and `testFrameConstancy_oneWalkNoModalWordsSpoken_holdsSignalSilent`.

The near-miss boundary (two walks agree, one differs, all three with full modal coverage) is pinned separately by `testFrameConstancy_twoOfThreeAgree_oneDiffers_staysSilent` — the original draft only tested full three-way disagreement, which doesn't exercise `allSatisfy`'s N-1 case.

- [ ] **Step 1: Write the failing tests**

```swift
    private func modalContext(_ uuid: UUID, modals: [String: Int], words: Int = 200) -> TranscriptContext {
        TranscriptContext(
            schemaVersion: TranscriptContext.currentSchemaVersion,
            recordingUUID: uuid, transcriptHash: "h", languageCode: "en",
            wordCount: words, themes: [],
            markers: MarkerPack(
                wordCount: words, absolutistCount: 5, firstPersonCount: 10,
                insightCount: 2, causationCount: 2, discrepancyCount: 1,
                futureCount: 3, pastCount: 3, sentiment: -0.1, modalCounts: modals
            )
        )
    }

    private func modalInput(_ contexts: [TranscriptContext], _ thread: WalkThread) -> DossierSenses.Input {
        DossierSenses.Input(
            currentWalkUUID: UUID(),
            walkStart: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            walkEnd: DateFactory.makeDate(2024, 6, 15, 10, 30, 0),
            totalAscent: 0, elevationSeries: [], photos: [], currentRecordings: [],
            historicalContexts: contexts, threads: [thread],
            backfillComplete: true, walkSnapshots: [], recordingTimestamps: [:],
            fixes: [:], moon: nil
        )
    }

    func testFrameConstancy_sameFamilyEveryWalk_fires() {
        let recs = [UUID(), UUID(), UUID()]
        let input = modalInput(
            [
                modalContext(recs[0], modals: ["should": 12, "can": 2]),
                modalContext(recs[1], modals: ["should": 9, "might": 1]),
                modalContext(recs[2], modals: ["must": 7, "could": 2])
            ],
            steadyThread("money", recordings: recs, walks: [UUID(), UUID(), UUID()])
        )
        let line = DossierSensesInvariance.frameConstancy(input: input, suppressed: [])
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.text.contains("money"))
        XCTAssertTrue(line!.text.contains("obligation"))
    }

    func testFrameConstancy_familyVaries_staysSilent() {
        let recs = [UUID(), UUID(), UUID()]
        let input = modalInput(
            [
                modalContext(recs[0], modals: ["should": 12]),
                modalContext(recs[1], modals: ["could": 11]),
                modalContext(recs[2], modals: ["would": 9])
            ],
            steadyThread("money", recordings: recs, walks: [UUID(), UUID(), UUID()])
        )
        XCTAssertNil(DossierSensesInvariance.frameConstancy(input: input, suppressed: []))
    }

    func testFrameConstancy_noModalsAtAll_staysSilent() {
        let recs = [UUID(), UUID(), UUID()]
        let input = modalInput(
            recs.map { modalContext($0, modals: [:]) },
            steadyThread("money", recordings: recs, walks: [UUID(), UUID(), UUID()])
        )
        XCTAssertNil(DossierSensesInvariance.frameConstancy(input: input, suppressed: []))
    }
```

Superseded by Deviations 1-3 above — shipped tests additionally cover: three recordings landing on one walk (`testFrameConstancy_threeRecordingsOnOneWalk_staysSilent`), same-walk sum resolving a same-walk disagreement (`testFrameConstancy_recordingsOnSameWalk_combineByModalCountSum`), the exact rendered string (`testFrameConstancy_sameFamilyEveryWalk_fires` now asserts `line?.text ==`, not just `.contains`), one walk lacking modal evidence via non-English markers or empty modalCounts (both hold the signal silent), and the N-1-agree near-miss boundary. The evidence-coverage and near-miss tests live in `UnitTests/DossierSensesInvarianceFrameConstancyCoverageTests.swift`, an `extension DossierSensesInvarianceTests` in a separate file (parent file sits at the `file_length` gate; `modalContext`, `modalInput`, `steadyThread` were widened from `private` to internal so the extension file can share them — same pattern as `DossierSensesCrossWalkMoonTests.swift`).

- [ ] **Step 2: Run to verify it fails**

Expected: COMPILE FAILURE — no `frameConstancy`.

- [ ] **Step 3: Implement**

```swift
extension DossierSensesInvariance {

    /// One modal family dominant in EVERY walk where the theme appears.
    /// Modals name the shape of the frame the walker was thinking inside —
    /// obligation constrains, counterfactual replays alternatives,
    /// possibility and tentative stay open. The same family every time is
    /// a frame that never varied.
    ///
    /// Grouped and gated by distinct WALK, not by qualifying recording,
    /// mirroring `fusedThemes` and `unmovedReturn` (Deviation 1 above): a
    /// theme argued in three bursts on one walk is one data point about one
    /// frame, not three. When a walk carries more than one recording, their
    /// modal counts are SUMMED into a single per-walk total before a
    /// dominant family is picked (Deviation 2), mirroring
    /// `ThreadsDossierFormatter.modalLeanSummary`.
    ///
    /// The rendered line claims "every walk". That claim is only true if
    /// EVERY walk where the theme appears has a dominant family — so a walk
    /// with no modal evidence (its only recording(s) have `markers == nil`,
    /// i.e. non-English, or an empty/unmapped `modalCounts`) is not
    /// silently dropped from the pool. A single uncovered walk holds the
    /// whole signal silent (Deviation 3) — full coverage is the price of
    /// the word "every". Silence is the correct default; see the type's
    /// doc comment.
    ///
    /// Per-walk dominance is a MODE, not a majority — the same fix PR #71
    /// applied to weatherWeave to kill the cloud tautologies. A family can
    /// dominate with 40% of the modals as long as nothing beats it.
    /// Deterministic ties: `ModalFamily.allCases` is declaration-ordered
    /// and only a STRICTLY greater count replaces the running best.
    static func frameConstancy(
        input: DossierSenses.Input, suppressed: Set<String>
    ) -> DossierSenses.SenseLine? {
        let byRecording = Dictionary(
            input.historicalContexts.map { ($0.recordingUUID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for thread in input.threads.sorted(by: { $0.lemma < $1.lemma })
        where !suppressed.contains(thread.lemma) {
            let allWalks = Set(thread.appearances.map(\.walkUUID))
            guard allWalks.count >= minimumInvariantWalks else { continue }

            var modalsByWalk: [UUID: [String: Int]] = [:]
            for appearance in thread.appearances {
                guard let modals = byRecording[appearance.recordingUUID]?.markers?.modalCounts,
                      !modals.isEmpty else { continue }
                modalsByWalk[appearance.walkUUID, default: [:]].merge(modals, uniquingKeysWith: +)
            }

            let dominantFamilies = allWalks.compactMap { modalsByWalk[$0].flatMap(dominantModalFamily) }
            guard dominantFamilies.count == allWalks.count,
                  let first = dominantFamilies.first,
                  dominantFamilies.allSatisfy({ $0 == first }) else { continue }

            return DossierSenses.SenseLine(
                text: "Every walk where '\(thread.displayTerm)' appears is "
                    + "\(first.rawValue)-dominant.",
                lemma: thread.lemma
            )
        }
        return nil
    }

    /// The dominant `ModalFamily` for one walk's summed modal counts, or
    /// nil if none of the words present map to a known family. A mode over
    /// family totals, not a majority share — see `frameConstancy`.
    private static func dominantModalFamily(in modals: [String: Int]) -> MarkerLexicons.ModalFamily? {
        var totals: [MarkerLexicons.ModalFamily: Int] = [:]
        for (word, count) in modals {
            guard let family = MarkerLexicons.modalFamily(of: word) else { continue }
            totals[family, default: 0] += count
        }
        var best: (family: MarkerLexicons.ModalFamily, count: Int)?
        for family in MarkerLexicons.ModalFamily.allCases {
            let count = totals[family] ?? 0
            guard count > 0, best == nil || count > best!.count else { continue }
            best = (family, count)
        }
        return best?.family
    }
}
```

Wire the case:

```swift
        case .frameConstancy:
            return DossierSensesInvariance.frameConstancy(input: input, suppressed: suppressed)
```

- [ ] **Step 4: Run to verify it passes**

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Threads/DossierSensesInvariance.swift UnitTests/DossierSensesInvarianceTests.swift
git commit -m "feat(threads): frame constancy — it always arrives the same way

Modal families name the shape of the frame the walker was thinking inside.
Obligation constrains, counterfactual replays alternatives, possibility
stays open. The same family in every single walk where a theme appears is a
frame that never once varied.

Dominance is a mode, not a majority - the fix PR #71 made to weatherWeave
after majority-voting produced cloud tautologies.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

Review fix (post-ship, same task): full walk-coverage requirement plus
the N-1-agree boundary test. See Deviation 3 above and
`.superpowers/sdd/task-5-report.md` for the fix commit and test run.

---

## Task 6: Signal 4 — place-frame lock

**Why:** The same theme spoken within the same 150m cluster every time is an invariant tied to ground, not language. `placeResonance` already proves the clustering machinery works over `fixes`.

**Files:**
- Modify: `Pilgrim/Models/Threads/DossierSensesInvariance.swift`
- New: `UnitTests/DossierSensesInvariancePlaceFrameLockTests.swift` (not an edit to `DossierSensesInvarianceTests.swift` — see Deviation 1)

**Interfaces:**
- Produces: `DossierSensesInvariance.placeFrameLock(input:suppressed:) -> DossierSenses.SenseLine?`
- Consumes: `DossierSenses.Input.fixes`, `DossierSenses.qualifies(_:)`, `DossierSenses.distance(_:_:)`, `DossierSenses.placeClusterRadius`

**Adjudicated deviations from the draft below** (shipped code differs from the original Step 1/3 draft in three ways; each is intentional, reviewed *before* ship — not a post-ship fix like Task 5's — and must not be "simplified" back to the draft):

1. **New test file, not an edit to the parent.** `UnitTests/DossierSensesInvarianceTests.swift` was already at 458 lines against the `file_length` warning gate of 500 (`.swiftlint.yml`); this signal's fixture-heavy tests (each needs its own `fixes` dictionary) would have pushed it over. Filed as `UnitTests/DossierSensesInvariancePlaceFrameLockTests.swift`, an `extension DossierSensesInvarianceTests` reusing the parent's `steadyThread` fixture — same split pattern Task 5 used for `DossierSensesInvarianceFrameConstancyCoverageTests.swift`. Registered with 4 hand-added `project.pbxproj` entries (`PBXBuildFile`, `PBXFileReference`, group listing, `PBXSourcesBuildPhase` listing) — `UnitTests` uses explicit file references, not a synchronized group.
2. **Full walk-coverage requirement, baked in from the start — SUPERSEDED by Deviation 4 below, kept here for the historical record.** The rendered line says "has been spoken in the same place on all N walks it appears in" — a totalizing claim over the theme's entire appearance history, the same shape as `frameConstancy`'s "every walk" (Task 5's post-ship FIX 1). The draft below computed `walks` from `Set(thread.appearances.map(\.walkUUID)).count` — *every* appearance, regardless of whether its fix qualified — while the clustering check (`coordinates`) ran only over the subset that passed `DossierSenses.qualifies`. A theme in 5 walks where only 3 had usable fixes would have rendered "all 5 walks" on evidence from 3. Shipped code (as of this commit) grouped qualifying fixes by `walkUUID` first (`coordinatesByWalk: [UUID: [Coordinate]]`) and required `coordinatesByWalk.count == allWalks.count` — every walk in the theme's walk-set had to contribute at least one qualifying fix, or the whole signal stayed silent — before rendering `allWalks.count` as the "all N" figure. This is the strong option (full coverage), the same choice Task 5 made for the identically-shaped problem, not the fallback of binding the text to a smaller, unqualified-of-"all" count. Originally pinned by `testPlaceFrameLock_oneWalkWithNoFixAtAll_staysSilent`, since renamed to `testPlaceFrameLock_oneWalkWithNoFixAtAll_rendersMeasuredCoverage` under Deviation 4 (same fixture, opposite assertion).
3. **Cluster membership by max pairwise spread, not distance from an arbitrary anchor.** The draft below picked `coordinates.first` as an anchor and checked every other point was within `placeClusterRadius` of *it*. With a 150m radius, two points can each sit within 150m of a shared anchor while sitting up to 300m from each other — and which fix happens to be "first" is an artifact of iteration order, not geography. Shipped code instead requires the maximum distance between *any two* qualifying coordinates to be `<= placeClusterRadius` (`maxPairwiseSpread`, order-independent), mirroring the compactness `DossierSenses.bestCluster` already measures via its own `spread` field for `placeResonance`. Pinned by `testPlaceFrameLock_pointsNearSharedAnchorButFarApart_staysSilent`: three points where two sit ~130m from a shared anchor (each individually within radius of it) but ~260m from each other — the anchor-based draft would fire here; shipped code stays silent. **This check is UNCHANGED by Deviation 4 — do not touch it.**
4. **Coverage relaxed to the MEASURED set (owner's product decision, post-ship, 2026-08-27) — do not revert this to Deviation 2's full-coverage gate.** This app runs on rural pilgrimage routes where GPS quality varies. Full coverage meant one dead-zone walk with no fix at all could permanently silence an otherwise genuinely place-locked theme, which was judged too conservative. Shipped code (current) now gates `minimumInvariantWalks` on `coordinatesByWalk.count` — the count of walks that actually contributed a qualifying fix — instead of `allWalks.count`. A theme in 10 walks with only 1 usable fix still stays silent (clustering over fewer than `minimumInvariantWalks` points is not evidence of anything); a theme in 5 walks with 3 usable fixes that cluster tightly may now speak. The max-pairwise-spread check (Deviation 3) is untouched — this only moves which count the walk-floor and the "all N" figure are measured against. Two rendered variants now exist, following the precedent `fusedThemes` already sets for identical-vs-nested walk-sets: full coverage (`coordinatesByWalk.count == allWalks.count`) keeps "on all N walks it appears in"; partial coverage renders "on every walk where its location is known — M of the N it appears in", naming both the measured count and the total without implying anything about the walks that were not measured (we do not know where they were, only that we cannot say). Pinned by `testPlaceFrameLock_oneWalkWithNoFixAtAll_rendersMeasuredCoverage` (partial-coverage sentence, exact `XCTAssertEqual`) and `testPlaceFrameLock_measuredWalksBelowMinimum_staysSilentDespiteManyAppearances` (a theme in 10 walks with only 2 measured stays silent). See `.superpowers/sdd/task-6-report.md` ("## Coverage relaxation") for the commit and test run.

- [ ] **Step 1: Write the failing tests**

```swift
    func testPlaceFrameLock_sameCluster_fires() {
        let recs = [UUID(), UUID(), UUID()]
        var fixes: [UUID: DossierSenses.RouteFix] = [:]
        for (offset, rec) in recs.enumerated() {
            fixes[rec] = DossierSenses.RouteFix(
                coordinate: .init(latitude: 51.5 + Double(offset) * 0.0001, longitude: -0.12),
                horizontalAccuracy: 10, gapSeconds: 5
            )
        }
        var input = modalInput([], steadyThread("river", recordings: recs, walks: [UUID(), UUID(), UUID()]))
        input = DossierSenses.Input(
            currentWalkUUID: input.currentWalkUUID, walkStart: input.walkStart, walkEnd: input.walkEnd,
            totalAscent: 0, elevationSeries: [], photos: [], currentRecordings: [],
            historicalContexts: [], threads: input.threads, backfillComplete: true,
            walkSnapshots: [], recordingTimestamps: [:], fixes: fixes, moon: nil
        )
        let line = DossierSensesInvariance.placeFrameLock(input: input, suppressed: [])
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.text.contains("river"))
    }

    func testPlaceFrameLock_scatteredFixes_staysSilent() {
        let recs = [UUID(), UUID(), UUID()]
        var fixes: [UUID: DossierSenses.RouteFix] = [:]
        for (offset, rec) in recs.enumerated() {
            fixes[rec] = DossierSenses.RouteFix(
                coordinate: .init(latitude: 51.5 + Double(offset) * 0.5, longitude: -0.12),
                horizontalAccuracy: 10, gapSeconds: 5
            )
        }
        let thread = steadyThread("river", recordings: recs, walks: [UUID(), UUID(), UUID()])
        let input = DossierSenses.Input(
            currentWalkUUID: UUID(),
            walkStart: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            walkEnd: DateFactory.makeDate(2024, 6, 15, 10, 30, 0),
            totalAscent: 0, elevationSeries: [], photos: [], currentRecordings: [],
            historicalContexts: [], threads: [thread], backfillComplete: true,
            walkSnapshots: [], recordingTimestamps: [:], fixes: fixes, moon: nil
        )
        XCTAssertNil(DossierSensesInvariance.placeFrameLock(input: input, suppressed: []))
    }

    func testPlaceFrameLock_poorAccuracyFixesExcluded_staysSilent() {
        let recs = [UUID(), UUID(), UUID()]
        var fixes: [UUID: DossierSenses.RouteFix] = [:]
        for rec in recs {
            fixes[rec] = DossierSenses.RouteFix(
                coordinate: .init(latitude: 51.5, longitude: -0.12),
                horizontalAccuracy: 500, gapSeconds: 5
            )
        }
        let thread = steadyThread("river", recordings: recs, walks: [UUID(), UUID(), UUID()])
        let input = DossierSenses.Input(
            currentWalkUUID: UUID(),
            walkStart: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            walkEnd: DateFactory.makeDate(2024, 6, 15, 10, 30, 0),
            totalAscent: 0, elevationSeries: [], photos: [], currentRecordings: [],
            historicalContexts: [], threads: [thread], backfillComplete: true,
            walkSnapshots: [], recordingTimestamps: [:], fixes: fixes, moon: nil
        )
        XCTAssertNil(DossierSensesInvariance.placeFrameLock(input: input, suppressed: []))
    }
```

Superseded by Deviations 1-3 above — shipped tests as of the original commit additionally covered: full walk-coverage on a mixed fixture where one walk has no fix at all (`testPlaceFrameLock_oneWalkWithNoFixAtAll_staysSilent`), the anchor-arbitrariness boundary (`testPlaceFrameLock_pointsNearSharedAnchorButFarApart_staysSilent`), the exact rendered string (`testPlaceFrameLock_sameCluster_fires` asserts `line?.text ==`, not just `.contains`), below-minimum-walks, and suppressed-lemma — seven tests total in `UnitTests/DossierSensesInvariancePlaceFrameLockTests.swift` (Deviation 1). Under Deviation 4 (coverage relaxation), `testPlaceFrameLock_oneWalkWithNoFixAtAll_staysSilent` was renamed to `testPlaceFrameLock_oneWalkWithNoFixAtAll_rendersMeasuredCoverage` and now asserts the partial-coverage sentence via `XCTAssertEqual` instead of silence, and one more test was added — `testPlaceFrameLock_measuredWalksBelowMinimum_staysSilentDespiteManyAppearances` — pinning that a theme appearing on many walks with fewer than `minimumInvariantWalks` *measured* walks stays silent regardless of appearance count. Nine tests live in the file today.

- [ ] **Step 2: Run to verify it fails**

Expected: COMPILE FAILURE — no `placeFrameLock`.

- [ ] **Step 3: Implement (superseded by Deviation 4 — see "As shipped, current" below for the code actually in the tree)**

```swift
extension DossierSensesInvariance {

    /// The same theme spoken inside the same `DossierSenses.placeClusterRadius`
    /// cluster on every walk it appears in — an invariant tied to ground
    /// rather than to language. Reuses `DossierSenses.qualifies` so a
    /// poor-accuracy or stale-gap fix is excluded on the same hygiene terms
    /// as `placeResonance`: a 500m-accuracy fix would make any two points on
    /// earth look like the same place.
    ///
    /// The rendered line claims "all N walks it appears in" — a claim over
    /// the theme's ENTIRE appearance history, the same shape as
    /// `frameConstancy`'s "every walk". That claim is only true if every
    /// walk where the theme appears contributed at least one qualifying
    /// fix to check. A walk whose only recording(s) have no fix, or a fix
    /// too poor to qualify, is NOT silently dropped from the denominator —
    /// dropping it would let N-1 walks that happen to cluster outvote a
    /// walk the line never actually looked at, while still claiming to
    /// speak for it (the exact shape of `frameConstancy`'s FIX 1). Instead
    /// a single walk with no usable fix holds the whole signal silent —
    /// full coverage is the price of the word "all". Grouped by distinct
    /// WALK for the coverage check, mirroring `fusedThemes`,
    /// `unmovedReturn`, and `frameConstancy`: a walk contributes to
    /// coverage if ANY of its recordings has a qualifying fix, since the
    /// claim is about ground the walker stood on, and one usable fix is
    /// enough to place a walk on the map.
    ///
    /// Clustering is judged by SPREAD — the maximum pairwise distance
    /// across every qualifying coordinate — never by distance from an
    /// arbitrary anchor point such as the first coordinate encountered.
    /// Two points can each sit within `placeClusterRadius` of a shared
    /// anchor while sitting up to 2x that radius from each other; that is
    /// not "the same place" by any reading a walker would recognize, and
    /// an anchor-relative check would silently depend on appearance order
    /// (which fix happens to come first). Requiring every pair to sit
    /// within the radius of EACH OTHER is the stricter, order-independent
    /// reading, and mirrors the compactness `placeResonance.bestCluster`
    /// already measures via its own `spread`.
    static func placeFrameLock(
        input: DossierSenses.Input, suppressed: Set<String>
    ) -> DossierSenses.SenseLine? {
        for thread in input.threads.sorted(by: { $0.lemma < $1.lemma })
        where !suppressed.contains(thread.lemma) {
            let allWalks = Set(thread.appearances.map(\.walkUUID))
            guard allWalks.count >= minimumInvariantWalks else { continue }

            var coordinatesByWalk: [UUID: [DossierSenses.Coordinate]] = [:]
            for appearance in thread.appearances {
                guard let fix = input.fixes[appearance.recordingUUID],
                      DossierSenses.qualifies(fix) else { continue }
                coordinatesByWalk[appearance.walkUUID, default: []].append(fix.coordinate)
            }
            guard coordinatesByWalk.count == allWalks.count else { continue }

            let coordinates = coordinatesByWalk.values.flatMap { $0 }
            guard maxPairwiseSpread(coordinates) <= DossierSenses.placeClusterRadius else { continue }

            return DossierSenses.SenseLine(
                text: "'\(thread.displayTerm)' has been spoken in the same place "
                    + "on all \(allWalks.count) walks it appears in.",
                lemma: thread.lemma
            )
        }
        return nil
    }

    /// The greatest distance between any two coordinates in the set —
    /// order-independent, so which fix was recorded "first" cannot change
    /// the answer. Mirrors the `spread` computation in
    /// `DossierSenses.bestCluster`, minus the seed search: full coverage
    /// above already fixes the one candidate set this function is asked
    /// to judge, so there is nothing to search over.
    private static func maxPairwiseSpread(_ coordinates: [DossierSenses.Coordinate]) -> CLLocationDistance {
        guard coordinates.count >= 2 else { return 0 }
        var spread: CLLocationDistance = 0
        for i in 0..<(coordinates.count - 1) {
            for j in (i + 1)..<coordinates.count {
                spread = max(spread, DossierSenses.distance(coordinates[i], coordinates[j]))
            }
        }
        return spread
    }
}
```

Wire the case:

```swift
        case .placeFrameLock:
            return DossierSensesInvariance.placeFrameLock(input: input, suppressed: suppressed)
```

- [ ] **Step 4: Run to verify it passes**

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Threads/DossierSensesInvariance.swift \
  UnitTests/DossierSensesInvariancePlaceFrameLockTests.swift \
  Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(threads): place-frame lock — the same thought at the same bend

An invariant tied to ground rather than language: the walker says this in
this place, every time, and has never noticed. Reuses the placeResonance
hygiene gate so a 500m-accuracy fix cannot make two points look like one.

The \"on all N walks\" claim requires full walk coverage — a walk with no
qualifying fix stays out of the denominator instead of being silently
outvoted by walks that did cluster, the same shape as frameConstancy's
review fix (T5). Clustering is judged by max pairwise spread across every
qualifying fix, not distance from an arbitrary first coordinate, so two
points can't each hide within radius of a shared anchor while sitting
twice that radius apart from each other.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

See `.superpowers/sdd/task-6-report.md` for the TDD sequence, actual test
counts, and self-review.

**Coverage relaxation (post-ship, product decision, 2026-08-27) — the plan and code above are superseded; this is what actually ships.** Deviation 2's full-coverage requirement is deliberately relaxed. Reason: this app is used on rural pilgrimage routes where GPS quality varies, and requiring every appearance-walk to contribute a qualifying fix meant a single dead-zone walk could permanently silence an otherwise genuinely place-locked theme — too conservative. `minimumInvariantWalks` now gates on the MEASURED set (`coordinatesByWalk.count`), not the full appearance-walk set (`allWalks.count`). The max-pairwise-spread clustering check (Deviation 3) is completely unchanged — do not touch it, a reviewer verified by haversine that anchor-relative clustering lets points ~260m apart pass a 150m gate. As shipped, current:

```swift
static func placeFrameLock(
    input: DossierSenses.Input, suppressed: Set<String>
) -> DossierSenses.SenseLine? {
    for thread in input.threads.sorted(by: { $0.lemma < $1.lemma })
    where !suppressed.contains(thread.lemma) {
        let allWalks = Set(thread.appearances.map(\.walkUUID))

        var coordinatesByWalk: [UUID: [DossierSenses.Coordinate]] = [:]
        for appearance in thread.appearances {
            guard let fix = input.fixes[appearance.recordingUUID],
                  DossierSenses.qualifies(fix) else { continue }
            coordinatesByWalk[appearance.walkUUID, default: []].append(fix.coordinate)
        }
        // GATE ON THE MEASURED SET, not `allWalks.count` — a theme in 10
        // walks with only 1 usable fix must stay silent (clustering over
        // fewer than minimumInvariantWalks points is not evidence of
        // anything), but a theme in 5 walks with 3 usable fixes that
        // cluster tightly may now speak. Do not reinstate
        // `coordinatesByWalk.count == allWalks.count` as a silence gate —
        // that regression is the whole point of this comment.
        let measuredWalks = coordinatesByWalk.count
        guard measuredWalks >= minimumInvariantWalks else { continue }

        let coordinates = coordinatesByWalk.values.flatMap { $0 }
        guard maxPairwiseSpread(coordinates) <= DossierSenses.placeClusterRadius else { continue }

        // Two rendered variants, the same shape `fusedThemes` already sets
        // for identical-vs-nested walk-sets. Full coverage keeps the
        // original wording; partial coverage names both counts and never
        // implies anything about the unmeasured walks — we do not know
        // where they were, only that we cannot say.
        guard measuredWalks < allWalks.count else {
            return DossierSenses.SenseLine(
                text: "'\(thread.displayTerm)' has been spoken in the same place "
                    + "on all \(allWalks.count) walks it appears in.",
                lemma: thread.lemma
            )
        }

        return DossierSenses.SenseLine(
            text: "'\(thread.displayTerm)' has been spoken in the same place on every walk "
                + "where its location is known — \(measuredWalks) of the \(allWalks.count) it appears in.",
            lemma: thread.lemma
        )
    }
    return nil
}
```

Rendered wordings, both pinned by `XCTAssertEqual`:

- Full coverage: `'river' has been spoken in the same place on all 3 walks it appears in.`
- Partial coverage: `'river' has been spoken in the same place on every walk where its location is known — 3 of the 4 it appears in.`

Tests: `testPlaceFrameLock_sameCluster_fires` (full coverage, unchanged), `testPlaceFrameLock_oneWalkWithNoFixAtAll_rendersMeasuredCoverage` (partial coverage — the exact regression this task was warned about, now the desired behavior instead of silence), `testPlaceFrameLock_measuredWalksBelowMinimum_staysSilentDespiteManyAppearances` (a theme in 10 walks with only 2 measured stays silent — the floor is measured-count, not appearance-count). See `.superpowers/sdd/task-6-report.md` ("## Coverage relaxation") for the commit and full test run.

---

## Task 7: Signal 5 — unarrived intention, shipped dark

**Why:** The walker deliberately set out carrying a word, repeatedly, and the language never moved. This is Vervaeke's *"keep good track of your failures"* made literal — and the most confronting line the app could produce, which is why it ships behind a flag.

**Files:**
- Modify: `Pilgrim/Models/Threads/DossierSensesInvariance.swift`
- New: `UnitTests/DossierSensesInvarianceUnarrivedIntentionTests.swift` (deviation — see "As shipped" below)
- Modify: `Pilgrim.xcodeproj/project.pbxproj` (4 hand-added entries for the new test file — `UnitTests` uses explicit file references)

**Interfaces:**
- Produces: `DossierSensesInvariance.unarrivedIntention(input:suppressed:) -> DossierSenses.SenseLine?`
- Consumes: `DossierSenses.WalkSnapshotRow.intention`, `DossierSenses.intentionLemmas(in:)`, `ThreadStore.salienceDirection(of:)`

**As shipped — deviations from the brief below, all found by interrogating the brief's own draft before trusting it (per this task's instructions, and the four-consecutive-tasks warning that preceded it):**

1. **New test file, not an addition to `DossierSensesInvarianceTests.swift`.** The parent sat at 458 lines, close enough to the `file_length` gate of 500 that six tests (the brief's two plus four more) would have pushed it over. Same split pattern as `DossierSensesInvarianceFrameConstancyCoverageTests.swift` / `DossierSensesInvariancePlaceFrameLockTests.swift`: an `extension DossierSensesInvarianceTests` in its own file, reusing the parent's internal `steadyThread` fixture. Required 4 hand-added `project.pbxproj` entries (PBXBuildFile, PBXFileReference, group children, Sources build phase).
2. **`intentionWalks` lemma extraction uses `DossierSenses.intentionLemmas(in:)`, not raw `TranscriptNLP.contentLemmas(in:)`.** `intentionLemmas` is the established helper `intentionLineage` already uses for this exact transformation (intention text → lemma set) — it subtracts `SpokenStoplist.scaffoldLemmas` so a filler verb in an intention sentence never masquerades as a carried topic. Reusing it avoids a second, subtly different lemma-extraction path for the same kind of text.
3. **The rendered N is bound to the intersection of intention-text walks and the thread's own appearance walks — not the raw `intentionWalks[lemma].count` the brief's draft used.** `intentionWalks` comes from `WalkSnapshotRow.intention` text; `ThreadStore.salienceDirection` is computed over the thread's `appearances` — a different, independently-populated set. A walker can name a word as their intention on a walk where the topic is never actually discussed that day (no appearance), or a thread can appear on walks where the word was never the stated intention. The brief's draft would report `intentionWalks.count` while judging steadiness over the *entire* unfiltered thread — a claim the steadiness verdict never actually measured for the extra walks. Fixed: `boundWalks = Set(thread.appearances.filter { carried.contains($0.walkUUID) }.map(\.walkUUID))`, gated on `boundWalks.count >= minimumInvariantWalks`, and N in the rendered string is `boundWalks.count`.
4. **`ThreadStore.salienceDirection` is now computed over a `boundThread` built from only the intersected appearances, not the full unfiltered thread.** This gives "has not shifted *since*" an actual temporal anchor: the direction verdict now covers exactly the walks the intention was carried on, in date order (appearances arrive pre-sorted from `ThreadStore.build`; `filter` preserves that order). Without this, unrelated flat history elsewhere in the thread's life could cancel out a real shift that happened specifically during the intention-carrying walks, and the full-thread verdict would read "steady" by coincidence — see `testUnarrivedIntention_judgesDirectionOverBoundWalksOnly_notFullUnrelatedHistory`, which pins exactly this failure mode (thirds of the full 6-walk history read flat by cancellation; thirds of the 3 bound walks read as a sharp, unmistakable rise).
5. Because `minimumInvariantWalks == ThreadStore.directionFloor == 3`, gating on `boundWalks.count >= minimumInvariantWalks` before calling `salienceDirection` also guarantees the bound appearance count clears `directionFloor` by construction — the nil-safety the brief's draft relied on accidentally (checking the *full* thread's appearance count, which happened to be large enough) is now a structural guarantee on the *bound* set instead.

- [ ] **Step 1: Write the failing tests**

```swift
    func testUnarrivedIntention_engineFires_whenCalledDirectly() {
        let walks = [UUID(), UUID(), UUID()]
        let recs = [UUID(), UUID(), UUID()]
        let snapshots = walks.map {
            DossierSenses.WalkSnapshotRow(
                walkUUID: $0, startDate: DateFactory.makeDate(2024, 6, 1, 9, 0, 0),
                intention: "walk with patience", weatherCondition: nil
            )
        }
        let thread = WalkThread(
            lemma: "patience", displayTerm: "patience",
            appearances: zip(recs, walks).map { rec, walk in
                ThreadAppearance(
                    recordingUUID: rec, walkUUID: walk,
                    date: DateFactory.makeDate(2024, 6, 1, 9, 0, 0),
                    mentionCount: 3, salience: 0.5
                )
            }
        )
        let input = DossierSenses.Input(
            currentWalkUUID: walks[0],
            walkStart: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            walkEnd: DateFactory.makeDate(2024, 6, 15, 10, 30, 0),
            totalAscent: 0, elevationSeries: [], photos: [], currentRecordings: [],
            historicalContexts: [], threads: [thread], backfillComplete: true,
            walkSnapshots: snapshots, recordingTimestamps: [:], fixes: [:], moon: nil
        )
        let line = DossierSensesInvariance.unarrivedIntention(input: input, suppressed: [])
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.text.contains("patience"))
    }

    func testUnarrivedIntention_isSuppressedFromEngineOutputByTheFlag() {
        let walks = [UUID(), UUID(), UUID()]
        let recs = [UUID(), UUID(), UUID()]
        let snapshots = walks.map {
            DossierSenses.WalkSnapshotRow(
                walkUUID: $0, startDate: DateFactory.makeDate(2024, 6, 1, 9, 0, 0),
                intention: "walk with patience", weatherCondition: nil
            )
        }
        let thread = WalkThread(
            lemma: "patience", displayTerm: "patience",
            appearances: zip(recs, walks).map { rec, walk in
                ThreadAppearance(
                    recordingUUID: rec, walkUUID: walk,
                    date: DateFactory.makeDate(2024, 6, 1, 9, 0, 0),
                    mentionCount: 3, salience: 0.5
                )
            }
        )
        let input = DossierSenses.Input(
            currentWalkUUID: walks[0],
            walkStart: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            walkEnd: DateFactory.makeDate(2024, 6, 15, 10, 30, 0),
            totalAscent: 0, elevationSeries: [], photos: [], currentRecordings: [],
            historicalContexts: [], threads: [thread], backfillComplete: true,
            walkSnapshots: snapshots, recordingTimestamps: [:], fixes: [:], moon: nil
        )
        XCTAssertNil(DossierSenses.evaluateInvariant(.unarrivedIntention, input: input, suppressed: []))
        XCTAssertTrue(DossierSenses.invarianceLines(input: input).isEmpty)
    }
```

- [ ] **Step 2: Run to verify it fails**

Expected: COMPILE FAILURE — no `unarrivedIntention`.

- [x] **Step 3: Implement (as shipped — bound to the intersection, see deviations above)**

```swift
extension DossierSensesInvariance {

    /// The walker deliberately set out carrying a word, on at least
    /// `minimumInvariantWalks` walks, and that word's thread is STILL
    /// steady across those same walks. They tried, on purpose, and nothing
    /// moved.
    ///
    /// SHIPS DARK behind `pendingFieldGate`. This is the most confronting
    /// line the app can produce; the engine and its tests exist so the
    /// judgement can be made on real history, not on a guess.
    ///
    /// Both the rendered N and the direction verdict are bound to the same
    /// evidence: walks where the intention was set on this lemma AND the
    /// thread has an appearance that walk — see deviations 3-5 above for
    /// why the raw `intentionWalks[lemma].count` and the full unfiltered
    /// thread were each, independently, an overclaim.
    static func unarrivedIntention(
        input: DossierSenses.Input, suppressed: Set<String>
    ) -> DossierSenses.SenseLine? {
        var intentionWalks: [String: Set<UUID>] = [:]
        for snapshot in input.walkSnapshots {
            guard let intention = snapshot.intention, !intention.isEmpty else { continue }
            for lemma in DossierSenses.intentionLemmas(in: intention) {
                intentionWalks[lemma, default: []].insert(snapshot.walkUUID)
            }
        }

        for thread in input.threads.sorted(by: { $0.lemma < $1.lemma })
        where !suppressed.contains(thread.lemma) {
            guard let carried = intentionWalks[thread.lemma] else { continue }

            let boundAppearances = thread.appearances.filter { carried.contains($0.walkUUID) }
            let boundWalks = Set(boundAppearances.map(\.walkUUID))
            guard boundWalks.count >= minimumInvariantWalks else { continue }

            let boundThread = WalkThread(
                lemma: thread.lemma, displayTerm: thread.displayTerm, appearances: boundAppearances
            )
            guard ThreadStore.salienceDirection(of: boundThread) == .steady else { continue }

            return DossierSenses.SenseLine(
                text: "'\(thread.displayTerm)' was set as an intention on \(boundWalks.count) walks; "
                    + "it has not shifted since.",
                lemma: thread.lemma
            )
        }
        return nil
    }
}
```

Wire the case **with the flag guard**:

```swift
        case .unarrivedIntention:
            guard !DossierSensesInvariance.pendingFieldGate else { return nil }
            return DossierSensesInvariance.unarrivedIntention(input: input, suppressed: suppressed)
```

- [x] **Step 4: Run to verify it passes**

Verified: `UnitTests/DossierSensesInvarianceTests` suite (parent class, includes the split file's tests) — 39/39 passed, including both brief-specified tests plus 4 more closing the overclaim holes above. Full `UnitTests` target: 1458 tests, 0 failures (baseline 1452 + 6 new).

- [x] **Step 5: Commit**

```bash
git add Pilgrim/Models/Threads/DossierSensesInvariance.swift \
        UnitTests/DossierSensesInvarianceUnarrivedIntentionTests.swift \
        Pilgrim.xcodeproj/project.pbxproj \
        docs/superpowers/plans/2026-08-27-oblique-voice.md
git commit -m "feat(threads): the unarrived intention, shipped dark

The walker set out carrying a word, on purpose, three times or more, and
the language never moved. Keeping good track of your failures, made
literal - and the hardest thing the app could say to someone on a bad day.

Engine and tests ship so the call can be made on real history rather than
on a guess. The flag stays true until the field gate says otherwise.

N and the steadiness verdict are bound to the same walks (intention text
intersected with thread appearances, judged in date order) rather than two
different, unordered populations - the same overclaim shape this plan's
own brief warned about, caught before it shipped.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Build the `Unchanged:` block and carry it on `ActivityContext`

**Why:** The engine produces lines; something must render them into a block, build it **once**, and hand it to the assembler.

**Files:**
- Modify: `Pilgrim/Models/Prompt/ActivityContext.swift` (add `var unchangedBlock: String?` and the `make` parameter)
- Modify: `Pilgrim/Models/Threads/ThreadsDossierBuilder.swift` (build and assign)
- Modify: `UnitTests/ThreadsDossierSensesTests.swift`
- Modify: `Pilgrim/Scenes/Prompts/PromptListView.swift` — not anticipated by the draft below (see Deviation 4)
- New: `Pilgrim/Models/Threads/ThreadsDossierFieldReport.swift` — file-length split, not new behavior (see Deviation 5)

**Interfaces:**
- Produces: `ActivityContext.unchangedBlock: String?` — the fully rendered block including its `**Unchanged:**` heading, or `nil` when no invariant fired.

**Adjudicated deviations from the draft below** (shipped code differs from the original Step 3 draft in five ways; each is intentional and must not be "simplified" back to the draft):

1. **`build` keeps its old signature; the dual computation lives in a new `buildResult`.** The draft's Step 3 snippet reads as if `build` itself grew a second output (`unchangedBlock = ThreadsDossierBuilder.renderUnchangedBlock(invariance)` inside its body), but `build(...) -> String?` has ~12 pre-existing call sites across `ThreadsDossierTests.swift`, `ThreadsDossierModalLeanTests.swift`, and `ThreadsDossierSensesTests.swift` that treat the return value as a bare `String?` (`XCTAssertNil(ThreadsDossierBuilder.build(...))`, `let dossier = ThreadsDossierBuilder.build(...)`). Changing `build`'s return type would have broken all of them for a task whose Files list names only one test file. Shipped code keeps `build` as a 3-line wrapper (unchanged signature and behavior, zero call sites touched) and moves the real logic into a new `static func buildResult(...) -> (dossier: String?, unchangedBlock: String?)`, which `PromptListView` calls instead.
2. **`appendSensesBlock` changes its return type, not its parameter list.** The file's own doc comment on `SensesAssemblyState` records that it exists "to keep both it and `appendSensesBlock` under the function-parameter-count lint gate" — `appendSensesBlock` already sits at 5 non-default parameters, the default `function_parameter_count` warning threshold. Adding a 6th (`unchangedBlock: inout String?`, mirroring `dossier: inout String?`) would have tripped that gate. Shipped code instead changes the return type from `Int?` (moon state alone) to `(moonState: Int?, unchangedBlock: String?)` — zero new parameters, same `input` computed once inside the function body, per the invariance call site.
3. **The memo now carries `unchangedBlock` too, not just the dossier.** `cachedDossier(key:) -> String??` (renamed `cachedResult`) returns early on a cache hit, before `appendSensesBlock` (and therefore the invariance computation) ever runs. Without widening `private static var memo` to `(key: MemoKey, dossier: String?, unchangedBlock: String?)`, a same-session reopen of the same walk's prompt screen (no writes in between) would cache-hit the dossier but silently return `nil` for `unchangedBlock` even when invariants exist — an under-claim bug, not just a missed optimization. Fixed by threading `unchangedBlock` through the memo alongside `dossier`.
4. **`PromptListView.swift` needed a call-site change the Files list omitted.** `context.threadsDossier` is not assigned inside `ThreadsDossierBuilder` at all — it's assigned by the one production caller, `PromptListView.generatePrompts()`, at `context.threadsDossier = walkUUID.flatMap { ThreadsDossierBuilder.build(...) }`. "Assign it onto the `ActivityContext` at the same site the builder already assigns `threadsDossier`" is that call site. It now reads `ThreadsDossierBuilder.buildResult(...)` once and assigns both `context.threadsDossier` and `context.unchangedBlock` from the same tuple — never two builds, never a second `DossierSenses.Input`.
5. **`ThreadsDossierBuilder.swift` crossed the file_length gate (500); the pre-existing DEBUG field-report harness moved out.** The dual-return plumbing (`buildResult`, widened memo, widened `appendSensesBlock`) pushed the file from 482 to 519 lines. Comment-trimming alone wasn't enough for a comfortable margin, so the already-self-contained `#if DEBUG ... enum DossierSensesFieldReport ... #endif` block (~130 lines, calling only non-private `ThreadsDossierBuilder` members — `gatherSensesBundle`, `makeSensesInput`, `SensesAssemblyState`) moved verbatim to a new file, `Pilgrim/Models/Threads/ThreadsDossierFieldReport.swift`. This is a pure move, no behavior change. It required 4 hand-added `project.pbxproj` entries (`PBXBuildFile`, `PBXFileReference`, the `Threads` group listing, the `Pilgrim` target's `PBXSourcesBuildPhase` listing) — the main `Pilgrim` target uses explicit file references for this directory, not a `PBXFileSystemSynchronizedRootGroup` (only `PilgrimWidget` and `ScreenshotTests` are synchronized roots in this project).

- [ ] **Step 1: Write the failing test**

Add to `UnitTests/ThreadsDossierSensesTests.swift`:

```swift
func testUnchangedBlock_rendersHeadingAndLines() {
    let block = ThreadsDossierBuilder.renderUnchangedBlock(
        ["'father' and 'money' have appeared in 3 of 3 walks together, never apart.",
         "'work' has returned across 4 walks; it sounds the same each time."]
    )
    XCTAssertEqual(
        block,
        """
        **Unchanged:**
        'father' and 'money' have appeared in 3 of 3 walks together, never apart.
        'work' has returned across 4 walks; it sounds the same each time.
        """
    )
}

func testUnchangedBlock_emptyLines_isNil() {
    XCTAssertNil(ThreadsDossierBuilder.renderUnchangedBlock([]))
}

func testActivityContext_carriesUnchangedBlock() {
    let context = ActivityContext.make(
        startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
        unchangedBlock: "**Unchanged:**\nline"
    )
    XCTAssertEqual(context.unchangedBlock, "**Unchanged:**\nline")
}
```

- [ ] **Step 2: Run to verify it fails**

Expected: COMPILE FAILURE — no `renderUnchangedBlock`, no `unchangedBlock`.

- [ ] **Step 3: Implement**

In `Pilgrim/Models/Prompt/ActivityContext.swift`, add after `var threadsDossier: String?`:

```swift
    /// The `Unchanged:` block, built once alongside the dossier and emitted
    /// only for voices whose context policy requests it. Built once because
    /// `PromptGenerator.generateAll` fans ONE context across every style —
    /// building per voice would undo PR #65's single-pass work.
    var unchangedBlock: String?
```

Add `unchangedBlock: String? = nil` to the `make` parameter list (after `threadsDossier`) and `unchangedBlock: unchangedBlock` to the `ActivityContext(...)` body.

In `ThreadsDossierBuilder`, add:

```swift
    /// Renders invariance lines into the block the assembler emits. Nil for
    /// an empty list, so `unchangedBlock` is absent rather than an empty
    /// heading — the same shape `ThreadsDossierFormatter.dossier` uses.
    static func renderUnchangedBlock(_ lines: [String]) -> String? {
        guard !lines.isEmpty else { return nil }
        return "**Unchanged:**\n" + lines.joined(separator: "\n")
    }
```

Then, at the same point the builder appends the `Noticed:` block (around line 253), also compute and assign the invariance block:

```swift
        let invariance = DossierSenses.invarianceLines(input: input)
        unchangedBlock = ThreadsDossierBuilder.renderUnchangedBlock(invariance)
```

Assign it onto the `ActivityContext` at the same site the builder already assigns `threadsDossier`.

- [ ] **Step 4: Run to verify it passes**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: all PASS, full suite green.

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Prompt/ActivityContext.swift Pilgrim/Models/Threads/ThreadsDossierBuilder.swift \
  Pilgrim/Models/Threads/ThreadsDossierFieldReport.swift Pilgrim/Scenes/Prompts/PromptListView.swift \
  Pilgrim.xcodeproj/project.pbxproj UnitTests/
git commit -m "feat(threads): build the Unchanged block once, carry it on the context

generateAll fans one ActivityContext across every style, so the block is
built alongside the dossier and merely emitted per voice later. Building it
per voice would quietly undo the single-pass work from PR #65.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: The context policy, and the marker-in-a-journal-entry defect

**Why:** `JournalingVoice` currently receives absolutist percentages and sentiment scores, and they land in an entry the walker rereads years later. `CreativeVoice` is asked for a poem while holding a sentiment score. This is live, and fixing it needs the same mechanism Oblique needs for hoisting.

**Files:**
- Create: `Pilgrim/Models/Prompt/PromptContextPolicy.swift`
- Modify: `Pilgrim/Models/Prompt/PromptVoice.swift`
- Modify: `Pilgrim/Models/Prompt/WalkPromptVoices.swift`
- Modify: `Pilgrim/Models/Prompt/PromptAssembler.swift`
- Modify: `Pilgrim/Models/Prompt/ActivityContext.swift` — not listed by the draft; needed the `threadsDossierWithoutMarkers` field alongside `threadsDossier`, the same way Task 8 added `unchangedBlock`
- Modify: `Pilgrim/Models/Threads/ThreadsDossierFormatter.swift`
- Modify: `Pilgrim/Models/Threads/ThreadsDossierBuilder.swift` — not listed by the draft; builds the second dossier variant and widens `buildResult`'s tuple (see Deviations 3–4)
- Modify: `Pilgrim/Scenes/Prompts/PromptListView.swift` — not listed by the draft; the one production call site for `buildResult` needed to assign the new `threadsDossierWithoutMarkers` field, the same gap Task 8 hit (its Deviation 4)
- Create: `UnitTests/PromptContextPolicyTests.swift`
- (Review fixes, post-ship — see below) Modify: `Pilgrim/Models/Prompt/ActivityContext.swift`, `Pilgrim/Models/Threads/ThreadsDossierBuilder.swift`, `Pilgrim/Models/Prompt/PromptAssembler.swift`, `Pilgrim/Scenes/Prompts/PromptListView.swift`, `UnitTests/PromptContextPolicyTests.swift` again; Create: `UnitTests/ThreadsDossierSensesMarkerColoringLeakTests.swift` (plus its 4 `project.pbxproj` entries)

**Interfaces:**
- Produces:
  - `struct PromptContextPolicy { let includesMarkerLines: Bool; let includesThreadAnalysis: Bool; let hoistsUnchangedBlock: Bool; static let full: PromptContextPolicy }`
  - `PromptVoice.contextPolicy: PromptContextPolicy` with a `.full` default in the protocol extension
  - `ThreadsDossierFormatter.dossier(..., includeMarkerLines: Bool, includeThreadAnalysis: Bool)`

**Adjudicated deviations from the draft below** (shipped code differs from the original Step 3 draft in four ways; each is intentional and must not be "simplified" back to the draft):

1. **The assembler's dossier selection consults BOTH policy axes, not `includesMarkerLines` alone.** The draft's Step 3 sketch — `voice.contextPolicy.includesMarkerLines ? context.threadsDossier : context.threadsDossierWithoutMarkers` — branches only on markers. Applied literally, Creative and Gratitude (whose row suppresses thread analysis too) would receive `threadsDossierWithoutMarkers`, which is markers-off but thread-analysis-**on** (it's the Journaling variant) — leaking the "Threads across recent walks" / "Quiet this walk" sections their policy asks to suppress. Shipped code adds `PromptAssembler.selectedDossier(context:policy:)`: it returns `nil` outright when `includesThreadAnalysis` is false, and only then branches on `includesMarkerLines` for voices that do want thread content. No third pre-rendered string was needed — Creative/Gratitude's "nothing" is `nil`, not a new field. Pinned by `testAssembler_creative_omitsThreadAnalysisEntirely` and `testAssembler_gratitude_omitsThreadAnalysisEntirely`.
2. **`responseContract` receives the voice's *selected* dossier, not `context.threadsDossier` unconditionally.** Read literally, the draft leaves the `responseContract(...)` call passing the raw full dossier for every voice; Journaling would then carry the interpretive key describing absolutist-word share and modal lean — referents it was never shown, which the task brief calls out as a worse defect than the one being fixed. Shipped code computes the selected dossier once in `assemble` and threads the same value into both `walkRecord` and `responseContract`. Pinned by `testAssembler_journaling_contractOmitsInterpretiveKey` and `testAssembler_creativeAndGratitude_contractCarriesNoThreadsLanguage`.
3. **The `**Noticed:**` (senses) block is appended identically to both dossier variants**, not scoped by either policy axis. `DossierSenses` output (weather, moon, elevation, pace) is orthogonal to the marker/thread-analysis table this task scopes — Task 9 deliberately defers the full six-voice matrix. The draft's one-line instruction ("call `ThreadsDossierFormatter.dossier` a second time... assign to `threadsDossierWithoutMarkers`") never touches `appendSensesBlock`, which would have left Journaling's reduced variant silently missing sensory content the draft never intended to remove. Shipped code widens `appendSensesBlock` to take both dossier strings (`inout (dossier: String?, withoutMarkers: String?)`, keeping it at 5 parameters, the `function_parameter_count` warning threshold) and appends the same rendered `**Noticed:**` text to whichever of the two is non-nil.
4. **`ThreadsDossierBuilder.buildResult`'s tuple widens to three fields, and a new `DossierRenderInputs`/`renderDossierPair` pair factors the now-duplicated formatter call.** Two calls to `ThreadsDossierFormatter.dossier` (full and `includeMarkerLines: false`) inline in `buildResult` pushed its body to 62 lines against the `function_body_length` warning threshold of 60. `renderDossierPair` states the shared-input call once; `DossierRenderInputs` bundles its six inputs to stay under the 5-parameter gate — the same bundling pattern `SensesAssemblyState` already uses. Pure extraction, no behavior change.

Note also: the response-contract snippets throughout this section already use the current `responseContract(voice:hasSpeech:threadsDossier: String?)` signature (no `hasThreadsDossier: Bool`) — the signature drift flagged going into this task turned out to already match between this plan doc and the shipped source; the substantive gap was the selection logic (deviations 1–2 above), not the parameter list.

**Review fixes (post-ship).** Two findings surfaced after the commit above shipped; both are now live and are documented here rather than left as a silent second commit, per house rule (the field-gate precedent this whole plan already follows for thresholds).

5. **Deviation 3 above was wrong: the `**Noticed:**` block is NOT uniformly marker-free of its own accord.** `DossierSenses.Sense.markerColoring` is itself a sense in that block — it renders "Absolutist words cluster around 'X' — Nx the density of the rest of the walk's speech," which is marker-derived commentary on the current walk's speech, exactly the category `includeMarkerLines: false` exists to suppress. Appending the SAME `output.lines` to both dossier variants (as deviation 3 shipped it) meant `markerColoring` reached `threadsDossierWithoutMarkers` — and therefore Journaling — by a side door, reopening the defect this task exists to close. `DossierSensesMarkerPhotoTests.swift`'s `testMarkerColoring_viaSense_usesActiveThreadOrderAndSuppression` proved the sense was reachable; nothing at the builder level proved it was blocked from the marker-free variant, which is how this shipped unnoticed. Fixed: `ThreadsDossierBuilder.appendSensesBlock` now renders TWO `DossierSenses.lines` outputs — the default (`output`, all eight senses, feeds `dossier`) and a marker-free one (`markerFree`, via the `evaluate` test seam: `{ sense, input, used in sense == .markerColoring ? nil : DossierSenses.evaluate(sense, input: input, suppressed: used) }`, feeds `withoutMarkers` and the new senses-only variant below). The two computations independently run the lemma-dedup/three-line-cap loop, so a lower-priority sense may legitimately take the slot `markerColoring` would have filled in the marker-free computation — the two variants can differ in WHICH senses appear, not just whether markers appear. That is intended, not a bug: it is the same "say less rather than reaching" posture the rest of the dossier already takes. Pinned by `testMarkerColoring_firesInFullDossier_absentFromMarkerFreeVariant` and `testMarkerColoring_neverReachesSensesOnlyVariant` (`UnitTests/ThreadsDossierSensesMarkerColoringLeakTests.swift`).
6. **Deviation 1's "no third pre-rendered string was needed" was too strong.** `PromptAssembler.selectedDossier` returning `nil` for Creative/Gratitude was correct for the marker/thread-analysis TABLE this task scopes, but it also discarded the `**Noticed:**` block's sensory content (place resonance, moon, weather, climb, photo adjacency, speech shape) — none of which is marker or thread analysis, and Creative in particular loses the weather, the moon, and the place right when it is asked to write a poem from them. Fixed: a third variant, `ActivityContext.threadsDossierSensesOnly` — just `**Noticed:**` (built from the SAME marker-free `markerFree.lines` as fix 5, so it can never carry a `markerColoring` line either), with no heading, no marker section, no thread section. `ThreadsDossierBuilder.buildResult`'s return tuple widens from three fields to four (`dossier`, `unchangedBlock`, `dossierWithoutMarkers`, `dossierSensesOnly`); the memo tuple and `cachedResult` widen the same way — the memo carries every variant, so a cache hit cannot silently drop the new one (the exact bug Task 8's review caught). `PromptAssembler.selectedDossier` now returns `context.threadsDossierSensesOnly` instead of `nil` when `!policy.includesThreadAnalysis`. The response contract stays untouched by this: `assemble` computes a separate `threadsDossierForContract` (`policy.includesThreadAnalysis ? dossier : nil`) so Creative/Gratitude's contract still sees `nil` and carries neither the clinical-language guard sentence nor an interpretive key — both are about reading marker/thread numbers, and a voice shown only sensory content was never shown those numbers. Pinned by `PromptContextPolicyTests.testAssembler_creative_receivesNoticedBlock`, `testAssembler_creative_omitsMarkerAndSentimentFigures`, `testAssembler_creative_omitsThreadSection`, `testAssembler_creative_omitsMarkerColoringLine`, `testAssembler_gratitude_receivesNoticedBlockWithoutThreadAnalysis`, and `testAssembler_creativeAndGratitude_contractStillCarriesNoThreadsLanguage_withSensesOnlyDossier`.

Net effect on the six voices: Reflective/Contemplative/Philosophical/Custom get the full dossier unchanged. Journaling gets the marker-free, thread-analysis-on variant, now genuinely marker-free (fix 5). Creative and Gratitude go from "nothing" to the senses-only variant (fix 6) — sensory content only, no numbers, no thread section, and their response contract is unaffected (still carries no thread-analysis language at all).

- [ ] **Step 1: Write the failing tests**

Create `UnitTests/PromptContextPolicyTests.swift`:

```swift
import XCTest
@testable import Pilgrim

final class PromptContextPolicyTests: XCTestCase {

    func testDefaultPolicy_isFull() {
        XCTAssertTrue(ReflectiveVoice().contextPolicy.includesMarkerLines)
        XCTAssertTrue(ContemplativeVoice().contextPolicy.includesMarkerLines)
        XCTAssertTrue(PhilosophicalVoice().contextPolicy.includesMarkerLines)
    }

    func testJournalingVoice_excludesMarkerLines() {
        XCTAssertFalse(JournalingVoice().contextPolicy.includesMarkerLines)
    }

    func testCreativeVoice_excludesMarkersAndThreadAnalysis() {
        XCTAssertFalse(CreativeVoice().contextPolicy.includesMarkerLines)
        XCTAssertFalse(CreativeVoice().contextPolicy.includesThreadAnalysis)
    }

    func testGratitudeVoice_excludesMarkersAndThreadAnalysis() {
        XCTAssertFalse(GratitudeVoice().contextPolicy.includesMarkerLines)
        XCTAssertFalse(GratitudeVoice().contextPolicy.includesThreadAnalysis)
    }

    func testCustomStyle_getsFullPolicyViaProtocolDefault() {
        let custom = CustomPromptStyle(
            id: UUID(), name: "Test", promptText: "Reflect on this walk."
        )
        XCTAssertTrue(custom.contextPolicy.includesMarkerLines)
    }
}
```

> If `CustomPromptStyle`'s initialiser differs, construct it however `CustomPromptStyleStoreTests` does — the assertion is what matters, not the fixture shape.

- [ ] **Step 2: Run to verify it fails**

Expected: COMPILE FAILURE — no `contextPolicy`.

- [ ] **Step 3: Implement**

Create `Pilgrim/Models/Prompt/PromptContextPolicy.swift`:

```swift
import Foundation

/// Which already-computed context blocks a voice receives. A FILTER at
/// assembly time, never a per-voice build — `PromptGenerator.generateAll`
/// fans one `ActivityContext` across every style, and computing per voice
/// would undo PR #65's single-pass work.
///
/// Each voice is a frame, and the right frame is the one that makes the
/// search space small enough to work in. A poem prompt holding a sentiment
/// score is a covering-problem framing of a parity problem.
struct PromptContextPolicy {
    let includesMarkerLines: Bool
    let includesThreadAnalysis: Bool
    let hoistsUnchangedBlock: Bool

    static let full = PromptContextPolicy(
        includesMarkerLines: true,
        includesThreadAnalysis: true,
        hoistsUnchangedBlock: false
    )
}
```

In `Pilgrim/Models/Prompt/PromptVoice.swift`, add the protocol member and its default:

```swift
protocol PromptVoice {
    func preamble(hasSpeech: Bool) -> String
    func instruction(hasSpeech: Bool) -> String
    func responseConstraints(hasSpeech: Bool) -> [String]
    /// Which context blocks this voice receives. Defaults to `.full`, so
    /// `CustomPromptStyle` and any future voice are unaffected until they
    /// opt out deliberately.
    var contextPolicy: PromptContextPolicy { get }
}

extension PromptVoice {
    func responseConstraints(hasSpeech: Bool) -> [String] { [] }
    var contextPolicy: PromptContextPolicy { .full }
}
```

In `WalkPromptVoices.swift`, add to the three voices that opt out:

```swift
// inside CreativeVoice
    var contextPolicy: PromptContextPolicy {
        PromptContextPolicy(
            includesMarkerLines: false, includesThreadAnalysis: false, hoistsUnchangedBlock: false
        )
    }

// inside GratitudeVoice — identical body
    var contextPolicy: PromptContextPolicy {
        PromptContextPolicy(
            includesMarkerLines: false, includesThreadAnalysis: false, hoistsUnchangedBlock: false
        )
    }

// inside JournalingVoice — markers out, thread analysis kept
    var contextPolicy: PromptContextPolicy {
        PromptContextPolicy(
            includesMarkerLines: false, includesThreadAnalysis: true, hoistsUnchangedBlock: false
        )
    }
```

In `ThreadsDossierFormatter.dossier`, add two parameters defaulting to `true` so existing callers are unchanged, and guard the two sections:

```swift
    static func dossier(
        currentRecordings: [(context: TranscriptContext, wordsPerMinute: Double?)],
        allContexts: [TranscriptContext],
        threads: [WalkThread],
        currentWalkUUID: UUID,
        backfillComplete: Bool,
        walkIndex: [UUID: UUID] = [:],
        includeMarkerLines: Bool = true,
        includeThreadAnalysis: Bool = true
    ) -> String? {
```

Wrap the per-recording marker loop and the modal-lean append in `if includeMarkerLines { ... }`, and the `activeThreads` / `Quiet this walk` sections in `if includeThreadAnalysis { ... }`. If both are false and nothing was appended beyond the heading, return `nil` rather than a bare heading.

In `PromptAssembler.assemble`, apply the policy. Where `contextDossier` currently appends unconditionally, and where `walkRecord` appends `context.threadsDossier`, consult `voice.contextPolicy`. Add the hoist immediately after the `**Context:**` line:

```swift
        if voice.contextPolicy.hoistsUnchangedBlock, let unchanged = context.unchangedBlock {
            sections += "\n\n\(unchanged)"
        }
```

`threadsDossier` arrives **pre-rendered**, so the assembler cannot strip marker lines from it after the fact without string surgery. Two options were considered:

- Carry the raw inputs on `ActivityContext` and re-render per voice — **rejected**: it leaks `TranscriptContext` and `WalkThread` into the prompt layer, and re-rendering per voice reintroduces per-voice work.
- Render both variants once in the builder and carry both strings — **chosen**: one extra format pass over data already in hand, still one build for all seven styles.

In `ActivityContext.swift`, add alongside `threadsDossier`:

```swift
    /// Second pre-rendered variant, built in the same pass. Voices whose
    /// policy excludes marker lines read this one. Both are built once —
    /// `generateAll` fans one context across every style.
    var threadsDossierWithoutMarkers: String?
```

Add `threadsDossierWithoutMarkers: String? = nil` to the `make` parameter list and `threadsDossierWithoutMarkers: threadsDossierWithoutMarkers` to the `ActivityContext(...)` body, exactly as Task 8 did for `unchangedBlock`.

In `ThreadsDossierBuilder`, at the site that already assigns `threadsDossier`, call `ThreadsDossierFormatter.dossier` a second time with `includeMarkerLines: false` and assign the result to `threadsDossierWithoutMarkers`.

The assembler then selects:

```swift
        let dossier = voice.contextPolicy.includesMarkerLines
            ? context.threadsDossier
            : context.threadsDossierWithoutMarkers
        if let dossier {
            sections += "\n\n\(dossier)"
        }
```

- [ ] **Step 4: Write the assembler integration tests**

Add to `UnitTests/PromptContextPolicyTests.swift`:

```swift
    private func contextWithDossiers() -> ActivityContext {
        .make(
            recordings: [RecordingContext(
                text: "the river was loud today", timestamp: DateFactory.makeDate(2024, 6, 15, 9, 5, 0),
                startCoordinate: nil, endCoordinate: nil, wordsPerMinute: 100,
                recordingUUID: UUID(), endTimestamp: nil
            )],
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            threadsDossier: "**Thought threads:**\nRecording 1: absolutist words 2.3%",
            threadsDossierWithoutMarkers: "**Thought threads:**\n'river' — 3 walks",
            unchangedBlock: "**Unchanged:**\n'river' has returned across 4 walks."
        )
    }

    func testAssembler_journaling_omitsMarkerPercentages() {
        let prompt = PromptAssembler.assemble(context: contextWithDossiers(), voice: JournalingVoice())
        XCTAssertFalse(prompt.contains("absolutist words 2.3%"))
    }

    func testAssembler_reflective_keepsMarkerPercentages() {
        let prompt = PromptAssembler.assemble(context: contextWithDossiers(), voice: ReflectiveVoice())
        XCTAssertTrue(prompt.contains("absolutist words 2.3%"))
    }

    func testAssembler_nonObliqueVoices_neverSeeUnchangedBlock() {
        for voice: PromptVoice in [
            ContemplativeVoice(), ReflectiveVoice(), CreativeVoice(),
            GratitudeVoice(), PhilosophicalVoice(), JournalingVoice()
        ] {
            let prompt = PromptAssembler.assemble(context: contextWithDossiers(), voice: voice)
            XCTAssertFalse(prompt.contains("**Unchanged:**"))
        }
    }
```

- [ ] **Step 5: Run to verify everything passes**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: all PASS, full suite green.

- [ ] **Step 6: Commit**

```bash
git add Pilgrim/Models/Prompt/ Pilgrim/Models/Threads/ThreadsDossierFormatter.swift Pilgrim/Models/Threads/ThreadsDossierBuilder.swift UnitTests/PromptContextPolicyTests.swift
git commit -m "fix(prompts): stop putting absolutist percentages in journal entries

Journaling has been receiving marker profiles and sentiment scores and
folding them into an entry the walker rereads years later. Creative was
asked for a poem while holding a sentiment score. Live defect, shipping
today.

Each voice is a frame, and the right frame is the one that makes the space
small enough to work in. The policy is a filter at assembly time over a
context still built once - never a per-voice build, which would undo PR #65.
Custom styles keep the full dossier through the protocol default.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: The Oblique voice

**Why:** Everything above produces the block. This is the voice that reads it.

**Files:**
- Modify: `Pilgrim/Models/Prompt/PromptStyle.swift`
- Modify: `Pilgrim/Models/Prompt/WalkPromptVoices.swift`
- Create: `UnitTests/ObliqueVoiceTests.swift`

**Interfaces:**
- Produces: `PromptStyle.oblique`, `struct ObliqueVoice: PromptVoice`

- [x] **Step 1: Write the failing tests**

Create `UnitTests/ObliqueVoiceTests.swift`:

```swift
import XCTest
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
}
```

- [x] **Step 2: Run to verify it fails**

Expected: COMPILE FAILURE — no `.oblique`, no `ObliqueVoice`. Confirmed: `Type 'PromptStyle' has no member 'oblique'` / `Cannot find 'ObliqueVoice' in scope` (3 + 5 occurrences).

- [x] **Step 3: Implement**

In `PromptStyle.swift`, add `case oblique` to the enum and a branch to each of `title`, `icon`, and `description`:

```swift
    case oblique
    // title:       case .oblique: return "Oblique"
    // icon:        case .oblique: return "circle.dotted"
    // description: case .oblique: return "What has not moved"
```

Add the voice mapping: `case .oblique: return ObliqueVoice()`.

In `WalkPromptVoices.swift`:

```swift
/// Reads what has NOT moved across the walker's history and names the frame
/// they have been looking through rather than at.
///
/// The governing constraint is Weber et al. 1981: subjects stuck on the
/// nine-dot problem were told "think outside the box" and it helped nobody.
/// A contentless instruction to reframe does not transfer. A specific,
/// structurally-grounded alternative reading does — which is why constraint
/// 3 bans the former and requires the latter.
struct ObliqueVoice: PromptVoice {

    var contextPolicy: PromptContextPolicy {
        PromptContextPolicy(
            includesMarkerLines: true, includesThreadAnalysis: true, hoistsUnchangedBlock: true
        )
    }

    func preamble(hasSpeech: Bool) -> String {
        "This walker keeps a record. Across many walks they have returned, without planning to, to the same few things. What follows includes what has not changed across those returns — patterns in their own language that they cannot see, because these are the terms they think in rather than the terms they think about."
    }

    func instruction(hasSpeech: Bool) -> String {
        "Work from the invariants named under Unchanged. Name what the walker has been treating as fixed — the assumption they have been looking through rather than at — and offer one specific alternative reading of that structure. Be concrete about the shape, not about what it means for their life."
    }

    func responseConstraints(hasSpeech: Bool) -> [String] {
        [
            "Build only on the invariants named under Unchanged — never assert a pattern that block does not show.",
            "Name one thing. An insight that can be carried is single, not a list.",
            "Offer a specific alternative reading of the structure; never a contentless instruction to reframe. Do not write \"perhaps consider\", \"try seeing\", \"from another perspective\", or \"outside the box\".",
            "End on the observation. Do not resolve it and do not prescribe an action — the walker does that part."
        ]
    }
}
```

Both `hasSpeech` branches return the same text: the availability gate in Task 11 means Oblique is never assembled without speech, and dead placeholder prose would be worse than an honest duplicate.

- [x] **Step 4: Run to verify it passes**

Expected: all PASS. Confirmed: 5/5 `ObliqueVoiceTests` green.

- [x] **Step 5: Run the full suite**

Any test asserting `PromptStyle.allCases.count == 6` must become `7`. Any test iterating all styles will now include Oblique — confirm those still pass rather than weakening them.

Shipped exactly as anticipated: `PromptGeneratorTests.testGenerateAll_returnsOnePerStyle` was the one test hardcoding `6` and was updated to `7` (the `styles.count` line already read `PromptStyle.allCases.count` dynamically, so it needed no change). No other switch/count in the codebase pattern-matches `PromptStyle` cases individually or hardcodes a style total. Full suite: 1489 tests, 0 failures (baseline 1484 + 5 new).

- [x] **Step 6: Commit**

```bash
git add Pilgrim/Models/Prompt/ UnitTests/ObliqueVoiceTests.swift
git commit -m "feat(prompts): Oblique — what has not moved

The voice that reads the Unchanged block. Its whole discipline is one
finding: Weber et al. told stuck subjects to think outside the box and it
helped nobody, because a contentless instruction to reframe does not
transfer. A specific, structurally-grounded alternative reading does.

So it may interpret and may not invent, names one thing rather than a list,
and stops on the observation. The walker does the resolving - a reframe
handed to you is not one you can act from.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: The picker gate — "Still listening"

**Why:** `ObliqueVoice.preamble` and `.instruction` reference the invariants named under `Unchanged:` **unconditionally** — they do not branch on `hasSpeech`. `unchangedBlock` is nil whenever fewer than `DossierSensesInvariance.minimumInvariantWalks` (3) qualifying walks exist for any signal, which can be true even on a speech-bearing walk with deep history. A gate built from `walksWithTranscripts >= 5 && currentWalkHasSpeech` (the draft below) does not track that — it would let the picker offer Oblique on a walk where `unchangedBlock` is still nil, handing the model an instruction to read a block that is not in the prompt. **Corrected during implementation:** the gate must be `context.unchangedBlock != nil` directly. That single condition subsumes thin history, a silent current walk, and a history-deep walk where nothing has held still yet — all three already leave `unchangedBlock` nil, so checking it is the only gate that can't lie. `minimumWalksForOblique` and the `walksWithTranscripts` parameter below are dead once the block-presence check is used, so they were dropped rather than kept unread. It shows in the list from day one, unselectable, so the walker learns it exists.

**Files:**
- Modify: `Pilgrim/Models/Prompt/PromptStyle.swift` (availability helper)
- Modify: `Pilgrim/Scenes/Prompts/PromptListView.swift`
- Modify: `UnitTests/ObliqueVoiceTests.swift`
- Modify: `Pilgrim/Models/Prompt/PromptContextPolicy.swift` (stale doc comment fix, carried from Task 10 review)

**Interfaces (as shipped):**
- Produces: `PromptStyle.isAvailable(unchangedBlockPresent:) -> Bool`, `PromptStyle.waitingCopy: String?`

- [ ] **Step 1: Write the failing tests**

```swift
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
        XCTAssertEqual(PromptStyle.oblique.waitingCopy, "Still listening. A few more walks with your voice.")
        XCTAssertNil(PromptStyle.reflective.waitingCopy)
    }

    func testPreambleAndInstruction_hasSpeechFalseMatchesHasSpeechTrue() {
        let voice = ObliqueVoice()
        XCTAssertEqual(voice.preamble(hasSpeech: false), voice.preamble(hasSpeech: true))
        XCTAssertEqual(voice.instruction(hasSpeech: false), voice.instruction(hasSpeech: true))
    }
```

The fourth test is the Task 10 review Minor: the symmetry between `ObliqueVoice`'s `hasSpeech: false` and `hasSpeech: true` text is deliberate (the gate means Oblique is never assembled without speech) but was unguarded before this task.

- [ ] **Step 2: Run to verify it fails**

Expected: COMPILE FAILURE — no `isAvailable`, no `waitingCopy`.

- [ ] **Step 3: Implement**

In `PromptStyle.swift`:

```swift
extension PromptStyle {

    /// Oblique is gated on whether the `Unchanged:` block actually exists
    /// for this walk, not on a walk-count threshold — `unchangedBlock` is
    /// already nil whenever the current walk is silent, history is thin,
    /// `UserPreferences.threadsAfterWalks` is off, or history is deep but
    /// nothing has held still yet. Checking the block directly is the only
    /// gate that can't tell `ObliqueVoice` to read a block that isn't in
    /// the prompt. Every other style is always available.
    func isAvailable(unchangedBlockPresent: Bool) -> Bool {
        guard self == .oblique else { return true }
        return unchangedBlockPresent
    }

    /// Shown dimmed in the picker while unavailable. True for every case
    /// that fails the gate above, so one string covers all of them without
    /// lying. It reads as the voice needing to hear more, not as a level to
    /// grind.
    var waitingCopy: String? {
        self == .oblique ? "Still listening. A few more walks with your voice." : nil
    }
}
```

No `minimumWalksForOblique` constant — nothing reads a walk count once the gate is the block's presence.

In `PromptListView.swift`, `PromptStyleRow` (line ~356) takes a `GeneratedPrompt` and renders `prompt.icon` / `prompt.title` / `prompt.subtitle`. Add a waiting state to it:

```swift
struct PromptStyleRow: View {
    let prompt: GeneratedPrompt
    var waitingCopy: String?

    private var isWaiting: Bool { waitingCopy != nil }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: prompt.icon)
                .font(.title2)
                .foregroundColor(.stone)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(prompt.title)
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
                Text(waitingCopy ?? prompt.subtitle)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                    .lineLimit(2)
            }

            Spacer()

            if !isWaiting {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.fog)
            }
        }
        .padding(.vertical, Constants.UI.Padding.small)
        .opacity(isWaiting ? 0.45 : 1)
    }
}
```

Keep `VStack(alignment: .leading)` — rows here vary in width and centring them misaligns the column.

In the `ForEach(prompts)` body, suppress the button when the style is waiting. The gate reads `activityContext?.unchangedBlock` — the same `@State var activityContext: ActivityContext?` the view already assigns in `generatePrompts()` right before `prompts`, so no new fetch or derivation is needed:

```swift
                ForEach(prompts) { prompt in
                    let waiting = prompt.style.flatMap { style in
                        style.isAvailable(unchangedBlockPresent: activityContext?.unchangedBlock != nil)
                            ? nil : style.waitingCopy
                    }
                    if let waiting {
                        PromptStyleRow(prompt: prompt, waitingCopy: waiting)
                            .listRowBackground(Color.parchment)
                    } else {
                        Button { selectedPrompt = prompt } label: {
                            PromptStyleRow(prompt: prompt)
                        }
                        .listRowBackground(Color.parchment)
                    }
                }
```

Custom prompts have `style == nil`, so `prompt.style.flatMap` is nil for them and they are never gated. No `walksWithTranscripts` derivation was added to `PromptGenerator.resolvedDerivations` — the block-presence check made it unnecessary.

Never use `.system()` fonts — `Constants.Typography.*` only.

Also update `PromptContextPolicy.hoistsUnchangedBlock`'s doc comment, which still said "Reserved for the Oblique voice (a later task)... False for every voice this task introduces" — stale now that Oblique ships and sets it true.

- [ ] **Step 4: Run to verify it passes**

Expected: all PASS.

- [ ] **Step 5: Check it on device**

Build and run. Confirm: with a fresh profile Oblique appears dimmed with the waiting copy; the row is not tappable; the copy uses the project's fonts and does not crowd on a small screen at large Dynamic Type.

- [ ] **Step 6: Commit**

```bash
git add Pilgrim/Models/Prompt/PromptStyle.swift Pilgrim/Scenes/Prompts/PromptListView.swift Pilgrim/Models/Prompt/PromptContextPolicy.swift UnitTests/ObliqueVoiceTests.swift
git commit -m "feat(prompts): the Oblique gate — still listening

The block, not a walk count: unchangedBlock is nil whenever the current
walk is silent, history is thin, or history is deep but nothing has held
still yet. A gate built from a walk-count threshold plus speech could still
pass while the block stayed nil, handing ObliqueVoice's unconditional
'invariants named under Unchanged' reference to a prompt that never
printed one — checking the block directly is the only gate that can't do
that.

One string covers every failing case without lying, and it frames the
voice as needing to hear more rather than as a level to grind. Every other
gate in this app is silent; a style that vanished from a picker would be
stranger than one that says what it is waiting for.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 12: DEBUG harness and the field gate

**Why:** Firing rate measures only the upside. The no-free-lunch theorem guarantees a matching downside that firing rate is structurally blind to — `questionDensity` escaped only because it was loud.

**Files:**
- ~~Modify: `Pilgrim/Models/Threads/ThreadsDossierBuilder.swift` (the `#if DEBUG` harness block)~~ — **DEVIATION (implemented 2026-08-27):** that `#if DEBUG` block no longer lives in `ThreadsDossierBuilder.swift`; Task 8 already split it out into `Pilgrim/Models/Threads/ThreadsDossierFieldReport.swift` (the `DossierSensesFieldReport` enum). The invariance harness was added there instead, as a sibling `generateInvarianceReport()`/`evaluateWalkInvariance()` pair next to the existing `generate()`/`evaluateWalk()`, reusing the same `FieldReportContext`, `transcribedRecordings(for:)`, `ThreadsDossierBuilder.gatherSensesBundle`, and `ThreadsDossierBuilder.makeSensesInput` seams. `runIfRequested()` now checks both `--senses-field-report` and `--invariance-field-report` independently (not a literal `switch`, matching the pre-existing style). Also updated the `AppDelegate.swift` comment at the `runIfRequested()` call site to mention both flags.
- Modify: `Pilgrim/Models/Threads/ThreadsDossierFieldReport.swift` (added the invariance harness)
- Modify: `Pilgrim/AppDelegate.swift` (comment only — no wiring change needed, `runIfRequested()` already covers both flags)
- Spec doc `docs/superpowers/specs/2026-08-27-oblique-and-prompt-relevance-design.md` needed no changes: its "DEBUG harness" and "Field gate" sections describe behavior, not the file path, and already match what was built.

**Note on `makeSensesInputForReport`:** the brief's sketch below references a `makeSensesInputForReport` helper. No such symbol exists. The real senses harness assembles its `Input` via `ThreadsDossierBuilder.gatherSensesBundle(walk:now:)` + `ThreadsDossierBuilder.makeSensesInput(senses:state:resolveRouteFix:)` with a `ThreadsDossierBuilder.SensesAssemblyState`; the invariance harness reuses exactly that pair, per-walk, unchanged.

**Interfaces:**
- Produces: `--invariance-field-report` launch argument, mirroring `--senses-field-report`.

- [x] **Step 1: Add the harness** — done 2026-08-27 (see file deviation note above). Steps 2-6 are manual human QA on a real device and are explicitly out of scope for this implementation pass.

Extend the existing `#if DEBUG` harness block at the bottom of `ThreadsDossierBuilder.swift`, mirroring how `--senses-field-report` is structured:

```swift
    /// Ship-gate harness: iterates every walk with transcribed recordings,
    /// evaluates every invariant UNCAPPED and ignoring `pendingFieldGate`,
    /// and prints per-signal firing rates plus each emitted line, so a human
    /// can judge degeneration (fires on nearly every walk) and dead signals
    /// (nearly never) against a REAL device history.
    ///
    /// EVALUATES ONLY — never writes defaults, never consumes real state,
    /// exactly like the senses report.
    static func invarianceFieldReport(walkUUIDs: [UUID]) {
        var fired: [DossierSenses.Invariant: Int] = [:]
        var considered = 0

        for walkUUID in walkUUIDs {
            guard let input = makeSensesInputForReport(walkUUID: walkUUID) else { continue }
            considered += 1
            for invariant in DossierSenses.Invariant.allCases {
                let line: DossierSenses.SenseLine?
                if invariant == .unarrivedIntention {
                    line = DossierSensesInvariance.unarrivedIntention(input: input, suppressed: [])
                } else {
                    line = DossierSenses.evaluateInvariant(invariant, input: input, suppressed: [])
                }
                guard let line else { continue }
                fired[invariant, default: 0] += 1
                print("[invariance] \(walkUUID) \(invariant): \(line.text)")
            }
        }

        print("[invariance] walks considered: \(considered)")
        for invariant in DossierSenses.Invariant.allCases {
            let count = fired[invariant] ?? 0
            let rate = considered > 0 ? Double(count) / Double(considered) * 100 : 0
            print(String(format: "[invariance] %@: %d/%d (%.1f%%)",
                         String(describing: invariant), count, considered, rate))
        }
    }
```

`makeSensesInputForReport` is whatever the existing senses harness already uses to assemble an `Input` per walk — reuse it rather than writing a second one. Signal 5 is called directly so the flag does not hide it from the very report meant to judge it.

Wire `--invariance-field-report` into the same launch-argument switch that handles `--senses-field-report`.

- [ ] **Step 2: Run the firing-rate pass**

Launch the dev build on the team device with `--invariance-field-report` and read the console. Judge per signal: degeneration (fires on nearly every walk) and dead signals (nearly never). Known limitations, same as the senses harness: it skips stale-context self-heal and ignores the `threadsAfterWalks` toggle.

- [ ] **Step 3: Run the harm check**

For a sample of walks, generate the Oblique reflection twice — once as built, once with the `**Unchanged:**` block deleted by hand — and human-rate which is better. A signal that fires often and makes reflections worse is invisible to firing rate.

- [ ] **Step 4: Run the LLM readback**

Paste real Oblique prompts, including elevated marker profiles, into ChatGPT or Claude. Iterate until: no clinical language, no contentless reframe instruction, no invented invariant, one thing named rather than a list. Check specifically whether the model smuggles the pivot back in through a closing question.

- [ ] **Step 5: Judge signal 5**

Only after steps 2–4 pass, and only on real history, decide whether `DossierSensesInvariance.pendingFieldGate` flips to `false`.

- [ ] **Step 6: Record outcomes and commit**

```bash
git add docs/superpowers/specs/2026-08-27-oblique-and-prompt-relevance-design.md Pilgrim/Models/Threads/ThreadsDossierBuilder.swift
git commit -m "test(threads): invariance field harness, and the gate readback

Per-signal firing rates plus the with/without harm check. Firing rate is
the upside only; no free lunch guarantees a matching downside it cannot
see, so both halves get recorded before anything ships externally.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Done when

- [ ] `DossierSensesInvariance` is pure — no DataManager, no CoreStore, no `Date()`
- [ ] Four signals live, fifth dark behind `pendingFieldGate`
- [ ] `Unchanged:` built once, emitted only for Oblique, hoisted above the transcription
- [ ] Marker percentages absent from Creative, Journaling, and Gratitude prompts
- [ ] `CustomPromptStyle` still receives the full dossier via the protocol default
- [ ] Oblique dimmed with "Still listening" until both gates pass, verified on device
- [ ] `TranscriptContext.currentSchemaVersion` still `4`
- [ ] No new `fetchAll` anywhere in the diff
- [ ] Full suite green, no reduction from the 1388 baseline; lint clean, zero new warnings
- [ ] Field gate steps 2–4 recorded in the spec before any external release
