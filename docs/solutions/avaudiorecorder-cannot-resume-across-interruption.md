---
title: AVAudioRecorder cannot resume into the same file after a system interruption
date: 2026-06-30
category: audio
module: VoiceRecordingManagement
problem_type: best_practice
component: service_object
severity: medium
applies_when:
  - "Handling AVAudioSession interruptions while AVAudioRecorder is capturing"
  - "Deciding what to do when a call, Siri, alarm, or notification interrupts a recording"
tags: [avaudiorecorder, audio-interruption, avaudiosession, voice-recording, callkit, ios]
---

# AVAudioRecorder cannot resume into the same file after a system interruption

## Context
A "talk" recording was being cut short by transient audio interruptions (a
notification, Siri, an alarm) — not just phone calls. The fix turned on a
single non-obvious framework fact that is worth not rediscovering.

## Guidance
**Once the system deactivates the audio session for an interruption, an
`AVAudioRecorder` cannot resume into the same file.** Calling `record()` again
after `AVAudioSession.interruptionNotification` `.began` does not append — it
discards the pre-interruption audio. There is no "pause and continue in place."

Your real choices when an interruption begins are therefore:

1. **Finalize** the current file and treat the interruption as a hard stop, or
2. **Segment-and-merge** — finalize the current file, start a new one when the
   interruption ends, and stitch the segments together afterward, or
3. **Probe and finalize only if the recorder died** — don't act on `.began`; on
   `.ended`, read `audioRecorder.isRecording`. If it survived the interruption,
   let it keep going (seamless); if it was stopped, finalize the audio captured
   so far *then* (correct duration, mic released) instead of leaving it nominally
   "recording" with a dead recorder.

"Keep the recorder running and let it pick back up after the system stopped it"
is not an option, no matter how brief the interruption — once stopped, the file
is sealed.

## Why This Matters
Conflating these two facts causes both failure modes we hit:
- Assuming you *can* resume → silent tail loss (recorder looks alive, captures
  nothing after the interruption).
- Treating *every* `.began` as a hard stop → a one-second notification ding
  ends a 40-minute talk (this was the v1.7.0 AF11 regression, pilgrim-worker#15).

The right split is by **interruption source**, not by the `.began` event alone:
detect real phone calls via `CXCallObserver` (which fires for any active call,
`!hasEnded` — including unanswered rings) and stop the talk only for those.
For transient non-call interruptions, don't finalize on `.began`; instead probe
the recorder on `.ended` (option 3 above). That keeps a survivable interruption
seamless (one continuous file) while still finalizing cleanly — correct
duration, mic released, no zombie capture — when the system actually stopped the
recorder. Watch two related lifecycle traps the no-finalize path exposes:
`AVAudioRecorder`'s finish delegate firing `successfully: false` can delete the
whole file and leave stale `isRecording` state (reset it), and a coordinator
that re-activates the session on `.ended` will hold a live mic recording nothing
unless the dead-recorder case releases it.

## When to Apply
- Any time you add or change `AVAudioSession` interruption handling around an
  active `AVAudioRecorder`.
- Before writing code that assumes a recording survives an interruption.

## Related
- `Pilgrim/Models/Walk/WalkBuilder/Components/VoiceRecordingManagement.swift`
  (`handleCallStateChange`, `handleAudioInterruption`)
- pilgrim-worker#15 (real-world split-recording report)
- PR #47 (fix), follow-up to PR #45 (v1.7.0, where AF11 introduced the regression)
