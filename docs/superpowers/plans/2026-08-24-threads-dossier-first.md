# Threads Dossier-First Refit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Remove the Stage 3 surfaces (threads card, thread history, lunation recap, release gesture) after the field verdict — the AI-prompt dossier is the feature's home — and fix the junk-theme bug (auxiliary/modal/light verbs threading as themes) at the extractor.

**Architecture:** The data layer survives untouched in role: TranscriptNLP → ThemeExtractor → TranscriptContext(Store) → ThreadStore → ThreadsDossierBuilder feeds AI prompts; ThreadIntentionSuggestions feeds the intention chips (kept). Everything that rendered threads directly to the walker is deleted, along with the released-threads concept it carried. Themes become nouns-only with a small light-noun stoplist; a shared spoken-scaffolding stoplist also cleans the recurring-word attention directive. Extractor semantics change ⇒ backfill completion key bumps to V3.

**Field context (2026-08-24, build 106):** Real-device themes were "was / have / can / think" — spoken-English scaffolding tagged as verbs, passing the [noun, verb, adjective] filter and winning every raw-frequency ranking. User verdict: kill the card (prompts already carry themes, with an LLM to contextualize them); keep chips; keep dossier. LunationCalendar is intentionally retained — the follow-up dossier PR ("the moon line") consumes it.

## Global Constraints

- Suite baseline 1364 tests at branch base `f14323a`; reconcile every count via `grep -c "Test Case '.*' started"` (summary lines lie under the macos-26 sim flake; retry once before believing a failure).
- SwiftLint full-repo baseline 401 warnings / 0 errors. Deletions will LOWER the count (the spec-pinned 7-param LunationRecapModelBuilder warning dies with its file) — record the new baseline in the final task; zero NEW findings.
- pbxproj is classic format, hand-edited: file deletions remove exactly 4 entries per file (PBXBuildFile, PBXFileReference, group child, Sources/Resources build phase); `plutil -lint Pilgrim.xcodeproj/project.pbxproj` must pass after every pbxproj edit.
- Full app build (`xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build`) succeeds before every commit.
- Test hygiene: dataStack restore-not-nil in tearDowns; UserDefaults save/restore for every key a test mutates.
- Comment policy: comments state constraints code can't show; no what-comments.
- Typography `Constants.Typography.*` only; intention-screen fix must match the "Recent" section's exact layout modifiers.
- `threadsAfterWalks` toggle sovereignty unchanged: off = no computation (backfill, dossier, chips).
- Intention echo in AttentionDirectives keeps verbs — the noun restriction applies to THEME extraction only.

## Execution status

- Task 1: COMPLETE — commit `c364907`, review Approved (suite 1368).
- Task 2: COMPLETE — commit `e454430`, review Approved (suite 1353).
- Task 3: COMPLETE — commit `affd1c3`, review pending at time of writing (suite 1284). NOTE: this plan file was collateral damage of a subagent `git stash` during T2/T3 (it was untracked); restored from the session record and committed afterward — the restored text is verbatim except this Execution-status section.
- Task 4: pending.

---

### Task 1: Noun-only themes + spoken stoplist + backfill V3

**Files:**
- Modify: `Pilgrim/Models/Threads/TranscriptNLP.swift` — `contentLemmaMentions(in:)` gains a `classes: Set<NLTag> = [.noun, .verb, .adjective]` parameter (default preserves existing callers: intention echo, insight words).
- Modify: `Pilgrim/Models/Threads/ThemeExtractor.swift` — `mentions(in:)` requests `classes: [.noun]`; new `lightNouns` stoplist filtered alongside `walkingDomain`.
- Create (type only, in ThemeExtractor.swift or TranscriptNLP.swift — implementer's judgment, no new file): `SpokenStoplist` with two sets: `lightNouns` (themes) = ["thing", "things", "stuff", "kind", "sort", "lot", "bit", "way", "ways", "one", "ones", "something", "anything", "everything", "nothing"], `scaffoldLemmas` (recurring-word) = ["be", "have", "do", "get", "go", "come", "make", "take", "know", "think", "say", "see", "want", "mean", "feel", "need", "let", "put", "keep", "kind", "thing", "stuff", "way", "lot", "bit"].
- Modify: `Pilgrim/Models/Prompt/AttentionDirectives.swift` — recurring-word detector skips `SpokenStoplist.scaffoldLemmas`.
- Modify: `Pilgrim/Models/Threads/ThreadsBackfill.swift` — `completedKey` → `"threadsBackfillCompletedV3"`; legacy-removal now clears BOTH `"threadsBackfillCompleted"` and `"threadsBackfillCompletedV2"`.
- Test: `UnitTests/` — extend the theme/directive/backfill test files in place.

**Interfaces:**
- Produces: `TranscriptNLP.contentLemmaMentions(in:classes:)`; `SpokenStoplist.lightNouns` / `.scaffoldLemmas`; ThemeExtractor emits nouns only.
- Consumers unchanged: ThreadStore, ThreadsDossierBuilder, ThreadIntentionSuggestions, TranscriptContextAnalyzer.

**Steps (TDD):**
- [x] RED: theme test — transcript ≥25 words of pure scaffolding yields ZERO themes; transcript with "music" ×3 among scaffolding yields exactly the "music" theme.
- [x] RED: recurring-word test — "think" ×4 does NOT fire; "river" still fires; `testRecurringWord_countsAcrossInflections` ("move") still passes.
- [x] RED: backfill test — seed `threadsBackfillCompletedV2` = true, assert `isComplete` false.
- [x] Implement minimally; intention-echo tests ("worrying", "grieving") stay green untouched.
- [x] Verify + commit `fix(threads): themes are nouns — spoken scaffolding can no longer thread`.

### Task 2: Unwire the released-threads concept from the engine

**Files:**
- Modify: `Pilgrim/Models/Threads/ThreadStore.swift` — remove `released:` parameter from `build`.
- Modify: `Pilgrim/Models/Prompt/AttentionDirectives.swift` — remove releasedLemmas skip (Task 1's stoplist supersedes it).
- Modify: `Pilgrim/Models/Threads/ThreadsDossierBuilder.swift`, `ThreadIntentionSuggestions.swift` — remove releasedToken from memo keys and the released set from calls.
- Modify: `Pilgrim/Models/Data/DataManager.swift` — remove `releasedThreadsStore` / `lunationRecapState` seams and their deleteAll clears; remove `threadsReleaseCaptionShown` reset.
- Modify: `Pilgrim/Models/Preferences/UserPreferences.swift` — remove `threadsReleaseCaptionShown`.
- Modify: `Pilgrim/Models/Data/PilgrimPackage/PilgrimPackageModels.swift`, `PilgrimPackageConverter.swift`, `PilgrimPackageImporter.swift` — remove the released-threads carve-out (fields are additive/optional; packages from build ≤106 still decode).
- Test: delete `ThreadsReleaseFilteringTests` + `ReleasedThreadsPackageTests` (4 pbxproj entries each); trim `AttentionDirectivesTests`, `ThreadIntentionSuggestionsTests`, `DataManagerThreadsDeletionTests`, `PilgrimPackageExporterArchivedTests`.

**Interfaces:**
- Produces: `ThreadStore.build(contexts:walks:)` (no released param).
- Compile-order note: ReleasedThreadsStore/LunationRecapState FILES survive this task (deleted in Task 3); only their consumers are severed here. Both tasks each end green.

**Steps (TDD):** [x] all — commit `refactor(threads): the released concept returns to the engine — no surface, no carve-out`.

### Task 3: Delete the surfaces

**Files (delete, each with 4 pbxproj entries):**
- `Pilgrim/Scenes/WalkSummary/ThreadsCardSection.swift`, `WalkSummaryView+Threads.swift`, `ThreadHistoryView.swift`, `LunationRecapView.swift`
- `Pilgrim/Scenes/Settings/PastRecapsListView.swift`, `ReleasedThreadsListView.swift`
- `Pilgrim/Models/Threads/ThreadHistoryModel.swift`, `ThreadsCardModel.swift`, `ThreadsTexture.swift` (verified: only card/recap consumers — deleted), `ReleasedThreadsStore.swift`, `ReleasedThreadsCopy.swift`, `LunationRecapModel.swift`, `LunationRecapState.swift`
- KEEP: `LunationCalendar.swift` + `LunationCalendarTests.swift` (follow-up dossier PR consumes it — deliberate, not dead code).
- Tests (delete): `ThreadsCardModelTests`, `ThreadHistoryModelTests`, `LunationRecapModelTests`, `LunationRecapStateTests`, `ReleasedThreadsStoreTests`, `ReleasedThreadsInteractionTests`.
- Modify: `WalkSummaryView.swift` — remove `showsThreadsCard`, card/recap/theme state, `ThreadsCardReloadKey` task, onChange reloads, sheets, invitation row (outcome verified byte-identical to pre-Stage-3 `6d77706`).
- Modify: `VoiceCard.swift` — remove Released-threads and Past-recaps rows and state; Thought Threads toggle stays.
- Modify: `UnitTests/DataManagerThreadsDeletionTests.swift` — final trim (already at target from T2).

**Steps:** [x] all — commit `refactor(threads): the card returns to silence — dossier and chips carry the feature`.

### Task 4: Intention-screen alignment + verification + spec addendum

**Files:**
- Modify: `Pilgrim/Scenes/ActiveWalk/IntentionSettingView.swift` — the "Recurring" section floats centered: pin it full-width leading exactly as the "Recent" section does (read Recent's modifier chain; likely `.frame(maxWidth: .infinity, alignment: .leading)` on the section container).
- Modify: `docs/superpowers/specs/2026-08-22-thought-threads-design.md` — addendum: "Stage 3 field verdict (2026-08-24)": card/recap/history/release removed after real-device contact (junk themes + redundancy with dossier); themes nouns-only; chips kept; dossier-first direction with the four approved upgrade tracks named (place-theme resonance, the moon line, body & sky, small signatures + photo adjacency + theme-marker coloring).
- Verification: full suite reconciled; build; lint new baseline recorded; grep sweep proving no orphan references (`ReleasedThreads`, `LunationRecap`, `ThreadsCard`, `ThreadHistory`, `threadsReleaseCaptionShown`, `showsThreadsCard`) outside git history/spec/plan docs.

**Steps:** alignment fix (visual parity with Recent — no unit test possible, note for human smoke) → spec addendum → sweeps → commit `fix(intention): the Recurring shelf stands with Recent — flush left, full width`.
