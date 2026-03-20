# Goshuin Collection View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a goshuin (御朱印帳) collection view to the Pilgrim Log — an accordion-fold book of walk seals with mark filters, milestone detection, and aging patina.

**Architecture:** A floating action button (FAB) on HomeView overlays the Pilgrim Log, showing the most recent seal. Tapping it opens a sheet containing `GoshuinView` — a horizontal-paging accordion book. Each page holds 4-6 seal thumbnails on parchment. Mark filter toggles at top. Milestone seals get a decorative border + caption. The parchment ages with walk count.

**Tech Stack:** SwiftUI, SealGenerator/SealCache (existing)

**Spec:** `docs/superpowers/specs/2026-03-19-seal-etegami-goshuin-design.md` (Section 5: Goshuin)

**Depends on:** Seal Generation (complete)

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `Pilgrim/Scenes/Goshuin/GoshuinFAB.swift` | Floating button showing latest seal thumbnail |
| `Pilgrim/Scenes/Goshuin/GoshuinView.swift` | Accordion book container with filters and share |
| `Pilgrim/Scenes/Goshuin/GoshuinPageView.swift` | Single parchment page with 4-6 seals |
| `Pilgrim/Scenes/Goshuin/GoshuinMilestones.swift` | Milestone detection logic |
| `UnitTests/GoshuinMilestonesTests.swift` | Milestone detection tests |

### Modified Files
| File | Change |
|------|--------|
| `Pilgrim/Scenes/Home/HomeView.swift` | Add FAB overlay + goshuin sheet |

---

## Task 1: Milestone Detection

**Files:**
- Create: `Pilgrim/Scenes/Goshuin/GoshuinMilestones.swift`
- Create: `UnitTests/GoshuinMilestonesTests.swift`

Pure logic — no UI. Determines which walks are milestones.

- [ ] **Step 1: Write tests**

```swift
import XCTest
@testable import Pilgrim

final class GoshuinMilestonesTests: XCTestCase {

    func testFirstWalk_isMilestone() {
        let milestones = GoshuinMilestones.detect(walkCount: 1, walkIndex: 0, walk: nil, allWalks: [])
        XCTAssertTrue(milestones.contains(.firstWalk))
    }

    func testEveryTenth_isMilestone() {
        let m10 = GoshuinMilestones.detect(walkCount: 10, walkIndex: 9, walk: nil, allWalks: [])
        XCTAssertTrue(m10.contains(.nthWalk(10)))

        let m20 = GoshuinMilestones.detect(walkCount: 20, walkIndex: 19, walk: nil, allWalks: [])
        XCTAssertTrue(m20.contains(.nthWalk(20)))
    }

    func testNonMilestone_isEmpty() {
        let m = GoshuinMilestones.detect(walkCount: 7, walkIndex: 6, walk: nil, allWalks: [])
        XCTAssertTrue(m.isEmpty)
    }
}
```

- [ ] **Step 2: Write implementation**

```swift
import Foundation

enum GoshuinMilestones {

    enum Milestone: Equatable, Hashable {
        case firstWalk
        case nthWalk(Int)
        case longestWalk
        case longestMeditation
        case firstOfSeason(String)
    }

    static func detect(
        walkCount: Int,
        walkIndex: Int,
        walk: WalkInterface?,
        allWalks: [WalkInterface]
    ) -> Set<Milestone> {
        var milestones: Set<Milestone> = []
        let walkNumber = walkIndex + 1

        if walkNumber == 1 {
            milestones.insert(.firstWalk)
        }

        if walkNumber % 10 == 0 {
            milestones.insert(.nthWalk(walkNumber))
        }

        guard let walk = walk, !allWalks.isEmpty else { return milestones }

        if let longest = allWalks.max(by: { $0.distance < $1.distance }),
           let walkUUID = walk.uuid, let longestUUID = longest.uuid,
           walkUUID == longestUUID {
            milestones.insert(.longestWalk)
        }

        if let longestMed = allWalks.filter({ $0.meditateDuration > 0 })
            .max(by: { $0.meditateDuration < $1.meditateDuration }),
           let walkUUID = walk.uuid, let medUUID = longestMed.uuid,
           walkUUID == medUUID {
            milestones.insert(.longestMeditation)
        }

        let calendar = Calendar.current
        let walkMonth = calendar.component(.month, from: walk.startDate)
        let walkYear = calendar.component(.year, from: walk.startDate)
        let latitude = walk.routeData.first?.latitude ?? 0
        let season = SealTimeHelpers.season(for: walk.startDate, latitude: latitude)

        let isFirstOfSeason = !allWalks.contains { other in
            guard let otherUUID = other.uuid, let walkUUID = walk.uuid,
                  otherUUID != walkUUID,
                  other.startDate < walk.startDate else { return false }
            let otherLat = other.routeData.first?.latitude ?? 0
            let otherSeason = SealTimeHelpers.season(for: other.startDate, latitude: otherLat)
            let otherYear = calendar.component(.year, from: other.startDate)
            return otherSeason == season && otherYear == walkYear
        }

        if isFirstOfSeason {
            milestones.insert(.firstOfSeason(season))
        }

        return milestones
    }

    static func label(for milestone: Milestone) -> String {
        switch milestone {
        case .firstWalk: return "First Walk"
        case .nthWalk(let n): return "\(n)th Walk"
        case .longestWalk: return "Longest Walk"
        case .longestMeditation: return "Longest Meditation"
        case .firstOfSeason(let s): return "First of \(s)"
        }
    }
}
```

- [ ] **Step 3: Run tests, verify pass**
- [ ] **Step 4: Commit**

```
feat(goshuin): add milestone detection logic
```

---

## Task 2: Goshuin Page View

**Files:**
- Create: `Pilgrim/Scenes/Goshuin/GoshuinPageView.swift`

A single page of the accordion book — parchment card with 4-6 seal thumbnails.

- [ ] **Step 1: Write implementation**

```swift
import SwiftUI

struct GoshuinPageView: View {

    let walks: [WalkInterface]
    let allWalks: [WalkInterface]
    let totalWalkCount: Int
    let globalStartIndex: Int
    let onSelectWalk: (UUID) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(Array(walks.enumerated()), id: \.offset) { offset, walk in
                sealCell(walk: walk, walkIndex: globalStartIndex + offset)
            }
        }
        .padding(Constants.UI.Padding.normal)
        .background(parchmentBackground)
        .cornerRadius(Constants.UI.CornerRadius.normal)
    }

    private func sealCell(walk: WalkInterface, walkIndex: Int) -> some View {
        let milestones = GoshuinMilestones.detect(
            walkCount: totalWalkCount,
            walkIndex: walkIndex,
            walk: walk,
            allWalks: allWalks
        )
        let isMilestone = !milestones.isEmpty

        return VStack(spacing: 4) {
            ZStack {
                if isMilestone {
                    Circle()
                        .stroke(Color.dawn.opacity(0.5), lineWidth: 2)
                        .frame(width: 136, height: 136)
                }

                if let thumb = SealCache.shared.thumbnail(for: walk.uuid?.uuidString ?? "") {
                    Image(uiImage: thumb)
                        .resizable()
                        .frame(width: 128, height: 128)
                        .clipShape(Circle())
                } else {
                    sealPlaceholder
                }
            }
            .onTapGesture {
                if let uuid = walk.uuid { onSelectWalk(uuid) }
            }

            if let milestone = milestones.first {
                Text(GoshuinMilestones.label(for: milestone))
                    .font(Constants.Typography.caption)
                    .foregroundStyle(Color.fog)
            }
        }
    }

    private var sealPlaceholder: some View {
        Circle()
            .fill(Color.fog.opacity(0.2))
            .frame(width: 128, height: 128)
            .onAppear {
                // Trigger lazy seal generation for walks not yet cached
            }
    }

    private var parchmentBackground: some View {
        let patina = GoshuinPageView.patinaColor(for: totalWalkCount)
        return Color.parchment.overlay(patina)
    }

    static func patinaColor(for walkCount: Int) -> Color {
        switch walkCount {
        case 0...10:  return Color.clear
        case 11...30: return Color.dawn.opacity(0.03)
        case 31...70: return Color.dawn.opacity(0.07)
        default:      return Color.dawn.opacity(0.12)
        }
    }
}
```

- [ ] **Step 2: Build to verify**
- [ ] **Step 3: Commit**

```
feat(goshuin): add GoshuinPageView with parchment aging and milestone borders
```

---

## Task 3: Goshuin View (Accordion Book)

**Files:**
- Create: `Pilgrim/Scenes/Goshuin/GoshuinView.swift`

The main goshuin container — horizontal paging with mark filters.

- [ ] **Step 1: Write implementation**

```swift
import SwiftUI

struct GoshuinView: View {

    let walks: [WalkInterface]
    let onSelectWalk: (UUID) -> Void

    @State private var activeFilter: WalkFavicon?
    @State private var shareImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    private var filteredWalks: [WalkInterface] {
        guard let filter = activeFilter else { return walks }
        return walks.filter { WalkFavicon(rawValue: $0.favicon ?? "") == filter }
    }

    private var pages: [[WalkInterface]] {
        stride(from: 0, to: filteredWalks.count, by: 6).map { start in
            Array(filteredWalks[start..<min(start + 6, filteredWalks.count)])
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                bookContent
                shareButton
            }
            .background(Color.parchment)
            .navigationTitle("Goshuin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Constants.Typography.button)
                }
            }
            .sheet(item: $shareImage) { image in
                ShareSheet(items: [image])
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: Constants.UI.Padding.small) {
            filterToggle(nil, label: "All")
            ForEach(WalkFavicon.allCases, id: \.self) { fav in
                filterToggle(fav, label: fav.label)
            }
        }
        .padding(.horizontal, Constants.UI.Padding.normal)
        .padding(.vertical, Constants.UI.Padding.small)
    }

    private func filterToggle(_ favicon: WalkFavicon?, label: String) -> some View {
        let isActive = activeFilter == favicon
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                activeFilter = favicon
            }
        } label: {
            HStack(spacing: 4) {
                if let fav = favicon {
                    Image(systemName: fav.icon)
                        .font(.system(size: 12))
                }
                Text(label)
                    .font(Constants.Typography.caption)
            }
            .padding(.horizontal, Constants.UI.Padding.small)
            .padding(.vertical, 6)
            .background(isActive ? Color.stone.opacity(0.15) : Color.clear)
            .cornerRadius(12)
            .foregroundStyle(isActive ? Color.stone : Color.fog)
        }
    }

    // MARK: - Book Content

    private var bookContent: some View {
        Group {
            if pages.isEmpty {
                emptyState
            } else {
                TabView {
                    ForEach(Array(pages.enumerated()), id: \.offset) { pageIndex, pageWalks in
                        GoshuinPageView(
                            walks: pageWalks,
                            allWalks: walks,
                            totalWalkCount: walks.count,
                            globalStartIndex: pageIndex * 6,
                            onSelectWalk: { uuid in
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    onSelectWalk(uuid)
                                }
                            }
                        )
                        .padding(.horizontal, Constants.UI.Padding.normal)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: Constants.UI.Padding.normal) {
            Image(systemName: "seal")
                .font(.system(size: 40))
                .foregroundStyle(Color.fog.opacity(0.4))
            Text("Your goshuin will fill as you walk")
                .font(Constants.Typography.body)
                .foregroundStyle(Color.fog)
        }
    }

    // MARK: - Share

    private var shareButton: some View {
        Button {
            shareCurrentPage()
        } label: {
            Text("Share Goshuin")
                .font(Constants.Typography.button)
                .foregroundStyle(Color.stone)
                .padding(.vertical, Constants.UI.Padding.small)
                .frame(maxWidth: .infinity)
        }
        .padding(Constants.UI.Padding.normal)
        .opacity(pages.isEmpty ? 0 : 1)
    }

    private func shareCurrentPage() {
        // Render current page as image — simplified: render all filtered seals in a grid
        let size = CGSize(width: 1080, height: 1080)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor(Color.parchment).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let seals = Array(filteredWalks.prefix(36))
            let cols = 6
            let cellSize: CGFloat = 150
            let padding: CGFloat = (size.width - CGFloat(cols) * cellSize) / CGFloat(cols + 1)

            for (i, walk) in seals.enumerated() {
                let col = i % cols
                let row = i / cols
                let x = padding + CGFloat(col) * (cellSize + padding)
                let y = padding + CGFloat(row) * (cellSize + padding)

                if let thumb = SealCache.shared.thumbnail(for: walk.uuid?.uuidString ?? "") {
                    thumb.draw(in: CGRect(x: x, y: y, width: cellSize, height: cellSize))
                }
            }
        }
        shareImage = image
    }
}
```

**IMPORTANT:** Before writing, verify:
- `WalkFavicon.allCases` works (it's `CaseIterable`)
- `WalkFavicon.icon` returns SF Symbol name strings
- `ShareSheet` (the UIViewControllerRepresentable) is accessible
- How `TabView` with `.page` style works for horizontal swiping

- [ ] **Step 2: Build to verify**
- [ ] **Step 3: Commit**

```
feat(goshuin): add GoshuinView accordion book with mark filters and share
```

---

## Task 4: Goshuin FAB

**Files:**
- Create: `Pilgrim/Scenes/Goshuin/GoshuinFAB.swift`

Floating button showing the latest seal thumbnail.

- [ ] **Step 1: Write implementation**

```swift
import SwiftUI

struct GoshuinFAB: View {

    let latestWalk: WalkInterface?
    let action: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.parchmentSecondary)
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "seal")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.stone)
                }
            }
        }
        .onAppear { loadThumbnail() }
    }

    private func loadThumbnail() {
        guard let walk = latestWalk else { return }
        Task.detached(priority: .background) {
            let thumb = SealGenerator.thumbnail(for: walk)
            await MainActor.run { thumbnail = thumb }
        }
    }
}
```

- [ ] **Step 2: Build to verify**
- [ ] **Step 3: Commit**

```
feat(goshuin): add GoshuinFAB floating button with latest seal thumbnail
```

---

## Task 5: Integrate FAB + Goshuin into HomeView

**Files:**
- Modify: `Pilgrim/Scenes/Home/HomeView.swift`

- [ ] **Step 1: Read HomeView.swift**

Understand the current layout and where to add the overlay.

- [ ] **Step 2: Add FAB overlay and goshuin sheet**

Add state:
```swift
@State private var showGoshuin = false
```

Add overlay to the main content (after existing modifiers):
```swift
.overlay(alignment: .bottomTrailing) {
    if !viewModel.walks.isEmpty {
        GoshuinFAB(
            latestWalk: viewModel.walks.first,
            action: { showGoshuin = true }
        )
        .padding(.trailing, Constants.UI.Padding.normal)
        .padding(.bottom, Constants.UI.Padding.big)
    }
}
.sheet(isPresented: $showGoshuin) {
    GoshuinView(
        walks: viewModel.walks,
        onSelectWalk: { uuid in
            selectedWalk = viewModel.walk(for: uuid)
        }
    )
}
```

- [ ] **Step 3: Build and run all tests**
- [ ] **Step 4: Commit**

```
feat(goshuin): integrate FAB and goshuin view into Pilgrim Log
```

---

## Completion Checklist

- [ ] FAB appears bottom-right of Pilgrim Log when walks exist
- [ ] FAB shows latest seal thumbnail (async loaded)
- [ ] FAB placeholder icon shown while seal renders
- [ ] Tapping FAB opens goshuin sheet
- [ ] Goshuin shows horizontal-paging accordion book
- [ ] Each page holds up to 6 seals in a 2-column grid
- [ ] Mark filter toggles (All / Transformative / Peaceful / Extraordinary)
- [ ] Filtering shows only matching walks; color clustering visible
- [ ] Milestone seals have decorative border ring
- [ ] Milestone caption shown below seal ("First Walk", "10th Walk", etc.)
- [ ] Book parchment ages with walk count (4 tiers)
- [ ] Tapping a seal navigates to walk detail
- [ ] "Share Goshuin" renders grid as image
- [ ] Empty state shown when no walks match filter
- [ ] All existing tests pass
- [ ] No resource leaks
