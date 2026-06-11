---
date: 2026-06-11
topic: finalization-pass
---

# v1.7.0 Finalization Pass

## Summary

One PR that finalizes Pilgrim iOS for v1.7.0: it closes the three open issues (#41 deprecation cleanup, #42 launch-latency remainder, #43 onboarding delight) and fixes every defect surfaced by a multi-agent adversarial code audit plus a runtime verification pass. Done means the known-rough-edges list is empty — every finding fixed or explicitly dispositioned.

---

## Problem Frame

v1.6.0 is shipped and the app feels great in daily use — its most frequent user has no rough-edges list of his own. But "feels great" and "is sound" are different claims: the March 2026 audit passes found 15 real bugs in an app that also felt fine at the time, and this codebase's highest-stakes failure classes (resource leaks compounding over multi-hour walks, audio-session edge cases, data-layer integrity) are precisely the ones daily use doesn't surface. Three issues remain open with documented remaining work, including ~2.1s of avoidable launch cost and 8 deprecation warnings sitting on regression-sensitive code paths. New feature work is queued behind this; any hidden defect shipped under new features becomes harder to attribute and fix later.

---

## Requirements

**Known issue resolution**

- R1. All 8 deprecation warnings from #41 are resolved (NavigationLink value-based migration, AVURLAsset async duration loading, MetalKit frame-rate migration), with existing behavior preserved: all navigation flows, walk-recovery semantics, and battery-saving render pause during long walks.
- R2. The ~880ms post-setup stall from #42 is eliminated: the synchronous prelude inside the fire-and-forget manifest syncs no longer burns CPU during the WelcomeView entrance.
- R3. The 1.2s CoreStore model-resolution cost from #42 is investigated. Compression of the migration chain ships only if the investigation confirms a big launch-time win at acceptable data-safety risk; otherwise no new migration ships and the finding is closed with the measured numbers as disposition.
- R4. #43 ships its confirmed direction: Wander Zoom on Begin tap and permission-grant bell + pulse, honoring the acceptance criteria already recorded on the issue (reduce-motion fallback, `soundsEnabled` preference respected, bell once per grant, no feedback on denial).

**Hidden-defect discovery**

- R5. A multi-agent adversarial audit reviews the app across defect lenses at minimum: resource leaks (timers, audio players, Combine subscriptions, location/motion callbacks), data safety, error propagation, performance, design-system/typography conformance, accessibility, and dark mode. Every finding is adversarially verified before entering the fix list.
- R6. Disposition rule: every verified finding is either fixed in this PR or explicitly dispositioned as false-positive or accepted-with-reason. The disposition log ships in the PR description. An accepted-with-reason item does not count as a rough edge.
- R7. A runtime pass drives the app through its primary flows (onboarding, walk start/pause/finish, meditation, voice recording, settings, import/export) plus dark mode and large accessibility text sizes. Runtime findings join the same list and follow R6.

**Verification and release readiness**

- R8. Full test suite passes; new behavior is covered by tests where the project's conventions make it testable.
- R9. Zero deprecation warnings in app sources after the PR (Pods and system noise excluded).
- R10. The branch is organized as per-concern commits so a post-merge defect can be bisected within the branch even though it merges as one PR.
- R11. Frozen constraints hold throughout: CoreStore string identifiers, `healthKitUUID`, `SwiftUI.ProgressView` qualification, Info.plist/UTI rules. No refactor may require a schema migration except under R3's condition.

---

## Acceptance Examples

- AE1. **Covers R3.** Given the investigation measures model-resolution savings, when the projected cold-launch improvement is large (on the order of the ~1.2s identified in #42) and migration tests pass against real-shaped legacy data, the compression ships; when the win is marginal or the risk disproportionate, no new migration ships and the issue closes with measured numbers as the disposition.
- AE2. **Covers R4.** Given Reduce Motion is enabled, when the user taps Begin, the zoom is skipped and the existing jump-cut transition plays unchanged.
- AE3. **Covers R4.** Given the user denies a permission, no bell or pulse plays and the row updates exactly as it does today.
- AE4. **Covers R6.** Given a verified finding the project chooses to keep (e.g., an intentional ritual delay), the PR description records it as accepted-with-reason and it does not block "done."

---

## Success Criteria

- Issues #41, #42, and #43 are closed by this PR — each fully resolved, or closed with a documented disposition for the conditional piece (R3).
- The combined audit + runtime findings list reaches zero open items: everything fixed or dispositioned.
- Cold launch to WelcomeView meets #42's target (~1s on the lowest-spec target) or the remaining gap is documented as intentional ritual time.
- Test suite green; the runtime pass completes with no undispositioned findings.
- Handoff quality: planning could enumerate all work directly from this document, the three issues, and the audit output without inventing scope.

---

## Scope Boundaries

- No field-signal mining: TestFlight crash reports, beta feedback, and App Store reviews are not discovery inputs for this pass.
- No new-feature ideation. QoL improvements are limited to what the audit and runtime pass surface; dreaming up new QoL features is post-finalization work.
- No new schema migration unless R3's big-win condition is met.
- Sibling repos (landing page, worker, viewer) are untouched.
- Release execution (TestFlight soak, App Store submission) happens after the PR and is not part of this scope; TestFlight dispatch additionally requires explicit user approval.

---

## Key Decisions

- One big PR instead of incremental slices: explicit user override of the house incremental-changes style for a single finalization sweep. R10 (bisectable per-concern commits) is the compensating control.
- Discovery is "B then C": a multi-agent adversarial audit builds the code-level findings list, then a runtime pass catches feel-level issues and doubles as the post-fix verification gate. Chosen over solo review (single perspective) and runtime-only (misses slow-compounding defects).
- Migration guard: no new migration machinery without a confirmed big win (user-stated rule).
- "No known rough edges" is operationalized by R6's disposition rule rather than "fix literally everything."
- #43 stays inside the finalization fence despite being a feature: it is one of the three open issues, and it shares the launch path with #42's work — doing both in one branch avoids sequential rework.

---

## Dependencies / Assumptions

- Ships as v1.7.0, the next minor after the shipped 1.6.0.
- The May 2026 profiling numbers recorded on #42 (~880ms stall, ~1.2s model resolution, ~1.75s store open) still approximately hold on current main.
- #43's A+B direction remains confirmed scope per the issue thread; no re-brainstorm needed.
- The multi-agent audit's token cost is accepted (user selected this approach explicitly).

---

## Outstanding Questions

### Deferred to Planning

- [Affects R3][Needs research] What launch-time saving is actually achievable from migration-chain handling, and which mechanism is safest? This investigation is itself a planned work item.
- [Affects R1][Technical] The exact pause mechanism replacing `preferredFramesPerSecond = 0` that preserves zero-rate battery behavior with the current Mapbox SDK.
- [Affects R5][Technical] Final lens list and agent counts for the audit workflow.
- [Affects R7][Technical] Whether a simulated long walk (City Run) is feasible in the automated runtime pass or is covered by demo mode plus targeted manual checks.
