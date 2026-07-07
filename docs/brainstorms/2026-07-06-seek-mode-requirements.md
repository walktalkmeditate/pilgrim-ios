---
date: 2026-07-06
topic: seek-mode
---

# Seek Mode

## Summary

Seek becomes Pilgrim's third walk mode: the walker picks how long they have, sets an intention, and the app hides one to three randomly generated clearings under fog on the map. A single pulse clock guides them — puck rings and haptics in hand, a soft audio ping in the pocket, tightening rings on the lock screen — and stillness at each clearing reveals the next. Signs are marked with the tools the app already has, and the walk itself starts, records, and ends exactly like Wander.

---

## Problem Frame

The home screen has promised Seek ("follow the unknown") since the mode selector shipped, but the card has stayed unavailable. Wander serves walkers who already know where they're going — or don't care — but nothing in the app answers the walker who has an hour and an intention and no destination. Their walks default to the same familiar loops, and the contemplative frame the app is named for (walking toward something unknown, with intention) has no mode of its own.

Randonautica proved the appetite for random-destination walking, but with baggage Pilgrim must not inherit: a screen-first experience, exact points that land in lakes and private yards, red/wrong-direction punishment mechanics, and network-dependent randomness wrapped in pseudoscience.

---

## Key Flows

- F1. Begin a seek
  - **Trigger:** Walker taps Seek on the home screen.
  - **Steps:** One question — "How long do you have?" (four presets, last choice pre-selected) → intention (required; existing intention step with text, voice, and suggestions) → a brief stillness moment → the first fog condenses on the map and the first pulse sounds.
  - **Outcome:** Walker is walking within a minute, inside the ritual, with one fogged clearing calling.
  - **Covered by:** R1, R2, R3, R4

- F2. Guidance loop
  - **Trigger:** A clearing is active and the walker is moving.
  - **Steps:** The pulse clock fires on a cadence that shortens with distance. Each pulse renders on whichever surfaces are live: puck ring + haptic in hand, audio ping in the pocket; the lock-screen Live Activity follows the same clock at its own budgeted cadence. Fog over the clearing thins as distance closes.
  - **Outcome:** The walker can navigate by feel from any phone context, and is never told they are "wrong."
  - **Covered by:** R6, R7, R8, R9, R11, R12

- F3. Arrival and reveal
  - **Trigger:** Walker crosses into the clearing region.
  - **Steps:** Fog dissolves; arrival haptic/audio moment. Walker explores and marks signs (photos, waypoints, cairns, whispers). Stillness is detected automatically → breath-rhythm haptics (if in hand) → a bowl tone → one whisper from the walker's downloaded categories plays → the next fog condenses and a new, distant pulse begins. At the final clearing the bowl tone closes the seeking and the engine goes quiet.
  - **Outcome:** The next unknown reveals itself as earned by presence; after the last, the walk continues as an ordinary walk.
  - **Covered by:** R12, R13, R14, R15, R16, R17

- F4. End and summary
  - **Trigger:** Walker taps End — the only way any walk ends.
  - **Steps:** Standard walk completion → summary shows the intention as header, clearing halos on the route map, an "unknowns found" note, and signs grouped by clearing.
  - **Outcome:** The seek reads as a story: what was sought, where the world answered, what was noticed.
  - **Covered by:** R1, R18, R19

---

## Requirements

**Setup and ritual**
- R1. Seek is selectable from the home screen and uses the standard walk lifecycle unchanged: start, pause, background recording, and ending only via the End button, identical to Wander.
- R2. Setup asks exactly one question — duration — via presets (30 min / 1 hr / 2 hrs / 3 hrs), with the last choice remembered and pre-selected. Duration is asked before intention. No other configuration appears in the setup flow.
- R3. Intention is required for a seek (it remains optional for Wander), reusing the existing intention step unchanged.
- R4. Clearing count (1–3) is drawn randomly within a band derived from duration (longer walks tilt toward more clearings; adjacent presets share overlapping bands) and never shown to the walker, so a repeat walker can never infer the count from the preset. For chains of two or more, the chain is generated so the final clearing lands near the starting point; a single-clearing seek is out-and-back, with the clearing at roughly two-fifths of the walkable distance. Generation assumes a contemplative pace (~24–25 min/mile) and reserves roughly a quarter of the time for stillness and exploration. Duration is a generation input only: nothing happens when the chosen time elapses mid-walk — no timer, no signal — the pulse simply continues until the walker ends the walk.
- R5. Clearings are generated with local system randomness only — no network calls, no external randomness services.

**Clearings and fog**
- R6. Each clearing is a region (roughly 80–120 m across) shown as fog on the map; the exact center coordinate exists only in the engine and is never displayed as a pin.
- R7. Fog thins progressively as the walker approaches, dissolves entirely when they enter the region, and revealed clearings stay revealed for the rest of the walk.

**Guidance**
- R8. A single pulse clock drives all guidance; its cadence shortens as distance to the active clearing closes. The in-hand surfaces (puck ring, haptic) and the pocket surface (audio ping) render each pulse in sync; the Live Activity reflects the same pulse clock's state at its own budgeted cadence (R12).
- R9. When the screen is on: each pulse renders as a ring from the puck, and as a haptic whose character encodes direction — a soft double-pulse when the walker's sustained heading (smoothed over ~15 s, generous cone) converges on the clearing, a single soft tick otherwise. Guidance is positive-only: no red states, no warning haptics, no wrong-direction feedback of any kind.
- R10. When the phone is locked or backgrounded: each pulse renders as a soft audio ping through background audio, mixed quietly beneath any soundscape and ducking under whispers and voice playback. The ping carries the same direction character as the haptic — a soft double-ping when the sustained heading converges on the clearing, a single ping otherwise — so the pocket walker gets alignment confirmation, not just distance. (iOS does not permit haptics from backgrounded apps; audio is the only pocket channel.)
- R11. The sonar sound has an enable toggle (default on) and a quiet-leaning volume setting, following the voice guide settings pattern: home in Sound Settings, mirrored during a seek in a seek-only section of the in-walk options sheet (present regardless of whether a soundscape or voice guide is active), never in the setup flow.
- R12. During a seek, the Live Activity shows distance to the active clearing in coarse steps with a tightening-rings visual, plus general direction relative to the walker's direction of travel while moving; distance only while stationary.

**Arrival, stillness, and reveal**
- R13. Arrival means crossing into the clearing region — never reaching an exact point — and is marked by an arrival haptic/audio moment alongside the fog dissolve.
- R14. Signs are marked with existing tools only: photos, waypoints, cairns, and whispers. No new content types, whisper categories, or seek-specific audio content.
- R15. Stillness at a clearing is detected automatically (no button) within a variable 45–90 s window. The reveal ritual: breath-rhythm haptics when in hand, a bowl tone, one whisper drawn from the walker's already-downloaded categories, then the next fog condenses and its pulse begins. If no whisper content is available locally, the ritual proceeds without the whisper. While the walk is manually paused, the seek engine — pulse clock, stillness window, grace timer — suspends, and resumes with the same active clearing when the walk resumes.
- R16. If the walker lingers at a clearing for several minutes without stillness being detected, the next clearing reveals anyway, quietly.
- R17. Seek has no failure states. The walker may request a fresh clearing whenever a way feels closed — physically, legally, or personally — via a single seek-only "Seek anew" action in the in-walk options sheet's seek section (alongside the sonar controls, R11). There is no separate skip action: walking on is always free, and declining a clearing is always a reroll. The walker may end at any time; the summary simply reflects whatever happened. A reroll regenerates the remainder of the chain under R4's constraints — remaining time budget, final clearing near start — and rerolls are uncapped by design. After the final clearing's reveal moment, the seek layer goes quiet — revealed halos remain on the map, all fog is gone, the puck ring stops pulsing — and the walk continues as an ordinary walk.

**Persistence and summary**
- R18. Arrivals are recorded as waypoints (distinguishable as seek arrivals) and the walk is marked as a seek via a walk event. Arrivals and the seek marker ride the existing walk checkpoint, so a crash mid-seek preserves them; the crashed walk is salvaged as a finished walk like every other mode (the app's crash recovery never resumes a live session, so a fresh seek after a crash starts a new chain). No database schema migration.
- R19. The walk summary extends the existing view for seek walks: intention as header, clearing halos on the route map, an "unknowns found" note, and signs grouped by the clearing they were marked in — one group per reached clearing (replacing the flat sign sections for seek walks only), with signs marked outside any clearing gathered in a closing "Along the way" group. The summary reflects only clearings the walker reached: no totals, no "X of Y" phrasing, and skipped or rerolled clearings never appear as halos or in the note. Wander summaries are unchanged.

**Engine seam**
- R20. The guidance/arrival engine consumes an ordered list of destinations; random generation is the only Seek-specific feeder. No routing, no offline tiles, no multi-day state — the seam exists so a future pilgrimage mode can feed real route stages into the same engine.

**Safety framing**
- R21. Copy frames each clearing as an invitation, not an instruction. On first seek only, a single caption-style line in the duration step carries the safety framing: never trespass, and the walker's own judgment ranks above the pulse — a clearing that feels unsafe or unwelcoming may be rerolled or skipped as part of the practice, not as failure. What keeps arrival on public ways is the generous region radius together with the reroll: a region that cannot be entered from public ways is a reroll case, never an obligation.

---

## Acceptance Examples

- AE1. **Covers R4.** Given a 30-minute seek, one clearing is generated; given a 3-hour seek, two or three are (drawn within the duration band); in neither case is the count displayed anywhere.
- AE2. **Covers R9.** Given a walker detouring around a block — momentarily walking directly away from the clearing — pulses continue as single soft ticks; no red state, warning, or corrective feedback appears.
- AE3. **Covers R10, R11.** Given the phone locked in a pocket with a soundscape playing, pings continue quietly beneath the soundscape; when a whisper plays, the ping ducks under it; toggling sonar off in the in-walk sound controls silences pings immediately.
- AE4. **Covers R15, R16.** Given a walker who reaches a clearing but keeps moving for several minutes (dog, companions, busy street), the next clearing reveals anyway without requiring stillness.
- AE5. **Covers R1, R17.** Given a walker who passes the final clearing and keeps walking for 40 more minutes, the walk records normally and ends only when they tap End.
- AE6. **Covers R18.** Given a device with existing walk history, completing a first seek adds waypoints and a walk event only — older walks are untouched and no migration runs.
- AE7. **Covers R12.** Given a walker stopped at a crossing, the Live Activity shows distance only; direction reappears once they are moving.

---

## Success Criteria

- A walker with an hour and no destination is walking a seek within a minute of tapping the card: one question, one intention, out the door.
- The seek is fully navigable without the screen: a pocket-walker can find every clearing by audio cadence alone.
- At no point in any seek does the app signal "wrong" — verified by walking deliberate detours.
- A seek walk appears in history and summary alongside Wander walks with no data loss and no migration prompt on any device.
- Planning (`ce-plan`) can proceed without inventing product behavior: every state a walker can reach is covered by a flow, requirement, or scope boundary here.

---

## Scope Boundaries

- Whole-map fog-of-war (fogging everything unexplored) — clearings only in v1.
- Share Your Walk clearing halos — worker-side polish, later.
- Routing, POI, or reachability APIs — no new network surface; the region + reroll design absorbs unreachable points.
- Network or quantum randomness — local randomness only.
- New whisper categories or seek-specific voice content — existing catalog only.
- Collective crossings or seek-specific collective features — seek walks join the existing collective counting like any walk.
- Pilgrimage mode itself — only the destination-list seam ships now.
- Apple Watch companion guidance.

---

## Key Decisions

- Clearings, not pins: a fogged region solves trespass, GPS error, and the looking-for-signs experience in one move; the exact coordinate never reaches the UI.
- Duration, not point count — and the count stays hidden: the number of unknowns ahead is itself unknown; the quiet after the final reveal is how the walker learns the seeking is complete.
- Context-owned guidance channels: iOS forbids background haptics (verified against the current haptics implementation, which fires only from the foreground view), so haptics own the in-hand moment, audio owns the pocket, and the Live Activity owns the glance — all synchronized to one pulse clock.
- Positive-only guidance: single tick = "still with you," double pulse = "this way." No punishment channel exists, because street grids force wrong-bearing walking constantly.
- Stillness-earned reveal with a grace fallback: presence, not a timer or a button, opens the next unknown — but lingering never traps the walker.
- Sonar audio defaults on: it is the only channel that reaches a pocketed phone; turning it off is a legitimate quiet mode, not a broken state.
- Zero-migration persistence: arrivals as waypoints plus a walk event keeps the frozen schema untouched.
- Duration before intention: logistics first, then ritual — setup ends inside the ritual and the walk begins there.

---

## Dependencies / Assumptions

- Background audio, the Live Activity (with updates from the backgrounded app), the intention step, proximity-style region detection, whisper playback with ducking, and the persistent haptic engine all exist and are reused, not rebuilt.
- The pace and time-reserve constants (R4) are starting assumptions to tune on real walks, not commitments.
- Whisper reveal audio assumes at least one category is downloaded; the bootstrap catalog makes this true for nearly all users.

---

## Outstanding Questions

### Deferred to Planning

- [Affects R15][Technical] Which signals define stillness (speed, pedometer, motion activity) and their thresholds — on-device tuning.
- [Affects R6, R7][Technical] Fog rendering approach on the Mapbox map within the project's resource-safety constraints (no continuous animation; opacity driven by location updates).
- [Affects R12][Technical] Live Activity update cadence vs. the system update budget; coarse distance bucket size.
- [Affects R10][Technical] Audio session behavior when sonar is the only audio (no soundscape selected) — keeping background audio alive without fighting other apps' playback.
- [Affects R9][Technical] Alignment cone width and heading-smoothing window — on-device tuning.
- [Affects R4][Technical] Clearing placement constraints (minimum spacing, distance from start) that keep short seeks from feeling cramped.
- [Affects R4, R21][Needs research] Locally determinable water/land masking at generation time (on-device map data only, no network) so coastal and riverside walkers are not asked to reroll repeatedly.

---

## Deferred / Open Questions

### From 2026-07-06 review

- **Reroll and skip clearing have no UI model** — Requirements — R17 (P0, design-lens + scope-guardian, confidence 100)

  A walker standing in front of a gated driveway cannot request a fresh clearing or skip to the next one if there is no surface to do so from. The document establishes these as user-available actions but provides no gesture, button, menu item, or flow step — the implementer would have to invent the interaction model, the affordance discovery path, and any confirmation from scratch. Two reviewers split on the resolution, which is why this is deferred rather than fixed: design-lens proposes a seek-only section in the in-walk options sheet with "Request new clearing" and "Skip this clearing" rows (the same seek section R11 now establishes for the sonar mirror); scope-guardian counters that R16's grace reveal already prevents a blocked clearing from trapping anyone, so reroll could move to a v2 scope boundary instead of gaining UI now. Also unresolved: whether "skip" is genuinely a user-initiated action or just R16's grace fallback described actively.

  <!-- dedup-key: section="requirements r17" title="reroll and skip clearing have no ui model" evidence="The walker may request a fresh clearing if the way is closed (a graceful reroll), skip clearings, or end at any time" -->

  **Resolved 2026-07-06 (planning):** Single "Seek anew" row in the seek-only section of the in-walk options sheet. No separate skip action — walking on is always free, and declining a clearing is always a reroll. R17 and R11 updated to match.
