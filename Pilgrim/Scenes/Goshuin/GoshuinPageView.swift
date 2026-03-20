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

                if let uuid = walk.uuid?.uuidString,
                   let thumb = SealCache.shared.thumbnail(for: uuid) {
                    Image(uiImage: thumb)
                        .resizable()
                        .frame(width: 128, height: 128)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.fog.opacity(0.2))
                        .frame(width: 128, height: 128)
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

    private var parchmentBackground: some View {
        let patina = patinaColor
        return Color.parchment.overlay(patina)
    }

    private var patinaColor: Color {
        switch totalWalkCount {
        case 0...10:  return Color.clear
        case 11...30: return Color.dawn.opacity(0.03)
        case 31...70: return Color.dawn.opacity(0.07)
        default:      return Color.dawn.opacity(0.12)
        }
    }
}
