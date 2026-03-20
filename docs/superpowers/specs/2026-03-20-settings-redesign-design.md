# Settings Page Redesign

Replace the flat iOS List settings page with a curated, card-based continuous scroll that organizes settings by intent — how you walk, how it feels, what you hear — with inline controls, one-line descriptions, a seasonal practice summary, and the wabi-sabi aesthetic of the rest of the app.

## Layout

Replace `SettingsView`'s `List` with a `ScrollView` containing styled cards. Each group is a rounded card on `Color.parchmentSecondary`, separated by `Constants.UI.Padding.big` spacing. Background is `Color.parchment`.

## Sections

### 1. Practice Summary (Header)

A non-card header at the top of the scroll. Shows:
- Season + year ("Spring 2026") with a small seasonal botanical vignette (reuse the tree element from `AboutView`)
- Aggregate stats: "{N} walks · {distance}" and "{hours} meditated" in `Constants.Typography.caption`, `Color.fog`
- Stats are tappable, cycling through presentations (like AboutView's stats whisper)

Data source: `HomeViewModel` properties — `walks.count`, total distance (sum of `walk.distance`), total meditation (sum of `walk.meditateDuration`).

The seasonal vignette uses `SealTimeHelpers.season(for: Date(), latitude:)` with the most recent walk's latitude, or 0 if no walks.

### 2. The Practice — "How you walk"

Card containing inline controls:

| Setting | Control | Description |
|---------|---------|-------------|
| Begin with intention | Toggle | "Set an intention before each walk" |
| Celestial awareness | Toggle | "Moon phases, planetary hours, and zodiac during walks" |
| Zodiac system | Segmented (Tropical / Sidereal) | Only visible when celestial awareness is on |
| Units | Segmented (km / mi) | Shows unit examples below: "km · min/km · m · °C" or "mi · min/mi · ft · °F" |

All controls inline — no navigation to sub-pages. The zodiac picker animates in/out when celestial toggle changes.

Preferences: `beginWithIntention`, `celestialAwarenessEnabled`, `zodiacSystem`, `distanceMeasurementType` (changing this also sets altitude, speed, energy, weight measurement types to match, as the existing `GeneralSettingsView` does).

### 3. Atmosphere — "How it feels"

Card containing:

| Setting | Control | Description |
|---------|---------|-------------|
| Appearance | Segmented (Auto / Light / Dark) | Inline, no description needed |
| Sounds | Toggle | "Bells, haptics, and ambient soundscapes" |
| Bells & Soundscapes | NavigationLink | Only visible when sounds enabled. Leads to existing bell/soundscape picker sub-page |
| Breath Rhythm | NavigationLink | Only visible when sounds enabled. Leads to existing breath rhythm picker |
| Volume | NavigationLink | Only visible when sounds enabled. Leads to a volume sub-page with bell + soundscape sliders |

The NavigationLinks show a chevron and are styled as list rows within the card.

Preferences: `appearanceMode`, `soundsEnabled`, `bellHapticEnabled`, bell/soundscape IDs, `breathRhythm`, volume levels.

### 4. Voice — "What you hear and say"

Card containing:

| Setting | Control | Description |
|---------|---------|-------------|
| Voice Guide | Toggle | "Spoken prompts during walks and meditation" |
| Guide Packs | NavigationLink | Only visible when voice guide enabled. Shows current pack name. Leads to existing voice guide packs page |
| Dynamic Voice | Toggle | "Enhance clarity of your voice recordings" |
| Auto-transcribe | Toggle | "Convert recordings to text after each walk" |
| Recordings | NavigationLink | Shows count + total size (e.g., "12 · 48 MB"). Leads to existing RecordingsListView |

Preferences: `voiceGuideEnabled`, `selectedVoiceGuidePackId`, `dynamicVoiceEnabled`, `autoTranscribe`.

### 5. Permissions — "What the app needs"

Card containing three permission rows, each with:
- Status dot (green = authorized, amber = not determined, red = denied/restricted)
- Permission name
- One-line description of why it's needed
- Action button if needed ("Grant" for not determined, "Settings" for denied)

| Permission | Description |
|-----------|-------------|
| Location | "Route tracking during walks" |
| Microphone | "Voice recording and transcription" |
| Motion | "Step counting and activity detection" |

Reuse `PermissionStatusViewModel` for status tracking and action handling.

### 6. Your Data — "Your pilgrimage archive"

Card containing:
- Export My Data (NavigationLink or button with progress indicator)
- Import Data (button opening document picker)
- Leave a Trail Note (NavigationLink to existing FeedbackView)

Footer text: "Export creates a .pilgrim archive with all your walks, transcriptions, and settings."

### 7. About Pilgrim

Small card with NavigationLink to existing `AboutView`. Shows app version below.

## Design Language

### Card Styling
```
Background: Color.parchmentSecondary
Corner radius: Constants.UI.CornerRadius.normal
Padding: Constants.UI.Padding.normal (internal)
Spacing between cards: Constants.UI.Padding.big
```

### Section Headers (inside cards)
- Title: `Constants.Typography.heading`, `Color.ink`
- Subtitle: `Constants.Typography.caption`, `Color.fog`

### Setting Rows
- Label: `Constants.Typography.body`, `Color.ink`
- Description: `Constants.Typography.caption`, `Color.fog`
- Toggle tint: `Color.stone`
- NavigationLink chevron: `Color.fog`
- Spacing between rows: `Constants.UI.Padding.normal`

### Seasonal Vignette
Reuse the seasonal tree from `AboutView`. Position at top-right of the practice summary header, small (~40pt), at low opacity (~0.3). Season determined from current date + latitude.

## File Changes

### New
| File | Responsibility |
|------|---------------|
| `Pilgrim/Scenes/Settings/SettingsView.swift` | Complete rewrite — card-based scroll |
| `Pilgrim/Scenes/Settings/SettingsCards/PracticeCard.swift` | The Practice section card |
| `Pilgrim/Scenes/Settings/SettingsCards/AtmosphereCard.swift` | Atmosphere section card |
| `Pilgrim/Scenes/Settings/SettingsCards/VoiceCard.swift` | Voice section card |
| `Pilgrim/Scenes/Settings/SettingsCards/PermissionsCard.swift` | Permissions section card |
| `Pilgrim/Scenes/Settings/SettingsCards/DataCard.swift` | Your Data section card |
| `Pilgrim/Scenes/Settings/PracticeSummaryHeader.swift` | Seasonal header with stats |
| `Pilgrim/Scenes/Settings/VolumeSettingsView.swift` | New sub-page for bell + soundscape volume sliders |

### Modified
| File | Change |
|------|--------|
| `Pilgrim/Scenes/Settings/SettingsView.swift` | Complete rewrite |

### Unchanged (reused as sub-pages)
- `SoundSettingsView.swift` — partially reused for bell/soundscape pickers (but volume sliders extracted to new VolumeSettingsView)
- `VoiceGuideSettingsView.swift` — reused for pack management
- `RecordingsListView.swift` — reused as-is
- `DataSettingsView.swift` — logic reused, UI may be simplified
- `FeedbackView.swift` — reused as-is
- `AboutView.swift` — reused as-is

### Removed
| File | Reason |
|------|--------|
| `GeneralSettingsView.swift` | All settings moved inline to cards |
| `TalkSettingsView.swift` | Settings moved inline to Voice card |

## What This Does NOT Include

- Animated transitions between cards (keep it simple, use standard SwiftUI)
- Rewriting sub-pages (bell picker, voice packs, recordings, about, feedback)
- New preferences or settings not currently in the app
- Onboarding or setup flow changes

## Success Criteria

- All existing settings accessible (nothing lost in the redesign)
- Simple toggles require 0 navigation (inline on the main page)
- Complex settings require exactly 1 navigation (main → sub-page)
- Every setting has a description explaining what it does
- Groups organized by user intent, not technical category
- Seasonal practice summary visible at top
- Card-based layout with wabi-sabi aesthetic
- All existing tests still pass
- No new preferences or data model changes needed
