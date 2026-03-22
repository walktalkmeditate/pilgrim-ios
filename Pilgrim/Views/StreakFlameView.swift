import SwiftUI

struct StreakFlameView: View {

    let days: Int

    @State private var flicker1 = false
    @State private var flicker2 = false

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Image(systemName: "flame.fill")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 12))
                    .foregroundColor(.rust.opacity(0.5))
                    .scaleEffect(flicker1 ? 1.15 : 0.9)
                    .opacity(flicker1 ? 0.6 : 0.3)

                Image(systemName: "flame.fill")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 12))
                    .foregroundColor(.rust)
                    .scaleEffect(flicker2 ? 1.05 : 0.95)
                    .opacity(flicker2 ? 1.0 : 0.7)
            }

            Text("\(days) days, the path unbroken")
                .font(Constants.Typography.caption)
                .foregroundColor(.stone)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                flicker1 = true
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                flicker2 = true
            }
        }
    }
}
