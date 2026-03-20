import SwiftUI

struct GoshuinFAB: View {

    let latestWalk: Walk?
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
