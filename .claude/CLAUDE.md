# Pilgrim iOS

Privacy-first pilgrimage walking app. SwiftUI + Combine + CoreStore + CocoaPods.

## Build

```bash
xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build
```

## Test

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Release

```bash
scripts/release.sh check     # validate readiness
scripts/release.sh bump      # increment build number
scripts/release.sh archive   # build .xcarchive
scripts/release.sh export    # export IPA
scripts/release.sh upload    # upload to App Store Connect
scripts/release.sh release   # full pipeline
```

Or use `/release` skill for guided release with changelog generation.

## Screenshots

```bash
# Enable City Run location in Simulator (Features > Location > City Run), then:
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:ScreenshotTests
```

Screenshots save to `/tmp/pilgrim-screenshots/`. Final curated set in `docs/screenshots/`.

Demo mode (`--demo-mode` launch arg) seeds 5 Camino de Santiago walks with routes, weather, meditation, voice recordings, and intentions. All demo code is `#if DEBUG` guarded.

## Resource Safety

This app runs during long walks and meditations (30+ minutes). Resource leaks compound over time and drain battery, overheat the device, or crash the app mid-session — all unacceptable for a mindfulness tool.

**Before writing any code that involves these patterns, verify it won't leak:**

- **Timers**: Every `Timer.scheduledTimer` or `DispatchQueue.asyncAfter` must have a clear cancellation path. Use generation counters for async chains so stale closures become no-ops.
- **AVAudioPlayer / AVAudioSession**: Only one player per role at a time. Always `stop()` and nil out old players before creating new ones. Never accumulate players through crossfade or loop mechanisms. Always call `coordinator.deactivate` in error paths.
- **SwiftUI animations**: Never mutate `@State` arrays inside `withAnimation(.repeatForever)` — this causes infinite re-diffing. Use a single boolean toggle with `.animation()` modifier instead.
- **Combine subscriptions**: Store in `cancellables` and ensure the owning object deallocates. Watch for retain cycles in `.sink` closures.
- **CoreLocation**: Updates continue in background during walks. Ensure location subscriptions are properly cleaned up when walks end.
- **CMAltimeter / CMPedometer callbacks**: Always use `[weak self]` — these OS callbacks retain the closure until explicitly stopped.
- **MeditationView lifecycle**: `onDisappear` must set `isClosing = false` and call `onDismiss()` if not already dismissed, to prevent duplicate activity intervals and lost meditation sessions.

**If you're unsure whether something leaks, default to the simpler approach.** One `AVAudioPlayer` with `numberOfLoops = -1` is better than a dual-player crossfade timer. A static view is better than a continuously-animated one.

## Typography

Always use `Constants.Typography.*` — never use `.system()` fonts or SwiftUI defaults. The project uses **Cormorant Garamond** (display, heading, body) and **Lato** (timer, stats, button, caption).

- `displayLarge` / `displayMedium` — large titles, hero text
- `heading` — section titles, nav bar
- `body` — body text, labels
- `timer` — duration displays
- `statValue` / `statLabel` — metric numbers and labels
- `button` — button text
- `caption` — secondary text, hints

## Privacy Manifest

`Pilgrim/PrivacyInfo.xcprivacy` declares:
- **NSPrivacyTracking**: false
- **NSPrivacyCollectedDataTypes**: precise location (not linked, not tracked, app functionality — for Mapbox tiles and WeatherKit)
- **NSPrivacyAccessedAPITypes**: UserDefaults (CA92.1), FileTimestamp (C617.1 — Cache pod expiry), DiskSpace (E174.1)

When adding dependencies, check if they use required-reason APIs. If the dependency has no `PrivacyInfo.xcprivacy`, the app's manifest must cover its usage.

## Data Safety

- **DataManager.deleteAll**: Errors must propagate (throw, not catch) so CoreStore rolls back. Never delete audio files from disk unless the database transaction committed successfully.
- **Computation.calculateDurationData**: `activeDuration` is clamped to `max(0, ...)`. Consumers (WalkStats) must guard against zero `activeDuration` to avoid division by zero.
- **SoundscapePlayer**: Always reset `isPlaying`, `currentAsset`, and `activePlayer` in error paths. Always stop `fadingOutPlayer` in `stop()`.

## Key Constraints

- **Frozen DB identifiers**: CoreStore entity names and migration version identifiers (`OutRunV1`–`OutRunV4`, `PilgrimV1`) cannot be renamed. Internal `TempV1`–`TempV4` class names (`Workout`, `WorkoutPause`, etc.) must match entity names exactly.
- **`healthKitUUID` field**: Exists in all schema versions, always nil. Cannot be removed without a migration. Leave it alone.
- **`SwiftUI.ProgressView` collision**: The project has a custom `ProgressView` that shadows SwiftUI's. Always qualify as `SwiftUI.ProgressView` when you need the framework version.
- **CocoaPods + SPM hybrid**: CocoaPods manages most dependencies (`Podfile`). WhisperKit is added via SPM. Both coexist — run `pod install` after Podfile changes.
- **Walk.WalkType raw values**: `.walking` is rawValue `1`, not `0`. rawValue `0` and all other values map to `.unknown`.

## Info.plist

- **UIRequiredDeviceCapabilities**: `arm64` (not armv7 — iOS 18+ only)
- **UTExportedTypeDeclarations**: `org.walktalkmeditate.pilgrim.package` for .pilgrim files (distinct from bundle ID)
- **UTImportedTypeDeclarations**: `com.topografix.gpx` only (we don't own GPX, never export it)
- **Location strings**: `NSLocationAlwaysAndWhenInUseUsageDescription` must explain background usage. `NSLocationWhenInUseUsageDescription` is the basic string.
- **InfoPlist.strings**: Must match or improve upon Info.plist values, never weaken them.

## Related Repos

- **pilgrim-landing** (`../pilgrim-landing`): Landing page at pilgrimapp.org. Static HTML/CSS/JS, deployed via GitHub Pages. Contains privacy policy (`privacy.html`) and terms of use (`terms.html`).
