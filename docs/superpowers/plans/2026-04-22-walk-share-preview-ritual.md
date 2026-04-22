# Walk Share Preview Ritual — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-reveal the hosted walk page as a full-screen WKWebView modal after a successful share, with a contemplative 800 ms beat, soft haptic, slide-up animation, skeleton loading state, and a condensed post-ritual success card.

**Architecture:** A new `WebViewLoader` ObservableObject owns a single `WKWebView` and publishes load state. `WebViewRepresentable` (a `UIViewRepresentable`) binds the webview into SwiftUI, with a navigation delegate that locks to the initial share URL and hands off external links to Safari. A new `WalkSharePreviewView` is the modal presentation (top bar + webview + skeleton overlay + floating Copy/Share). `WalkShareView` is modified to own the loader, trigger the ritual on `shareState` transitioning `.uploading → .success`, and present the modal via `.fullScreenCover`.

**Tech Stack:** SwiftUI, WebKit (WKWebView), Combine, CocoaPods, XCTest.

**Reference:** Design spec at `docs/superpowers/specs/2026-04-22-walk-share-preview-ritual-design.md`.

---

## File Structure

**New files:**
- `Pilgrim/Scenes/WalkShare/WebViewLoader.swift` — ObservableObject owning the `WKWebView`, publishing `LoadState` (loading / loaded / failed), with a pure `shouldAllowNavigation(to:)` policy method.
- `Pilgrim/Scenes/WalkShare/WebViewRepresentable.swift` — `UIViewRepresentable` that embeds `WebViewLoader.webView` into SwiftUI.
- `Pilgrim/Scenes/WalkShare/WalkSharePreviewView.swift` — the modal (top bar, webview middle, skeleton overlay, floating action bar).
- `UnitTests/WebViewLoaderTests.swift` — unit tests for the loader's state machine and navigation policy.

**Modified:**
- `Pilgrim/Scenes/WalkShare/WalkShareView.swift` — condensed success card, `.fullScreenCover` wiring, `onChange` ritual trigger, hidden prefetch webview.

**Unchanged:** `Pilgrim/Scenes/WalkShare/WalkShareViewModel.swift` (state machine already distinguishes fresh vs cached via `.uploading`).

---

## Task 1: WebViewLoader state machine — failing test

**Files:**
- Create: `UnitTests/WebViewLoaderTests.swift`

- [ ] **Step 1: Write the failing test file**

Create `UnitTests/WebViewLoaderTests.swift` with this content:

```swift
import XCTest
@testable import Pilgrim

final class WebViewLoaderTests: XCTestCase {

    private let shareURL = URL(string: "https://walk.pilgrimapp.org/abc123")!

    func testInitialState_isLoading() {
        let loader = WebViewLoader(url: shareURL)
        XCTAssertEqual(loader.loadState, .loading)
    }

    func testDidFinish_transitionsToLoaded() {
        let loader = WebViewLoader(url: shareURL)
        loader.handleDidFinish()
        XCTAssertEqual(loader.loadState, .loaded)
    }

    func testDidFail_transitionsToFailed() {
        let loader = WebViewLoader(url: shareURL)
        loader.handleDidFail()
        XCTAssertEqual(loader.loadState, .failed)
    }

    func testRetry_afterFailure_returnsToLoading() {
        let loader = WebViewLoader(url: shareURL)
        loader.handleDidFail()
        loader.retry()
        XCTAssertEqual(loader.loadState, .loading)
    }

    func testShouldAllowNavigation_initialURL_returnsTrue() {
        let loader = WebViewLoader(url: shareURL)
        XCTAssertTrue(loader.shouldAllowNavigation(to: shareURL))
    }

    func testShouldAllowNavigation_differentURL_returnsFalse() {
        let loader = WebViewLoader(url: shareURL)
        let external = URL(string: "https://apple.com/")!
        XCTAssertFalse(loader.shouldAllowNavigation(to: external))
    }

    func testShouldAllowNavigation_differentPathSameHost_returnsFalse() {
        let loader = WebViewLoader(url: shareURL)
        let other = URL(string: "https://walk.pilgrimapp.org/xyz999")!
        XCTAssertFalse(loader.shouldAllowNavigation(to: other))
    }
}
```

- [ ] **Step 2: Run test — expect compile failure**

Run:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/WebViewLoaderTests 2>&1 | tail -20
```

Expected: compile error — `WebViewLoader` not defined.

---

## Task 2: Implement WebViewLoader

**Files:**
- Create: `Pilgrim/Scenes/WalkShare/WebViewLoader.swift`

- [ ] **Step 1: Create the loader**

Create `Pilgrim/Scenes/WalkShare/WebViewLoader.swift`:

```swift
import Foundation
import WebKit
import Combine

final class WebViewLoader: ObservableObject {

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed
    }

    @Published private(set) var loadState: LoadState = .loading

    let webView: WKWebView
    let initialURL: URL

    private let navigationDelegate: NavigationDelegate

    init(url: URL) {
        self.initialURL = url

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.isOpaque = false
        self.webView.backgroundColor = .clear
        self.webView.scrollView.backgroundColor = .clear

        self.navigationDelegate = NavigationDelegate()
        self.webView.navigationDelegate = self.navigationDelegate
        self.navigationDelegate.loader = self

        self.webView.load(URLRequest(url: url))
    }

    deinit {
        webView.navigationDelegate = nil
        webView.stopLoading()
    }

    func retry() {
        loadState = .loading
        webView.load(URLRequest(url: initialURL))
    }

    func handleDidFinish() {
        loadState = .loaded
    }

    func handleDidFail() {
        loadState = .failed
    }

    func shouldAllowNavigation(to url: URL) -> Bool {
        return url == initialURL
    }
}

private final class NavigationDelegate: NSObject, WKNavigationDelegate {

    weak var loader: WebViewLoader?

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url,
              let loader = loader else {
            decisionHandler(.cancel)
            return
        }

        if loader.shouldAllowNavigation(to: url) {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            DispatchQueue.main.async {
                UIApplication.shared.open(url)
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loader?.handleDidFinish()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loader?.handleDidFail()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loader?.handleDidFail()
    }
}
```

- [ ] **Step 2: Add the new file to the Xcode target**

The file needs to be added to the `Pilgrim` target. Since this project uses an Xcode workspace, use this Ruby script to register the file via `xcodeproj`:

```bash
cd /Users/rubberduck/GitHub/momentmaker/pilgrim-ios
# Check for xcodeproj gem; add the file by opening the workspace in Xcode and letting it be picked up by the file-system-synchronized group, or use a helper script.
# Simplest: Xcode detects new files under Pilgrim/ automatically in sync'd groups. Verify membership in project.pbxproj.
grep -c "WebViewLoader.swift" Pilgrim.xcodeproj/project.pbxproj
```

Expected: `>= 2` (file reference + build phase entry). If `0`, open Xcode, right-click `Pilgrim/Scenes/WalkShare/`, "Add Files to 'Pilgrim'", select `WebViewLoader.swift`, ensure `Pilgrim` target is checked.

- [ ] **Step 3: Run tests — expect pass**

Run:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/WebViewLoaderTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **` with all 7 tests passing.

- [ ] **Step 4: Commit**

```bash
git add Pilgrim/Scenes/WalkShare/WebViewLoader.swift UnitTests/WebViewLoaderTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(share): add WebViewLoader state machine for preview modal"
```

---

## Task 3: WebViewRepresentable (SwiftUI bridge)

**Files:**
- Create: `Pilgrim/Scenes/WalkShare/WebViewRepresentable.swift`

- [ ] **Step 1: Create the representable**

Create `Pilgrim/Scenes/WalkShare/WebViewRepresentable.swift`:

```swift
import SwiftUI
import WebKit

struct WebViewRepresentable: UIViewRepresentable {

    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // WebView state is managed by WebViewLoader; nothing to update here.
    }
}
```

- [ ] **Step 2: Add to Xcode target**

Run:
```bash
grep -c "WebViewRepresentable.swift" Pilgrim.xcodeproj/project.pbxproj
```

Expected `>= 2` (see Task 2 step 2 guidance if not).

- [ ] **Step 3: Build to verify it compiles**

Run:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Pilgrim/Scenes/WalkShare/WebViewRepresentable.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(share): add WebViewRepresentable SwiftUI bridge"
```

---

## Task 4: WalkSharePreviewView skeleton + chrome

Build the modal UI in stages. This task creates the static structure; subsequent tasks wire in real webview content and animation.

**Files:**
- Create: `Pilgrim/Scenes/WalkShare/WalkSharePreviewView.swift`

- [ ] **Step 1: Create the preview view**

Create `Pilgrim/Scenes/WalkShare/WalkSharePreviewView.swift`:

```swift
import SwiftUI

struct WalkSharePreviewView: View {

    @ObservedObject var loader: WebViewLoader
    let shareURL: String
    let onDismiss: () -> Void

    @State private var captionOpacity: Double = 0
    @State private var showCopiedToast = false
    @State private var toastGeneration = 0

    var body: some View {
        ZStack {
            Color.parchment.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                contentArea
                Spacer(minLength: 0)
            }

            VStack {
                Spacer()
                floatingActionBar
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.3).delay(0.2)) {
                captionOpacity = 1
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Text("Your walk.")
                .font(Constants.Typography.heading)
                .foregroundColor(.ink)
                .opacity(captionOpacity)

            Spacer()

            Button("Done", action: onDismiss)
                .font(Constants.Typography.button)
                .foregroundColor(.stone)
        }
        .padding(.horizontal, Constants.UI.Padding.normal)
        .padding(.vertical, Constants.UI.Padding.small)
        .background(Color.parchment)
    }

    // MARK: - Content area

    private var contentArea: some View {
        ZStack {
            WebViewRepresentable(webView: loader.webView)
                .opacity(loader.loadState == .loaded ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: loader.loadState)

            if loader.loadState == .loading {
                skeleton
            }

            if loader.loadState == .failed {
                failureView
            }
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.normal) {
            Rectangle()
                .fill(Color.fog.opacity(0.2))
                .frame(height: 28)
                .frame(maxWidth: .infinity)

            ForEach(0..<5, id: \.self) { _ in
                Rectangle()
                    .fill(Color.fog.opacity(0.15))
                    .frame(height: 12)
                    .frame(maxWidth: .infinity)
            }

            Rectangle()
                .fill(Color.fog.opacity(0.1))
                .frame(height: 140)
                .frame(maxWidth: .infinity)
        }
        .padding(Constants.UI.Padding.big)
        .transition(.opacity)
    }

    private var failureView: some View {
        VStack(spacing: Constants.UI.Padding.normal) {
            Text("The scroll will appear when your connection returns.")
                .font(Constants.Typography.body)
                .foregroundColor(.fog)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Constants.UI.Padding.big)

            Button("Retry", action: { loader.retry() })
                .font(Constants.Typography.button)
                .foregroundColor(.stone)
                .padding(.horizontal, Constants.UI.Padding.big)
                .padding(.vertical, 12)
                .overlay(
                    Capsule()
                        .stroke(Color.stone.opacity(0.3), lineWidth: 1)
                )
        }
    }

    // MARK: - Floating action bar

    private var floatingActionBar: some View {
        HStack(spacing: Constants.UI.Padding.small) {
            copyButton
            shareButton
        }
        .padding(.horizontal, Constants.UI.Padding.normal)
        .padding(.vertical, Constants.UI.Padding.small)
        .background(
            Color.parchment
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: -2)
        )
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = shareURL
            toastGeneration += 1
            let gen = toastGeneration
            showCopiedToast = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                if toastGeneration == gen { showCopiedToast = false }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: showCopiedToast ? "checkmark" : "doc.on.doc")
                Text(showCopiedToast ? "Copied" : "Copy")
                    .font(Constants.Typography.button)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.parchmentSecondary)
            .foregroundColor(.stone)
            .cornerRadius(Constants.UI.CornerRadius.small)
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if let url = URL(string: shareURL) {
            ShareLink(item: url) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share")
                        .font(Constants.Typography.button)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.stone)
                .foregroundColor(.parchment)
                .cornerRadius(Constants.UI.CornerRadius.small)
            }
        }
    }
}
```

- [ ] **Step 2: Add to Xcode target**

Run:
```bash
grep -c "WalkSharePreviewView.swift" Pilgrim.xcodeproj/project.pbxproj
```

Expected `>= 2`.

- [ ] **Step 3: Build**

Run:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Pilgrim/Scenes/WalkShare/WalkSharePreviewView.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(share): add WalkSharePreviewView modal UI with skeleton and failure states"
```

---

## Task 5: Condensed success card in WalkShareView

Replace the existing `.success` case with the condensed card (no Copy/Share buttons on the card, tappable route preview, "View scroll" affordance, *"Shared ✓"* label).

**Files:**
- Modify: `Pilgrim/Scenes/WalkShare/WalkShareView.swift`

- [ ] **Step 1: Read the current `.success` case**

Run:
```bash
sed -n '267,330p' /Users/rubberduck/GitHub/momentmaker/pilgrim-ios/Pilgrim/Scenes/WalkShare/WalkShareView.swift
```

Confirm the current `.success` case is an `HStack` containing the route preview, URL text, expiry label, and Copy+Share buttons (lines 267–327).

- [ ] **Step 2: Add state variables to WalkShareView**

Find the `@State` declarations near the top of `WalkShareView` (around the existing `@State private var showCopiedToast`) and add:

```swift
@State private var showPreview = false
@State private var revealTask: Task<Void, Never>?
@StateObject private var webViewLoaderHolder = WebViewLoaderHolder()
@State private var previewURL: String?
```

Where `WebViewLoaderHolder` is a small class that lazily creates the loader (needed because `@StateObject` requires eager init and we don't have the URL yet). Add this private class at the bottom of the file, outside the `WalkShareView` struct:

```swift
private final class WebViewLoaderHolder: ObservableObject {
    @Published var loader: WebViewLoader?

    func create(url: URL) {
        loader = WebViewLoader(url: url)
    }

    func clear() {
        loader = nil
    }
}
```

- [ ] **Step 3: Replace the `.success` case with the condensed card**

Find `case .success(let url):` in the view body and replace its block (the entire `VStack` from the opening brace through the matching closing brace and modifiers, roughly lines 267–327) with:

```swift
case .success(let url):
    VStack(spacing: Constants.UI.Padding.normal) {
        Button {
            openPreview(url: url)
        } label: {
            ZStack(alignment: .topTrailing) {
                routePreview
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.fog.opacity(0.4))
                    .padding(8)
            }
        }
        .buttonStyle(.plain)

        HStack(spacing: 6) {
            Text("Shared")
                .font(Constants.Typography.body)
                .foregroundColor(.stone)
            Image(systemName: "checkmark")
                .font(.caption)
                .foregroundColor(.moss)
        }

        Text("Returns to the trail on \(expiryDateFormatted)")
            .font(Constants.Typography.caption)
            .foregroundColor(.fog)
            .italic()

        Button {
            openPreview(url: url)
        } label: {
            Text("View scroll")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    .padding(Constants.UI.Padding.normal)
    .background(Color.parchmentSecondary)
    .cornerRadius(Constants.UI.CornerRadius.normal)
```

- [ ] **Step 4: Add the `openPreview` helper**

Add this private function inside the `WalkShareView` struct (near other private helpers):

```swift
private func openPreview(url: String) {
    guard let parsedURL = URL(string: url) else { return }
    if webViewLoaderHolder.loader == nil {
        webViewLoaderHolder.create(url: parsedURL)
    }
    previewURL = url
    showPreview = true
}
```

- [ ] **Step 5: Build**

Run:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. The preview modal is not yet wired in (that's Task 6).

- [ ] **Step 6: Commit**

```bash
git add Pilgrim/Scenes/WalkShare/WalkShareView.swift
git commit -m "feat(share): condense success card, remove redundant copy/share buttons"
```

---

## Task 6: Wire `.fullScreenCover` + ritual trigger

Add the modal presentation, the hidden prefetch webview (0×0 frame), and the `onChange` handler that fires the ritual when `shareState` transitions `.uploading → .success`.

**Files:**
- Modify: `Pilgrim/Scenes/WalkShare/WalkShareView.swift`

- [ ] **Step 1: Attach `.fullScreenCover` + hidden prefetch to the view body**

Find the end of the main `body` (after the outermost view's closing brace but before `.onDisappear` if present, otherwise just before the final `}` of `var body: some View {`). Append these modifiers:

```swift
.fullScreenCover(isPresented: $showPreview, onDismiss: {
    webViewLoaderHolder.clear()
    previewURL = nil
}) {
    if let loader = webViewLoaderHolder.loader, let url = previewURL {
        WalkSharePreviewView(
            loader: loader,
            shareURL: url,
            onDismiss: { showPreview = false }
        )
    }
}
.background(
    Group {
        if let loader = webViewLoaderHolder.loader, !showPreview {
            WebViewRepresentable(webView: loader.webView)
                .frame(width: 0, height: 0)
                .opacity(0)
                .allowsHitTesting(false)
        }
    }
)
.onChange(of: viewModel.shareState) { oldValue, newValue in
    triggerRitualIfNeeded(old: oldValue, new: newValue)
}
.onDisappear {
    revealTask?.cancel()
    revealTask = nil
    webViewLoaderHolder.clear()
}
```

- [ ] **Step 2: Add the `triggerRitualIfNeeded` helper**

Add inside `WalkShareView`:

```swift
private func triggerRitualIfNeeded(
    old: WalkShareViewModel.ShareState,
    new: WalkShareViewModel.ShareState
) {
    guard case .uploading = old, case .success(let url) = new else { return }
    guard let parsedURL = URL(string: url) else { return }

    webViewLoaderHolder.create(url: parsedURL)
    previewURL = url

    revealTask?.cancel()
    revealTask = Task {
        try? await Task.sleep(for: .milliseconds(800))
        guard !Task.isCancelled else { return }
        await MainActor.run {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            showPreview = true
        }
    }
}
```

- [ ] **Step 3: Build**

Run:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual smoke test — ritual fires on fresh share**

1. Open simulator, launch app.
2. Complete a walk or use demo mode (`--demo-mode`) to access a walk summary with Share enabled.
3. Tap Share, wait.
4. Expected: after Worker returns the URL, ~800 ms later a full-screen modal slides up showing the hosted page. Soft haptic at reveal. Caption *"Your walk."* fades in at top.
5. Tap Done — modal dismisses, success card is in condensed form underneath.

If the ritual does not fire, check: `onChange` fires correctly (add a temporary `print` inside `triggerRitualIfNeeded`), `Task.isCancelled` is false, `showPreview` is being set on the main actor.

- [ ] **Step 5: Manual smoke test — cached share does NOT fire ritual**

1. With a walk that was just shared, quit the app.
2. Reopen the app, navigate to the same walk summary.
3. Expected: condensed success card appears immediately, no modal, no haptic.
4. Tap the route preview on the condensed card. Expected: modal opens (no 800 ms beat this time — deliberate tap).

- [ ] **Step 6: Commit**

```bash
git add Pilgrim/Scenes/WalkShare/WalkShareView.swift
git commit -m "feat(share): trigger preview ritual on fresh share, tap-to-reopen from card"
```

---

## Task 7: Reduce Motion honoring

**Files:**
- Modify: `Pilgrim/Scenes/WalkShare/WalkSharePreviewView.swift`

- [ ] **Step 1: Honor Reduce Motion for caption fade**

In `WalkSharePreviewView.swift`, at the top of the file (after `import SwiftUI`), add:

```swift
import UIKit
```

In the `body`, replace the `.onAppear` block with:

```swift
.onAppear {
    let reduceMotion = UIAccessibility.isReduceMotionEnabled
    let delay = reduceMotion ? 0.0 : 0.2
    let duration = reduceMotion ? 0.2 : 0.3
    withAnimation(.easeInOut(duration: duration).delay(delay)) {
        captionOpacity = 1
    }
}
```

- [ ] **Step 2: Honor Reduce Motion for `.fullScreenCover` slide**

`.fullScreenCover` uses iOS's default slide-up transition. Under Reduce Motion, iOS already swaps it to a crossfade automatically. No additional code needed. Verify this during manual testing.

- [ ] **Step 3: Build**

Run:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual smoke test — Reduce Motion**

1. In simulator: Features → Accessibility → Motion → Reduce Motion (On).
2. Share a walk.
3. Expected: modal appears via crossfade rather than slide-up. Haptic still fires. Caption fade-in is shorter (0.2 s).
4. Toggle Reduce Motion off, confirm slide-up returns.

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Scenes/WalkShare/WalkSharePreviewView.swift
git commit -m "feat(share): honor Reduce Motion for preview modal caption"
```

---

## Task 8: VoiceOver focus order

**Files:**
- Modify: `Pilgrim/Scenes/WalkShare/WalkSharePreviewView.swift`

- [ ] **Step 1: Add `.accessibilitySortPriority` to top bar, webview, and action bar**

In `topBar`, add:
```swift
.accessibilitySortPriority(3)
```
immediately after the outer `.background(Color.parchment)`.

In `contentArea`, after the closing `}` of the `ZStack`, add:
```swift
.accessibilitySortPriority(2)
```

In `floatingActionBar`, at the end of the view chain (after the `.background` modifier), add:
```swift
.accessibilitySortPriority(1)
```

- [ ] **Step 2: Build**

Run:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual smoke test — VoiceOver**

1. In simulator: triple-click Home button shortcut → enable VoiceOver (or Accessibility Inspector).
2. Share a walk.
3. Swipe right through modal elements.
4. Expected order: *"Your walk."* caption → Done button → webview content → Copy → Share.

- [ ] **Step 4: Commit**

```bash
git add Pilgrim/Scenes/WalkShare/WalkSharePreviewView.swift
git commit -m "feat(share): set VoiceOver focus order in preview modal"
```

---

## Task 9: Full test suite pass + leak probe

- [ ] **Step 1: Run all unit tests**

Run:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests 2>&1 | tail -10
```

Expected: `** TEST SUCCEEDED **`. All previously passing tests + the 7 new `WebViewLoaderTests` pass.

- [ ] **Step 2: Manual leak probe with Instruments**

1. In Xcode: Product → Profile → Allocations template.
2. Launch app in simulator, start a walk, complete it.
3. Share the walk (ritual fires, modal appears).
4. Tap Done to dismiss.
5. Repeat open-via-route-preview + Done 20 times.
6. In Instruments' allocation view, filter by `WKWebView`. Expected: count returns to baseline after each dismiss; no unbounded growth.
7. Also filter by `WebViewLoader` — same expectation.

If `WKWebView` allocations accumulate:
- Check `webViewLoaderHolder.clear()` is being called (add temporary `print`).
- Check `WebViewLoader.deinit` is being called (add temporary `print`).
- If neither fires on dismiss, there's a retain cycle — inspect for closures capturing `self` strongly.

- [ ] **Step 3: Manual test — failure state**

1. Disable network (Airplane mode on simulator's host, or block `walk.pilgrimapp.org` in `/etc/hosts`).
2. Complete a walk, tap Share.
3. If `.error` fires in the viewmodel: existing error UI shows. Preview does NOT auto-fire. ✓
4. If the share succeeds (cached response) but webview can't reach the URL: the modal opens on skeleton, eventually transitions to failure state with Retry button.
5. Tap Retry — confirm the state returns to `loading` and the skeleton reappears.

- [ ] **Step 3b: Manual test — slow network / skeleton crossfade**

1. In simulator: Features → Network Link Conditioner → select "3G" (or similar low-bandwidth profile).
2. Complete a walk, tap Share.
3. Expected: modal opens on skeleton at ~800 ms after share success. Skeleton visible for 1–3 seconds while the page paints. Skeleton crossfades (~0.3 s) to real content once `WKNavigationDelegate.webView(_:didFinish:)` fires.
4. No judder or layout pop during crossfade.
5. Reset network conditioner after testing.

- [ ] **Step 4: Manual test — external link interception**

Temporarily edit the `pilgrim-worker` (in `../pilgrim-worker`) to add an `<a href="https://apple.com">Apple</a>` link to the hosted page. Redeploy to dev. Share a walk. In the preview modal, tap the Apple link. Expected: Safari opens with apple.com; modal stays mounted on the original page. Revert the worker change after testing.

- [ ] **Step 5: Manual test — ritual cancellation**

To reproduce reliably, temporarily bump the delay in `triggerRitualIfNeeded` from 800 ms to 5 seconds. Share a walk, then before the modal appears, swipe back to the walk list (or background the app). Expected: the modal does NOT spuriously appear when you return. Revert the delay bump after testing.

- [ ] **Step 6: Manual test — dark mode**

1. Settings → Developer → Dark Appearance (or the app's appearance setting if available).
2. Share a walk, observe modal in dark mode.
3. Expected: parchment and stone colors render correctly; floating bar's drop shadow (`Color.black.opacity(0.08)`) remains visible against the page content; no bright halo inversions.

- [ ] **Step 7: Manual test — iPad**

1. Run app on iPad simulator (e.g., iPad Air 11-inch).
2. Share a walk.
3. Expected: modal is full-screen (not form-sheet). Copy/Share bar stretches across iPad width without awkward gaps. Haptic may not fire on iPad (no taptic engine) — that's fine.

- [ ] **Step 8: Final commit (no code changes; verification only)**

If all tests pass and manual checks succeed, no further commits are required. If any test reveals an issue, fix it as a Task 10 ad-hoc entry.

---

## Task 10: Final code review

- [ ] **Step 1: Run the build + test suite one more time**

Run:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **` + `** TEST SUCCEEDED **`.

- [ ] **Step 2: Diff review**

Run:
```
git diff main...HEAD --stat
git log main..HEAD --oneline
```

Expected: 4 new files, 1 modified file, 8 commits.

- [ ] **Step 3: Check for stale debug prints**

Run:
```
git diff main...HEAD -- '*.swift' | grep -E '^\+.*print\('
```

Expected: no output. If any debug `print` statements remain from testing, remove them in a follow-up commit.

- [ ] **Step 4: Open PR or merge to main (per user preference)**

If this was worked in a worktree, merge back. If straight on main, push.

```bash
git push origin HEAD
```

---

## Notes for the engineer

- **Why a holder class for `WebViewLoader`?** `@StateObject` requires eager initialization in the view's init — but we don't have the URL until `shareState` fires `.success`. A lightweight `@StateObject WebViewLoaderHolder` that lazily instantiates the real loader lets us avoid constructing a webview we may never need (e.g., if the user never shares).
- **Why `.background` instead of `.overlay` for the prefetch webview?** Both work. `.background` is slightly more idiomatic for invisible helpers. The `frame(width: 0, height: 0)` + `opacity(0)` + `allowsHitTesting(false)` combination ensures it doesn't affect layout or interaction.
- **Why not use `@StateObject` on `WebViewLoader` directly?** Because its lifetime must span the hidden-prefetch + modal phases but also be torn down on dismiss. A holder gives us explicit control via `clear()`.
- **SwiftUI `.fullScreenCover` transition customization**: if the default slide-up timing feels off (too fast, too slow), it's not easy to override directly. Open question in the spec flags a fall-back to a custom presentation controller if needed. Don't attempt this in v1 unless visual verification shows the default transition is off-vibe.
- **CocoaPods/SPM**: no new dependencies. Everything uses Foundation, UIKit, WebKit, SwiftUI, Combine — all system frameworks.
