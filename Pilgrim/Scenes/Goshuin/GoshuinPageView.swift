import SwiftUI

struct GoshuinPageView: View {

    let walks: [WalkInterface]
    let allWalks: [WalkInterface]
    let totalWalkCount: Int
    let globalStartIndex: Int
    let arrivalCounts: [UUID: Int]
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
        // Bottom padding gives the TabView page-indicator dots room
        // to breathe — without this they sit flush against the card.
        .padding(.bottom, Constants.UI.Padding.big)
    }

    private func sealCell(walk: WalkInterface, walkIndex: Int) -> some View {
        let milestones = GoshuinMilestones.detect(
            walkCount: totalWalkCount,
            walkIndex: walkIndex,
            walk: walk,
            allWalks: allWalks,
            arrivalCounts: arrivalCounts
        )
        let isMilestone = !milestones.isEmpty
        let isArchived = walk.uuid.map { UserPreferences.isArchivedWalk(uuid: $0) } ?? false

        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color.ink.opacity(0.04))
                    .frame(width: 132, height: 132)

                if isMilestone && !isArchived {
                    Circle()
                        .stroke(Color.dawn.opacity(0.5), lineWidth: 2)
                        .frame(width: 136, height: 136)
                }

                SealThumbnailView(walk: walk)
                    .opacity(isArchived ? 0.45 : 1.0)
            }
            .onTapGesture {
                guard !isArchived, let uuid = walk.uuid else { return }
                onSelectWalk(uuid)
            }

            if isArchived {
                Text("Archived")
                    .font(Constants.Typography.caption)
                    .foregroundStyle(Color.fog.opacity(0.7))
            } else if let milestone = GoshuinMilestones.primaryMilestone(of: milestones) {
                Text(GoshuinMilestones.label(for: milestone))
                    .font(Constants.Typography.caption)
                    .foregroundStyle(Color.fog)
            }
        }
    }

    @ViewBuilder
    private var parchmentBackground: some View {
        // In constellation mode, use parchmentSecondary (#141228 cool indigo)
        // so the card reads as a distinct surface against the deeper #0a0a12
        // canvas. The earth-toned dawn patina is suppressed in this mode —
        // it warms the card brown which clashes with the starlit palette.
        if UserPreferences.appearanceMode.value == "constellation" {
            Color.parchmentSecondary
        } else {
            Color.parchment.overlay(patinaColor)
        }
    }

}

private struct SealThumbnailView: View {
    let walk: WalkInterface
    @State private var thumbnail: UIImage?

    init(walk: WalkInterface) {
        self.walk = walk
        // Render an already-cached thumbnail on the first frame — no
        // placeholder flash, and no work when the pager recreates the page.
        // Memory-only, so no disk I/O on the main thread during construction.
        let uuid = walk.uuid?.uuidString
        _thumbnail = State(initialValue: uuid.flatMap { SealCache.shared.memoryThumbnail(for: $0) })
    }

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .frame(width: 128, height: 128)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.fog.opacity(0.2))
                    .frame(width: 128, height: 128)
            }
        }
        .task { await loadIfNeeded() }
    }

    private func loadIfNeeded() async {
        guard thumbnail == nil, let uuid = walk.uuid?.uuidString else { return }
        // Look the thumbnail up by id first (off the main thread). Only on a
        // genuine cache miss do we build `SealInput`, which faults and maps the
        // entire route — so a cached thumbnail never pays that main-thread cost,
        // even when the pager recreates the page and resets `@State`.
        if let cached = await Task.detached(priority: .utility, operation: {
            SealCache.shared.thumbnail(for: uuid)
        }).value {
            thumbnail = cached
            return
        }
        let input = SealInput(walk: walk)
        let thumb = await Task.detached(priority: .utility) {
            SealGenerator.thumbnail(from: input)
        }.value
        thumbnail = thumb
    }
}

extension GoshuinPageView {
    private var patinaColor: Color {
        switch totalWalkCount {
        case 0...10:  return Color.clear
        case 11...30: return Color.dawn.opacity(0.03)
        case 31...70: return Color.dawn.opacity(0.07)
        default:      return Color.dawn.opacity(0.12)
        }
    }
}
