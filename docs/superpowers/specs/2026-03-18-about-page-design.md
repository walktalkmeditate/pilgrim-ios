# About Page Design

## Context

Pilgrim's Settings has no About page. Users have no way to learn the philosophy behind the app, connect with the walk · talk · meditate project, or understand that Pilgrim is open source and privacy-first. This page fills that gap — a contemplative scroll that builds trust, connection, and inspiration.

## Emotional Arc

The page moves through three layers as the user scrolls:

1. **Trust** — Who made this and why (philosophy, quiet companion framing)
2. **Connection** — The walk · talk · meditate pillars and project link
3. **Inspiration** — Personal stats whisper + closing motto as a gentle send-off

## Location

- New file: `Pilgrim/Scenes/Settings/AboutView.swift`
- Added as a NavigationLink in the existing `SettingsView.swift` — new section between the Feedback section and the footer

## Scroll Structure

### 1. Hero — Breathing Logo + Philosophy

- `PilgrimLogoView(size: 80, animated: true, breathing: $breathing)` centered
- `AboutView` owns `@State private var breathing = false` and sets `breathing = true` in `.onAppear` to trigger the breathing animation
- Headline: *"Every walk is a small pilgrimage."* — `displayMedium`, italic
- Body: *"Walking is how we think, process, and return to ourselves. Pilgrim is a quiet companion for the path — no leaderboards, no metrics, just you and the walk."* — `body`, `.fog` color

### 2. walk · talk · meditate — Three Pillars

Section header: **"walk · talk · meditate"** — `caption`, letter-spaced, centered, stone color

Each pillar row:
- **Icon**: Small `SceneryItemView` (tree for walk, lantern for talk, moon for meditate) at ~36pt in a circular tinted background. Uses `walkDate: Date()` for current season rendering. Gentle animation via TimelineView.
- **Title**: lowercase — "walk", "talk", "meditate" — `heading` font
- **Description** (from walktalkmeditate.org):
  - walk: *"Walking as practice, not transit. Side by side, step by step — strengthening the physical body."*
  - talk: *"Deep reflection and connection, not small talk. Ask and share your unique perspective of reality."*
  - meditate: *"Seek the peace and calmness within. Harmonize your being with the group and the environment."*

Descriptions use `body` font, `ink` color, indented under the icon.

### 3. Stats Whisper

- Only shown if the user has completed at least one walk
- Displays total distance formatted with user's preferred unit (km or mi)
- Format: large stat value on top (e.g., "127.4 km"), "walked with Pilgrim" below in italic
- Uses `statValue` font for the number, `caption` italic for the label
- Color: `stone` for number, `fog` for label

**Data source**: Use `.task` modifier to query walks asynchronously with error handling:

```swift
.task {
    do {
        let walks = try DataManager.dataStack.fetchAll(From<Walk>())
        totalDistance = walks.reduce(0) { $0 + $1.distance }
    } catch {
        totalDistance = 0
    }
}
```

**Distance formatting**: `InkScrollView.formatTotalDistance` bakes "walked" into the output string (e.g., "127.4 km walked"), which would duplicate the word with the "walked with Pilgrim" subtitle. Write a small private formatter in `AboutView` that returns only the number + unit (e.g., "127.4 km"), respecting `UserPreferences.distanceMeasurementType`.

### 4. Open Source

- Section label: "Open source" — `caption`, letter-spaced, uppercase (matches the Audio section header convention in SettingsView)
- Body: *"Pilgrim is free and open source. No accounts, no tracking, no data leaves your device. Built as part of the walk · talk · meditate project."* — `body` font
- Two tappable link rows:
  - "walktalkmeditate.org" — opens `https://walktalkmeditate.org` in SFSafariViewController
  - "Source code on GitHub" — opens `https://github.com/walktalkmeditate/pilgrim-ios` in SFSafariViewController
- Link rows: SF Symbol icon + text + chevron, `stone` color, `body` font

### 5. Motto Closer

- Centered, italic, `body` font, `stone` color
- Three lines:
  - *"Slow and chill is the motto."*
  - *"Relax and release is the practice."*
  - *"Peace and harmony is the way."*

### 6. Version Footer

- App version from `CFBundleShortVersionString` — `caption`, `fog.opacity(0.3)`

## Visual Design

### Typography
All from `Constants.Typography.*`:
- Hero headline: `displayMedium` italic
- Hero body: `body`
- Section labels: `caption`, letter-spaced
- Pillar titles: `heading`
- Pillar descriptions: `body`
- Stat value: `statValue`
- Stat label: `caption` italic
- Link rows: `body`
- Motto: `body` italic
- Version: `caption`

### Colors
- Background: `Color.parchment`
- Text: `Color.ink` (primary), `Color.fog` (secondary)
- Accent: `Color.stone` (links, stat value, motto)
- Pillar icon tints: `Color.moss` (walk), `Color.dawn` (talk), `Color.stone` (meditate)
- Dividers: gradient `transparent → stone.opacity(0.2) → transparent`

### Seasonal Awareness
- Apply `SeasonalColorEngine` to the background tint. The parchment base gains a subtle seasonal overlay — greener in spring, warmer in summer, muted in autumn, cooler in winter.
- SceneryItemView shapes already render seasonally (bare winter trees, autumn leaves, etc.)

### Animation
- **Breathing logo**: `PilgrimLogoView` with `animated: true, breathing: $breathing` — 4s easeInOut cycle, 2% scale. Set `breathing = true` in `.onAppear`.
- **Scenery icons**: TimelineView-based animation (tree sway, lantern flicker, moon twinkle) at 36pt. **Resource note**: Three simultaneous 30fps TimelineViews is acceptable for a settings subpage since the user won't stay here for 30+ minutes. However, if battery optimization becomes a concern, these can be replaced with static shape renders.
- **Staggered fade-in**: Each section appears with `.opacity` transition + `.offset(y: 8)`, staggered by 0.1s delay per section on `.onAppear`. Use `Constants.UI.Motion.appear` (0.4s) duration.
- **Reduce motion**: Use `@Environment(\.accessibilityReduceMotion) var reduceMotion`. When `reduceMotion` is true: skip fade-in stagger (show all sections immediately), render scenery shapes as static images (do not use `SceneryItemView` — use the underlying shape views directly without `TimelineView`), and disable logo breathing. `SceneryItemView` does **not** handle reduce-motion internally — `AboutView` must handle this.

## Navigation Integration

In `SettingsView.swift`, add a new section after the Feedback section:

```swift
Section {
    NavigationLink {
        AboutView()
    } label: {
        Text("About")
            .font(Constants.Typography.body)
    }
}
```

The "About" row uses the same pattern as General, Sounds, etc. — plain text with `body` font, NavigationLink push.

Simplify the existing `footer` computed property to remove "crafted with intention" since the About page now carries this sentiment. The modified footer should be:

```swift
private var footer: some View {
    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
        .font(Constants.Typography.caption)
        .foregroundColor(.fog.opacity(0.3))
        .frame(maxWidth: .infinity)
        .padding(.top, Constants.UI.Padding.breathingRoom)
        .padding(.bottom, Constants.UI.Padding.normal)
        .background(Color.parchment)
}
```

## Links Implementation

Create a new `SafariView` wrapper (does not exist in the project):

```swift
import SafariServices

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
```

Place in `Pilgrim/Views/SafariView.swift`. Use via `@State var safariURL: URL?` + `.sheet(item:)` in AboutView.

## Files to Create/Modify

| File | Action |
|------|--------|
| `Pilgrim/Scenes/Settings/AboutView.swift` | **Create** — new About page view |
| `Pilgrim/Views/SafariView.swift` | **Create** — SFSafariViewController wrapper |
| `Pilgrim/Scenes/Settings/SettingsView.swift` | **Modify** — add About NavigationLink, simplify footer |

## Reused Components

- `PilgrimLogoView` — `Pilgrim/Views/PilgrimLogoView.swift`
- `SceneryItemView` — `Pilgrim/Views/Scenery/SceneryItemView.swift` (tree, lantern, moon types)
- `SeasonalColorEngine` — `Pilgrim/Models/SeasonalColorEngine.swift`
- `Constants.Typography.*` — `Pilgrim/Models/Constants.swift`
- `Constants.UI.Motion.*` — appear timing
- `Color.parchment/stone/ink/fog/moss/dawn` — `Pilgrim/Extensions/SwiftUI/Color.swift`
- `DataManager.dataStack` — `Pilgrim/Models/Data/DataManager.swift`
- `Walk` type alias — `Pilgrim/Models/Data/DataModels/Versions/`
- `UserPreferences.distanceMeasurementType` — `Pilgrim/Models/Preferences/UserPreferences.swift`
- `InkScrollView.formatTotalDistance` pattern — `Pilgrim/Scenes/Home/InkScrollView.swift` (private static func, reference for formatting logic only — do not call directly)

## Verification

1. **Build**: `xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build`
2. **Visual check**: Settings → About should show all 6 sections with proper typography, colors, and animations
3. **Breathing logo**: Logo should gently pulse (2% scale, 4s cycle)
4. **Scenery shapes**: Tree, lantern, and moon should render with seasonal awareness and gentle animation
5. **Stats whisper**: Should show real total distance (or be hidden if no walks exist)
6. **Links**: Tapping walktalkmeditate.org and GitHub should open SFSafariViewController
7. **Seasonal colors**: Run in simulator with different dates to verify tint shifts
8. **Reduce motion**: Enable Accessibility → Reduce Motion in simulator — fade-in stagger should be skipped
9. **Unit test**: Test distance formatting with both metric and imperial preferences
