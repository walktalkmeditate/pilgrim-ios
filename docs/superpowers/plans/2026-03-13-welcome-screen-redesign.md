# Welcome Screen Redesign Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Pilgrim onboarding with a two-screen cinematic journey — The Threshold (animated welcome) and Preparing for the Journey (consolidated permissions) — connected by a breath transition into the app.

**Architecture:** The setup flow is controlled by `SetupCoordinatorView`, which currently routes between `WelcomeView` and `SetupView`. We replace this with a three-phase enum (`.threshold`, `.permissions`, `.breathTransition`) managed by a rewritten `SetupCoordinatorView`. Each phase is its own View with its own animation state. The breath transition sets `UserPreferences.isSetUp.value = true`, which triggers `RootCoordinatorViewModel` to switch to `.main`.

**Tech Stack:** SwiftUI, Combine, UIKit haptics (`UIImpactFeedbackGenerator`), `PermissionManager` (existing singleton), `UserPreferences` (existing), `UIAccessibility.isReduceMotionEnabled`

**Xcode project note:** This is a CocoaPods project — Xcode does not auto-discover source files. Every new `.swift` file must be added to the Xcode project (`Pilgrim.xcodeproj/project.pbxproj`) and every deleted file must be removed from it. When creating files, add them to the `Pilgrim` target. When creating test files, add them to the `UnitTests` target. The implementer should use `ruby` with the `xcodeproj` gem, or manually add via Xcode, or use PBXProjHelper to splice entries.

**Build:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build`

**Test:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`

**Spec:** `docs/superpowers/specs/2026-03-13-welcome-screen-redesign.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `Pilgrim/Views/FootprintShape.swift` | Create | Custom SwiftUI `Shape` — two angled ovals representing a footprint pair |
| `Pilgrim/Scenes/Setup/Welcome/WelcomeAnimationState.swift` | Create | `ObservableObject` managing the choreographed entrance/exit timeline |
| `Pilgrim/Scenes/Setup/Welcome/WelcomeView.swift` | Rewrite | The Threshold screen — logo, quote, footprints, Begin button |
| `Pilgrim/Scenes/Setup/Welcome/WelcomeViewModel.swift` | Rewrite | Quote pool, Begin action callback |
| `Pilgrim/Views/PilgrimLogoView.swift` | Modify | Add `breathing` parameter for continuous scale animation |
| `Pilgrim/Scenes/Setup/Permissions/PermissionsView.swift` | Create | Consolidated "Preparing for the Journey" screen with 3 permission cards |
| `Pilgrim/Scenes/Setup/Permissions/PermissionsViewModel.swift` | Create | Permission state tracking, grant flow, auto-transition trigger |
| `Pilgrim/Scenes/Setup/BreathTransitionView.swift` | Create | The inhale/peak/exhale crossing animation |
| `Pilgrim/Scenes/Setup/SetupCoordinatorView.swift` | Rewrite | Three-phase flow: threshold → permissions → breath → app |
| `Pilgrim/Support Files/Base.lproj/Localizable.strings` | Modify | Add new localization keys for quotes, permission titles, etc. |
| `UnitTests/WelcomeViewModelTests.swift` | Create | Tests for quote pool and view model logic |
| `UnitTests/PermissionsViewModelTests.swift` | Create | Tests for permission state, auto-transition gating |

**Files to delete** (after all tasks complete):
- `Pilgrim/Scenes/Setup/SetupCoordinatorViewModel.swift`
- `Pilgrim/Scenes/Setup/SetupView.swift`
- `Pilgrim/Scenes/Setup/SetupViewModel.swift`
- `Pilgrim/Scenes/Setup/Steps/SetupPermissionsView.swift`
- `Pilgrim/Scenes/Setup/Steps/SetupStepBaseView.swift`
- `Pilgrim/Scenes/Setup/Steps/SetupFormalitiesView.swift`
- `Pilgrim/Scenes/Setup/Steps/SetupUserInfoView.swift`

---

## Chunk 1: Foundation Components

### Task 1: FootprintShape

**Files:**
- Create: `Pilgrim/Views/FootprintShape.swift`

- [ ] **Step 1: Create FootprintShape**

A single footprint pair — two angled ovals (left foot, right foot), wabi-sabi imperfect.

```swift
import SwiftUI

struct FootprintShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Left foot — slightly rotated oval, offset left
        let leftCenter = CGPoint(x: w * 0.35, y: h * 0.5)
        let ovalW: CGFloat = w * 0.22
        let ovalH: CGFloat = h * 0.7
        path.addEllipse(in: CGRect(
            x: leftCenter.x - ovalW / 2,
            y: leftCenter.y - ovalH / 2,
            width: ovalW,
            height: ovalH
        ))

        // Right foot — slightly rotated oval, offset right
        let rightCenter = CGPoint(x: w * 0.65, y: h * 0.5)
        path.addEllipse(in: CGRect(
            x: rightCenter.x - ovalW / 2,
            y: rightCenter.y - ovalH / 2,
            width: ovalW,
            height: ovalH
        ))

        return path
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Pilgrim/Views/FootprintShape.swift
git commit -m "feat: add FootprintShape for onboarding footprint animation"
```

---

### Task 2: PilgrimLogoView Breathing Mode

**Files:**
- Modify: `Pilgrim/Views/PilgrimLogoView.swift`

- [ ] **Step 1: Add breathing parameter**

Add a `breathing` parameter that enables a continuous scale oscillation (1.0 → 1.02 → 1.0 over 8s). The existing `animated` fade-in behavior stays untouched.

```swift
import SwiftUI

struct PilgrimLogoView: View {

    var size: CGFloat = 80
    var color: Color = .stone
    var animated: Bool = false
    @Binding var breathing: Bool

    @State private var appeared = false
    @State private var breathScale: CGFloat = 1.0

    var body: some View {
        Image("pilgrimLogo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
            .scaleEffect(breathScale)
            .opacity(animated && !appeared ? 0 : 1)
            .onAppear {
                if animated {
                    withAnimation(.easeInOut(duration: 1.0)) {
                        appeared = true
                    }
                }
            }
            .onChange(of: breathing) { isBreathing in
                if isBreathing {
                    startBreathing()
                } else {
                    withAnimation(.easeInOut(duration: Constants.UI.Motion.gentle)) {
                        breathScale = 1.0
                    }
                }
            }
    }

    init(size: CGFloat = 80, color: Color = .stone, animated: Bool = false, breathing: Binding<Bool> = .constant(false)) {
        self.size = size
        self.color = color
        self.animated = animated
        self._breathing = breathing
    }

    private func startBreathing() {
        withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
            breathScale = 1.02
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Pilgrim/Views/PilgrimLogoView.swift
git commit -m "feat: add breathing animation mode to PilgrimLogoView"
```

---

### Task 3: WelcomeViewModel with Quote Pool

**Files:**
- Rewrite: `Pilgrim/Scenes/Setup/Welcome/WelcomeViewModel.swift`
- Create: `UnitTests/WelcomeViewModelTests.swift`

- [ ] **Step 1: Write tests for WelcomeViewModel**

```swift
import XCTest
@testable import Pilgrim

final class WelcomeViewModelTests: XCTestCase {

    func testQuotePool_isNotEmpty() {
        let vm = WelcomeViewModel {}
        XCTAssertFalse(vm.quotePool.isEmpty)
    }

    func testCurrentQuote_isFromPool() {
        let vm = WelcomeViewModel {}
        XCTAssertTrue(vm.quotePool.contains(vm.currentQuote))
    }

    func testBeginAction_callsClosure() {
        var called = false
        let vm = WelcomeViewModel { called = true }
        vm.beginAction()
        XCTAssertTrue(called)
    }
}
```

- [ ] **Step 2: Run tests — expect failure**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: FAIL (WelcomeViewModel API doesn't match yet)

- [ ] **Step 3: Rewrite WelcomeViewModel**

Replace the entire contents of `WelcomeViewModel.swift`:

```swift
import Foundation

class WelcomeViewModel: ObservableObject {

    static let quotePool = [
        "Every journey begins\nwith a single step",
        "The path is made\nby walking",
        "Not all who wander\nare lost",
        "Solvitur ambulando —\nit is solved by walking",
        "Walk as if you are kissing\nthe earth with your feet",
        "The journey of a thousand miles\nbegins beneath your feet"
    ]

    let currentQuote: String
    private let onBegin: () -> Void

    init(beginAction: @escaping () -> Void) {
        self.currentQuote = Self.quotePool.randomElement() ?? Self.quotePool[0]
        self.onBegin = beginAction
    }

    func beginAction() {
        onBegin()
    }
}
```

Update tests to use `WelcomeViewModel.quotePool` (static):
```swift
func testQuotePool_isNotEmpty() {
    XCTAssertFalse(WelcomeViewModel.quotePool.isEmpty)
}

func testCurrentQuote_isFromPool() {
    let vm = WelcomeViewModel {}
    XCTAssertTrue(WelcomeViewModel.quotePool.contains(vm.currentQuote))
}
```

- [ ] **Step 4: Run tests — expect pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Scenes/Setup/Welcome/WelcomeViewModel.swift UnitTests/WelcomeViewModelTests.swift
git commit -m "feat: rewrite WelcomeViewModel with rotating quote pool"
```

---

### Task 4: WelcomeAnimationState

**Files:**
- Create: `Pilgrim/Scenes/Setup/Welcome/WelcomeAnimationState.swift`

This `ObservableObject` drives the choreographed entrance and exit timeline. Each `@Published` property is a flag that SwiftUI views observe to show/hide elements.

**Implementation notes:**
- Use `[weak self]` in all `DispatchQueue.main.asyncAfter` closures to avoid retaining a deallocated object if the view is dismissed mid-animation.
- `@StateObject` in the parent view owns this object's lifecycle.

- [ ] **Step 1: Create WelcomeAnimationState**

```swift
import SwiftUI

class WelcomeAnimationState: ObservableObject {

    @Published var showLogo = false
    @Published var isBreathing = false
    @Published var showQuote = false
    @Published var footprintOpacities: [Double] = [0, 0, 0]
    @Published var showButton = false
    @Published var showAmbient = false
    @Published var isExiting = false

    private let reduceMotion = UIAccessibility.isReduceMotionEnabled

    func runEntrance() {
        if reduceMotion {
            showLogo = true
            isBreathing = false
            showQuote = true
            footprintOpacities = [1, 1, 1]
            showButton = true
            showAmbient = true
            return
        }

        // 0.5s — Logo fades in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 1.5)) { self.showLogo = true }
        }

        // 2.0s — Breathing starts
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.isBreathing = true
        }

        // 2.5s — Quote fades in
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: Constants.UI.Motion.gentle)) { self.showQuote = true }
        }

        // 3.5s, 4.2s, 4.9s — Footprints one by one
        let footprintTimes: [Double] = [3.5, 4.2, 4.9]
        for (index, time) in footprintTimes.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + time) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeInOut(duration: Constants.UI.Motion.appear)) {
                    self.footprintOpacities[index] = 1.0
                }
            }
            // Fade to ghost after appearing (except last holds longer)
            let fadeDelay = index == 2 ? 1.5 : 0.8
            DispatchQueue.main.asyncAfter(deadline: .now() + time + fadeDelay) {
                withAnimation(.easeOut(duration: 1.0)) {
                    self.footprintOpacities[index] = 0.15
                }
            }
        }

        // 5.5s — Button slides up
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.easeOut(duration: Constants.UI.Motion.gentle)) { self.showButton = true }
        }

        // 6.0s — Ambient starts
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            withAnimation(.easeIn(duration: 2.0)) { self.showAmbient = true }
        }
    }

    func runExit(completion: @escaping () -> Void) {
        isExiting = true

        if reduceMotion {
            showLogo = false
            showQuote = false
            footprintOpacities = [0, 0, 0]
            showButton = false
            showAmbient = false
            isBreathing = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { completion() }
            return
        }

        // Stop breathing
        isBreathing = false

        // Button slides down
        withAnimation(.easeIn(duration: 0.3)) { showButton = false }

        // Footprints fade
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeIn(duration: 0.3)) { self.footprintOpacities = [0, 0, 0] }
        }

        // Quote fades
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeIn(duration: 0.3)) { self.showQuote = false }
        }

        // Logo fades + scales down
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeIn(duration: 0.5)) { self.showLogo = false }
        }

        // Complete after total exit animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { completion() }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Pilgrim/Scenes/Setup/Welcome/WelcomeAnimationState.swift
git commit -m "feat: add WelcomeAnimationState choreography controller"
```

---

## Chunk 2: The Threshold Screen

### Task 5: WelcomeView — The Threshold

**Files:**
- Rewrite: `Pilgrim/Scenes/Setup/Welcome/WelcomeView.swift`

- [ ] **Step 1: Rewrite WelcomeView**

Replace the entire contents of `WelcomeView.swift`. This builds the full Threshold screen using all foundation components from Tasks 1-4.

```swift
import SwiftUI

struct WelcomeView: View {

    @ObservedObject var viewModel: WelcomeViewModel
    @StateObject private var animation = WelcomeAnimationState()
    @State private var ambientOffset: CGSize = .zero

    var body: some View {
        ZStack {
            background
            content
        }
        .onAppear { animation.runEntrance() }
    }

    private var background: some View {
        ZStack {
            Color.parchment
            // Warm golden overlay (subliminal)
            Color.yellow.opacity(0.02)
            // Ambient drifting gradient
            if animation.showAmbient && !UIAccessibility.isReduceMotionEnabled {
                RadialGradient(
                    colors: [Color.yellow.opacity(0.03), Color.clear],
                    center: UnitPoint(
                        x: 0.5 + ambientOffset.width,
                        y: 0.5 + ambientOffset.height
                    ),
                    startRadius: 50,
                    endRadius: 300
                )
                .onAppear { startAmbientDrift() }
            }
        }
        .ignoresSafeArea()
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            PilgrimLogoView(size: 120, breathing: $animation.isBreathing)
                .opacity(animation.showLogo ? 1 : 0)
                .scaleEffect(animation.showLogo ? 1.0 : 0.85)
                .padding(.bottom, Constants.UI.Padding.big)

            // Quote
            Text(viewModel.currentQuote)
                .font(Constants.Typography.displayMedium)
                .foregroundColor(.fog)
                .multilineTextAlignment(.center)
                .opacity(animation.showQuote ? 1 : 0)

            Spacer()

            // Footprints
            footprintsView
                .padding(.bottom, Constants.UI.Padding.big)

            // Begin button
            Button(action: beginTapped) {
                Text("Begin")
                    .font(Constants.Typography.button)
                    .foregroundColor(.parchment)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.stone)
                    .cornerRadius(Constants.UI.CornerRadius.normal)
            }
            .accessibilityLabel("Begin your journey")
            .opacity(animation.showButton ? 1 : 0)
            .offset(y: animation.showButton ? 0 : 30)
            .disabled(animation.isExiting)
        }
        .padding(.horizontal, Constants.UI.Padding.big)
        .padding(.bottom, Constants.UI.Padding.normal)
    }

    private var footprintsView: some View {
        VStack(spacing: Constants.UI.Padding.normal) {
            ForEach(0..<3, id: \.self) { index in
                FootprintShape()
                    .fill(Color.fog)
                    .frame(width: 30, height: 20)
                    .opacity(animation.footprintOpacities[index])
                    .offset(x: index % 2 == 0 ? -4 : 4)
                    .accessibilityHidden(true)
            }
        }
    }

    private func beginTapped() {
        guard !animation.isExiting else { return }
        animation.runExit {
            viewModel.beginAction()
        }
    }

    private func startAmbientDrift() {
        withAnimation(
            .easeInOut(duration: 15)
            .repeatForever(autoreverses: true)
        ) {
            ambientOffset = CGSize(width: 0.15, height: 0.1)
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build`

Note: The old `SetupCoordinatorViewModel` creates `WelcomeViewModel(setupButtonAction:)`. To keep intermediate commits compiling, add a backward-compatible convenience init to `WelcomeViewModel`:

```swift
convenience init(setupButtonAction: @escaping () -> Void) {
    self.init(beginAction: setupButtonAction)
}
```

This will be removed in Task 9 when we delete `SetupCoordinatorViewModel`. Every commit must compile.

- [ ] **Step 3: Commit**

```bash
git add Pilgrim/Scenes/Setup/Welcome/WelcomeView.swift
git commit -m "feat: rebuild WelcomeView as The Threshold with choreographed animation"
```

---

## Chunk 3: Permissions Screen

### Task 6: PermissionsViewModel

**Files:**
- Create: `Pilgrim/Scenes/Setup/Permissions/PermissionsViewModel.swift`
- Create: `UnitTests/PermissionsViewModelTests.swift`

- [ ] **Step 1: Write tests for PermissionsViewModel**

```swift
import XCTest
@testable import Pilgrim

final class PermissionsViewModelTests: XCTestCase {

    func testInitialState_noPermissionsGranted() {
        let vm = PermissionsViewModel(permissionManager: nil, onComplete: {})
        XCTAssertFalse(vm.locationGranted)
        XCTAssertFalse(vm.microphoneGranted)
        XCTAssertFalse(vm.motionGranted)
    }

    func testCanTransition_requiresLocationAndMicrophone() {
        let vm = PermissionsViewModel(permissionManager: nil, onComplete: {})
        XCTAssertFalse(vm.canTransition)

        vm.locationGranted = true
        XCTAssertFalse(vm.canTransition)

        vm.microphoneGranted = true
        XCTAssertTrue(vm.canTransition)
    }

    func testCanTransition_doesNotRequireMotion() {
        let vm = PermissionsViewModel(permissionManager: nil, onComplete: {})
        vm.locationGranted = true
        vm.microphoneGranted = true
        XCTAssertTrue(vm.canTransition)
        // Motion still false — doesn't block transition
    }

    func testOnComplete_calledWhenCanTransitionBecomesTrue() {
        var completeCalled = false
        let vm = PermissionsViewModel(permissionManager: nil, onComplete: { completeCalled = true })
        vm.locationGranted = true
        vm.microphoneGranted = true
        // Give async transition delay time to fire
        let expectation = expectation(description: "onComplete called")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if completeCalled { expectation.fulfill() }
        }
        waitForExpectations(timeout: 3)
    }

    func testLocationDenied_setsLocationDeniedFlag() {
        let vm = PermissionsViewModel(permissionManager: nil, onComplete: {})
        vm.handleLocationDenied()
        XCTAssertTrue(vm.locationDenied)
    }

    func testMicrophoneDenied_setsMicrophoneDeniedFlag() {
        let vm = PermissionsViewModel(permissionManager: nil, onComplete: {})
        vm.handleMicrophoneDenied()
        XCTAssertTrue(vm.microphoneDenied)
    }
}
```

- [ ] **Step 2: Run tests — expect failure**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: FAIL (PermissionsViewModel doesn't exist yet)

- [ ] **Step 3: Create PermissionsViewModel**

```swift
import SwiftUI
import Combine

class PermissionsViewModel: ObservableObject {

    @Published var locationGranted = false
    @Published var microphoneGranted = false
    @Published var motionGranted = false
    @Published var locationDenied = false
    @Published var microphoneDenied = false
    @Published var motionDecided = false
    @Published var shakeLocationCard = false
    @Published var shakeMicrophoneCard = false

    var canTransition: Bool { locationGranted && microphoneGranted }

    private let permissionManager: PermissionManager?
    private let onComplete: () -> Void
    private var cancellables = Set<AnyCancellable>()
    private var transitionFired = false

    init(permissionManager: PermissionManager?, onComplete: @escaping () -> Void) {
        self.permissionManager = permissionManager
        self.onComplete = onComplete

        $locationGranted.combineLatest($microphoneGranted)
            .map { $0 && $1 }
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in self?.triggerTransition() }
            .store(in: &cancellables)
    }

    func checkExistingPermissions() {
        guard let pm = permissionManager else { return }
        locationGranted = pm.currentLocationStatus == .granted
        microphoneGranted = pm.isMicrophoneGranted
        motionGranted = pm.isMotionGranted
        if motionGranted { motionDecided = true }
    }

    func requestLocation() {
        permissionManager?.checkLocationPermission { [weak self] status in
            guard let self else { return }
            if status == .granted {
                self.locationGranted = true
                self.locationDenied = false
            } else {
                self.handleLocationDenied()
            }
        }
    }

    func requestMicrophone() {
        permissionManager?.checkMicrophonePermission { [weak self] granted in
            guard let self else { return }
            if granted {
                self.microphoneGranted = true
                self.microphoneDenied = false
            } else {
                self.handleMicrophoneDenied()
            }
        }
    }

    func requestMotion() {
        motionDecided = true
        permissionManager?.checkMotionPermission { [weak self] granted in
            self?.motionGranted = granted
        }
    }

    func handleLocationDenied() {
        locationDenied = true
        shakeLocationCard = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.shakeLocationCard = false
        }
    }

    func handleMicrophoneDenied() {
        microphoneDenied = true
        shakeMicrophoneCard = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.shakeMicrophoneCard = false
        }
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func triggerTransition() {
        guard !transitionFired else { return }
        transitionFired = true
        // Motion is skipped by omission when auto-transition fires
        motionDecided = true
        // 0.8s stillness before the crossing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.onComplete()
        }
    }
}
```

- [ ] **Step 4: Create Permissions directory**

```bash
mkdir -p Pilgrim/Scenes/Setup/Permissions
```

- [ ] **Step 5: Run tests — expect pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Pilgrim/Scenes/Setup/Permissions/PermissionsViewModel.swift UnitTests/PermissionsViewModelTests.swift
git commit -m "feat: add PermissionsViewModel with auto-transition gating"
```

---

### Task 7: PermissionsView

**Files:**
- Create: `Pilgrim/Scenes/Setup/Permissions/PermissionsView.swift`

- [ ] **Step 1: Create PermissionsView**

```swift
import SwiftUI

struct PermissionsView: View {

    @ObservedObject var viewModel: PermissionsViewModel
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("Prepare for the journey")
                .font(Constants.Typography.displayMedium)
                .foregroundColor(.stone)
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1 : 0)

            Text("Pilgrim walks best with these")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
                .padding(.top, Constants.UI.Padding.small)
                .opacity(appeared ? 1 : 0)

            VStack(spacing: Constants.UI.Padding.normal) {
                permissionCard(
                    icon: "location.fill",
                    title: "To walk with you",
                    description: "Track your route, distance, and pace",
                    granted: viewModel.locationGranted,
                    denied: viewModel.locationDenied,
                    shake: viewModel.shakeLocationCard,
                    required: true,
                    action: viewModel.requestLocation,
                    retryAction: viewModel.openSettings
                )

                permissionCard(
                    icon: "mic.fill",
                    title: "To hear your thoughts",
                    description: "Capture voice reflections along the way",
                    granted: viewModel.microphoneGranted,
                    denied: viewModel.microphoneDenied,
                    shake: viewModel.shakeMicrophoneCard,
                    required: true,
                    action: viewModel.requestMicrophone,
                    retryAction: viewModel.openSettings
                )

                permissionCard(
                    icon: "figure.walk",
                    title: "To count your steps",
                    description: "Measure steps as you move",
                    granted: viewModel.motionGranted,
                    denied: false,
                    shake: false,
                    required: false,
                    action: viewModel.requestMotion,
                    retryAction: nil
                )
            }
            .padding(.top, Constants.UI.Padding.big)
            .opacity(appeared ? 1 : 0)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, Constants.UI.Padding.big)
        .background(warmParchment)
        .onAppear {
            viewModel.checkExistingPermissions()
            withAnimation(.easeInOut(duration: Constants.UI.Motion.gentle)) {
                appeared = true
            }
        }
    }

    private var warmParchment: some View {
        ZStack {
            Color.parchment
            Color.yellow.opacity(0.02)
        }
        .ignoresSafeArea()
    }

    private func permissionCard(
        icon: String,
        title: String,
        description: String,
        granted: Bool,
        denied: Bool,
        shake: Bool,
        required: Bool,
        action: @escaping () -> Void,
        retryAction: (() -> Void)?
    ) -> some View {
        VStack(spacing: Constants.UI.Padding.small) {
            HStack(spacing: Constants.UI.Padding.normal) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.stone)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Constants.UI.Padding.small) {
                        Text(title)
                            .font(Constants.Typography.heading)
                            .foregroundColor(.ink)
                        if !required {
                            Text("(optional)")
                                .font(Constants.Typography.caption)
                                .foregroundColor(.fog)
                        }
                    }
                    Text(description)
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }

                Spacer()

                grantButton(
                    granted: granted,
                    denied: denied,
                    required: required,
                    decided: !required && viewModel.motionDecided,
                    action: denied && retryAction != nil ? retryAction! : action
                )
            }
            .padding(Constants.UI.Padding.normal)
            .background(granted ? Color.moss.opacity(0.1) : Color.parchmentSecondary)
            .cornerRadius(Constants.UI.CornerRadius.normal)
            .offset(x: shake ? -6 : 0)
            .animation(
                shake
                    ? .default.repeatCount(3, autoreverses: true).speed(6)
                    : .default,
                value: shake
            )

            if denied && required {
                Text("Pilgrim needs this to walk with you")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func grantButton(
        granted: Bool,
        denied: Bool,
        required: Bool,
        decided: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if granted {
            Image(systemName: "checkmark")
                .foregroundColor(.moss)
                .font(.subheadline.bold())
        } else if !required && decided {
            Text("Skipped")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
        } else {
            Button(action: action) {
                Text(denied ? "Settings" : "Grant")
                    .font(.subheadline.bold())
                    .foregroundColor(.stone)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 14)
                    .overlay(
                        Capsule()
                            .stroke(Color.stone, lineWidth: 1.5)
                    )
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build`
Expected: BUILD SUCCEEDED (or minor issues from coordinator — that's Task 8)

- [ ] **Step 3: Commit**

```bash
git add Pilgrim/Scenes/Setup/Permissions/PermissionsView.swift
git commit -m "feat: add PermissionsView — consolidated journey preparation screen"
```

---

## Chunk 4: Breath Transition + Coordinator Integration

### Task 8: BreathTransitionView

**Files:**
- Create: `Pilgrim/Scenes/Setup/BreathTransitionView.swift`

- [ ] **Step 1: Create BreathTransitionView**

```swift
import SwiftUI

struct BreathTransitionView: View {

    let onComplete: () -> Void

    @State private var screenScale: CGFloat = 1.0
    @State private var contentOpacity: Double = 1.0
    @State private var footprintOpacity: Double = 0
    @State private var warmthOpacity: Double = 0.02
    @State private var mainContentOpacity: Double = 0
    @State private var mainContentOffset: CGFloat = 3

    private let reduceMotion = UIAccessibility.isReduceMotionEnabled

    var body: some View {
        ZStack {
            // Background with warm-to-normal shift
            ZStack {
                Color.parchment
                Color.yellow.opacity(warmthOpacity)
            }
            .ignoresSafeArea()

            // Ghostly footprint at center
            FootprintShape()
                .fill(Color.fog)
                .frame(width: 30, height: 20)
                .opacity(footprintOpacity)

            // Placeholder for main app content settling
            Color.clear
                .opacity(mainContentOpacity)
                .offset(y: mainContentOffset)
        }
        .scaleEffect(screenScale)
        .onAppear { runTransition() }
    }

    private func runTransition() {
        if reduceMotion {
            warmthOpacity = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { onComplete() }
            return
        }

        // Stillness: 0.8s — already elapsed (triggered by PermissionsViewModel delay)

        // Inhale: scale up, content dissolves, footprint appears
        withAnimation(.easeInOut(duration: Constants.UI.Motion.breath)) {
            screenScale = 1.015
            contentOpacity = 0
            footprintOpacity = 0.3
        }

        // Peak: haptic pulse, hold
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.UI.Motion.breath) {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }

        // Exhale: scale back, footprint fades, warmth fades, main content appears
        let exhaleStart = Constants.UI.Motion.breath + 0.3
        DispatchQueue.main.asyncAfter(deadline: .now() + exhaleStart) {
            withAnimation(.easeInOut(duration: Constants.UI.Motion.breath)) {
                self.screenScale = 1.0
                self.footprintOpacity = 0
                self.warmthOpacity = 0
                self.mainContentOpacity = 1
            }
        }

        // Settle: main content drifts up to final position
        let settleStart = exhaleStart + Constants.UI.Motion.breath
        DispatchQueue.main.asyncAfter(deadline: .now() + settleStart) {
            withAnimation(.easeOut(duration: Constants.UI.Motion.gentle)) {
                self.mainContentOffset = 0
            }
        }

        // Complete: trigger root state change
        let completeTime = settleStart + Constants.UI.Motion.gentle
        DispatchQueue.main.asyncAfter(deadline: .now() + completeTime) {
            self.onComplete()
        }
    }

}
```

- [ ] **Step 2: Build to verify**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Pilgrim/Scenes/Setup/BreathTransitionView.swift
git commit -m "feat: add BreathTransitionView — cinematic onboarding crossing"
```

---

### Task 9: Rewrite SetupCoordinatorView + Delete Old Files

**Files:**
- Rewrite: `Pilgrim/Scenes/Setup/SetupCoordinatorView.swift`
- Delete: `Pilgrim/Scenes/Setup/SetupCoordinatorViewModel.swift`
- Delete: `Pilgrim/Scenes/Setup/SetupView.swift`
- Delete: `Pilgrim/Scenes/Setup/SetupViewModel.swift`
- Delete: `Pilgrim/Scenes/Setup/Steps/SetupPermissionsView.swift`
- Delete: `Pilgrim/Scenes/Setup/Steps/SetupStepBaseView.swift`
- Delete: `Pilgrim/Scenes/Setup/Steps/SetupFormalitiesView.swift`
- Delete: `Pilgrim/Scenes/Setup/Steps/SetupUserInfoView.swift`

- [ ] **Step 1: Rewrite SetupCoordinatorView**

This replaces both `SetupCoordinatorView` and `SetupCoordinatorViewModel` — the coordinator is now simple enough to manage its own state.

```swift
import SwiftUI

struct SetupCoordinatorView: View {

    enum Phase {
        case threshold
        case permissions
        case breathTransition
    }

    @State private var phase: Phase = .threshold

    var body: some View {
        ZStack {
            switch phase {
            case .threshold:
                WelcomeView(viewModel: WelcomeViewModel {
                    withAnimation(.easeInOut(duration: Constants.UI.Motion.gentle)) {
                        phase = .permissions
                    }
                })
                .transition(.opacity)

            case .permissions:
                PermissionsView(viewModel: PermissionsViewModel(
                    permissionManager: PermissionManager.standard,
                    onComplete: {
                        withAnimation(.easeInOut(duration: Constants.UI.Motion.appear)) {
                            phase = .breathTransition
                        }
                    }
                ))
                .transition(.opacity)

            case .breathTransition:
                BreathTransitionView {
                    UserPreferences.isSetUp.value = true
                }
                .transition(.opacity)
            }
        }
    }
}
```

- [ ] **Step 2: Update RootCoordinatorViewModel to remove SetupCoordinatorViewModel dependency**

In `Pilgrim/Scenes/Root/RootCoordinatorViewModel.swift`, remove the `setupCoordinatorViewModel` property (line 30) since `SetupCoordinatorView` no longer needs it.

In `Pilgrim/Scenes/Root/RootCoordinatorView.swift` line 17, change:
```swift
// Before:
SetupCoordinatorView(viewModel: viewModel.setupCoordinatorViewModel)
// After:
SetupCoordinatorView()
```

And in `RootCoordinatorViewModel.swift`, remove:
```swift
// Delete this line:
let setupCoordinatorViewModel = SetupCoordinatorViewModel()
```

- [ ] **Step 3: Delete old setup files**

```bash
git rm Pilgrim/Scenes/Setup/SetupCoordinatorViewModel.swift
git rm Pilgrim/Scenes/Setup/SetupView.swift
git rm Pilgrim/Scenes/Setup/SetupViewModel.swift
git rm Pilgrim/Scenes/Setup/Steps/SetupPermissionsView.swift
git rm Pilgrim/Scenes/Setup/Steps/SetupStepBaseView.swift
git rm Pilgrim/Scenes/Setup/Steps/SetupFormalitiesView.swift
git rm Pilgrim/Scenes/Setup/Steps/SetupUserInfoView.swift
```

- [ ] **Step 4: Build to verify full integration**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build`
Expected: BUILD SUCCEEDED — the entire flow now compiles: RootCoordinator → SetupCoordinator (threshold → permissions → breath) → main app

- [ ] **Step 5: Run all tests**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: ALL PASS — no existing tests should reference the deleted files

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: rewrite SetupCoordinatorView with three-phase flow, remove old setup screens"
```

---

## Chunk 5: Localization + Polish

### Task 10: Add Localization Keys

**Files:**
- Modify: `Pilgrim/Support Files/Base.lproj/Localizable.strings`

- [ ] **Step 1: Add new localization keys**

Add the following keys to the end of the Setup section in `Localizable.strings`:

```
// Welcome - The Threshold
"Welcome.Quote.1" = "Every journey begins\nwith a single step";
"Welcome.Quote.2" = "The path is made\nby walking";
"Welcome.Quote.3" = "Not all who wander\nare lost";
"Welcome.Quote.4" = "Solvitur ambulando —\nit is solved by walking";
"Welcome.Quote.5" = "Walk as if you are kissing\nthe earth with your feet";
"Welcome.Quote.6" = "The journey of a thousand miles\nbegins beneath your feet";
"Welcome.Begin" = "Begin";

// Permissions - Preparing for the Journey
"Permissions.Headline" = "Prepare for the journey";
"Permissions.Subtitle" = "Pilgrim walks best with these";
"Permissions.Location.Title" = "To walk with you";
"Permissions.Location.Description" = "Track your route, distance, and pace";
"Permissions.Microphone.Title" = "To hear your thoughts";
"Permissions.Microphone.Description" = "Capture voice reflections along the way";
"Permissions.Motion.Title" = "To count your steps";
"Permissions.Motion.Description" = "Measure steps as you move";
"Permissions.Motion.Optional" = "(optional)";
"Permissions.Grant" = "Grant";
"Permissions.Settings" = "Settings";
"Permissions.Skipped" = "Skipped";
"Permissions.Required.Hint" = "Pilgrim needs this to walk with you";
```

- [ ] **Step 2: Update WelcomeViewModel to use LS keys**

In `WelcomeViewModel.swift`, change the quote pool to use localization:

```swift
let quotePool = (1...6).map { LS["Welcome.Quote.\($0)"] }
```

And update the `currentQuote` initialization accordingly.

- [ ] **Step 3: Update PermissionsView to use LS keys**

Replace hardcoded strings in `PermissionsView.swift` with `LS["Permissions.Headline"]`, `LS["Permissions.Location.Title"]`, etc.

- [ ] **Step 4: Update WelcomeView Begin button text**

Replace `"Begin"` with `LS["Welcome.Begin"]`.

- [ ] **Step 5: Build and test**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: ALL PASS

- [ ] **Step 6: Commit**

```bash
git add Pilgrim/Support\ Files/Base.lproj/Localizable.strings Pilgrim/Scenes/Setup/Welcome/WelcomeViewModel.swift Pilgrim/Scenes/Setup/Welcome/WelcomeView.swift Pilgrim/Scenes/Setup/Permissions/PermissionsView.swift
git commit -m "feat: add localization keys for onboarding screens"
```

---

### Task 11: Final Build + Full Test Suite

- [ ] **Step 1: Clean build**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild clean build -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Run full test suite**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: ALL PASS

- [ ] **Step 3: Run SwiftLint**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /opt/homebrew/bin/swiftlint`
Expected: No new warnings in changed files

- [ ] **Step 4: Commit any lint fixes if needed**

```bash
git add -A
git commit -m "fix: address lint warnings in onboarding screens"
```
