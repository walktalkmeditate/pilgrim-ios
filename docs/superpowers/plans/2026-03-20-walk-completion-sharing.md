# Walk Completion Flow & Sharing UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add seal reveal animation at walk completion and a three-tier sharing UI (Seal / Etegami / Journey) to the walk summary.

**Architecture:** Insert a seal reveal overlay between walk dismissal and summary presentation in `MainCoordinator`. Replace the existing single "Share this walk" button in `WalkSummaryView` with a grouped layout showing Seal and Etegami (instant image share) above a divider, and Journey (existing web page share) below. The spatial separation communicates the privacy model (on-device vs. hosted URL).

**Tech Stack:** SwiftUI, UIKit (haptics), Combine

**Spec:** `docs/superpowers/specs/2026-03-19-seal-etegami-goshuin-design.md` (Sections 3 & 4)

**Depends on:** Seal Generation (complete), Etegami Generation (complete)

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `Pilgrim/Scenes/SealReveal/SealRevealView.swift` | Full-screen seal reveal with wax stamp animation |
| `Pilgrim/Views/WalkSharingButtons.swift` | Reusable three-tier sharing UI component |

### Modified Files
| File | Change |
|------|--------|
| `Pilgrim/Scenes/Root/MainCoordinatorView.swift` | Add `showSealReveal` state, insert reveal between walk dismiss and summary |
| `Pilgrim/Scenes/Root/MainTabView.swift` | Add seal reveal overlay presentation |
| `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift` | Replace share button with `WalkSharingButtons` |

---

## Task 1: Seal Reveal View

**Files:**
- Create: `Pilgrim/Scenes/SealReveal/SealRevealView.swift`

The seal presses into existence like a wax stamp. Tap the seal to share, tap elsewhere or wait ~2 seconds to dismiss.

- [ ] **Step 1: Write implementation**

```swift
import SwiftUI

struct SealRevealView: View {
    let walk: WalkInterface
    let onDismiss: () -> Void
    let onShareSeal: (UIImage) -> Void

    @State private var sealImage: UIImage?
    @State private var animationPhase: AnimationPhase = .hidden
    @State private var autoDismissTask: Task<Void, Never>?

    private enum AnimationPhase {
        case hidden, pressing, revealed
    }

    var body: some View {
        ZStack {
            Color.parchment.opacity(0.95)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            if let sealImage {
                Image(uiImage: sealImage)
                    .resizable()
                    .frame(width: 200, height: 200)
                    .scaleEffect(scaleForPhase)
                    .opacity(opacityForPhase)
                    .shadow(color: .black.opacity(shadowOpacity), radius: 10, y: 5)
                    .onTapGesture { shareSeal(sealImage) }
            }
        }
        .onAppear {
            generateAndAnimate()
        }
        .onDisappear {
            autoDismissTask?.cancel()
        }
    }

    private var scaleForPhase: CGFloat {
        switch animationPhase {
        case .hidden: return 1.2
        case .pressing: return 0.95
        case .revealed: return 1.0
        }
    }

    private var opacityForPhase: Double {
        switch animationPhase {
        case .hidden: return 0
        case .pressing, .revealed: return 1
        }
    }

    private var shadowOpacity: Double {
        animationPhase == .revealed ? 0.15 : 0
    }

    private func generateAndAnimate() {
        let image = SealGenerator.generate(for: walk, size: 512)
        sealImage = image

        withAnimation(.easeIn(duration: 0.2)) {
            animationPhase = .pressing
        }

        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.prepare()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            haptic.impactOccurred()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                animationPhase = .revealed
            }
        }

        autoDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    private func shareSeal(_ image: UIImage) {
        autoDismissTask?.cancel()
        onShareSeal(image)
    }

    private func dismiss() {
        autoDismissTask?.cancel()
        onDismiss()
    }
}
```

**Key design decisions:**
- `DispatchQueue.main.asyncAfter` for the haptic timing is a one-shot delay (not a timer), so no cleanup concern
- `Task.sleep` for auto-dismiss is cancelled in `onDisappear` and on manual dismiss
- The seal is generated synchronously on appear (cached after first walk completion)
- `.spring(response: 0.4, dampingFraction: 0.6)` gives the "stamp press" bounce feel

- [ ] **Step 2: Add to Xcode project**

Add `SealRevealView.swift` to the Pilgrim target. Create a `SealReveal` group under `Scenes/`.

- [ ] **Step 3: Build to verify**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build
```

- [ ] **Step 4: Commit**

```
feat: add SealRevealView with wax stamp press animation and haptic
```

---

## Task 2: Walk Sharing Buttons Component

**Files:**
- Create: `Pilgrim/Views/WalkSharingButtons.swift`

Reusable component showing Seal / Etegami above a divider, Journey below.

- [ ] **Step 1: Write implementation**

```swift
import SwiftUI

struct WalkSharingButtons: View {
    let walk: WalkInterface
    @State private var showJourneyShare = false

    var body: some View {
        if walk.routeData.count >= 2 {
            VStack(spacing: Constants.UI.Padding.normal) {
                HStack(spacing: Constants.UI.Padding.normal) {
                    shareButton(
                        icon: "seal",
                        label: LS["Seal"],
                        action: shareSeal
                    )
                    shareButton(
                        icon: "rectangle.portrait.on.rectangle.portrait",
                        label: LS["Etegami"],
                        action: shareEtegami
                    )
                }

                Divider()
                    .padding(.horizontal, Constants.UI.Padding.big)

                Button(action: { showJourneyShare = true }) {
                    VStack(spacing: Constants.UI.Padding.xs) {
                        Image(systemName: "link")
                            .font(Constants.Typography.body)
                        Text(LS["Share Journey"])
                            .font(Constants.Typography.caption)
                        Text("walk.pilgrimapp.org")
                            .font(.system(size: 9))
                            .tracking(2)
                            .foregroundStyle(Color.stone)
                            .opacity(0.6)
                    }
                    .foregroundStyle(Color.stone)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Constants.UI.Padding.small)
                }
            }
            .padding(Constants.UI.Padding.normal)
            .background(Color.parchmentSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .sheet(isPresented: $showJourneyShare) {
                WalkShareView(walk: walk)
            }
        }
    }

    private func shareButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Constants.UI.Padding.xs) {
                Image(systemName: icon)
                    .font(Constants.Typography.body)
                Text(label)
                    .font(Constants.Typography.caption)
            }
            .foregroundStyle(Color.stone)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Constants.UI.Padding.small)
        }
    }

    private func shareSeal() {
        let image = SealGenerator.generate(for: walk, size: 512)
        let activityVC = UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )
        presentShareSheet(activityVC)
    }

    private func shareEtegami() {
        let image = EtegamiGenerator.generate(for: walk)
        let activityVC = UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )
        presentShareSheet(activityVC)
    }

    private func presentShareSheet(_ controller: UIActivityViewController) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        var presenter = rootVC
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        controller.popoverPresentationController?.sourceView = presenter.view
        presenter.present(controller, animated: true)
    }
}
```

**IMPORTANT:** Before writing, check:
- How `LS` (localized strings) works — `LS["key"]` subscript pattern
- Whether `Constants.UI.Padding` and `Constants.Typography` are used with the exact syntax above
- Whether `Color.parchmentSecondary`, `Color.stone` exist as SwiftUI Color extensions
- How other share sheets are presented in the app (the UIKit UIActivityViewController presentation pattern)
- The system icon names — "seal" may not exist; may need "circle.circle" or custom icon

Localization keys "Seal", "Etegami", "Share Journey" need to be added to the `.lproj` files if the app uses localization.

- [ ] **Step 2: Add to Xcode project**
- [ ] **Step 3: Build to verify**
- [ ] **Step 4: Commit**

```
feat: add WalkSharingButtons component with Seal, Etegami, and Journey tiers
```

---

## Task 3: Integrate Seal Reveal into Walk Completion

**Files:**
- Modify: `Pilgrim/Scenes/Root/MainCoordinatorView.swift`
- Modify: `Pilgrim/Scenes/Root/MainTabView.swift`

Insert the seal reveal overlay between walk dismissal and summary presentation.

- [ ] **Step 1: Read current MainCoordinatorView.swift and MainTabView.swift**

Understand the exact state flow:
```
onWalkCompleted → saves walk → sets pendingSnapshot → nils activeWalkViewModel
→ fullScreenCover dismisses → handleActiveWalkDismiss() → moves pendingSnapshot to completedSnapshot
→ .sheet presents WalkSummaryView
```

- [ ] **Step 2: Add seal reveal state to MainCoordinator**

In `MainCoordinatorView.swift`, add to `MainCoordinator`:

```swift
@Published var showSealReveal = false
@Published var sealRevealWalk: TempWalk?
```

Modify `handleActiveWalkDismiss()` to show the seal reveal instead of immediately presenting the summary:

```swift
func handleActiveWalkDismiss() {
    if let snapshot = pendingSnapshot {
        sealRevealWalk = snapshot
        showSealReveal = true
        pendingSnapshot = nil
    } else {
        // ... existing cleanup
    }
}

func handleSealRevealDismiss() {
    showSealReveal = false
    if let walk = sealRevealWalk {
        completedSnapshot = walk
        sealRevealWalk = nil
    }
}
```

- [ ] **Step 3: Add seal reveal overlay to MainTabView**

In `MainTabView.swift`, add an overlay for the seal reveal (after the existing sheet):

```swift
.overlay {
    if coordinator.showSealReveal, let walk = coordinator.sealRevealWalk {
        SealRevealView(
            walk: walk,
            onDismiss: { coordinator.handleSealRevealDismiss() },
            onShareSeal: { image in
                coordinator.handleSealRevealDismiss()
                // Present share sheet with image
            }
        )
        .transition(.opacity)
        .zIndex(100)
    }
}
```

- [ ] **Step 4: Build and test manually**

Run the app in simulator, complete a walk, and verify:
1. After walk ends, seal reveal appears (not the summary directly)
2. Seal animates in with press effect
3. Tapping the seal opens share sheet
4. Tapping background or waiting dismisses to summary
5. Summary view appears after dismiss

- [ ] **Step 5: Run all tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

- [ ] **Step 6: Commit**

```
feat: integrate seal reveal into walk completion flow
```

---

## Task 4: Replace Share Button in WalkSummaryView

**Files:**
- Modify: `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift`

Replace the existing `shareCard` (lines 738-763) with `WalkSharingButtons`.

- [ ] **Step 1: Read the current shareCard implementation**

Lines 738-763 in WalkSummaryView.swift. Also check if `showShareSheet` state is used elsewhere.

- [ ] **Step 2: Replace shareCard with WalkSharingButtons**

Remove or replace the `shareCard` property with:
```swift
WalkSharingButtons(walk: walk)
```

Remove the `@State private var showShareSheet` and the `.sheet(isPresented: $showShareSheet)` that presents `WalkShareView` — this is now handled inside `WalkSharingButtons`.

- [ ] **Step 3: Build and verify**
- [ ] **Step 4: Run all tests**
- [ ] **Step 5: Commit**

```
feat: replace share button with three-tier WalkSharingButtons in WalkSummaryView
```

---

## Completion Checklist

- [ ] Seal reveal appears after walk completion with wax stamp animation
- [ ] Haptic feedback on stamp press
- [ ] Auto-dismiss after ~2.5 seconds
- [ ] Tap seal → share sheet with seal image
- [ ] Tap background → dismiss to summary
- [ ] WalkSummaryView shows Seal + Etegami buttons (instant share) above divider
- [ ] Journey button below divider opens existing WalkShareView
- [ ] `walk.pilgrimapp.org` caption on Journey button
- [ ] Seal reveal properly cleaned up (Task cancelled on dismiss)
- [ ] All existing tests still pass
- [ ] No resource leaks (timers, subscriptions)
