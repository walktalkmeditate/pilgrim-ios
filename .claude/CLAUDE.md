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

## Key Constraints

- **Frozen DB identifiers**: CoreStore entity names and migration version identifiers (`OutRunV1`–`OutRunV4`, `PilgrimV1`) cannot be renamed. Internal `TempV1`–`TempV4` class names (`Workout`, `WorkoutPause`, etc.) must match entity names exactly.
- **`SwiftUI.ProgressView` collision**: The project has a custom `ProgressView` that shadows SwiftUI's. Always qualify as `SwiftUI.ProgressView` when you need the framework version.
- **CocoaPods + SPM hybrid**: CocoaPods manages most dependencies (`Podfile`). WhisperKit is added via SPM. Both coexist — run `pod install` after Podfile changes.
- **Walk.WalkType raw values**: `.walking` is rawValue `1`, not `0`. rawValue `0` and all other values map to `.unknown`.
