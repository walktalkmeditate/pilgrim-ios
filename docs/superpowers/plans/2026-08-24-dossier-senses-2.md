# Dossier Senses II Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Spec (binding):** `docs/superpowers/specs/2026-08-24-dossier-senses-2-design.md` — every "(binding)" annotation there is non-negotiable. Context spec: `docs/superpowers/specs/2026-08-22-thought-threads-design.md`.

**Goal:** Nine quiet senses for the AI-prompt dossier — place-theme resonance, the moon line, theme-marker coloring, intention lineage, climb anchoring, weather weave, photo adjacency, question density, speech shape — rendered as a `**Noticed:**` block of at most 3 lines inside the existing threads dossier. All on-device, all descriptive, no new UI.

**Architecture:** One new pure module `DossierSenses` (`DossierSenses.lines(input:) -> Output`; two files — `DossierSenses.swift` core + `DossierSensesTracks.swift` senses — purely for the SwiftLint file_length gate) owns the cap, priority order, one-theme-one-line rule, and every template. `ThreadsDossierBuilder` stays the one impure gatherer: a new main-actor `gatherSensesBundle(walk:now:)` collects the cheap CoreStore snapshots before the detached build; the builder resolves route fixes lazily (per needed recording, via a `threadSafeSyncReturn`-hopping `DataManager.routeFixNear`), assembles `DossierSenses.Input`, appends the block, and owns the moon-line UserDefaults state. Data fetches are small extensions in the two existing DataManager files (`+VoiceRecording`, `+Query`) mirroring the shipped `queryAttributes` snapshot patterns.

**Tech stack:** Swift (Foundation + CoreLocation + NaturalLanguage), CoreStore via DataManager, XCTest (`UnitTests` target), CocoaPods workspace, classic pbxproj.

**Branch:** `feat/dossier-senses-2` off `main` (a26783d).

## Global Constraints

**Binding thresholds and gates (verbatim from the spec — do not tune):**

- **Place-theme resonance:** mentions on ≥2 distinct walks whose recording coordinates fall within a **150 m** great-circle radius of each other. **Specificity guard (binding):** emits only when the theme's cluster radius is **at most half** the walker's baseline in-window recording spread (median pairwise distance across ALL in-window mention recordings) — implemented as strict `spread < baseline / 2` so the all-points-identical degenerate case suppresses. Gates: `backfillComplete`, ≥2 distinct walks in the standard 30-day window. Cost bound: only themes already in the dossier's thread section are checked (≤4), only mention recordings' coordinates are resolved.
- **Coordinate hygiene (applies wherever a recording is located):** a recording participates in location claims only when its nearest `routeData` sample is within **90 seconds** of the recording's start AND `horizontalAccuracy < 100` m. The accuracy floor reuses the existing discipline at `LocationManagement.swift:57` (`horizontalAccuracy < 100`); the 90-second recording↔sample gap is a new threshold introduced by this plan, not precedented there — field-tunable at the ship gate like the priority order. Failing either → non-participation, same as walks without route data.
- **Photo adjacency:** photo within **75 m** of a theme mention's recording location, taken within **10 minutes** of that mention. Place first, time second. Nearest qualifying pair only; one line max.
- **Weather weave climate guard (binding):** skip when the shared category is the walker's in-window *majority* condition (**>50%** of in-window walks with stored weather). Categories: rain, snow, clear, cloud, wind, fog, plus a named `unknown` bucket; a unit test asserts every condition string the app can store maps to some bucket. Walks with unknown/missing conditions are excluded, and a theme with any excluded walk emits nothing — the claim must be total.
- **Theme-marker coloring:** ±15-word windows; emit only when window density **≥ 2×** overall AND **≥3** absolutist tokens in windows. **Placement + gate (binding):** the line renders inside the `Noticed:` block, counts against the 3-line cap, and emits ONLY when the full threads dossier is present — structurally guaranteed because the block is appended to a non-nil dossier, whose presence triggers the marker handling note via `PromptAssembler.responseContract(hasThreadsDossier:)` (verified: `PromptAssembler.swift:45,183-184`; line 185 is the closing brace, not a further conditional line).
- **Climb anchoring:** steepest sustained ascent = top decile of smoothed gradient, minimum **20 m** gain; skip entirely when total ascent < **50 m**.
- **Question density:** ≥3 walks of history required; emit only when today ≥ **2× median**, **≥3** questions, AND today's count exceeds every other in-window walk's count. Counts computed at build time from stored transcripts (bounded in-window fetch) — no `TranscriptContext` schema change.
- **Speech shape:** all recordings in the first third of the walk's duration AND wordless remainder exceeds **30 minutes**.
- **Intention lineage:** ≥3 in-window walks carrying intentions sharing a **non-scaffold** lemma, and today's walk has an intention in that family. **Scaffold filter (binding):** `SpokenStoplist.scaffoldLemmas`. Required fixture: two topically-unrelated intentions sharing only "want" must NOT cluster.
- **Moon line:** once per lunation; state is one UserDefaults int `threadsMoonLineLastLunationIndex`, set when the line is emitted; Delete All Data clears it; device-backup only, never in `.pilgrim` exports (no PilgrimPackage change — absence is the policy). Gates: the closed lunation contains ≥1 walk with words; **the current walk itself has ≥1 recorded word**; `threadsAfterWalks` on. Only the single most-recently-closed lunation is ever eligible — no retroactive moon lines (accepted behavior).
- **Prompt economy:** each sense emits **at most one line**; the whole block is capped at **3 lines**; silence is the default.
- **One theme, one line:** once a sense has named a theme, lower-priority senses skip that theme (they may fall through to their next qualifying theme).
- **Priority order (binding, provisional — field-tunable only at the ship gate):** 1 place-theme resonance, 2 the moon line, 3 theme-marker coloring, 4 intention lineage, 5 climb anchoring, 6 weather weave, 7 photo adjacency, 8 question density, 9 speech shape.
- **Module purity (binding):** `DossierSenses.lines(...)` performs no DataManager, CoreStore, or singleton access itself. Every input is fetched by the caller (`ThreadsDossierBuilder`) and passed as an argument. A future sense that needs new data must widen the call signature — never reach out sideways.
- **Descriptive-never-evaluative** in every emitted line; template counts and ordinals are always substituted from computed values, never hardcoded prose; raw coordinates never appear in prompt text — "near the same stretch of ground" is the whole location claim.
- **Toggle sovereignty:** `threadsAfterWalks` off = none of this computes (no fetches, no senses, no moon state).
- **No schema migration:** no new entities, attributes, or Core Data indexes. All new state is UserDefaults or derived at build time.
- **Performance:** target <50 ms added for a typical history; route-sample resolution is bounded timestamp-predicate queries with `fetchLimit` — never `walk.routeData` full-array traversal for cross-walk resolution. Measured for real at the ship gate.

**Exact template strings (string-pin every one; substitution rules are binding):**

| # | Sense | Template | Substitution rules |
|---|---|---|---|
| 1 | Place | `'music' has surfaced on N walks — K times near the same stretch of ground.` | N = distinct in-window walks (digits). K = cluster's actual mention count; `twice` replaces `2 times` only when K is literally 2. |
| 2 | Moon | `The Sturgeon Moon has set: 5 walks, 3 with recorded words; 'music' walked in 2 of them.` | Digits throughout; `walk`/`walks` pluralized; theme clause omitted (line ends `...recorded words.`) when no theme walked that moon or the top theme is already named this build; at most one theme — the one in the most walks that moon, ties alphabetical. |
| 3 | Marker | `Absolutist words cluster around 'the move' — twice the density of the rest of the walk's speech.` | Multiplier = floor of window density ÷ rest-of-walk density (vs-overall fallback when the rest holds zero absolutist words — an under-claim, never an overstatement); `twice` / `three times`…`nine times` spelled, digits + ` times` from 10. |
| 4 | Intention | `Fifth walk in the last 30 days carrying some form of 'release'.` | Ordinal = actual in-window count carrying the family (today included); spelled `Third`…`Twelfth`, numeric ordinal (`13th`, `21st`) beyond. |
| 5 | Climb | `'the move' was spoken on the day's steepest climb.` | Display term substituted. |
| 6 | Weather | `All N walks where 'music' surfaced were under rain.` | N digits; `Both walks where...` only when N is literally 2. Sky phrases (pinned): rain `under rain`, snow `under snow`, clear `under clear skies`, cloud `under cloud`, wind `in wind`, fog `in fog`. |
| 7 | Photo | `A photo was taken near where 'music' was spoken.` | Display term substituted. |
| 8 | Question | `Four of today's sentences were questions — more than any walk in the last 30 days.` | Count spelled + capitalized `Three`…`Nine`, digits from 10. |
| 9 | Speech | `All the words came in the first third; the last 40 minutes were wordless.` | Minutes = floor(wordless remainder ÷ 60), digits. |

Block heading: `**Noticed:**`, appended to the dossier after the quiet-lines section, one line per row.

**House rules:**

- Suite baseline on main (a26783d): **1284 tests**. Reconcile every count via `grep -c "Test Case '.*' started"` — summary lines lie under the macos-26 first-run sim flake; retry once before believing a failure.
- SwiftLint full-repo baseline **398 warnings / 0 errors** (`swiftlint 2>/dev/null | tail -3`). Zero NEW findings. `.swiftlint.yml` gates: file_length warning 500, type_body_length warning 400, function_body_length warning 60 — structure `DossierSenses` as a small primary enum + per-track extensions, keep every function under 60 lines.
- pbxproj is classic format, hand-edited: exactly 4 entries per new file (PBXBuildFile, PBXFileReference, group child, Sources build phase), mirroring the `ThreadsDossierBuilder.swift` / `ThreadsDossierTests.swift` entries; `plutil -lint Pilgrim.xcodeproj/project.pbxproj` must pass after every pbxproj edit.
- New files are exactly four: `Pilgrim/Models/Threads/DossierSenses.swift` (types + engine + helpers), `Pilgrim/Models/Threads/DossierSensesTracks.swift` (the nine sense implementations — the split keeps each source file under the 500-line file_length gate), `UnitTests/DossierSensesTests.swift` (Stage A tests), `UnitTests/DossierSensesCrossWalkTests.swift` (Stage C tests). Everything else extends existing files. At every task's lint step, check the touched files against file_length 500; if one approaches the gate, a further split at that task is sanctioned (4 pbxproj entries, recorded in Execution status) — never accept a new warning.
- Test hygiene: `DataManager.dataStack` swap-and-restore (restore the saved stack, never nil) in tearDowns; UserDefaults save/restore for every key a test mutates — **including `threadsMoonLineLastLunationIndex`**; per-test temp `TranscriptContextStore` directories removed in defer.
- Comment policy: comments state constraints code can't show; no what-comments.
- Toggle guard is the first statement of every entry point that computes (existing `ThreadsDossierBuilder.build` guard stays first; the new senses gather in `PromptListView` is wrapped in the same check).
- `Date()` never inside pure sense functions — the builder injects `now`; `DossierSenses` receives only dates as data.
- `rowUUID` discipline for every `queryAttributes` UUID column (CoreStore stores `UUID` as `.stringAttributeType` — a raw `as? UUID` cast silently drops every row).
- Full app build (`xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build`) succeeds before every commit. Test command: `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` (narrow with `-only-testing:UnitTests/<Class>` during TDD loops).
- Commits end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

**Ship gate (binding — release precondition, not code):** before ANY Senses II line ships externally: (1) real-history firing pass — run the Task 10 harness against the team's own device history, record each sense's firing rate and output text; a sense that fires on nearly every walk or nearly never is re-thresholded or cut here; this is also where "same stretch of ground" is judged and Whisper's `?` reliability is measured (question density is cut at the gate, not patched, if punctuation proves unreliable). (2) LLM-readback QA — paste real dossiers containing Senses II blocks, **explicitly including theme-linked marker lines**, into consumer LLMs; iterate the handling note until no response contains clinical or diagnostic language. Both are human judgment on real data.

**Resolved ambiguities (documented so review can challenge them, not rediscover them):**

- The spec's "dossier's thread section (≤4)" cap: the shipped thread section is uncapped, so the ≤4 is implemented as `placeCandidateThemeCap = 4` — place resonance checks only the first 4 active threads (lemma-sorted, the section's order).
- Specificity guard uses strict `<` (see above). Cluster construction is deterministic seed-centered: for each hygiene-qualified mention recording (sorted by UUID), members = recordings within 150 m of the seed; best cluster by mention count, then smallest spread, then seed order.
- Climb "gradient" = climb rate over time (m/s) between consecutive smoothed samples (centered moving average, window 5) — the series carries no distance; top decile computed over positive rates only (nearest-rank percentile).
- Walk "duration" for speech shape and climb overlap = wall clock `startDate…endDate` (recording timestamps are wall-clock).
- Question count = number of `?` characters in the transcript (Whisper terminates sentences; the ship gate judges this proxy).
- Weather bucket mapping from the stored `WeatherCondition` rawValues: clear→clear; partlyCloudy/overcast/haze→cloud; lightRain/heavyRain/thunderstorm→rain; snow→snow; fog→fog; wind→wind; anything else→unknown.
- Sky phrases: the spec's own example only gives "under rain." The other five (`under snow`, `under clear skies`, `under cloud`, `in wind`, `in fog`) are invented for this plan — flagged here so review can challenge the wording, not just the mapping.
- Moon line's `asOf` is build-time `now` (spec-literal): an old walk's dossier may carry the current closed lunation's line, once, if that walk has words.
- Memo (`changeCount, walkUUID, backfillComplete` + moon state): the memo stores the **post-write** moon state, so reopening the same walk's prompts returns the cached dossier with its moon line intact; any other walk or a store change rebuilds without it — once per lunation holds.

---

## Stage A — pure module skeleton + current-walk senses

### Task 1: DossierSenses skeleton — types, engine (cap / priority / dedup), helpers

**Files:**
- Create: `Pilgrim/Models/Threads/DossierSenses.swift` (types, engine, helpers)
- Create: `Pilgrim/Models/Threads/DossierSensesTracks.swift` (sense implementations; holds the stubs until each track's task lands)
- Create: `UnitTests/DossierSensesTests.swift`
- Modify: `Pilgrim.xcodeproj/project.pbxproj` — 4 entries per new file, 12 total (source files → Pilgrim target group `Pilgrim/Models/Threads` + Pilgrim Sources phase; test file → `UnitTests` group + UnitTests Sources phase). Generate fresh 24-hex IDs (`uuidgen | tr -d '-' | cut -c1-24 | tr 'a-f' 'A-F'`), mirror the `ThreadsDossierBuilder.swift` / `ThreadsDossierTests.swift` entry shapes exactly. Run `plutil -lint Pilgrim.xcodeproj/project.pbxproj`.

**Interfaces produced (stable for every later task — do not rename):**
- `DossierSenses.Input`, `.Output`, `.SenseLine`, `.Sense`, `.Coordinate`, `.RouteFix`, `.ElevationSample`, `.PhotoPin`, `.CurrentRecording`, `.WalkSnapshotRow`, `.MoonInput`
- `DossierSenses.lines(input:evaluate:) -> Output` (the `evaluate` default is the production dispatch; tests may stub it — same seam style as `ThreadsBackfill.runIfNeeded`)
- `DossierSenses.qualifies(_: RouteFix) -> Bool`, `.distance(_:_:)`, `.median(_:)`, `.timesPhrase(_:)`, `.capitalizedCount(_:)`, `.ordinalWord(_:)`, `.activeThreads(in:)`

**Step 1 — RED.** Write `UnitTests/DossierSensesTests.swift`:

```swift
import XCTest
@testable import Pilgrim

final class DossierSensesTests: XCTestCase {

    // MARK: - Fixtures

    static let walkStart = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
    static let walkEnd = DateFactory.makeDate(2024, 6, 15, 10, 30, 0)

    func makeInput(
        currentWalkUUID: UUID = UUID(),
        walkStart: Date = DossierSensesTests.walkStart,
        walkEnd: Date = DossierSensesTests.walkEnd,
        totalAscent: Double = 0,
        elevationSeries: [DossierSenses.ElevationSample] = [],
        photos: [DossierSenses.PhotoPin] = [],
        currentRecordings: [DossierSenses.CurrentRecording] = [],
        threads: [WalkThread] = [],
        backfillComplete: Bool = true,
        walkSnapshots: [DossierSenses.WalkSnapshotRow] = [],
        historyTranscripts: [(recordingUUID: UUID, transcript: String)] = [],
        recordingTimestamps: [UUID: Date] = [:],
        walkIndex: [UUID: (walkUUID: UUID, date: Date)] = [:],
        fixes: [UUID: DossierSenses.RouteFix] = [:],
        moon: DossierSenses.MoonInput? = nil
    ) -> DossierSenses.Input {
        DossierSenses.Input(
            currentWalkUUID: currentWalkUUID, walkStart: walkStart, walkEnd: walkEnd,
            totalAscent: totalAscent, elevationSeries: elevationSeries, photos: photos,
            currentRecordings: currentRecordings, threads: threads,
            backfillComplete: backfillComplete, walkSnapshots: walkSnapshots,
            historyTranscripts: historyTranscripts, recordingTimestamps: recordingTimestamps,
            walkIndex: walkIndex, fixes: fixes, moon: moon
        )
    }

    func fix(lat: Double, lon: Double, accuracy: Double = 10, gap: TimeInterval = 5) -> DossierSenses.RouteFix {
        DossierSenses.RouteFix(
            coordinate: DossierSenses.Coordinate(latitude: lat, longitude: lon),
            horizontalAccuracy: accuracy, gapSeconds: gap
        )
    }

    // MARK: - Engine: cap, priority, dedup

    private func stub(_ firing: [DossierSenses.Sense: DossierSenses.SenseLine])
        -> (DossierSenses.Sense, DossierSenses.Input, Set<String>) -> DossierSenses.SenseLine? {
        { sense, _, _ in firing[sense] }
    }

    func testEngine_fiveSensesFiring_exactlyThreeLinesInPriorityOrder() {
        let firing: [DossierSenses.Sense: DossierSenses.SenseLine] = [
            .speechShape: .init(text: "speech", lemma: nil),
            .climbAnchoring: .init(text: "climb", lemma: "river"),
            .placeResonance: .init(text: "place", lemma: "move"),
            .questionDensity: .init(text: "question", lemma: nil),
            .weatherWeave: .init(text: "weather", lemma: "music")
        ]
        let output = DossierSenses.lines(input: makeInput(), evaluate: stub(firing))
        XCTAssertEqual(output.lines, ["place", "climb", "weather"],
                       "cap 3, spec priority order: place(1) > climb(5) > weather(6) > question(8) > speech(9)")
    }

    func testEngine_themeNamedAtRankOne_neverReappearsAtLowerRank() {
        let firing: [DossierSenses.Sense: DossierSenses.SenseLine] = [
            .placeResonance: .init(text: "place move", lemma: "move"),
            .climbAnchoring: .init(text: "climb move", lemma: "move"),
            .speechShape: .init(text: "speech", lemma: nil)
        ]
        let output = DossierSenses.lines(input: makeInput(), evaluate: stub(firing))
        XCTAssertEqual(output.lines, ["place move", "speech"],
                       "the engine enforces one-theme-one-line even against a misbehaving sense")
    }

    func testEngine_nothingFiring_emitsNothing() {
        let output = DossierSenses.lines(input: makeInput(), evaluate: { _, _, _ in nil })
        XCTAssertTrue(output.lines.isEmpty)
        XCTAssertNil(output.reportedLunationIndex)
    }

    func testEngine_moonLineAdmitted_reportsLunationIndex() {
        let moon = DossierSenses.MoonInput(
            lunationIndex: 300, moonName: "Sturgeon Moon",
            start: DateFactory.makeDate(2024, 5, 8), end: DateFactory.makeDate(2024, 6, 6),
            lastReportedIndex: nil, currentWalkHasWords: true,
            allWalkDates: [], wordedWalkDates: []
        )
        let firing: [DossierSenses.Sense: DossierSenses.SenseLine] = [
            .moonLine: .init(text: "moon", lemma: nil)
        ]
        let output = DossierSenses.lines(input: makeInput(moon: moon), evaluate: stub(firing))
        XCTAssertEqual(output.lines, ["moon"])
        XCTAssertEqual(output.reportedLunationIndex, 300)
    }

    func testEngine_moonLineNotAdmitted_doesNotReport() {
        let output = DossierSenses.lines(input: makeInput(moon: nil), evaluate: { _, _, _ in nil })
        XCTAssertNil(output.reportedLunationIndex)
    }

    // MARK: - Helpers

    func testCoordinateHygiene_gates() {
        XCTAssertTrue(DossierSenses.qualifies(fix(lat: 0, lon: 0, accuracy: 99, gap: 90)))
        XCTAssertFalse(DossierSenses.qualifies(fix(lat: 0, lon: 0, accuracy: 100, gap: 5)),
                       "accuracy must be strictly under 100 m — LocationManagement's discipline")
        XCTAssertFalse(DossierSenses.qualifies(fix(lat: 0, lon: 0, accuracy: 10, gap: 91)),
                       "a stale sample (>90 s) never anchors a claim")
    }

    func testDistance_greatCircle() {
        let a = DossierSenses.Coordinate(latitude: 42.8782, longitude: -8.5448)
        let b = DossierSenses.Coordinate(latitude: 42.8791, longitude: -8.5448)
        XCTAssertEqual(DossierSenses.distance(a, b), 100, accuracy: 5)
    }

    func testMedian_oddAndEven() {
        XCTAssertEqual(DossierSenses.median([3, 1, 2]), 2)
        XCTAssertEqual(DossierSenses.median([1, 2, 3, 10]), 2.5)
    }

    func testNumberWords() {
        XCTAssertEqual(DossierSenses.timesPhrase(2), "twice")
        XCTAssertEqual(DossierSenses.timesPhrase(3), "three times")
        XCTAssertEqual(DossierSenses.timesPhrase(10), "10 times")
        XCTAssertEqual(DossierSenses.capitalizedCount(4), "Four")
        XCTAssertEqual(DossierSenses.capitalizedCount(11), "11")
        XCTAssertEqual(DossierSenses.ordinalWord(5), "Fifth")
        XCTAssertEqual(DossierSenses.ordinalWord(12), "Twelfth")
        XCTAssertEqual(DossierSenses.ordinalWord(13), "13th")
        XCTAssertEqual(DossierSenses.ordinalWord(21), "21st")
    }
}
```

Run: `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/DossierSensesTests 2>&1 | tail -20`
Expected: **build failure** — `cannot find 'DossierSenses' in scope` (RED via compile).

**Step 2 — GREEN.** Create `Pilgrim/Models/Threads/DossierSenses.swift`:

```swift
import Foundation
import CoreLocation

/// Pure sense engine for the dossier's `Noticed:` block. Binding purity
/// contract (spec principle 8): no DataManager, CoreStore, or singleton
/// access — every input arrives as an argument, fetched by the builder, so
/// every line stays traceable to enumerable, deterministic inputs. `Date()`
/// is never called here; time arrives as data.
enum DossierSenses {

    static let lineCap = 3
    static let placeClusterRadius: CLLocationDistance = 150
    static let placeCandidateThemeCap = 4
    static let hygieneMaxGap: TimeInterval = 90
    static let hygieneMaxAccuracy: Double = 100
    static let photoTieRadius: CLLocationDistance = 75
    static let photoTieMaxInterval: TimeInterval = 600
    static let climbMinTotalAscent: Double = 50
    static let climbMinRunGain: Double = 20
    static let climbSmoothingWindow = 5
    static let climbTopDecile = 0.9
    static let markerWindowRadius = 15
    static let markerMinWindowAbsolutist = 3
    static let markerMinDensityRatio = 2.0
    static let questionMinCount = 3
    static let questionMinHistoryWalks = 3
    static let questionMedianRatio = 2.0
    static let speechShapeMinWordlessRemainder: TimeInterval = 30 * 60
    static let lineageMinWalks = 3

    struct Coordinate: Equatable {
        let latitude: Double
        let longitude: Double
    }

    struct RouteFix: Equatable {
        let coordinate: Coordinate
        let horizontalAccuracy: Double
        let gapSeconds: TimeInterval
    }

    struct ElevationSample: Equatable {
        let timestamp: Date
        let altitude: Double
    }

    struct PhotoPin: Equatable {
        let capturedAt: Date
        let coordinate: Coordinate?
    }

    struct CurrentRecording {
        let uuid: UUID
        let start: Date
        let end: Date
        let text: String
        let wordCount: Int
        let themes: [Theme]
    }

    struct WalkSnapshotRow: Equatable {
        let walkUUID: UUID
        let startDate: Date
        let intention: String?
        let weatherCondition: String?
    }

    struct MoonInput {
        let lunationIndex: Int
        let moonName: String
        let start: Date
        let end: Date
        let lastReportedIndex: Int?
        let currentWalkHasWords: Bool
        let allWalkDates: [Date]
        let wordedWalkDates: [Date]
    }

    struct Input {
        let currentWalkUUID: UUID
        let walkStart: Date
        let walkEnd: Date
        let totalAscent: Double
        let elevationSeries: [ElevationSample]
        let photos: [PhotoPin]
        let currentRecordings: [CurrentRecording]
        let threads: [WalkThread]
        let backfillComplete: Bool
        let walkSnapshots: [WalkSnapshotRow]
        let historyTranscripts: [(recordingUUID: UUID, transcript: String)]
        let recordingTimestamps: [UUID: Date]
        let walkIndex: [UUID: (walkUUID: UUID, date: Date)]
        let fixes: [UUID: RouteFix]
        let moon: MoonInput?
    }

    struct SenseLine: Equatable {
        let text: String
        let lemma: String?
    }

    struct Output: Equatable {
        let lines: [String]
        let reportedLunationIndex: Int?
    }

    /// Declaration order IS the spec's binding priority order — reordering
    /// cases reorders the block.
    enum Sense: CaseIterable {
        case placeResonance, moonLine, markerColoring, intentionLineage,
             climbAnchoring, weatherWeave, photoAdjacency, questionDensity,
             speechShape
    }

    /// `evaluate` is a test seam (same style as ThreadsBackfill's
    /// `snapshotProvider`); production callers use the default dispatch.
    static func lines(
        input: Input,
        evaluate: (Sense, Input, Set<String>) -> SenseLine? = { DossierSenses.evaluate($0, input: $1, suppressed: $2) }
    ) -> Output {
        var used = Set<String>()
        var lines: [String] = []
        var reportedLunationIndex: Int?
        for sense in Sense.allCases {
            guard lines.count < lineCap else { break }
            guard let line = evaluate(sense, input, used) else { continue }
            // Belt over the senses' own suppression: a theme named at a
            // higher rank never reappears, whatever a sense returns.
            if let lemma = line.lemma {
                guard !used.contains(lemma) else { continue }
                used.insert(lemma)
            }
            lines.append(line.text)
            if sense == .moonLine {
                reportedLunationIndex = input.moon?.lunationIndex
            }
        }
        return Output(lines: lines, reportedLunationIndex: reportedLunationIndex)
    }

    static func evaluate(_ sense: Sense, input: Input, suppressed: Set<String>) -> SenseLine? {
        switch sense {
        case .placeResonance: return placeResonance(input: input, suppressed: suppressed)
        case .moonLine: return moonLine(input: input, suppressed: suppressed)
        case .markerColoring: return markerColoring(input: input, suppressed: suppressed)
        case .intentionLineage: return intentionLineage(input: input, suppressed: suppressed)
        case .climbAnchoring: return climbAnchoring(input: input, suppressed: suppressed)
        case .weatherWeave: return weatherWeave(input: input, suppressed: suppressed)
        case .photoAdjacency: return photoAdjacency(input: input, suppressed: suppressed)
        case .questionDensity: return questionDensity(input: input, suppressed: suppressed)
        case .speechShape: return speechShape(input: input, suppressed: suppressed)
        }
    }
}

// MARK: - Shared helpers

extension DossierSenses {

    /// Threads with an appearance on the current walk, in the dossier thread
    /// section's own order (ThreadStore.build sorts by lemma).
    static func activeThreads(in input: Input) -> [WalkThread] {
        input.threads.filter { thread in
            thread.appearances.contains { $0.walkUUID == input.currentWalkUUID }
        }
    }

    static func qualifies(_ fix: RouteFix) -> Bool {
        fix.gapSeconds <= hygieneMaxGap && fix.horizontalAccuracy < hygieneMaxAccuracy
    }

    static func distance(_ a: Coordinate, _ b: Coordinate) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    private static let spelledSmall = [
        3: "three", 4: "four", 5: "five", 6: "six", 7: "seven", 8: "eight", 9: "nine"
    ]
    private static let ordinalWords = [
        3: "Third", 4: "Fourth", 5: "Fifth", 6: "Sixth", 7: "Seventh",
        8: "Eighth", 9: "Ninth", 10: "Tenth", 11: "Eleventh", 12: "Twelfth"
    ]

    static func timesPhrase(_ n: Int) -> String {
        if n == 2 { return "twice" }
        if let word = spelledSmall[n] { return "\(word) times" }
        return "\(n) times"
    }

    static func capitalizedCount(_ n: Int) -> String {
        spelledSmall[n]?.capitalized ?? "\(n)"
    }

    static func ordinalWord(_ n: Int) -> String {
        if let word = ordinalWords[n] { return word }
        if (11...13).contains(n % 100) { return "\(n)th" }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }
}

```

And create `Pilgrim/Models/Threads/DossierSensesTracks.swift` with the stub set (Tasks 2-8 replace these one track at a time). **A stub traps, it doesn't fake silence:** Task 1's own engine tests (above) exercise the cap/priority/dedup engine exclusively through the `evaluate:` seam with synthetic `stub(firing:)` closures — they never call `placeResonance`/`moonLine`/etc. directly, so nothing in this file's own suite depends on what these nine functions return. Every later task's tests DO call their two or three sense functions directly, including `doesNotFire`/suppression tests that assert `XCTAssertNil(...)`. If the stub simply returned `nil`, every one of those negative assertions would pass vacuously before the sense is implemented — a green bar that proves nothing. `preconditionFailure` makes that impossible: calling an unimplemented sense traps the process, so a negative assertion can only pass once the real implementation deliberately returns `nil`:

```swift
import Foundation
import CoreLocation

extension DossierSenses {

    static func placeResonance(input: Input, suppressed: Set<String>) -> SenseLine? {
        preconditionFailure("unimplemented sense")
    }

    static func moonLine(input: Input, suppressed: Set<String>) -> SenseLine? {
        preconditionFailure("unimplemented sense")
    }

    static func markerColoring(input: Input, suppressed: Set<String>) -> SenseLine? {
        preconditionFailure("unimplemented sense")
    }

    static func intentionLineage(input: Input, suppressed: Set<String>) -> SenseLine? {
        preconditionFailure("unimplemented sense")
    }

    static func climbAnchoring(input: Input, suppressed: Set<String>) -> SenseLine? {
        preconditionFailure("unimplemented sense")
    }

    static func weatherWeave(input: Input, suppressed: Set<String>) -> SenseLine? {
        preconditionFailure("unimplemented sense")
    }

    static func photoAdjacency(input: Input, suppressed: Set<String>) -> SenseLine? {
        preconditionFailure("unimplemented sense")
    }

    static func questionDensity(input: Input, suppressed: Set<String>) -> SenseLine? {
        preconditionFailure("unimplemented sense")
    }

    static func speechShape(input: Input, suppressed: Set<String>) -> SenseLine? {
        preconditionFailure("unimplemented sense")
    }
}
```

Register all three files in the pbxproj (4 entries each), `plutil -lint`, run the class: expected **TEST SUCCEEDED**, 9 tests (none of Task 1's own tests call the nine sense functions directly, so the trap never fires here).

**Step 3 — verify + commit.** Full build; full suite (expect 1284 + 9 = 1293 via grep); `swiftlint 2>&1 | tail -3` (398/0, zero new).
Commit: `feat(threads): the senses get a spine — cap, priority, one theme one line`

### Task 2: Climb anchoring + speech shape (pure, current walk)

**Files:**
- Modify: `Pilgrim/Models/Threads/DossierSensesTracks.swift` — replace the `climbAnchoring` and `speechShape` stubs; add `smoothedAltitudes`, `steepestSustainedAscent`, `AscentRun`.
- Modify: `UnitTests/DossierSensesTests.swift` — add fixtures + tests.

**Step 1 — RED.** Add to `DossierSensesTests`:

```swift
    // MARK: - Climb anchoring fixtures

    func thread(lemma: String, display: String? = nil, appearances: [ThreadAppearance]) -> WalkThread {
        WalkThread(lemma: lemma, displayTerm: display ?? lemma, appearances: appearances)
    }

    func appearance(recording: UUID = UUID(), walk: UUID, date: Date, mentions: Int = 2) -> ThreadAppearance {
        ThreadAppearance(recordingUUID: recording, walkUUID: walk, date: date,
                         mentionCount: mentions, salience: 0.02)
    }

    func currentRecording(
        uuid: UUID = UUID(), start: Date, end: Date, text: String = "words",
        wordCount: Int = 40, themeLemmas: [String] = []
    ) -> DossierSenses.CurrentRecording {
        DossierSenses.CurrentRecording(
            uuid: uuid, start: start, end: end, text: text, wordCount: wordCount,
            themes: themeLemmas.map {
                Theme(lemma: $0, displayTerm: $0, mentionCount: 2, salience: 0.05,
                      mentions: [ThemeMention(start: 0, length: 4)])
            }
        )
    }

    /// 40 min of flat, 10 min climbing 60 m, 40 min flat — one unmistakable
    /// steepest sustained ascent in the middle.
    func hillSeries(start: Date) -> [DossierSenses.ElevationSample] {
        var samples: [DossierSenses.ElevationSample] = []
        for i in 0..<240 {  // 10 s cadence, 40 min
            samples.append(.init(timestamp: start.addingTimeInterval(Double(i) * 10), altitude: 100))
        }
        for i in 0..<60 {   // 10 min, +1 m per 10 s
            samples.append(.init(timestamp: start.addingTimeInterval(2400 + Double(i) * 10),
                                 altitude: 100 + Double(i)))
        }
        for i in 0..<240 {
            samples.append(.init(timestamp: start.addingTimeInterval(3000 + Double(i) * 10), altitude: 160))
        }
        return samples
    }

    func testClimb_mentionOnSteepestClimb_fires() {
        let walkUUID = UUID()
        let recUUID = UUID()
        let start = Self.walkStart
        let input = makeInput(
            currentWalkUUID: walkUUID,
            walkEnd: start.addingTimeInterval(5400),
            totalAscent: 60,
            elevationSeries: hillSeries(start: start),
            currentRecordings: [currentRecording(
                uuid: recUUID, start: start.addingTimeInterval(2500),
                end: start.addingTimeInterval(2700), themeLemmas: ["move"]
            )],
            threads: [thread(lemma: "move", display: "the move",
                             appearances: [appearance(recording: recUUID, walk: walkUUID, date: start)])]
        )
        XCTAssertEqual(
            DossierSenses.climbAnchoring(input: input, suppressed: []),
            DossierSenses.SenseLine(text: "'the move' was spoken on the day's steepest climb.", lemma: "move")
        )
    }

    func testClimb_mentionOnTheFlat_doesNotFire() {
        let walkUUID = UUID()
        let recUUID = UUID()
        let start = Self.walkStart
        let input = makeInput(
            currentWalkUUID: walkUUID,
            walkEnd: start.addingTimeInterval(5400),
            totalAscent: 60,
            elevationSeries: hillSeries(start: start),
            currentRecordings: [currentRecording(
                uuid: recUUID, start: start.addingTimeInterval(300),
                end: start.addingTimeInterval(500), themeLemmas: ["move"]
            )],
            threads: [thread(lemma: "move",
                             appearances: [appearance(recording: recUUID, walk: walkUUID, date: start)])]
        )
        XCTAssertNil(DossierSenses.climbAnchoring(input: input, suppressed: []))
    }

    func testClimb_flatWalkUnder50mAscent_skipsEntirely() {
        let walkUUID = UUID()
        let recUUID = UUID()
        let start = Self.walkStart
        let input = makeInput(
            currentWalkUUID: walkUUID,
            totalAscent: 49,
            elevationSeries: hillSeries(start: start),
            currentRecordings: [currentRecording(
                uuid: recUUID, start: start.addingTimeInterval(2500),
                end: start.addingTimeInterval(2700), themeLemmas: ["move"]
            )],
            threads: [thread(lemma: "move",
                             appearances: [appearance(recording: recUUID, walk: walkUUID, date: start)])]
        )
        XCTAssertNil(DossierSenses.climbAnchoring(input: input, suppressed: []),
                     "total ascent < 50 m makes the claim meaningless — binding skip")
    }

    func testClimb_jitterWithoutSustainedGain_doesNotFire() {
        let walkUUID = UUID()
        let recUUID = UUID()
        let start = Self.walkStart
        // ±3 m sawtooth: raw gradients spike, smoothed sustained gain never
        // reaches 20 m — the smoothing exists exactly for this.
        let series = (0..<540).map { i in
            DossierSenses.ElevationSample(
                timestamp: start.addingTimeInterval(Double(i) * 10),
                altitude: 100 + Double(i % 2) * 3
            )
        }
        let input = makeInput(
            currentWalkUUID: walkUUID,
            totalAscent: 60,
            elevationSeries: series,
            currentRecordings: [currentRecording(
                uuid: recUUID, start: start.addingTimeInterval(2500),
                end: start.addingTimeInterval(2700), themeLemmas: ["move"]
            )],
            threads: [thread(lemma: "move",
                             appearances: [appearance(recording: recUUID, walk: walkUUID, date: start)])]
        )
        XCTAssertNil(DossierSenses.climbAnchoring(input: input, suppressed: []))
    }

    func testClimb_suppressedTheme_fallsThroughToNextTheme() {
        let walkUUID = UUID()
        let recA = UUID(), recB = UUID()
        let start = Self.walkStart
        let input = makeInput(
            currentWalkUUID: walkUUID,
            walkEnd: start.addingTimeInterval(5400),
            totalAscent: 60,
            elevationSeries: hillSeries(start: start),
            currentRecordings: [
                currentRecording(uuid: recA, start: start.addingTimeInterval(2500),
                                 end: start.addingTimeInterval(2600), themeLemmas: ["move"]),
                currentRecording(uuid: recB, start: start.addingTimeInterval(2600),
                                 end: start.addingTimeInterval(2700), themeLemmas: ["river"])
            ],
            threads: [
                thread(lemma: "move", appearances: [appearance(recording: recA, walk: walkUUID, date: start)]),
                thread(lemma: "river", appearances: [appearance(recording: recB, walk: walkUUID, date: start)])
            ]
        )
        let line = DossierSenses.climbAnchoring(input: input, suppressed: ["move"])
        XCTAssertEqual(line?.lemma, "river")
    }

    // MARK: - Speech shape

    func testSpeechShape_wordsInFirstThird_longWordlessRemainder_fires() {
        let start = Self.walkStart
        let end = start.addingTimeInterval(7200)  // 2 h walk; first third ends at 40 min
        let input = makeInput(
            walkStart: start, walkEnd: end,
            currentRecordings: [
                currentRecording(start: start.addingTimeInterval(300), end: start.addingTimeInterval(600)),
                currentRecording(start: start.addingTimeInterval(1200), end: start.addingTimeInterval(1500))
            ]
        )
        XCTAssertEqual(
            DossierSenses.speechShape(input: input, suppressed: []),
            DossierSenses.SenseLine(
                text: "All the words came in the first third; the last 95 minutes were wordless.",
                lemma: nil
            )
        )
    }

    func testSpeechShape_lateRecording_doesNotFire() {
        let start = Self.walkStart
        let end = start.addingTimeInterval(7200)
        let input = makeInput(
            walkStart: start, walkEnd: end,
            currentRecordings: [
                currentRecording(start: start.addingTimeInterval(300), end: start.addingTimeInterval(600)),
                currentRecording(start: start.addingTimeInterval(3000), end: start.addingTimeInterval(3300))
            ]
        )
        XCTAssertNil(DossierSenses.speechShape(input: input, suppressed: []))
    }

    func testSpeechShape_shortWordlessRemainder_doesNotFire() {
        let start = Self.walkStart
        let end = start.addingTimeInterval(2700)  // 45 min walk
        let input = makeInput(
            walkStart: start, walkEnd: end,
            currentRecordings: [
                currentRecording(start: start.addingTimeInterval(60), end: start.addingTimeInterval(900))
            ]
        )
        XCTAssertNil(DossierSenses.speechShape(input: input, suppressed: []),
                     "1800 s remainder must EXCEED 30 minutes, not merely reach it")
    }

    func testSpeechShape_wordlessRecordings_doNotAnchorTheClaim() {
        let start = Self.walkStart
        let end = start.addingTimeInterval(7200)
        let input = makeInput(
            walkStart: start, walkEnd: end,
            currentRecordings: [
                currentRecording(start: start.addingTimeInterval(300), end: start.addingTimeInterval(600)),
                currentRecording(start: start.addingTimeInterval(5000), end: start.addingTimeInterval(5100),
                                 wordCount: 0)
            ]
        )
        XCTAssertNotNil(DossierSenses.speechShape(input: input, suppressed: []),
                        "a zero-word recording is not words — it cannot break the first-third claim")
    }
```

Run the class: expected — the process traps on the first `climbAnchoring`/`speechShape` call via the `preconditionFailure("unimplemented sense")` stub (RED; every climb and speech test, including the `doesNotFire` ones, is genuinely red — none can pass against a stub that crashes instead of returning `nil`).

**Step 2 — GREEN.** Replace the two stubs in `DossierSenses.swift`:

```swift
// MARK: - Track 3: climb anchoring (current walk)

extension DossierSenses {

    struct AscentRun: Equatable {
        let start: Date
        let end: Date
        let gain: Double
        let averageRate: Double
    }

    static func climbAnchoring(input: Input, suppressed: Set<String>) -> SenseLine? {
        guard input.totalAscent >= climbMinTotalAscent,
              let run = steepestSustainedAscent(in: input.elevationSeries) else { return nil }
        for thread in activeThreads(in: input) where !suppressed.contains(thread.lemma) {
            let onClimb = input.currentRecordings.contains { recording in
                recording.themes.contains { $0.lemma == thread.lemma }
                    && recording.start <= run.end && recording.end >= run.start
            }
            if onClimb {
                return SenseLine(
                    text: "'\(thread.displayTerm)' was spoken on the day's steepest climb.",
                    lemma: thread.lemma
                )
            }
        }
        return nil
    }

    /// Centered moving average — raw GPS elevation is noisy per sample and
    /// unsmoothed gradients false-positive on jitter (spec Track 3).
    static func smoothedAltitudes(_ series: [ElevationSample]) -> [ElevationSample] {
        let half = climbSmoothingWindow / 2
        return series.indices.map { i in
            let lo = max(0, i - half)
            let hi = min(series.count - 1, i + half)
            let mean = series[lo...hi].map(\.altitude).reduce(0, +) / Double(hi - lo + 1)
            return ElevationSample(timestamp: series[i].timestamp, altitude: mean)
        }
    }

    /// The maximal-average-rate contiguous run of top-decile positive climb
    /// rates gaining ≥20 m. Rate is over time (m/s) — the series carries no
    /// distance, and "steepest" stays deterministic without one.
    static func steepestSustainedAscent(in series: [ElevationSample]) -> AscentRun? {
        let smoothed = smoothedAltitudes(series)
        guard smoothed.count > 1 else { return nil }
        var segments: [(start: Int, end: Int, rate: Double)] = []
        for i in 1..<smoothed.count {
            let dt = smoothed[i].timestamp.timeIntervalSince(smoothed[i - 1].timestamp)
            guard dt > 0 else { continue }
            segments.append((i - 1, i, (smoothed[i].altitude - smoothed[i - 1].altitude) / dt))
        }
        let positive = segments.map(\.rate).filter { $0 > 0 }.sorted()
        guard !positive.isEmpty else { return nil }
        let threshold = positive[Int(Double(positive.count - 1) * climbTopDecile)]
        var best: AscentRun?
        var runStartIndex: Int?
        func closeRun(endingAt segmentIndex: Int) {
            guard let startSegment = runStartIndex else { return }
            runStartIndex = nil
            let startSample = segments[startSegment].start
            let endSample = segments[segmentIndex].end
            let gain = smoothed[endSample].altitude - smoothed[startSample].altitude
            let duration = smoothed[endSample].timestamp.timeIntervalSince(smoothed[startSample].timestamp)
            guard gain >= climbMinRunGain, duration > 0 else { return }
            let run = AscentRun(
                start: smoothed[startSample].timestamp,
                end: smoothed[endSample].timestamp,
                gain: gain,
                averageRate: gain / duration
            )
            if best == nil || run.averageRate > best!.averageRate {
                best = run
            }
        }
        for (index, segment) in segments.enumerated() {
            if segment.rate >= threshold && segment.rate > 0 {
                if runStartIndex == nil { runStartIndex = index }
                if index == segments.count - 1 { closeRun(endingAt: index) }
            } else if runStartIndex != nil {
                closeRun(endingAt: index - 1)
            }
        }
        return best
    }
}

// MARK: - Track 4: speech shape (current walk)

extension DossierSenses {

    static func speechShape(input: Input, suppressed: Set<String>) -> SenseLine? {
        let worded = input.currentRecordings.filter { $0.wordCount > 0 }
        guard !worded.isEmpty else { return nil }
        let span = input.walkEnd.timeIntervalSince(input.walkStart)
        guard span > 0 else { return nil }
        let firstThirdEnd = input.walkStart.addingTimeInterval(span / 3)
        guard worded.allSatisfy({ $0.end <= firstThirdEnd }),
              let lastEnd = worded.map(\.end).max() else { return nil }
        let remainder = input.walkEnd.timeIntervalSince(lastEnd)
        guard remainder > speechShapeMinWordlessRemainder else { return nil }
        let minutes = Int(remainder / 60)
        return SenseLine(
            text: "All the words came in the first third; the last \(minutes) minutes were wordless.",
            lemma: nil
        )
    }
}
```

Delete the two corresponding stubs from `DossierSensesTracks.swift`'s stub extension. Run the class: **TEST SUCCEEDED** (18 tests).

**Step 3 — verify + commit.** Full build; full suite (expect 1293 + 9 = 1302); lint.
Commit: `feat(threads): the dossier feels the hill and hears the silence`

### Task 3: Theme-marker coloring + photo adjacency (pure, current walk)

**Files:**
- Modify: `Pilgrim/Models/Threads/TranscriptNLP.swift` — add `WordToken` + `wordTokenOffsets(in:)` beside `wordTokens` (single-tokenizer rule: one splitting semantics, one denominator).
- Modify: `Pilgrim/Models/Threads/DossierSensesTracks.swift` — replace `markerColoring` and `photoAdjacency` stubs.
- Modify: `UnitTests/DossierSensesTests.swift` — tests.

**Step 1 — RED.** Add to `DossierSensesTests`:

```swift
    // MARK: - Tokenizer parity

    func testWordTokenOffsets_matchesWordTokensExactly() {
        let text = "Don't stop — the move MUST happen, always... whole-hearted?"
        XCTAssertEqual(TranscriptNLP.wordTokenOffsets(in: text).map(\.token),
                       TranscriptNLP.wordTokens(in: text),
                       "two tokenizers means diverging denominators — offsets must ride the same split")
    }

    func testWordTokenOffsets_matchesWordTokensExactly_combiningDiacritic() {
        // "café" written as base "e" + a combining acute accent (U+0301) —
        // one Swift `Character`, two Unicode scalars. A per-Character
        // all-scalars-are-letters check would treat the whole grapheme as
        // non-letter and drop it; a single shared tokenizer cannot.
        let text = "walking near the cafe\u{0301} today"
        XCTAssertEqual(TranscriptNLP.wordTokenOffsets(in: text).map(\.token),
                       TranscriptNLP.wordTokens(in: text),
                       "a combining-mark word must tokenize identically in both — one tokenizer, no exceptions")
    }

    // MARK: - Theme-marker coloring

    /// "move" at offsets with absolutist words packed around it; two more
    /// absolutist words sit far outside the mention windows (the last two
    /// repeats of the filler) so the "rest of the walk" has a nonzero
    /// denominator — the ordinary vs-rest branch.
    private var coloredTranscript: String {
        let prefix = "the move must always happen and everything about the move is completely certain now "
        let neutralFiller = "walking along the river path watching herons drift over quiet water today "
        let distantAbsolutist = "walking along the river path watching herons drift over quiet water always "
        return prefix + String(repeating: neutralFiller, count: 4) + String(repeating: distantAbsolutist, count: 2)
    }

    /// Same clustering, but every absolutist word in the transcript sits
    /// inside the mention windows — the rest of the walk holds none, so the
    /// ratio falls back to vs-overall density (spec: an under-claim, never
    /// an overstatement).
    private var coloredTranscriptNoRestAbsolutist: String {
        "the move must always happen and everything about the move is completely certain now " +
        String(repeating: "walking along the river path watching herons drift over quiet water today ", count: 6)
    }

    private func mentionOffsets(of word: String, in text: String) -> [ThemeMention] {
        var mentions: [ThemeMention] = []
        var search = text.startIndex
        while let range = text.range(of: word, range: search..<text.endIndex) {
            mentions.append(ThemeMention(start: text.distance(from: text.startIndex, to: range.lowerBound),
                                         length: word.count))
            search = range.upperBound
        }
        return mentions
    }

    func testMarkerColoring_clusteredAbsolutistWords_fire() {
        let text = coloredTranscript
        let theme = Theme(lemma: "move", displayTerm: "the move", mentionCount: 2, salience: 0.05,
                          mentions: mentionOffsets(of: "move", in: text))
        XCTAssertEqual(
            DossierSenses.markerLine(theme: theme, displayTerm: "the move", text: text),
            "Absolutist words cluster around 'the move' — four times the density of the rest of the walk's speech."
        )
    }

    func testMarkerColoring_restHoldsNoAbsolutistWords_fallsBackToVsOverallRatio() {
        let text = coloredTranscriptNoRestAbsolutist
        let theme = Theme(lemma: "move", displayTerm: "the move", mentionCount: 2, salience: 0.05,
                          mentions: mentionOffsets(of: "move", in: text))
        XCTAssertEqual(
            DossierSenses.markerLine(theme: theme, displayTerm: "the move", text: text),
            "Absolutist words cluster around 'the move' — three times the density of the rest of the walk's speech.",
            "the rest of the walk holds zero absolutist words — the ratio falls back to vs-overall density"
        )
    }

    func testMarkerColoring_fewerThanThreeAbsolutistTokensInWindows_doesNotFire() {
        let text = "the move must happen soon " +
            String(repeating: "walking along the river path watching herons drift over quiet water ", count: 6)
        let theme = Theme(lemma: "move", displayTerm: "the move", mentionCount: 1, salience: 0.02,
                          mentions: mentionOffsets(of: "move", in: text))
        XCTAssertNil(DossierSenses.markerLine(theme: theme, displayTerm: "the move", text: text),
                     "≥3 absolutist tokens in windows is a binding floor")
    }

    func testMarkerColoring_uniformAbsolutistSpread_doesNotFire() {
        let text = String(repeating: "every path always leads somewhere and the move waits completely still ", count: 8)
        let theme = Theme(lemma: "move", displayTerm: "the move", mentionCount: 8, salience: 0.1,
                          mentions: mentionOffsets(of: "move", in: text))
        XCTAssertNil(DossierSenses.markerLine(theme: theme, displayTerm: "the move", text: text),
                     "uniform density can never reach 2× overall — no clustering, no claim")
    }

    func testMarkerColoring_viaSense_usesActiveThreadOrderAndSuppression() {
        let walkUUID = UUID()
        let recUUID = UUID()
        let text = coloredTranscript
        let recording = DossierSenses.CurrentRecording(
            uuid: recUUID, start: Self.walkStart, end: Self.walkStart.addingTimeInterval(120),
            text: text, wordCount: TranscriptNLP.wordCount(in: text),
            themes: [Theme(lemma: "move", displayTerm: "the move", mentionCount: 2, salience: 0.05,
                           mentions: mentionOffsets(of: "move", in: text))]
        )
        let input = makeInput(
            currentWalkUUID: walkUUID,
            currentRecordings: [recording],
            threads: [thread(lemma: "move", display: "the move",
                             appearances: [appearance(recording: recUUID, walk: walkUUID, date: Self.walkStart)])]
        )
        XCTAssertEqual(DossierSenses.markerColoring(input: input, suppressed: [])?.lemma, "move")
        XCTAssertNil(DossierSenses.markerColoring(input: input, suppressed: ["move"]))
    }

    // MARK: - Photo adjacency

    func testPhotoAdjacency_nearAndSoon_fires() {
        let walkUUID = UUID()
        let recUUID = UUID()
        let input = makeInput(
            currentWalkUUID: walkUUID,
            photos: [.init(capturedAt: Self.walkStart.addingTimeInterval(400),
                           coordinate: .init(latitude: 42.87825, longitude: -8.5448))],
            currentRecordings: [currentRecording(uuid: recUUID, start: Self.walkStart,
                                                 end: Self.walkStart.addingTimeInterval(120),
                                                 themeLemmas: ["music"])],
            threads: [thread(lemma: "music",
                             appearances: [appearance(recording: recUUID, walk: walkUUID, date: Self.walkStart)])],
            fixes: [recUUID: fix(lat: 42.8782, lon: -8.5448)]
        )
        XCTAssertEqual(
            DossierSenses.photoAdjacency(input: input, suppressed: []),
            DossierSenses.SenseLine(text: "A photo was taken near where 'music' was spoken.", lemma: "music")
        )
    }

    func testPhotoAdjacency_nearButLate_doesNotFire() {
        let walkUUID = UUID()
        let recUUID = UUID()
        let input = makeInput(
            currentWalkUUID: walkUUID,
            photos: [.init(capturedAt: Self.walkStart.addingTimeInterval(800),
                           coordinate: .init(latitude: 42.87825, longitude: -8.5448))],
            currentRecordings: [currentRecording(uuid: recUUID, start: Self.walkStart,
                                                 end: Self.walkStart.addingTimeInterval(120),
                                                 themeLemmas: ["music"])],
            threads: [thread(lemma: "music",
                             appearances: [appearance(recording: recUUID, walk: walkUUID, date: Self.walkStart)])],
            fixes: [recUUID: fix(lat: 42.8782, lon: -8.5448)]
        )
        XCTAssertNil(DossierSenses.photoAdjacency(input: input, suppressed: []),
                     "680 s after the recording ended exceeds the 10-minute tie")
    }

    func testPhotoAdjacency_soonButFar_doesNotFire() {
        let walkUUID = UUID()
        let recUUID = UUID()
        let input = makeInput(
            currentWalkUUID: walkUUID,
            photos: [.init(capturedAt: Self.walkStart.addingTimeInterval(60),
                           coordinate: .init(latitude: 42.8792, longitude: -8.5448))],  // ~111 m north
            currentRecordings: [currentRecording(uuid: recUUID, start: Self.walkStart,
                                                 end: Self.walkStart.addingTimeInterval(120),
                                                 themeLemmas: ["music"])],
            threads: [thread(lemma: "music",
                             appearances: [appearance(recording: recUUID, walk: walkUUID, date: Self.walkStart)])],
            fixes: [recUUID: fix(lat: 42.8782, lon: -8.5448)]
        )
        XCTAssertNil(DossierSenses.photoAdjacency(input: input, suppressed: []))
    }

    func testPhotoAdjacency_recordingFailingHygiene_doesNotParticipate() {
        let walkUUID = UUID()
        let recUUID = UUID()
        let input = makeInput(
            currentWalkUUID: walkUUID,
            photos: [.init(capturedAt: Self.walkStart.addingTimeInterval(60),
                           coordinate: .init(latitude: 42.8782, longitude: -8.5448))],
            currentRecordings: [currentRecording(uuid: recUUID, start: Self.walkStart,
                                                 end: Self.walkStart.addingTimeInterval(120),
                                                 themeLemmas: ["music"])],
            threads: [thread(lemma: "music",
                             appearances: [appearance(recording: recUUID, walk: walkUUID, date: Self.walkStart)])],
            fixes: [recUUID: fix(lat: 42.8782, lon: -8.5448, accuracy: 150)]
        )
        XCTAssertNil(DossierSenses.photoAdjacency(input: input, suppressed: []))
    }

    func testPhotoAdjacency_photoWithoutCoordinate_doesNotParticipate() {
        let walkUUID = UUID()
        let recUUID = UUID()
        let input = makeInput(
            currentWalkUUID: walkUUID,
            photos: [.init(capturedAt: Self.walkStart.addingTimeInterval(60), coordinate: nil)],
            currentRecordings: [currentRecording(uuid: recUUID, start: Self.walkStart,
                                                 end: Self.walkStart.addingTimeInterval(120),
                                                 themeLemmas: ["music"])],
            threads: [thread(lemma: "music",
                             appearances: [appearance(recording: recUUID, walk: walkUUID, date: Self.walkStart)])],
            fixes: [recUUID: fix(lat: 42.8782, lon: -8.5448)]
        )
        XCTAssertNil(DossierSenses.photoAdjacency(input: input, suppressed: []))
    }
```

Run: expected build failure — `wordTokenOffsets` and `markerLine` don't exist yet (compile RED). (Once Step 2 adds them, `markerColoring`/`photoAdjacency` would still trap via `preconditionFailure("unimplemented sense")` until the same step replaces the stubs — compile failure is what RED looks like here, not a runtime nil.)

**Step 2 — GREEN.** In `TranscriptNLP.swift`, below `wordCount(in:)`:

```swift
    struct WordToken: Equatable {
        let token: String
        let start: Int
    }

    /// Offsets for `wordTokens`' own output — not a second tokenizer. A
    /// separate letters-only scan (even a careful one) can still diverge from
    /// `components(separatedBy:)` on a grapheme that mixes scalar classes
    /// (a base letter plus a combining mark): the two would draw the split
    /// in different places. Sourcing the token list directly from
    /// `wordTokens` and locating each one by forward search makes the token
    /// TEXT identical by construction — there is exactly one tokenizer, and
    /// this just remembers where its output came from (the offsets
    /// `contentLemmaMentions` also measures in: `String.distance`, Character
    /// count).
    static func wordTokenOffsets(in text: String) -> [WordToken] {
        let lowered = text.lowercased()
        var tokens: [WordToken] = []
        var cursor = lowered.startIndex
        for token in wordTokens(in: text) {
            guard let range = lowered.range(of: token, range: cursor..<lowered.endIndex) else { continue }
            tokens.append(WordToken(
                token: token,
                start: lowered.distance(from: lowered.startIndex, to: range.lowerBound)
            ))
            cursor = range.upperBound
        }
        return tokens
    }
```

In `DossierSensesTracks.swift`, replace the two stubs:

```swift
// MARK: - Track 4: theme-marker coloring (current walk)

extension DossierSenses {

    static func markerColoring(input: Input, suppressed: Set<String>) -> SenseLine? {
        for thread in activeThreads(in: input) where !suppressed.contains(thread.lemma) {
            for recording in input.currentRecordings {
                guard let theme = recording.themes.first(where: { $0.lemma == thread.lemma }),
                      let text = markerLine(theme: theme, displayTerm: thread.displayTerm,
                                            text: recording.text) else { continue }
                return SenseLine(text: text, lemma: thread.lemma)
            }
        }
        return nil
    }

    static func markerLine(theme: Theme, displayTerm: String, text: String) -> String? {
        let tokens = TranscriptNLP.wordTokenOffsets(in: text)
        guard !tokens.isEmpty else { return nil }
        var windowIndices = IndexSet()
        for mention in theme.mentions {
            guard let index = tokens.lastIndex(where: { $0.start <= mention.start }) else { continue }
            windowIndices.insert(
                integersIn: max(0, index - markerWindowRadius)...min(tokens.count - 1, index + markerWindowRadius)
            )
        }
        guard !windowIndices.isEmpty else { return nil }
        let windowTokens = windowIndices.map { tokens[$0].token }
        let windowAbsolutist = windowTokens.filter { MarkerLexicons.absolutist.contains($0) }.count
        guard windowAbsolutist >= markerMinWindowAbsolutist else { return nil }
        let totalAbsolutist = tokens.filter { MarkerLexicons.absolutist.contains($0.token) }.count
        let windowDensity = Double(windowAbsolutist) / Double(windowTokens.count)
        let overallDensity = Double(totalAbsolutist) / Double(tokens.count)
        guard overallDensity > 0, windowDensity >= markerMinDensityRatio * overallDensity else { return nil }
        let restTokenCount = tokens.count - windowTokens.count
        let restAbsolutist = totalAbsolutist - windowAbsolutist
        let restDensity = restTokenCount > 0 ? Double(restAbsolutist) / Double(restTokenCount) : 0
        // Vs-rest ratio matches the line's own claim; when the rest holds no
        // absolutist words at all, the vs-overall ratio under-claims — a
        // descriptive line may understate, never overstate.
        let ratio = restDensity > 0 ? windowDensity / restDensity : windowDensity / overallDensity
        return "Absolutist words cluster around '\(displayTerm)' — \(timesPhrase(Int(ratio))) the density of the rest of the walk's speech."
    }
}

// MARK: - Track 4: photo adjacency (current walk, place-tied)

extension DossierSenses {

    static func photoAdjacency(input: Input, suppressed: Set<String>) -> SenseLine? {
        let placedPhotos = input.photos.compactMap { photo -> (capturedAt: Date, coordinate: Coordinate)? in
            photo.coordinate.map { (photo.capturedAt, $0) }
        }
        guard !placedPhotos.isEmpty else { return nil }
        var best: (distance: CLLocationDistance, gap: TimeInterval, capturedAt: Date,
                   lemma: String, displayTerm: String)?
        for thread in activeThreads(in: input) where !suppressed.contains(thread.lemma) {
            for recording in input.currentRecordings
            where recording.themes.contains(where: { $0.lemma == thread.lemma }) {
                guard let fix = input.fixes[recording.uuid], qualifies(fix) else { continue }
                for photo in placedPhotos {
                    let separation = distance(fix.coordinate, photo.coordinate)
                    guard separation <= photoTieRadius else { continue }
                    let gap = intervalGap(photo.capturedAt, start: recording.start, end: recording.end)
                    guard gap <= photoTieMaxInterval else { continue }
                    // Place first, time second, then capture order — the tie
                    // is about ground shared, not clocks.
                    if best == nil
                        || (separation, gap, photo.capturedAt) < (best!.distance, best!.gap, best!.capturedAt) {
                        best = (separation, gap, photo.capturedAt, thread.lemma, thread.displayTerm)
                    }
                }
            }
        }
        guard let best else { return nil }
        return SenseLine(text: "A photo was taken near where '\(best.displayTerm)' was spoken.",
                         lemma: best.lemma)
    }

    static func intervalGap(_ instant: Date, start: Date, end: Date) -> TimeInterval {
        if instant >= start && instant <= end { return 0 }
        return min(abs(instant.timeIntervalSince(start)), abs(instant.timeIntervalSince(end)))
    }
}
```

Run the class: **TEST SUCCEEDED** (30 tests).

**Step 3 — verify + commit.** Full build; full suite (expect 1302 + 12 = 1314); lint (zero new; check `DossierSensesTracks.swift` stays under 500 lines).
Commit: `feat(threads): absolutist words show their neighborhood; the camera meets the words`

---

## Stage B — data-layer fetch extensions

### Task 4: Per-recording timestamp index, bounded route-fix query, in-window walk/transcript snapshots

**Files:**
- Modify: `Pilgrim/Models/Data/DataManager+VoiceRecording.swift` — add `voiceRecordingTimestampIndex()`; widen `transcribedRecordingsSnapshot` with an optional date range; promote `rowUUID` from `private` to internal (Query needs it; the discipline is a house rule, not a file secret).
- Modify: `Pilgrim/Models/Data/DataManager+Query.swift` — add `routeFixNear(timestamp:)` and `walkSensesSnapshot(from:to:)`.
- Modify: `UnitTests/VoiceRecordingPersistenceTests.swift` — extend the existing snapshot-query section (same stack swap-and-restore pattern already in the file).

**Interfaces produced:**
- `DataManager.voiceRecordingTimestampIndex() -> [UUID: Date]` (@MainActor)
- `DataManager.transcribedRecordingsSnapshot(in range: ClosedRange<Date>? = nil) -> [(uuid: UUID, transcript: String)]` (@MainActor; default nil preserves every existing caller)
- `DataManager.routeFixNear(timestamp: Date) -> DossierSenses.RouteFix?` (any thread; `threadSafeSyncReturn` main-hop, the `queryExistingHealthUUIDs` pattern — the detached builder calls it lazily)
- `DataManager.walkSensesSnapshot(from: Date, to: Date) -> [DossierSenses.WalkSnapshotRow]` (@MainActor)

**Step 1 — RED.** Extend `VoiceRecordingPersistenceTests` (its `seedRecording` helper gains optional `startDate:` and route-sample/comment/weather seeding; keep the existing signature defaults so current tests stand):

```swift
    private func seedWalk(
        uuid: UUID = UUID(), startDate: Date, comment: String? = nil,
        weatherCondition: String? = nil,
        routeSamples: [(timestamp: Date, lat: Double, lon: Double, accuracy: Double)] = []
    ) throws {
        try stack.perform(synchronous: { transaction in
            let walk = transaction.create(Into<Walk>())
            walk._uuid .= uuid
            walk._workoutType .= .walking
            walk._startDate .= startDate
            walk._endDate .= startDate.addingTimeInterval(1800)
            walk._distance .= 1000
            walk._activeDuration .= 1800
            walk._pauseDuration .= 0
            walk._talkDuration .= 0
            walk._meditateDuration .= 0
            walk._ascend .= 0
            walk._descend .= 0
            walk._isRace .= false
            walk._isUserModified .= false
            walk._finishedRecording .= true
            walk._dayIdentifier .= "20240615"
            if let comment { walk._comment .= comment }
            if let weatherCondition { walk._weatherCondition .= weatherCondition }
            for sample in routeSamples {
                let row = transaction.create(Into<RouteDataSample>())
                row._uuid .= UUID()
                row._timestamp .= sample.timestamp
                row._latitude .= sample.lat
                row._longitude .= sample.lon
                row._altitude .= 100
                row._horizontalAccuracy .= sample.accuracy
                row._verticalAccuracy .= 5
                row._speed .= 1.2
                row._direction .= 0
                row._workout .= walk
            }
        })
    }

    @MainActor
    func test_voiceRecordingTimestampIndex_returnsRecordingStartNotWalkStart() throws {
        let previousDataStack = DataManager.dataStack
        DataManager.dataStack = stack
        defer { DataManager.dataStack = previousDataStack }

        let uuid = UUID()
        let recordingStart = Date(timeIntervalSince1970: 1_700_000_600)
        try seedRecording(uuid: uuid, startDate: recordingStart)

        let index = DataManager.voiceRecordingTimestampIndex()
        XCTAssertEqual(index[uuid], recordingStart,
                       "per-RECORDING instants — voiceRecordingWalkIndex's WALK dates cannot serve Track 1")
    }

    @MainActor
    func test_transcribedRecordingsSnapshot_rangeBoundsTheFetch() throws {
        let previousDataStack = DataManager.dataStack
        DataManager.dataStack = stack
        defer { DataManager.dataStack = previousDataStack }

        let inside = UUID(), outside = UUID()
        try seedRecording(uuid: inside, transcription: "inside the window",
                          startDate: Date(timeIntervalSince1970: 1_700_000_000))
        try seedRecording(uuid: outside, transcription: "outside the window",
                          startDate: Date(timeIntervalSince1970: 1_600_000_000))

        let range = Date(timeIntervalSince1970: 1_699_999_000)...Date(timeIntervalSince1970: 1_700_001_000)
        let snapshot = DataManager.transcribedRecordingsSnapshot(in: range)
        XCTAssertEqual(snapshot.map(\.uuid), [inside])
        XCTAssertEqual(DataManager.transcribedRecordingsSnapshot().count, 2,
                       "nil range preserves the existing all-recordings behavior")
    }

    @MainActor
    func test_routeFixNear_returnsNearestSampleWithinNinetySeconds() throws {
        let previousDataStack = DataManager.dataStack
        DataManager.dataStack = stack
        defer { DataManager.dataStack = previousDataStack }

        let target = Date(timeIntervalSince1970: 1_700_000_000)
        try seedWalk(startDate: target.addingTimeInterval(-600), routeSamples: [
            (target.addingTimeInterval(-80), 42.10, -8.50, 8),
            (target.addingTimeInterval(20), 42.20, -8.50, 12),
            (target.addingTimeInterval(70), 42.30, -8.50, 6)
        ])

        let fix = DataManager.routeFixNear(timestamp: target)
        XCTAssertEqual(fix?.coordinate.latitude ?? 0, 42.20, accuracy: 0.0001)
        XCTAssertEqual(fix?.gapSeconds ?? 0, 20, accuracy: 0.5)
        XCTAssertEqual(fix?.horizontalAccuracy ?? 0, 12, accuracy: 0.5)
    }

    @MainActor
    func test_routeFixNear_noSampleInWindow_returnsNil() throws {
        let previousDataStack = DataManager.dataStack
        DataManager.dataStack = stack
        defer { DataManager.dataStack = previousDataStack }

        let target = Date(timeIntervalSince1970: 1_700_000_000)
        try seedWalk(startDate: target.addingTimeInterval(-600), routeSamples: [
            (target.addingTimeInterval(-120), 42.10, -8.50, 8)
        ])
        XCTAssertNil(DataManager.routeFixNear(timestamp: target),
                     "GPS-paused stretches and indoor starts never anchor a claim")
    }

    func test_routeFixNear_callableOffMain() throws {
        let previousDataStack = DataManager.dataStack
        DataManager.dataStack = stack
        defer { DataManager.dataStack = previousDataStack }

        let target = Date(timeIntervalSince1970: 1_700_000_000)
        try seedWalk(startDate: target.addingTimeInterval(-600), routeSamples: [
            (target.addingTimeInterval(10), 42.10, -8.50, 8)
        ])
        let done = expectation(description: "off-main fix")
        DispatchQueue.global().async {
            let fix = DataManager.routeFixNear(timestamp: target)
            XCTAssertNotNil(fix, "the detached builder resolves fixes lazily — the main hop must hold")
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    @MainActor
    func test_walkSensesSnapshot_returnsIntentionWeatherAndBoundsRange() throws {
        let previousDataStack = DataManager.dataStack
        DataManager.dataStack = stack
        defer { DataManager.dataStack = previousDataStack }

        let inside = UUID()
        try seedWalk(uuid: inside, startDate: Date(timeIntervalSince1970: 1_700_000_000),
                     comment: "release what I cannot carry", weatherCondition: "lightRain")
        try seedWalk(startDate: Date(timeIntervalSince1970: 1_600_000_000), comment: "old walk")

        let rows = DataManager.walkSensesSnapshot(
            from: Date(timeIntervalSince1970: 1_699_000_000),
            to: Date(timeIntervalSince1970: 1_701_000_000)
        )
        XCTAssertEqual(rows.map(\.walkUUID), [inside],
                       "queryAttributes stores \"id\" as a string — rowUUID must decode it")
        XCTAssertEqual(rows.first?.intention, "release what I cannot carry")
        XCTAssertEqual(rows.first?.weatherCondition, "lightRain")
    }
```

`seedRecording` gains a `startDate: Date = Date(timeIntervalSince1970: 1_700_000_000)` parameter applied as `recording._startDate .= startDate` (the existing seeding omits it today — add the line unconditionally).

Run `-only-testing:UnitTests/VoiceRecordingPersistenceTests`: expected **build failure** — `voiceRecordingTimestampIndex` / `routeFixNear` / `walkSensesSnapshot` not found (RED).

**Step 2 — GREEN.** In `DataManager+VoiceRecording.swift` (below `voiceRecordingPaceIndex`; also change `private static func rowUUID` → `static func rowUUID`):

```swift
    /// Recording UUID → the recording's own start instant. The walk-level
    /// `voiceRecordingWalkIndex` above returns WALK dates; the senses' 30-day
    /// windows and coordinate lookups need per-RECORDING times (spec Track 1).
    @MainActor
    public static func voiceRecordingTimestampIndex() -> [UUID: Date] {
        guard let rows = try? dataStack.queryAttributes(
            From<VoiceRecording>().select(
                NSDictionary.self,
                .attribute(\._uuid),
                .attribute(\._startDate)
            )
        ) else { return [:] }
        var index: [UUID: Date] = [:]
        for row in rows {
            guard let uuid = rowUUID(row["id"]),
                  let start = row["startDate"] as? Date else { continue }
            index[uuid] = start
        }
        return index
    }
```

Change `transcribedRecordingsSnapshot` to:

```swift
    @MainActor
    public static func transcribedRecordingsSnapshot(
        in range: ClosedRange<Date>? = nil
    ) -> [(uuid: UUID, transcript: String)] {
        var query = From<VoiceRecording>().select(
            NSDictionary.self,
            .attribute(\._uuid),
            .attribute(\._transcription)
        )
        if let range {
            query = query.where(\._startDate >= range.lowerBound && \._startDate <= range.upperBound)
        }
        guard let rows = try? dataStack.queryAttributes(query) else { return [] }
        return rows.compactMap { row in
            guard let uuid = rowUUID(row["id"]),
                  let transcript = row["transcription"] as? String,
                  !transcript.isEmpty else { return nil }
            return (uuid, transcript)
        }
    }
```

(Keep the existing doc comment; append one line noting the optional range serves the senses' bounded in-window fetch.)

In `DataManager+Query.swift` (new MARK section after the Walk Route section):

```swift
    // MARK: - Dossier Senses

    /// Nearest route fix for one recording instant: a ±90 s timestamp-
    /// predicate query with a fetch limit — never a full `walk.routeData`
    /// materialization (spec: bounded fetch; the samples table is the
    /// store's largest). 240 caps the read: ~1 Hz logging yields ≤181
    /// samples inside ±90 s, so the ascending-order clip never bites in
    /// practice. Callable off-main via `threadSafeSyncReturn`, matching
    /// `queryExistingHealthUUIDs` — ThreadsDossierBuilder resolves fixes
    /// lazily from its detached build.
    public static func routeFixNear(timestamp: Date) -> DossierSenses.RouteFix? {
        threadSafeSyncReturn {
            let windowStart = timestamp.addingTimeInterval(-DossierSenses.hygieneMaxGap)
            let windowEnd = timestamp.addingTimeInterval(DossierSenses.hygieneMaxGap)
            guard let rows = try? dataStack.queryAttributes(
                From<RouteDataSample>()
                    .select(
                        NSDictionary.self,
                        .attribute(\._timestamp),
                        .attribute(\._latitude),
                        .attribute(\._longitude),
                        .attribute(\._horizontalAccuracy)
                    )
                    .where(\._timestamp >= windowStart && \._timestamp <= windowEnd)
                    .orderBy(.ascending(\._timestamp))
                    .tweak { $0.fetchLimit = 240 }
            ) else { return nil }
            return rows
                .compactMap { row -> DossierSenses.RouteFix? in
                    guard let sampleTime = row["timestamp"] as? Date,
                          let latitude = row["latitude"] as? Double,
                          let longitude = row["longitude"] as? Double,
                          let accuracy = row["horizontalAccuracy"] as? Double else { return nil }
                    return DossierSenses.RouteFix(
                        coordinate: DossierSenses.Coordinate(latitude: latitude, longitude: longitude),
                        horizontalAccuracy: accuracy,
                        gapSeconds: abs(sampleTime.timeIntervalSince(timestamp))
                    )
                }
                .min { ($0.gapSeconds, $0.horizontalAccuracy) < ($1.gapSeconds, $1.horizontalAccuracy) }
        }
    }

    /// One row per walk in range — intention (`comment`), stored weather,
    /// start date — one bounded fetch serving intention lineage, weather
    /// weave, and the moon line's walk counts.
    @MainActor
    public static func walkSensesSnapshot(from: Date, to: Date) -> [DossierSenses.WalkSnapshotRow] {
        guard let rows = try? dataStack.queryAttributes(
            From<Walk>()
                .select(
                    NSDictionary.self,
                    .attribute(\._uuid),
                    .attribute(\._startDate),
                    .attribute(\._comment),
                    .attribute(\._weatherCondition)
                )
                .where(\._startDate >= from && \._startDate <= to)
                .orderBy(.ascending(\._startDate))
        ) else { return [] }
        return rows.compactMap { row in
            guard let uuid = rowUUID(row["id"]),
                  let start = row["startDate"] as? Date else { return nil }
            return DossierSenses.WalkSnapshotRow(
                walkUUID: uuid,
                startDate: start,
                intention: row["comment"] as? String,
                weatherCondition: row["weatherCondition"] as? String
            )
        }
    }
```

Run the class: **TEST SUCCEEDED**.

**Step 3 — verify + commit.** Full build; full suite (expect 1314 + 6 = 1320); lint.
Commit: `feat(threads): the data layer learns when and where each recording stood`

---

## Stage C — cross-walk senses, the moon line, builder integration

### Task 5: Weather buckets + weather weave

**Files:**
- Modify: `Pilgrim/Models/Weather/WeatherService.swift` — `enum WeatherCondition: String, Codable, CaseIterable` (one-word edit; synthesis requires same-file conformance).
- Modify: `Pilgrim/Models/Threads/DossierSensesTracks.swift` — `WeatherBucket`, `bucket(forStoredCondition:)`, `skyPhrase(_:)`, replace the `weatherWeave` stub.
- Create: `UnitTests/DossierSensesCrossWalkTests.swift` (+ 4 pbxproj entries, `plutil -lint`) — carries all Stage C pure-sense tests, with its own fixture helpers so the two test files stay independently compilable.

**Step 1 — RED.** `UnitTests/DossierSensesCrossWalkTests.swift`:

```swift
import XCTest
@testable import Pilgrim

final class DossierSensesCrossWalkTests: XCTestCase {

    static let walkStart = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
    static let walkEnd = DateFactory.makeDate(2024, 6, 15, 10, 30, 0)

    func makeInput(
        currentWalkUUID: UUID = UUID(),
        walkStart: Date = DossierSensesCrossWalkTests.walkStart,
        walkEnd: Date = DossierSensesCrossWalkTests.walkEnd,
        totalAscent: Double = 0,
        elevationSeries: [DossierSenses.ElevationSample] = [],
        photos: [DossierSenses.PhotoPin] = [],
        currentRecordings: [DossierSenses.CurrentRecording] = [],
        threads: [WalkThread] = [],
        backfillComplete: Bool = true,
        walkSnapshots: [DossierSenses.WalkSnapshotRow] = [],
        historyTranscripts: [(recordingUUID: UUID, transcript: String)] = [],
        recordingTimestamps: [UUID: Date] = [:],
        walkIndex: [UUID: (walkUUID: UUID, date: Date)] = [:],
        fixes: [UUID: DossierSenses.RouteFix] = [:],
        moon: DossierSenses.MoonInput? = nil
    ) -> DossierSenses.Input {
        DossierSenses.Input(
            currentWalkUUID: currentWalkUUID, walkStart: walkStart, walkEnd: walkEnd,
            totalAscent: totalAscent, elevationSeries: elevationSeries, photos: photos,
            currentRecordings: currentRecordings, threads: threads,
            backfillComplete: backfillComplete, walkSnapshots: walkSnapshots,
            historyTranscripts: historyTranscripts, recordingTimestamps: recordingTimestamps,
            walkIndex: walkIndex, fixes: fixes, moon: moon
        )
    }

    func fix(lat: Double, lon: Double, accuracy: Double = 10, gap: TimeInterval = 5) -> DossierSenses.RouteFix {
        DossierSenses.RouteFix(
            coordinate: DossierSenses.Coordinate(latitude: lat, longitude: lon),
            horizontalAccuracy: accuracy, gapSeconds: gap
        )
    }

    func thread(lemma: String, display: String? = nil, appearances: [ThreadAppearance]) -> WalkThread {
        WalkThread(lemma: lemma, displayTerm: display ?? lemma, appearances: appearances)
    }

    func appearance(recording: UUID = UUID(), walk: UUID, date: Date, mentions: Int = 2) -> ThreadAppearance {
        ThreadAppearance(recordingUUID: recording, walkUUID: walk, date: date,
                         mentionCount: mentions, salience: 0.02)
    }

    func snapshotRow(
        walk: UUID = UUID(), date: Date, intention: String? = nil, weather: String? = nil
    ) -> DossierSenses.WalkSnapshotRow {
        DossierSenses.WalkSnapshotRow(walkUUID: walk, startDate: date,
                                      intention: intention, weatherCondition: weather)
    }

    // MARK: - Weather buckets

    func testWeatherBucket_everyStorableConditionMapsToAKnownBucket() {
        for condition in WeatherCondition.allCases {
            XCTAssertNotEqual(DossierSenses.bucket(forStoredCondition: condition.rawValue), .unknown,
                              "\(condition.rawValue) fell out of the bucket map — WeatherKit vocabulary drifted")
        }
    }

    func testWeatherBucket_unrecognizedStringLandsInUnknown() {
        XCTAssertEqual(DossierSenses.bucket(forStoredCondition: "Rain"), .unknown,
                       "REST conditionCodes are mapped before storage; a raw one must not pass as rain")
    }

    // MARK: - Weather weave

    private func weaveInput(
        themeWalkWeather: [String?], otherWalkWeather: [String?]
    ) -> DossierSenses.Input {
        let currentWalk = UUID()
        var snapshots: [DossierSenses.WalkSnapshotRow] = []
        var appearances: [ThreadAppearance] = []
        for (i, weather) in themeWalkWeather.enumerated() {
            let walkUUID = i == 0 ? currentWalk : UUID()
            let date = Self.walkStart.addingTimeInterval(Double(i) * -3 * 86400)
            snapshots.append(snapshotRow(walk: walkUUID, date: date, weather: weather))
            appearances.append(appearance(walk: walkUUID, date: date))
        }
        for (i, weather) in otherWalkWeather.enumerated() {
            snapshots.append(snapshotRow(
                walk: UUID(), date: Self.walkStart.addingTimeInterval(Double(i + 1) * -5 * 86400),
                weather: weather
            ))
        }
        return makeInput(
            currentWalkUUID: currentWalk,
            threads: [thread(lemma: "music", appearances: appearances)],
            walkSnapshots: snapshots
        )
    }

    func testWeatherWeave_sharedMinorityCondition_fires() {
        let input = weaveInput(themeWalkWeather: ["lightRain", "heavyRain"],
                               otherWalkWeather: ["clear", "clear", "clear"])
        XCTAssertEqual(
            DossierSenses.weatherWeave(input: input, suppressed: []),
            DossierSenses.SenseLine(text: "Both walks where 'music' surfaced were under rain.", lemma: "music")
        )
    }

    func testWeatherWeave_threeWalks_usesAllPhrasing() {
        let input = weaveInput(themeWalkWeather: ["lightRain", "heavyRain", "thunderstorm"],
                               otherWalkWeather: ["clear", "clear", "clear", "clear"])
        XCTAssertEqual(DossierSenses.weatherWeave(input: input, suppressed: [])?.text,
                       "All 3 walks where 'music' surfaced were under rain.")
    }

    func testWeatherWeave_climateGuard_majorityConditionSuppresses() {
        let input = weaveInput(themeWalkWeather: ["lightRain", "heavyRain"],
                               otherWalkWeather: ["lightRain", "lightRain"])
        XCTAssertNil(DossierSenses.weatherWeave(input: input, suppressed: []),
                     "in a place where it mostly rains, 'both walks under rain' is geography, not signal")
    }

    func testWeatherWeave_anyExcludedWalk_emitsNothing() {
        let input = weaveInput(themeWalkWeather: ["lightRain", nil],
                               otherWalkWeather: ["clear", "clear", "clear"])
        XCTAssertNil(DossierSenses.weatherWeave(input: input, suppressed: []),
                     "the claim must be total — a walk without stored weather voids it")
    }

    func testWeatherWeave_mixedConditions_doesNotFire() {
        let input = weaveInput(themeWalkWeather: ["lightRain", "snow"],
                               otherWalkWeather: ["clear", "clear", "clear"])
        XCTAssertNil(DossierSenses.weatherWeave(input: input, suppressed: []))
    }

    func testWeatherWeave_singleWalkTheme_doesNotFire() {
        let input = weaveInput(themeWalkWeather: ["lightRain"],
                               otherWalkWeather: ["clear", "clear"])
        XCTAssertNil(DossierSenses.weatherWeave(input: input, suppressed: []))
    }
}
```

Run: expected **build failure** — `bucket(forStoredCondition:)` / `.unknown` not found; `CaseIterable` missing (RED).

**Step 2 — GREEN.** `WeatherService.swift` line 5: `enum WeatherCondition: String, Codable, CaseIterable {`. In `DossierSensesTracks.swift`:

```swift
// MARK: - Track 3: weather weave (cross-walk)

extension DossierSenses {

    enum WeatherBucket: Hashable {
        case rain, snow, clear, cloud, wind, fog, unknown
    }

    /// Collapses the app's stored `WeatherCondition` rawValues. Anything
    /// unrecognized lands in `unknown`, which excludes the walk from claims —
    /// the drift test keeps this total over the storable vocabulary.
    static func bucket(forStoredCondition raw: String) -> WeatherBucket {
        switch raw {
        case "clear": return .clear
        case "partlyCloudy", "overcast", "haze": return .cloud
        case "lightRain", "heavyRain", "thunderstorm": return .rain
        case "snow": return .snow
        case "fog": return .fog
        case "wind": return .wind
        default: return .unknown
        }
    }

    static func skyPhrase(_ bucket: WeatherBucket) -> String? {
        switch bucket {
        case .rain: return "under rain"
        case .snow: return "under snow"
        case .clear: return "under clear skies"
        case .cloud: return "under cloud"
        case .wind: return "in wind"
        case .fog: return "in fog"
        case .unknown: return nil
        }
    }

    static func weatherWeave(input: Input, suppressed: Set<String>) -> SenseLine? {
        let windowStart = input.walkStart.addingTimeInterval(-ThreadStore.recurrenceWindow)
        let inWindow = input.walkSnapshots.filter { $0.startDate >= windowStart && $0.startDate <= input.walkEnd }
        var buckets: [UUID: WeatherBucket] = [:]
        for row in inWindow {
            buckets[row.walkUUID] = row.weatherCondition.map(bucket(forStoredCondition:)) ?? .unknown
        }
        let known = buckets.values.filter { $0 != .unknown }
        guard !known.isEmpty else { return nil }
        let majority = Dictionary(grouping: known, by: { $0 })
            .first { Double($0.value.count) / Double(known.count) > 0.5 }?.key
        for thread in activeThreads(in: input) where !suppressed.contains(thread.lemma) {
            let walkUUIDs = Set(
                thread.appearances
                    .filter { $0.date >= windowStart && $0.date <= input.walkEnd }
                    .map(\.walkUUID)
            )
            guard walkUUIDs.count >= 2 else { continue }
            let themeBuckets = walkUUIDs.map { buckets[$0] ?? .unknown }
            guard let shared = themeBuckets.first,
                  shared != .unknown,
                  themeBuckets.allSatisfy({ $0 == shared }),
                  shared != majority,
                  let phrase = skyPhrase(shared) else { continue }
            let head = walkUUIDs.count == 2 ? "Both walks" : "All \(walkUUIDs.count) walks"
            return SenseLine(text: "\(head) where '\(thread.displayTerm)' surfaced were \(phrase).",
                             lemma: thread.lemma)
        }
        return nil
    }
}
```

Remove the `weatherWeave` stub. Run both sense test classes: **TEST SUCCEEDED**.

**Step 3 — verify + commit.** Full build; full suite (expect 1320 + 8 = 1328); lint.
Commit: `feat(threads): the dossier weaves the sky — minority weather only, tautologies stay silent`

### Task 6: Place-theme resonance (clustering + specificity guard)

**Files:**
- Modify: `Pilgrim/Models/Threads/DossierSensesTracks.swift` — replace the `placeResonance` stub; add `PlaceCluster`, `bestCluster`.
- Modify: `UnitTests/DossierSensesCrossWalkTests.swift` — tests.

**Step 1 — RED.** Add to `DossierSensesCrossWalkTests` (helper builds a two-walk history with per-recording fixes):

```swift
    // MARK: - Place-theme resonance

    /// Theme 'music' spoken at the river bend on two walks; theme 'work'
    /// spoken kilometers apart — the wide baseline the guard divides by.
    private func placeInput(
        clusterOffsetMeters: Double = 40,
        baselineSpreadDegrees: Double = 0.05,   // ~5.5 km — wide daily range
        backfillComplete: Bool = true,
        secondClusterFixGap: TimeInterval = 5
    ) -> DossierSenses.Input {
        let currentWalk = UUID(), otherWalk = UUID()
        let recA = UUID(), recB = UUID(), farC = UUID(), farD = UUID()
        let dayA = Self.walkStart, dayB = Self.walkStart.addingTimeInterval(-5 * 86400)
        let timestamps: [UUID: Date] = [
            recA: dayA.addingTimeInterval(600), recB: dayB.addingTimeInterval(600),
            farC: dayA.addingTimeInterval(1200), farD: dayB.addingTimeInterval(1200)
        ]
        let latOffset = clusterOffsetMeters / 111_320
        let fixes: [UUID: DossierSenses.RouteFix] = [
            recA: fix(lat: 42.8782, lon: -8.5448),
            recB: fix(lat: 42.8782 + latOffset, lon: -8.5448, gap: secondClusterFixGap),
            farC: fix(lat: 42.8782 + baselineSpreadDegrees, lon: -8.5448),
            farD: fix(lat: 42.8782 - baselineSpreadDegrees, lon: -8.5448)
        ]
        let threads = [
            thread(lemma: "music", appearances: [
                appearance(recording: recA, walk: currentWalk, date: dayA, mentions: 2),
                appearance(recording: recB, walk: otherWalk, date: dayB, mentions: 1)
            ]),
            thread(lemma: "work", appearances: [
                appearance(recording: farC, walk: currentWalk, date: dayA),
                appearance(recording: farD, walk: otherWalk, date: dayB)
            ])
        ]
        return makeInput(
            currentWalkUUID: currentWalk,
            threads: threads,
            backfillComplete: backfillComplete,
            recordingTimestamps: timestamps,
            fixes: fixes
        )
    }

    func testPlace_tightClusterWideBaseline_fires() {
        XCTAssertEqual(
            DossierSenses.placeResonance(input: placeInput(), suppressed: []),
            DossierSenses.SenseLine(
                text: "'music' has surfaced on 2 walks — 3 times near the same stretch of ground.",
                lemma: "music"
            )
        )
    }

    func testPlace_twoMentionCluster_saysTwice() {
        let currentWalk = UUID(), otherWalk = UUID()
        let recA = UUID(), recB = UUID(), farC = UUID(), farD = UUID()
        let dayA = Self.walkStart, dayB = Self.walkStart.addingTimeInterval(-5 * 86400)
        let input = makeInput(
            currentWalkUUID: currentWalk,
            threads: [
                thread(lemma: "music", appearances: [
                    appearance(recording: recA, walk: currentWalk, date: dayA, mentions: 1),
                    appearance(recording: recB, walk: otherWalk, date: dayB, mentions: 1)
                ]),
                thread(lemma: "work", appearances: [
                    appearance(recording: farC, walk: currentWalk, date: dayA),
                    appearance(recording: farD, walk: otherWalk, date: dayB)
                ])
            ],
            recordingTimestamps: [
                recA: dayA.addingTimeInterval(600), recB: dayB.addingTimeInterval(600),
                farC: dayA.addingTimeInterval(1200), farD: dayB.addingTimeInterval(1200)
            ],
            fixes: [
                recA: fix(lat: 42.8782, lon: -8.5448),
                recB: fix(lat: 42.87824, lon: -8.5448),
                farC: fix(lat: 42.93, lon: -8.5448),
                farD: fix(lat: 42.82, lon: -8.5448)
            ]
        )
        XCTAssertEqual(DossierSenses.placeResonance(input: input, suppressed: [])?.text,
                       "'music' has surfaced on 2 walks — twice near the same stretch of ground.")
    }

    func testPlace_specificityGuard_tightBaselineSuppresses() {
        let input = placeInput(baselineSpreadDegrees: 0.0005)  // ~55 m daily loop
        XCTAssertNil(DossierSenses.placeResonance(input: input, suppressed: []),
                     "when ALL recordings cluster, a 150 m match means nothing — routine geography suppresses")
    }

    func testPlace_backfillIncomplete_suppresses() {
        XCTAssertNil(DossierSenses.placeResonance(input: placeInput(backfillComplete: false), suppressed: []),
                     "an origin-class claim waits on the backfill gate")
    }

    func testPlace_hygieneFailedFix_dropsRecordingFromCluster() {
        XCTAssertNotNil(DossierSenses.placeResonance(input: placeInput(), suppressed: []))
        XCTAssertNil(DossierSenses.placeResonance(input: placeInput(secondClusterFixGap: 120), suppressed: []),
                     "a stale fix drops its recording; one walk's mentions alone cannot cluster")
    }

    func testPlace_singleWalkCluster_doesNotFire() {
        let currentWalk = UUID()
        let recA = UUID(), recB = UUID(), farC = UUID()
        let dayA = Self.walkStart
        let input = makeInput(
            currentWalkUUID: currentWalk,
            threads: [
                thread(lemma: "music", appearances: [
                    appearance(recording: recA, walk: currentWalk, date: dayA, mentions: 2),
                    appearance(recording: recB, walk: currentWalk, date: dayA, mentions: 2)
                ]),
                thread(lemma: "work", appearances: [appearance(recording: farC, walk: currentWalk, date: dayA)])
            ],
            recordingTimestamps: [recA: dayA.addingTimeInterval(60), recB: dayA.addingTimeInterval(900),
                                  farC: dayA.addingTimeInterval(1500)],
            fixes: [recA: fix(lat: 42.8782, lon: -8.5448), recB: fix(lat: 42.87824, lon: -8.5448),
                    farC: fix(lat: 42.93, lon: -8.5448)]
        )
        XCTAssertNil(DossierSenses.placeResonance(input: input, suppressed: []),
                     "≥2 distinct walks — one walk's cluster is a walk, not a resonance")
    }

    func testPlace_onlyFirstFourActiveThreadsChecked() {
        let base = placeInput()
        // Push 'music' past the candidate cap with four alphabetically-earlier
        // active threads carrying no cluster of their own.
        let fillers = ["alpha", "beta", "delta", "gamma"].map { name in
            thread(lemma: name, appearances: [appearance(walk: base.currentWalkUUID, date: Self.walkStart)])
        }
        let input = makeInput(
            currentWalkUUID: base.currentWalkUUID,
            threads: (fillers + base.threads).sorted { $0.lemma < $1.lemma },
            recordingTimestamps: base.recordingTimestamps,
            fixes: base.fixes
        )
        XCTAssertNil(DossierSenses.placeResonance(input: input, suppressed: []),
                     "cost bound: only the thread section's first 4 themes are checked")
    }
```

Run: expected — the process traps via `preconditionFailure("unimplemented sense")` inside `placeResonance` (RED; the `doesNotFire`/suppression tests are genuinely red, not vacuously green).

**Step 2 — GREEN.** In `DossierSensesTracks.swift`:

```swift
// MARK: - Track 1: place-theme resonance (cross-walk)

extension DossierSenses {

    struct PlaceCluster {
        let mentionCount: Int
        let walkCount: Int
        let spread: CLLocationDistance
    }

    static func placeResonance(input: Input, suppressed: Set<String>) -> SenseLine? {
        guard input.backfillComplete else { return nil }
        let windowStart = input.walkStart.addingTimeInterval(-ThreadStore.recurrenceWindow)
        func inWindow(_ uuid: UUID) -> Bool {
            guard let instant = input.recordingTimestamps[uuid] else { return false }
            return instant >= windowStart && instant <= input.walkEnd
        }
        func qualifiedCoordinate(_ uuid: UUID) -> Coordinate? {
            guard let fix = input.fixes[uuid], qualifies(fix) else { return nil }
            return fix.coordinate
        }
        // Baseline spread: median pairwise distance across ALL in-window
        // mention recordings, any theme — the specificity guard's denominator.
        var mentionCoordinates: [UUID: Coordinate] = [:]
        for thread in input.threads {
            for appearance in thread.appearances where inWindow(appearance.recordingUUID) {
                if let coordinate = qualifiedCoordinate(appearance.recordingUUID) {
                    mentionCoordinates[appearance.recordingUUID] = coordinate
                }
            }
        }
        let ordered = mentionCoordinates.sorted { $0.key.uuidString < $1.key.uuidString }.map(\.value)
        guard ordered.count >= 2 else { return nil }
        var pairwise: [Double] = []
        for i in 0..<(ordered.count - 1) {
            for j in (i + 1)..<ordered.count {
                pairwise.append(distance(ordered[i], ordered[j]))
            }
        }
        let baseline = median(pairwise)

        for thread in activeThreads(in: input).prefix(placeCandidateThemeCap)
        where !suppressed.contains(thread.lemma) {
            let distinctWalks = Set(
                thread.appearances
                    .filter { $0.date >= windowStart && $0.date <= input.walkEnd }
                    .map(\.walkUUID)
            )
            guard distinctWalks.count >= 2 else { continue }
            let members = thread.appearances
                .filter { inWindow($0.recordingUUID) }
                .compactMap { appearance in
                    qualifiedCoordinate(appearance.recordingUUID).map { (appearance: appearance, coordinate: $0) }
                }
                .sorted { $0.appearance.recordingUUID.uuidString < $1.appearance.recordingUUID.uuidString }
            guard let cluster = bestCluster(members: members),
                  // Strict: a walker whose every recording shares one spot has
                  // baseline 0 — nothing can be "more specific" than routine.
                  cluster.spread < baseline / 2 else { continue }
            let times = cluster.mentionCount == 2 ? "twice" : "\(cluster.mentionCount) times"
            return SenseLine(
                text: "'\(thread.displayTerm)' has surfaced on \(distinctWalks.count) walks — \(times) near the same stretch of ground.",
                lemma: thread.lemma
            )
        }
        return nil
    }

    /// Deterministic seed-centered clustering: for each member in UUID order,
    /// the candidate cluster is everything within the radius of that seed;
    /// best by mention count, then smallest spread, then seed order.
    static func bestCluster(
        members: [(appearance: ThreadAppearance, coordinate: Coordinate)]
    ) -> PlaceCluster? {
        var best: PlaceCluster?
        for seed in members {
            let near = members.filter { distance(seed.coordinate, $0.coordinate) <= placeClusterRadius }
            let mentionCount = near.reduce(0) { $0 + $1.appearance.mentionCount }
            let walkCount = Set(near.map(\.appearance.walkUUID)).count
            guard mentionCount >= 2, walkCount >= 2 else { continue }
            var spread: CLLocationDistance = 0
            for i in 0..<near.count {
                for j in (i + 1)..<near.count {
                    spread = max(spread, distance(near[i].coordinate, near[j].coordinate))
                }
            }
            if best == nil
                || mentionCount > best!.mentionCount
                || (mentionCount == best!.mentionCount && spread < best!.spread) {
                best = PlaceCluster(mentionCount: mentionCount, walkCount: walkCount, spread: spread)
            }
        }
        return best
    }
}
```

Remove the stub. Run both classes: **TEST SUCCEEDED**.

**Step 3 — verify + commit.** Full build; full suite (expect 1328 + 7 = 1335); lint; check `DossierSensesTracks.swift` length (<500; if the warning fires, split the cross-walk tracks into a sanctioned continuation file — do NOT restructure types).
Commit: `feat(threads): the ground remembers — place resonance with a specificity conscience`

### Task 7: Intention lineage + question density

**Files:**
- Modify: `Pilgrim/Models/Threads/DossierSensesTracks.swift` — replace the two stubs; add `intentionLemmas`, `questionCount`.
- Modify: `UnitTests/DossierSensesCrossWalkTests.swift` — tests.

**Step 1 — RED.**

```swift
    // MARK: - Intention lineage

    private func lineageInput(intentions: [String?], todayIntention: String?) -> DossierSenses.Input {
        let currentWalk = UUID()
        var snapshots = [snapshotRow(walk: currentWalk, date: Self.walkStart, intention: todayIntention)]
        for (i, intention) in intentions.enumerated() {
            snapshots.append(snapshotRow(
                walk: UUID(), date: Self.walkStart.addingTimeInterval(Double(i + 1) * -3 * 86400),
                intention: intention
            ))
        }
        return makeInput(currentWalkUUID: currentWalk, walkSnapshots: snapshots)
    }

    func testLineage_sharedContentLemmaAcrossFiveWalks_firesWithOrdinal() {
        let input = lineageInput(
            intentions: ["release the day", "releasing my grip", "release what is done", "release again"],
            todayIntention: "release what I cannot carry"
        )
        XCTAssertEqual(
            DossierSenses.intentionLineage(input: input, suppressed: []),
            DossierSenses.SenseLine(
                text: "Fifth walk in the last 30 days carrying some form of 'release'.",
                lemma: "release"
            )
        )
    }

    func testLineage_scaffoldOnlyOverlap_mustNotCluster() {
        let input = lineageInput(
            intentions: ["want to call my mother", "want less noise around meals"],
            todayIntention: "want a slower morning"
        )
        XCTAssertNil(DossierSenses.intentionLineage(input: input, suppressed: []),
                     "the spec's required fixture: unrelated intentions sharing only 'want' must NOT cluster")
    }

    func testLineage_twoPriorWalks_belowFloor() {
        let input = lineageInput(intentions: ["release the day"], todayIntention: "release the morning")
        XCTAssertNil(DossierSenses.intentionLineage(input: input, suppressed: []),
                     "≥3 in-window walks carrying the family — two is coincidence")
    }

    func testLineage_todayWithoutIntentionInFamily_doesNotFire() {
        let input = lineageInput(
            intentions: ["release the day", "releasing my grip", "release what is done"],
            todayIntention: "walk with the river"
        )
        XCTAssertNil(DossierSenses.intentionLineage(input: input, suppressed: []))
    }

    // MARK: - Question density

    private func questionInput(today: String, history: [String]) -> DossierSenses.Input {
        let currentWalk = UUID()
        let recUUID = UUID()
        var walkIndex: [UUID: (walkUUID: UUID, date: Date)] = [:]
        var timestamps: [UUID: Date] = [:]
        var transcripts: [(recordingUUID: UUID, transcript: String)] = []
        for (i, text) in history.enumerated() {
            let historyRec = UUID()
            let date = Self.walkStart.addingTimeInterval(Double(i + 1) * -3 * 86400)
            walkIndex[historyRec] = (UUID(), date)
            timestamps[historyRec] = date.addingTimeInterval(600)
            transcripts.append((historyRec, text))
        }
        return makeInput(
            currentWalkUUID: currentWalk,
            currentRecordings: [DossierSenses.CurrentRecording(
                uuid: recUUID, start: Self.walkStart, end: Self.walkStart.addingTimeInterval(300),
                text: today, wordCount: TranscriptNLP.wordCount(in: today), themes: []
            )],
            historyTranscripts: transcripts,
            recordingTimestamps: timestamps,
            walkIndex: walkIndex
        )
    }

    func testQuestionDensity_todayDoublesTheMedianAndTopsEveryWalk_fires() {
        let input = questionInput(
            today: "Who sits with him? What changes? Why now? What am I holding?",
            history: ["A question? Another?", "One thing today?", "No questions today at all."]
        )
        XCTAssertEqual(
            DossierSenses.questionDensity(input: input, suppressed: []),
            DossierSenses.SenseLine(
                text: "Four of today's sentences were questions — more than any walk in the last 30 days.",
                lemma: nil
            )
        )
    }

    func testQuestionDensity_tiedWithAHistoryWalk_doesNotFire() {
        let input = questionInput(
            today: "Who? What? Why?",
            history: ["One? Two? Three?", "Quiet.", "Still quiet."]
        )
        XCTAssertNil(DossierSenses.questionDensity(input: input, suppressed: []),
                     "today must EXCEED every other in-window walk, not tie one")
    }

    func testQuestionDensity_underThreeQuestions_doesNotFire() {
        let input = questionInput(today: "Why now? What next?", history: ["Quiet.", "Quiet.", "Quiet."])
        XCTAssertNil(DossierSenses.questionDensity(input: input, suppressed: []))
    }

    func testQuestionDensity_underThreeHistoryWalks_doesNotFire() {
        let input = questionInput(today: "Who? What? Why?", history: ["Quiet.", "Quiet."])
        XCTAssertNil(DossierSenses.questionDensity(input: input, suppressed: []),
                     "≥3 walks of history required before a median means anything")
    }
```

Run: expected — the process traps via `preconditionFailure("unimplemented sense")` inside `intentionLineage`/`questionDensity` (RED; the `doesNotFire` tests are genuinely red, not vacuously green).

**Step 2 — GREEN.**

```swift
// MARK: - Track 4: intention lineage (cross-walk)

extension DossierSenses {

    static func intentionLemmas(in intention: String) -> Set<String> {
        Set(TranscriptNLP.contentLemmas(in: intention)).subtracting(SpokenStoplist.scaffoldLemmas)
    }

    static func intentionLineage(input: Input, suppressed: Set<String>) -> SenseLine? {
        let windowStart = input.walkStart.addingTimeInterval(-ThreadStore.recurrenceWindow)
        let inWindow = input.walkSnapshots.filter { $0.startDate >= windowStart && $0.startDate <= input.walkEnd }
        guard let today = inWindow.first(where: { $0.walkUUID == input.currentWalkUUID }),
              let todayIntention = today.intention, !todayIntention.isEmpty else { return nil }
        let todayLemmas = intentionLemmas(in: todayIntention)
        guard !todayLemmas.isEmpty else { return nil }
        var familyWalks: [String: Set<UUID>] = [:]
        for row in inWindow {
            guard let intention = row.intention, !intention.isEmpty else { continue }
            for lemma in intentionLemmas(in: intention) {
                familyWalks[lemma, default: []].insert(row.walkUUID)
            }
        }
        let candidate = familyWalks
            .filter { todayLemmas.contains($0.key) && $0.value.count >= lineageMinWalks && !suppressed.contains($0.key) }
            .min { ($0.value.count, $1.key) > ($1.value.count, $0.key) }
        guard let candidate else { return nil }
        return SenseLine(
            text: "\(ordinalWord(candidate.value.count)) walk in the last 30 days carrying some form of '\(candidate.key)'.",
            lemma: candidate.key
        )
    }
}

// MARK: - Track 4: question density (cross-walk)

extension DossierSenses {

    static func questionCount(in text: String) -> Int {
        text.filter { $0 == "?" }.count
    }

    static func questionDensity(input: Input, suppressed: Set<String>) -> SenseLine? {
        let todayCount = input.currentRecordings.reduce(0) { $0 + questionCount(in: $1.text) }
        guard todayCount >= questionMinCount else { return nil }
        let windowStart = input.walkStart.addingTimeInterval(-ThreadStore.recurrenceWindow)
        var countsByWalk: [UUID: Int] = [:]
        for entry in input.historyTranscripts {
            guard let walk = input.walkIndex[entry.recordingUUID],
                  walk.walkUUID != input.currentWalkUUID,
                  let instant = input.recordingTimestamps[entry.recordingUUID],
                  instant >= windowStart, instant <= input.walkEnd else { continue }
            countsByWalk[walk.walkUUID, default: 0] += questionCount(in: entry.transcript)
        }
        guard countsByWalk.count >= questionMinHistoryWalks else { return nil }
        let history = countsByWalk.values.sorted()
        guard Double(todayCount) >= questionMedianRatio * median(history.map(Double.init)),
              todayCount > history.last ?? 0 else { return nil }
        return SenseLine(
            text: "\(capitalizedCount(todayCount)) of today's sentences were questions — more than any walk in the last 30 days.",
            lemma: nil
        )
    }
}
```

Remove both stubs. Run: **TEST SUCCEEDED**.

**Step 3 — verify + commit.** Full build; full suite (expect 1335 + 8 = 1343); lint.
Commit: `feat(threads): intentions show their lineage; questions find their walk`

### Task 8: The moon line (pure sense)

**Files:**
- Modify: `Pilgrim/Models/Threads/DossierSensesTracks.swift` — replace the `moonLine` stub.
- Modify: `UnitTests/DossierSensesCrossWalkTests.swift` — tests.

**Step 1 — RED.**

```swift
    // MARK: - Moon line

    private func moonInput(
        lastReported: Int? = nil, currentWalkHasWords: Bool = true,
        walkCount: Int = 5, wordedCount: Int = 3,
        themeWalksInLunation: Int = 2
    ) -> DossierSenses.Input {
        let lunationStart = DateFactory.makeDate(2024, 5, 8)
        let lunationEnd = DateFactory.makeDate(2024, 6, 6, 12, 0, 0)
        let inLunation = { (i: Int) in lunationStart.addingTimeInterval(Double(i + 1) * 4 * 86400) }
        let currentWalk = UUID()
        var appearances: [ThreadAppearance] = [
            appearance(walk: currentWalk, date: Self.walkStart)
        ]
        for i in 0..<themeWalksInLunation {
            appearances.append(appearance(walk: UUID(), date: inLunation(i)))
        }
        return makeInput(
            currentWalkUUID: currentWalk,
            threads: [thread(lemma: "music", appearances: appearances)],
            moon: DossierSenses.MoonInput(
                lunationIndex: 300, moonName: "Sturgeon Moon",
                start: lunationStart, end: lunationEnd,
                lastReportedIndex: lastReported,
                currentWalkHasWords: currentWalkHasWords,
                allWalkDates: (0..<walkCount).map(inLunation),
                wordedWalkDates: (0..<wordedCount).map(inLunation)
            )
        )
    }

    func testMoon_firstBuildAfterClose_firesWithCountsAndTopTheme() {
        XCTAssertEqual(
            DossierSenses.moonLine(input: moonInput(), suppressed: []),
            DossierSenses.SenseLine(
                text: "The Sturgeon Moon has set: 5 walks, 3 with recorded words; 'music' walked in 2 of them.",
                lemma: "music"
            )
        )
    }

    func testMoon_alreadyReportedLunation_staysSilent() {
        XCTAssertNil(DossierSenses.moonLine(input: moonInput(lastReported: 300), suppressed: []),
                     "once per lunation — emit once, not twice")
    }

    func testMoon_earlierLunationReported_currentOneStillFires() {
        XCTAssertNotNil(DossierSenses.moonLine(input: moonInput(lastReported: 299), suppressed: []))
    }

    func testMoon_silentCurrentWalk_neverCarriesTheLine() {
        XCTAssertNil(DossierSenses.moonLine(input: moonInput(currentWalkHasWords: false), suppressed: []),
                     "the line must never be a non-sequitur stapled to a silent walk")
    }

    func testMoon_lunationWithoutWordedWalks_staysSilent() {
        XCTAssertNil(DossierSenses.moonLine(input: moonInput(wordedCount: 0), suppressed: []))
    }

    func testMoon_topThemeSuppressed_dropsClauseKeepsCounts() {
        XCTAssertEqual(
            DossierSenses.moonLine(input: moonInput(), suppressed: ["music"]),
            DossierSenses.SenseLine(
                text: "The Sturgeon Moon has set: 5 walks, 3 with recorded words.",
                lemma: nil
            )
        )
    }

    func testMoon_topThemeSuppressed_secondThemeExists_fallsThroughInsteadOfDropping() {
        let base = moonInput()
        let lunationStart = DateFactory.makeDate(2024, 5, 8)
        let secondThemeDate = lunationStart.addingTimeInterval(3 * 4 * 86400)
        let augmented = makeInput(
            currentWalkUUID: base.currentWalkUUID,
            threads: base.threads + [thread(lemma: "art", appearances: [
                appearance(walk: UUID(), date: secondThemeDate)
            ])],
            moon: base.moon
        )
        XCTAssertEqual(
            DossierSenses.moonLine(input: augmented, suppressed: ["music"]),
            DossierSenses.SenseLine(
                text: "The Sturgeon Moon has set: 5 walks, 3 with recorded words; 'art' walked in 1 of them.",
                lemma: "art"
            ),
            "suppressing the top theme falls through to the next theme that walked that moon, not to silence"
        )
    }

    func testMoon_singleWalkLunation_pluralizesHonestly() {
        XCTAssertEqual(
            DossierSenses.moonLine(input: moonInput(walkCount: 1, wordedCount: 1, themeWalksInLunation: 1),
                                   suppressed: [])?.text,
            "The Sturgeon Moon has set: 1 walk, 1 with recorded words; 'music' walked in 1 of them."
        )
    }
```

Run: expected — the process traps via `preconditionFailure("unimplemented sense")` inside `moonLine` (RED; the "stays silent" tests are genuinely red, not vacuously green).

**Step 2 — GREEN.**

```swift
// MARK: - Track 2: the moon line (once per lunation)

extension DossierSenses {

    static func moonLine(input: Input, suppressed: Set<String>) -> SenseLine? {
        guard let moon = input.moon,
              moon.lastReportedIndex != moon.lunationIndex,
              moon.currentWalkHasWords else { return nil }
        // Lunation membership is [start, end): LunationCalendar mints end ==
        // next start, and the boundary instant belongs to the next moon.
        func inLunation(_ date: Date) -> Bool { date >= moon.start && date < moon.end }
        let walkCount = moon.allWalkDates.filter(inLunation).count
        let wordedCount = moon.wordedWalkDates.filter(inLunation).count
        guard wordedCount >= 1 else { return nil }
        var text = "The \(moon.moonName) has set: \(walkCount) walk\(walkCount == 1 ? "" : "s"), " +
            "\(wordedCount) with recorded words"
        let topTheme = input.threads
            .compactMap { thread -> (lemma: String, displayTerm: String, walks: Int)? in
                guard !suppressed.contains(thread.lemma) else { return nil }
                let walks = Set(thread.appearances.filter { inLunation($0.date) }.map(\.walkUUID)).count
                guard walks >= 1 else { return nil }
                return (thread.lemma, thread.displayTerm, walks)
            }
            .min { ($0.walks, $1.lemma) > ($1.walks, $0.lemma) }
        guard let topTheme else {
            return SenseLine(text: text + ".", lemma: nil)
        }
        text += "; '\(topTheme.displayTerm)' walked in \(topTheme.walks) of them."
        return SenseLine(text: text, lemma: topTheme.lemma)
    }
}
```

Remove the stub (the stub extension in `DossierSensesTracks.swift` is now empty — delete it). Run: **TEST SUCCEEDED**.

**Step 3 — verify + commit.** Full build; full suite (expect 1343 + 8 = 1351); lint.
Commit: `feat(threads): the moon reports once, and only to a walk that spoke`

### Task 9: Builder integration — gather, resolve, append, remember

**Files:**
- Modify: `Pilgrim/Models/Prompt/PromptContextTypes.swift` — `RecordingContext` gains `var endTimestamp: Date?` (optional var ⇒ memberwise default nil; every existing construction compiles unchanged).
- Modify: `Pilgrim/Models/Threads/ThreadsDossierBuilder.swift` — `DossierSensesFetchBundle`, `moonLineDefaultsKey`, `gatherSensesBundle(walk:now:)`, widened `build(...)`, `makeSensesInput(...)`, memo extension.
- Modify: `Pilgrim/Scenes/Prompts/PromptListView.swift` — toggle-guarded gather + pass-through; `endTimestamp: recording.endDate` in `RecordingContext` construction.
- Modify: `Pilgrim/Models/Data/DataManager.swift` — `deleteAll` success path clears `ThreadsDossierBuilder.moonLineDefaultsKey`.
- Modify: `UnitTests/ThreadsDossierTests.swift` — integration tests.
- Modify: `UnitTests/DataManagerThreadsDeletionTests.swift` — Delete All re-arm test, plus class-level `threadsMoonLineLastLunationIndex` save/restore in `setUpWithError`/`tearDownWithError` (house rule: every key a test mutates gets save/restore; `deleteAll` now touches this key on every call in this class, including the two pre-existing tests that call it).

**Interfaces produced:**

```swift
struct DossierSensesFetchBundle {
    let walkStart: Date
    let walkEnd: Date
    let totalAscent: Double
    let elevationSeries: [DossierSenses.ElevationSample]
    let photos: [DossierSenses.PhotoPin]
    let walkSnapshots: [DossierSenses.WalkSnapshotRow]
    let historyTranscripts: [(recordingUUID: UUID, transcript: String)]
    let recordingTimestamps: [UUID: Date]
    let closedLunation: Lunation
    let moonName: String
}

extension ThreadsDossierBuilder {
    static let moonLineDefaultsKey = "threadsMoonLineLastLunationIndex"
    @MainActor static func gatherSensesBundle(walk: WalkInterface, now: Date = Date()) -> DossierSensesFetchBundle
}

// build gains, all defaulted (existing call sites and tests unchanged):
//   senses: DossierSensesFetchBundle? = nil,
//   resolveRouteFix: (Date) -> DossierSenses.RouteFix? = DataManager.routeFixNear,
//   defaults: UserDefaults = .standard
```

**Step 1 — RED.** Add to `ThreadsDossierTests`:

```swift
    private func sensesBundle(
        walkStart: Date, walkEnd: Date,
        walkSnapshots: [DossierSenses.WalkSnapshotRow] = [],
        recordingTimestamps: [UUID: Date] = [:],
        lunationAnchor: Date
    ) -> DossierSensesFetchBundle {
        let lunation = LunationCalendar.mostRecentClosed(asOf: lunationAnchor)
        return DossierSensesFetchBundle(
            walkStart: walkStart, walkEnd: walkEnd, totalAscent: 0,
            elevationSeries: [], photos: [], walkSnapshots: walkSnapshots,
            historyTranscripts: [], recordingTimestamps: recordingTimestamps,
            closedLunation: lunation, moonName: LunationCalendar.moonName(for: lunation)
        )
    }

    private func wordedRecording(uuid: UUID, start: Date) -> RecordingContext {
        RecordingContext(
            text: String(repeating: "the move keeps returning to me today ", count: 6),
            timestamp: start, startCoordinate: nil, endCoordinate: nil,
            wordsPerMinute: nil, recordingUUID: uuid, endTimestamp: start.addingTimeInterval(120)
        )
    }

    func testBuilder_sensesBundle_appendsNoticedBlock_andMoonReportsOnce() {
        let saved = UserPreferences.threadsAfterWalks.value
        defer { UserPreferences.threadsAfterWalks.value = saved }
        UserPreferences.threadsAfterWalks.value = true
        let defaults = UserDefaults.standard
        let savedMoon = defaults.object(forKey: ThreadsDossierBuilder.moonLineDefaultsKey)
        defer {
            if let savedMoon { defaults.set(savedMoon, forKey: ThreadsDossierBuilder.moonLineDefaultsKey) }
            else { defaults.removeObject(forKey: ThreadsDossierBuilder.moonLineDefaultsKey) }
        }
        defaults.removeObject(forKey: ThreadsDossierBuilder.moonLineDefaultsKey)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DossierSensesBuilderTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptContextStore(directory: directory)

        // A walk dated just after a lunation close, with a worded walk inside
        // the closed lunation, so the moon line has something true to say.
        let now = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let lunation = LunationCalendar.mostRecentClosed(asOf: now)
        let walkStart = lunation.end.addingTimeInterval(3 * 86400)
        let walkA = UUID(), recA = UUID()
        let lunationWalk = UUID(), lunationRec = UUID()
        let lunationDate = lunation.start.addingTimeInterval(5 * 86400)
        _ = TranscriptContextAnalyzer.analyzeAndStore(
            recordingUUID: lunationRec,
            transcript: String(repeating: "the move keeps returning to me today ", count: 6),
            store: store
        )
        let walkIndex: [UUID: (walkUUID: UUID, date: Date)] = [
            recA: (walkA, walkStart), lunationRec: (lunationWalk, lunationDate)
        ]
        let bundle = sensesBundle(
            walkStart: walkStart, walkEnd: walkStart.addingTimeInterval(3600),
            walkSnapshots: [
                DossierSenses.WalkSnapshotRow(walkUUID: lunationWalk, startDate: lunationDate,
                                              intention: nil, weatherCondition: nil),
                DossierSenses.WalkSnapshotRow(walkUUID: walkA, startDate: walkStart,
                                              intention: nil, weatherCondition: nil)
            ],
            recordingTimestamps: [recA: walkStart.addingTimeInterval(300),
                                  lunationRec: lunationDate.addingTimeInterval(300)],
            lunationAnchor: now
        )

        let first = ThreadsDossierBuilder.build(
            walkUUID: walkA, recordings: [wordedRecording(uuid: recA, start: walkStart.addingTimeInterval(300))],
            walkIndex: walkIndex, store: store, senses: bundle, resolveRouteFix: { _ in nil }
        )
        XCTAssertNotNil(first)
        XCTAssertTrue(first!.contains("**Noticed:**"))
        XCTAssertTrue(first!.contains("has set"), "the closed lunation's line rides the first build after it")
        XCTAssertEqual(defaults.object(forKey: ThreadsDossierBuilder.moonLineDefaultsKey) as? Int,
                       bundle.closedLunation.index)

        // Memo: the same walk keeps its moon line on reopen.
        let again = ThreadsDossierBuilder.build(
            walkUUID: walkA, recordings: [wordedRecording(uuid: recA, start: walkStart.addingTimeInterval(300))],
            walkIndex: walkIndex, store: store, senses: bundle, resolveRouteFix: { _ in nil }
        )
        XCTAssertEqual(again, first)

        // A different walk in the same lunation: reported already — no line.
        let walkB = UUID(), recB = UUID()
        var indexB = walkIndex
        indexB[recB] = (walkB, walkStart.addingTimeInterval(86400))
        let second = ThreadsDossierBuilder.build(
            walkUUID: walkB,
            recordings: [wordedRecording(uuid: recB, start: walkStart.addingTimeInterval(86400))],
            walkIndex: indexB, store: store, senses: bundle, resolveRouteFix: { _ in nil }
        )
        XCTAssertNotNil(second)
        XCTAssertFalse(second!.contains("has set"), "once per lunation — the second walk stays quiet")
    }

    func testBuilder_nilSensesBundle_dossierUnchangedFromToday() {
        let saved = UserPreferences.threadsAfterWalks.value
        defer { UserPreferences.threadsAfterWalks.value = saved }
        UserPreferences.threadsAfterWalks.value = true
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DossierSensesBuilderTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptContextStore(directory: directory)
        let uuid = UUID()
        let dossier = ThreadsDossierBuilder.build(
            walkUUID: UUID(),
            recordings: [wordedRecording(uuid: uuid, start: DateFactory.makeDate(2024, 6, 15, 9, 0, 0))],
            walkIndex: [:], store: store
        )
        XCTAssertNotNil(dossier)
        XCTAssertFalse(dossier!.contains("**Noticed:**"),
                       "no bundle, no block — existing callers and tests see today's dossier")
    }

    func testBuilder_recordingWithoutUUID_noDossierAtAll_firingSenseNeverLeaksThrough() {
        let saved = UserPreferences.threadsAfterWalks.value
        defer { UserPreferences.threadsAfterWalks.value = saved }
        UserPreferences.threadsAfterWalks.value = true
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DossierSensesBuilderTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptContextStore(directory: directory)

        // A recording with no `recordingUUID` can never enter `current` — the
        // formatter's dossier is nil by the same guard the builder already
        // short-circuits on. A senses bundle built to fire (a worded walk
        // inside a closed lunation) must still leak nothing: the `if let
        // senses, dossier != nil` gate holds even when a sense has something
        // to say — the same structural guarantee the marker line's
        // handling-note co-presence claim rests on, proven from the other
        // direction.
        let now = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let lunation = LunationCalendar.mostRecentClosed(asOf: now)
        let walkStart = lunation.end.addingTimeInterval(3 * 86400)
        let walkA = UUID()
        let lunationWalk = UUID(), lunationRec = UUID()
        let lunationDate = lunation.start.addingTimeInterval(5 * 86400)
        _ = TranscriptContextAnalyzer.analyzeAndStore(
            recordingUUID: lunationRec,
            transcript: String(repeating: "the move keeps returning to me today ", count: 6),
            store: store
        )
        let walkIndex: [UUID: (walkUUID: UUID, date: Date)] = [lunationRec: (lunationWalk, lunationDate)]
        let bundle = sensesBundle(
            walkStart: walkStart, walkEnd: walkStart.addingTimeInterval(3600),
            walkSnapshots: [
                DossierSenses.WalkSnapshotRow(walkUUID: lunationWalk, startDate: lunationDate,
                                              intention: nil, weatherCondition: nil)
            ],
            recordingTimestamps: [lunationRec: lunationDate.addingTimeInterval(300)],
            lunationAnchor: now
        )
        let recordingWithoutUUID = RecordingContext(
            text: "words that never earn a dossier", timestamp: walkStart,
            startCoordinate: nil, endCoordinate: nil, wordsPerMinute: nil,
            recordingUUID: nil, endTimestamp: walkStart.addingTimeInterval(120)
        )

        let dossier = ThreadsDossierBuilder.build(
            walkUUID: walkA, recordings: [recordingWithoutUUID],
            walkIndex: walkIndex, store: store, senses: bundle, resolveRouteFix: { _ in nil }
        )
        XCTAssertNil(dossier, "no thread-bearing recording — no dossier, and a firing sense cannot conjure one")
    }

    func testAssembler_noticedBlockRidesInsideDossier_handlingNoteCoPresent() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let dossier = "**Thought threads (on-device analysis):**\ntest\n\n**Noticed:**\n'music' has surfaced on 2 walks — twice near the same stretch of ground."
        let context = ActivityContext.make(startDate: start, threadsDossier: dossier)
        let prompt = PromptAssembler.assemble(context: context, voice: PromptStyle.allCases[0].voice)
        XCTAssertTrue(prompt.contains("**Noticed:**"))
        XCTAssertTrue(prompt.contains("not assessments"),
                      "the dossier's presence triggers the marker handling note — the binding co-presence gate")
    }
```

`DataManager.deleteAll` now clears `ThreadsDossierBuilder.moonLineDefaultsKey` on every call — including inside the two PRE-EXISTING tests in this class that already call it (`testDeleteAll_removesEveryContextFile`, `testDeleteAll_tombstonesRecordingsWithoutContextFiles`), which today mutate real `UserDefaults.standard` with no save/restore. Move the save/restore to class level so it covers all three `deleteAll`-calling tests, not just the new one:

```swift
    private var stack: DataStack!
    private var store: TranscriptContextStore!
    private var directory: URL!
    private var previousDataStack: DataStack!
    private var savedMoonState: Any?

    override func setUpWithError() throws {
        try super.setUpWithError()
        previousDataStack = DataManager.dataStack
        stack = DataStack(PilgrimV7.schema)
        try stack.addStorageAndWait(InMemoryStore())
        DataManager.dataStack = stack

        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThreadsDeletionTests-\(UUID().uuidString)")
        store = TranscriptContextStore(directory: directory)
        DataManager.transcriptContextStore = store

        savedMoonState = UserDefaults.standard.object(forKey: ThreadsDossierBuilder.moonLineDefaultsKey)
    }

    override func tearDownWithError() throws {
        if let savedMoonState {
            UserDefaults.standard.set(savedMoonState, forKey: ThreadsDossierBuilder.moonLineDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: ThreadsDossierBuilder.moonLineDefaultsKey)
        }
        DataManager.transcriptContextStore = .shared
        DataManager.dataStack = previousDataStack
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }
```

(Mechanical edit: add the `savedMoonState` property and its two lines in each override; everything else in `setUpWithError`/`tearDownWithError` stays as shipped.) Add the new test — it needs no local save/restore of its own now that the class handles it:

```swift
    func testDeleteAll_clearsMoonLineState() throws {
        UserDefaults.standard.set(300, forKey: ThreadsDossierBuilder.moonLineDefaultsKey)

        let done = expectation(description: "deleteAll")
        DataManager.deleteAll { success, _ in
            XCTAssertTrue(success)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        XCTAssertNil(UserDefaults.standard.object(forKey: ThreadsDossierBuilder.moonLineDefaultsKey),
                     "Delete All Data re-arms the moon line with everything else")
    }
```

Run both classes: expected **build failure** — `endTimestamp` / `DossierSensesFetchBundle` / `moonLineDefaultsKey` not found (RED).

**Step 2 — GREEN.**

`PromptContextTypes.swift` — add to `RecordingContext` below `recordingUUID`:

```swift
    var endTimestamp: Date?
```

`ThreadsDossierBuilder.swift` — full replacement of the file's working parts (the memoization comment block stays; shown here complete):

```swift
import Foundation

/// Main-actor-fetched inputs for the senses block, gathered before the
/// detached build. Route fixes are NOT here — the builder resolves them
/// lazily, per needed recording, through `resolveRouteFix`.
struct DossierSensesFetchBundle {
    let walkStart: Date
    let walkEnd: Date
    let totalAscent: Double
    let elevationSeries: [DossierSenses.ElevationSample]
    let photos: [DossierSenses.PhotoPin]
    let walkSnapshots: [DossierSenses.WalkSnapshotRow]
    let historyTranscripts: [(recordingUUID: UUID, transcript: String)]
    let recordingTimestamps: [UUID: Date]
    let closedLunation: Lunation
    let moonName: String
}

enum ThreadsDossierBuilder {

    static let moonLineDefaultsKey = "threadsMoonLineLastLunationIndex"

    private static var memo: (
        changeCount: Int, walkUUID: UUID, backfillComplete: Bool,
        moonState: Int?, dossier: String?
    )?
    private static let memoLock = NSLock()

    /// The one impure gather for the senses (spec architecture): cheap
    /// CoreStore snapshots on the main actor, value types out. Callers wrap
    /// this in the `threadsAfterWalks` check — off means no fetches at all.
    @MainActor
    static func gatherSensesBundle(walk: WalkInterface, now: Date = Date()) -> DossierSensesFetchBundle {
        let lunation = LunationCalendar.mostRecentClosed(asOf: now)
        let windowStart = walk.startDate.addingTimeInterval(-ThreadStore.recurrenceWindow)
        return DossierSensesFetchBundle(
            walkStart: walk.startDate,
            walkEnd: walk.endDate,
            totalAscent: walk.ascend,
            elevationSeries: walk.routeData.map {
                DossierSenses.ElevationSample(timestamp: $0.timestamp, altitude: $0.altitude)
            },
            photos: walk.walkPhotos.map { photo in
                // (-1, -1) is the schema's unset sentinel, not a place.
                DossierSenses.PhotoPin(
                    capturedAt: photo.capturedAt,
                    coordinate: photo.capturedLat == -1 && photo.capturedLng == -1
                        ? nil
                        : DossierSenses.Coordinate(latitude: photo.capturedLat, longitude: photo.capturedLng)
                )
            },
            walkSnapshots: DataManager.walkSensesSnapshot(
                from: min(windowStart, lunation.start),
                to: max(walk.endDate, lunation.end)
            ),
            historyTranscripts: DataManager.transcribedRecordingsSnapshot(in: windowStart...walk.endDate),
            recordingTimestamps: DataManager.voiceRecordingTimestampIndex(),
            closedLunation: lunation,
            moonName: LunationCalendar.moonName(for: lunation)
        )
    }

    static func build(
        walkUUID: UUID,
        recordings: [RecordingContext],
        walkIndex: [UUID: (walkUUID: UUID, date: Date)],
        store: TranscriptContextStore = .shared,
        senses: DossierSensesFetchBundle? = nil,
        resolveRouteFix: (Date) -> DossierSenses.RouteFix? = DataManager.routeFixNear,
        defaults: UserDefaults = .standard
    ) -> String? {
        guard UserPreferences.threadsAfterWalks.value, !recordings.isEmpty else { return nil }
        // One consistent read each, captured before any store mutation: a
        // mid-build mutation leaves the memoized tokens stale, so the next
        // call rebuilds instead of absorbing the mutation unseen.
        let backfillComplete = ThreadsBackfill.isComplete
        let preBuildChangeCount = store.changeCount
        let moonState = defaults.object(forKey: moonLineDefaultsKey) as? Int
        memoLock.lock()
        let cached = memo
        memoLock.unlock()
        if let cached, cached.changeCount == preBuildChangeCount,
           cached.walkUUID == walkUUID, cached.backfillComplete == backfillComplete,
           cached.moonState == moonState {
            return cached.dossier
        }

        // >>> KEEP VERBATIM from the shipped builder: the whole span from
        // `let all = store.loadAll()` (orphan pruning) through
        // `let threads = ThreadStore.build(contexts: allContexts, walks: walkIndex)`
        // — including the `current` assembly with its lazy-backfill fallback.
        // Two mechanical adjustments only: `contextsByUUID` stays a named
        // local (makeSensesInput consumes it), and the formatter result below
        // binds as `var dossier` instead of `let dossier`. <<<

        var dossier = ThreadsDossierFormatter.dossier(
            currentRecordings: current,
            allContexts: allContexts,
            threads: threads,
            currentWalkUUID: walkUUID,
            backfillComplete: backfillComplete
        )

        var postBuildMoonState = moonState
        if let senses, dossier != nil {
            let input = makeSensesInput(
                senses: senses, walkUUID: walkUUID, recordings: recordings,
                contextsByUUID: contextsByUUID, threads: threads, walkIndex: walkIndex,
                backfillComplete: backfillComplete, moonState: moonState,
                resolveRouteFix: resolveRouteFix
            )
            let output = DossierSenses.lines(input: input)
            if !output.lines.isEmpty {
                dossier! += "\n\n**Noticed:**\n" + output.lines.joined(separator: "\n")
            }
            if let reported = output.reportedLunationIndex {
                defaults.set(reported, forKey: moonLineDefaultsKey)
                postBuildMoonState = reported
            }
        }

        memoLock.lock()
        // Post-write moon state: reopening this walk hits the memo and keeps
        // its moon line; any other walk rebuilds against the recorded state.
        memo = (preBuildChangeCount, walkUUID, backfillComplete, postBuildMoonState, dossier)
        memoLock.unlock()
        return dossier
    }

    /// Bridges builder-held data into the pure module's Input. Resolves route
    /// fixes for exactly the recordings that can anchor a location claim:
    /// in-window mention recordings (any thread — the baseline needs them
    /// all) plus the current walk's themed recordings.
    static func makeSensesInput(
        senses: DossierSensesFetchBundle,
        walkUUID: UUID,
        recordings: [RecordingContext],
        contextsByUUID: [UUID: TranscriptContext],
        threads: [WalkThread],
        walkIndex: [UUID: (walkUUID: UUID, date: Date)],
        backfillComplete: Bool,
        moonState: Int?,
        resolveRouteFix: (Date) -> DossierSenses.RouteFix?
    ) -> DossierSenses.Input {
        let currentRecordings: [DossierSenses.CurrentRecording] = recordings.compactMap { recording in
            guard let uuid = recording.recordingUUID,
                  let context = contextsByUUID[uuid] else { return nil }
            return DossierSenses.CurrentRecording(
                uuid: uuid,
                start: recording.timestamp,
                end: recording.endTimestamp ?? recording.timestamp,
                text: recording.text,
                wordCount: context.wordCount,
                themes: context.themes
            )
        }

        let windowStart = senses.walkStart.addingTimeInterval(-ThreadStore.recurrenceWindow)
        var needed = Set<UUID>()
        for thread in threads {
            for appearance in thread.appearances {
                guard let instant = senses.recordingTimestamps[appearance.recordingUUID],
                      instant >= windowStart, instant <= senses.walkEnd else { continue }
                needed.insert(appearance.recordingUUID)
            }
        }
        for recording in currentRecordings where !recording.themes.isEmpty {
            needed.insert(recording.uuid)
        }
        var fixes: [UUID: DossierSenses.RouteFix] = [:]
        for uuid in needed.sorted(by: { $0.uuidString < $1.uuidString }) {
            let timestamp = senses.recordingTimestamps[uuid]
                ?? currentRecordings.first { $0.uuid == uuid }?.start
            if let timestamp, let fix = resolveRouteFix(timestamp) {
                fixes[uuid] = fix
            }
        }

        var wordedWalkDates: [UUID: Date] = [:]
        for (uuid, context) in contextsByUUID where context.wordCount > 0 {
            if let walk = walkIndex[uuid] {
                wordedWalkDates[walk.walkUUID] = walk.date
            }
        }
        let moon = DossierSenses.MoonInput(
            lunationIndex: senses.closedLunation.index,
            moonName: senses.moonName,
            start: senses.closedLunation.start,
            end: senses.closedLunation.end,
            lastReportedIndex: moonState,
            currentWalkHasWords: currentRecordings.contains { $0.wordCount > 0 },
            allWalkDates: senses.walkSnapshots.map(\.startDate),
            wordedWalkDates: Array(wordedWalkDates.values)
        )

        return DossierSenses.Input(
            currentWalkUUID: walkUUID,
            walkStart: senses.walkStart,
            walkEnd: senses.walkEnd,
            totalAscent: senses.totalAscent,
            elevationSeries: senses.elevationSeries,
            photos: senses.photos,
            currentRecordings: currentRecordings,
            threads: threads,
            backfillComplete: backfillComplete,
            walkSnapshots: senses.walkSnapshots,
            historyTranscripts: senses.historyTranscripts,
            recordingTimestamps: senses.recordingTimestamps,
            walkIndex: walkIndex,
            fixes: fixes,
            moon: moon
        )
    }
}
```

Implementation note: the `>>> KEEP VERBATIM <<<` span is an instruction to preserve existing shipped code, not a placeholder for new code — nothing inside it changes except the two named mechanical adjustments.

`PromptListView.swift` — in `generatePrompts()`, after `let walkIndex = ...`:

```swift
            let sensesBundle = UserPreferences.threadsAfterWalks.value
                ? ThreadsDossierBuilder.gatherSensesBundle(walk: walk)
                : nil
```

and in the detached call: `ThreadsDossierBuilder.build(walkUUID: $0, recordings: baseContext.recordings, walkIndex: walkIndex, senses: sensesBundle)`. In `buildActivityContext()`, the `RecordingContext` construction gains `endTimestamp: recording.endDate`.

`DataManager.swift` — in `deleteAll`'s `.success` block, after `UserPreferences.clearArchivedRegistry()`:

```swift
                UserDefaults.standard.removeObject(forKey: ThreadsDossierBuilder.moonLineDefaultsKey)
```

Run both test classes: **TEST SUCCEEDED**.

**Step 3 — verify + commit.** Full build; full suite (expect 1351 + 5 = 1356 — reconcile; existing ThreadsDossierTests must all still pass against the widened signature); lint.
Commit: `feat(threads): the dossier notices — three lines at most, silence by default`

---

## Stage D — verification + ship-gate harness

### Task 10: DEBUG field-report harness, fixture report, final verification

**Files:**
- Modify: `Pilgrim/Models/Threads/ThreadsDossierBuilder.swift` — `#if DEBUG` `DossierSensesFieldReport` at file bottom (the builder is the impure gatherer; the harness reuses `gatherSensesBundle` + `makeSensesInput` so the report exercises the REAL input path).
- Modify: `Pilgrim/AppDelegate.swift` — inside `DataManager.setup`'s completion, after `self.appLaunchState = .done`: `#if DEBUG` / `Task { @MainActor in DossierSensesFieldReport.runIfRequested() }` / `#endif` (the completion closure carries no actor annotation; the Task hop keeps the @MainActor call clean).
- Modify: `UnitTests/FieldGateReportTests.swift` — a senses-report test over the existing fixture corpus (extends the shipped field-gate pattern).

**Step 1 — harness.** In `ThreadsDossierBuilder.swift`:

```swift
#if DEBUG
/// Ship-gate harness (spec Ship gate item 1): iterates every walk with
/// transcribed recordings, evaluates every sense uncapped, and prints
/// per-sense firing rates plus each emitted line, so a human can judge
/// degeneration (fires on nearly every walk) and dead senses (nearly never)
/// against a REAL device history. Launch the dev build on the team device
/// with `--senses-field-report` and read the console. The report only
/// EVALUATES senses (moon state passed as nil, no defaults write anywhere
/// on this path) — it never consumes the real once-per-lunation budget.
enum DossierSensesFieldReport {

    @MainActor
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--senses-field-report"),
              NSClassFromString("XCTestCase") == nil else { return }
        print(generate())
    }

    @MainActor
    static func generate(now: Date = Date()) -> String {
        guard let walks = try? DataManager.dataStack.fetchAll(
            From<Walk>().orderBy(.ascending(\._startDate))
        ) else { return "senses field report: walk fetch failed" }
        let walkIndex = DataManager.voiceRecordingWalkIndex()
        let store = TranscriptContextStore.shared
        let all = store.loadAll()
        let contextsByUUID = Dictionary(uniqueKeysWithValues: all.map { ($0.recordingUUID, $0) })
        let threadsAll = ThreadStore.build(contexts: all, walks: walkIndex)
        var firing: [DossierSenses.Sense: Int] = [:]
        var eligible = 0
        var report = "\n===== DOSSIER SENSES FIELD REPORT =====\n"
        for walk in walks {
            guard let walkUUID = walk._uuid.value else { continue }
            let recordings: [RecordingContext] = walk._voiceRecordings.value.compactMap { recording in
                guard let uuid = recording._uuid.value,
                      let text = recording._transcription.value, !text.isEmpty else { return nil }
                return RecordingContext(
                    text: text, timestamp: recording._startDate.value,
                    startCoordinate: nil, endCoordinate: nil,
                    wordsPerMinute: recording._wordsPerMinute.value,
                    recordingUUID: uuid, endTimestamp: recording._endDate.value
                )
            }
            guard !recordings.isEmpty else { continue }
            eligible += 1
            let bundle = ThreadsDossierBuilder.gatherSensesBundle(walk: walk, now: now)
            let input = ThreadsDossierBuilder.makeSensesInput(
                senses: bundle, walkUUID: walkUUID, recordings: recordings,
                contextsByUUID: contextsByUUID, threads: threadsAll, walkIndex: walkIndex,
                backfillComplete: ThreadsBackfill.isComplete, moonState: nil,
                resolveRouteFix: DataManager.routeFixNear
            )
            report += "\nWalk \(walk._startDate.value):\n"
            for sense in DossierSenses.Sense.allCases {
                guard let line = DossierSenses.evaluate(sense, input: input, suppressed: []) else { continue }
                firing[sense, default: 0] += 1
                report += "  [\(sense)] \(line.text)\n"
            }
        }
        report += "\nFiring rates over \(eligible) walks with words:\n"
        for sense in DossierSenses.Sense.allCases {
            report += "  \(sense): \(firing[sense] ?? 0)/\(eligible)\n"
        }
        report += "=======================================\n"
        return report
    }
}
#endif
```

(`import CoreStore` is needed at the top of `ThreadsDossierBuilder.swift` for `From<Walk>` — add it.)

**Step 2 — fixture report test.** Append to `FieldGateReportTests` (the class comment already frames the pattern):

```swift
    /// Senses over the same corpus, uncapped, with synthetic ground: a
    /// printed rehearsal of the on-device report so template phrasing gets
    /// human eyes before the real-history pass.
    func testPrintSensesFieldGateReport() {
        var contexts: [TranscriptContext] = []
        var walks: [UUID: (walkUUID: UUID, date: Date)] = [:]
        let base = DateFactory.makeDate(2024, 6, 1, 9, 0, 0)
        for (index, transcript) in fixtures.enumerated() {
            let context = TranscriptContextAnalyzer.analyze(
                recordingUUID: UUID(), transcript: transcript, flaggedFragments: []
            )
            contexts.append(context)
            walks[context.recordingUUID] = (UUID(), base.addingTimeInterval(Double(index) * 3 * 86400))
        }
        let threads = ThreadStore.build(contexts: contexts, walks: walks)
        let current = contexts.last!
        let currentWalk = walks[current.recordingUUID]!
        let input = DossierSenses.Input(
            currentWalkUUID: currentWalk.walkUUID,
            walkStart: currentWalk.date,
            walkEnd: currentWalk.date.addingTimeInterval(5400),
            totalAscent: 60,
            elevationSeries: [], photos: [],
            currentRecordings: [DossierSenses.CurrentRecording(
                uuid: current.recordingUUID, start: currentWalk.date.addingTimeInterval(300),
                end: currentWalk.date.addingTimeInterval(600),
                text: fixtures.last!, wordCount: current.wordCount, themes: current.themes
            )],
            threads: threads, backfillComplete: true,
            walkSnapshots: walks.values.map {
                DossierSenses.WalkSnapshotRow(walkUUID: $0.walkUUID, startDate: $0.date,
                                              intention: nil, weatherCondition: nil)
            },
            historyTranscripts: [], recordingTimestamps: [:], walkIndex: walks,
            fixes: [:], moon: nil
        )
        var report = "\n===== SENSES FIELD GATE REPORT (fixtures) =====\n"
        for sense in DossierSenses.Sense.allCases {
            let line = DossierSenses.evaluate(sense, input: input, suppressed: [])
            report += "  \(sense): \(line?.text ?? "—")\n"
        }
        report += "===============================================\n"
        print(report)
        XCTAssertFalse(threads.isEmpty)
    }
```

**Step 3 — final verification.**
- Full suite: `xcodebuild test ... 2>&1 | tee /tmp/senses-suite.log; grep -c "Test Case '.*' started" /tmp/senses-suite.log` — reconcile against the running tally (expected 1356 + 1 = 1357; macos-26 flake → retry once).
- `swiftlint 2>&1 | tail -3` — record the closing baseline in this plan's Execution status; zero new findings.
- `plutil -lint Pilgrim.xcodeproj/project.pbxproj`.
- Full app build.
- Grep sweeps: `grep -rn "Noticed:" Pilgrim/ | grep -v DossierSenses` (only ThreadsDossierBuilder's append); `grep -rn "threadsMoonLineLastLunationIndex" Pilgrim/` (builder + DataManager.deleteAll only — never PilgrimPackage); `grep -rn "Date()" Pilgrim/Models/Threads/DossierSenses*.swift` (zero hits — purity, both files).
- Descriptive-only sweep: read all nine emitted templates (the table under Global Constraints) against principle "descriptive-never-evaluative" — no trajectory language ("improving", "worsening", "more than usual" as judgment), no hardcoded prose where a computed value belongs; check each against its own row's substitution rule.
- Update `docs/superpowers/specs/2026-08-24-dossier-senses-2-design.md` Status line: `implemented on feat/dossier-senses-2, pending ship gate`.

Commit: `feat(threads): a field report for human eyes — the senses show their firing before they ship`

**Ship gate (human, after merge to the feature branch — blocks any external release):**
1. Run the dev build on the team iPhone with `--senses-field-report`; capture the console report. Judge: per-sense firing rates (degenerate/dead senses re-thresholded or cut), "same stretch of ground" thinness, Whisper `?` reliability (cut question density at the gate if unreliable — never patch).
2. LLM-readback QA: paste real dossiers with Senses II blocks — including at least one theme-linked marker line — into the major consumer LLMs; iterate `PromptAssembler.responseContract`'s handling note until no response contains clinical or diagnostic language.
3. Only after both pass: release per the `/release` skill.

## Execution status

- Task 1: complete
- Task 2: complete
- Task 3: complete (commit `cec4863`)
- Task 4: complete
- Task 5: complete
- Task 6: complete
- Task 7: complete
- Task 8: complete
- Task 9: complete (commit `f93fdec`)
- Task 10: complete — ship-gate harness + fixture report test + full verification sweep. Suite 1361 (baseline 1360 + 1), swiftlint 398/0 (unchanged baseline), `plutil -lint` clean, purity/descriptive/`Noticed:`/moon-key grep sweeps all clean. Harness confirmed to print "no walk history on this device" gracefully against empty simulator data. Human ship gate (real-device firing pass + LLM-readback QA) remains outstanding before any external release.
- Task 10: pending
