# Constellation appearance mode + Edit My Journey link

**Release:** 1.6.0
**Status:** Spec — pending review
**Date:** 2026-05-07
**Branch (proposed):** `feat/constellation-mode-and-edit-link`

## 1. Problem statement

Pilgrim's iOS app ships three appearance modes: Auto / Light / Dark. The
companion landing site (`pilgrimapp.org`) ships a fourth — "star mode" /
constellation — with a deep-indigo background, lavender text, and a
canvas-rendered field of drifting stars. The mode is signature on the
web; the app has no equivalent.

Separately, an in-browser editor for `.pilgrim` files now lives at
`edit.pilgrimapp.org`. The companion viewer at `view.pilgrimapp.org` is
already linked from the in-app `Settings → Data → View My Journey` row.
The editor is not yet discoverable from inside the app.

This spec covers two coordinated additions for 1.6.0:

1. **Constellation appearance mode** — fourth option in Appearance,
   landing-aligned palette, app-wide overlay of sparse animated stars.
2. **Edit My Journey link** — sibling row in `Settings → Data` that
   opens `edit.pilgrimapp.org` via the same `WKWebView` + JS-bridge
   pattern already used for the viewer.

## 2. Scope

### In

- New appearance mode value `"constellation"` (extends existing
  `UserPreferences.appearanceMode: String` — no schema migration)
- `AppearanceManager` gains `isConstellation` published flag
- New detail screen `AppearanceView.swift` (icon + title + description +
  trailing-checkmark rows) reached via NavigationLink from
  `AtmosphereCard`
- `AtmosphereCard` refactored from inline 3-segment picker to a single
  navigation row that previews the current mode glyph
- New overlay view `ConstellationOverlay.swift` — `TimelineView`-driven
  Canvas, 1–12 sparse stars, occasional shooting star, app-wide via root
  `ZStack`, accessibility-aware
- New file `JourneyEditorView.swift` — mirror of
  `JourneyViewerView.swift`, points at `edit.pilgrimapp.org`
- Hardcoded URLs added to `Pilgrim/Models/Config.swift` under a new
  `Web` namespace: `Web.viewer`, `Web.editor`
- Sibling row added to `DataSettingsView`, shared footer text rewritten
- New unit tests for `AppearanceManager.resolve(...)` covering all four
  modes
- Localization keys added to `LS.swift`

### Out (explicit non-goals)

- **Round-trip deep-link import** from edit.pilgrimapp.org back into the
  app. URL-scheme payload limits, schema-version coupling between
  editor and app (PilgrimV6 / PilgrimV7), and the trust model of
  re-importing externally edited walks all need their own design pass.
  User flow stays manual: edit in browser → re-export `.pilgrim` from
  the editor → use existing `Import Data` flow if changes need to come
  back to the device.
- **Native in-app editor.** Future spike, not 1.6.0.
- **Constellation as a context-state** triggered by night-walking
  conditions (location + sun angle). Wild-lens convergence in dream
  flagged this as the more ambitious shape; deferred for evaluation
  after Constellation as a global toggle ships and we see whether
  anyone uses it.
- **Per-text lavender override** to exactly match landing's
  `rgba(220,215,255,0.85)`. Project's existing dark-mode text colors
  (already near-white per asset catalog dark variants) are used
  unchanged. If visual QA on `#0a0a12` shows muddy text in specific
  surfaces, ship a tweak in 1.6.1.
- **Dedicated `turningIndigo` lighter twin** for Constellation. Existing
  dark variant of `turningIndigo` is used. If winter-solstice accent
  disappears against `#0a0a12`, ship asset tweak in 1.6.1.
- **Mapbox style swap** in Constellation. Active-walk map keeps current
  style. Mapbox tiles are opaque, so the indigo bg never peeks through
  during walks; only the star overlay renders above the map. Visual
  mud accepted.
- **Schema-version query param** on the editor URL. Editor handles
  whatever version we inject via the JS bridge. Add later if mismatch
  becomes a real issue.

## 3. Acceptance criteria

### Constellation mode

- [ ] User can select Constellation from `Settings → Atmosphere →
      Appearance`. Selection persists across launches.
- [ ] When Constellation is active, app uses `.dark` color scheme AND
      renders an indigo background (`#0a0a12`) with a sparse animated
      star field on every screen including settings, home, walk-end,
      meditation, and active walk.
- [ ] Star count is randomized between 1 and 12 once per overlay
      lifetime (regenerates when the overlay re-mounts).
- [ ] An occasional shooting star streaks diagonally; spawn interval
      30–90 s random.
- [ ] When Reduce Motion is on, stars freeze at a fixed opacity of
      `0.6` (mid-twinkle) and shooting stars are suppressed entirely.
- [ ] When Reduce Transparency is on, the overlay is skipped entirely
      and the app renders in standard `.dark` palette.
- [ ] Overlay does not intercept taps (`.allowsHitTesting(false)`) and
      is hidden from VoiceOver (`.accessibilityHidden(true)`).
- [ ] Switching from Constellation to any other mode tears down the
      overlay cleanly (no `Timer` left running, no `@State` retained
      beyond view lifecycle, no log spam).
- [ ] Twinkle frequency is ≤ 1 Hz per star; shooting star is a single
      600 ms fade transition with no flicker. Design intent is WCAG
      2.3.1 compliance (three-flashes-or-below); formal luminance /
      flash-frequency measurement is not gated on initial ship — if a
      user reports a photosensitivity issue, ship a 1.6.x patch with
      the mode disabled by default until measured.
- [ ] App backgrounded → `TimelineView(.periodic)` stops emitting
      `context.date` updates per Apple's documented behaviour ("aligns
      to schedule when visible"); §8 manual QA includes an Instruments
      Energy Log capture confirming CPU drops to ~0 in the background.

### Edit My Journey link

- [ ] `Settings → Data` shows two rows in the existing journey section:
      "View My Journey" and "Edit My Journey".
- [ ] Tapping "Edit My Journey" pushes a `JourneyEditorView` that loads
      `edit.pilgrimapp.org` in a `WKWebView` and injects walk JSON via
      the same JS-bridge pattern used by the viewer.
- [ ] Footer copy explains both rows accurately. Privacy reassurance
      reads "your walk data is not uploaded" (the editor page itself
      is fetched over the network; only the walk JSON is local).
- [ ] Both URLs are read from `Config.Web.*` (hardcoded; not remote-
      configured).
- [ ] Edit acceptance is broken into observable steps in §8 step 7
      (open walk → edit a field → see edit reflected in the editor →
      export → re-import via Import Data).
- [ ] Offline behaviour: if `WKWebView` reports
      `didFailProvisionalNavigation` (no network, DNS, 5xx) the view
      shows the same error fallback as `JourneyViewerView` (existing
      `error` state with "exclamationmark.triangle" icon and a
      message). No retry button in 1.6.0 — user dismisses and re-
      enters.
- [ ] AtmosphereCard regression: existing Auto / Light / Dark
      selections persist across the picker → nav-row refactor; the
      row glyph and label always reflect the active mode and update
      when the underlying preference changes.

## 4. Architecture

### 4.1 Existing primitives reused

- `UserPreferences.appearanceMode` (String, Required, default
  `"system"`) — extended with a fourth valid value, no migration
- `AppearanceManager` (existing `@ObservedObject`, exposes
  `resolvedScheme: ColorScheme?`) — extended with
  `isConstellation: Bool`
- `PilgrimApp.swift` line 33: `.preferredColorScheme(...)` — wrapped in
  a root `ZStack` that conditionally renders the overlay layer
- `JourneyWebView` (`UIViewRepresentable` in `JourneyViewerView.swift`)
  — pattern reused verbatim for the editor; URL parametrized
- `Constants.Typography.*`, `.ink`, `.fog`, `.stone`, `.parchment`,
  `Constants.UI.Padding.*` — used unchanged

### 4.2 New primitives

- `Pilgrim/Models/Config.swift` — new `Web` namespace
  ```swift
  enum Web {
      static let viewer = URL(string: "https://view.pilgrimapp.org")!
      static let editor = URL(string: "https://edit.pilgrimapp.org")!
  }
  ```

- `Pilgrim/Models/AppearanceManager.swift` — extend
  ```swift
  @Published var resolvedScheme: ColorScheme?
  @Published var isConstellation: Bool

  private static func resolve(_ mode: String) -> (ColorScheme?, Bool) {
      switch mode {
      case "light":         return (.light, false)
      case "dark":          return (.dark,  false)
      case "constellation": return (.dark,  true)
      default:              return (nil,    false)
      }
  }
  ```

- `Pilgrim/Views/ConstellationOverlay.swift` — new file
  - Reads `@Environment(\.accessibilityReduceMotion)` and
    `\.accessibilityReduceTransparency`
  - On Reduce Transparency: returns `EmptyView`
  - On Reduce Motion: renders static stars (no TimelineView, no
    shooting star)
  - Otherwise: `TimelineView(.periodic(from: .now, by: 1.0/30.0))`
    drives a `Canvas` that draws stars + shooting star
  - Star generation in `onAppear` (random count 1–12, random
    normalized positions, random tier far/mid/near, random twinkle
    phase + frequency 0.3–0.8 Hz)
  - Shooting-star state machine: `idle` → `active(start: Date,
    duration: 0.6s, line: …)` → `idle`. Next-spawn time chosen on
    state transition, 30–90 s random.
  - Star tints: cool `rgb(232, 224, 255)` for far/mid; warm
    `rgb(255, 232, 220)` for ~30% of stars (matches landing's
    `TINT_WARM`)
  - `.allowsHitTesting(false)`, `.accessibilityHidden(true)`,
    `.ignoresSafeArea()`

- `Pilgrim/Scenes/Settings/AppearanceView.swift` — new file
  - List of four rows; tapping a row writes
    `UserPreferences.appearanceMode.value = entry.value` and updates
    local `@State mode` so the checkmark moves
  - Each row: SF Symbol (`.title3`, `.fog`) at fixed 28pt width,
    serif label, caption description, trailing checkmark when active
  - Mode glyphs: `circle.righthalf.filled` (Auto), `sun.max` (Light),
    `moon` (Dark — note: avoid `moon.stars` which would collide with
    Constellation), `sparkles` (Constellation)

- `Pilgrim/Scenes/Settings/JourneyEditorView.swift` — new file
  - Same shape as `JourneyViewerView.swift`: `prepareData()` builds
    walks JSON, `JourneyWebView` loads URL and injects JSON on
    `didFinish`
  - Differences: title `"Edit My Journey"`, URL `Config.Web.editor`,
    JS bridge call may need updating to
    `window.pilgrimEditor.loadData(data)` if the editor exposes a
    distinct API. **Verify the editor's actual JS API name before
    landing this file.** If the editor reuses
    `window.pilgrimViewer.loadData`, drop the rename.

### 4.3 Composition at the root

```swift
// PilgrimApp.swift
WindowGroup {
    ZStack {
        if appearanceManager.isConstellation {
            Color(red: 0.039, green: 0.039, blue: 0.071)
                .ignoresSafeArea()
        }
        RootCoordinatorView()
        if appearanceManager.isConstellation {
            ConstellationOverlay()
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
    .preferredColorScheme(appearanceManager.resolvedScheme)
}
```

ZStack ordering: indigo bg first (deepest), then app content, then
overlay last (visually topmost). Stars render *over* every surface
including Mapbox tiles, the active-walk stats panel, and modal sheets.
This is intentional — Mapbox tiles are opaque, so without the overlay
sitting on top the stars would never be visible during walks. With
`.allowsHitTesting(false)` the overlay accepts no touches; all
gestures pass through to the app content underneath. Star opacity is
already low (0.3 base × twinkle modulation) so content readability is
preserved.

### 4.4 Settings UI flow

```
Settings → Atmosphere card
   "Appearance"  [✦ Constellation ›]   ← row, glyph echoes current mode
        ↓ tap
   AppearanceView
   ┌─────────────────────────────────────┐
   │ ◐  Auto                             │
   │     Match the system setting        │
   │                                     │
   │ ☀  Light                            │
   │     Parchment background, ink text  │
   │                                     │
   │ ☾  Dark                             │
   │     Easy on the eyes for evening    │
   │                                     │
   │ ✦  Constellation              ✓     │
   │     A quiet night sky, with         │
   │     drifting stars                  │
   └─────────────────────────────────────┘
```

### 4.5 Settings → Data flow (new sibling row)

```
Settings → Data
  ...
  ┌─────────────────────────────────────┐
  │ View My Journey                  ›  │
  │ Edit My Journey                  ›  │
  └─────────────────────────────────────┘
  Footer: "View renders your walks at view.pilgrimapp.org. Edit
  opens edit.pilgrimapp.org for in-browser editing. Your walk data
  is not uploaded; the JSON is injected into the browser via the
  JS bridge."
```

## 5. Resource safety

Project-wide constraint (CLAUDE.md): walks run 30+ minutes; resource
leaks compound and are unacceptable. Constellation overlay is the only
new always-on animation system.

- **No `Timer.scheduledTimer`** — `TimelineView` provides the clock
- **No `DispatchQueue.asyncAfter`** for shooting-star scheduling — next-
  spawn time is computed and stored in `@State`; `TimelineView` checks
  it each tick
- **No Combine subscription** beyond the existing `AppearanceManager`
  publisher
- **No `@State` array mutation inside `withAnimation(.repeatForever)`**
  — twinkle is computed deterministically from `context.date` per
  frame (pure function of time + per-star seed)
- **View lifecycle is the cleanup mechanism** — when
  `isConstellation` flips false, the `ZStack` drops the overlay,
  `TimelineView` stops firing, `@State` releases. No manual teardown.
- **Background → animation pause** is automatic (`TimelineView`
  respects scene phase)

## 6. Accessibility

- `accessibilityReduceMotion` → freeze stars at mid-opacity, suppress
  shooting stars
- `accessibilityReduceTransparency` → suppress overlay entirely;
  Constellation falls back to standard `.dark` palette
- WCAG 2.3.1 (three-flashes-or-below threshold) — twinkle ≤ 1 Hz per
  star; shooting star is a single 600 ms fade
- VoiceOver — overlay marked `.accessibilityHidden(true)` (decorative)
- Touch — `.allowsHitTesting(false)` (no interception)
- VoiceOver pass on `AppearanceView` — confirm row title + description
  read together as a single utterance

## 7. Privacy

- Walk data injected into `WKWebView` running edit.pilgrimapp.org JS
  uses the same trust model already accepted for view.pilgrimapp.org.
  No data leaves the device via fetch; the JS bridge is the sandbox.
- **Verification required before ship:** confirm
  `edit.pilgrimapp.org` is purely client-side — no analytics calls
  containing walk content, no error-reporting payload that includes
  user data. View has already cleared this bar; edit must too.
- Hardcoded URLs in `Config.Web.*`. No remote configuration of the
  endpoint, so a typo-squat or hijacked config file cannot redirect.
- No round-trip deep-link import = no inbound URL-scheme attack
  surface added.

## 8. Testing

### Unit

- `AppearanceManagerTests` (new file or extend existing)
  - `testResolveSystem()` — mode `"system"` → `(nil, false)`
  - `testResolveLight()` — `(.light, false)`
  - `testResolveDark()` — `(.dark, false)`
  - `testResolveConstellation()` — `(.dark, true)`
  - `testResolveUnknown()` — unrecognized string → defaults to
    `(nil, false)` (graceful fallback)

### Manual visual QA (gating ship)

1. Switch to Constellation on iPhone SE3 (small screen) and iPhone 17
   Pro (large screen). Confirm:
   - Stars visible at all sizes
   - Text readable across home, settings, walk-end, recap, meditation
   - Active walk map is recognizably "starry indigo at night" and not
     unreadable
2. Toggle Reduce Motion (System Settings → Accessibility → Motion).
   Confirm:
   - Stars freeze; no animation; shooting stars never appear
3. Toggle Reduce Transparency. Confirm:
   - Overlay disappears entirely; standard dark palette renders
4. Background app for 30 s. Foreground. Confirm:
   - Animation resumes smoothly; no orphaned shooting star mid-flight;
     no log spam
5. Run a 30-minute meditation in Constellation mode on device. Confirm:
   - No noticeable battery delta vs Dark (informal — iOS Battery
     panel after the run)
   - No memory growth (Xcode Memory Graph snapshot at start vs end of
     session)
5a. Run a 60–90 minute active walk in Constellation mode on device
    (Mapbox + stats panel + overlay simultaneously — the worst-case
    overdraw scenario). Confirm:
    - Battery drain ≤ 25% over 60 min on a fully-charged device (loose
      sanity bound, not a hard SLO)
    - No memory growth between walk start and walk-end snapshot
    - No frame drops visible on the map during pan/zoom interactions
    - Background → foreground transition resumes overlay smoothly
5b. Background the app for 30 s during 5a. Capture an Instruments
    Energy Log. Confirm:
    - CPU drops to ~0 while backgrounded (TimelineView pause)
    - No wake-ups attributable to the overlay
6. Walk through a winter-solstice stub (`--turning-stub
   winter-solstice` launch arg). Confirm:
   - `turningIndigo` accent is visible against `#0a0a12` bg. If not,
     file 1.6.1 follow-up to ship a Constellation-specific lighter
     twin.
7. Tap Edit My Journey. Confirm — observable predicates only:
   - a. `edit.pilgrimapp.org` loads (no spinner stuck, no error
     fallback shown when network is up)
   - b. Walks render in the editor (count matches `Walk.fetchAll`)
   - c. Open one walk; edit a single field (e.g. notes); the edit is
     reflected in the editor's UI
   - d. Export the edited file from the editor (download as
     `.pilgrim`)
   - e. Re-import the file via Settings → Data → Import Data; the
     edited field shows in-app
   - Step c–e gates the round-trip story even though no deep-link
     import is shipped in 1.6.0
8. Tap Edit My Journey while in airplane mode. Confirm:
   - The same error fallback used by `JourneyViewerView` appears
     ("exclamationmark.triangle" + message). Dismiss; re-enter once
     online; loads normally.

### No new UI tests

Animation is flaky to test in simulator and adds little signal beyond
manual QA.

## 9. Localization

`LS.swift` keys added (en):

- `appearance.mode.constellation` — "Constellation"
- `appearance.mode.constellation.description` — "A quiet night sky,
  with drifting stars"
- `appearance.mode.system.description` — "Match the system setting"
- `appearance.mode.light.description` — "Parchment background, ink
  text"
- `appearance.mode.dark.description` — "Easy on the eyes for evening
  walks"
- `journey.viewer.row` — "View My Journey"  (existing key, no change)
- `journey.editor.row` — "Edit My Journey"  (used as both the row
  label in `DataSettingsView` AND the `JourneyEditorView` toolbar
  title — single key shared)
- `journey.section.footer` — "View renders your walks at
  view.pilgrimapp.org. Edit opens edit.pilgrimapp.org for in-browser
  editing. Your walk data is not uploaded; the JSON is injected into
  the browser via the JS bridge."

### Localization ship gate for 1.6.0

The new copy must ship in `en` only. Existing locales (full list
already in `Pilgrim/Support Files/*.lproj/`) follow the project's
normal post-merge translation workflow and may lag by a release. For
non-`en` users in the gap, SwiftUI's `LocalizedStringKey` falls back
to the `en` value automatically — the new mode and row are usable
even if untranslated.

## 10. Risks accepted

| Risk | Decision |
|---|---|
| Mapbox active-walk map looks visually muddy in Constellation | Accept; revisit in 1.6.1 if user feedback is strong |
| Existing dark-mode text colors may read flat on `#0a0a12` (vs landing's lavender) | Accept; ship 1.6.1 lavender override only if QA finds it unreadable |
| `turningIndigo` accent may disappear against `#0a0a12` | Accept; ship Constellation-specific accent in 1.6.1 if winter visual QA flags it |
| `WKWebView` injection trust model for the editor | Inherits viewer's trust model (already shipped); requires explicit confirmation editor JS is purely client-side before ship |
| "Constellation" vocabulary collision with existing zodiac / Four Turnings nomenclature | Accept; landing already uses `body.constellation` — code/web alignment outweighs minor user namespace pressure |
| Editor JS-bridge API name may differ from viewer's (`window.pilgrimViewer.loadData`) | Verify before merge; mirror or distinct call as the editor dictates |

## 11. Open items requiring confirmation before merge

1. Confirm edit.pilgrimapp.org's actual JS-bridge API
   (`window.pilgrimEditor.loadData(...)` vs reusing
   `window.pilgrimViewer.loadData(...)`).
2. Confirm edit.pilgrimapp.org is purely client-side: no telemetry,
   no server-side data fetch that includes walk content, no error
   reporting payload that includes user data. The footer copy "your
   walk data is not uploaded" depends on this.
3. Confirm edit.pilgrimapp.org exposes a `.pilgrim` file *download* /
   export action — the documented user recovery loop in §2 ("re-export
   from the editor → Import Data") presumes one. If the editor is
   in-place edit only and produces no exportable artifact, the spec's
   claim that 1.6.0 supports a "manual" round-trip is broken; we either
   ship without that claim or block.
4. Confirm asset-catalog dark variants of `ink`, `fog`, `stone`,
   `parchment` render acceptably on `#0a0a12` — visual QA pass per §8.
5. Confirm the JSON shape produced by `prepareData()` in
   `JourneyViewerView` is the schema version that
   edit.pilgrimapp.org expects today. If the editor is staged for
   PilgrimV7 and the app still ships V6 (or vice versa from
   `feat/walk-reliquary` ordering), users will see broken renders
   with no diagnostic. Resolution: either confirm version match, or
   add a `?schema=v6` query param + editor-side compatibility check
   before ship.
6. `JourneyEditorView` uses the same `Walk.fetchAll` /
   `PilgrimPackageConverter.convert` path as the viewer. Confirm the
   editor expects exactly the `{walks, manifest}` envelope shape that
   the viewer emits today (line 99 of `JourneyViewerView.swift`).

## 12. Release plan

- Branch: `feat/constellation-mode-and-edit-link` off `main`
- Marketing version bump to `1.6.0`, build number incremented per
  `scripts/release.sh bump`
- Implementation phased into reviewable slices (see implementation
  plan, separate doc):
  1. Config + `AppearanceManager` extension + tests
  2. `AppearanceView` + `AtmosphereCard` refactor
  3. `ConstellationOverlay` + root composition
  4. `JourneyEditorView` + `DataSettingsView` row + Config URL
  5. Localization + visual QA + release-notes copy
- TestFlight first; explicit user approval before TF dispatch
  (`feedback_testflight_approval.md`)
- Release notes: "Introducing Constellation mode — a quiet night sky
  for evening walks. Plus: Edit My Journey, opening
  edit.pilgrimapp.org for in-browser editing of your `.pilgrim`
  archives."
