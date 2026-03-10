import SwiftUI

struct ProgressView: View {

    var progress: Int
    let total: Int

    var body: some View {
        HStack(spacing: Constants.UI.Padding.small) {
            ForEach(0..<total, id: \.self) { index in
                Rectangle()
                    .foregroundColor(index > progress ? .parchmentTertiary : .stone)
                    .frame(height: 2)
                    .clipShape(Capsule())
                    .animation(.default, value: progress)
            }
        }
    }
}
