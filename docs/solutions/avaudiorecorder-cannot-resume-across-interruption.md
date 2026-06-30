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

Your only real choices when an interruption begins are therefore:

1. **Finalize** the current file and treat the interruption as a hard stop, or
2. **Segment-and-merge** — finalize the current file, start a new one when the
   interruption ends, and stitch the segments together afterward.

"Keep the recorder running and let it pick back up" is not an option, no matter
how brief the interruption.

## Why This Matters
Conflating these two facts causes both failure modes we hit:
- Assuming you *can* resume → silent tail loss (recorder looks alive, captures
  nothing after the interruption).
- Treating *every* `.began` as a hard stop → a one-second notification ding
  ends a 40-minute talk (this was the v1.7.0 AF11 regression, pilgrim-worker#15).

The right split is by **interruption source**, not by the `.began` event alone:
detect real phone calls via `CXCallObserver` (which fires for any active call,
`!hasEnded` — including unanswered rings) and stop the talk only for those.
Leave the recorder running on transient non-call interruptions; accept the
documented tail-loss risk rather than finalizing on every system sound. If
that tail-loss ever proves common in the field, the principled upgrade is
segment-and-merge — not "resume in place," which does not exist.

## When to Apply
- Any time you add or change `AVAudioSession` interruption handling around an
  active `AVAudioRecorder`.
- Before writing code that assumes a recording survives an interruption.

## Related
- `Pilgrim/Models/Walk/WalkBuilder/Components/VoiceRecordingManagement.swift`
  (`handleCallStateChange`, `handleAudioInterruption`)
- pilgrim-worker#15 (real-world split-recording report)
- PR #47 (fix), follow-up to PR #45 (v1.7.0, where AF11 introduced the regression)
