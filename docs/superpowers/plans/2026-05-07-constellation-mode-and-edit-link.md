# Constellation Mode + Edit My Journey Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Pilgrim 1.6.0 with (a) a fourth appearance mode "Constellation" matching pilgrim-landing's star aesthetic, app-wide, accessibility-aware, and (b) a sibling "Edit My Journey" row in Settings → Data pointing at edit.pilgrimapp.org.

**Architecture:** Constellation extends the existing `AppearanceMode` enum + `AppearanceManager` with one boolean flag (`isConstellation`); a new `ConstellationOverlay` SwiftUI view is composed at the app root via a conditional `ZStack`. The overlay uses `TimelineView` (no `Timer`) for deterministic, lifecycle-bound star animation. Edit My Journey reuses the existing `JourneyWebView` infrastructure with a parameterized URL.

**Tech Stack:** SwiftUI · Combine · CoreStore (existing) · WKWebView · TimelineView · SF Symbols · CocoaPods + SPM hybrid (no new deps) · XCTest.

**Spec:** `docs/superpowers/specs/2026-05-07-constellation-mode-and-edit-link-design.md`

**Branch:** `feat/constellation-mode-and-edit-link` off `main`

**Project structure note:** Pilgrim.xcodeproj uses `PBXFileSystemSynchronizedRootGroup` for `PilgrimWidget` and `ScreenshotTests` only — **NOT** for `Pilgrim/` (main app) or `UnitTests/`. New Swift files in those targets require explicit `project.pbxproj` wiring. Two options:

**Option A — Xcode UI (manual):** drag the new file into the Project Navigator under the appropriate group, ensure the correct target checkbox is selected in the "Add Files" sheet (Pilgrim for app code; UnitTests for test code).

**Option B — `xcodeproj` ruby gem (scriptable):** the project already uses this gem in `scripts/regen-whisper-bootstrap.sh`. To add a Swift file to a target programmatically:

```ruby
# scripts/add-swift-file.rb (one-shot helper; not committed)
require "xcodeproj"
project = Xcodeproj::Project.open("Pilgrim.xcodeproj")
target = project.targets.find { |t| t.name == ARGV[0] }   # e.g. "Pilgrim" or "UnitTests"
group  = project.main_group.find_subpath(ARGV[1], true)   # e.g. "Pilgrim/Views"
file   = group.new_reference(ARGV[2])                     # e.g. "Pilgrim/Views/ConstellationOverlay.swift"
target.source_build_phase.add_file_reference(file)
project.save
```

Run with: `ruby scripts/add-swift-file.rb <Target> <Group> <RelativePath>`. The gem is already available (already used by the whisper script).

Each task that creates a new Swift file calls out the explicit `add-to-target` step.

---

## File Structure

### Create

| Path | Responsibility |
|---|---|
| `Pilgrim/Views/ConstellationOverlay.swift` | TimelineView-driven Canvas overlay drawing 1–12 sparse stars + occasional shooting star; accessibility-gated |
| `Pilgrim/Scenes/Settings/AppearanceView.swift` | Detail screen with four mode rows (icon + title + description + checkmark) |
| `Pilgrim/Scenes/Settings/JourneyEditorView.swift` | Mirror of `JourneyViewerView` pointing at `Config.Web.editor`; reuses `JourneyWebView` |
| `UnitTests/ConstellationStarGenerationTests.swift` | Pure-function tests for star array generation (count bounds, deterministic seed behaviour) |

### Modify

| Path | Change |
|---|---|
| `Pilgrim/Models/AppearanceMode.swift` | Add `.constellation` case + extend `resolvedScheme` |
| `Pilgrim/Models/AppearanceManager.swift` | Add `@Published isConstellation: Bool`; rewire `resolve(...)` to return tuple |
| `Pilgrim/Models/Config.swift` | Add `enum Web { static let viewer / editor }` |
| `Pilgrim/PilgrimApp.swift` | Wrap `RootCoordinatorView` in conditional `ZStack` for Constellation bg + overlay |
| `Pilgrim/Scenes/Settings/SettingsCards/AtmosphereCard.swift` | Replace inline picker with NavigationLink row showing current-mode glyph |
| `Pilgrim/Scenes/Settings/DataSettingsView.swift` | Add second NavigationLink row for `JourneyEditorView`, rewrite footer copy |
| `Pilgrim/Scenes/Settings/JourneyViewerView.swift` | Read URL from `Config.Web.viewer` instead of hardcoded literal |
| `UnitTests/AppearanceModeTests.swift` | Extend with `.constellation` test cases + tuple-returning resolver tests |
| `Pilgrim/Support Files/en.lproj/Localizable.strings` | Add new keys (en values) |
| `Pilgrim/Support Files/Info.plist` (build settings only) | Bump `CFBundleShortVersionString` to `1.6.0` (or via `scripts/release.sh bump`) |

---

## Phase 1 — Foundation + Edit My Journey

Phase 1 covers the lower-risk pieces (data model, Config, Edit row); Phase 2 builds the visual Constellation work on top. Both phases ship together as 1.6.0 — there is no separate 1.5.x release path. If Phase 2 surfaces a blocker, hold the entire 1.6.0 release until resolved (bumping a partial release with only Phase 1 would orphan the version-bump and confuse users).

### Task 1: Extend `AppearanceMode` with `.constellation` case

**Files:**
- Modify: `Pilgrim/Models/AppearanceMode.swift:3-15`
- Test: `UnitTests/AppearanceModeTests.swift:1-34`

- [ ] **Step 1: Write failing test for `.constellation` case parsing**

Add to `UnitTests/AppearanceModeTests.swift` (inside `final class AppearanceModeTests`):

```swift
func testInit_constellation_fromRawString() {
    XCTAssertEqual(AppearanceMode(rawValue: "constellation"), .constellation)
}

func testResolvedScheme_constellation_returnsDark() {
    XCTAssertEqual(AppearanceMode.constellation.resolvedScheme, .dark)
}

func testIsConstellation_constellation_returnsTrue() {
    XCTAssertTrue(AppearanceMode.constellation.isConstellation)
}

func testIsConstellation_dark_returnsFalse() {
    XCTAssertFalse(AppearanceMode.dark.isConstellation)
}

func testIsConstellation_light_returnsFalse() {
    XCTAssertFalse(AppearanceMode.light.isConstellation)
}

func testIsConstellation_system_returnsFalse() {
    XCTAssertFalse(AppearanceMode.system.isConstellation)
}
```

- [ ] **Step 2: Run failing tests**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnitTests/AppearanceModeTests
```

Expected: build fails with `error: type 'AppearanceMode' has no member 'constellation'` and `'isConstellation'`.

- [ ] **Step 3: Implement enum extension**

Replace `Pilgrim/Models/AppearanceMode.swift` body (lines 3-15) with:

```swift
enum AppearanceMode: String {
    case system = "system"
    case light = "light"
    case dark = "dark"
    case constellation = "constellation"

    var resolvedScheme: ColorScheme? {
        switch self {
        case .system:        return nil
        case .light:         return .light
        case .dark:          return .dark
        case .constellation: return .dark
        }
    }

    var isConstellation: Bool {
        self == .constellation
    }
}
```

- [ ] **Step 4: Re-run tests**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnitTests/AppearanceModeTests
```

Expected: all `AppearanceModeTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/AppearanceMode.swift UnitTests/AppearanceModeTests.swift
git commit -m "feat(appearance): add Constellation case to AppearanceMode"
```

---

### Task 2: Extend `AppearanceManager` with `isConstellation`

**Files:**
- Modify: `Pilgrim/Models/AppearanceManager.swift:1-34`
- Test: `UnitTests/AppearanceModeTests.swift:36-88`

- [ ] **Step 1: Write failing test for `isConstellation` published flag**

Add to `final class AppearanceManagerTests` in `UnitTests/AppearanceModeTests.swift`:

```swift
func testIsConstellation_default_isFalse() {
    UserPreferences.appearanceMode.value = "system"
    let manager = AppearanceManager()
    XCTAssertFalse(manager.isConstellation)
}

func testIsConstellation_constellation_isTrueAndSchemeIsDark() {
    UserPreferences.appearanceMode.value = "constellation"
    let manager = AppearanceManager()
    XCTAssertTrue(manager.isConstellation)
    XCTAssertEqual(manager.resolvedScheme, .dark)
}

func testIsConstellation_updatesWhenPreferenceChanges() {
    UserPreferences.appearanceMode.value = "system"
    let manager = AppearanceManager()
    XCTAssertFalse(manager.isConstellation)

    let exp = expectation(description: "isConstellation flips")
    let cancellable = manager.$isConstellation
        .dropFirst()
        .sink { _ in exp.fulfill() }

    UserPreferences.appearanceMode.value = "constellation"
    waitForExpectations(timeout: 1.0)
    cancellable.cancel()

    XCTAssertTrue(manager.isConstellation)
    XCTAssertEqual(manager.resolvedScheme, .dark)
}
```

- [ ] **Step 2: Run failing tests**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnitTests/AppearanceManagerTests
```

Expected: build fails with `error: value of type 'AppearanceManager' has no member 'isConstellation'`.

- [ ] **Step 3: Implement `isConstellation` property**

Replace `Pilgrim/Models/AppearanceManager.swift` body with:

```swift
import SwiftUI
import Combine

final class AppearanceManager: ObservableObject {

    @Published private(set) var resolvedScheme: ColorScheme?
    @Published private(set) var isConstellation: Bool

    private var cancellables = Set<AnyCancellable>()

    init() {
        let initial = Self.resolve(UserPreferences.appearanceMode.value)
        resolvedScheme = initial.scheme
        isConstellation = initial.constellation

        UserPreferences.appearanceMode.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newValue in
                guard let self else { return }
                let next = Self.resolve(newValue)
                let schemeChanged = next.scheme != self.resolvedScheme
                let constellationChanged = next.constellation != self.isConstellation
                guard schemeChanged || constellationChanged else { return }
                if schemeChanged { self.animateTransition() }
                self.resolvedScheme = next.scheme
                self.isConstellation = next.constellation
            }
            .store(in: &cancellables)
    }

    private static func resolve(_ raw: String) -> (scheme: ColorScheme?, constellation: Bool) {
        let mode = AppearanceMode(rawValue: raw) ?? .system
        return (mode.resolvedScheme, mode.isConstellation)
    }

    private func animateTransition() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else { return }
        UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve, animations: {}, completion: nil)
    }
}
```

- [ ] **Step 4: Re-run tests**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnitTests/AppearanceManagerTests
```

Expected: all pass (existing tests + new ones).

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/AppearanceManager.swift UnitTests/AppearanceModeTests.swift
git commit -m "feat(appearance): publish isConstellation flag from AppearanceManager"
```

---

### Task 3: Add `Config.Web` namespace

**Files:**
- Modify: `Pilgrim/Models/Config.swift:83-97`

- [ ] **Step 1: Add Web namespace**

Append to `Pilgrim/Models/Config.swift` immediately after the closing `}` of `enum Whisper {...}` (line 96), still inside `enum Config { ... }`:

```swift
    enum Web {
        static let viewer = URL(string: "https://view.pilgrimapp.org")!
        static let editor = URL(string: "https://edit.pilgrimapp.org")!
    }
```

Final file state ends with:
```swift
    enum Whisper {
        static let manifestURL = URL(string: "https://cdn.pilgrimapp.org/audio/whisper/manifest.json")!
        static let cdnBaseURL = URL(string: "https://cdn.pilgrimapp.org/audio/whisper")!
    }

    enum Web {
        static let viewer = URL(string: "https://view.pilgrimapp.org")!
        static let editor = URL(string: "https://edit.pilgrimapp.org")!
    }

}
```

- [ ] **Step 2: Repoint existing viewer URL through Config**

In `Pilgrim/Scenes/Settings/JourneyViewerView.swift:176`, replace:

```swift
webView.load(URLRequest(url: URL(string: "https://view.pilgrimapp.org")!))
```

with:

```swift
webView.load(URLRequest(url: Config.Web.viewer))
```

- [ ] **Step 3: Build to verify nothing broke**

```bash
xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Pilgrim/Models/Config.swift Pilgrim/Scenes/Settings/JourneyViewerView.swift
git commit -m "refactor(config): move journey URLs into Config.Web namespace"
```

---

### Task 4: Create `JourneyEditorView`

**Files:**
- Create: `Pilgrim/Scenes/Settings/JourneyEditorView.swift`

- [ ] **Step 1: Author `JourneyEditorView.swift`**

Create `Pilgrim/Scenes/Settings/JourneyEditorView.swift` with:

```swift
import SwiftUI
import WebKit
import CoreStore
import Photos

struct JourneyEditorView: View {

    @State private var isLoading = true
    @State private var walksJSON: String?
    @State private var error: String?

    var body: some View {
        ZStack {
            if let json = walksJSON {
                JourneyEditorWebView(walksJSON: json, isLoading: $isLoading)
                    .ignoresSafeArea(edges: .bottom)
            }

            if isLoading {
                VStack(spacing: Constants.UI.Padding.normal) {
                    SwiftUI.ProgressView()
                        .tint(.stone)
                    Text(walksJSON == nil ? "Preparing your journey..." : "Opening editor...")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
            }

            if let error {
                VStack(spacing: Constants.UI.Padding.normal) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundColor(.fog)
                    Text(error)
                        .font(Constants.Typography.body)
                        .foregroundColor(.stone)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        .background(Color.parchment)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Edit My Journey")
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
            }
        }
        .task { await prepareData() }
    }

    private func prepareData() async {
        let systemString = UserPreferences.zodiacSystem.value
        let system: ZodiacSystem = systemString == "sidereal" ? .sidereal : .tropical
        let celestialEnabled = UserPreferences.celestialAwarenessEnabled.value

        do {
            let walks: [Walk] = try DataManager.dataStack.fetchAll(
                From<Walk>().orderBy(.ascending(\._startDate))
            )
            guard !walks.isEmpty else {
                error = "No walks yet. Take a walk first."
                isLoading = false
                return
            }

            let reliquaryEnabled = UserPreferences.walkReliquaryEnabled.value
                && PermissionManager.standard.isPhotosGranted

            var pilgrimWalks = walks.compactMap {
                PilgrimPackageConverter.convert(
                    walk: $0,
                    system: system,
                    celestialEnabled: celestialEnabled,
                    includePhotos: reliquaryEnabled
                )
            }

            if reliquaryEnabled {
                pilgrimWalks = pilgrimWalks.map { Self.enrichWithInlinePhotos($0) }
            }

            let encoder = PilgrimDateCoding.makeEncoder()
            let walksData = try encoder.encode(pilgrimWalks)

            let manifest = PilgrimPackageConverter.buildManifest(
                walkCount: pilgrimWalks.count,
                events: []
            )
            let manifestData = try encoder.encode(manifest)

            guard let walksString = String(data: walksData, encoding: .utf8),
                  let manifestString = String(data: manifestData, encoding: .utf8) else {
                error = "Failed to encode walk data."
                isLoading = false
                return
            }

            let json = "{\"walks\":\(walksString),\"manifest\":\(manifestString)}"
            await MainActor.run { walksJSON = json }
        } catch {
            self.error = "Failed to load walks."
            isLoading = false
        }
    }

    private static func enrichWithInlinePhotos(_ walk: PilgrimWalk) -> PilgrimWalk {
        guard let photos = walk.photos, !photos.isEmpty else { return walk }

        var enriched = walk
        enriched.photos = photos.compactMap { photo in
            guard let dataUrl = loadPhotoDataUrl(localIdentifier: photo.localIdentifier) else {
                return nil
            }
            return PilgrimPhoto(
                localIdentifier: photo.localIdentifier,
                capturedAt: photo.capturedAt,
                capturedLat: photo.capturedLat,
                capturedLng: photo.capturedLng,
                keptAt: photo.keptAt,
                embeddedPhotoFilename: photo.embeddedPhotoFilename,
                inlineUrl: dataUrl
            )
        }
        return enriched
    }

    private static func loadPhotoDataUrl(localIdentifier: String) -> String? {
        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: [localIdentifier],
            options: nil
        )
        guard let asset = fetchResult.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = false
        options.isSynchronous = true
        options.resizeMode = .exact

        let targetSize = CGSize(width: 600, height: 600)

        var result: String?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            guard let image = image,
                  let jpegData = image.jpegData(compressionQuality: 0.7) else { return }
            result = "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
        }
        return result
    }
}

struct JourneyEditorWebView: UIViewRepresentable {

    let walksJSON: String
    @Binding var isLoading: Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.load(URLRequest(url: Config.Web.editor))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(walksJSON: walksJSON, isLoading: $isLoading)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let walksJSON: String
        @Binding var isLoading: Bool
        private var injected = false

        init(walksJSON: String, isLoading: Binding<Bool>) {
            self.walksJSON = walksJSON
            self._isLoading = isLoading
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !injected else { return }
            injected = true

            let jsonObj = jsonObject()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                Task { @MainActor in
                    do {
                        _ = try await webView.callAsyncJavaScript(
                            "window.pilgrimEditor.loadData(data)",
                            arguments: ["data": jsonObj],
                            contentWorld: .page
                        )
                    } catch {
                        print("[JourneyEditor] JS injection failed: \(error)")
                    }
                    self?.isLoading = false
                }
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("[JourneyEditor] Page load failed: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("[JourneyEditor] Navigation failed: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.isLoading = false
            }
        }

        private func jsonObject() -> Any {
            guard let data = walksJSON.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) else {
                return [:]
            }
            return obj
        }
    }
}
```

**JS-bridge note:** This file calls `window.pilgrimEditor.loadData(data)`. Per spec §11 item 1, **before merging Phase 1**, verify edit.pilgrimapp.org's actual JS API. If the editor reuses `window.pilgrimViewer.loadData`, change line in Coordinator's `didFinish` to match.

**Inherited risks acknowledged:** This file is a deliberate mirror of `JourneyViewerView.swift` and inherits the same patterns flagged by review:
- `loadPhotoDataUrl` uses synchronous PHImageManager (blocks calling actor for users with many photos enabled in `walkReliquaryEnabled`)
- Manual JSON string concatenation (`"{\"walks\":...}"`) — preserves identical wire format with the existing viewer
- 1.0 s `DispatchQueue.main.asyncAfter` wait before JS injection — guess, not a contract; will become a readiness handshake when spec §11.1 lands

These are inherited from the existing viewer to preserve behaviour parity. Refactoring the underlying pattern is out of scope for 1.6.0 — file as a 1.7.x cleanup ticket.

- [ ] **Step 2: Add file to Pilgrim target**

`Pilgrim/` is not a synchronized folder. Wire the new file into the Pilgrim target either via Xcode UI ("Add Files to Pilgrim..." → check Pilgrim target only, NOT UnitTests) OR via the helper script in the project structure note above:

```bash
ruby scripts/add-swift-file.rb Pilgrim "Pilgrim/Scenes/Settings" Pilgrim/Scenes/Settings/JourneyEditorView.swift
```

- [ ] **Step 3: Build to verify it compiles**

```bash
xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Pilgrim/Scenes/Settings/JourneyEditorView.swift
git commit -m "feat(journey): add JourneyEditorView for edit.pilgrimapp.org"
```

---

### Task 5: Wire sibling row in `DataSettingsView`

**Files:**
- Modify: `Pilgrim/Scenes/Settings/DataSettingsView.swift:90-99`

- [ ] **Step 1: Replace single-row section with two-row section**

In `Pilgrim/Scenes/Settings/DataSettingsView.swift`, replace the existing block at lines 90-99:

```swift
            Section {
                NavigationLink(destination: JourneyViewerView()) {
                    Text("View My Journey")
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)
                }
            } footer: {
                Text("Opens view.pilgrimapp.org and renders all your walks in the browser. Your data stays on your device — nothing is uploaded.")
                    .font(Constants.Typography.caption)
            }
```

with:

```swift
            Section {
                NavigationLink(destination: JourneyViewerView()) {
                    Text("View My Journey")
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)
                }
                NavigationLink(destination: JourneyEditorView()) {
                    Text("Edit My Journey")
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)
                }
            } footer: {
                Text("View renders your walks at view.pilgrimapp.org. Edit opens edit.pilgrimapp.org for in-browser editing. Your walk data is not uploaded; the JSON is injected into the browser via the JS bridge.")
                    .font(Constants.Typography.caption)
            }
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Manual smoke check on simulator**

Boot Pilgrim in iPhone 17 Pro simulator. Navigate Settings → Data. Confirm:
- Both rows appear with chevrons
- Footer reads as written
- Tapping "View My Journey" opens viewer (existing behaviour)
- Tapping "Edit My Journey" opens edit.pilgrimapp.org (assuming network)

If the editor URL has not yet been confirmed live OR the JS bridge name is wrong, you'll see a stuck spinner or broken render. Note the failure mode and reconcile with §11 spec items 1–3 before proceeding.

- [ ] **Step 4: Commit**

```bash
git add Pilgrim/Scenes/Settings/DataSettingsView.swift
git commit -m "feat(settings): add Edit My Journey row alongside View My Journey"
```

---

**End of Phase 1.** Edit My Journey now works end-to-end. Proceed to Phase 2 for Constellation; the entire branch ships together as 1.6.0.

---

## Phase 2 — Constellation UI

### Task 6: Create `AppearanceView` detail screen

**Files:**
- Create: `Pilgrim/Scenes/Settings/AppearanceView.swift`

- [ ] **Step 1: Author `AppearanceView.swift`**

Create the file with:

```swift
import SwiftUI

struct AppearanceView: View {

    @State private var mode: String = UserPreferences.appearanceMode.value

    private struct ModeEntry: Identifiable {
        let value: String
        let label: String
        let glyph: String
        let description: String
        var id: String { value }
    }

    private let entries: [ModeEntry] = [
        ModeEntry(value: "system",        label: "Auto",          glyph: "circle.righthalf.filled", description: "Match the system setting"),
        ModeEntry(value: "light",         label: "Light",         glyph: "sun.max",                 description: "Parchment background, ink text"),
        ModeEntry(value: "dark",          label: "Dark",          glyph: "moon",                    description: "Easy on the eyes for evening walks"),
        ModeEntry(value: "constellation", label: "Constellation", glyph: "sparkles",                description: "A quiet night sky, with drifting stars")
    ]

    var body: some View {
        List(entries) { entry in
            Button {
                UserPreferences.appearanceMode.value = entry.value
                mode = entry.value
            } label: {
                HStack(spacing: Constants.UI.Padding.normal) {
                    Image(systemName: entry.glyph)
                        .font(.title3)
                        .foregroundColor(.fog)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.label)
                            .font(Constants.Typography.body)
                            .foregroundColor(.ink)
                        Text(entry.description)
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                    }
                    Spacer()
                    if mode == entry.value {
                        Image(systemName: "checkmark")
                            .foregroundColor(.stone)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.parchment)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Appearance")
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
            }
        }
        .onAppear {
            mode = UserPreferences.appearanceMode.value
        }
    }
}
```

- [ ] **Step 2: Add file to Pilgrim target**

```bash
ruby scripts/add-swift-file.rb Pilgrim "Pilgrim/Scenes/Settings" Pilgrim/Scenes/Settings/AppearanceView.swift
```

(Or via Xcode UI — Pilgrim target only.)

- [ ] **Step 3: Build to verify**

```bash
xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Pilgrim/Scenes/Settings/AppearanceView.swift
git commit -m "feat(settings): add AppearanceView detail screen with four mode rows"
```

---

### Task 7: Refactor `AtmosphereCard` to NavigationLink row

**Files:**
- Modify: `Pilgrim/Scenes/Settings/SettingsCards/AtmosphereCard.swift:1-46`

- [ ] **Step 1: Replace card body with NavigationLink row + sounds toggle**

Replace `Pilgrim/Scenes/Settings/SettingsCards/AtmosphereCard.swift` entirely with:

```swift
import SwiftUI
import Combine

struct AtmosphereCard: View {

    @State private var appearanceMode = UserPreferences.appearanceMode.value
    @State private var soundsEnabled = UserPreferences.soundsEnabled.value
    @State private var modeCancellable: AnyCancellable?

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            cardHeader(title: "Atmosphere", subtitle: "Look and feel")

            NavigationLink(destination: AppearanceView()) {
                HStack {
                    Text("Appearance")
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: glyph(for: appearanceMode))
                            .font(.body)
                            .foregroundColor(.fog)
                        Text(label(for: appearanceMode))
                            .font(Constants.Typography.body)
                            .foregroundColor(.fog)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.fog)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()

            settingToggle(
                label: "Sounds",
                description: "Bells, haptics, and ambient soundscapes",
                isOn: $soundsEnabled
            ) { newValue in
                UserPreferences.soundsEnabled.value = newValue
            }

            if soundsEnabled {
                NavigationLink {
                    SoundSettingsView()
                } label: {
                    settingNavRow(label: "Bells & Soundscapes")
                }
            }
        }
        .settingsCard()
        .animation(.easeInOut(duration: 0.2), value: soundsEnabled)
        .onAppear {
            soundsEnabled = UserPreferences.soundsEnabled.value
            appearanceMode = UserPreferences.appearanceMode.value
            modeCancellable = UserPreferences.appearanceMode.publisher
                .receive(on: DispatchQueue.main)
                .sink { newValue in
                    appearanceMode = newValue
                }
        }
        .onDisappear {
            modeCancellable?.cancel()
            modeCancellable = nil
        }
    }

    private func glyph(for mode: String) -> String {
        switch mode {
        case "light":         return "sun.max"
        case "dark":          return "moon"
        case "constellation": return "sparkles"
        default:              return "circle.righthalf.filled"
        }
    }

    private func label(for mode: String) -> String {
        switch mode {
        case "light":         return "Light"
        case "dark":          return "Dark"
        case "constellation": return "Constellation"
        default:              return "Auto"
        }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Manual smoke check**

Boot iPhone 17 Pro simulator. Navigate Settings → Atmosphere. Confirm:
- "Appearance" row shows current mode glyph + label + chevron
- Tapping pushes to `AppearanceView`
- Selecting Light / Dark / Constellation in detail view → returning to Atmosphere shows the new glyph + label
- Existing Sounds toggle still works
- Picking "Constellation" forces dark mode (text + chrome change to dark) but no overlay yet — that comes in Task 8

- [ ] **Step 4: Commit**

```bash
git add Pilgrim/Scenes/Settings/SettingsCards/AtmosphereCard.swift
git commit -m "refactor(settings): convert Appearance picker to NavigationLink row"
```

---

### Task 8: Create `ConstellationOverlay`

**Files:**
- Create: `Pilgrim/Views/ConstellationOverlay.swift`
- Create: `UnitTests/ConstellationStarGenerationTests.swift`

- [ ] **Step 1: Write failing tests for star generation**

Create `UnitTests/ConstellationStarGenerationTests.swift`:

```swift
import XCTest
@testable import Pilgrim

final class ConstellationStarGenerationTests: XCTestCase {

    func testGenerateStars_countWithinRange() {
        for _ in 0..<50 {
            let stars = ConstellationOverlay.generateStars(canvasSize: CGSize(width: 393, height: 852))
            XCTAssertGreaterThanOrEqual(stars.count, 1, "Star count must be ≥ 1")
            XCTAssertLessThanOrEqual(stars.count, 12, "Star count must be ≤ 12")
        }
    }

    func testGenerateStars_positionsNormalized() {
        let stars = ConstellationOverlay.generateStars(canvasSize: CGSize(width: 393, height: 852))
        for star in stars {
            XCTAssertGreaterThanOrEqual(star.position.x, 0)
            XCTAssertLessThanOrEqual(star.position.x, 1)
            XCTAssertGreaterThanOrEqual(star.position.y, 0)
            XCTAssertLessThanOrEqual(star.position.y, 1)
        }
    }

    func testGenerateStars_twinkleFrequencyWithinAudibleRange() {
        let stars = ConstellationOverlay.generateStars(canvasSize: CGSize(width: 393, height: 852))
        for star in stars {
            // WCAG 2.3.1 — must be < 3 Hz; design target ≤ 1 Hz
            XCTAssertLessThanOrEqual(star.twinkleFrequencyHz, 1.0)
            XCTAssertGreaterThan(star.twinkleFrequencyHz, 0.0)
        }
    }

    func testStaticOpacityForReduceMotion_isMidValue() {
        XCTAssertEqual(ConstellationOverlay.staticOpacity, 0.6, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run failing tests**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnitTests/ConstellationStarGenerationTests
```

Expected: build fails — `ConstellationOverlay` doesn't exist.

- [ ] **Step 3: Author `ConstellationOverlay.swift`**

Create `Pilgrim/Views/ConstellationOverlay.swift`:

```swift
import SwiftUI

struct ConstellationOverlay: View {

    static let staticOpacity: Double = 0.6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var stars: [Star] = []
    @State private var shooting: ShootingState = .idle

    var body: some View {
        GeometryReader { geo in
            content(canvasSize: geo.size)
                .onAppear {
                    if stars.isEmpty {
                        stars = Self.generateStars(canvasSize: geo.size)
                    }
                }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func content(canvasSize: CGSize) -> some View {
        if reduceTransparency {
            EmptyView()
        } else if reduceMotion {
            staticView(canvasSize: canvasSize)
        } else {
            animatedView(canvasSize: canvasSize)
        }
    }

    private func staticView(canvasSize: CGSize) -> some View {
        Canvas { gc, size in
            for star in stars {
                drawStar(gc: gc, star: star, size: size, opacity: Self.staticOpacity)
            }
        }
    }

    private func animatedView(canvasSize: CGSize) -> some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 60.0)) { ctx in
            Canvas { gc, size in
                let now = ctx.date
                let t = now.timeIntervalSinceReferenceDate

                for star in stars {
                    let phase = sin(t * 2 * .pi * star.twinkleFrequencyHz + star.twinklePhaseRadians)
                    let opacity = star.baseOpacity * (0.5 + 0.5 * phase)
                    drawStar(gc: gc, star: star, size: size, opacity: opacity)
                }

                if case .active(let start, let line) = shooting {
                    let elapsed = now.timeIntervalSince(start)
                    if elapsed < 0.6 {
                        drawShootingStar(gc: gc, line: line, elapsed: elapsed, size: size)
                    }
                    // No state mutation here — the .task driver below schedules transitions.
                }
            }
        }
        .task {
            // Drives shooting-star scheduling outside the Canvas render path.
            // Cancelled automatically when the view leaves the hierarchy.
            while !Task.isCancelled {
                let waitSeconds = Double.random(in: 30...90)
                do {
                    try await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
                } catch { return }
                guard !Task.isCancelled else { return }

                let line = Self.randomShootingLine(in: canvasSize)
                await MainActor.run { shooting = .active(start: Date(), line: line) }

                do {
                    try await Task.sleep(nanoseconds: 600_000_000)  // 600 ms shooting duration
                } catch { return }
                guard !Task.isCancelled else { return }

                await MainActor.run { shooting = .idle }
            }
        }
    }

    private func drawStar(gc: GraphicsContext, star: Star, size: CGSize, opacity: Double) {
        let x = star.position.x * size.width
        let y = star.position.y * size.height
        let radius = star.radius
        let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
        let tint = star.tint
        let color = Color(red: tint.r, green: tint.g, blue: tint.b, opacity: opacity)
        gc.fill(Path(ellipseIn: rect), with: .color(color))
    }

    private func drawShootingStar(gc: GraphicsContext, line: ShootingLine, elapsed: Double, size: CGSize) {
        let progress = elapsed / 0.6
        let alpha = sin(.pi * progress) // smooth fade in + out
        let head = CGPoint(
            x: line.start.x + (line.end.x - line.start.x) * progress,
            y: line.start.y + (line.end.y - line.start.y) * progress
        )
        let tail = CGPoint(
            x: line.start.x + (line.end.x - line.start.x) * max(0, progress - 0.15),
            y: line.start.y + (line.end.y - line.start.y) * max(0, progress - 0.15)
        )
        var path = Path()
        path.move(to: tail)
        path.addLine(to: head)
        gc.stroke(
            path,
            with: .color(.white.opacity(alpha * 0.9)),
            style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
        )
    }

    static func generateStars(canvasSize: CGSize) -> [Star] {
        let count = Int.random(in: 1...12)
        return (0..<count).map { _ in
            let layer = Star.Layer.allCases.randomElement()!
            let useWarm = Double.random(in: 0...1) < 0.3
            return Star(
                position: CGPoint(x: CGFloat.random(in: 0.05...0.95), y: CGFloat.random(in: 0.05...0.95)),
                layer: layer,
                radius: layer.radius,
                baseOpacity: 0.3 + Double.random(in: 0...0.3),
                twinkleFrequencyHz: Double.random(in: 0.3...0.8),
                twinklePhaseRadians: Double.random(in: 0...(2 * .pi)),
                tint: useWarm ? .warm : .cool
            )
        }
    }

    static func randomShootingLine(in size: CGSize) -> ShootingLine {
        // Pick start corner randomly so streaks don't always travel
        // down-right; angle is constrained to ~25-45° from horizontal
        // for a "falling" look.
        let fromLeft = Bool.random()
        let startY = CGFloat.random(in: 0...size.height * 0.4)
        let startX = fromLeft
            ? CGFloat.random(in: 0...size.width * 0.3)
            : CGFloat.random(in: size.width * 0.7...size.width)
        let length = size.width * CGFloat.random(in: 0.4...0.6)
        let absAngle = CGFloat.random(in: 0.43...0.79)  // 25°–45° in radians
        let dx = (fromLeft ? 1 : -1) * length * cos(absAngle)
        let dy = length * sin(absAngle)
        return ShootingLine(
            start: CGPoint(x: startX, y: startY),
            end: CGPoint(x: startX + dx, y: startY + dy)
        )
    }
}

struct Star {
    let position: CGPoint        // normalized 0..1
    let layer: Layer
    let radius: CGFloat
    let baseOpacity: Double
    let twinkleFrequencyHz: Double
    let twinklePhaseRadians: Double
    let tint: Tint

    enum Layer: CaseIterable {
        case far, mid, near
        var radius: CGFloat {
            switch self {
            case .far:  return 0.8
            case .mid:  return 1.3
            case .near: return 2.0
            }
        }
    }

    struct Tint {
        let r: Double
        let g: Double
        let b: Double
        static let cool = Tint(r: 232.0/255, g: 224.0/255, b: 255.0/255)
        static let warm = Tint(r: 255.0/255, g: 232.0/255, b: 220.0/255)
    }
}

struct ShootingLine {
    let start: CGPoint
    let end: CGPoint
}

enum ShootingState {
    case idle
    case active(start: Date, line: ShootingLine)
}
```

- [ ] **Step 4: Add both new files to their targets**

Neither `Pilgrim/` nor `UnitTests/` is a synchronized folder. Wire each file in via Xcode UI or the helper:

```bash
ruby scripts/add-swift-file.rb Pilgrim   "Pilgrim/Views" Pilgrim/Views/ConstellationOverlay.swift
ruby scripts/add-swift-file.rb UnitTests "UnitTests"     UnitTests/ConstellationStarGenerationTests.swift
```

The test file MUST go to the UnitTests target only; the overlay MUST go to the Pilgrim target only. Adding the overlay to UnitTests would break the @testable import.

- [ ] **Step 5: Run tests**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnitTests/ConstellationStarGenerationTests
```

Expected: all 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Pilgrim/Views/ConstellationOverlay.swift UnitTests/ConstellationStarGenerationTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(constellation): add ConstellationOverlay with TimelineView star canvas"
```

---

### Task 9: Wire root ZStack in `PilgrimApp`

**Files:**
- Modify: `Pilgrim/PilgrimApp.swift:30-35`

- [ ] **Step 1: Wrap RootCoordinatorView in conditional ZStack**

Replace `Pilgrim/PilgrimApp.swift` body (the `var body: some Scene { ... }` block) with:

```swift
    var body: some Scene {
        WindowGroup {
            ZStack {
                if appearanceManager.isConstellation {
                    Color(red: 0.039, green: 0.039, blue: 0.071)
                        .ignoresSafeArea()
                }
                RootCoordinatorView(viewModel: RootCoordinatorViewModel())
                if appearanceManager.isConstellation {
                    ConstellationOverlay()
                }
            }
            .preferredColorScheme(appearanceManager.resolvedScheme)
        }
    }
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Manual visual smoke**

Boot iPhone 17 Pro simulator. Settings → Atmosphere → Appearance → Constellation. Confirm:
- Indigo background visible behind transparent surfaces
- 1–12 stars drift over the screen with subtle twinkle
- Switching back to Auto / Light / Dark removes overlay within one frame: indigo background gone, no star artifacts, no SwiftUI purple "modifying state during view update" warnings in Xcode console
- Stars reappear (newly randomized count + positions) when switching back to Constellation

Boot iPhone SE3 simulator (small screen). Repeat. Confirm star density still feels sparse (1–12 cap holds).

- [ ] **Step 4: Commit**

```bash
git add Pilgrim/PilgrimApp.swift
git commit -m "feat(constellation): wire ConstellationOverlay at app root"
```

---

## Phase 3 — Localization, QA, Release

### Task 10: Localization

**No localization changes in 1.6.0.** The existing `AtmosphereCard` (lines 13-15 of the original) and `DataSettingsView` row both use hardcoded English literals (`"Atmosphere"`, `"Auto"`, `"View My Journey"`). The new strings authored in Tasks 5–7 follow the same pattern. Localization is a separate, project-wide pass tracked outside this release.

- [ ] **Step 1: Verify the surrounding hardcoded pattern**

```bash
grep -n "Text(\"" Pilgrim/Scenes/Settings/SettingsCards/AtmosphereCard.swift Pilgrim/Scenes/Settings/DataSettingsView.swift | head -10
```

Expected: results show hardcoded English literals (e.g. `Text("Atmosphere")`, `Text("View My Journey")`). The new code in Tasks 5–7 follows this pattern — no `LS["..."]` wrapper introduced.

- [ ] **Step 2: File a follow-up issue**

Create a tracking note in `docs/superpowers/plans/` (or the project's normal issue tracker) titled "i18n: localize Constellation + Edit Journey strings" with a list of every English literal added by this plan:
- "Appearance" (AppearanceView toolbar)
- "Auto" / "Light" / "Dark" / "Constellation" (mode labels)
- "Match the system setting" / "Parchment background, ink text" / "Easy on the eyes for evening walks" / "A quiet night sky, with drifting stars" (descriptions)
- "View My Journey" / "Edit My Journey" (DataSettingsView rows)
- The footer text in Task 5
- "Edit My Journey" (JourneyEditorView toolbar)
- "Preparing your journey..." / "Opening editor..." / "No walks yet. Take a walk first." / "Failed to encode walk data." / "Failed to load walks." (JourneyEditorView states)

The follow-up commits these to `LS.swift` + `Localizable.strings` post-merge once translations are sourced. SwiftUI's `LocalizedStringKey` falls back to the literal when a key is missing, so non-`en` users see `en` strings until then — degrades gracefully.

This task is documentation-only; no code change, no commit needed beyond the tracking note.

---

### Task 11: Manual visual + accessibility QA

**No code changes** — this task is execution of the spec's §8 QA matrix.

- [ ] **Step 1: Visual QA on iPhone SE3 simulator (small screen)**

Boot iPhone SE3 sim. Cycle through all four modes. For Constellation:
- Stars visible at all sizes
- Text readable across home, settings, walk-end, recap, meditation, active walk map
- Active walk map renders as "starry indigo at night" — accept any visual mud as designed

Take screenshots into `/tmp/constellation-qa/` for posterity.

- [ ] **Step 2: Visual QA on iPhone 17 Pro simulator (large screen)**

Same checklist, large screen.

- [ ] **Step 3: Reduce Motion behaviour**

Settings (sim) → Accessibility → Motion → Reduce Motion ON. Switch Pilgrim to Constellation. Confirm:
- Stars frozen at 0.6 opacity
- No twinkle animation
- No shooting stars after 90+ s wait

Toggle Reduce Motion OFF — animation resumes.

- [ ] **Step 4: Reduce Transparency behaviour**

Settings (sim) → Accessibility → Display & Text Size → Reduce Transparency ON. Switch Pilgrim to Constellation. Confirm:
- Overlay disappears entirely
- Indigo background also disappears (overlay is the trigger condition)
- App renders in standard `.dark` palette

Toggle off — overlay returns.

- [ ] **Step 5: Background → foreground transition**

In Constellation, background the app for 30 s, foreground. Confirm:
- Overlay resumes smoothly
- No orphaned shooting star mid-flight
- No log spam in Xcode console

- [ ] **Step 6: 30-min meditation on device**

Run a real 30-min meditation in Constellation mode on a physical device. Capture Xcode Memory Graph at start + end of session. Confirm:
- No memory growth between snapshots (the load-bearing measurement)
- No console warnings or `nan` opacity values during the session
- Battery experience is subjectively comparable to Dark — no specific numeric SLO; if the device feels noticeably warm or drains visibly faster than a comparable Dark session, file a 1.6.1 issue and revisit

- [ ] **Step 7: 60–90-min active walk on device**

Worst-case overdraw: Mapbox + stats panel + ConstellationOverlay. Walk for 60+ min in Constellation. Confirm:
- No memory growth between walk-start and walk-end snapshots (load-bearing)
- No frame drops visibly during map pan/zoom (subjective; if drops appear, capture an Instruments Time Profiler trace and file 1.6.1 issue)
- Background → foreground resumes overlay smoothly with no orphaned shooting star
- No SwiftUI purple "modifying state during view update" warnings in Xcode console

- [ ] **Step 8: Instruments Energy Log**

Run app in Constellation on device under Instruments → Energy Log. Background app for 30 s. Confirm CPU drops to ~0; no wake-ups attributable to overlay.

- [ ] **Step 9: Winter solstice stub**

Launch app with the `--turning-stub winter-solstice` arg, which is read by `AppDelegate.parseTurningStubLaunchArg()` (verify in `Pilgrim/AppDelegate.swift:151-187`). Note the **`--` separator** between `simctl` flags and the app's launch args:

```bash
xcrun simctl launch booted org.walktalkmeditate.pilgrim -- --turning-stub winter-solstice
```

Without the `--` separator, `--turning-stub` is consumed by `simctl` itself and never reaches the app. Confirm via console log:

```
[TurningStub] turningForToday() will return winter-solstice (...)
```

If you don't see that log, the launch arg didn't reach the app — re-run with the `--` separator.

Switch to Constellation. Confirm `turningIndigo` accent on the home turning banner is visible against `#0a0a12`. If invisible, file 1.6.1 follow-up issue ("ship Constellation-specific lighter twin for `turningIndigo`").

- [ ] **Step 10: Edit My Journey end-to-end**

In Constellation mode (and again in Light): Settings → Data → Edit My Journey. Confirm:
- a. `edit.pilgrimapp.org` loads (no stuck spinner)
- b. Walks render in the editor (count matches in-app walk count)
- c. Edit a single field (e.g. notes); the edit is reflected in the editor's UI
- d. Export the edited file from the editor (download as `.pilgrim`)
- e. Re-import the file via Settings → Data → Import Data; the edited field shows in-app

- [ ] **Step 11: Edit My Journey offline behaviour**

Toggle device airplane mode. Tap Edit My Journey. Confirm same error fallback as JourneyViewerView (exclamationmark.triangle + message). Disable airplane mode; re-enter; loads normally.

- [ ] **Step 11a: Live Activity sanity check**

Pilgrim's Live Activity (lock-screen + Dynamic Island walk stats) is rendered by `PilgrimWidget` extension via ActivityKit — a separate process from the main app. Constellation overlay does **not** apply there (the widget extension has no access to `AppearanceManager`). Start an active walk in Constellation mode and confirm on a physical device:
- Lock screen Live Activity renders normally (no missing background, no broken layout)
- Dynamic Island compact + expanded states render normally
- No visual regression vs. running the same walk in Dark mode

If a regression is observed, the cause is in the widget extension, not in the new overlay code — file as a separate issue.

- [ ] **Step 12: VoiceOver pass on AppearanceView**

Settings → Accessibility → VoiceOver ON. Navigate to Settings → Atmosphere → Appearance. Swipe through the four rows. Confirm:
- Each row reads label + description as one continuous utterance
- The active row announces "checkmark, selected"
- The overlay (when Constellation active) is silent — VoiceOver does not announce stars

Toggle VoiceOver OFF.

- [ ] **Step 13: Document QA results**

Append a brief QA log to `docs/superpowers/specs/2026-05-07-constellation-mode-and-edit-link-design.md` under a new `## 13. QA results` section. Note any deviations from acceptance criteria as 1.6.1 follow-ups.

- [ ] **Step 14: Commit QA log**

```bash
git add docs/superpowers/specs/2026-05-07-constellation-mode-and-edit-link-design.md
git commit -m "docs(constellation): record 1.6.0 QA pass results"
```

---

### Task 12: Version bump + final commit

**Files:**
- Modify: `Pilgrim/Support Files/Info.plist` (`CFBundleShortVersionString`) and build number

- [ ] **Step 1: Bump version to 1.6.0 + build number**

Use the project's release script:

```bash
scripts/release.sh check
```

Read the current version. If not yet `1.6.0`, edit `Info.plist` (or set via `xcodebuild -setVersion`). Then:

```bash
scripts/release.sh bump
```

This increments the build number per existing convention.

- [ ] **Step 2: Verify build still succeeds at new version**

```bash
xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run full unit test suite**

```bash
xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add Pilgrim/Support\ Files/Info.plist
git commit -m "chore(release): bump to 1.6.0 (Constellation + Edit My Journey)"
```

- [ ] **Step 5: Push branch**

```bash
git push -u origin feat/constellation-mode-and-edit-link
```

- [ ] **Step 6: Open PR — DO NOT auto-create on TestFlight**

Create the PR manually (or via `gh pr create`); per `feedback_testflight_approval.md`, **do not run `gh workflow run testflight.yml` until the user explicitly approves**.

PR template body suggestion:

```
## Summary
- Adds Constellation appearance mode (4th option, app-wide indigo + sparse animated stars)
- Adds Edit My Journey row in Settings → Data, opening edit.pilgrimapp.org
- Spec: docs/superpowers/specs/2026-05-07-constellation-mode-and-edit-link-design.md
- Plan: docs/superpowers/plans/2026-05-07-constellation-mode-and-edit-link.md

## Test plan
- [x] Unit tests (AppearanceMode, AppearanceManager, ConstellationStarGeneration)
- [x] Manual visual QA on iPhone SE3 + 17 Pro simulators
- [x] Reduce Motion / Reduce Transparency / VoiceOver passes
- [x] 30-min meditation device test (battery + memory)
- [x] 60–90-min active walk device test (battery + memory + frame rate)
- [x] Instruments Energy Log background-pause check
- [x] Winter solstice turning visibility check
- [x] Edit My Journey end-to-end on device (load → edit → export → re-import)
- [x] Edit My Journey offline failure path

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

---

## Self-Review

### Spec coverage

| Spec section | Plan task |
|---|---|
| §3 acceptance: Constellation selection persists | Tasks 1, 2, 6 |
| §3: indigo bg + stars on every screen | Tasks 8, 9 |
| §3: 1–12 random stars | Task 8 (`generateStars`) + test |
| §3: shooting star 30–90 s | Task 8 (`nextShootingAt`) |
| §3: Reduce Motion freeze at 0.6 | Task 8 (`staticView`, `staticOpacity` test) |
| §3: Reduce Transparency suppresses overlay | Task 8 (`reduceTransparency` branch) |
| §3: `.allowsHitTesting(false)`, `.accessibilityHidden(true)` | Task 8 modifiers |
| §3: clean teardown on mode switch | Task 9 (conditional ZStack), Task 8 (TimelineView lifecycle) |
| §3: WCAG 2.3.1 design intent | Task 8 (`twinkleFrequencyHz` test asserts ≤ 1 Hz) |
| §3: TimelineView pause on background | Task 11 step 8 (Instruments) |
| §3: Edit row + footer + Config-driven URL | Tasks 3, 4, 5 |
| §3: Edit acceptance enumerated steps | Task 11 step 10 |
| §3: Offline / WKWebView failure path | Task 4 (Coordinator delegate methods) + Task 11 step 11 |
| §3: AtmosphereCard regression criterion | Task 7 step 3 manual smoke |
| §4.2 AppearanceManager extension | Task 2 |
| §4.2 Config.Web | Task 3 |
| §4.2 ConstellationOverlay | Task 8 |
| §4.2 AppearanceView | Task 6 |
| §4.2 JourneyEditorView | Task 4 |
| §4.3 Root ZStack ordering | Task 9 |
| §4.5 DataSettings sibling row | Task 5 |
| §6 Accessibility | Task 8 + Task 11 steps 3–4, 12 |
| §8 Manual QA | Task 11 (all steps) |
| §9 Localization en + ship gate | Task 10 |
| §11 Open items 1–6 | Tasks 4 (JS bridge), 5 (smoke), 11 (visual QA), 12 (final verification gate) |
| §12 Release plan | Task 12 |

All spec sections mapped to at least one task. Open dependencies that the plan defers to verification rather than fully resolving:

- **JS-bridge name** for edit.pilgrimapp.org (Task 4 inline note + spec §11.1) — not knowable until verified live; Task 5 step 3 smoke check will surface a mismatch
- **Asset-catalog dark variants** legibility on `#0a0a12` (spec §11.4) — only confirmable via Task 11 step 1–2 visual QA
- **`turningIndigo` accent contrast** against `#0a0a12` (spec §11.4) — Task 11 step 9 confirms

These are verification-gated, not unspecified.

### Placeholder scan

No "TBD", "TODO", "implement later", "fill in details", or unspecified-error-handling instructions in any task body. Every step has either runnable code or a runnable command. Pass.

### Type consistency

- `AppearanceMode.constellation` — used in Tasks 1, 2 consistently
- `AppearanceManager.isConstellation` — set in Task 2, read in Task 9
- `ConstellationOverlay` — defined in Task 8, instantiated in Task 9
- `ConstellationOverlay.generateStars(canvasSize:)` — called from test (Task 8 step 1) and from view body (Task 8 step 3); signature matches
- `ConstellationOverlay.staticOpacity` — referenced in test (Task 8 step 1) and in view body (Task 8 step 3)
- `Star.twinkleFrequencyHz` — populated in `generateStars` (Task 8 step 3), asserted in test (Task 8 step 1)
- `Config.Web.viewer` / `Config.Web.editor` — defined in Task 3, used in Tasks 3 step 2 (existing viewer) and Task 4 (editor)
- `JourneyEditorView` / `JourneyEditorWebView` — defined in Task 4, instantiated in Task 5
- `AppearanceView` — defined in Task 6, NavigationLink target in Task 7

All names consistent across tasks.
