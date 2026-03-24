> *The road is made by walking.*
> — Antonio Machado

# Pilgrim

A pilgrimage app for iOS. Track your walks, capture voice reflections, sit in meditation. No accounts. No servers. No leaderboards. Everything stays on your device.

[pilgrimapp.org](https://pilgrimapp.org)

---

<table>
<tr>
<td><img src="docs/screenshots/01_walk_start.png" alt="Path tab with quote and moon phase" /></td>
<td><img src="docs/screenshots/02_active_walk.png" alt="Active walk with live map" /></td>
<td><img src="docs/screenshots/03_meditation.png" alt="Meditation breathing circle" /></td>
</tr>
<tr>
<td><img src="docs/screenshots/04_walk_summary.png" alt="Walk summary with route and intention" /></td>
<td><img src="docs/screenshots/05_walk_stats.png" alt="Stats breakdown" /></td>
<td><img src="docs/screenshots/06_walk_activity.png" alt="Voice transcription, AI prompts, share" /></td>
</tr>
<tr>
<td><img src="docs/screenshots/07_journal.png" alt="Journal ink scroll path" /></td>
<td><img src="docs/screenshots/08_goshuin.png" alt="Goshuin seal collection" /></td>
<td><img src="docs/screenshots/09_settings.png" alt="Settings" /></td>
</tr>
</table>

---

## What Pilgrim Is

Walking is thinking. It always has been. Aristotle walked while he taught. Wordsworth composed poems on foot. Matsuo Bashō walked the narrow road to the deep north and came back with haiku.

Pilgrim treats a walk as a creative practice — a moving meditation, a thinking space, a way of being in the world. The app holds your walk lightly: GPS route, pace, steps, elevation. It records your voice so you can speak thoughts without stopping. It offers a breathing circle when you want to pause and be still. When you return, it offers back what you gave it: a map of where you went, a transcript of what you said, writing prompts drawn from your own words.

That's the whole thing. No more, no less.

### What Pilgrim Is Not

- Not a fitness app. There are no calorie counters, no personal bests, no badges for streaks.
- Not a social platform. There is no feed, no following, no comparison.
- Not a data business. No analytics, no advertising, no behavioral profiling.
- Not a subscription. No paywall mid-walk, no features gated behind recurring payments.
- Not a cloud service. Your walks live on your phone. When you delete the app, they're gone with it — unless you exported them first.

---

## Features

**The walk itself**

GPS tracking with live pace sparkline, step counting, altitude gain, and waypoint marking. Three-way time breakdown shows how each walk split between walking, talking, and meditating — because those are genuinely different states of attention. Walk data is auto-saved periodically so nothing is lost if the app is interrupted. Live weather via WeatherKit is logged with each walk.

**Voice**

Tap to record a voice note at any moment on the walk. Each recording is timestamped and pinned to a location. After the walk, WhisperKit transcribes everything on-device — no audio is ever sent to a server. Auto-transcription runs after each walk when enabled, and skips gracefully when battery is below 20%. Edit transcriptions inline to fix what WhisperKit got wrong. The transcriptions become the raw material for writing prompts.

**Meditation**

A dedicated meditation mode with an animated breathing circle. Set the rhythm (inhale, hold, exhale, rest). Meditation time is tracked separately and shown alongside walk time in the summary.

**Voice guides and soundscapes**

Downloadable meditation guide packs with spoken prompts during walks and meditation. Seven ambient soundscapes — forest, rain, ocean, stream, birds, fire, crickets — play seamlessly in the background with crossfade looping. Customizable bells mark the start and end of walks and meditation sessions.

**AI writing prompts**

Six prompt styles — contemplative, reflective, creative, gratitude, philosophical, journaling — generated from your transcriptions and walk context. Copy them into your favorite AI and turn a walk into writing.

**Goshuin seals**

In Japan, pilgrims collect *goshuin* — vermilion ink stamps given at temples along a route. Pilgrim generates a digital seal for each walk, derived from its unique data: distance, duration, weather, elevation. The collection grows with your practice.

**Celestial awareness**

Moon phase, zodiac sign, and planetary hour appear in the walk context. A contemplative koan drawn from the celestial, weather, or seasonal context appears before each walk — a seed for reflection.

**Sharing**

Share a walk as a goshuin seal image, a hand-painted etegami postcard, or an ephemeral HTML walk page (no login required). The walk is yours to keep or share as you see fit.

**Walk with the collective**

Opt-in anonymous counter that tracks total walks, distance, and meditation time across all pilgrims. Your Settings screen shows the collective progress mapped to real pilgrimage routes — from the Kumano Kodo to the Camino de Santiago. Sacred number milestones ring a temple bell. A streak flame tracks consecutive days someone, somewhere, has walked. The logo gently pulses when another pilgrim walked in the last hour.

**Your data**

See all your walks rendered on [view.pilgrimapp.org](https://view.pilgrimapp.org) — right from the app, nothing uploaded. Export as `.pilgrim` packages (full data, importable). Export voice recordings separately as a zip. Import on a new device anytime. Colors shift with the seasons, calibrated to your hemisphere.

---

## Privacy

Every feature that could require a network call has been built to work without one.

- Transcription: on-device via WhisperKit
- Writing prompts: generated on-device from walk context, copy into your own AI
- Maps: Mapbox with no user-identifying requests
- Weather: Apple WeatherKit (no personal account linked)
- Walk data: stored in CoreData on the device
- Collective counter: opt-in, sends only anonymous totals (walk count, distance, meditation time)

There is no backend that knows who you are. There is no account to create. The app ships with a full privacy manifest declaring every API it uses and why.

---

## Building

### Requirements

- Xcode 26 or later
- iOS 26.0 deployment target
- CocoaPods (`gem install cocoapods` if needed)
- A physical device or M-series simulator for arm64 builds

### Setup

```bash
git clone https://github.com/momentmaker/pilgrim-ios.git
cd pilgrim-ios
pod install
```

Copy the secrets template and fill in your Mapbox token:

```bash
cp Secrets.xcconfig.example Secrets.xcconfig
# Edit Secrets.xcconfig and add your Mapbox public token
```

Then open the workspace — not the project file:

```bash
open Pilgrim.xcworkspace
```

Build and run on a simulator or connected device. The app functions without a Mapbox token (maps will not render), but all other features work.

### Running Tests

```bash
xcodebuild test \
  -workspace Pilgrim.xcworkspace \
  -scheme Pilgrim \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

### Releasing

```bash
scripts/release.sh check       # validate the project is ready
scripts/release.sh bump        # auto-increment build number
scripts/release.sh changelog   # generate release notes from git log
scripts/release.sh archive     # build the release archive
scripts/release.sh export      # export for App Store upload
scripts/release.sh upload      # upload to App Store Connect
scripts/release.sh release     # full pipeline with tagging and GitHub Release
```

---

## Architecture

### Technology

- **SwiftUI + Combine** — views and reactive state throughout
- **CoreStore** — CoreData ORM with type-safe migrations
- **WhisperKit** (SPM) — on-device speech recognition
- **CocoaPods** — Cache, CombineExt, CoreGPX, ZIPFoundation
- **WeatherKit** — weather data with no user account

### Structure

```
Pilgrim/
├── Scenes/
│   ├── Home/           — journal scroll view, walk list, ink path renderer
│   ├── ActiveWalk/     — live walk, meditation mode, waypoints, intention
│   ├── WalkSummary/    — route map, elevation, timeline, AI prompts, share
│   ├── Goshuin/        — seal collection and generative art renderer
│   ├── Settings/       — preferences, data export, voice guides, sounds
│   └── WalkShare/      — ephemeral HTML walk page generation
├── Models/
│   ├── Walk/
│   │   ├── WalkBuilder/           — coordinates all recording components
│   │   └── WalkBuilder/Components/
│   │       ├── LocationManagement
│   │       ├── VoiceRecordingManagement
│   │       ├── AltitudeManagement
│   │       ├── StepCounter
│   │       ├── LiveStats
│   │       ├── AutoPauseDetection
│   │       └── MeditateDetection
│   └── Data/
│       ├── DataModels/Versions/   — 11-version CoreStore migration chain
│       └── PilgrimPackage/        — .pilgrim export/import format
└── Views/                         — shared components, design system
```

### Navigation

Coordinator pattern: `RootCoordinatorView` manages top-level state, `SetupCoordinatorView` handles first-run permissions. MVVM with `@Published`/`@ObservedObject` throughout.

### Data Model

Pilgrim carries a migration chain from its origin as OutRun through six Pilgrim-specific versions:

```
OutRunV1 → OutRunV2 → OutRunV3 → OutRunV3to4 → OutRunV4
→ PilgrimV1 → PilgrimV2 → PilgrimV3 → PilgrimV4 → PilgrimV5 → PilgrimV6
```

The CoreStore entity names (`OutRunV1`–`V4`, `PilgrimV1`) and migration identifiers are frozen — they cannot be renamed without breaking upgrades for existing users.

### Design System

Typography uses Cormorant Garamond (display, headings, body) and Lato (timer, stats, captions) via `Constants.Typography.*`. Never use `.system()` fonts or SwiftUI defaults.

Colors: stone (accent), ink, parchment, moss, rust, fog, dawn. Seasonal vignettes shift the palette across spring, summer, autumn, winter.

Spacing: `Constants.UI.Padding.*` — xs (4), small (8), normal (16), big (24), breathingRoom (64).

---

## Contributing

Pilgrim is open source under GPLv3. Contributions are welcome.

The app is built for long walks — sessions that last 30, 60, 90 minutes without interruption. The highest obligation when contributing is to not break that. A memory leak that manifests after 45 minutes, an audio player that doesn't clean up after itself, an animation that causes infinite re-diffing — these are not minor bugs. They are the app failing at the moment it matters most.

Before contributing:

- Read the resource safety guidelines in `.claude/CLAUDE.md`
- Study 2–3 existing scenes before writing a new one — patterns exist for a reason
- Timers, audio players, Combine subscriptions, and location updates all require explicit cleanup paths
- Code should be self-documenting; comments that explain *what* the code does signal a refactor, not a note

Open an issue before starting significant work. Not for permission — for conversation. Some paths have been tried and abandoned for reasons that aren't obvious in the code.

---

## Origin

Pilgrim is a fork of [OutRun](https://github.com/timfraedrich/OutRun) by Tim Fraedrich, a workout tracking app published under GPLv3. The core GPS recording infrastructure, CoreData model, and migration chain originate there. Everything built on top — the pilgrimage framing, voice recording, on-device transcription, meditation mode, celestial awareness, goshuin seals, the wabi-sabi design — is new work by the [Walk Talk Meditate](https://github.com/momentmaker/walktalkmeditate) contributors.

---

## License

GNU General Public License v3. See `LICENSE`.

    Pilgrim
    Copyright (C) 2020 Tim Fraedrich <timfraedrich@icloud.com>
    Copyright (C) 2025–2026 Walk Talk Meditate contributors

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

---

[pilgrimapp.org](https://pilgrimapp.org)
