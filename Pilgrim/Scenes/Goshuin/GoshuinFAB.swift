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
