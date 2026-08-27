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

            let packs = thread.appearances.compactMap { appearance -> MarkerPack? in
                guard let markers = byRecording[appearance.recordingUUID]?.markers,
                      markers.wordCount >= ThreadsDossierFormatter.densityFloorWords else { return nil }
                return markers
            }
            guard packs.count >= minimumInvariantWalks else { continue }

            let absolutist = packs.map { Double($0.absolutistCount) / Double($0.wordCount) }
            let firstPerson = packs.map { Double($0.firstPersonCount) / Double($0.wordCount) }
            let sentiment = packs.compactMap { $0.sentiment }.map { $0 + sentimentShift }
            guard sentiment.count == packs.count else { continue }

            guard isFlat(absolutist), isFlat(firstPerson), isFlat(sentiment) else { continue }

            let walks = Set(thread.appearances.map(\.walkUUID)).count
            return DossierSenses.SenseLine(
                text: "'\(thread.displayTerm)' has returned across \(walks) walks; "
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

**Interfaces:**
- Produces: `DossierSensesInvariance.frameConstancy(input:suppressed:) -> DossierSenses.SenseLine?`
- Consumes: `MarkerPack.modalCounts`, `MarkerLexicons.modalFamily(of:)`, `MarkerLexicons.ModalFamily`

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
    /// Per-appearance dominance is a MODE, not a majority — the same fix
    /// PR #71 applied to weatherWeave to kill the cloud tautologies. A
    /// family can dominate with 40% of the modals as long as nothing beats
    /// it. Deterministic ties: `ModalFamily.allCases` is declaration-ordered
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
            let families = thread.appearances.compactMap { appearance -> MarkerLexicons.ModalFamily? in
                guard let modals = byRecording[appearance.recordingUUID]?.markers?.modalCounts,
                      !modals.isEmpty else { return nil }
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

            guard families.count >= minimumInvariantWalks,
                  let first = families.first,
                  families.allSatisfy({ $0 == first }) else { continue }

            return DossierSenses.SenseLine(
                text: "Every walk where '\(thread.displayTerm)' appears is "
                    + "\(first.rawValue)-dominant.",
                lemma: thread.lemma
            )
        }
        return nil
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

---

## Task 6: Signal 4 — place-frame lock

**Why:** The same theme spoken within the same 150m cluster every time is an invariant tied to ground, not language. `placeResonance` already proves the clustering machinery works over `fixes`.

**Files:**
- Modify: `Pilgrim/Models/Threads/DossierSensesInvariance.swift`
- Modify: `UnitTests/DossierSensesInvarianceTests.swift`

**Interfaces:**
- Produces: `DossierSensesInvariance.placeFrameLock(input:suppressed:) -> DossierSenses.SenseLine?`
- Consumes: `DossierSenses.Input.fixes`, `DossierSenses.qualifies(_:)`, `DossierSenses.distance(_:_:)`, `DossierSenses.placeClusterRadius`

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

- [ ] **Step 2: Run to verify it fails**

Expected: COMPILE FAILURE — no `placeFrameLock`.

- [ ] **Step 3: Implement**

```swift
extension DossierSensesInvariance {

    /// The same theme spoken inside the same `placeClusterRadius` cluster
    /// every time. An invariant tied to ground rather than to language.
    ///
    /// Reuses `DossierSenses.qualifies` so poor-accuracy and long-gap fixes
    /// are excluded on the same terms as `placeResonance` — a 500m-accuracy
    /// fix would make any two points look like the same place.
    static func placeFrameLock(
        input: DossierSenses.Input, suppressed: Set<String>
    ) -> DossierSenses.SenseLine? {
        for thread in input.threads.sorted(by: { $0.lemma < $1.lemma })
        where !suppressed.contains(thread.lemma) {
            let coordinates = thread.appearances.compactMap { appearance -> DossierSenses.Coordinate? in
                guard let fix = input.fixes[appearance.recordingUUID],
                      DossierSenses.qualifies(fix) else { return nil }
                return fix.coordinate
            }
            guard coordinates.count >= minimumInvariantWalks else { continue }

            guard let anchor = coordinates.first else { continue }
            let clustered = coordinates.allSatisfy {
                DossierSenses.distance(anchor, $0) <= DossierSenses.placeClusterRadius
            }
            guard clustered else { continue }

            let walks = Set(thread.appearances.map(\.walkUUID)).count
            return DossierSenses.SenseLine(
                text: "'\(thread.displayTerm)' has been spoken in the same place "
                    + "on all \(walks) walks it appears in.",
                lemma: thread.lemma
            )
        }
        return nil
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
git add Pilgrim/Models/Threads/DossierSensesInvariance.swift UnitTests/DossierSensesInvarianceTests.swift
git commit -m "feat(threads): place-frame lock — the same thought at the same bend

An invariant tied to ground rather than language: the walker says this in
this place, every time, and has never noticed. Reuses the placeResonance
hygiene gate so a 500m-accuracy fix cannot make two points look like one.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Signal 5 — unarrived intention, shipped dark

**Why:** The walker deliberately set out carrying a word, repeatedly, and the language never moved. This is Vervaeke's *"keep good track of your failures"* made literal — and the most confronting line the app could produce, which is why it ships behind a flag.

**Files:**
- Modify: `Pilgrim/Models/Threads/DossierSensesInvariance.swift`
- Modify: `UnitTests/DossierSensesInvarianceTests.swift`

**Interfaces:**
- Produces: `DossierSensesInvariance.unarrivedIntention(input:suppressed:) -> DossierSenses.SenseLine?`
- Consumes: `DossierSenses.WalkSnapshotRow.intention`, `TranscriptNLP.contentLemmas(in:)`, `ThreadStore.salienceDirection(of:)`

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

- [ ] **Step 3: Implement**

```swift
extension DossierSensesInvariance {

    /// The walker deliberately set out carrying a word, on at least
    /// `minimumInvariantWalks` walks, and that word's thread is STILL
    /// steady. They tried, on purpose, and nothing moved.
    ///
    /// SHIPS DARK behind `pendingFieldGate`. This is the most confronting
    /// line the app can produce; the engine and its tests exist so the
    /// judgement can be made on real history, not on a guess.
    static func unarrivedIntention(
        input: DossierSenses.Input, suppressed: Set<String>
    ) -> DossierSenses.SenseLine? {
        var intentionWalks: [String: Set<UUID>] = [:]
        for snapshot in input.walkSnapshots {
            guard let intention = snapshot.intention, !intention.isEmpty else { continue }
            for lemma in TranscriptNLP.contentLemmas(in: intention) {
                intentionWalks[lemma, default: []].insert(snapshot.walkUUID)
            }
        }

        for thread in input.threads.sorted(by: { $0.lemma < $1.lemma })
        where !suppressed.contains(thread.lemma) {
            guard let walks = intentionWalks[thread.lemma],
                  walks.count >= minimumInvariantWalks,
                  ThreadStore.salienceDirection(of: thread) == .steady else { continue }
            return DossierSenses.SenseLine(
                text: "'\(thread.displayTerm)' was set as an intention on \(walks.count) walks; "
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

- [ ] **Step 4: Run to verify it passes**

Expected: both PASS — the engine computes it, the flag withholds it.

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Threads/DossierSensesInvariance.swift UnitTests/DossierSensesInvarianceTests.swift
git commit -m "feat(threads): the unarrived intention, shipped dark

The walker set out carrying a word, on purpose, three times or more, and
the language never moved. Keeping good track of your failures, made
literal - and the hardest thing the app could say to someone on a bad day.

Engine and tests ship so the call can be made on real history rather than
on a guess. The flag stays true until the field gate says otherwise.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Build the `Unchanged:` block and carry it on `ActivityContext`

**Why:** The engine produces lines; something must render them into a block, build it **once**, and hand it to the assembler.

**Files:**
- Modify: `Pilgrim/Models/Prompt/ActivityContext.swift` (add `var unchangedBlock: String?` and the `make` parameter)
- Modify: `Pilgrim/Models/Threads/ThreadsDossierBuilder.swift` (build and assign)
- Modify: `UnitTests/ThreadsDossierSensesTests.swift`

**Interfaces:**
- Produces: `ActivityContext.unchangedBlock: String?` — the fully rendered block including its `**Unchanged:**` heading, or `nil` when no invariant fired.

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
git add Pilgrim/Models/Prompt/ActivityContext.swift Pilgrim/Models/Threads/ThreadsDossierBuilder.swift UnitTests/
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
- Modify: `Pilgrim/Models/Threads/ThreadsDossierFormatter.swift`
- Create: `UnitTests/PromptContextPolicyTests.swift`

**Interfaces:**
- Produces:
  - `struct PromptContextPolicy { let includesMarkerLines: Bool; let includesThreadAnalysis: Bool; let hoistsUnchangedBlock: Bool; static let full: PromptContextPolicy }`
  - `PromptVoice.contextPolicy: PromptContextPolicy` with a `.full` default in the protocol extension
  - `ThreadsDossierFormatter.dossier(..., includeMarkerLines: Bool, includeThreadAnalysis: Bool)`

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

- [ ] **Step 1: Write the failing tests**

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

- [ ] **Step 2: Run to verify it fails**

Expected: COMPILE FAILURE — no `.oblique`, no `ObliqueVoice`.

- [ ] **Step 3: Implement**

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

- [ ] **Step 4: Run to verify it passes**

Expected: all PASS.

- [ ] **Step 5: Run the full suite**

Any test asserting `PromptStyle.allCases.count == 6` must become `7`. Any test iterating all styles will now include Oblique — confirm those still pass rather than weakening them.

- [ ] **Step 6: Commit**

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

**Why:** Oblique needs ≥5 walks with transcripts *and* speech on the current walk. Below either, it would be inventing. It shows in the list from day one, unselectable, so the walker learns it exists.

**Files:**
- Modify: `Pilgrim/Models/Prompt/PromptStyle.swift` (availability helper)
- Modify: `Pilgrim/Scenes/Prompts/PromptListView.swift`
- Modify: `UnitTests/ObliqueVoiceTests.swift`

**Interfaces:**
- Produces: `PromptStyle.isAvailable(walksWithTranscripts:currentWalkHasSpeech:) -> Bool`, `PromptStyle.waitingCopy: String?`, `PromptStyle.minimumWalksForOblique`

- [ ] **Step 1: Write the failing tests**

```swift
    func testAvailability_obliqueNeedsHistoryAndSpeech() {
        XCTAssertFalse(PromptStyle.oblique.isAvailable(walksWithTranscripts: 4, currentWalkHasSpeech: true))
        XCTAssertFalse(PromptStyle.oblique.isAvailable(walksWithTranscripts: 9, currentWalkHasSpeech: false))
        XCTAssertTrue(PromptStyle.oblique.isAvailable(walksWithTranscripts: 5, currentWalkHasSpeech: true))
    }

    func testAvailability_otherStylesAlwaysAvailable() {
        for style in PromptStyle.allCases where style != .oblique {
            XCTAssertTrue(style.isAvailable(walksWithTranscripts: 0, currentWalkHasSpeech: false))
        }
    }

    func testWaitingCopy_onlyObliqueHasIt() {
        XCTAssertEqual(PromptStyle.oblique.waitingCopy, "Still listening. A few more walks with your voice.")
        XCTAssertNil(PromptStyle.reflective.waitingCopy)
    }
```

- [ ] **Step 2: Run to verify it fails**

Expected: COMPILE FAILURE — no `isAvailable`.

- [ ] **Step 3: Implement**

In `PromptStyle.swift`:

```swift
extension PromptStyle {

    static let minimumWalksForOblique = 5

    /// Oblique needs both a deep enough record AND speech on this walk —
    /// `ThreadsDossierFormatter.dossier` returns nil when the current walk
    /// has no recordings, so a silent walk yields no Unchanged block to
    /// read. Every other style is always available.
    func isAvailable(walksWithTranscripts: Int, currentWalkHasSpeech: Bool) -> Bool {
        guard self == .oblique else { return true }
        return walksWithTranscripts >= Self.minimumWalksForOblique && currentWalkHasSpeech
    }

    /// Shown dimmed in the picker while unavailable. True for either failing
    /// gate — thin history, or no voice on this walk — so one string covers
    /// both without lying.
    var waitingCopy: String? {
        self == .oblique ? "Still listening. A few more walks with your voice." : nil
    }
}
```

In `PromptListView.swift`, `PromptStyleRow` (line ~352) takes a `GeneratedPrompt` and renders `prompt.icon` / `prompt.title` / `prompt.subtitle`. Add a waiting state to it:

```swift
struct PromptStyleRow: View {
    let prompt: GeneratedPrompt
    var waitingCopy: String? = nil

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

In the `ForEach(prompts)` body, suppress the button when the style is waiting:

```swift
                ForEach(prompts) { prompt in
                    let waiting = prompt.style.flatMap { style in
                        style.isAvailable(
                            walksWithTranscripts: walksWithTranscripts,
                            currentWalkHasSpeech: context.hasSpeech
                        ) ? nil : style.waitingCopy
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

`walksWithTranscripts` is a new `Int` the view needs. Source it the same way the view already obtains its `ActivityContext`; if that count is not already available, add it to the derivations `PromptGenerator.resolvedDerivations` returns rather than issuing a fetch from the view. Custom prompts have `style == nil` and so are never gated.

Never use `.system()` fonts — `Constants.Typography.*` only.

- [ ] **Step 4: Run to verify it passes**

Expected: all PASS.

- [ ] **Step 5: Check it on device**

Build and run. Confirm: with a fresh profile Oblique appears dimmed with the waiting copy; the row is not tappable; the copy uses the project's fonts and does not crowd on a small screen at large Dynamic Type.

- [ ] **Step 6: Commit**

```bash
git add Pilgrim/Models/Prompt/PromptStyle.swift Pilgrim/Scenes/Prompts/PromptListView.swift UnitTests/ObliqueVoiceTests.swift
git commit -m "feat(prompts): the Oblique gate — still listening

Two gates, because both are real: five walks of record, and a voice on this
walk. The dossier returns nil when the current walk has no recordings, so a
silent walk has no Unchanged block to read.

One string covers both failures without lying, and it frames the voice as
needing to hear more rather than as a level to grind. Every other gate in
this app is silent; a style that vanished from a picker would be stranger
than one that says what it is waiting for.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 12: DEBUG harness and the field gate

**Why:** Firing rate measures only the upside. The no-free-lunch theorem guarantees a matching downside that firing rate is structurally blind to — `questionDensity` escaped only because it was loud.

**Files:**
- Modify: `Pilgrim/Models/Threads/ThreadsDossierBuilder.swift` (the `#if DEBUG` harness block)
- Modify: `docs/superpowers/specs/2026-08-27-oblique-and-prompt-relevance-design.md`

**Interfaces:**
- Produces: `--invariance-field-report` launch argument, mirroring `--senses-field-report`.

- [ ] **Step 1: Add the harness**

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
