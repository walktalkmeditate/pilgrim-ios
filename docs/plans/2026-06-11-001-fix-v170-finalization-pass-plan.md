---
title: "fix: v1.7.0 finalization pass — issues #41/#42/#43 + audit remediation"
type: fix
status: active
date: 2026-06-11
origin: docs/brainstorms/2026-06-11-finalization-pass-requirements.md
---

# fix: v1.7.0 Finalization Pass

## Summary

One branch, per-concern commits, one PR. Resolves issues #41 (8 deprecation warnings), #42 (launch latency remainder — without any new migration), #43 (onboarding delight A+B), and remediates all 77 confirmed + 3 uncertain + 14 polish findings from the adversarial audit (`docs/brainstorms/2026-06-11-audit-findings.md`), each fixed or explicitly dispositioned. Ships as v1.7.0.

---

## Problem Frame

v1.6.0 is shipped and feels great; the audit proved "feels great" ≠ "is sound" (1 critical data-loss path, 19 major defects). Full context in the origin doc. Plan-specific framing: research overturned three assumptions — the NavigationLink refactor is dead-code deletion, the MetalKit "pause" is actually an un-capped display link (a battery bug), and the CoreStore launch cost is fixable without migration — so this plan is smaller in risk than the issues implied while larger in finding count.

---

## Assumptions

*This plan was authored without synchronous user confirmation (pre-authorized pipeline). The items below are agent inferences — review during doc review / PR review.*

- **CoreStore chain compression is rejected** (R3/AE1 no-migration disposition path): research showed the 1.2s lives in oldest-first model probing plus `versionLock:` eager model builds, both fixable with zero migration. Compression's data-safety risk buys nothing extra. Issue #42 closes with measured numbers as the disposition.
- **WeatherKit REST fallback is deleted outright** (key + `WeatherKitREST.swift`), not moved server-side. Native framework path remains primary; failure degrades to "no weather" gracefully. Server-side proxy is follow-up work if ever needed.
- Findings whose verifiers noted "documented intent" (e.g., ConstellationOverlay 60fps per PR #40) default to **accepted-with-reason disposition** unless a near-zero-cost gate (Low Power Mode / Reduce Motion) is trivially available.
- AF68 (fog token contrast): brand-token changes alter visual identity; default is a minimal contrast-preserving nudge validated side-by-side, with accepted-with-reason as fallback. No wholesale palette change.
- The PR does not bump version/build numbers — the release flow owns that.
- **`hasSanboxReceipt` (Config.swift:30) stays as an accepted-with-reason disposition**: the deprecated path is intentionally kept (documented in-code) to avoid an Apple Account sign-in prompt; it is the "+1 cached" warning acknowledged in issue #41, separate from the 8 tracked warnings. Logged in the PR disposition table.
- **Keychain device token is downgraded to a UserDefaults-backed token** (dies on reinstall) rather than declared as `NSPrivacyCollectedDataTypeDeviceID`: brand-aligned for a privacy-first app (reinstall = clean slate) and removes the manifest/nutrition-label obligation. The token is opaque to the worker, so server compatibility is expected — verify at implementation (U13).

---

## Requirements

Carried from origin (R1–R11 in `docs/brainstorms/2026-06-11-finalization-pass-requirements.md`); this plan must satisfy all of them. Key traceability:

- R1 (8 deprecations, behavior preserved) → U10, U11, U12
- R2 (880ms stall) → U8 · R3 (1.2s investigation, migration guard) → U9
- R4 (#43 A+B) → U18
- R5/R6 (audit findings fixed-or-dispositioned, log in PR) → U1–U7, U13–U17, U19
- R7 (runtime pass) → U19 · R8 (tests green) → all units · R9 (zero warnings) → U10–U12
- R10 (per-concern bisectable commits) → phase/commit structure below
- R11 (frozen constraints) → constraint on every unit; no schema migration anywhere in this plan

**Origin acceptance examples:** AE1 (covers R3 → U9), AE2/AE3 (cover R4 → U18), AE4 (covers R6 → U19).

---

## Scope Boundaries

Carried from origin: no field-signal mining; no new-feature ideation beyond #43; no schema migration (R3 condition resolved as "not needed"); sibling repos untouched; release execution (TestFlight soak, submission) is post-PR and TestFlight dispatch needs explicit user approval.

### Deferred to Follow-Up Work

- Server-side WeatherKit REST proxy (only if native-path reliability ever demands a fallback) — future issue.
- Capturing this pass's learnings into a durable `docs/solutions/` knowledge base — post-merge.
- WalkSummaryView/ActiveWalkView structural decomposition beyond what SwiftLint thresholds force — refactor-only PR if wanted later.

---

## Context & Research

### Relevant Code and Patterns

- Cleanup-on-disappear pattern to propagate: `Pilgrim/Scenes/Settings/RecordingsListView.swift:54` (`.onDisappear { audioPlayer.stop() }`).
- Accessibility reference implementations already in-repo: `FaviconSelectorView` (`.isSelected` traits), `RippleEffectView` + `WelcomeAnimationState` (Reduce Motion gating), `AboutView.statsWhisper` (tappable stats as real `Button`).
- In-memory CoreStore test pattern: `UnitTests/ArchivedWalkPrivacyTests.swift`, `UnitTests/PilgrimPackageImporterArchivedTests.swift` (private `DataStack(PilgrimV7.schema)` + `addStorageAndWait(InMemoryStore())`).
- Combine test helpers: `UnitTests/Helpers/XCTestCase+Combine.swift`; walk fixtures: `UnitTests/Helpers/WalkDataFactory.swift`.
- Launch instrumentation already present: `[LaunchProfile]` marks in `Pilgrim/AppDelegate.swift`, `[LaunchProfile.DM]` in `Pilgrim/Models/Data/DataManager.swift`.
- Interruption handling precedent: `VoiceRecordingManagement`'s `CXCallObserver` + `UnitTests/VoiceRecordingCallInterruptionTests.swift`.

### Institutional Learnings

- No `docs/solutions/`; canonical constraints live in `.claude/CLAUDE.md` (resource safety, frozen identifiers, data safety) and the audit doc's refuted/uncertain sections (disposition log of false positives — do not re-litigate X1–X5).
- Memory: shadow colors must be fixed (not adaptive); SwiftLint `type_body_length` error at 750 (extract subviews near 700); pre-commit lint covers staged files only → full-repo `swiftlint` before push.

### External References

- CoreStore 9.x source: `SchemaHistory` builds only the current model when `exactCurrentModelVersion` is supplied; `versionLock:` forces eager `rawModel()` builds for each LOCKED schema even in release — the condition and message autoclosures are evaluated unconditionally inside `Internals.assert` (`CoreStore+Logging.swift`), only DefaultLogger's trap is `#if DEBUG`; locks exist on the five OutRun schemas only; store-already-current fast path compares metadata against the current model only (`DataStack+Migration.swift:488-499`).
- Mapbox 11.20.0: `MapView.preferredFrameRateRange` (iOS 15+ replacement) and `MapView.displayState = []` (v11.17+ true pause; `touchesBegan` asserts when paused → pair with disabled gestures). `preferredFramesPerSecond = 0` means "native cadence", NOT pause (Apple CADisplayLink docs).
- SwiftUI: `navigationDestination(isPresented:/item:)` / value-based links; not needed here — wrappers are dead code.
- WeatherKit: native framework + `com.apple.developer.weatherkit` entitlement only; Apple: "Never distribute your private key." Attribution required via `WeatherService.attribution`.

---

## Key Technical Decisions

- **#42 via probe-order + versionLock gating, not migration**: reverse `currentORModel` probe to newest-first (`Pilgrim/Extensions/CoreStore/SQLiteStore.swift`) — the primary win: up-to-date stores resolve on the first probe instead of building ~11 models oldest-first. Secondarily, gate `versionLock:` to DEBUG on the five schemas that declare one (OutRunV1, V2, V3, V3to4, V4 — PilgrimV1–V7 have no locks): adjudicated against pod source, `Internals.assert` evaluates both its condition and message autoclosures unconditionally even in release (each forcing a `rawModel()` build at schema init), while no-lock schemas only log hashes under `#if DEBUG`. Preserves every migration path byte-for-byte. All before/after measurements in **Release configuration** — DEBUG builds all 12 models at DataStack init regardless, so Debug measurements understate the win.
- **Audio interruption resilience via the coordinator, not per-player observers**: `AudioSessionCoordinator` is already the single `AVAudioSession.interruptionNotification` observer; extend it to (a) arbitrate mode by highest active need instead of last-writer-wins, and (b) broadcast began/ended to registered consumers so players can pause/resume/finalize. One mechanism fixes AF4/AF5/AF6/AF11 coherently.
- **Mapbox pause via `displayState = []`** with gestures disabled while paused; visible-but-capped rendering via `preferredFrameRateRange`. Fixes both the deprecation (R1) and the un-cap bug.
- **Delete rules**: add `.cascade` to walk child relationships only if a fixture-store test proves the entity version hash is unchanged (delete rules are not part of CoreData's version hash — verify, don't trust). If the hash shifts: fall back to explicit child deletion inside the existing delete transactions. Either way, no migration.
- **Per-concern commits in phase order** (below) so the branch bisects even as one PR (R10).

---

## Open Questions

### Resolved During Planning

- Chain compression worth it? → No; no-migration fast path achieves the win (see Assumptions).
- MetalKit zero-rate replacement? → `displayState = []` (Mapbox 11.17+), `preferredFrameRateRange` for capping.
- Where is the 880ms? → Manifest-service singleton `init()` disk I/O + JSON decode on main thread at first `.shared` touch (esp. `WhisperManifestService` bootstrap decode), not the `Task` bodies.
- NavigationLink migration shape? → Wrappers have zero call sites; delete `Pilgrim/Extensions/SwiftUI/NavigationLink.swift` + `View+Navigation.swift`.
- Does versionLock cost release builds? (doc-review dispute) → Yes, adjudicated against `Pods/CoreStore/Sources/CoreStore+Logging.swift`: `Internals.assert` evaluates condition+message autoclosures before the logger's DEBUG-gated trap. Gating helps, but only 5 schemas carry locks.
- U11 mechanism → continuations cannot bridge sync→async; instead replace the deprecated probe with a synchronous `AVAudioFile(forReading:)`-based duration (length ÷ sampleRate), preserving the sync recovery call graph.

### Deferred to Implementation

- Exact coordinator arbitration table (which mode wins per consumer set) — design against the 9 known consumers at implementation; keep `recordAndPlay > recordingOnly > playbackOnly > idle` as the starting rule.
- Whether `.cascade` changes the version hash (fixture test decides the AF7 mechanism).
- AF34 reachability (does anything call `averageHeartRate`?) — guard regardless; if dead code, delete instead.
- U2-uncertain (`asBackgroundPublisher` de-serialization): investigate with a serial-queue swap + existing WalkBuilder tests; disposition if the mitigation noted by the refuting verifier holds.
- AF68 fog nudge vs accept — side-by-side render decides.

---

## Implementation Units

Phases group the per-concern commits; units inside a phase are independent unless noted. **Every unit that touches a finding must update the disposition log draft (U19 assembles it).** Frozen constraints (R11) apply globally.

### Phase A — Data integrity (the critical path)

### U1. Walk save/recovery ordering and import transactionality

**Goal:** No code path can lose a walk: checkpoint outlives save confirmation, recovery precedes sweeps, import never deletes before its replacement commit succeeds.

**Requirements:** R5, R6 — AF1 (critical), AF2, U1-uncertain.

**Dependencies:** None.

**Files:**
- Modify: `Pilgrim/Models/Walk/WalkSessionGuard.swift`, `Pilgrim/AppDelegate.swift`, `Pilgrim/Models/Data/PilgrimPackage/` (importer), walk-save call path (`Pilgrim/Models/Data/NewWalk.swift` / builder completion handler as found)
- Test: `UnitTests/WalkSessionGuardRecoveryTests.swift` (extend), new `UnitTests/PilgrimPackageImportTransactionTests.swift`

**Approach:**
- AF1: move checkpoint deletion into the save-transaction success completion; failure path must leave the checkpoint untouched and surface the error.
- AF2: serialize launch sequence — `RecordingPathRecovery` → `WalkSessionGuard` recovery commit → `OrphanRecordingSweep`; the sweep must not run concurrently with recovery (chain completions, don't fire in parallel). Guard against sweep starvation: recovery runs from MainCoordinator, which never constructs during onboarding/migration sessions — trigger the sweep on "recovery commit completed OR no checkpoint file exists" (the no-checkpoint fast path is evaluable in AppDelegate).
- U1-uncertain: make tended-import delete+insert a single transaction (or delete only in the same transaction that inserts); if CoreStore transaction scope can't span both, insert-then-delete-old with rollback on failure.

**Execution note:** Test-first where the in-memory stack reaches the behavior (checkpoint lifecycle, import transactionality).

**Patterns to follow:** in-memory `DataStack` pattern from `PilgrimPackageImporterArchivedTests.swift`.

**Test scenarios:**
- Happy path: save succeeds → checkpoint removed exactly once.
- Error path: save transaction fails → checkpoint still on disk, error surfaced, recovery on next launch restores the walk.
- Error path (Covers AE4 disposition flow if accepted differently): import replacement batch fails mid-write → pre-existing walks fully intact, no partial state.
- Integration: recovery + sweep ordering — a "crashed walk" fixture with orphaned audio recovers fully even when sweep is triggered immediately after.

**Verification:** extended recovery tests green; manual kill-during-walk recovery still works in runtime pass (U19).

### U2. Data-layer correctness and error propagation

**Goal:** Destructive and persistence operations are scoped, guarded, and honest about failure.

**Requirements:** R5, R6 — AF3, AF7, AF26, AF27, AF28, AF34, AF38, AF76.

**Dependencies:** None.

**Files:**
- Modify: settings clear-downloads path (`Pilgrim/Scenes/Settings/` + `Pilgrim/Models/Audio/AudioFileStore.swift` vicinity), `Pilgrim/Models/Data/DataModels/Versions/PilgrimV7.swift` (delete rules, only if hash-safe), `Pilgrim/Models/Data/PilgrimPackage/` exporter+importer, `Pilgrim/Models/TranscriptionService.swift` (persistence), `Pilgrim/Models/Data/Computation/WalkStats.swift` (or actual stats file)
- Test: new `UnitTests/DeleteRuleVersionHashTests.swift`, extend `UnitTests/PilgrimPackage*Tests.swift`, new stats guard tests

**Approach:**
- AF7: write the version-hash assertion test FIRST (compare `entityVersionHashesByName` with/without `deleteRule`); branch mechanism on its result per Key Technical Decisions.
- AF3: scope "Clear Downloaded Sounds" to soundscape assets only; leave voice-guide packs, manifests, prompt history.
- AF26/AF38: persistence completions must propagate failure (retry or user-visible state, not silence); set `isEnhanced` only after enhancement succeeds.
- AF27/AF28: distinguish fetch-error from empty in exporter; importer reports skipped/failed counts.
- AF34: guard division (`heartRates.isEmpty`), or delete if dead code.
- AF76: collect and propagate event-save failures during import.

**Test scenarios:**
- Edge case: `averageHeartRate` with zero samples → nil/0, no trap.
- Happy/error: export with DB error → error disposition, not "no walks found".
- Error path: import bundle with 2 valid + 1 corrupt walk file → result reports 2 imported, 1 failed (not unqualified success).
- Integration: delete walk → child route samples/pauses/recordings removed from store (cascade or explicit), verified via in-memory stack fetch.

**Verification:** new tests green; hash test documents the AF7 mechanism choice in its comments.

### Phase B — Audio resilience

### U3. AudioSessionCoordinator arbitration + interruption propagation + consumer-leak fixes

**Goal:** One coherent audio-session model: modes arbitrated by need, interruptions broadcast to players, every activation path has a guaranteed deactivation.

**Requirements:** R5, R6 — AF4, AF5, AF6, AF11, AF15/AF16 (same defect, dedup miss), AF21, AF22, AF24, AF37, AF40.

**Dependencies:** None. (U18's permission bell rides on BellPlayer, unaffected API-wise.)

**Files:**
- Modify: `Pilgrim/Models/Audio/AudioSessionCoordinator.swift`, `Pilgrim/Models/Audio/SoundscapePlayer.swift`, `Pilgrim/Models/Audio/VoiceGuide/VoiceGuidePlayer.swift`, `Pilgrim/Scenes/WalkSummary/AudioPlayerModel.swift`, `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift`, `Pilgrim/Models/Walk/WalkBuilder/Components/VoiceRecordingManagement.swift`, `Pilgrim/Models/Whisper/WhisperPlayer.swift`, `Pilgrim/Scenes/Meditation/` (resume logic)
- Test: new `UnitTests/AudioSessionCoordinatorTests.swift` (arbitration table, consumer lifecycle), extend `UnitTests/VoiceRecordingCallInterruptionTests.swift` for non-call interruptions

**Approach:**
- Coordinator: track consumer→mode map (not a bare Set); applied mode = max requirement of live consumers; deactivating a consumer recomputes (fixes AF4). Broadcast `.began`/`.ended` (with shouldResume option flag) to registered consumers (fixes AF5 soundscape resume, AF11 recording finalize-on-interrupt, complements CallKit path).
- **Re-entrancy and dispatch discipline** (doc-review catch): the coordinator uses `queue.sync` internally — a consumer reacting to `.began` by deactivating itself would re-enter the same serial queue and deadlock. Snapshot consumers under the lock, deliver began/ended callbacks OUTSIDE it (async on main), and make activate/deactivate safe to call from inside a broadcast handler.
- **Defer mode application during an active interruption**: between `.began` and `.ended`, record recomputed modes but defer `setActive`/`applyMode` until `.ended` — `setActive(true)` fails while another app holds the session, and that failure must not evict surviving consumers.
- AF6: `VoiceGuidePlayer.stop()` invokes `onFinished` (or scheduler observes a did-stop signal) so the latch clears.
- AF15/16: `AudioPlayerModel` gets `deinit` cleanup + `WalkSummaryView.onDisappear` calls `stop()` (mirror `RecordingsListView.swift:54`).
- AF21/22: crossfade sets `isPlaying` correctly; asyncAfter cleanup guarded by generation counter (CLAUDE.md rule).
- AF24: resume-after-meditation respects the user's manual pause state.
- AF37/AF40: error paths deactivate the consumer they activated.

**Execution note:** Test-first for the arbitration table — it's pure logic and the highest-regression-risk redesign in this PR.

**Test scenarios:**
- Happy: two playback consumers, one ends → session stays playback; recording consumer joins → recordAndPlay; recording ends → downgrades to playback (AF4).
- Integration: interruption began → soundscape pauses, isPlaying false; ended with shouldResume → resumes (AF5). Without shouldResume → stays paused, state consistent.
- Error path: recording interrupted by non-call source → recording finalized and saved, UI state updated (AF11).
- Edge: stop-then-play within crossfade window → isPlaying true, exactly one active player (AF21/22).
- Edge: consumer deactivates twice / never activated → no underflow, set consistent.
- Edge: consumer deactivates itself in response to `.began` → no deadlock, state consistent (re-entrancy test).
- Edge: consumer deactivates between `.began` and `.ended` → no setActive attempt mid-interruption; survivors resume on `.ended`.
- Integration (privacy property): voiceRecording consumer deactivates with only soundscape remaining → applied session category is playback-only, NOT playAndRecord (mic route released).

**Verification:** coordinator tests green; runtime pass exercises walk-with-soundscape + simulated interruption (Siri invocation on simulator) without permanent silence.

### Phase C — Leaks and thread-safety

### U4. Retain cycles and resource leaks

**Goal:** Builders, view models, and map observers deallocate; nothing accumulates per walk or per appearance.

**Requirements:** R5, R6 — AF8, AF33, AF61, AF70.

**Dependencies:** None.

**Files:**
- Modify: `Pilgrim/Models/Walk/WalkBuilder/Components/LocationManagement.swift`, `Pilgrim/Models/Walk/WalkBuilder/Components/StepCounter.swift`, `Pilgrim/Models/Walk/WalkBuilder/WalkBuilder.swift` (flush-action lifecycle), `Pilgrim/Scenes/Root/RootCoordinatorViewModel.swift` + `Pilgrim/PilgrimApp.swift`, `Pilgrim/Views/PilgrimMapView.swift` (onStyleLoaded capture), `Pilgrim/Models/TranscriptionService.swift` (unloadModel after auto-transcription)
- Test: new `UnitTests/WalkBuilderLifecycleTests.swift` (deinit expectation via weak ref)

**Approach:**
- AF8: `[weak builder]` in registered flush closures (or clear `preSnapshotFlushActions` in reset/cancel); also ensure cancelled walks reach a state that releases relays.
- AF61: replace `assign(to:on:)` self-retain with `sink { [weak self] }` or `@Published` republish; stop re-instantiating the VM in `body`.
- AF70: break the one-shot observer's strong capture (weak coordinator or remove-after-fire and nil the token).
- AF33: call `unloadModel()` when the auto-transcription queue drains (keep resident during active batch).

**Test scenarios:**
- Happy: builder completes walk → builder instance deallocates (weak-ref nil after reset).
- Edge: builder cancelled mid-walk → deallocates, relays emptied, no ApplicationStateObservation callbacks fire afterward.
- Integration: auto-transcription batch completes → WhisperKit memory released (model nil), next transcription reloads cleanly.

**Verification:** lifecycle tests green; Leaks-instrument spot check during runtime pass shows no WalkBuilder/RootCoordinatorViewModel accumulation across start/cancel cycles.

### U5. Thread-safety and dispatch correctness

**Goal:** Shared mutable state in the recording/sensor pipeline is queue-confined; timers live on run loops; UI mutations are main-thread.

**Requirements:** R5, R6 — AF12, AF30, AF31, AF35, AF36, AF77, U2-uncertain.

**Dependencies:** None.

**Files:**
- Modify: `Pilgrim/Models/Walk/WalkSessionGuard.swift` (sink queues + timer scheduling), `Pilgrim/Models/GeoCache/GeoCacheService.swift` (actual path as found), `Pilgrim/Models/TranscriptionService.swift`, `Pilgrim/Models/Walk/WalkBuilder/Components/AltitudeManagement.swift`, `Pilgrim/Models/Walk/WalkBuilder/Components/StepCounter.swift`, `Pilgrim/Models/Intention/IntentionVoiceRecorder.swift`, `Pilgrim/Extensions/Combine/` (asBackgroundPublisher)
- Test: extend `UnitTests/` with race-shaped tests where deterministic (gate checks, serialization), note where TSan-only

**Approach:** main-actor or serial-queue confinement per type; AF12 reschedules the checkpoint timer on the main run loop (or DispatchSourceTimer on its queue); AF31 funnels `ensureModelReady` through one gate; AF77 confines `recordingURL` mutation to the main actor; U2-uncertain: swap concurrent queue for serial in `asBackgroundPublisher` (cheap), then disposition.

**Test scenarios:**
- Happy: checkpoint timer fires repeatedly during a simulated 2-minute walk on background-sink configuration (AF12 regression).
- Edge: concurrent `ensureModelReady` calls → one load, both callers proceed (AF31).
- Integration: WalkBuilder pipeline ordering preserved after serial-queue swap (existing builder tests + new ordering assertion).

**Verification:** unit tests green; Thread Sanitizer run of UnitTests target clean for the touched types (note: TSan run is part of U19).

### Phase D — Performance (+ the map deprecation that gates it)

### U12. Mapbox frame-rate migration + true render pause

**Goal:** 3 warnings gone; the "pause" actually pauses; battery behavior improves rather than regresses. Lands FIRST in this phase — U6 modifies the same file on top of the new APIs.

**Requirements:** R1, R9 — also remediates the discovered un-cap bug (`preferredFramesPerSecond = 0` un-caps the display link to native cadence instead of pausing).

**Dependencies:** None (gates U6).

**Files:**
- Modify: `Pilgrim/Views/PilgrimMapView.swift` (`renderFPS`, `refreshRenderState`, init config)
- Test: `Test expectation: none — rendering behavior; verified via runtime pass + Instruments (display-link cadence not directly assertable in XCTest)`

**Approach:** visible state → `preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 30)` (match current 30fps intent); paused state → `displayState = []`, restore `[.foregroundActive, .foregroundInactive]` on resume. While paused, set `mapView.isUserInteractionEnabled = false` (restore after displayState is restored, in that order) — gesture-handler disabling is NOT sufficient: Mapbox's `touchesBegan` is a UIResponder override that force-restarts the display link on any raw touch (DEBUG assert + silent release un-pause). Re-key `hasDeferredRouteUpdate` from `preferredFramesPerSecond > 0` to the new displayState representation so a route update arriving while paused isn't dropped on resume. Background transitions are SDK-managed in 11.17+.

**Verification:** warnings −3 (the tracked 8 → 0; one pre-existing intentional warning, `hasSanboxReceipt`, remains and is logged accepted-with-reason per Assumptions); paused map shows zero display-link activity in Instruments, including after a stray touch; long-walk battery path exercised in runtime pass.

### U6. Walk-path data pipeline and map efficiency

**Goal:** Per-GPS-sample cost is O(1) amortized; map work happens only on change; battery tiers behave.

**Requirements:** R5, R6 — AF9, AF13, AF14, AF20, AF43, AF46.

**Dependencies:** U12 (same file: `Pilgrim/Views/PilgrimMapView.swift`) — land U12 first.

**Files:**
- Modify: `Pilgrim/Models/Walk/WalkBuilder/Components/LocationManagement.swift`, `Pilgrim/Views/PilgrimMapView.swift`, `Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift` + `ActiveWalkViewModel.swift`, `Pilgrim/Models/Walk/WalkSessionGuard.swift` (checkpoint encode off main + interval), battery-tier application path
- Test: new `UnitTests/RoutePipelineTests.swift` (incremental append semantics), checkpoint-interval tests

**Approach:**
- AF9/AF46: append-based publishing (publish the new sample / incremental segment, not the whole remapped array); GeoJSON updates become incremental or throttled-delta.
- AF13: encode checkpoint on a utility queue; write atomically; keep cadence but move cost off main.
- AF14: re-apply battery tier after meditation ends (single source of truth for desired accuracy).
- AF20/AF43: change-detection (diff annotations; cache rasterized symbols; memoize proximity annotations on inputs).

**Test scenarios:**
- Happy: 10k-sample synthetic walk → per-sample work bounded (measure: no full-array copy; assert via call-count probe or time budget).
- Edge: pause/resume mid-walk → segments correct with incremental publishing.
- Integration: battery tier low → meditation start/end → accuracy back at low-power values (AF14).

**Verification:** route pipeline tests green; Time Profiler spot check during U19 shows flat per-sample cost on a long demo walk.

### U7. View-layer render efficiency

**Goal:** High-frequency timers and heavy bodies stop re-rendering the world.

**Requirements:** R5, R6 — AF10, AF17, AF42, AF51, AF52, U3-uncertain.

**Dependencies:** None (touches different regions of ActiveWalkView than U6; coordinate commits).

**Files:**
- Modify: `Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift` (metering isolation), `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift` (routeData memoization), `Pilgrim/Scenes/Home/InkScrollView.swift` (memoized astronomical computation + lazy dots), scenery/options animation gating
- Test: `Test expectation: none — render-path changes verified via Instruments + runtime pass; logic extraction (lunar-event scan memoization) gets unit tests where extracted into pure helpers`

**Approach:**
- AF10: isolate the 20Hz level meter into a leaf view observing its own publisher; Mapbox representable must not re-evaluate per tick.
- AF17: fetch/derive route stats once per walk identity, not per body.
- AF51: cache day-scan/milestone/color computations keyed by walk set hash; AF52: `LazyVStack`/visible-window instantiation.
- AF42: gate the pulse to a few cycles or Reduce-Motion-aware stop.
- U3-uncertain (ConstellationOverlay 60fps, documented intent): add Low Power Mode pause if trivially achievable via TimelineView cadence switch; otherwise disposition accepted-with-reason citing PR #40.

**Verification:** SwiftUI re-render spot check (Self._printChanges or Instruments) during recording: map representable not re-evaluated at 20Hz; ink scroll opens smoothly with 100+ walk fixture in demo mode.

### Phase E — Launch (#42)

### U8. Manifest-service init off the main thread

**Goal:** Post-setup fire-and-forgets stop burning ~880ms of main-thread time during the welcome entrance.

**Requirements:** R2 — issue #42.

**Dependencies:** None.

**Files:**
- Modify: `Pilgrim/Models/Audio/AudioManifestService.swift`, `Pilgrim/Models/Audio/VoiceGuide/VoiceGuideManifestService.swift`, `Pilgrim/Models/Whisper/WhisperManifestService.swift`, `Pilgrim/AppDelegate.swift`
- Test: extend `UnitTests/WhisperManifestServiceTests.swift` + `VoiceGuideManifestTests.swift` for async-init behavior

**Approach:** make `loadLocalManifest()`/bootstrap decode lazy-async (load inside the existing `Task` before first use) or touch `.shared` on a utility queue from AppDelegate; keep main-actor confinement for published state; `VoiceGuideManifestService`'s post-await sync disk re-read moves off main. Preserve `[LaunchProfile]` marks; add a mark for first-manifest-ready.

**Test scenarios:**
- Happy: manifest lookups before sync complete → consistent empty/bootstrap behavior (no crash, no main-thread disk read).
- Integration: whisper catalog loads → existing manifest tests still pass with async init.

**Verification:** `[LaunchProfile]` delta on iPhone 16e sim: post-setup dispatch cost ≈ 0ms on main; welcome entrance animation hitch-free in runtime pass.

### U9. CoreStore model-resolution fast path (no migration)

**Goal:** `currentORModel` + stack construction stops costing ~1.2s for up-to-date stores; #42 closes with measured numbers.

**Requirements:** R3, AE1.

**Dependencies:** None.

**Files:**
- Modify: `Pilgrim/Extensions/CoreStore/SQLiteStore.swift` (reverse probe order), `Pilgrim/Models/Data/DataModels/Versions/OutRunV1.swift`, `OutRunV2.swift`, `OutRunV3.swift`, `OutRunV3to4.swift`, `OutRunV4.swift` (the only five schemas declaring `versionLock` — DEBUG-gate it), `Pilgrim/Extensions/CoreStore/DataStack.swift` (only if needed for lazy schema materialization), `Pilgrim/Models/Data/DataManager.swift` (instrumentation)
- Test: new `UnitTests/ModelResolutionTests.swift` — fixture store at current version resolves on first probe; fixture at an older version still resolves and migrates via a copied SQLite store file in a temp dir (CoreStore progressive migration requires SQLite stores, not InMemoryStore; generate the V6 fixture via `DataStack(oRMigrationChain:oRDataModel: PilgrimV6.self)` against a temp SQLiteStore)

**Approach:** newest-first probe (primary win: removes ~11 probe-time model builds for up-to-date stores); `versionLock:` behind `#if DEBUG` on the five OutRun schemas (removes their release init-time builds — both the assert condition and its message string force `rawModel()` per the adjudicated pod source); measure before/after with `[LaunchProfile.DM]` **in Release configuration** (Debug builds all 12 models at DataStack init via CoreStore's DEBUG assert/log paths, masking the win); record numbers in the disposition log and issue #42 close comment. **Migration behavior must be provably untouched**: the migration chain declaration, mapping providers, and schema contents do not change.

**Execution note:** characterization-first — capture current Release-config `[LaunchProfile.DM]` timings and a fixture-store migration walk (V6→V7 path at minimum, via copied store file in a temp dir) BEFORE touching probe order, so after-changes equivalence is demonstrable.

**Test scenarios:**
- Happy: up-to-date store → resolved version == PilgrimV7, one probe (assert via injected probe counter or log assertion).
- Edge (Covers AE1): store at PilgrimV6 fixture → still detected, migration path intact, data present after setup.
- Edge (probe-order safety): all 12 chain schemas' `entityVersionHashesByName` are pairwise distinct — makes probe order provably irrelevant to detection for every install state (a hash-identical pair would let newest-first skip a custom mapping step silently).
- Error path: store with unknown/corrupt metadata → same behavior as today (no new failure mode).

**Verification:** measured Release-config cold-start delta recorded; `setup()` total on 16e simulator materially down. Honest remainder: store open/validation (~1.75s in the May profile) is NOT addressed by this unit — if the post-fix total still exceeds the ~1s origin target, document the remainder as intentional-or-future per the origin's success criterion.

### Phase F — Deprecations (#41)

### U10. Delete dead navigation wrappers

**Goal:** 3 of 8 warnings gone by removing dead code.

**Requirements:** R1, R9.

**Dependencies:** None.

**Files:**
- Delete: `Pilgrim/Extensions/SwiftUI/NavigationLink.swift`, `Pilgrim/Extensions/SwiftUI/View+Navigation.swift`
- Modify: `README.md` (fix "11-version" → 12-version chain drift while touching docs)

**Approach:** delete; build. Zero call sites verified by research (grep for `.onNavigation(`, `.navigation(item:`, `.navigation(isActive:`, `NavigationLink(item:`).

**Test scenarios:** `Test expectation: none — dead-code deletion; full build + suite is the proof.`

**Verification:** build clean; warning count drops by 3; all navigation flows exercised in runtime pass (NavigationStack roots were already modern).

### U11. AVURLAsset async duration loading

**Goal:** 2 warnings gone; recovery semantics preserved.

**Requirements:** R1, R9.

**Dependencies:** U1 lands first (same file; U1 owns the recovery-ordering semantics this must preserve).

**Files:**
- Modify: `Pilgrim/Models/Walk/WalkSessionGuard.swift` (`defaultDurationProbe`, `reconnectOrphanedRecordings`)
- Test: extend `UnitTests/WalkSessionGuardRecoveryTests.swift`

**Approach:** the recovery call graph is synchronous completion-handler code (`sanitizeRecording` takes a sync `durationProbe: (URL) -> Double` invoked inside `.map`), and continuations cannot bridge sync→async — so do NOT convert to `await asset.load(.duration)`. Instead replace the deprecated probe with a synchronous, non-deprecated `AVAudioFile(forReading:)`-based duration (`length ÷ processingFormat.sampleRate`; throws on malformed files → return 0, preserving the existing sanitize fallback path). Kills both warnings with zero call-graph restructuring. Recovery outcomes (durations on reconnected recordings) must be identical.

**Test scenarios:**
- Happy: orphaned recording fixture with valid audio file → duration recovered, same value as before migration.
- Error path: missing/corrupt audio file → same fallback duration behavior as current code.

**Verification:** recovery tests green; warnings −2.

*(U12 relocated to Phase D — it gates U6's work in the same file. Phase F retains the two remaining #41 clusters.)*

### Phase G — Compliance (security/privacy)

### U13. WeatherKit key removal + privacy honesty

**Goal:** No private key in the bundle; permission strings and privacy manifest tell the truth.

**Requirements:** R5, R6 — AF18, AF19, AF41 (+ attribution check).

**Dependencies:** None.

**Files:**
- Delete: `Pilgrim/Models/Weather/WeatherKitREST.swift`
- Modify: `Pilgrim/Models/Weather/WeatherService.swift` (drop fallback, graceful degradation), `Pilgrim/Support Files/Info.plist` (remove WeatherKit key entries; fix `NSPhotoLibraryUsageDescription`), `Secrets.xcconfig` references (Podfile post_install untouched unless key injection lives there), `Pilgrim/PrivacyInfo.xcprivacy` (declare photos, audio/user content where required by collected-data taxonomy), `Pilgrim/Support Files/*.lproj/InfoPlist.strings` (keep ≥ Info.plist accuracy per CLAUDE.md)
- Test: `Test expectation: none — config/manifest change; build + a weather-fetch failure-path check in runtime pass`

**Approach:** native WeatherKit only; on failure show the existing no-weather state (verify `ActiveWalkViewModel.fetchWeather` generation-retry handles absence gracefully). Photo string: must cover BOTH transmission vectors — share upload AND `.pilgrim` export embedding (e.g., "only copied or shared when you explicitly include them in a shared walk or export"). Privacy manifest: add the concrete `NSPrivacyCollectedDataType` entries by name — `AudioData` (podcast voice recordings), `PhotosOrVideos` (share), `OtherUserContent` (journal/intention/reflection text in shares) — not tracking, app-functionality purpose. Device token: downgrade keychain token to UserDefaults-backed per Assumptions (verify the worker treats it as opaque). Check `WeatherService.attribution` display; add the mark/link if absent (small UI addition near weather display).

**Key revocation (P0, out-of-band):** the ES256 key shipped in every v1.0–v1.6 IPA and remains mintable until revoked. Revoke it in the Apple Developer portal (team YCF2TGZAX8 → Keys) concurrent with the v1.7.0 release — zero cost to new builds since `WeatherKitREST.swift` is deleted; old builds degrade to the native-primary path. **This is a user action — flag it at PR time and in the release checklist.**

**Test scenarios:**
- Error path: WeatherKit native call fails (airplane mode in runtime pass) → no crash, weather hidden, retry path silent.

**Verification:** `grep -i weatherkit` shows no key material across repo INCLUDING `Secrets.xcconfig*`, build scripts, and `.github/workflows/` (check `gh secret list` for `WEATHERKIT_PRIVATE_KEY` — delete the CI secret if present); IPA-shaped build contains no key; manifest passes App Store validation in a later archive (release flow); key-revocation step recorded in PR description.

### Phase H — UX conformance

### U14. Design-system conformance sweep

**Goal:** Typography and shadow tokens hold everywhere, including the widget.

**Requirements:** R5, R6 — AF25, AF39, AF44, AF55, AF56, AF67, AF68, AF69, AF71, AF73, AF74.

**Dependencies:** None.

**Files:**
- Modify: cairn badge view, weather/celestial vignette capsules, active-walk audio indicator buttons, archived-walks card, journal walk dots (shadow fixes), voice recordings count badge, `PilgrimWidget/PilgrimHomeWidget.swift` + `PilgrimWidgetLiveActivity.swift` (fonts + color parity), `Pilgrim/Support Files/Assets.xcassets/fog.colorset/Contents.json` (only if nudging)
- Test: `Test expectation: none — visual conformance; verified by dark/light runtime pass screenshots`

**Approach:** shadows → fixed colors (memory rule: adaptive ink/fog invert to halos in dark mode); fonts → `Constants.Typography.*`; widget colors → match asset catalog values (or reference shared assets if target membership allows); AF68 per Assumptions (nudge or disposition) — if nudged, the same fog values live in pilgrim-viewer CSS and pilgrim-worker templates (out of scope here): file follow-up issues in those repos at merge time so the brand canon re-syncs. Widget fonts: brand fonts require the font files in the widget target — verify license/embedding; **committed fallback** if extension memory budget rejects embedding: `.system(design: .serif)` for Cormorant Garamond roles, plain `.system` for Lato roles, logged accepted-with-reason.

**Verification:** dark-mode screenshot sweep shows no bright halos; widget side-by-side matches app palette.

### U15. Accessibility sweep

**Goal:** VoiceOver, Dynamic Type, Reduce Motion, and tap-target floors hold on every primary screen.

**Requirements:** R5, R6 — AF29, AF47, AF48, AF49, AF50, AF53, AF54, AF57, AF58, AF59, AF62, AF63, AF64, AF65, AF66, AF72.

**Dependencies:** U18 touches PermissionsView too — land U15 first, U18 rebases on it.

**Files:**
- Modify: `Pilgrim/Scenes/Meditation/MeditationView.swift` (options discoverability + breath count label + Reduce Motion), `Pilgrim/Scenes/Goshuin/GoshuinFAB.swift`, `Pilgrim/Scenes/Home/WalkStartView.swift` + `WalkDotView.swift`, `Pilgrim/Scenes/WalkSummary/` (timeline bar, waveform scrubber, transcription buttons, stat cycling), `Pilgrim/Scenes/SealReveal/SealRevealView.swift`, `Pilgrim/Scenes/Setup/Permissions/PermissionsView.swift`, `Pilgrim/Models/Podcast/PodcastSubmissionView.swift`, scenery animation gating
- Test: `Test expectation: none — accessibility tree changes; verified via VoiceOver/Accessibility-Inspector pass in U19`

**Approach:** mirror in-repo reference patterns (`FaviconSelectorView` for `.isSelected`, `AboutView.statsWhisper` for real Buttons, `RippleEffectView` for Reduce Motion). Gesture-only interactions get parallel accessible affordances (accessibilityAction / adjustable). 44pt floors via contentShape/frame. Fixed-size fonts → scaled equivalents (`Constants.Typography` should already scale; where it uses fixed sizes, apply relative metrics). Committed specifics from doc review:
- AF47 (meditation options): ship a small visible ellipsis affordance at the edge of the breathing circle in addition to `accessibilityAction` — covers Switch Access / motor-impaired users who can't sustain a 1s long-press; the long-press remains as a shortcut to the same sheet.
- AF62 (seal reveal): suppress the 2.5s auto-dismiss while `UIAccessibility.isVoiceOverRunning` so the share action is reachable; mirror the existing `isReduceMotionEnabled` gating pattern.
- AF63 (waveform scrubber): `accessibilityAdjustableAction` stepping ±10% via the existing seek path.

**Verification:** Accessibility Inspector audit on welcome, home, active walk, summary, meditation, settings: no unlabeled interactive elements; AX5 text size renders without overlap on stats panel (collapsible panel memory says this was already designed for — confirm).

### Phase I — Feedback honesty and polish

### U16. User-facing failure honesty

**Goal:** Operations that fail stop reporting success.

**Requirements:** R5, R6 — AF23, AF32, AF45, AF60, AF75.

**Dependencies:** None.

**Files:**
- Modify: voice-guide pack download progress path, auto-transcription state machine (`Pilgrim/Models/TranscriptionService.swift` / summary VM), `LiveStats` permission signal subscriber (ActiveWalk setup path), seal share sheet sequencing, `Pilgrim/Support Files/en.lproj/Changelog.strings` (populate or remove the dangling lookup)
- Test: extend transcription tests for all-failed → `.failed` state; download-failure aggregation test

**Failure-surface visual language** (committed per doc review — no raw error text in the wabi-sabi UI; the existing "Microphone Required" alert is the in-repo error-pattern precedent):
- AF23 voice-guide download failure → inline "Download failed — tap to retry" label replacing the progress indicator, consistent with the existing download affordance.
- AF32 all-transcriptions-failed → a `.failed` state rendered as caption-size fog-toned message + retry in `Constants.Typography.button` style.
- AF45 permission failure during walk setup → extend the Microphone-Required alert model with a Settings deep link.
- AF60 → sequencing fix only, no new error surface.

**Test scenarios:**
- Error path: all pack files fail → download UI shows failure, not 100% success (AF23).
- Error path: every recording fails transcription → state ≠ .completed, user-visible retry (AF32).
- Happy/edge: seal share → both summary dismissal and share sheet present correctly in sequence (AF60).

**Verification:** tests green; runtime pass exercises failure paths via airplane mode.

### U17. Polish sweep (P1–P14)

**Goal:** Each trivial polish item fixed or dispositioned in the log.

**Requirements:** R6.

**Dependencies:** After U3/U6/U7 (some polish items live in the same files; cheap rebases).

**Files:** per `docs/brainstorms/2026-06-11-audit-findings.md` Polish section (14 items across players, scenery, design tokens).

**Approach:** opportunistic one-liners during the relevant concern commits where possible; remainder as one `chore(polish):` commit. Items that turn out wrong → disposition false-positive (they were unverified).

**Test scenarios:** `Test expectation: none — trivial fixes; suite + runtime pass cover regressions.`

**Verification:** disposition log lists all 14 with outcomes.

### Phase J — #43 feature

### U18. Onboarding delight: Wander Zoom + permission ritual

**Goal:** #43's confirmed A+B direction ships per the issue's acceptance criteria.

**Requirements:** R4, AE2, AE3.

**Dependencies:** U15 (PermissionsView), U3 (BellPlayer/coordinator semantics stable).

**Files:**
- Modify: `Pilgrim/Scenes/Setup/Welcome/WelcomeView.swift`, `Pilgrim/Scenes/Setup/Welcome/WelcomeAnimationState.swift`, `Pilgrim/Scenes/Setup/Permissions/PermissionsView.swift` + `PermissionsViewModel.swift`
- Test: new `UnitTests/PermissionRitualTests.swift` (bell-once-per-grant logic, soundsEnabled gate)

**Approach:** per issue #43's implementation sketch — Begin tap: logo 1.0→1.4 ease-out 0.4s, parallel fades 0.3s, cross-dissolve 0.15s (~0.55s total); Reduce Motion → existing jump-cut. **Sequencing vs the existing exit animation** (doc-review catch): the zoom and `runExit`'s logo-fade must be sequential, not simultaneous — `beginWanderZoom()` runs first and `runExit()` fires from its completion, so the scale-up isn't fighting the 0.5s `showLogo=false` fade. Permission grant: bell (existing meditation-end sample, ~0.6s) + checkmark pulse after the iOS dialog resolves — pulse spec: scale 1.0→1.15→1.0, `spring(response: 0.4, dampingFraction: 0.6)`, one-shot. Denial → nothing; once per grant, **persisted per-permission in UserDefaults** (UserPreferences pattern) so re-entering onboarding or relaunching doesn't replay the bell; respects `soundsEnabled`; Reduce Motion keeps bell, skips pulse. Deferred to implementation: whether a grant also gets the welcome flow's haptic (consistency with `WelcomeAnimationState` footprint haptics — add if it feels coherent in the runtime pass).

**Test scenarios:**
- Happy: grant fires bell exactly once; second grant event for same permission → no bell.
- Edge (Covers AE2): Reduce Motion on → zoom skipped, jump-cut preserved.
- Edge (Covers AE3): denial → no bell, no pulse, row state updates.
- Edge: `soundsEnabled == false` → pulse only, no bell.

**Verification:** onboarding runtime pass on simulator (fresh install) with and without Reduce Motion.

### Phase K — Verification

### U19. Runtime pass, full verification, disposition log

**Goal:** R7's runtime pass executed; every finding's final status recorded; suite/lint/warnings gates pass.

**Requirements:** R6, R7, R8, R9, AE4 — origin success criteria.

**Dependencies:** All units.

**Files:**
- Create: disposition log content (PR description section; working copy may live alongside the plan)
- Test: full `UnitTests` + `ScreenshotTests` on iPhone 17 Pro Max + 16e sims

**Approach:** scripted demo-mode walkthrough (onboarding fresh-install, walk start/pause/finish with soundscape + voice note, meditation, summary playback + dismiss-mid-playback, import/export round-trip, settings flows) in light + dark + AX5 text; Instruments spot checks (Leaks on walk cycles, Time Profiler on long walk, display-link cadence on paused map); TSan UnitTests run; full-repo `swiftlint`; warning-count check (target: 1 intentional); `[LaunchProfile]` cold-start measurement recorded into issue #42 disposition; assemble fixed/dispositioned table for all AF1–77, U1–3, P1–14, X1–5.

**Verification:** every origin success criterion checked off; zero undispositioned findings; tests green on both simulators.

---

## System-Wide Impact

- **Interaction graph:** AudioSessionCoordinator changes touch all 9 consumer classes — the arbitration redesign is the widest blast radius in the PR; its unit tests + runtime audio scenarios are the containment. Launch-sequence serialization (U1) changes AppDelegate completion ordering — `[LaunchProfile]` marks guard against re-introducing main-thread stalls.
- **Error propagation:** U1/U2/U16 collectively shift the data layer from swallow-and-continue to propagate-or-display; check every new surfaced error has a sane UI landing (no raw error text in wabi-sabi UI).
- **State lifecycle risks:** U4's builder lifecycle changes interact with U1's cancel-path fixes — cancelled walks must both release memory AND preserve recovery invariants.
- **API surface parity:** widget target (U14) must keep building; no app-target-only symbol leaks into widget sources.
- **Integration coverage:** interruption → resume (U3) and recovery → sweep ordering (U1) are the two cross-layer behaviors unit tests alone cannot fully prove — both have explicit runtime-pass scenarios in U19.
- **Unchanged invariants:** CoreStore schema contents, migration chain, frozen identifiers, `healthKitUUID`, `.pilgrim` format, UTI declarations, GPX import-only stance — all untouched. R11 holds across every unit.

---

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Coordinator arbitration regresses a working audio flow | Med | High | Test-first arbitration table; runtime audio scenarios (walk+soundscape+voice note+interruption); per-concern commit isolates revert |
| versionLock DEBUG-gating hides a real schema edit someday | Low | Med | Locks stay active in DEBUG where development happens; CI runs DEBUG builds |
| `.cascade` silently changes version hash | Low | High | Hash-assertion test decides mechanism before any commit ships it |
| Async recovery migration (U11) alters crash-recovery timing | Med | High | U1 lands first with characterization tests; U11 preserves outcomes under the same fixtures |
| Big-PR review fatigue | High | Med | Per-concern commits in phase order; disposition log doubles as review map |
| SwiftLint type_body_length errors on touched giants (WalkSummaryView, ActiveWalkView, InkScrollView) | High | Low | Extract subviews opportunistically; full-repo lint before push |
| Touch on paused map restarts rendering (DEBUG assert / silent release un-pause) | Med | Med | `isUserInteractionEnabled = false` while paused — gesture-handler disabling alone does NOT stop UIResponder touch delivery |

---

## Documentation / Operational Notes

- Update issue #41/#42/#43 with close comments (numbers for #42; disposition for compression).
- README migration-chain count fix rides U10.
- **Revoke the WeatherKit ES256 key in the Apple Developer portal** (team YCF2TGZAX8 → Keys) concurrent with the v1.7.0 release — user action, tracked in the PR checklist (see U13).
- **Sync the App Store Connect privacy nutrition label** with the expanded PrivacyInfo.xcprivacy before the v1.7.0 submission — a manifest/label mismatch is a metadata rejection.
- Release execution (changelog, TestFlight) is post-PR via the existing `/release` flow; TestFlight dispatch requires explicit user approval.

---

## Sources & References

- **Origin document:** docs/brainstorms/2026-06-11-finalization-pass-requirements.md
- **Findings:** docs/brainstorms/2026-06-11-audit-findings.md (+ raw verifier reasoning: session workflow output)
- Related issues: #41, #42, #43
- External: CoreStore 9.x source (SchemaHistory/versionLock), Mapbox 11.20.0 MapView source (`displayState`, `preferredFrameRateRange`), Apple WeatherKit REST auth doc ("Never distribute your private key"), Apple CADisplayLink `preferredFramesPerSecond` semantics, Apple NavigationStack migration guide.
