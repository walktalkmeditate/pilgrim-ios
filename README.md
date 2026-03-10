# Pilgrim

Pilgrim is a privacy-first iOS app for intentional walking. Record your walks, capture voice reflections, sit in meditation, and receive AI-generated writing prompts — all without your data ever leaving your device.

Built as part of the [Walk Talk Meditate](https://github.com/momentmaker/walktalkmeditate) project.

## Why Pilgrim?

Walking is more than exercise. It's how we think, process, and create. Pilgrim treats a walk as a creative practice — not a fitness metric. There are no leaderboards, no social feeds, no calorie goals. Just you, the path, and whatever arises.

## Features

- **GPS Walk Tracking** — Record routes with distance, steps, altitude, and duration
- **Voice Recording** — Capture thoughts mid-walk with timestamped voice pins
- **Local Transcription** — On-device speech-to-text via WhisperKit (no network required)
- **Meditation Timer** — Dedicated meditation mode tracked separately from walking
- **Three-Way Time Breakdown** — See how your walk splits between walking, talking, and meditating
- **AI Writing Prompts** — Context-aware prompts generated from your transcriptions and walk data across six styles (contemplative, reflective, creative, gratitude, philosophical, journaling)
- **Walk Summary** — Post-walk view with route map, stats, recordings, and prompts
- **Privacy First** — All data stays on your device. No accounts, no servers, no tracking
- **Backup & Export** — Export walks as GPX files or Pilgrim Backup (.orbup)

## Building

Pilgrim uses CocoaPods and Swift Package Manager. To build:

```
git clone https://github.com/momentmaker/pilgrim-ios.git
cd pilgrim-ios
pod install
open Pilgrim.xcworkspace
```

Use `Pilgrim.xcworkspace` (not `.xcodeproj`). Requires Xcode 16+ and iOS 16.0+.

## License

Pilgrim is published under the GNU General Public License v3 (GPLv3):

    Pilgrim
    Copyright (C) 2020 Tim Fraedrich <timfraedrich@icloud.com>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

Pilgrim is a fork of [OutRun](https://github.com/timfraedrich/OutRun) by Tim Fraedrich.
