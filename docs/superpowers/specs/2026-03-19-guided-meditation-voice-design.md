# Guided Meditation Voice Guide

## Context

Pilgrim's voice guide system currently plays periodic prompts during walks — sparse, phase-based guidance that enhances the walking experience without dominating it. The meditation feature has a rich breathing circle visualization but no voice guidance.

This design extends the voice guide system into meditation. When a user downloads a voice pack, they get both walk and meditation prompts. During meditation, long-pressing the breathing circle reveals a picker to activate a voice guide for that session. The guide delivers periodic prompts while the breathing circle responds with intensified concentric rings, and the breathing animation slows and softens during speech.

## Design

### Data Model

**VoiceGuidePack additions** (backward-compatible optional fields):

```
meditationPrompts: [VoiceGuidePrompt]?   — meditation-specific prompts
meditationScheduling: PromptDensity?     — separate timing for meditation
```

`hasMeditationGuide: Bool` computed property returns true when `meditationPrompts` is non-empty.

`totalSizeBytes` and `totalDurationSec` in the manifest include both walk and meditation prompt totals combined so the settings UI accurately reports pack size.

Meditation prompts use the same `VoiceGuidePrompt` structure. The `phase` field maps to meditation timescales:
- `settling` → first ~5 minutes (grounding, arrival)
- `deepening` → 5–15 minutes
- `closing` → 15+ minutes

**Manifest example:**

```json
{
  "id": "gentle-pilgrim",
  "name": "The Gentle Pilgrim",
  "type": "voiceGuide",
  "scheduling": { "densityMinSec": 180, "densityMaxSec": 420, "minSpacingSec": 120, "initialDelaySec": 60, "walkEndBufferSec": 300 },
  "prompts": [ "... walk prompts ..." ],
  "meditationScheduling": { "densityMinSec": 90, "densityMaxSec": 180, "minSpacingSec": 60, "initialDelaySec": 30, "walkEndBufferSec": 0 },
  "meditationPrompts": [ "... meditation prompts ..." ]
}
```

### Download & File Storage

**VoiceGuideDownloadManager**: The `downloadPack` method's missing-file loop changes from `pack.prompts.filter(...)` to `(pack.prompts + (pack.meditationPrompts ?? [])).filter(...)` so meditation prompts are included in the download.

**VoiceGuideFileStore**: `isPackDownloaded` must check both `prompts` and `meditationPrompts` arrays. A pack is only fully downloaded when all prompts from both arrays are present on disk.

No changes to `VoiceGuidePlayer`.

### VoiceGuideScheduler Changes

**Phase thresholds**: The scheduler's `settlingThresholdSec` and `closingThresholdSec` are currently `private static let` constants. These become stored instance properties with default values matching current behavior (20 min / 45 min). The initializer accepts optional overrides:

```swift
init(pack: VoiceGuidePack,
     settlingThresholdSec: TimeInterval = 20 * 60,
     closingThresholdSec: TimeInterval = 45 * 60)
```

Meditation passes `settlingThresholdSec: 5 * 60, closingThresholdSec: 15 * 60`.

**Context mode**: The scheduler gains a `context: SchedulerContext` enum (`.walk` or `.meditation`). In `.walk` context, the existing `tick()` guards apply (`status == .recording`, `!isMeditating`). In `.meditation` context, the tick bypasses the walk-status and meditation guards — it only checks `!isPaused` and `!isPlaying`. The elapsed time is calculated from a `startDate` property set when the scheduler starts.

**Prompt source**: The scheduler is initialized with a prompts array rather than reading `pack.prompts` directly. Walk context passes `pack.prompts`, meditation context passes `pack.meditationPrompts`.

### MeditationGuideManagement

New class: `Pilgrim/Models/Audio/VoiceGuide/MeditationGuideManagement.swift`

```swift
final class MeditationGuideManagement: ObservableObject {
    @Published private(set) var isActive: Bool
    @Published private(set) var isVoicePlaying: Bool
}
```

Responsibilities:
- Owns a `VoiceGuideScheduler` in `.meditation` context, configured with `meditationScheduling`, `meditationPrompts`, and shortened phase thresholds
- Uses `VoiceGuidePlayer.shared` for playback (ownership hand-off described below)
- Publishes `isVoicePlaying` to drive visual treatment
- Uses a generation counter to prevent stale callbacks (same pattern as `VoiceGuideManagement`)

**`isVoicePlaying` lifecycle**: Transitions to `true` when `onShouldPlay` fires and the player starts playback. Transitions to `false` in the `onFinished` callback after `AVAudioPlayer` completes. Additionally, `stopGuiding()` sets `isVoicePlaying = false` directly — `VoiceGuidePlayer.stop()` does not invoke `onFinished`, so the forced-stop path must reset the visual state explicitly. This drives the visual ring and breathing speed transitions.

**Player ownership hand-off**: The walk's `VoiceGuideManagement` already pauses the scheduler when meditation starts, but a prompt could be mid-playback. Before `MeditationGuideManagement` starts its scheduler, it calls `VoiceGuidePlayer.shared.stop()` to ensure no walk prompt is playing. When meditation ends, the walk guide resumes normally (it already handles post-meditation silence). There is never concurrent playback because meditation fully owns the player during its lifecycle.

**Pack switching mid-session**: Selecting a new pack while a guide is active calls `stopGuiding()` first (stopping scheduler, stopping player, incrementing generation), then starts the new pack. The generation counter ensures stale callbacks from the old pack's prompts are ignored.

**Replay**: Replay is not supported in meditation context. `MeditationGuideManagement` does not expose a `replayLastPrompt()` method. The meditation UI has no replay button.

**Ownership in MeditationView**: Stored as `@State private var meditationGuide: MeditationGuideManagement?`. Created when a pack is selected (set to a new instance), nilled out on "Off" selection or when the closing ceremony begins. `beginClosingCeremony()` calls `meditationGuide?.stopGuiding()` as its first step before the existing DispatchQueue chain, then sets `meditationGuide = nil`.

### MeditationView UI Changes

**1. Combined Options Sheet**

The existing `showBreathPicker` sheet is replaced by a combined `showMeditationOptions` sheet. The `showSoundscapePicker` sheet remains separate (it's triggered by long-press on the soundscape label, not the breathing circle).

The long-press gesture on the breathing circle opens a redesigned sheet with two sections:

Voice Guide section (top):
- "Off" option (default) for silent meditation
- List of downloaded packs that have `meditationPrompts`, with checkmark for selected
- Not-downloaded packs shown at reduced opacity with download indicator; tapping starts download in-sheet with progress
- Section only appears when voice guide is enabled in settings AND at least one pack in the manifest has meditation prompts

Breath Rhythm section (below divider):
- Unchanged from current behavior

Sheet title: "Meditation Options" when voice guide section is present, "Breath Rhythm" otherwise.

Voice guide selection is per-session, defaulting to "Off". This is intentional: meditation is a deliberate practice, and choosing to invite a voice guide should be a conscious decision each time — not automatic. This matches the meditation philosophy of beginning with intention.

**2. Concentric Voice Rings**

When `isVoicePlaying` is true, the breathing circle gains intensified concentric rings:
- 3–4 additional rings emanate outward from the circle
- Slightly organic/imperfect shapes (irregular border-radius)
- Pulse in rhythm with the audio playback
- Use the existing ripple ring visual vocabulary (same color, similar opacity)
- Rings fade out over ~1.5 seconds when `isVoicePlaying` returns to false

**3. Slow and Soften Breathing**

When `isVoicePlaying` transitions to true:
- Breathing animation eases to ~50% speed over ~2 seconds
- Circle opacity softens slightly (moss opacity 0.5 → 0.35)
- The breath cycle does not stop or reset — it continues at reduced intensity

When `isVoicePlaying` transitions to false:
- Breathing animation eases back to normal speed over ~3 seconds
- Circle opacity returns to normal
- The breath cycle continues uninterrupted

### Closing Ceremony Integration

When the user taps Done:
1. `MeditationGuideManagement.stopGuiding()` is called immediately, which stops the scheduler and calls `VoiceGuidePlayer.shared.stop()`, cutting any in-progress prompt
2. `isVoicePlaying` transitions to false, voice rings fade
3. The existing closing ceremony proceeds as normal (dissolve → summary → fade → dismiss)

The voice guide does not delay or prevent the closing ceremony.

### Background Behavior

When the app enters background during guided meditation, the scheduler continues ticking (it's a main-thread timer). However, `AVAudioPlayer` playback depends on the audio session being active. If a soundscape is playing, the audio session stays active and voice prompts will play in background. If no soundscape is playing, the audio session may be deactivated by iOS and prompts will silently fail (the scheduler marks them as played and moves on). This matches the walk guide's existing background behavior and is acceptable.

### WalkOptionsSheet Enhancement (Bonus)

The walk guide's in-walk options sheet gains the same download-in-context treatment: not-downloaded packs appear greyed out with a download indicator, tappable to start download.

### Settings

No settings changes. The existing `voiceGuideEnabled` toggle and `selectedVoiceGuidePackId` preference control walk voice guide as before. Meditation guide selection is per-session only.

### What Doesn't Change

- `VoiceGuidePlayer` — same playback, ducking, audio session coordination
- `AudioSessionCoordinator` — same session management
- `VoiceGuideSettingsView` — packs with meditation prompts appear naturally (they're the same packs)
- Session timer, breath count, soundscape integration
- Walk voice guide behavior (still pauses during meditation, still applies post-meditation silence)

## Verification

1. **Download**: Download a voice pack and verify both walk and meditation prompts are downloaded. Check `Audio/voiceguide/{packId}/` contains all prompt files from both `prompts` and `meditationPrompts`.
2. **Pack status**: Verify `isPackDownloaded` returns false if walk prompts are present but meditation prompts are missing.
3. **Options sheet**: Enter meditation, long-press the breathing circle. Verify voice guide section appears with downloaded packs. Verify "Off" is default.
4. **Activation**: Select a pack. Verify `MeditationGuideManagement` starts and a prompt plays within the configured initial delay (~30 seconds).
5. **Visual treatment**: When a prompt plays, verify concentric rings appear and breathing slows. When prompt ends, verify rings fade and breathing resumes.
6. **Deactivation**: Select "Off" mid-session. Verify guidance stops, player stops, and visual treatment clears.
7. **Pack switching**: While a guide is active, select a different pack. Verify old guide stops cleanly (no stale callbacks) and new guide starts.
8. **Done during prompt**: Tap Done while a voice prompt is playing. Verify prompt stops immediately and closing ceremony proceeds normally without voice ring artifacts.
9. **Walk interaction**: Start a walk with voice guide active, start meditation. Verify walk voice guide pauses and any in-progress walk prompt stops. Activate meditation guide. Verify meditation prompts play. End meditation. Verify walk guide resumes after post-meditation silence.
10. **No meditation prompts**: Use a pack without `meditationPrompts`. Verify the voice guide section does not appear in the meditation options sheet.
11. **Settings off**: Disable voice guide in settings. Verify voice guide section does not appear in meditation options sheet.
