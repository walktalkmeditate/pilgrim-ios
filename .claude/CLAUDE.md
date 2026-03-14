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

## Resource Safety

This app runs during long walks and meditations (30+ minutes). Resource leaks compound over time and drain battery, overheat the device, or crash the app mid-session — all unacceptable for a mindfulness tool.

**Before writing any code that involves these patterns, verify it won't leak:**

- **Timers**: Every `Timer.scheduledTimer` or `DispatchQueue.asyncAfter` must have a clear cancellation path. Use generation counters for async chains so stale closures become no-ops.
- **AVAudioPlayer / AVAudioSession**: Only one player per role at a time. Always `stop()` and nil out old players before creating new ones. Never accumulate players through crossfade or loop mechanisms.
- **SwiftUI animations**: Never mutate `@State` arrays inside `withAnimation(.repeatForever)` — this causes infinite re-diffing. Use a single boolean toggle with `.animation()` modifier instead.
- **Combine subscriptions**: Store in `cancellables` and ensure the owning object deallocates. Watch for retain cycles in `.sink` closures.
- **CoreLocation**: Updates continue in background during walks. Ensure location subscriptions are properly cleaned up when walks end.

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

## Key Constraints

- **Frozen DB identifiers**: CoreStore entity names and migration version identifiers (`OutRunV1`–`OutRunV4`, `PilgrimV1`) cannot be renamed. Internal `TempV1`–`TempV4` class names (`Workout`, `WorkoutPause`, etc.) must match entity names exactly.
- **`SwiftUI.ProgressView` collision**: The project has a custom `ProgressView` that shadows SwiftUI's. Always qualify as `SwiftUI.ProgressView` when you need the framework version.
- **CocoaPods + SPM hybrid**: CocoaPods manages most dependencies (`Podfile`). WhisperKit is added via SPM. Both coexist — run `pod install` after Podfile changes.
- **Walk.WalkType raw values**: `.walking` is rawValue `1`, not `0`. rawValue `0` and all other values map to `.unknown`.
