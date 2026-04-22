# Walk Share Preview Ritual — Design Spec

## Summary

After a user successfully shares a walk, auto-reveal the actual hosted page as a full-screen scroll inside the app — a contemplative modal that lets them witness what they've made before (or instead of) sharing it. Replaces the current utility card where the URL is shown but unseen until copied elsewhere.

## Motivation

Share Your Walk's whole thesis is *the page quality should make people ask "what app is this?"* Today, after a successful share, the user sees a truncated URL and two buttons (Copy, Share) — they cannot see the artifact they just generated without round-tripping through the clipboard or a share sheet. For a pillar feature whose entire argument is aesthetic, hiding the artifact from its creator is an own goal.

This spec re-frames the moment of successful share as a small ritual: *this is yours, witness it, share only if you choose.*

## Non-Goals (for v1)

- Auto-scroll-through-the-narrative on reveal (deferred; potential v1.1 polish)
- Replacing the URL text with a goshuin-style seal/glyph (deferred)
- "Recent Scrolls" history of past shared walks (deferred)
- Edit-before-publish flow (separate feature, much larger scope)
- Changes to the hosted HTML itself in `pilgrim-worker` (Dynamic Type caveat noted below but not fixed here)

## Design

### User Flow — Fresh Share (Ritual Fires)

1. User taps Share. `shareState` transitions `.idle → .uploading` (unchanged).
2. Worker returns URL. `shareState` transitions `.uploading → .success(url)`. This transition is the signal that fires the ritual.
3. The moment `.success` fires, kick off a hidden `WKWebView` and begin loading the URL (prefetch).
4. Success card appears (briefly — it's about to be replaced).
5. After a contemplative beat (~800 ms), a full-screen modal slides up from the bottom over the success card.
6. Modal slide-in: 0.6 s `easeOut`, paired with one `UIImpactFeedbackGenerator(style: .soft)` at the start of the reveal.
7. 200 ms after the modal reaches its final position, a serif caption *"Your walk."* fades in at the top.
8. User reads, scrolls, and taps Copy / Share / Done at their own pace.
9. On dismiss, the modal slides down. The success card underneath transitions to its **condensed** post-ritual form.

### User Flow — Cached Share (No Ritual)

1. User opens a walk summary they've previously shared. `shareState` goes `.idle → .success(url)` directly from the existing cache hit at `WalkShareViewModel.swift:129`.
2. **No modal appears.** Condensed card shown immediately.
3. Tapping the route preview on the condensed card opens the same modal — without the 800 ms beat. A deliberate tap is not a ritual moment; it's an intentional action.

This distinction is the entire persistence story: the `.uploading → .success` transition is the "fresh" signal. `.idle → .success` (or rebuilding the view with an already-successful state) is the "cached" signal. No flag, no stored "has been seen" state.

### User Flow — Failure

- Worker returns error → existing `.error` state, unchanged.
- Worker succeeded (`.success(url)` fired) but webview fails to load (network drop, Worker degraded, R2 hiccup) → modal still opens on the skeleton state, with an inline retry affordance ("The scroll will appear when your connection returns" + Retry button). The modal does **not** auto-dismiss on timeout. The user taps Done when ready — preserving agency even in the failure case.

### Modal Visual Design

- Full-screen presentation (`.fullScreenCover`).
- Parchment background behind the webview, visible briefly during load and between content if the page doesn't fill the screen.
- **Top bar** (parchment, non-opaque, soft bottom shadow only when content scrolls beneath):
  - Left: serif caption *"Your walk."* using `Constants.Typography.body` or `.heading` (to be decided in implementation against the surrounding type scale). Fades in 200 ms after modal settles; does not slide in with the modal.
  - Right: `Done` button, `Constants.Typography.button`, stone color.
- **Middle**: `WKWebView` wrapped in `UIViewRepresentable`. `isOpaque = false`, `backgroundColor = .clear` so parchment shows through during initial paint.
- **Bottom floating action bar** (safe-area-inset aware):
  - Parchment background with soft top shadow so page content reads through as it scrolls past.
  - Copy button (left) + Share button (right), same visual weight and sizing as today's success card buttons.
  - `Copy` mirrors existing clipboard + toast behavior from `WalkShareView.swift:283–291`.
  - `Share` uses the existing `ShareLink` from `WalkShareView.swift:307–322`.

### Skeleton (Loading State)

Shown inside the modal when the webview has not yet painted by the time the modal opens. Aesthetic: "the page being drawn."

- Parchment background (matches the real page's background).
- Faint Cormorant Garamond ghost lines for heading and body text, using `Color.fog.opacity(~0.2)` (tune against the rendered page during implementation).
- Soft ink outline sketch where the route will render.
- Crossfades out (~0.3 s) when `WKNavigationDelegate.webView(_:didFinish:)` fires for the share URL's navigation.

### Reveal Animation

| State | Motion | Haptic |
|---|---|---|
| Default | Slide up from bottom, 0.6 s `easeOut` | `UIImpactFeedbackGenerator(style: .soft)` at reveal start |
| Reduce Motion (`UIAccessibility.isReduceMotionEnabled`) | Parchment crossfade, 0.4 s | Same soft haptic |

### Condensed Success Card (Post-Ritual or Cache Hit)

Replaces the current `.success` card structure at `WalkShareView.swift:267–327`.

- **Route preview**: the existing route preview component, reused. **Tappable** — tap re-opens the modal.
- Small chevron-right glyph in the corner of the route preview as a discoverability hint.
- Below the route preview: serif *"Shared ✓"* label (checkmark glyph) + existing expiry line *"Returns to the trail on X"*.
- **Copy and Share buttons are removed from the card.** They live in the modal.
- Card footer: a quiet tap affordance reading *"View scroll"* in `Constants.Typography.caption`, fog color, centered below the expiry line. The tap target extends via `.contentShape(Rectangle())` and vertical padding so the hit region meets the 44×44 pt HIG minimum even though the glyph is small.

### Re-Opening the Modal Later

From the condensed card, tapping the route preview or the "View scroll" caption re-opens the modal. This path:

- Does **not** use the 800 ms beat (deliberate action, not ritual).
- Does **not** play a haptic on reveal (no need — the user initiated it themselves).
- **Uses the same slide-up animation** (0.6 s `easeOut`, or crossfade under Reduce Motion). The visual vocabulary stays constant; what differs between ritual and re-open is only the pre-roll beat and haptic.
- Webview loads from scratch each time. We do not persist the `WKWebView` across dismissals (see memory safety below). The skeleton appears during first paint on every re-open.

## Technical Architecture

### New Components

- **`WalkSharePreviewView`** — SwiftUI view containing the `WKWebView` + top bar + floating action bar + skeleton overlay. Presented as a `.fullScreenCover` from `WalkShareView`.
- **`WebViewRepresentable`** — `UIViewRepresentable` wrapping `WKWebView` with the navigation delegate and first-paint signaling. Could be placed alongside `WalkSharePreviewView` or, if general-purpose, under `Pilgrim/Views/`.

### Prefetch

- Start loading the share URL in a hidden `WKWebView` the moment `shareState` becomes `.success` via a fresh-share transition. The hidden webview is mounted in the view hierarchy with `.frame(width: 0, height: 0)` (not `.hidden()` — `WKWebView` needs to be in the hierarchy to actually load) and sits behind the success card until the modal opens.
- When the modal opens, reuse the same webview instance (wired through `@StateObject` or a coordinator).
- In the cached-share path, prefetch does not fire. The webview loads from scratch the first time the user taps to open the modal. Skeleton handles the perceived-latency gap.

### Ritual Cancellation Safety

The 800 ms contemplative beat is implemented as a Swift `Task` with a sleep + cancellation guard, not `DispatchQueue.asyncAfter` — so that if the view disappears (user dismisses the walk summary, app backgrounds, etc.) during the beat, the delayed modal reveal cancels cleanly. Pattern (iOS 17+ `onChange` with both old and new values):

```swift
@State private var revealTask: Task<Void, Never>?

...

.onChange(of: viewModel.shareState) { oldValue, newValue in
    guard case .uploading = oldValue, case .success = newValue else { return }
    revealTask?.cancel()
    revealTask = Task {
        try? await Task.sleep(for: .milliseconds(800))
        guard !Task.isCancelled else { return }
        showPreview = true
    }
}
.onDisappear { revealTask?.cancel() }
```

This follows the resource-safety discipline in `.claude/CLAUDE.md` for timer/async cancellation. It also doubles as the State Signal for the ritual — see below.

### Navigation Policy

`WKNavigationDelegate.webView(_:decidePolicyFor:decisionHandler:)`:

- Allow the initial load of the share URL itself.
- Any subsequent navigation action to a different URL → cancel the navigation and hand the URL off to `UIApplication.shared.open(...)` so it opens in Safari.

This protects against future iterations of the hosted page adding links (e.g., to the App Store or landing page) turning the in-app preview into a general-purpose browser.

### Memory & Lifecycle Safety

Consistent with the project's resource-safety discipline (`.claude/CLAUDE.md`):

- The `WKWebView` is torn down when the modal is dismissed. We do **not** keep it alive across the whole walk session.
- Accept a small cost (~hundreds of ms of re-load) on re-opening the same scroll later in favor of eliminating the risk of cumulative webview leaks during a 30+ minute walk.
- All `WKNavigationDelegate` closures use `[weak self]` and the delegate is explicitly nulled on dismiss.
- Use `WKWebsiteDataStore.nonPersistent()` so no cookies, cache, or storage persists across preview sessions. Aligned with both the per-dismiss teardown discipline and the privacy posture of the rest of the app.
- Leak probe (manual + Instruments) is part of the test plan below.

### State Signal for Ritual

`WalkShareView` observes `shareState` via `.onChange(of:)`. Ritual fires if and only if the previous value was `.uploading` and the new value is `.success`. The two paths in `WalkShareViewModel` reach `.success` differently:

- Fresh share: `.idle → .uploading → .success` (the `.uploading` assignment is at `WalkShareViewModel.swift:135`, the success assignment at line 145).
- Cache hit: `.idle → .success` (single assignment at line 129, no `.uploading` in between).

`.onChange` sees the pre/post values directly, so the `.uploading → .success` filter distinguishes cleanly. No persistence flag, no "has been seen" state. If the view is rebuilt or torn down mid-flow, the ritual simply does not fire — and the condensed card appears directly on next open, which is the correct behavior.

### File Touch List (Estimated)

- `Pilgrim/Scenes/WalkShare/WalkShareView.swift` — modify success case to use condensed card + `.fullScreenCover` wiring + `.onChange(of: shareState)` for ritual trigger.
- `Pilgrim/Scenes/WalkShare/WalkSharePreviewView.swift` — new file, modal + webview + skeleton + floating action bar.
- `Pilgrim/Scenes/WalkShare/WebViewRepresentable.swift` — new file, `UIViewRepresentable` wrapping `WKWebView` with navigation delegate.
- `Pilgrim/Scenes/WalkShare/WalkShareViewModel.swift` — no changes expected; the state machine already distinguishes fresh vs cached cleanly (see State Signal above).

## Device & Appearance Considerations

- **iPad**: the project targets iPhone + iPad (`TARGETED_DEVICE_FAMILY = "1,2"`). `.fullScreenCover` on iPad presents as an iPad-sized full-screen modal, not a floating form sheet — which is correct for the ritual framing (we want immersion, not a windowed preview). No iPad-specific layout code needed for v1; rely on standard SwiftUI adaptive layout. Verify Copy/Share bar renders correctly at iPad widths during testing.
- **Dark mode**: colors used in the modal (parchment, stone, fog) must be chosen deliberately. Per `feedback_shadow_color_not_adaptive`, adaptive `ink`/`fog` colors can invert and become bright halos in dark mode. For the floating action bar's top shadow, use a **fixed** dark color (e.g., `Color.black.opacity(0.08)`), not `Color.ink.opacity(...)`. Verify modal in both appearances during testing.

## Accessibility

- **Reduce Motion**: handled via the crossfade fallback specified in the reveal animation table above.
- **VoiceOver**: focus order on modal reveal is (1) *"Your walk."* caption, (2) webview content, (3) Copy / Share / Done bar. Implement via `.accessibilitySortPriority` (higher number = earlier in focus order), not a custom focus trap — the native SwiftUI approach composes more cleanly with `.fullScreenCover`.
- **Dynamic Type**: the webview text is governed by the hosted page's CSS in `pilgrim-worker`, not `Constants.Typography`. The existing page needs to respect the iOS system font size. **Known gap** — filed as a follow-up to address in `pilgrim-worker`; not blocking this iOS change.
- **Haptics**: a single soft impact on reveal. No haptic on any other interaction (Copy already has toast feedback; Share hands off to the system sheet).

## Test Plan

Manual and automated checks to add:

1. **Happy path (fresh share, WiFi)** — share completes, modal reveals after ~800 ms with fully painted content, haptic fires, caption fades in 200 ms later.
2. **Fresh share on slow network** — throttle to 3G in simulator, confirm skeleton appears and crossfades into real content without judder.
3. **Worker-down failure** — block `walk.pilgrimapp.org` in charles proxy / `/etc/hosts`, confirm inline retry appears, user can dismiss, share URL on condensed card is still functional.
4. **Cached share** — share walk, kill app, reopen, navigate to same walk summary, confirm **no modal auto-fires** and condensed card appears directly.
5. **Re-open via tap** — from condensed card, tap route preview, confirm modal opens without the 800 ms beat and without haptic.
6. **Reduce Motion** — enable in iOS Settings → Accessibility → Motion, confirm crossfade path (no slide-up) and haptic still fires.
7. **VoiceOver navigation** — enable VoiceOver, confirm focus order.
8. **Leak probe** — open/dismiss modal 20× during a simulated walk, verify `WKWebView` instance count returns to zero in Instruments' allocation tracker. Run during a 30+ minute simulated walk to check for cumulative drift.
9. **External link interception** — temporarily add a link to the hosted page (pilgrim-worker dev), confirm tapping it opens Safari rather than navigating inside the modal.
10. **Ritual cancellation** — initiate share, then during the 800 ms beat (introduce a larger delay temporarily if needed to reproduce reliably), navigate away from the walk summary or background the app. Confirm the modal does not appear spuriously on return.
11. **Dark mode** — switch appearance mid-preview, confirm floating action bar's shadow and background remain legible, no adaptive-color inversions.
12. **iPad layout** — run preview on iPad simulator, confirm modal is full-screen (not form-sheet) and Copy/Share bar renders at the wider width without awkward gaps.

## Decisions & Tradeoffs

Choices made during brainstorming that future iterations should know about:

- **Ritual over utility**: the modal auto-reveals rather than requiring a tap. Rationale: for a feature whose whole thesis is aesthetic, hiding the artifact behind a tap is the wrong default.
- **WKWebView over SFSafariViewController**: chosen for full control over chrome and vibe. Costs: more implementation work, no built-in Safari affordances. Benefit: no URL bar or reader-mode button intruding on the moment.
- **No persistence of "has seen" state**: ritual fires only on a live `.uploading → .success` transition. Simpler than a flag; handles backgrounding/force-quit naturally (just shows the condensed card on next open).
- **Copy/Share floating, always visible** (vs embedded at the bottom of the scroll): respects user autonomy. The modal is not a gated experience.
- **Condensed card after dismiss** (vs keeping full success card): once the ritual has happened, repeating Copy/Share on the outer card is bureaucratic. Users can re-open the modal to act.
- **Navigation locked to the share URL**: future-proofing. If the hosted page ever needs outbound links, we relax this.
- **Webview torn down per dismiss**: safety over caching. A 30+ minute walk session cannot tolerate a compounding webview leak.

## Open Questions (for implementation)

- Exact typography scale for the *"Your walk."* caption — `.heading` feels right for weight, `.body` for size restraint. Decide against the rendered mock.
- Chevron glyph color/opacity on the condensed route preview — pick against the existing `routePreview` component to avoid overpowering it.
- Whether to use `.fullScreenCover` or a custom `UIViewControllerRepresentable` presentation. `.fullScreenCover` should work; if its transition can't be customized enough for the 0.6 s slide, fall back to custom presentation.
