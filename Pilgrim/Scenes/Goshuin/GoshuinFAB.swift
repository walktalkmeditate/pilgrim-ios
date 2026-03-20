import SwiftUI

struct GoshuinFAB: View {

    let latestWalk: Walk?
    let action: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.parchmentTertiary)
                    .frame(width: 56, height: 56)
                    .overlay(Circle().stroke(Color.stone.opacity(0.3), lineWidth: 1))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 5)

                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "seal")
                        .font(Constants.Typography.statValue)
                        .foregroundStyle(Color.stone)
                }
            }
        }
        .accessibilityIdentifier("goshuin_fab")
        .task { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        guard let walk = latestWalk else { return }
        let input = SealInput(walk: walk)
        let thumb = await Task.detached(priority: .background) {
            SealGenerator.thumbnail(from: input)
        }.value
        thumbnail = thumb
    }
}
